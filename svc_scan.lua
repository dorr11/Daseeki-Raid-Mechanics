--[[
    Daseeki Raid Mechanics 2.0 — TARGET SCANNERS (engine services, wave 2)

    ENGINE SPEC §5.3, the three distinct scanners "all necessary on Era", with the
    Era truncations from §10.2 and §10.4 applied to the token ladder.

    WHY THREE. "Who is the boss about to hit" has no API on Era, so it is inferred
    three different ways depending on how much time there is:

      (a) POLLING scanner   — 0.05 s between passes, 16 passes (~0.8 s worst case).
                              Used when a cast has started and the victim will be
                              known within a second. Filters out the tank, friendlies
                              and NPCs, and a nominated previous victim.
      (b) EVENT scanner     — registers UNIT_TARGET and returns the INSTANT the
                              watched unit swaps target. Aborts at 1.5 s. Used when
                              the swap itself is the mechanic, and the difference
                              between "we saw the swap" and "it was on the tank all
                              along" matters (that is what allowTank encodes).
      (c) REPEATED scanner  — an indefinite 0.1 s loop for the rare encounters where
                              the target must be sampled continuously. Stopped by
                              the module, never by a timeout.

    ERA GATES APPLIED TO THE TOKEN LADDER. §5.3(a) describes a priority-ordered token
    list that begins `boss1..boss10` and includes `focus` / `focustarget`. Both are
    removed here, and the removal is not an optimisation:
      * §10.2 — "Creature-ID -> unit lookups SKIP the boss1..boss10 fast path
        ENTIRELY on Classic/BCC and go straight to the general token sweep", because
        the boss unit frame does not populate for Classic raid bosses (§10.22).
      * §10.4 / §2.1(e) — there is NO focus token on Era at all.
    Keeping either would spend passes on tokens that can never resolve, which on a
    0.05 s x 16 budget is the difference between finding the victim and not.

    HEADLESS DISCIPLINE. Every WoW API goes through `Scan.env`, every delay goes
    through the engine scheduler, and the event scanner's ingest point
    (`Scan.OnUnitTarget`) is a plain function — so all three scanners run on the
    harness's fake clock and fake raid, and it is the SHIPPING code that runs.
--]]

local _, Addon = ...

local Scan = {}
Addon.Scan = Scan

local function S() return Addon.Sched end

-- ══════════════════════════════════════════════════════════════════════════════
--  CONSTANTS (§5.3 + §12)
-- ══════════════════════════════════════════════════════════════════════════════
Scan.POLL_INTERVAL   = 0.05    -- §12 "polling target scanner: 0.05 s x 16 passes"
Scan.POLL_TRIES      = 16
Scan.EVENT_ABORT     = 1.5     -- §12 "event target scanner abort: 1.5 s"
Scan.REPEAT_INTERVAL = 0.1     -- §12 "repeated target scanner: 0.1 s"

-- §5.3(a): "Hard-coded exclusion of pet/guardian creature IDs 24207, 80258, 87519,
-- which otherwise poison scans."
Scan.EXCLUDED_CREATURES = { [24207] = true, [80258] = true, [87519] = true }

-- The Era token ladder, priority-ordered, built once. See the header for why
-- boss1..boss10 / focus / focustarget are absent.
local function buildEraTokens()
    local t = { "mouseover", "target", "targettarget", "mouseovertarget" }
    for i = 1, 4  do t[#t + 1] = "party" .. i .. "target" end
    for i = 1, 40 do t[#t + 1] = "raid"  .. i .. "target" end
    for i = 1, 40 do t[#t + 1] = "nameplate" .. i end
    return t
end
Scan.ERA_TOKENS = buildEraTokens()

-- ══════════════════════════════════════════════════════════════════════════════
--  INJECTABLE ENVIRONMENT
-- ══════════════════════════════════════════════════════════════════════════════
local function g(name)
    return function(...)
        local f = _G[name]
        if type(f) == "function" then return f(...) end
        return nil
    end
end

Scan.env = {
    UnitExists    = g("UnitExists"),
    UnitGUID      = g("UnitGUID"),
    UnitName      = g("UnitName"),
    UnitIsPlayer  = g("UnitIsPlayer"),
    UnitIsFriend  = g("UnitIsFriend"),
    UnitIsUnit    = g("UnitIsUnit"),
    UnitIsDeadOrGhost = g("UnitIsDeadOrGhost"),
    IsInGroup     = g("IsInGroup"),
    IsInRaid      = g("IsInRaid"),
    GetNumGroupMembers = g("GetNumGroupMembers"),
    UnitDetailedThreatSituation = g("UnitDetailedThreatSituation"),
}

function Scan.env.IsSolo()
    local n = Scan.env.GetNumGroupMembers() or 0
    return n <= 1
end

-- §5.3(b): "Group membership of the new target is VALIDATED (skipped when solo)."
function Scan.env.IsGroupMember(unit)
    if Scan.env.IsSolo() then return true end
    local n = Scan.env.GetNumGroupMembers() or 0
    local prefix = Scan.env.IsInRaid() and "raid" or "party"
    local uu = Scan.env.UnitIsUnit
    if type(uu) == "function" and uu("player", unit) then return true end
    for i = 1, n do
        if type(uu) == "function" and uu(prefix .. i, unit) then return true end
    end
    return false
end

function Scan:SetEnv(t)
    if type(t) ~= "table" then return end
    for k, v in pairs(t) do Scan.env[k] = v end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  UNIT-TOKEN RESOLUTION (§5.3(a))
-- ══════════════════════════════════════════════════════════════════════════════
-- "Unit-token resolution CACHES the last successful token per GUID and RE-VALIDATES
-- IT FIRST; on a miss it walks a priority-ordered token list."
Scan.tokenCache = {}       -- guid -> unit token

local function creatureIdOf(unit)
    local L = Addon.Lifecycle
    if not L then return nil end
    return L.CreatureIdFromGUID(Scan.env.UnitGUID(unit))
end
Scan.CreatureIdOf = creatureIdOf

local function matches(unit, creatureId, guid)
    if not Scan.env.UnitExists(unit) then return false end
    if guid then return Scan.env.UnitGUID(unit) == guid end
    if creatureId then return creatureIdOf(unit) == creatureId end
    return false
end

function Scan.ResolveUnit(creatureId, guid)
    local key = guid or creatureId
    if key then
        local cached = Scan.tokenCache[key]
        if cached and matches(cached, creatureId, guid) then return cached end
        if cached then Scan.tokenCache[key] = nil end
    end
    for i = 1, #Scan.ERA_TOKENS do
        local u = Scan.ERA_TOKENS[i]
        if matches(u, creatureId, guid) then
            if key then Scan.tokenCache[key] = u end
            return u
        end
    end
    return nil
end

function Scan.ClearTokenCache()
    for k in pairs(Scan.tokenCache) do Scan.tokenCache[k] = nil end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  FILTERS (§5.3(a))
-- ══════════════════════════════════════════════════════════════════════════════
-- "Rejects and rescans while the found target IS THE CURRENT TANK (threat status 3,
-- or the boss's own target if that's all that's available)."
--
-- Note the fallback carefully: when the threat API yields nothing, the ONLY evidence
-- of who is tanking is that the boss is looking at them — and the unit we just read
-- IS the boss's target. So "no threat data" means "assume tank", which keeps the
-- scanner rescanning until the final pass drops the filter. That is deliberate:
-- reporting the tank early is worse than reporting late, and §5.3 guarantees the
-- final pass reports SOMETHING.
function Scan.IsTank(targetUnit, bossUnit)
    local f = Scan.env.UnitDetailedThreatSituation
    if type(f) == "function" then
        local isTanking, status = f(targetUnit, bossUnit)
        if isTanking ~= nil or status ~= nil then
            return (isTanking and true or false) or status == 3
        end
    end
    return true
end

-- Returns nil when the candidate is acceptable, or a string reason when it is not.
function Scan.RejectReason(h, targetUnit, finalPass)
    local cid = creatureIdOf(targetUnit)
    if cid and Scan.EXCLUDED_CREATURES[cid] then return "excluded_pet" end
    local name = Scan.env.UnitName(targetUnit)
    if h.filter == "playersOnly" and not Scan.env.UnitIsPlayer(targetUnit) then
        return "not_a_player"
    end
    if h.filter == "enemy" and Scan.env.UnitIsFriend("player", targetUnit) then
        return "friendly"
    end
    -- §5.3(a): "Supports a 'filter this player out' argument (used when a boss casts
    -- twice in a row and the previous victim must be excluded), with an optional
    -- FALLBACK that caches the filtered player and returns them on the final pass
    -- anyway, because by then the boss has usually re-acquired its tank."
    if h.filterOut and name == h.filterOut then
        h.filteredUnit, h.filteredName = targetUnit, name
        if finalPass and h.filterOutFallback then return nil end
        return "filtered_out"
    end
    -- "A final pass IGNORES THE TANK FILTER so *something* gets reported."
    if h.excludeTank and not finalPass and Scan.IsTank(targetUnit, h.bossUnit) then
        return "is_tank"
    end
    return nil
end

-- ══════════════════════════════════════════════════════════════════════════════
--  (a) POLLING BOSS-TARGET SCANNER
-- ══════════════════════════════════════════════════════════════════════════════
Scan.active = {}          -- handle -> true

local pollPass          -- forward (scheduler needs a stable function identity)

local function finish(h, name, targetUnit, reason)
    if h.done then return end
    h.done = true
    Scan.active[h] = nil
    S():Unschedule(pollPass, Scan, h)
    local elapsed = S():Now() - h.startedAt
    h.result = { name = name, targetUnit = targetUnit, bossUnit = h.bossUnit,
                 elapsed = elapsed, passes = h.pass, reason = reason }
    -- §5.3(a): "Reports back (name, targetUnitId, bossUnitId, scanElapsed)."
    if h.cb then h.cb(name, targetUnit, h.bossUnit, elapsed, h) end
    Addon:FireEngineEvent("SCAN_RESULT", h.encId, h.key, h.result)
    return h.result
end
Scan.Finish = finish

function pollPass(h)
    if h.done then return end
    h.pass = h.pass + 1
    local finalPass = h.pass >= h.tries

    local bossUnit = Scan.ResolveUnit(h.creatureId, h.guid)
    h.bossUnit = bossUnit or h.bossUnit
    if bossUnit then
        local targetUnit = bossUnit .. "target"
        if Scan.env.UnitExists(targetUnit) then
            -- §5.3(a): "SOLO, it stops after the first pass with a valid target."
            -- With nobody else in the group there is no tank to reject and nothing
            -- better coming, so the filters have no work to do.
            if Scan.env.IsSolo() then
                return finish(h, Scan.env.UnitName(targetUnit), targetUnit, "solo")
            end
            local reject = Scan.RejectReason(h, targetUnit, finalPass)
            if not reject then
                return finish(h, Scan.env.UnitName(targetUnit), targetUnit,
                              finalPass and "final" or "matched")
            end
            h.lastReject = reject
        end
    end

    if finalPass then
        -- Nothing acceptable was ever seen. If a player was filtered out and the
        -- caller asked for the fallback, report them rather than nothing.
        if h.filterOutFallback and h.filteredName then
            return finish(h, h.filteredName, h.filteredUnit, "filter_fallback")
        end
        return finish(h, nil, nil, h.lastReject or "not_found")
    end
    S():Schedule(h.interval, pollPass, Scan, h)
end

function Scan.Poll(opts, cb)
    opts = opts or {}
    local h = {
        kind = "poll",
        creatureId = opts.creatureId, guid = opts.guid,
        tries    = opts.tries    or Scan.POLL_TRIES,
        interval = opts.interval or Scan.POLL_INTERVAL,
        filter   = opts.filter,
        excludeTank = opts.excludeTank and true or false,
        filterOut = opts.filterOut,
        filterOutFallback = opts.filterOutFallback and true or false,
        encId = opts.encId, key = opts.key,
        cb = cb, pass = 0, startedAt = S():Now(),
    }
    Scan.active[h] = true
    -- §5.3(a) "delay" — some callers want the first pass a beat after the cast so
    -- the server has actually applied the new target.
    if opts.delay and opts.delay > 0 then
        S():Schedule(opts.delay, pollPass, Scan, h)
    else
        pollPass(h)
    end
    return h
end

-- ══════════════════════════════════════════════════════════════════════════════
--  (b) EVENT-DRIVEN SCANNER
-- ══════════════════════════════════════════════════════════════════════════════
Scan.watchers = {}        -- handle -> true

local eventAbort          -- forward

-- §8.1 "short-term (registered ad hoc by a scanner and torn down in bulk)": the
-- event scanner owns its own frame and only holds UNIT_TARGET while someone is
-- watching, so the raid pays nothing for it the rest of the fight.
local unitTargetFrame

local function ensureUnitTargetFrame()
    if unitTargetFrame ~= nil then return unitTargetFrame end
    if type(_G.CreateFrame) ~= "function" then unitTargetFrame = false; return false end
    local f = _G.CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, _, unit) Scan.OnUnitTarget(unit) end)
    unitTargetFrame = f
    return f
end

local function armUnitTarget(on)
    local f = ensureUnitTargetFrame()
    if not f then return false end
    if on then f:RegisterEvent("UNIT_TARGET") else f:UnregisterEvent("UNIT_TARGET") end
    return true
end

local function anyWatchers()
    return next(Scan.watchers) ~= nil
end

function eventAbort(h)
    if h.done then return end
    -- §5.3(b): "An 'allow tank' mode makes the abort return the unit's CURRENT
    -- TARGET rather than nothing — the difference between 'we saw the swap' and
    -- 'the cast was on the tank all along'."
    if h.allowTank and h.watchUnit then
        local t = h.watchUnit .. "target"
        if Scan.env.UnitExists(t) then
            return Scan.EventFinish(h, Scan.env.UnitName(t), t, "abort_allow_tank")
        end
    end
    return Scan.EventFinish(h, nil, nil, "abort")
end

function Scan.EventFinish(h, name, targetUnit, reason)
    if h.done then return end
    h.done = true
    Scan.watchers[h] = nil
    S():Unschedule(eventAbort, Scan, h)
    if not anyWatchers() then armUnitTarget(false) end
    local elapsed = S():Now() - h.startedAt
    h.result = { name = name, targetUnit = targetUnit, bossUnit = h.watchUnit,
                 elapsed = elapsed, reason = reason }
    if h.cb then h.cb(name, targetUnit, h.watchUnit, elapsed, h) end
    Addon:FireEngineEvent("SCAN_RESULT", h.encId, h.key, h.result)
    return h.result
end

-- The ingest point. A plain function so the harness drives it directly.
function Scan.OnUnitTarget(unit)
    local hits = 0
    for h in pairs(Scan.watchers) do
        if not h.done and (h.watchUnit == nil or h.watchUnit == unit) then
            local t = unit .. "target"
            if Scan.env.UnitExists(t) then
                local name = Scan.env.UnitName(t)
                -- §5.3(b): group membership of the new target is validated.
                if Scan.env.IsGroupMember(t) then
                    h.watchUnit = h.watchUnit or unit
                    Scan.EventFinish(h, name, t, "swapped")
                    hits = hits + 1
                end
            end
        end
    end
    return hits
end

function Scan.Event(opts, cb)
    opts = opts or {}
    local h = {
        kind = "event",
        watchUnit = opts.unit or Scan.ResolveUnit(opts.creatureId, opts.guid),
        allowTank = opts.allowTank and true or false,
        abort = opts.abort or Scan.EVENT_ABORT,
        encId = opts.encId, key = opts.key,
        cb = cb, startedAt = S():Now(),
    }
    Scan.watchers[h] = true
    armUnitTarget(true)
    S():Schedule(h.abort, eventAbort, Scan, h)
    return h
end

-- ══════════════════════════════════════════════════════════════════════════════
--  (c) REPEATED SCANNER
-- ══════════════════════════════════════════════════════════════════════════════
-- §5.3(c): "An INDEFINITE loop at a configurable interval (default 0.1 s) for the
-- rare encounters where target must be sampled continuously. EXPLICITLY STOPPED by
-- the module." There is no abort here on purpose — a timeout would silently turn a
-- continuous sample into a one-shot half a fight later.
Scan.repeats = {}

function Scan.Repeated(opts, cb)
    opts = opts or {}
    local h = {
        kind = "repeated",
        creatureId = opts.creatureId, guid = opts.guid,
        interval = opts.interval or Scan.REPEAT_INTERVAL,
        filter = opts.filter,
        encId = opts.encId, key = opts.key,
        cb = cb, samples = 0, startedAt = S():Now(), last = nil,
    }
    Scan.repeats[h] = true
    h.loop = S():Loop(h.interval, function()
        if h.done then return end
        h.samples = h.samples + 1
        local bossUnit = Scan.ResolveUnit(h.creatureId, h.guid)
        h.bossUnit = bossUnit
        local name, targetUnit
        if bossUnit then
            targetUnit = bossUnit .. "target"
            if Scan.env.UnitExists(targetUnit) then
                if h.filter == "playersOnly" and not Scan.env.UnitIsPlayer(targetUnit) then
                    targetUnit = nil
                else
                    name = Scan.env.UnitName(targetUnit)
                end
            else
                targetUnit = nil
            end
        end
        -- Only report CHANGES: a 0.1 s loop that re-announces the same target ten
        -- times a second is a spam generator, not a scanner.
        if name ~= h.last then
            h.last = name
            if h.cb then h.cb(name, targetUnit, bossUnit, S():Now() - h.startedAt, h) end
            Addon:FireEngineEvent("SCAN_RESULT", h.encId, h.key,
                { name = name, targetUnit = targetUnit, bossUnit = bossUnit,
                  elapsed = S():Now() - h.startedAt, reason = "sample" })
        end
    end, Scan)
    return h
end

-- ══════════════════════════════════════════════════════════════════════════════
--  LIFECYCLE
-- ══════════════════════════════════════════════════════════════════════════════
function Scan.Stop(h)
    if type(h) ~= "table" or h.done then return false end
    h.done = true
    if h.kind == "poll" then
        Scan.active[h] = nil
        S():Unschedule(pollPass, Scan, h)
    elseif h.kind == "event" then
        Scan.watchers[h] = nil
        S():Unschedule(eventAbort, Scan, h)
        if not anyWatchers() then armUnitTarget(false) end
    elseif h.kind == "repeated" then
        Scan.repeats[h] = nil
        S():CancelLoop(h.loop)
    end
    return true
end

function Scan.StopAll()
    local n = 0
    for h in pairs(Scan.active)   do if Scan.Stop(h) then n = n + 1 end end
    for h in pairs(Scan.watchers) do if Scan.Stop(h) then n = n + 1 end end
    for h in pairs(Scan.repeats)  do if Scan.Stop(h) then n = n + 1 end end
    Scan.ClearTokenCache()
    return n
end

-- ══════════════════════════════════════════════════════════════════════════════
--  ENGINE SEAM — SCAN_REQUEST
-- ══════════════════════════════════════════════════════════════════════════════
-- core_api's Runtime:Act raises SCAN_REQUEST(encId, row, ev) for every declared
-- scan row. This is the service that answers it.
--
-- The RESULT re-enters the engine as a `targetChanged` event, which is already in
-- the trigger vocabulary (API.TRIGGER_EVENTS). That is the whole seam: encounter
-- data declares a scan, and consumes its answer with an ordinary trigger row —
-- no second grammar, and no engine change to carry a scan result.
function Scan.Dispatch(encId, row, ev)
    local rt = Addon.Lifecycle and Addon.Lifecycle:GetRuntime(encId)
    local creatureId = row.creatureId or (ev and (ev.sourceId or ev.creatureId))
    local guid       = row.guid       or (ev and ev.sourceGUID)
    local opts = {
        encId = encId, key = row.key,
        creatureId = creatureId, guid = guid,
        interval = row.interval, tries = row.tries, delay = row.delay,
        filter = row.filter, excludeTank = row.excludeTank,
        filterOut = row.filterOut or (ev and row.filterPrevious and ev.destName),
        filterOutFallback = row.filterOutFallback,
        abort = row.abort, allowTank = row.allowTank,
        unit = row.unit,
    }
    local function report(name, targetUnit, bossUnit, elapsed)
        -- W4d: TARGET LOSS is a result too. Sapphiron's air phase has no event on Era;
        -- the only tell is that the boss stops having a target of its own, so a scan
        -- row may declare `reportLoss` and consume the loss as an ordinary trigger
        -- (`where = { lost = true }`). Every other scanner is unaffected: without the
        -- flag a nil target still reports nothing, exactly as before.
        if not name then
            if row.reportLoss and rt and (rt.engaged or rt.isZone) then
                rt:Route({ on = "targetChanged", key = row.key, lost = true,
                           sourceUnit = bossUnit, elapsed = elapsed })
            end
            return
        end
        if rt and rt.engaged then
            rt:Route({ on = "targetChanged", key = row.key, destName = name,
                       unit = targetUnit, sourceUnit = bossUnit, elapsed = elapsed })
        end
        -- A scan row may name a warning row to emit with the found target folded in.
        if row.warning and rt then
            local w = rt.def.rowsByKey and rt.def.rowsByKey[row.warning]
            if w and Addon.API.IsRowEnabled(encId, w) then
                local text = w.text or w.key
                text = text:find("%%s") and text:format(">" .. name .. "<")
                                        or (text .. " >" .. name .. "<")
                if (w.tier or "announce") == "special" then Addon:EmitSpecial(encId, w, text)
                else Addon:EmitAnnounce(encId, w, text) end
            end
        end
    end

    local kind = row.type or "poll"
    if kind == "event"    then return Scan.Event(opts, report) end
    if kind == "repeated" then return Scan.Repeated(opts, report) end
    return Scan.Poll(opts, report)
end

function Scan.Init()
    if Scan._inited then return end
    Scan._inited = true
    Addon:RegisterEngineCallback("SCAN_REQUEST", function(_, encId, row, ev)
        return Scan.Dispatch(encId, row, ev)
    end, Scan)
    -- Every scanner is fight-scoped: a scan still running after the fight is a
    -- 0.05 s poll nobody is reading.
    Addon:RegisterEngineCallback("ENGINE_END", function() Scan.StopAll() end, Scan)
    return true
end

return Scan
