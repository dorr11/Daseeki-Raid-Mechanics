--[[
    Daseeki Raid Mechanics 2.0 — encounter lifecycle (engine core, wave 1)

    ENGINE SPEC §2 in full, plus the Era gates from §10 that change its shape.

      §2.1  FIVE combat-start paths, in priority order:
              (a) ENCOUNTER_START                    — delay 0, highest fidelity
              (b) INSTANCE_ENCOUNTER_ENGAGE_UNIT     — REGISTERED BUT INERT ON ERA (§10.22)
              (c) PLAYER_REGEN_DISABLED + target sweeps at 0.5 / 1.25 / 2.0 s
              (d) chat trigger (yell / say / emote / raid boss emote)
              (e) UNIT_HEALTH_FREQUENT on a boss creature, armed 20 s after load
      §2.2  re-engage lockouts: 120 s after a kill, 20 s after a wipe (3 s when the
            trigger is ENCOUNTER_START), both bypassed by a zone load
      §2.3  what a start does, incl. the difficulty snapshot (§10.8: Classic reports
            wrong difficulty data AFTER A RELEASE, so the snapshot is taken at engage
            and every end-of-combat report uses it)
      §2.4  wipe detection: a 3 s poll producing a verdict, then a confirmation
            window of 5 s (15 s for world bosses, or a longer per-module value)
      §2.5  four kill paths
      §2.6  what an end does, incl. the sub-30 s attempt rule

    PATH (b) IS DELIBERATELY A NO-OP. ENGINE SPEC §10.22: "INSTANCE_ENCOUNTER_
    ENGAGE_UNIT is registered but effectively inert on Era — the boss unit frame
    does not populate for Classic raid bosses." We register it, we never start
    combat from it, and if it ever DOES fire with a matching boss we write a
    telemetry note so we find out. Building the path for real would be dead code
    that silently double-starts the day Blizzard changes it.

    HEADLESS DISCIPLINE: every WoW API this file touches goes through `Life.env`,
    a table of injectable functions. The harness swaps the table and drives the
    REAL lifecycle code on a fake clock and a fake raid.
--]]

local _, Addon = ...

local Life = {}
Addon.Lifecycle = Life

local function S() return Addon.Sched end
local function API() return Addon.API end

-- ── Constants (ENGINE SPEC §12) ───────────────────────────────────────────────
Life.ARM_COMBAT           = 1.5     -- combat-state pull detection arms after load
Life.ARM_HEALTH           = 20      -- health-based pull detection arms after load
Life.SWEEP_DELAYS         = { 0.5, 1.25, 2.0 }
-- AUDIT RML-1: the sweep's tiebreak rule. See Life:SweepOrder. `true` = the mob the
-- player is targeting wins a multi-creature sweep; otherwise lowest creature id.
-- Either way the answer is a RULE, never a pairs() race.
Life.PREFER_TARGETED      = true
Life.HEALTH_REARM         = 2.1     -- health path re-arms after the sweeps
Life.HEALTH_HIGH_PCT      = 97      -- above this, the engage delay is a flat 0.5 s
Life.HEALTH_HIGH_DELAY    = 0.5
Life.HEALTH_MAX_DELAY     = 20
Life.HEALTH_IGNORE_PCT    = 2       -- below this, ignore outright
Life.LOCKOUT_KILL         = 120
Life.LOCKOUT_WIPE         = 20
Life.LOCKOUT_WIPE_ENCOUNTER = 3
Life.WIPE_POLL            = 3
Life.WIPE_WINDOW          = 5
Life.WIPE_WINDOW_WORLDBOSS = 15
Life.FIRST_WIPE_CHECK_MIN = 3
Life.MIN_ATTEMPT          = 30      -- a wipe under this decrements the pull counter
Life.HEALTH_POLL          = 1
Life.AURA_TEARDOWN_DELAY  = 2       -- aura-removed events survive 2 s past the end
Life.TIMER_SWEEP_DELAY    = 3       -- full timer stop at +3 s
Life.LOG_STOP_DELAY       = 10
Life.MUSIC_RESTART_DELAY  = 22
Life.WORLD_BOSS_RECORD_PCT = 98     -- engaging below this disqualifies the kill record
-- ENGINE SPEC §9.1 step 3 (added in W3, the smallest seam that makes the rule real):
-- "a 'recovery in progress' flag is set for 15 s; while set, the boss-frame
-- combat-start path is disabled so a partial recovery can't be mistaken for a fresh
-- pull." ERA TRANSLATION: path (b) — the boss-frame path — is INERT on Era (§10.22),
-- so suppressing only that would suppress nothing. The Era path that can actually
-- mistake a recovery for a pull is the HEALTH path (e), which is why §1.2 already
-- delays its arming by 20 s for exactly this reason. So the flag gates BOTH: the
-- literal boss-frame path (for the day Blizzard fixes it) and the health path.
Life.RECOVERY_SUPPRESS    = 15

-- ENGINE SPEC §10.9: difficulty index mapping for Era raids.
Life.ERA_DIFFICULTY = {
    [9]   = { bucket = "raid40", size = 40 },
    [186] = { bucket = "raid40", size = 40 },
    [148] = { bucket = "raid20", size = 20 },
    [185] = { bucket = "raid20", size = 20 },
    [215] = { bucket = "raid20", size = 20 },
    [3]   = { bucket = "raid10", size = 10 },
    [175] = { bucket = "raid10", size = 10 },
    [198] = { bucket = "raid10", size = 10 },
    [0]   = { bucket = "worldboss", size = 0, worldBoss = true },
    [1]   = { bucket = "party",  size = 5 },
    [2]   = { bucket = "heroic", size = 5 },
}
Life.ZG_INSTANCE_ID = 309           -- §10.9 force-mapped to the 10-man stats bucket
-- §2.4 row 1: scenario-type content, or difficulty index 11 / 12 / 208, never wipes.
Life.NO_WIPE_DIFFICULTY = { [11] = true, [12] = true, [208] = true }

-- The five verdicts of the wipe poll (§2.4), plus the fall-through that means the
-- fight is simply still going. Named constants because the harness asserts the
-- whole matrix row by row.
Life.VERDICT = {
    NOT_WIPE_TRIVIAL            = "not_wipe_trivial",       -- scenario / difficulty 11,12,208
    NOT_WIPE_ENCOUNTER_PROGRESS = "not_wipe_encounter",     -- IsEncounterInProgress()
    NOT_WIPE_WORLDBOSS_DEATH    = "not_wipe_worldboss",     -- world boss + player dead/ghost
    WIPE_BOSS_GONE              = "wipe_boss_gone",         -- type 2
    WIPE_NO_COMBATANT           = "wipe_no_combatant",      -- type 1
    NOT_WIPE_COMBAT_LIVE        = "not_wipe_live",          -- someone is in combat and alive
}
local V = Life.VERDICT

-- Scheduled work is dispatched by the scheduler as `fn(arg1, …)` with NO implicit
-- self, so anything scheduled must be a PLAIN function, not a `Life:Method`
-- reference (which would silently receive its first argument as `self`). These
-- shims give the cancellable tasks a stable function identity for §3.2's
-- partial-match Unschedule.
local sweepTask, wipeTask

-- ── State ─────────────────────────────────────────────────────────────────────
Life.engaged     = {}       -- ordered array of runtimes
Life.zoneArmed   = {}       -- encId -> runtime  (W4d: trash modules, §1.1 "zone combat")
Life.byId        = {}       -- encId -> runtime
Life.lockouts    = {}       -- encId -> { reason = "kill"|"wipe", at = }
Life.healthCache = {}       -- creatureId -> last known health pct
Life.bossSeen    = false    -- "boss unit IDs were confirmed to exist at some point"
Life.armedCombat = false
Life.armedHealthBoot = false
Life.healthSuppressed = false
Life.lastCombatFlagAt = nil
Life.pendingSweeps = 0
Life.stats = { engages = 0, kills = 0, wipes = 0, rejected = 0 }

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

Life.env = {
    UnitExists            = g("UnitExists"),
    UnitAffectingCombat   = g("UnitAffectingCombat"),
    UnitIsDeadOrGhost     = g("UnitIsDeadOrGhost"),
    UnitIsPlayer          = g("UnitIsPlayer"),
    UnitGUID              = g("UnitGUID"),
    UnitName              = g("UnitName"),
    UnitHealth            = g("UnitHealth"),
    UnitHealthMax         = g("UnitHealthMax"),
    UnitIsFriend          = g("UnitIsFriend"),
    UnitInVehicle         = g("UnitInVehicle"),
    IsEncounterInProgress = g("IsEncounterInProgress"),
    GetInstanceInfo       = g("GetInstanceInfo"),
    IsInInstance          = g("IsInInstance"),
    IsInRaid              = g("IsInRaid"),
    IsInGroup             = g("IsInGroup"),
    GetNumGroupMembers    = g("GetNumGroupMembers"),
}

-- Allocation-free group iteration (§3.2 "allocation-free custom iterators that
-- synthesize unit-ID strings"). `fn(unit)` may return true to stop early.
function Life.env.ForEachGroupMember(fn)
    local e = Life.env
    local n = e.GetNumGroupMembers() or 0
    if e.IsInRaid() then
        for i = 1, n do if fn("raid" .. i) then return true end end
    else
        if fn("player") then return true end
        for i = 1, (n > 0 and n - 1 or 0) do if fn("party" .. i) then return true end end
    end
    return false
end

function Life.env.ForEachNameplate(fn)
    for i = 1, 40 do
        local u = "nameplate" .. i
        if Life.env.UnitExists(u) then if fn(u) then return true end end
    end
    return false
end

-- "Boss unit IDs were confirmed to exist at some point during this fight" (§2.4).
function Life.env.AnyBossUnit()
    for i = 1, 10 do
        if Life.env.UnitExists("boss" .. i) then return true end
    end
    return false
end

function Life.env.IsGroupUnit(unit)
    local hit = false
    Life.env.ForEachGroupMember(function(u)
        if u == unit then hit = true return true end
        local guid = Life.env.UnitGUID(u)
        if guid and guid == Life.env.UnitGUID(unit) then hit = true return true end
        if u .. "pet" == unit then hit = true return true end
        return false
    end)
    return hit
end

function Life:SetEnv(t)
    if type(t) ~= "table" then return end
    for k, v in pairs(t) do Life.env[k] = v end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  HELPERS
-- ══════════════════════════════════════════════════════════════════════════════
function Life.CreatureIdFromGUID(guid)
    -- ENGINE SPEC §8.4: Creature/Vehicle/Pet GUIDs are type-?-?-?-?-creatureID-spawnUID;
    -- the 6th hyphen-delimited field is the creature ID.
    if type(guid) ~= "string" then return nil end
    local kind, f2, f3, f4, f5, id = guid:match("^(%w+)%-([^-]*)%-([^-]*)%-([^-]*)%-([^-]*)%-(%d+)")
    if not kind then return nil end
    if kind ~= "Creature" and kind ~= "Vehicle" and kind ~= "Pet" then return nil end
    return tonumber(id)
end

function Life:CreatureIdOfUnit(unit)
    return Life.CreatureIdFromGUID(Life.env.UnitGUID(unit))
end

function Life:HealthPct(unit)
    local hp, mx = Life.env.UnitHealth(unit), Life.env.UnitHealthMax(unit)
    if not hp or not mx or mx == 0 then return nil end
    return hp / mx * 100
end

function Life:InInstance()
    local inside = Life.env.IsInInstance()
    return inside and true or false
end

-- §2.3 step 3 + §10.8/§10.9: SNAPSHOT the difficulty at engage.
function Life:SnapshotDifficulty()
    local name, instanceType, difficultyID, difficultyName, maxPlayers,
          _, _, instanceID = Life.env.GetInstanceInfo()
    local map = Life.ERA_DIFFICULTY[difficultyID or -1]
    local bucket = map and map.bucket or "normal"
    local size   = map and map.size or maxPlayers
    -- §10.9: Zul'Gurub (instance 309) is force-mapped to the 10-man bucket
    -- regardless of what the client reports.
    if instanceID == Life.ZG_INSTANCE_ID then bucket, size = "raid10", 20 end
    return {
        id = difficultyID, name = difficultyName, text = name,
        instanceType = instanceType, instanceId = instanceID,
        bucket = bucket, size = size,
        worldBoss = (map and map.worldBoss) or false,
    }
end

-- ══════════════════════════════════════════════════════════════════════════════
--  W4d — ZONE (TRASH) MODULES.  ENCOUNTERS SPEC §1.1: "Zone combat — trash module;
--  armed for the whole instance, tracks per-mob-GUID timers, disarms when the whole
--  raid drops combat."
--
--  A zone module is NOT an engagement: it has no pull, no wipe verdict, no lockout,
--  no statistics, and it must not appear in `Life.engaged` (which would make a trash
--  pack look like a boss fight to the wipe poll). It is a second, flat list of
--  runtimes that receives the same routed events. Arming is by instance, so the
--  Naxxramas trash alerts are live during boss fights too — which the spec requires,
--  because the AQ40/Naxx trash modules explicitly stay active mid-encounter.
function Life:ArmZones(instanceId)
    if instanceId == nil then
        local _, _, _, _, _, _, _, iid = Life.env.GetInstanceInfo()
        instanceId = iid
    end
    local wanted = {}
    for _, enc in ipairs(Addon.encByZone[instanceId] or {}) do
        if enc.detect and enc.detect.mode == "zone" then wanted[enc.id] = enc end
    end
    -- Disarm anything that is not wanted here (zoning out of Naxx into Azeroth).
    for encId, rt in pairs(Life.zoneArmed) do
        if not wanted[encId] then
            rt:Teardown()
            Life.zoneArmed[encId] = nil
        end
    end
    local armed = 0
    for encId, enc in pairs(wanted) do
        if not Life.zoneArmed[encId] then
            local rt = API().NewRuntime(enc, { pullTime = S():Now(), trigger = "zone" })
            rt.isZone = true
            Life.zoneArmed[encId] = rt
            rt:StartPullSchedules()
            Addon:FireEngineEvent("ENGINE_ENGAGE", enc.id, rt, 0, "zone")
            armed = armed + 1
        end
    end
    return armed
end

function Life:DisarmZones()
    local n = 0
    for encId, rt in pairs(Life.zoneArmed) do
        rt:Teardown()
        Life.zoneArmed[encId] = nil
        n = n + 1
    end
    return n
end

function Life:IsZoneArmed(encId) return Life.zoneArmed[encId] ~= nil end

function Life:IsEngaged(encId) return Life.byId[encId] ~= nil end
function Life:GetRuntime(encId) return Life.byId[encId] end
function Life:AnyEngaged() return #Life.engaged > 0 end

function Life:GetStage(encId)
    local rt = Life.byId[encId]
    return rt and rt.stage or nil
end

-- ══════════════════════════════════════════════════════════════════════════════
--  BOOT (ENGINE SPEC §1.2 initialization timeline)
-- ══════════════════════════════════════════════════════════════════════════════
function Life:Boot()
    Life.loadedAt = S():Now()
    Life.armedCombat = false
    Life.armedHealthBoot = false
    -- +1.5 s: combat-state pull detection arms. Before this PLAYER_REGEN_DISABLED
    -- is ignored ENTIRELY.
    S():Schedule(Life.ARM_COMBAT, function() Life.armedCombat = true end, Life)
    -- +20 s: health-based pull detection arms. Deliberately delayed so timer
    -- recovery on a /reload mid-fight is not mistaken for a fresh pull.
    S():Schedule(Life.ARM_HEALTH, function() Life.armedHealthBoot = true end, Life)
    return true
end

function Life:HealthArmed()
    if Life:IsRecovering() then return false end          -- §9.1 step 3
    return Life.armedHealthBoot and not Life.healthSuppressed
end

-- §9.1 step 3. Absolute-deadline flag rather than a scheduled clear, so a second
-- recovery attempt EXTENDS the window instead of racing a stale unschedule, and so
-- the harness can read the deadline directly on the fake clock.
function Life:SetRecovering(on, seconds)
    if not on then Life.recoveringUntil = nil return false end
    Life.recoveringUntil = S():Now() + (seconds or Life.RECOVERY_SUPPRESS)
    return true
end

function Life:IsRecovering()
    local until_ = Life.recoveringUntil
    if not until_ then return false end
    if S():Now() >= until_ then Life.recoveringUntil = nil return false end
    return true
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §2.2 RE-ENGAGE LOCKOUTS
-- ══════════════════════════════════════════════════════════════════════════════
function Life:LockoutWindow(enc, trigger)
    local lk = Life.lockouts[enc.id]
    if not lk then return 0 end
    if lk.reason == "kill" then
        return (enc.combat and enc.combat.killLockout) or Life.LOCKOUT_KILL
    end
    -- After a WIPE the window is 20 s, reduced to 3 s when the trigger is
    -- ENCOUNTER_START (because that event is trustworthy).
    if trigger == "encounter" then return Life.LOCKOUT_WIPE_ENCOUNTER end
    return (enc.combat and enc.combat.wipeLockout) or Life.LOCKOUT_WIPE
end

-- Returns allowed, reason, secondsRemaining.
function Life:CanStart(enc, trigger)
    if Life:IsEngaged(enc.id) then return false, "already_engaged", 0 end
    if enc.detect and enc.detect.noMultiBoss and Life:AnyEngaged() then
        return false, "multiboss", 0
    end
    if enc.detect and enc.detect.noVehicleEngage and Life.env.UnitInVehicle("player") then
        return false, "vehicle", 0
    end
    -- Both lockouts are BYPASSED when the trigger is a zone load.
    if trigger == "zone" then return true, nil, 0 end
    local lk = Life.lockouts[enc.id]
    if lk then
        local window = Life:LockoutWindow(enc, trigger)
        local left = (lk.at + window) - S():Now()
        if left > 0 then return false, lk.reason, left end
    end
    return true, nil, 0
end

function Life:SetLockout(encId, reason)
    Life.lockouts[encId] = { reason = reason, at = S():Now() }
end

function Life:ClearLockout(encId) Life.lockouts[encId] = nil end

-- ══════════════════════════════════════════════════════════════════════════════
--  §2.3 START
-- ══════════════════════════════════════════════════════════════════════════════
function Life:StartCombat(enc, delay, trigger)
    delay = delay or 0
    local allowed, reason, left = Life:CanStart(enc, trigger)
    if not allowed then
        Life.stats.rejected = Life.stats.rejected + 1
        if Addon.Telemetry then
            Addon.Telemetry.Write("lifecycle.lockout",
                { enc = enc.id, reason = reason, trigger = trigger, delay = left })
        end
        Addon:FireEngineEvent("ENGINE_LOCKOUT", enc.id, reason, left)
        return nil, reason
    end

    local now = S():Now()
    local difficulty = Life:SnapshotDifficulty()
    local rt = API().NewRuntime(enc, {
        pullTime = now - delay,          -- 1. stamp pull time as now - delay
        difficulty = difficulty,
        trigger = trigger,
    })
    rt.delay = delay
    rt.lastValidCombat = now             -- the pull instant stamps last-valid-combat (§2.4)
    rt.confirming = false
    rt.bossSeen = Life.env.AnyBossUnit() and true or false

    -- 5. engaged-at health + record eligibility
    local pct = Life:BossHealthPct(enc)
    rt.engagedAtPct = pct
    rt.recordEligible = true
    if difficulty.worldBoss and pct and pct < Life.WORLD_BOSS_RECORD_PCT then rt.recordEligible = false end
    if trigger == "health" and delay > 4 then rt.recordEligible = false end
    if trigger == "recovery" then rt.recordEligible = false end

    Life.engaged[#Life.engaged + 1] = rt
    Life.byId[enc.id] = rt
    Life.stats.engages = Life.stats.engages + 1
    if pct then Life.healthCache[enc.creatureIds[1] or enc.id] = pct end

    -- 4. first wipe check at max(minCombatTime - delay, 3 s)
    local minCombat = (enc.combat and enc.combat.minCombatTime) or 0
    local first = minCombat - delay
    if first < Life.FIRST_WIPE_CHECK_MIN then first = Life.FIRST_WIPE_CHECK_MIN end
    S():Schedule(first, wipeTask, Life, rt)

    -- 6. boss-health poller (default 1 s, module-overridable)
    local pollEvery = (enc.combat and enc.combat.healthPoll) or Life.HEALTH_POLL
    rt.healthLoop = S():Loop(pollEvery, function() Life:PollHealth(rt) end, rt)

    -- 9/10. legacy widget contract + special modules + the module's own engage hook
    API().SetLegacyActive(enc, rt)
    API().StartSpecials(enc, rt)

    -- pull-seeded schedules and pull-triggered timers
    rt:StartPullSchedules()

    if Addon.Telemetry then
        Addon.Telemetry.Write("lifecycle.engage",
            { enc = enc.id, trigger = trigger, delay = delay, path = trigger })
    end
    Addon:FireEngineEvent("ENGINE_ENGAGE", enc.id, rt, delay, trigger)
    -- 11. broadcast the combat-start sync unless this start WAS a sync (W3 wires the wire)
    if trigger ~= "sync" then
        Addon:FireEngineEvent("SYNC_SEND", "C", delay, enc.id, pct, trigger)
    end
    return rt
end

function Life:BossHealthPct(enc)
    -- ENGINE SPEC §8.6 Era resolution order: cached token -> target -> every group
    -- member's target -> nameplate1..20. Boss tokens are skipped entirely (§10.2).
    local want = {}
    for _, cid in ipairs(enc.creatureIds or {}) do want[cid] = true end
    local found
    local function probe(u)
        if not Life.env.UnitExists(u) then return false end
        local cid = Life:CreatureIdOfUnit(u)
        if cid and want[cid] then
            local p = Life:HealthPct(u)
            -- §8.6: return the LAST NON-ZERO value when the unit reports 0 health
            -- but is not actually dead — a real Classic API quirk.
            if p and p > 0 then found = p; return true end
            if p == 0 and not Life.env.UnitIsDeadOrGhost(u) then
                found = Life.healthCache[cid]; return found ~= nil
            end
        end
        return false
    end
    if probe("target") then return found end
    local stop = Life.env.ForEachGroupMember(function(u) return probe(u .. "target") end)
    if stop then return found end
    for i = 1, 20 do if probe("nameplate" .. i) then return found end end
    return nil
end

function Life:PollHealth(rt)
    if not rt.engaged then return end
    local pct = Life:BossHealthPct(rt.def)
    if pct then
        local cid = rt.def.creatureIds[1]
        if cid then
            -- §8.6: the cache keeps the LOWEST value seen, or the HIGHEST when the
            -- module declared "report the highest-health boss" (council fights).
            local prev = Life.healthCache[cid]
            if prev == nil then Life.healthCache[cid] = pct
            elseif rt.def.combat and rt.def.combat.highestHealth then
                if pct > prev then Life.healthCache[cid] = pct end
            elseif pct < prev then Life.healthCache[cid] = pct end
        end
        rt.bossPct = pct
        Life:EvaluateHealthTriggers(rt, pct)
    end
    if Life.env.AnyBossUnit() then rt.bossSeen = true end
end

-- Health-threshold triggers declared anywhere in the encounter grammar
-- ("Enrage soon at <= 25 %", "Phase 3 soon at <= 48 %"). Each fires once per
-- engagement unless the row asks to repeat.
function Life:EvaluateHealthTriggers(rt, pct)
    local bucket = rt.def.index and rt.def.index.health
    if not bucket then return 0 end
    local fired = 0
    for i = 1, #bucket do
        local entry = bucket[i]
        local tr = entry.trigger
        -- Phase rows have no option key of their own, so they are addressed by
        -- their index in the phases list.
        -- W4c: the once-per-engagement key is per THRESHOLD, not per row. Skeram's
        -- three split pre-warnings are one row with three health windows, and keying
        -- the "already fired" set on the row alone would spend the row on the first
        -- window and go silent for the other two.
        local key = (entry.consumer.row.key or ("phase#" .. tostring(entry.consumer.act)))
                    .. ":health:" .. tostring(tr.pct) .. ":" .. tostring(tr.pctMin or "")
        local hev = { on = "health", pct = pct }
        -- W4d: run the health threshold through the SAME matcher every other trigger
        -- uses, so a health rule can be scoped ("phase 3 at <= 48 % WHILE IN PHASE 2" —
        -- Kel'Thuzad's guardian point, which is not a phase-1 rule).
        if pct <= (tr.pct or 0) and (tr.repeat_ or not rt.healthFired[key])
           and API().TriggerMatches(rt, tr, hev) then
            rt.healthFired[key] = true
            if rt:Act(entry, hev) then fired = fired + 1 end
            if tr.sync then Addon:FireEngineEvent("SYNC_SEND", "M", rt.id, key) end
        end
    end
    return fired
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §2.1 THE FIVE START PATHS
-- ══════════════════════════════════════════════════════════════════════════════

-- (a) ENCOUNTER_START — delay 0, highest fidelity. A module can opt out.
function Life:OnEncounterStart(encounterId)
    local list = Addon.encByEncounterId[encounterId]
    if not list then return nil, "no_module" end
    for _, enc in ipairs(list) do
        if not (enc.detect and enc.detect.noEncounterStart) then
            local rt = Life:StartCombat(enc, 0, "encounter")
            if rt then return rt end
        end
    end
    return nil, "opted_out"
end

-- (b) INSTANCE_ENCOUNTER_ENGAGE_UNIT — §10.22 INERT ON ERA. Never starts combat.
-- If it ever fires with a boss we recognise, that is news, so it is recorded.
function Life:OnEngageUnit()
    -- §9.1 step 3: the boss-frame combat-start path is disabled for 15 s while a
    -- reload recovery is in flight. Inert on Era today, wired anyway so the rule is
    -- present the moment the path becomes real.
    if Life:IsRecovering() then return nil, "recovery_in_progress" end
    for i = 1, 10 do
        local u = "boss" .. i
        if not Life.env.UnitExists(u) then break end
        local cid = Life:CreatureIdOfUnit(u)
        if cid and Addon.encByCreature[cid] and Addon.Telemetry then
            Addon.Telemetry.Write("lifecycle.inert",
                { path = "INSTANCE_ENCOUNTER_ENGAGE_UNIT", enc = Addon.encByCreature[cid][1].id })
        end
    end
    return nil, "inert_on_era"
end

-- (c) PLAYER_REGEN_DISABLED + target sweeps at 0.5 / 1.25 / 2.0 s.
function Life:OnRegenDisabled()
    if not Life.armedCombat then return nil, "unarmed" end
    Life.lastCombatFlagAt = S():Now()
    Life.healthSuppressed = true               -- health path disabled while sweeps pend
    Life.pendingSweeps = #Life.SWEEP_DELAYS
    for _, d in ipairs(Life.SWEEP_DELAYS) do
        S():Schedule(d, sweepTask, Life, d)
    end
    S():Schedule(Life.HEALTH_REARM, function()
        Life.healthSuppressed = false
    end, Life)
    return true
end

function Life:OnRegenEnabled()
    Life.lastRegenEnabledAt = S():Now()
end

-- Build the creature-ID -> unit-ID snapshot: every group member's target, plus
-- every active nameplate that is UnitAffectingCombat.
--   delay > 0 : the matched mob must be UnitAffectingCombat AND must not be a group
--               member or a group member's pet (guards against a hunter pet being
--               mistaken for the boss).
--   delay = 0 : (the chat-message path for world bosses) requires only that the mob
--               is somebody's target.
function Life:BuildCreatureMap(delay)
    local map = {}
    local strict = (delay or 0) > 0
    local function consider(unit)
        if not Life.env.UnitExists(unit) then return false end
        if strict then
            if not Life.env.UnitAffectingCombat(unit) then return false end
            if Life.env.IsGroupUnit(unit) then return false end
        end
        local cid = Life:CreatureIdOfUnit(unit)
        if cid and map[cid] == nil then map[cid] = unit end
        return false
    end
    Life.env.ForEachGroupMember(function(u) return consider(u .. "target") end)
    Life.env.ForEachNameplate(function(u)
        if Life.env.UnitAffectingCombat(u) then consider(u) end
        return false
    end)
    return map
end

-- W4a: the sweep now carries WHY it was scheduled. Outdoors, a boss yell does not
-- engage directly (§2.1(d)) — it schedules a delay-0 sweep — so without this the
-- resulting engagement would report trigger "sweep" and the fact that a YELL pulled
-- the fight would be lost. Lord Kazzak's berserk bar is conditional on exactly that
-- fact (§9.2), and §2.3 step 10's startedByMessage hook wants the same answer.
-- AUDIT RML-1 (Brief G, lesson Class 8). The sweep used to walk `map` with pairs()
-- and accumulate `started = started or Life:StartCombat(...)`. Two defects in one
-- line: the WALK ORDER was a hash accident, and `or` short-circuits, so once ANY
-- encounter started, every remaining matched encounter was silently skipped —
-- meaning "which encounter wins a multi-creature pull" was decided by table
-- lifetime. In Naxxramas' Four Horsemen chamber and AQ40's twin-boss rooms that is
-- the difference between the right module arming and the wrong one.
--
-- The rule is now STATED: sort the matched creature ids ascending and take the
-- FIRST encounter that successfully starts. Lowest creature id wins. It is
-- arbitrary in the sense that any total order would do, but it is a rule — the
-- same raid, the same pull, the same winner, every time and on every client.
--
-- The short-circuit is KEPT deliberately (one sweep starts one encounter, which is
-- the §2.1(c) contract) — what changed is that the winner is chosen rather than
-- raced. `Life.PREFER_TARGETED` lets a caller override the tiebreak with "the mob
-- the player is actually looking at", which is the answer a human would give.
function Life:SweepOrder(map)
    local cids = {}
    for cid in pairs(map) do cids[#cids + 1] = cid end
    table.sort(cids)
    -- The player's own target outranks the numeric order when it is in the map:
    -- if the raid is looking at Thane Korth'azz, Thane Korth'azz is the pull.
    if Life.PREFER_TARGETED then
        local tcid = Life:CreatureIdOfUnit("target")
        if tcid and map[tcid] then
            for i, cid in ipairs(cids) do
                if cid == tcid then table.remove(cids, i); table.insert(cids, 1, cid) break end
            end
        end
    end
    return cids
end

function Life:Sweep(delay, onlyEncId, trigger)
    if Life.pendingSweeps > 0 then Life.pendingSweeps = Life.pendingSweeps - 1 end
    local map = Life:BuildCreatureMap(delay)
    local started
    for _, cid in ipairs(Life:SweepOrder(map)) do
        local unit = map[cid]
        local list = Addon.encByCreature[cid]
        if list then
            for _, enc in ipairs(list) do
                local skip = (onlyEncId and enc.id ~= onlyEncId)
                    or (enc.detect and enc.detect.noRegenSweep)
                -- A module may declare "don't engage friendly units", which vetoes
                -- this path if the matched unit is friendly.
                if not skip and enc.detect and enc.detect.noFriendlyEngage
                   and Life.env.UnitIsFriend("player", unit) then
                    skip = true
                end
                if not skip and not started then
                    started = Life:StartCombat(enc, delay, trigger or "sweep")
                end
            end
        end
        if started then break end
    end
    return started
end

-- (d) Chat trigger. INSIDE an instance the match alone starts combat; OUTDOORS it
-- instead triggers a delay-0 target sweep (so a yell heard across a zone does not
-- engage the mod for someone who is not there).
local CHAT_KIND = {
    CHAT_MSG_MONSTER_YELL  = "yell",
    CHAT_MSG_MONSTER_SAY   = "say",
    CHAT_MSG_MONSTER_EMOTE = "emote",
    CHAT_MSG_RAID_BOSS_EMOTE = "emote",
    RAID_BOSS_EMOTE        = "emote",
}
Life.CHAT_KIND = CHAT_KIND

local function anyExact(list, text)
    if not list then return false end
    for _, s in ipairs(list) do if s == text then return true end end
    return false
end
local function anyFind(list, text)
    if not list then return false end
    for _, s in ipairs(list) do if text:find(s, 1, true) then return true end end
    return false
end
local function anyPattern(list, text)
    if not list then return false end
    for _, s in ipairs(list) do if text:match(s) then return true end end
    return false
end

function Life:ChatMatches(enc, kind, text)
    local d = enc.detect or {}
    if kind == "yell" then
        return anyExact(d.yell, text) or anyFind(d.yellFind, text) or anyPattern(d.yellPattern, text)
    elseif kind == "say" then
        return anyExact(d.say, text) or anyFind(d.sayFind, text) or anyPattern(d.sayPattern, text)
    elseif kind == "emote" then
        return anyExact(d.emote, text) or anyFind(d.emoteFind, text) or anyPattern(d.emotePattern, text)
    end
    return false
end

-- W4b extension 25: THE RP PULL COUNTDOWN. Some fights announce themselves a known
-- interval before combat can start — Vaelastrasz's forced dialogue is 43.5 seconds of
-- standing still — and the right surface for "combat starts in N" already exists
-- (§11.4's pull timer). This is a DETECTION-side rule, not an encounter runtime one:
-- nothing is engaged yet, so there is no runtime to route a trigger into.
function Life:PullCountdownMatches(enc, kind, text)
    local pc = enc.detect and enc.detect.pullCountdown
    if not pc then return nil end
    local hit
    if kind == "yell" then hit = anyExact(pc.yell, text) or anyFind(pc.yellFind, text)
    elseif kind == "say" then hit = anyExact(pc.say, text) or anyFind(pc.sayFind, text)
    elseif kind == "emote" then hit = anyExact(pc.emote, text) or anyFind(pc.emoteFind, text) end
    return hit and pc or nil
end

-- The shared arming rule, lifted out of OnChat so the chat source and W4a's death
-- source cannot drift apart: only inside the instance, only when nothing is already
-- engaged, and only once per throttle window (the RP repeats on every attempt).
function Life:ArmPullCountdown(enc, pc)
    if not (pc and Life:InInstance()) then return false end
    if Life:AnyEngaged() then return false end
    if type(Addon.StartPullTimer) ~= "function" then return false end
    local last = Life.pullCountdownAt and Life.pullCountdownAt[enc.id]
    if last and (S():Now() - last) <= (pc.throttle or pc.seconds) then return false end
    Life.pullCountdownAt = Life.pullCountdownAt or {}
    Life.pullCountdownAt[enc.id] = S():Now()
    pcall(Addon.StartPullTimer, Addon, pc.seconds, pc.source or "encounter", enc.name)
    return true
end

-- W4a extension 29. Some RP windows are measured from a MOB DYING rather than from a
-- line of chat — Ragnaros's raid stands still for 73 seconds after Majordomo dies,
-- and the spec names no yell for it. Same surface (§11.4's pull timer), same guards,
-- one more admissible event.
function Life:PullCountdownFromDeath(creatureId)
    if creatureId == nil then return 0 end
    if Life:AnyEngaged() then return 0 end
    local armed = 0
    for _, enc in ipairs(Addon.encounters) do
        local pc = enc.detect and enc.detect.pullCountdown
        local want = pc and pc.creatureDeath
        if want then
            local hit = false
            if type(want) == "table" then
                for _, cid in ipairs(want) do if cid == creatureId then hit = true break end end
            else
                hit = (want == creatureId)
            end
            if hit and Life:ArmPullCountdown(enc, pc) then armed = armed + 1 end
        end
    end
    return armed
end

function Life:OnChat(event, text)
    local kind = CHAT_KIND[event] or event
    text = text or ""
    local acted = 0
    for _, enc in ipairs(Addon.encounters) do
        local pc = Life:PullCountdownMatches(enc, kind, text)
        if pc and Life:ArmPullCountdown(enc, pc) then acted = acted + 1 end
        if Life:ChatMatches(enc, kind, text) then
            if Life:InInstance() then
                if Life:StartCombat(enc, 0, "chat") then acted = acted + 1 end
            else
                S():Schedule(0, sweepTask, Life, 0, enc.id, "chat")
                acted = acted + 1
            end
        end
    end
    -- Chat is also a trigger source INSIDE a running fight (emote state machines,
    -- add-wave yells, class calls).
    local chatEv = { on = kind == "emote" and "emote" or kind, text = text }
    for i = 1, #Life.engaged do
        Life.engaged[i]:Route(chatEv)
    end
    for _, rt in pairs(Life.zoneArmed) do rt:Route(chatEv) end
    return acted
end

-- (e) UNIT_HEALTH_FREQUENT on a boss creature.
function Life:OnUnitHealth(unit)
    if not Life:HealthArmed() then return nil, "unarmed" end
    if not Life.env.UnitExists(unit) then return nil, "no_unit" end
    local cid = Life:CreatureIdOfUnit(unit)
    if not cid then return nil, "not_a_creature" end
    local list = Addon.encByCreature[cid]
    if not list then return nil, "unregistered" end
    -- no cached health entry may exist yet for that creature ID
    if Life.healthCache[cid] ~= nil then return nil, "cached" end
    if not Life.env.UnitAffectingCombat(unit) then return nil, "not_in_combat" end
    if Life.env.IsGroupUnit(unit) then return nil, "group_unit" end
    local pct = Life:HealthPct(unit)
    if not pct then return nil, "no_health" end
    -- health below 2 % is ignored outright
    if pct < Life.HEALTH_IGNORE_PCT then return nil, "below_two_percent" end

    local delay
    if pct > Life.HEALTH_HIGH_PCT then
        delay = Life.HEALTH_HIGH_DELAY
    else
        local since = Life.lastCombatFlagAt and (S():Now() - Life.lastCombatFlagAt) or Life.HEALTH_MAX_DELAY
        delay = since < Life.HEALTH_MAX_DELAY and since or Life.HEALTH_MAX_DELAY
    end
    for _, enc in ipairs(list) do
        if not (enc.detect and enc.detect.noHealthStart) then
            local rt = Life:StartCombat(enc, delay, "health")
            if rt then return rt end
        end
    end
    return nil, "opted_out"
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §2.4 WIPE DETECTION — poll + confirmation
-- ══════════════════════════════════════════════════════════════════════════════
function Life:ClassifyWipe(rt)
    local d = rt.difficulty or {}
    -- Row 1: scenario-type content, or difficulty index 11 / 12 / 208.
    if d.instanceType == "scenario" or Life.NO_WIPE_DIFFICULTY[d.id or -1] then
        return V.NOT_WIPE_TRIVIAL
    end
    -- Row 2: IsEncounterInProgress() is true.
    if Life.env.IsEncounterInProgress() then return V.NOT_WIPE_ENCOUNTER_PROGRESS end
    -- Row 3: world-boss difficulty AND the player is dead or a ghost.
    if d.worldBoss and Life.env.UnitIsDeadOrGhost("player") then
        return V.NOT_WIPE_WORLDBOSS_DEATH
    end
    -- Row 4 (type 2): boss units were confirmed to exist at some point during this
    -- fight AND instance type is `raid` AND none of boss1..boss10 currently exists.
    if rt.bossSeen and d.instanceType == "raid" and not Life.env.AnyBossUnit() then
        return V.WIPE_BOSS_GONE
    end
    -- Row 5 (type 1): otherwise, no group member is simultaneously
    -- UnitAffectingCombat AND not dead-or-ghost. This single test absorbs feign
    -- death, vanish, pets, and spirit release.
    local alive = Life.env.ForEachGroupMember(function(u)
        if Life.env.UnitAffectingCombat(u) and not Life.env.UnitIsDeadOrGhost(u) then
            return true
        end
        return false
    end)
    if alive then return V.NOT_WIPE_COMBAT_LIVE end
    return V.WIPE_NO_COMBATANT
end

function Life:WipeWindow(rt)
    local base = (rt.difficulty and rt.difficulty.worldBoss) and Life.WIPE_WINDOW_WORLDBOSS
                 or Life.WIPE_WINDOW
    local mod = rt.def.combat and rt.def.combat.wipeWindow
    if mod and mod > base then return mod end          -- "or a longer per-module value"
    return base
end

function Life:WipeCheck(rt)
    if not rt.engaged then return end
    local now = S():Now()
    local verdict = Life:ClassifyWipe(rt)
    local isWipe = (verdict == V.WIPE_BOSS_GONE or verdict == V.WIPE_NO_COMBATANT)

    if not isWipe then
        rt.lastValidCombat = now            -- every "not a wipe" pass stamps it
        if rt.confirming then
            rt.confirming = false
            if Addon.Telemetry then
                Addon.Telemetry.Write("lifecycle.verdict",
                    { enc = rt.id, verdict = verdict, reason = "recovered" })
            end
        end
    else
        if not rt.confirming then
            rt.confirming = true
            rt.confirmStartedAt = now
            if Addon.Telemetry then
                Addon.Telemetry.Write("lifecycle.verdict", { enc = rt.id, verdict = verdict })
            end
        end
        if (now - rt.lastValidCombat) > Life:WipeWindow(rt) then
            Addon:FireEngineEvent("ENGINE_WIPE_VERDICT", rt.id, verdict, false)
            return Life:EndCombat(rt, true, verdict)
        end
    end
    Addon:FireEngineEvent("ENGINE_WIPE_VERDICT", rt.id, verdict, rt.confirming)
    S():Schedule(Life.WIPE_POLL, wipeTask, Life, rt)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §2.5 KILL DETECTION — four independent paths
-- ══════════════════════════════════════════════════════════════════════════════
function Life:OnUnitDied(creatureId)
    -- W4a extension 29: a creature death may be the START of a pull countdown, not
    -- only the end of a fight. Checked FIRST and only while nothing is engaged, on
    -- the same guards the chat path uses (§2.1(d)).
    Life:PullCountdownFromDeath(creatureId)
    local ended = 0
    for i = #Life.engaged, 1, -1 do
        local rt = Life.engaged[i]
        local enc = rt.def
        local c = enc.combat or {}
        if not c.noDeathKill then
            local killSet = enc.killCreatureIds or enc.creatureIds
            local matched = false
            for _, cid in ipairs(killSet) do if cid == creatureId then matched = true break end end
            if matched then
                rt.down = rt.down or {}
                rt.down[creatureId] = true
                Addon:FireEngineEvent("SYNC_SEND", "K", creatureId, rt.difficulty and rt.difficulty.id)
                -- "several creature IDs, one boss": death never ends combat by itself.
                if not c.severalCreatureIdsOneBoss then
                    local all = true
                    for _, cid in ipairs(killSet) do if not rt.down[cid] then all = false break end end
                    if all then
                        -- W4b extension 24: THE KILL-STAGE GATE. Razorgore dies in phase 1
                        -- every time somebody drops the orb, and that is a wipe, not a
                        -- kill — the mod has to decide for itself because Blizzard's
                        -- encounter event is wrong for this fight (which is why the same
                        -- encounter also sets `noEncounterEndKill`). Expressed as the rule
                        -- it actually is rather than as the decoy-creature trick, so a
                        -- reader of the data can see WHY the death did not count.
                        local minStage = c.killMinStage
                        if minStage and rt.stage < minStage then
                            Life:EndCombat(rt, true, "died_before_stage")
                        else
                            Life:EndCombat(rt, false, "unit_died")
                        end
                        ended = ended + 1
                    end
                end
            end
        end
    end
    return ended
end

function Life:OnEncounterEnd(encounterId, success)
    local list = Addon.encByEncounterId[encounterId]
    if not list then return 0 end
    local ended = 0
    for _, enc in ipairs(list) do
        local rt = Life.byId[enc.id]
        if rt and not (enc.combat and enc.combat.noEncounterEndKill) then
            Addon:FireEngineEvent("SYNC_SEND", "EE", encounterId, success, enc.id)
            if success == 1 or success == true then
                Life:EndCombat(rt, false, "encounter_end"); ended = ended + 1
            end
        end
    end
    return ended
end

function Life:OnBossKill(encounterId)
    local list = Addon.encByEncounterId[encounterId]
    if not list then return 0 end
    local ended = 0
    for _, enc in ipairs(list) do
        local rt = Life.byId[enc.id]
        if rt and not (enc.combat and enc.combat.noBossKill) then
            Life:EndCombat(rt, false, "boss_kill"); ended = ended + 1
        end
    end
    return ended
end

function Life:OnKillMessage(kind, text)
    local ended = 0
    for i = #Life.engaged, 1, -1 do
        local rt = Life.engaged[i]
        local km = rt.def.combat and rt.def.combat.killMessage
        if km and (km.type == kind) and anyExact(km.text, text) then
            Life:EndCombat(rt, false, "kill_message"); ended = ended + 1
        end
    end
    return ended
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §2.6 END
-- ══════════════════════════════════════════════════════════════════════════════
function Life:EndCombat(rt, wiped, cause)
    if not rt.engaged then return nil end
    local now = S():Now()
    local duration = now - rt.pullTime
    rt.engaged = false

    for i = #Life.engaged, 1, -1 do
        if Life.engaged[i] == rt then table.remove(Life.engaged, i) end
    end
    Life.byId[rt.id] = nil

    S():CancelLoop(rt.healthLoop)
    S():Unschedule(wipeTask, Life, rt)

    -- In-combat events are unregistered immediately, EXCEPT aura-removed events,
    -- which are unregistered on a 2 s delay so trailing debuff-fade triggers still
    -- resolve. A full timer stop is scheduled at +3 s to sweep up bars started by
    -- events that arrived after the end, and the module's combat-end hook runs
    -- again at +3 s to close accidentally-shown frames.
    rt.auraGrace = true
    S():Schedule(Life.AURA_TEARDOWN_DELAY, function() rt.auraGrace = false end, Life)
    S():Schedule(Life.TIMER_SWEEP_DELAY, function()
        rt:Teardown()
        API().StopSpecials(rt.def, rt, wiped)
    end, Life)

    -- ATTEMPT ACCOUNTING (§2.6): a wipe under 30 s decrements the pull counter — it
    -- was not a real attempt — and is reported without adding to the wipe tally.
    local counted = true
    if wiped and duration < Life.MIN_ATTEMPT then counted = false end

    -- All reporting uses the ENGAGE-TIME difficulty snapshot, never the current one
    -- (§10.8: Classic corrupts live difficulty data after a release).
    local report = {
        enc = rt.id, wiped = wiped and true or false, cause = cause,
        duration = duration, difficulty = rt.difficulty,
        bossPct = rt.bossPct or rt.engagedAtPct,
        counted = counted, recordEligible = rt.recordEligible,
    }
    rt.report = report

    if wiped then
        if counted then Life.stats.wipes = Life.stats.wipes + 1 end
        Life:SetLockout(rt.id, "wipe")
    else
        Life.stats.kills = Life.stats.kills + 1
        Life:SetLockout(rt.id, "kill")
    end
    Life:RecordStats(rt, report)

    Addon:FireEngineEvent("ENGINE_END", rt.id, rt, report.wiped, duration, report.bossPct)

    if not Life:AnyEngaged() then
        Addon.active = nil
        for k in pairs(Life.healthCache) do Life.healthCache[k] = nil end
        Life.bossSeen = false
        S():Schedule(Life.LOG_STOP_DELAY, function()
            Addon:FireEngineEvent("ENGINE_LOG_STOP")
        end, Life)
        S():Schedule(Life.MUSIC_RESTART_DELAY, function()
            Addon:FireEngineEvent("ENGINE_MUSIC_RESTART")
        end, Life)
    end
    return report
end

-- Kill counter clamped so kills can never exceed pulls; a stale best-time under
-- 1.5 s is treated as corrupt and overwritten (§2.6).
function Life:RecordStats(rt, report)
    if type(Addon.GetBossStats) ~= "function" then return nil end
    local legacy = rt.def.legacy
    if not legacy then return nil end
    local okc, s = pcall(Addon.GetBossStats, Addon, legacy.raidId, legacy.bossId)
    if not okc or type(s) ~= "table" then return nil end
    if report.counted then s.pulls = (s.pulls or 0) + 1 end
    if not report.wiped then
        s.kills = (s.kills or 0) + 1
        if s.pulls and s.kills > s.pulls then s.kills = s.pulls end
        s.lastTime = report.duration
        if report.recordEligible then
            if not s.bestTime or s.bestTime < 1.5 or report.duration < s.bestTime then
                s.bestTime = report.duration
            end
        end
        s.lastResult = "kill"
    else
        if report.counted then s.wipes = (s.wipes or 0) + 1 end
        s.lastResult = "wipe"
    end
    return s
end

-- Bind the scheduler shims now that both methods exist.
function sweepTask(delay, encId, trigger) return Life:Sweep(delay, encId, trigger) end
function wipeTask(rt) return Life:WipeCheck(rt) end

-- ══════════════════════════════════════════════════════════════════════════════
--  EVENT INGEST
-- ══════════════════════════════════════════════════════════════════════════════
Life.EVENTS = {
    "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL",
    "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "UNIT_HEALTH_FREQUENT",
    "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_EMOTE",
    "CHAT_MSG_RAID_BOSS_EMOTE", "RAID_BOSS_EMOTE",
    "COMBAT_LOG_EVENT_UNFILTERED",
    -- W4d: the nameplate path. `nameplate` was already in the trigger vocabulary and
    -- nothing delivered one, so Kel'Thuzad's Era-only phase-2 detection ("his
    -- nameplate appears while still in phase 1") and Razuvious's understudy discovery
    -- were declarable but dead. Nameplates are also the only Era route to either.
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    -- W4a DEFECT FIX B. `unitCast` (§1.6's "unit-cast channel") has been in the
    -- trigger vocabulary since wave 1 and NOTHING EVER REGISTERED THE EVENT, so every
    -- row written against it was dead on arrival: Maexxna's spiderlings, Sapphiron's
    -- air phase, Viscidus, Venoxis, Arlokk — and now Ragnaros's submerge visual and
    -- Ysondre's Lightning Wave. It is the only witness for casts Era omits from the
    -- combat log entirely, which is exactly why those encounters reach for it.
    "UNIT_SPELLCAST_SUCCEEDED",
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "LOADING_SCREEN_DISABLED",
}

-- ENGINE SPEC §8.6: the Era unit-event token set. UNIT_HEALTH is explicitly
-- avoided ("slow and less reliable" on Classic) and there is NO focus token.
Life.HEALTH_TOKENS = { "mouseover", "target", "player", "targettarget" }

-- Normalise a raw combat-log payload into the flat event table the encounter
-- runtime routes on. Deliberately separate from `Deliver`, so the harness can feed
-- normalised events without reconstructing CLEU argument order.
-- COMBATLOG_OBJECT_TYPE_PET. W4d: `tr.source == "pet"` was in the matcher from wave 1
-- but nothing ever SET `sourceIsPet`, so it could not match. Razuvious needs it — a
-- mind-controlled Deathknight Understudy counts as a pet, which is how its Taunt and
-- Shield Wall are attributed. Pure arithmetic, because `bit` is not guaranteed.
local OBJECT_TYPE_PET = 0x00001000
local function isPetFlags(flags)
    if type(flags) ~= "number" then return false end
    return math.floor(flags / OBJECT_TYPE_PET) % 2 == 1
end
Life.IsPetFlags = isPetFlags

function Life:NormalizeCLEU(subevent, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
                            destGUID, destName, destFlags, destRaidFlags, a1, a2, a3, a4)
    local ev = {
        on = subevent,
        sourceGUID = sourceGUID, sourceName = sourceName,
        destGUID = destGUID, destName = destName,
        sourceId = Life.CreatureIdFromGUID(sourceGUID),
        destId   = Life.CreatureIdFromGUID(destGUID),
    }
    if subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
        -- §8.2: dest fields are mirrored into source fields so a handler can read either.
        ev.sourceGUID, ev.sourceName, ev.sourceId = destGUID, destName, ev.destId
        ev.creatureId = ev.destId
    elseif subevent:sub(1, 6) == "SPELL_" then
        ev.spellId, ev.spellName = a1, a2
        if subevent:find("AURA") then
            -- §8.2: stack count defaults to 1 when the client omits it.
            ev.amount = a4 or 1
            if sourceGUID == nil or sourceGUID == "" then
                ev.sourceGUID, ev.sourceName, ev.sourceId = destGUID, destName, ev.destId
            end
        else
            ev.school = a3
            -- W4c: the miss sub-events put the miss TYPE where damage puts its amount.
            -- The Anubisath reflect buffs are not reliably visible on Era, so
            -- "REFLECT/DEFLECT + this school" is the only evidence a reflect happened.
            if subevent == "SPELL_MISSED" or subevent == "SPELL_PERIODIC_MISSED"
               or subevent == "RANGE_MISSED" then
                ev.missType = a4
            end
        end
    elseif subevent == "SWING_MISSED" then
        ev.missType = a1
    end
    local pg = Life.env.UnitGUID("player")
    ev.destIsPlayer   = (pg ~= nil and destGUID == pg)
    ev.sourceIsPlayer = (pg ~= nil and sourceGUID == pg)
    ev.sourceIsPet    = isPetFlags(sourceFlags)
    ev.destIsPet      = isPetFlags(destFlags)
    return ev
end

-- Deliver a normalised event to every engaged encounter, then to the legacy
-- combat hooks (the special-module escape hatch, verbatim signature).
function Life:Deliver(ev)
    local acted = 0
    for i = 1, #Life.engaged do
        acted = acted + Life.engaged[i]:Route(ev)
    end
    for _, rt in pairs(Life.zoneArmed) do acted = acted + rt:Route(ev) end
    -- W4a DEFECT FIX A. §2.5's death-based kill path was reachable only from a
    -- corroborated `K` sync and from the harness — the live combat-log path routed
    -- UNIT_DIED to encounter rows and stopped. Razorgore, which refuses Blizzard's
    -- ENCOUNTER_END outright, therefore had NO working kill detection in game. Routed
    -- AFTER the rows so a row that reacts to the death (a census counter, an add
    -- tracker) still sees it before the runtime can be torn down.
    if ev.on == "UNIT_DIED" and (ev.destId or ev.creatureId) then
        Life:OnUnitDied(ev.destId or ev.creatureId)
    end
    if ev.on and ev.on:sub(1, 6) ~= "SPELL_" and ev.on ~= "UNIT_DIED" then return acted end
    Addon:FireCombatHooks(ev.on, ev.sourceGUID, ev.sourceId, ev.destGUID, ev.destId,
                          ev.spellId, ev.spellName)
    return acted
end

function Life:OnEvent(event, ...)
    if event == "ENCOUNTER_START" then
        local encounterId = ...
        return Life:OnEncounterStart(encounterId)
    elseif event == "ENCOUNTER_END" then
        local encounterId, _, _, _, success = ...
        return Life:OnEncounterEnd(encounterId, success)
    elseif event == "BOSS_KILL" then
        local encounterId = ...
        return Life:OnBossKill(encounterId)
    elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        return Life:OnEngageUnit()
    elseif event == "PLAYER_REGEN_DISABLED" then
        return Life:OnRegenDisabled()
    elseif event == "PLAYER_REGEN_ENABLED" then
        return Life:OnRegenEnabled()
    elseif event == "UNIT_HEALTH_FREQUENT" then
        local unit = ...
        return Life:OnUnitHealth(unit)
    elseif CHAT_KIND[event] then
        local text = ...
        return Life:OnChat(event, text)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        return Life:Deliver(Life:NormalizeCLEU(...))
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- W3 SEAM (§9.1). W1 registered this event but had no handler; the reload
        -- recovery cascade needs exactly one fact the engine already knows — "we just
        -- came back, and this is whether it was a fresh login or a /reload". The
        -- lifecycle publishes it and takes no action of its own; core_sync.lua owns
        -- the cascade, so the engine core stays free of comms.
        local isLogin, isReload = ...
        Life.enteredWorldAt = S():Now()
        Life:ArmZones()                     -- W4d: zoning in arms the trash module
        Addon:FireEngineEvent("ENGINE_LOGIN", isLogin and true or false, isReload and true or false)
        return true
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- W4a DEFECT FIX B. A unit event with no unit filter fires for every caster in
        -- the raid, so this is gated hard: nothing listening, nothing parsed; and a
        -- unit with no creature id is a player, which this channel exists to ignore.
        if #Life.engaged == 0 and next(Life.zoneArmed) == nil then return nil end
        local unit, _, spellId = ...
        if type(unit) ~= "string" then return nil, "no_unit" end
        local cid = Life:CreatureIdOfUnit(unit)
        if not cid then return nil, "not_a_creature" end
        return Life:Deliver({ on = "unitCast", unit = unit, spellId = spellId,
                              creatureId = cid, sourceId = cid,
                              sourceGUID = Life.env.UnitGUID(unit),
                              sourceName = Life.env.UnitName and Life.env.UnitName(unit) })
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        -- Hot event: skip the GUID parse entirely when nothing is listening.
        if #Life.engaged == 0 and next(Life.zoneArmed) == nil then return nil end
        local unit = ...
        local cid = Life:CreatureIdOfUnit(unit)
        if not cid then return nil, "not_a_creature" end
        return Life:Deliver({ on = "nameplate", unit = unit, creatureId = cid,
                              sourceId = cid, sourceGUID = Life.env.UnitGUID(unit) })
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        return nil
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "LOADING_SCREEN_DISABLED" then
        Life.zoneAt = S():Now()
        Life:ArmZones()                     -- W4d: (dis)arm this instance's trash module
        Addon:FireEngineEvent("ENGINE_ZONE")
        return true
    end
    return nil
end

-- ENGINE SPEC §9.4: a hard disable force-ends every engaged encounter FIRST
-- (because tearing down the scheduler would otherwise strand wipe detection),
-- then flushes the scheduler and clears every lockout timestamp.
function Life:Disable()
    for i = #Life.engaged, 1, -1 do Life:EndCombat(Life.engaged[i], true, "disabled") end
    Life:DisarmZones()
    if Addon.Timers then Addon.Timers.StopAll("disabled") end
    S():Flush()
    for k in pairs(Life.lockouts) do Life.lockouts[k] = nil end
    for k in pairs(Life.healthCache) do Life.healthCache[k] = nil end
    Addon.active = nil
    return true
end

-- Full reset used by the harness between fixtures (and by /reload paths).
function Life:Reset()
    Life:Disable()
    Life.armedCombat, Life.armedHealthBoot, Life.healthSuppressed = false, false, false
    Life.lastCombatFlagAt, Life.pendingSweeps, Life.bossSeen = nil, 0, false
    Life.recoveringUntil = nil
    Life.pullCountdownAt = nil          -- W4b extension 25
    Life.stats = { engages = 0, kills = 0, wipes = 0, rejected = 0 }
    return true
end

return Life
