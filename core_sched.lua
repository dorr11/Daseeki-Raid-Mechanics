--[[
    Daseeki Raid Mechanics 2.0 — scheduler (engine core, wave 1)

    ENGINE SPEC §3, implemented rule for rule:
      §3.1  ONE frame-driven scheduler, NOT C_Timer. A single hidden frame carries
            an OnUpdate that runs the whole engine's deferred work. Tasks live in a
            min-heap keyed on ABSOLUTE time. Each frame drains EVERY task whose due
            time is <= now — no per-frame budget, no one-task-per-frame pacing.
            Drift correction is inherent: due times are absolute timestamps computed
            at schedule time, so a slow frame delays execution but never accumulates
            error. Looping timers re-derive from the same absolute base each iteration.
            The frame HIDES AND DETACHES its update script when the heap is empty and
            no per-frame handler is registered, so idle cost outside encounters is zero.
      §3.2  A stack of up to 8 recycled task tables; a completed task's table is
            pushed back only if it has 4 or fewer arguments. Strong references, no
            weak table. Cancellation matches on (function, owner, first N arguments)
            with PARTIAL matching — fewer arguments cancels every task whose leading
            arguments match.
      §3.3  Per-module update handlers with an interval accumulator, skippable by a
            zone gate.
      §3.4  Countdown / fixed loop / interval-table loop / delayed-call primitives.
      §3.5  A 20 s housekeeping pass on the same loop.

    HEADLESS DISCIPLINE (house rule): the clock is INJECTABLE (`Sched:SetClock`) and
    the drain is drivable by hand (`Sched:Tick(now)`), so the harness runs the REAL
    scheduler on a fake frame clock. The drain carries an ITERATION CEILING; hitting
    it writes to the telemetry ring rather than freezing a raid frame.
--]]

local _, Addon = ...

local Heap = Addon.Heap

local Sched = {}
Addon.Sched = Sched

-- ── Constants (ENGINE SPEC §3.2, §3.4, §3.5, §12) ─────────────────────────────
Sched.POOL_MAX            = 8      -- recycled task tables kept
Sched.POOL_MAX_ARGS       = 4      -- tasks with more args allocate fresh
Sched.MAX_ARGS            = 8      -- hard cap on arguments a task may carry
Sched.MAX_DRAIN_PER_TICK  = 512    -- headless/raid-frame safety ceiling
Sched.HOUSEKEEP_INTERVAL  = 20     -- §3.5
Sched.COUNTDOWN_TIME      = 5      -- §3.4 default `time`
Sched.COUNTDOWN_ANNOUNCES = 3      -- §3.4 default `numAnnounces`
Sched.LOOP_TABLE_KICK     = 0.0001 -- §3.4 timer-flavoured loops fire the first entry instantly

Sched.heap     = Heap.New()
Sched.pool     = {}
Sched.updaters = {}                -- owner -> { interval, fn, acc, zoneGate }
Sched.housekeepers = {}            -- ordered { fn, owner }
Sched.awake    = false
Sched.frame    = nil
Sched.stats    = { drained = 0, allocated = 0, recycled = 0, overflow = 0, cancelled = 0 }

-- ── Clock (injectable — this is what makes the engine headless-drivable) ───────
local function realTime()
    local f = _G.GetTime
    if type(f) == "function" then return f() end
    return os.clock()
end
Sched.clock = realTime

function Sched:SetClock(fn) self.clock = fn or realTime end
function Sched:Now() return self.clock() end

-- ── Task tables (§3.2 allocation discipline) ──────────────────────────────────
local function acquire(self)
    local p = self.pool
    local k = #p
    if k > 0 then
        local t = p[k]
        p[k] = nil
        self.stats.recycled = self.stats.recycled + 1
        return t
    end
    self.stats.allocated = self.stats.allocated + 1
    return {}
end

-- Returns true when the table went back on the stack. Deliberately STRONG
-- references (no weak table) to avoid GC churn — spec §3.2.
local function release(self, t)
    if (t.n or 0) > self.POOL_MAX_ARGS then return false end
    if #self.pool >= self.POOL_MAX then return false end
    for i = 1, (t.n or 0) do t[i] = nil end
    t.at, t.fn, t.owner, t.n, t.seq, t.tag = nil, nil, nil, nil, nil, nil
    self.pool[#self.pool + 1] = t
    return true
end

-- ── Scheduling ────────────────────────────────────────────────────────────────
-- Absolute-time insert. Everything else funnels through here, which is why drift
-- cannot accumulate: the due time is a timestamp, never a countdown.
function Sched:ScheduleAt(at, fn, owner, ...)
    local n = select("#", ...)
    if n > self.MAX_ARGS then n = self.MAX_ARGS end
    local t = acquire(self)
    t.at, t.fn, t.owner, t.n = at, fn, owner, n
    for i = 1, n do t[i] = (select(i, ...)) end
    self.heap:Push(t)
    self:Wake()
    return t
end

function Sched:Schedule(delay, fn, owner, ...)
    return self:ScheduleAt(self:Now() + (delay or 0), fn, owner, ...)
end

-- §3.2 PARTIAL matching: nil fn matches any function, nil owner matches any owner,
-- and supplying fewer arguments cancels every task whose LEADING arguments match.
local function matches(t, fn, owner, argc, a1, a2, a3, a4, a5, a6, a7, a8)
    if fn ~= nil and t.fn ~= fn then return false end
    if owner ~= nil and t.owner ~= owner then return false end
    if argc >= 1 and t[1] ~= a1 then return false end
    if argc >= 2 and t[2] ~= a2 then return false end
    if argc >= 3 and t[3] ~= a3 then return false end
    if argc >= 4 and t[4] ~= a4 then return false end
    if argc >= 5 and t[5] ~= a5 then return false end
    if argc >= 6 and t[6] ~= a6 then return false end
    if argc >= 7 and t[7] ~= a7 then return false end
    if argc >= 8 and t[8] ~= a8 then return false end
    return true
end

function Sched:Unschedule(fn, owner, ...)
    local argc = select("#", ...)
    local a1, a2, a3, a4, a5, a6, a7, a8 = ...
    local sink = {}
    local removed = self.heap:RemoveWhere(function(t)
        return matches(t, fn, owner, argc, a1, a2, a3, a4, a5, a6, a7, a8)
    end, sink)
    for i = 1, #sink do release(self, sink[i]) end
    self.stats.cancelled = self.stats.cancelled + removed
    self:MaybeSleep()
    return removed
end

function Sched:IsScheduled(fn, owner, ...)
    local argc = select("#", ...)
    local a1, a2, a3, a4, a5, a6, a7, a8 = ...
    local h = self.heap
    for i = 1, h.n do
        if matches(h[i], fn, owner, argc, a1, a2, a3, a4, a5, a6, a7, a8) then return true end
    end
    return false
end

function Sched:CancelOwner(owner)
    return self:Unschedule(nil, owner)
end

function Sched:Count() return self.heap:Count() end

-- Shift every queued task's ABSOLUTE due time by a constant.
--
-- This exists for exactly one caller: the testing suite's compressed playback
-- (ui_testing.lua), which runs the encounter's own scheduled script on a TIME-SCALED
-- clock and must hand the real clock back afterwards without moving anything. The
-- scaled clock is continuous at the moment it is installed but has run AHEAD by the
-- time it is removed, so restoring the real clock would otherwise make every
-- surviving task's delay jump. Rebasing by (realNow - scaledNow) preserves every
-- remaining task's RELATIVE delay exactly across the swap.
--
-- The heap invariant survives untouched because a CONSTANT shift cannot reorder a
-- strict min on `at` (nor the insertion-sequence tie-break), so this is an O(n) walk
-- with no re-heapify. It is deliberately NOT part of the live path — nothing in the
-- engine calls it, and the harness asserts that.
function Sched:Rebase(delta)
    delta = tonumber(delta)
    if not delta or delta == 0 then return 0 end
    local h = self.heap
    for i = 1, h.n do h[i].at = h[i].at + delta end
    return h.n
end

-- ENGINE SPEC §9.4: the hard-disable path flushes the scheduler.
function Sched:Flush()
    local sink = {}
    local n = self.heap:Clear(sink)
    for i = 1, #sink do release(self, sink[i]) end
    for k in pairs(self.updaters) do self.updaters[k] = nil end
    for i = #self.housekeepers, 1, -1 do self.housekeepers[i] = nil end
    self.housekeeping = nil
    self:MaybeSleep()
    return n
end

-- ── The drain (§3.1) ──────────────────────────────────────────────────────────
-- Drains EVERY task due at or before `now`, in heap order, in one pass. Tasks
-- scheduled during the drain that are also already due are drained in the same
-- pass — that is the spec's "batch of simultaneous expiries all fire in the same
-- frame". The ceiling is ours: a runaway zero-delay reschedule stops at
-- MAX_DRAIN_PER_TICK and lands in the telemetry ring instead of hanging the client.
function Sched:Tick(now)
    now = now or self:Now()
    local heap, drained = self.heap, 0
    while true do
        local top = heap:Peek()
        if not top or top.at > now then break end
        if drained >= self.MAX_DRAIN_PER_TICK then
            self.stats.overflow = self.stats.overflow + 1
            if Addon.Telemetry then
                Addon.Telemetry.Write("sched.overflow",
                    { queued = heap:Count(), ceiling = self.MAX_DRAIN_PER_TICK })
            end
            break
        end
        heap:Pop()
        drained = drained + 1
        local fn = top.fn
        local a1, a2, a3, a4, a5, a6, a7, a8 =
            top[1], top[2], top[3], top[4], top[5], top[6], top[7], top[8]
        release(self, top)      -- args are already copied out, so recycling here is safe
        if fn then fn(a1, a2, a3, a4, a5, a6, a7, a8) end
    end
    self.stats.drained = self.stats.drained + drained
    return drained
end

-- ── Per-module update handlers (§3.3) ─────────────────────────────────────────
function Sched:RegisterUpdate(owner, interval, fn, zoneGate)
    if owner == nil or type(fn) ~= "function" then return end
    self.updaters[owner] = { interval = interval or 0, fn = fn, acc = 0, zoneGate = zoneGate }
    self:Wake()
end

function Sched:UnregisterUpdate(owner)
    self.updaters[owner] = nil
    self:MaybeSleep()
end

function Sched:RunUpdaters(elapsed)
    elapsed = elapsed or 0
    for owner, u in pairs(self.updaters) do
        u.acc = u.acc + elapsed
        if u.acc >= u.interval then
            local acc = u.acc
            u.acc = 0
            if not u.zoneGate or u.zoneGate(owner) then u.fn(owner, acc) end
        end
    end
end

-- ── Housekeeping (§3.5) ───────────────────────────────────────────────────────
-- Runs ONLY while something is registered, so the "idle cost outside encounters
-- is zero" guarantee in §3.1 is not quietly broken by a permanent 20 s heartbeat.
local function housekeepTick()
    local self = Sched
    local list = self.housekeepers
    for i = 1, #list do
        local h = list[i]
        if h and h.fn then h.fn(h.owner) end
    end
    if #list > 0 then
        self.housekeeping = self:Schedule(self.HOUSEKEEP_INTERVAL, housekeepTick, self)
    else
        self.housekeeping = nil
    end
end

function Sched:AddHousekeeper(fn, owner)
    if type(fn) ~= "function" then return end
    self.housekeepers[#self.housekeepers + 1] = { fn = fn, owner = owner }
    if not self.housekeeping then
        self.housekeeping = self:Schedule(self.HOUSEKEEP_INTERVAL, housekeepTick, self)
    end
end

function Sched:RemoveHousekeeper(fn)
    local list = self.housekeepers
    for i = #list, 1, -1 do
        if list[i].fn == fn then table.remove(list, i) end
    end
    if #list == 0 and self.housekeeping then
        self:Unschedule(housekeepTick, self)
        self.housekeeping = nil
    end
end

-- ── Frame wake / idle self-hide (§3.1) ────────────────────────────────────────
function Sched:EnsureFrame()
    if self.frame ~= nil then return self.frame end
    if type(_G.CreateFrame) ~= "function" then
        self.frame = false          -- headless: remembered so we stop retrying
        return false
    end
    local f = _G.CreateFrame("Frame", nil, _G.UIParent)
    f:Hide()
    self.frame = f
    return f
end

function Sched:OnUpdate(elapsed)
    self:RunUpdaters(elapsed)
    self:Tick(self:Now())
    self:MaybeSleep()
end

function Sched:Wake()
    if self.awake then return end
    self.awake = true
    local f = self:EnsureFrame()
    if f then
        f:SetScript("OnUpdate", function(_, elapsed) Sched:OnUpdate(elapsed) end)
        f:Show()
    end
end

-- Heap empty AND no per-frame handler => detach the update script and hide.
function Sched:MaybeSleep()
    if not self.awake then return false end
    if self.heap:Count() > 0 then return false end
    if next(self.updaters) ~= nil then return false end
    self.awake = false
    local f = self.frame
    if f then
        f:SetScript("OnUpdate", nil)
        f:Hide()
    end
    return true
end

function Sched:IsAwake() return self.awake end

-- ── Higher-level primitives (§3.4) ────────────────────────────────────────────
-- Countdown: `numAnnounces` firings at time-1, time-2, …; anything landing under
-- 1 s is discarded. The callback receives the REMAINING count.
function Sched:Countdown(time, numAnnounces, fn, owner, ...)
    time = time or self.COUNTDOWN_TIME
    numAnnounces = numAnnounces or self.COUNTDOWN_ANNOUNCES
    local made = 0
    for i = 1, numAnnounces do
        local delay = time - i
        if delay >= 1 then
            self:Schedule(delay, fn, owner, i, ...)
            made = made + 1
        end
    end
    return made
end

-- Count OUT: 1, 2, 3 … upward (ENGINE SPEC §4.4, "a count of 0 means count out").
function Sched:CountOut(count, fn, owner, ...)
    local made = 0
    for i = 1, count do
        self:Schedule(i, fn, owner, i, ...)
        made = made + 1
    end
    return made
end

-- Fixed-interval loop. Re-derives every iteration from the SAME absolute base, so
-- a slow frame never accumulates error (§3.1). Runs until cancelled — cancellation
-- is the caller's responsibility (§3.4).
local function loopTick(state)
    if state.cancelled then return end
    state.i = state.i + 1
    state.fn(state.owner, state.i, unpack(state.args, 1, state.argn))
    if state.cancelled then return end
    Sched:ScheduleAt(state.base + (state.i + 1) * state.interval, loopTick, state.owner, state)
end

function Sched:Loop(interval, fn, owner, ...)
    local state = {
        interval = interval, fn = fn, owner = owner, i = 0,
        base = self:Now(), args = { ... }, argn = select("#", ...),
    }
    self:ScheduleAt(state.base + interval, loopTick, owner, state)
    return state
end

-- Interval-TABLE loop: walks a list of gaps, each firing scheduling the next. The
-- last gap repeats forever (that is how "4th+ = 35 s" cycles in the encounter data
-- are expressed). `immediate` fires entry 1 at once (the timer-flavoured variant,
-- so the bar appears instantly).
--
-- W4d EXTENSION — `gaps.repeatFrom`. "The last gap repeats forever" cannot express a
-- cycle whose TAIL alternates, which is the shape of every scripted two-state loop in
-- the encounters spec (Noth's room/balcony 35/55, Heigan's room/dance 88/47). With
-- `repeatFrom = n` the tail cycles gaps[n..#gaps] instead of repeating gaps[#gaps];
-- without it the old rule is unchanged.
function Sched.GapAt(gaps, i)
    local g = gaps[i]
    if g then return g end
    local rf = gaps.repeatFrom
    if not rf or rf < 1 or rf > #gaps then return gaps[#gaps] end
    local span = #gaps - rf + 1
    return gaps[rf + ((i - rf) % span)]
end

local function loopTableTick(state)
    if state.cancelled then return end
    state.i = state.i + 1
    state.fn(state.owner, state.i, unpack(state.args, 1, state.argn))
    if state.cancelled then return end
    local gap = Sched.GapAt(state.gaps, state.i + 1)
    if not gap then return end
    state.base = state.base + gap
    Sched:ScheduleAt(state.base, loopTableTick, state.owner, state)
end

function Sched:LoopTable(gaps, fn, owner, immediate, ...)
    local state = {
        gaps = gaps, fn = fn, owner = owner, i = 0,
        base = self:Now(), args = { ... }, argn = select("#", ...),
    }
    if immediate then
        state.base = state.base + self.LOOP_TABLE_KICK
    else
        state.base = state.base + (gaps[1] or 0)
    end
    self:ScheduleAt(state.base, loopTableTick, owner, state)
    return state
end

function Sched:CancelLoop(state)
    if type(state) ~= "table" then return false end
    state.cancelled = true
    self:Unschedule(loopTick, state.owner, state)
    self:Unschedule(loopTableTick, state.owner, state)
    return true
end

-- Delayed call: cancel-then-schedule, the cheap debounce (§3.4).
function Sched:DelayedCall(delay, fn, owner, ...)
    self:Unschedule(fn, owner, ...)
    return self:Schedule(delay, fn, owner, ...)
end

return Sched
