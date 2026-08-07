--[[
    Daseeki Raid Mechanics 2.0 — timer semantics + the early-refresh tripwire
    (engine core, wave 1)

    ENGINE SPEC §4.1 identity/de-duplication, §4.2 variance, §4.3 early-refresh
    detection, §4.4 countdown voice, §4.5 the external contract.

    THIS LAYER RENDERS NOTHING. It owns bar STATE and the rules that govern it, and
    publishes every transition on the engine dispatch seam. W2 draws bars off that
    seam. Keeping the semantics here — not in the HUD — is what makes them
    assertable headless, which is the whole reason the variance rules and the
    tripwire land in wave 1 rather than alongside the pixels.

    THE EARLY-REFRESH TRIPWIRE (§4.3) IS THE PRODUCT FEATURE. Every restart measures
    the bar it replaces. The reference engine raises a "please report this" chat
    line; we write the observation to the telemetry ring instead (design doc, target
    architecture item 3), so a season of Drew's raids produces a dataset that says
    which declared timer values are wrong, with numbers, and nobody is nagged.
--]]

local _, Addon = ...

local Timers = {}
Addon.Timers = Timers

Timers.EPSILON      = 0.2      -- §4.3 "|remaining| <= 0.2 s — silent (normal jitter)"
Timers.REPORT_AT    = 1.0      -- §4.3 "remaining > 1 s raises a user-visible warning"
Timers.COUNTDOWN_DEPTH = 4     -- §12 "Countdown default depth 4"
Timers.varianceDisplay = true  -- §4.2 default ON: bar runs to MAX and paints the window

Timers.objects = {}            -- timerId -> timer object
Timers.bars    = {}            -- barId   -> live bar record

local function Sched() return Addon.Sched end

-- ══════════════════════════════════════════════════════════════════════════════
--  §4.2 DURATION GRAMMAR
--     v<min>-<max>   variance window (decimals allowed)
--     d<n>           "allow double" on a plain numeric duration
--     dv<min>-<max>  both
-- ══════════════════════════════════════════════════════════════════════════════
local function plain(n, allowDouble)
    return { total = n, min = n, max = n, variance = 0,
             hasVariance = false, allowDouble = allowDouble or false }
end

function Timers.ParseDuration(v)
    if type(v) == "number" then return plain(v) end
    if type(v) ~= "string" then return nil end
    local s, allowDouble = v, false
    if s:sub(1, 2) == "dv" then
        allowDouble = true
        s = s:sub(2)
    elseif s:sub(1, 1) == "d" then
        local n = tonumber(s:sub(2))
        if not n then return nil end
        return plain(n, true)
    end
    if s:sub(1, 1) == "v" then
        local mn, mx = s:match("^v(%-?[%d%.]+)%-(%-?[%d%.]+)$")
        mn, mx = tonumber(mn), tonumber(mx)
        if not mn or not mx or mx < mn then return nil end
        return { total = mx, min = mn, max = mx, variance = mx - mn,
                 hasVariance = true, allowDouble = allowDouble }
    end
    local n = tonumber(s)
    if n then return plain(n, allowDouble) end
    return nil
end

-- §4.2: "A NEGATIVE start value (including negative zero) means 'this variance
-- window, shifted earlier by this delay' — the window is recomputed as
-- (min+delay)…(max+delay)."  Negative zero is a real value in Lua and must be
-- distinguished from plain zero, or a `-0` shift silently becomes "0 seconds".
function Timers.IsNegativeStart(v)
    if type(v) ~= "number" then return false end
    if v < 0 then return true end
    if v == 0 then return 1 / v == -math.huge end   -- negative zero
    return false
end

function Timers.ShiftWindow(dur, delay)
    return { total = dur.max + delay, min = dur.min + delay, max = dur.max + delay,
             variance = dur.variance, hasVariance = dur.hasVariance,
             allowDouble = dur.allowDouble, shifted = delay }
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §4.1 IDENTITY
--     A running bar's identity is timerObjectId + tab-joined stringified arguments.
--     Two starts with the same arguments address the same bar; a start on an
--     existing bar REPLACES it.
-- ══════════════════════════════════════════════════════════════════════════════
local Timer = {}
Timer.__index = Timer
Timers.Timer = Timer

function Timers.New(def)
    local t = setmetatable({}, Timer)
    t.id          = def.id
    t.key         = def.key or def.id
    t.encId       = def.encId
    t.kind        = def.kind or "cd"
    t.dur         = Timers.ParseDuration(def.duration)
    t.spellId     = def.spellId
    t.text        = def.text
    t.icon        = def.icon
    t.color       = def.color
    t.hasCount    = def.count and true or false
    t.allowDouble = def.allowDouble or (t.dur and t.dur.allowDouble) or false
    t.keep        = def.keep
    t.fade        = def.fade
    t.nameplate   = def.nameplate
    t.perTarget   = def.perTarget
    t.requiresCombat = def.requiresCombat
    t.countdown   = def.countdown
    t.owner       = def.owner
    t.live        = {}          -- barId -> true (§4.1 "timer objects keep their own list")
    Timers.objects[t.id] = t
    return t
end

function Timer:BarId(...)
    local n = select("#", ...)
    if n == 0 then return self.id end
    local parts = { self.id }
    for i = 1, n do parts[i + 1] = tostring((select(i, ...))) end
    return table.concat(parts, "\t")
end

-- §4.5: every timer collapses into one of seven simplified categories for external
-- consumers, with nameplate-only variants mapping to cdnp / castnp.
function Timer:Category()
    local base = (Addon.API and Addon.API.TIMER_KINDS and Addon.API.TIMER_KINDS[self.kind]) or "cd"
    if self.nameplate then
        if base == "cast" then return "castnp" end
        if base == "cd" then return "cdnp" end
    end
    return base
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §4.3 THE EARLY-REFRESH TRIPWIRE
-- ══════════════════════════════════════════════════════════════════════════════
-- Eligible on every start/restart of a NON-target, NON-active, NON-fade,
-- NON-learning timer.
function Timer:TripwireEligible()
    if self.kind == "target" or self.kind == "active" or self.kind == "learning" then return false end
    if self.fade then return false end
    return true
end

-- Classify a refresh. Pure: no side effects, so the harness can assert the whole
-- verdict table directly and the live path uses the same function.
--   |remaining| <= 0.2                       -> nil (silent jitter)
--   variance:  adj = remaining - variance
--                adj > 1.0                   -> "early"        (report level)
--                adj > 0.2                   -> "early_minor"  (debug level)
--                remaining < -0.2            -> "after_zero"   (report level)
--                otherwise                   -> nil (inside the declared window)
--   non-variance:
--                remaining > 1.0             -> "early"
--                remaining > 0.2             -> "early_minor"
--                remaining < -0.2            -> "after_zero"
function Timers.ClassifyRefresh(remaining, variance)
    local absRem = remaining < 0 and -remaining or remaining
    if absRem <= Timers.EPSILON then return nil, 0 end
    if variance and variance > 0 then
        local adj = remaining - variance
        if adj > Timers.REPORT_AT then return "early", adj end
        if adj > Timers.EPSILON then return "early_minor", adj end
        if remaining < -Timers.EPSILON then return "after_zero", remaining end
        return nil, adj
    end
    if remaining > Timers.REPORT_AT then return "early", remaining end
    if remaining > Timers.EPSILON then return "early_minor", remaining end
    if remaining < -Timers.EPSILON then return "after_zero", remaining end
    return nil, remaining
end

function Timers.CheckEarlyRefresh(timer, prev, now)
    local remaining = prev.endsAt - now
    local verdict, delta = Timers.ClassifyRefresh(remaining, prev.hasVariance and prev.variance or nil)
    if not verdict then return nil end
    local stage
    local o = timer.owner
    if o and o.GetStage then stage = o:GetStage() end
    return Addon.Telemetry and Addon.Telemetry.Write("timer.refresh", {
        enc     = timer.encId,
        mod     = o and o.id,
        timer   = timer.id,
        key     = timer.key,
        spell   = timer.spellId,
        bar     = prev.id,
        stage   = stage,
        expMin  = prev.min,
        expMax  = prev.max,
        expVar  = prev.variance,
        total   = prev.total,
        obs     = now - prev.startedAt,     -- what the interval ACTUALLY was
        rem     = remaining,
        delta   = delta,
        verdict = verdict,
    })
end

-- ══════════════════════════════════════════════════════════════════════════════
--  Bar lifecycle
-- ══════════════════════════════════════════════════════════════════════════════
local function expireBar(barId)
    local bar = Timers.bars[barId]
    if not bar then return end
    Timers.bars[barId] = nil
    local t = Timers.objects[bar.timerId]
    if t then t.live[barId] = nil end
    Addon:FireEngineEvent("TIMER_STOP", barId, bar.timerId, "expired")
end

-- §4.1: "Bar IDs are auto-removed from the object's live list on a schedule
-- matching the bar's own duration"; Update/AddTime/RemoveTime/Pause/Resume all
-- re-schedule or cancel that removal to stay consistent.
local function armExpiry(bar)
    local S = Sched()
    S:Unschedule(expireBar, nil, bar.id)
    if bar.paused then return end
    local left = bar.endsAt - S:Now()
    if left < 0 then left = 0 end
    S:Schedule(left, expireBar, nil, bar.id)
end

-- §4.4 countdown voice. One scheduler task per second, keyed by bar ID, so a
-- restart cancels them wholesale. Audio is fed the MINIMUM end of a variance
-- window (§4.2), never the maximum.
local function fireCountdown(barId, n)
    local bar = Timers.bars[barId]
    if not bar then return end
    local t = Timers.objects[bar.timerId]
    if t and t.requiresCombat then
        local f = _G.UnitAffectingCombat
        if type(f) == "function" and not f("player") then return end
    end
    Addon:FireEngineEvent("TIMER_COUNTDOWN", barId, n, t)
end

local function cancelCountdown(barId)
    Sched():Unschedule(fireCountdown, nil, barId)
end

local function armCountdown(timer, bar)
    cancelCountdown(bar.id)
    local cd = timer.countdown
    if not cd or bar.fade then return 0 end
    local depth = cd.depth or Timers.COUNTDOWN_DEPTH
    local cap = Addon.CountdownMax          -- W2 sets this from the selected voice pack
    if cap and depth > cap then depth = cap end
    local S = Sched()
    local audioEnd = bar.startedAt + bar.min     -- §4.2 audio counts to the EARLIEST cast
    local made = 0
    if depth == 0 then                            -- §4.4 "a count of 0 means count OUT"
        for i = 1, (cd.out or 3) do
            S:ScheduleAt(bar.startedAt + i, fireCountdown, nil, bar.id, i)
            made = made + 1
        end
        return made
    end
    for i = depth, 1, -1 do
        local at = audioEnd - i
        if at > S:Now() then
            S:ScheduleAt(at, fireCountdown, nil, bar.id, i)
            made = made + 1
        end
    end
    return made
end

-- Resolve the duration handed to Start into a window table.
function Timer:ResolveStart(v)
    if v == nil then return self.dur end
    if type(v) == "string" then return Timers.ParseDuration(v) end
    if type(v) == "number" then
        -- §4.2 negative start = shift the DECLARED window earlier by this delay.
        if Timers.IsNegativeStart(v) and self.dur and self.dur.hasVariance then
            return Timers.ShiftWindow(self.dur, v)
        end
        -- §4.2 "Variance is cleared from a live bar if it is later updated with a
        -- plain numeric total." We apply the same rule at Start, so there is one
        -- rule, not two: a plain number always means a plain bar.
        return plain(v, self.allowDouble)
    end
    return self.dur
end

function Timer:Start(duration, ...)
    local S = Sched()
    local now = S:Now()
    local d = self:ResolveStart(duration)
    if not d then return nil end
    local barId = self:BarId(...)

    -- §4.1 COUNT TIMERS cancel all previously started variants of the same object
    -- on a new start, unless the object was declared "allow double". This is what
    -- makes "Meteor (3)" replace "Meteor (2)" instead of stacking.
    if self.hasCount and not self.allowDouble then
        for id in pairs(self.live) do
            if id ~= barId then self:StopBar(id, "count-replaced") end
        end
    end

    -- THE TRIPWIRE: measure the bar we are about to replace.
    local prev = Timers.bars[barId]
    if prev and self:TripwireEligible() then Timers.CheckEarlyRefresh(self, prev, now) end

    local bar = prev or {}
    bar.id          = barId
    bar.timerId     = self.id
    bar.key         = self.key
    bar.encId       = self.encId
    bar.startedAt   = now
    bar.total       = d.total
    bar.min         = d.min
    bar.max         = d.max
    bar.variance    = d.variance
    bar.hasVariance = d.hasVariance
    bar.endsAt      = now + d.max
    bar.minEndsAt   = now + d.min
    bar.paused      = nil
    bar.pausedAt    = nil
    bar.text        = self.text
    bar.icon        = self.icon
    bar.color       = self.color
    bar.keep        = self.keep
    bar.fade        = self.fade
    bar.category    = self:Category()
    bar.spellId     = self.spellId
    bar.nameplate   = self.nameplate
    -- §4.2 rendering contract: the bar RUNS to max with the window painted when
    -- variance display is on, and to min when it is off. Audio, callbacks, sorting,
    -- enlargement and hide thresholds ALWAYS evaluate against min.
    bar.renderTotal = Timers.varianceDisplay and d.max or d.min
    bar.varianceFrac = (d.hasVariance and d.max > 0) and (d.variance / d.max) or 0

    Timers.bars[barId] = bar
    self.live[barId] = true
    armExpiry(bar)
    armCountdown(self, bar)
    Addon:FireEngineEvent("TIMER_START", bar)
    return bar
end

function Timer:Get(...)
    return Timers.bars[self:BarId(...)]
end

-- Remaining to the RENDER end (max when variance display is on).
function Timers.Remaining(bar, now)
    if not bar then return nil end
    now = now or Sched():Now()
    if bar.paused then return bar.endsAt - bar.pausedAt end
    return bar.endsAt - now
end

-- §4.2: "Bar auto-enlargement, hidden-bar thresholds and SORTING all evaluate
-- against the MINIMUM end of the window, so a v40-60 bar enlarges when 40 s
-- remain, not 60."  This is the number W2 sorts and enlarges on.
function Timers.SortValue(bar, now)
    if not bar then return nil end
    now = now or Sched():Now()
    if bar.paused then return bar.minEndsAt - bar.pausedAt end
    return bar.minEndsAt - now
end

function Timer:StopBar(barId, reason)
    local bar = Timers.bars[barId]
    if not bar then return false end
    Timers.bars[barId] = nil
    self.live[barId] = nil
    Sched():Unschedule(expireBar, nil, barId)
    cancelCountdown(barId)
    Addon:FireEngineEvent("TIMER_STOP", barId, self.id, reason or "stopped")
    return true
end

-- §4.1: "Stop() with no arguments can kill every variant."
function Timer:Stop(...)
    if select("#", ...) == 0 then
        local n = 0
        for id in pairs(self.live) do
            if self:StopBar(id, "stop-all") then n = n + 1 end
        end
        return n
    end
    return self:StopBar(self:BarId(...), "stopped") and 1 or 0
end

-- §4.2: "Variance is cleared from a live bar if it is later updated with a plain
-- numeric total."  §4.4: Update recomputes the countdown only if more than 2 s remain.
function Timer:Update(elapsed, total, ...)
    local barId = self:BarId(...)
    local bar = Timers.bars[barId]
    if not bar then return nil end
    local now = Sched():Now()
    if total then
        bar.total, bar.max, bar.min = total, total, total
        bar.variance, bar.hasVariance, bar.varianceFrac = 0, false, 0
        bar.renderTotal = total
    end
    bar.startedAt = now - (elapsed or 0)
    bar.endsAt    = bar.startedAt + bar.max
    bar.minEndsAt = bar.startedAt + bar.min
    armExpiry(bar)
    if (bar.minEndsAt - now) > 2 then armCountdown(self, bar) else cancelCountdown(barId) end
    Addon:FireEngineEvent("TIMER_UPDATE", bar)
    return bar
end

local function shift(self, seconds, ...)
    local barId = self:BarId(...)
    local bar = Timers.bars[barId]
    if not bar then return nil end
    bar.endsAt    = bar.endsAt + seconds
    bar.minEndsAt = bar.minEndsAt + seconds
    bar.total     = bar.total + seconds
    bar.min, bar.max = bar.min + seconds, bar.max + seconds
    bar.renderTotal = Timers.varianceDisplay and bar.max or bar.min
    armExpiry(bar)
    armCountdown(self, bar)
    Addon:FireEngineEvent("TIMER_UPDATE", bar)
    return bar
end

function Timer:AddTime(seconds, ...)    return shift(self,  seconds, ...) end
function Timer:RemoveTime(seconds, ...) return shift(self, -seconds, ...) end

function Timer:Pause(...)
    local barId = self:BarId(...)
    local bar = Timers.bars[barId]
    if not bar or bar.paused then return nil end
    bar.paused, bar.pausedAt = true, Sched():Now()
    Sched():Unschedule(expireBar, nil, barId)
    cancelCountdown(barId)                     -- §4.4 Pause kills the countdown
    Addon:FireEngineEvent("TIMER_PAUSE", bar)
    return bar
end

function Timer:Resume(...)
    local barId = self:BarId(...)
    local bar = Timers.bars[barId]
    if not bar or not bar.paused then return nil end
    local now = Sched():Now()
    local drift = now - bar.pausedAt
    bar.startedAt = bar.startedAt + drift
    bar.endsAt    = bar.endsAt + drift
    bar.minEndsAt = bar.minEndsAt + drift
    bar.paused, bar.pausedAt = nil, nil
    armExpiry(bar)
    armCountdown(self, bar)                    -- §4.4 Resume recomputes the countdown
    Addon:FireEngineEvent("TIMER_RESUME", bar)
    return bar
end

-- ── Global sweeps ─────────────────────────────────────────────────────────────
function Timers.StopAll(reason)
    local n = 0
    for barId, bar in pairs(Timers.bars) do
        local t = Timers.objects[bar.timerId]
        Timers.bars[barId] = nil
        if t then t.live[barId] = nil end
        Sched():Unschedule(expireBar, nil, barId)
        cancelCountdown(barId)
        Addon:FireEngineEvent("TIMER_STOP", barId, bar.timerId, reason or "sweep")
        n = n + 1
    end
    return n
end

function Timers.Count()
    local n = 0
    for _ in pairs(Timers.bars) do n = n + 1 end
    return n
end

Timers._expireBar = expireBar     -- exposed for harness assertions on the residue rule

return Timers
