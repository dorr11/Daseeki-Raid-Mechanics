--[[
    Daseeki Raid Mechanics 2.0 — encounter-mod API + engine dispatch seam
    (engine core, wave 1)

    Design doc, target-architecture item 8: "Encounter-mod API: declarative tables
    (the ClassHUD displays-registry lesson: sources/conditions/presentation as data),
    with an escape hatch to registered special modules (the Naxx five)."

    TWO HALVES:

    A. THE OUTBOUND DISPATCH SEAM (`Addon:FireEngineEvent`). ENGINE SPEC §11.8 —
       the external callback surface is "more load-bearing than it looks". Every
       engine decision leaves through it. W2 hangs presentation off it, W3 hangs
       sync off it, the harness hangs a recorder off it. Callbacks run inside a
       pcall so a misbehaving consumer cannot break the engine.

    B. THE DECLARATIVE ENCOUNTER GRAMMAR (`Addon:RegisterEncounter`). Data in,
       engine services out. The grammar is sized against DBM_ERA_ENCOUNTERS_
       BEHAVIOR_SPEC.md so that NO encounter in that document is inexpressible:
         variance + pull-vs-cd + per-stage + alternating-sequence + hard-coded-cycle
         timer values;  phase machinery incl. half-stages, stage totality, health
         thresholds and the "encounter in progress" poll;  target-scan declarations
         in all three scanner shapes;  emote state machines;  stack / census /
         rate counters;  ship-off defaults, role gates and dynamic class defaults;
         and a REGISTERED-SPECIAL-MODULE ESCAPE HATCH for everything that refuses
         to be data.

    THE ESCAPE HATCH IS THE CONTRACT WITH W4d. The five shipped Naxx specials
    (mod_loatheb_healers, mod_fourhorsemen_rotation, mod_fourhorsemen_tracker,
    mod_gothik_waves, mod_razuvious_understudy, thaddius) are NOT touched by this
    wave. They call exactly three engine-owned surfaces:
        Addon:RegisterModule{...}   -- modules.lua, unchanged
        Addon:RegisterCombatHook(fn) with signature
            fn(subevent, sourceGUID, sourceID, destGUID, destID, spellID, spellName)
        Addon.active = { raidId, bossId, boss, startTime }
    All three are preserved VERBATIM here. The ONLY seam W4d adds is a `legacy =
    { raidId=, bossId= }` field on the encounter definition, which tells the engine
    which legacy module bucket to Start/Stop on engage/end.
--]]

local _, Addon = ...

local API = {}
Addon.API = API

-- ══════════════════════════════════════════════════════════════════════════════
--  A. DISPATCH SEAM (ENGINE SPEC §11.8)
-- ══════════════════════════════════════════════════════════════════════════════

Addon._engineCallbacks = {}     -- event -> ordered { fn, owner }
Addon._eventLog        = nil    -- headless recorder, off unless enabled
Addon.EVENT_LOG_MAX    = 4000

-- The published event vocabulary. W2/W3 build against exactly this list.
API.EVENTS = {
    -- lifecycle
    "ENGINE_ENGAGE",        -- (encId, rt, delay, trigger)
    "ENGINE_END",           -- (encId, rt, wiped, duration, bossHpPct)
    "ENGINE_STAGE",         -- (encId, stage, totality)
    "ENGINE_WIPE_VERDICT",  -- (encId, verdict, confirming)
    "ENGINE_LOCKOUT",       -- (encId, reason, remaining)
    "ENGINE_LOGIN",         -- (isLogin, isReload)        -> W3 reload-recovery cascade (§9.1)
    -- timers
    "TIMER_START", "TIMER_UPDATE", "TIMER_STOP", "TIMER_PAUSE", "TIMER_RESUME",
    "TIMER_COUNTDOWN",      -- (barId, remainingCount, timer)
    -- warnings
    "WARN_ANNOUNCE",        -- (encId, row, text, ...)
    "WARN_SPECIAL",         -- (encId, row, text, ...)
    -- services other waves own
    "SCAN_REQUEST",         -- (encId, scanDecl, ctx)     -> W2 target scanners
    "ICON_REQUEST",         -- (encId, iconDecl, ctx)     -> W2 raid icons
    "SYNC_SEND",            -- (subPrefix, ...)           -> W3 addon channel, outbound
    "SYNC_RECV",            -- (subPrefix, sender, ...)   -> W3 addon channel, inbound
    "ENGINE_PULL",          -- (seconds, source, target)  -> W3 pull timer (§11.4)
    "ENGINE_BREAK",         -- (seconds, source)          -> W3 break timer (§11.4)
    "COUNTER",              -- (encId, key, value, delta)
    "STATE",                -- (encId, key, from, to)
    "TELEMETRY",            -- (entry)
}

local KNOWN_EVENT = {}
for _, e in ipairs(API.EVENTS) do KNOWN_EVENT[e] = true end

function Addon:RegisterEngineCallback(event, fn, owner)
    if type(fn) ~= "function" then return false end
    local list = Addon._engineCallbacks[event]
    if not list then list = {}; Addon._engineCallbacks[event] = list end
    list[#list + 1] = { fn = fn, owner = owner }
    return true
end

function Addon:UnregisterEngineCallback(event, fn)
    local list = Addon._engineCallbacks[event]
    if not list then return 0 end
    local n = 0
    for i = #list, 1, -1 do
        if list[i].fn == fn then table.remove(list, i); n = n + 1 end
    end
    return n
end

-- Headless / diagnostic recorder. Bounded; the harness reads it to prove the
-- engine drove the right decisions without needing any UI.
function Addon:SetEventRecording(on)
    Addon._eventLog = on and (Addon._eventLog or {}) or nil
    return Addon._eventLog
end

function Addon:GetEventLog() return Addon._eventLog end

function Addon:ClearEventLog()
    local l = Addon._eventLog
    if l then for i = #l, 1, -1 do l[i] = nil end end
end

function Addon:FireEngineEvent(event, ...)
    local log = Addon._eventLog
    if log then
        if #log >= Addon.EVENT_LOG_MAX then table.remove(log, 1) end
        log[#log + 1] = { event = event, n = select("#", ...), ... }
    end
    local list = Addon._engineCallbacks[event]
    if not list then return 0 end
    local fired = 0
    for i = 1, #list do
        local cb = list[i]
        local okc, err = pcall(cb.fn, event, ...)   -- secure-call wrapper, §11.8
        if okc then
            fired = fired + 1
        elseif Addon.Telemetry then
            Addon.Telemetry.Write("api.validate", { reason = "callback error", key = event,
                                                    detail = tostring(err) })
        end
    end
    return fired
end

-- ── Minimal alert dispatch seam (W1 scope: "drivable end-to-end headless") ─────
-- W2 replaces the fallbacks with the real HUD. Until then the engine still emits
-- a complete, assertable stream of warnings, and in-game it opportunistically
-- forwards to whatever alerts.lua already exposes.
function Addon:EmitAnnounce(encId, row, text)
    Addon:FireEngineEvent("WARN_ANNOUNCE", encId, row, text)
    if not Addon._suppressLegacyAlerts and type(Addon.ShowWarning) == "function" then
        pcall(Addon.ShowWarning, Addon, text, row and row.color)
    end
    return text
end

function Addon:EmitSpecial(encId, row, text)
    Addon:FireEngineEvent("WARN_SPECIAL", encId, row, text)
    if not Addon._suppressLegacyAlerts and type(Addon.ShowSpecialWarning) == "function" then
        pcall(Addon.ShowSpecialWarning, Addon, text, row and row.sound)
    end
    return text
end

-- ══════════════════════════════════════════════════════════════════════════════
--  B. THE DECLARATIVE ENCOUNTER GRAMMAR
-- ══════════════════════════════════════════════════════════════════════════════

-- Detection modes (ENCOUNTERS SPEC §1.1 + ENGINE SPEC §2.1). `combat` subscribes
-- to all generic paths; the message variants subscribe to chat triggers instead
-- of, or in addition to, the generic paths.
API.DETECT_MODES = {
    combat = true, yell = true, say = true, emote = true,
    yell_regex = true, say_regex = true, emote_regex = true,
    combat_yell = true, combat_say = true, combat_emote = true,
    combat_yellfind = true, combat_sayfind = true, combat_emotefind = true,
    zone = true,                    -- trash module: armed for a whole instance
}

-- Timer kinds. `cd/next/cast/active/fades/target/stage/intermission/adds/berserk`
-- cover every row in the encounters spec; `learning` is the self-teaching flavour
-- (ENGINE SPEC §4.6) and is exempt from the early-refresh tripwire.
API.TIMER_KINDS = {
    cd = "cd", next = "cd", cast = "cast", active = "cd", fades = "cd",
    target = "target", stage = "stage", intermission = "stage", adds = "cd",
    berserk = "berserk", combat = "cd", achievement = "cd", learning = "cd",
}

-- The simplified external categories every timer collapses into (§4.5), so
-- third-party consumers and our own bars agree.
API.SIMPLE_CATEGORIES = { cd = true, target = true, stage = true, cast = true,
                          ["break"] = true, pull = true, berserk = true,
                          cdnp = true, castnp = true }

-- Colour indices (§4.5): 1 add, 2 AoE, 3 targeted, 4 interrupt, 5 role, 6 stage, 7 user.
API.COLOR_MAX = 7

-- Trigger vocabulary. CLEU sub-events plus the engine's own synthetic sources.
API.TRIGGER_EVENTS = {
    -- combat log
    SPELL_CAST_START = true, SPELL_CAST_SUCCESS = true, SPELL_CAST_FAILED = true,
    SPELL_AURA_APPLIED = true, SPELL_AURA_REFRESH = true, SPELL_AURA_REMOVED = true,
    SPELL_AURA_APPLIED_DOSE = true, SPELL_AURA_REMOVED_DOSE = true,
    SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true, SPELL_MISSED = true,
    SPELL_PERIODIC_MISSED = true, SPELL_HEAL = true, SPELL_SUMMON = true,
    SPELL_INTERRUPT = true, SPELL_DISPEL = true, SWING_DAMAGE = true,
    RANGE_DAMAGE = true, UNIT_DIED = true, UNIT_DESTROYED = true,
    -- synthetic / non-CLEU
    pull = true, yell = true, say = true, emote = true, bossEmote = true,
    unitCast = true,        -- UNIT_SPELLCAST_SUCCEEDED channel (Gothik, Sapphiron, Ysondre)
    health = true,          -- boss-health threshold from the poll
    stage = true,           -- a stage transition
    schedule = true,        -- a pure schedule seeded at pull
    nameplate = true,       -- NAME_PLATE_UNIT_ADDED (KT phase 2, Razuvious understudies)
    targetChanged = true,   -- UNIT_TARGET
    unitDeath = true,       -- creature-id death (alias of UNIT_DIED with a creature filter)
    sync = true,            -- an incoming module sync (W3)
    state = true,           -- an emote state machine transition
    counter = true,         -- a counter threshold
    aura = true,            -- a unit-aura sweep result (Chromaggus/Thaddius icon reads)
}

-- Role gates (ENCOUNTERS SPEC §1.4). Compound gates use `|` as OR. The engine
-- stores them; W2's role resolver evaluates them.
API.ROLE_GATES = {
    Tank = true, Healer = true, Melee = true, ["-Melee"] = true, Dps = true,
    RangedDps = true, CasterDps = true, SpellCaster = true, ManaUser = true,
    ["-Healer"] = true, HasInterrupt = true, MagicDispeller = true,
    RemoveMagic = true, RemoveCurse = true, RemovePoison = true, RemoveEnrage = true,
}

API.SCAN_TYPES  = { poll = true, event = true, repeated = true }
API.COUNTER_SCOPES = { global = true, self = true, boss = true, census = true, target = true }
API.WARN_TIERS  = { announce = true, special = true }

-- ── Registry ──────────────────────────────────────────────────────────────────
Addon.encounters        = {}    -- ordered array
Addon.encountersById    = {}    -- id -> def
Addon.encByCreature     = {}    -- creatureId -> { def, ... }
Addon.encByEncounterId  = {}    -- encounterId -> { def, ... }
Addon.encByZone         = {}    -- instanceId -> { def, ... }

local function listify(v)
    if v == nil then return nil end
    if type(v) == "table" then return v end
    return { v }
end

local function addTo(map, key, def)
    local l = map[key]
    if not l then l = {}; map[key] = l end
    l[#l + 1] = def
end

-- ── Validation ────────────────────────────────────────────────────────────────
-- Never throws in-game: returns an error list and writes to the telemetry ring.
-- The harness asserts the list is empty for real data (and non-empty for the
-- deliberate bad fixtures).
local function validateTrigger(errs, where, tr)
    if type(tr) ~= "table" then errs[#errs + 1] = where .. ": trigger must be a table"; return end
    if tr.on == nil then errs[#errs + 1] = where .. ": trigger has no `on`"; return end
    if not API.TRIGGER_EVENTS[tr.on] then
        errs[#errs + 1] = where .. ": unknown trigger event '" .. tostring(tr.on) .. "'"
    end
end

local function validateRole(errs, where, role)
    if role == nil then return end
    if type(role) ~= "string" then errs[#errs + 1] = where .. ": role gate must be a string"; return end
    for tok in role:gmatch("[^|]+") do
        tok = tok:gsub("^%s+", ""):gsub("%s+$", "")
        if not API.ROLE_GATES[tok] then
            errs[#errs + 1] = where .. ": unknown role gate '" .. tok .. "'"
        end
    end
end

local function validateDuration(errs, where, v)
    if v == nil then return end
    local T = Addon.Timers
    if not T then return end                 -- timers module loads after us in headless slices
    if type(v) == "table" then
        for k, sub in pairs(v) do validateDuration(errs, where .. "[" .. tostring(k) .. "]", sub) end
        return
    end
    if not T.ParseDuration(v) then
        errs[#errs + 1] = where .. ": unparseable duration '" .. tostring(v) .. "'"
    end
end

function API.Validate(def)
    local errs = {}
    if type(def) ~= "table" then return { "encounter definition must be a table" } end
    if type(def.id) ~= "string" or def.id == "" then errs[#errs + 1] = "encounter needs a string id" end
    local d = def.detect or {}
    if d.mode and not API.DETECT_MODES[d.mode] then
        errs[#errs + 1] = "unknown detect.mode '" .. tostring(d.mode) .. "'"
    end
    if not def.creatureId and not def.encounterId and not (d.yell or d.yellFind or d.yellPattern
        or d.emote or d.emoteFind or d.say) then
        errs[#errs + 1] = def.id .. ": no creatureId, encounterId or chat trigger — nothing can start it"
    end

    local seen = {}
    local function rowKey(kind, row, i)
        local k = row.key
        if type(k) ~= "string" or k == "" then
            errs[#errs + 1] = ("%s: %s row %d has no key"):format(tostring(def.id), kind, i)
            return nil
        end
        if seen[k] then
            errs[#errs + 1] = ("%s: duplicate row key '%s'"):format(tostring(def.id), k)
        end
        seen[k] = true
        return k
    end

    for i, row in ipairs(def.timers or {}) do
        local where = ("%s.timers[%s]"):format(tostring(def.id), tostring(row.key or i))
        rowKey("timer", row, i)
        if row.kind and not API.TIMER_KINDS[row.kind] then
            errs[#errs + 1] = where .. ": unknown timer kind '" .. tostring(row.kind) .. "'"
        end
        validateDuration(errs, where .. ".duration", row.duration)
        validateDuration(errs, where .. ".pull", row.pull)
        validateDuration(errs, where .. ".phaseDuration", row.phaseDuration)
        validateRole(errs, where, row.role)
        if row.start then validateTrigger(errs, where .. ".start", row.start) end
        if row.restart then validateTrigger(errs, where .. ".restart", row.restart) end
        if row.stop then validateTrigger(errs, where .. ".stop", row.stop) end
        if row.color and (type(row.color) ~= "number" or row.color < 1 or row.color > API.COLOR_MAX) then
            errs[#errs + 1] = where .. ": colour index out of range 1.." .. API.COLOR_MAX
        end
    end

    for i, row in ipairs(def.warnings or {}) do
        local where = ("%s.warnings[%s]"):format(tostring(def.id), tostring(row.key or i))
        rowKey("warning", row, i)
        local tier = row.tier or "announce"
        if not API.WARN_TIERS[tier] then
            errs[#errs + 1] = where .. ": unknown warning tier '" .. tostring(tier) .. "'"
        end
        if tier == "announce" and row.color and (row.color < 1 or row.color > 4) then
            errs[#errs + 1] = where .. ": announce colour tier must be 1..4"
        end
        if tier == "special" and row.sound and (row.sound < 1 or row.sound > 5) then
            errs[#errs + 1] = where .. ": special sound tier must be 1..5"
        end
        validateRole(errs, where, row.role)
        if row.trigger then validateTrigger(errs, where .. ".trigger", row.trigger) end
        for j, tr in ipairs(row.triggers or {}) do
            validateTrigger(errs, where .. ".triggers[" .. j .. "]", tr)
        end
    end

    for i, row in ipairs(def.scans or {}) do
        local where = ("%s.scans[%s]"):format(tostring(def.id), tostring(row.key or i))
        rowKey("scan", row, i)
        if not API.SCAN_TYPES[row.type or "poll"] then
            errs[#errs + 1] = where .. ": unknown scan type '" .. tostring(row.type) .. "'"
        end
        if row.on then validateTrigger(errs, where .. ".on", row.on) end
    end

    for i, row in ipairs(def.counters or {}) do
        local where = ("%s.counters[%s]"):format(tostring(def.id), tostring(row.key or i))
        rowKey("counter", row, i)
        if not API.COUNTER_SCOPES[row.scope or "global"] then
            errs[#errs + 1] = where .. ": unknown counter scope '" .. tostring(row.scope) .. "'"
        end
        if row.inc then validateTrigger(errs, where .. ".inc", row.inc) end
        if row.dec then validateTrigger(errs, where .. ".dec", row.dec) end
    end

    for i, row in ipairs(def.phases or {}) do
        local where = ("%s.phases[%d]"):format(tostring(def.id), i)
        if row.stage == nil then errs[#errs + 1] = where .. ": phase row has no stage" end
        if row.on then validateTrigger(errs, where, row) end
    end

    for i, row in ipairs(def.states or {}) do
        local where = ("%s.states[%s]"):format(tostring(def.id), tostring(row.key or i))
        rowKey("state", row, i)
        for j, tr in ipairs(row.transitions or {}) do
            validateTrigger(errs, where .. ".transitions[" .. j .. "]", tr)
            if tr.to == nil then errs[#errs + 1] = where .. ".transitions[" .. j .. "]: no `to` state" end
        end
    end

    if def.special ~= nil and type(def.special) ~= "string" and type(def.special) ~= "table" then
        errs[#errs + 1] = tostring(def.id) .. ": `special` must be a module id or a list of them"
    end
    if def.legacy ~= nil then
        if type(def.legacy) ~= "table" or not def.legacy.raidId or not def.legacy.bossId then
            errs[#errs + 1] = tostring(def.id) .. ": `legacy` needs { raidId=, bossId= }"
        end
    end
    return errs
end

-- ── Compilation ───────────────────────────────────────────────────────────────
-- Builds a trigger index so runtime dispatch is a table lookup, not a linear
-- sweep of every row in the encounter.
local function indexTrigger(enc, tr, consumer)
    if type(tr) ~= "table" or tr.on == nil then return end
    local bucket = enc.index[tr.on]
    if not bucket then bucket = {}; enc.index[tr.on] = bucket end
    bucket[#bucket + 1] = { trigger = tr, consumer = consumer }
end

local function compile(enc)
    enc.index    = {}
    enc.rowsByKey = {}
    for _, row in ipairs(enc.timers or {}) do
        enc.rowsByKey[row.key] = row
        indexTrigger(enc, row.start,   { kind = "timer", row = row, act = "start" })
        indexTrigger(enc, row.restart, { kind = "timer", row = row, act = "restart" })
        indexTrigger(enc, row.stop,    { kind = "timer", row = row, act = "stop" })
    end
    for _, row in ipairs(enc.warnings or {}) do
        enc.rowsByKey[row.key] = row
        if row.trigger then indexTrigger(enc, row.trigger, { kind = "warning", row = row }) end
        for _, tr in ipairs(row.triggers or {}) do
            indexTrigger(enc, tr, { kind = "warning", row = row })
        end
    end
    for _, row in ipairs(enc.scans or {}) do
        enc.rowsByKey[row.key] = row
        if row.on then indexTrigger(enc, row.on, { kind = "scan", row = row }) end
    end
    for _, row in ipairs(enc.counters or {}) do
        enc.rowsByKey[row.key] = row
        if row.inc then indexTrigger(enc, row.inc, { kind = "counter", row = row, act = "inc" }) end
        if row.dec then indexTrigger(enc, row.dec, { kind = "counter", row = row, act = "dec" }) end
        if row.reset then indexTrigger(enc, row.reset, { kind = "counter", row = row, act = "reset" }) end
    end
    -- A phase row IS its own trigger, except that its `stage` field is the stage to
    -- MOVE TO, never a stage filter. Copy the row into a synthetic trigger with
    -- `stage`/`pre` stripped; a phase that should only fire while already in a given
    -- stage declares `whenStage` ("phase 3 soon at <= 48 % IN PHASE 2").
    for i, row in ipairs(enc.phases or {}) do
        local tr = {}
        for k, v in pairs(row) do
            if k ~= "stage" and k ~= "pre" and k ~= "whenStage" then tr[k] = v end
        end
        if row.whenStage ~= nil then tr.stage = row.whenStage end
        indexTrigger(enc, tr, { kind = "phase", row = row, act = i })
    end
    for _, row in ipairs(enc.states or {}) do
        enc.rowsByKey[row.key] = row
        for _, tr in ipairs(row.transitions or {}) do
            indexTrigger(enc, tr, { kind = "state", row = row, transition = tr })
        end
    end
    for _, row in ipairs(enc.icons or {}) do
        enc.rowsByKey[row.key] = row
        if row.on then indexTrigger(enc, row.on, { kind = "icon", row = row }) end
    end
    return enc
end

-- ── Registration ──────────────────────────────────────────────────────────────
function Addon:RegisterEncounter(def)
    local errs = API.Validate(def)
    if #errs > 0 then
        for _, e in ipairs(errs) do
            if Addon.Telemetry then
                Addon.Telemetry.Write("api.validate", { enc = def and def.id, reason = e })
            end
        end
        return nil, errs
    end

    def.detect  = def.detect  or {}
    def.combat  = def.combat  or {}
    def.timers  = def.timers  or {}
    def.warnings = def.warnings or {}
    def.scans   = def.scans   or {}
    def.phases  = def.phases  or {}
    def.counters = def.counters or {}
    def.states  = def.states  or {}
    def.icons   = def.icons   or {}
    def.schedule = def.schedule or {}
    def.creatureIds   = listify(def.creatureId) or {}
    def.encounterIds  = listify(def.encounterId) or {}
    def.zones         = listify(def.zone) or {}
    def.specials      = listify(def.special) or {}
    compile(def)

    if Addon.encountersById[def.id] then
        for i, e in ipairs(Addon.encounters) do
            if e.id == def.id then Addon.encounters[i] = def break end
        end
    else
        Addon.encounters[#Addon.encounters + 1] = def
    end
    Addon.encountersById[def.id] = def

    for _, cid in ipairs(def.creatureIds)  do addTo(Addon.encByCreature, cid, def) end
    for _, eid in ipairs(def.encounterIds) do addTo(Addon.encByEncounterId, eid, def) end
    for _, z   in ipairs(def.zones)        do addTo(Addon.encByZone, z, def) end
    return def, errs
end

function Addon:GetEncounter(id) return Addon.encountersById[id] end
function Addon:GetEncounters() return Addon.encounters end

-- Option key for a row. Everything user-facing (enable/disable, style, sound) is
-- addressed by this; W5's options surface and the SavedVariables overrides key on it.
function API.OptionKey(encId, rowKey) return tostring(encId) .. ":" .. tostring(rowKey) end

-- Ship-off defaults + role gate + dynamic class default (ENCOUNTERS SPEC §1.4).
-- The engine owns the DEFAULT decision; W2 supplies the live role/class resolvers.
Addon.RoleResolver  = nil   -- function(gateString) -> boolean
Addon.ClassResolver = nil   -- function() -> "WARLOCK" etc.

function API.RowDefault(row)
    if row.default ~= nil then return row.default and true or false end
    if row.classDefault then
        local f = Addon.ClassResolver
        if type(f) ~= "function" then return false end
        return f() == row.classDefault
    end
    if row.role then
        local f = Addon.RoleResolver
        if type(f) ~= "function" then return true end   -- no resolver yet: show it
        return f(row.role) and true or false
    end
    return true
end

function API.IsRowEnabled(encId, row)
    local db = Addon.db
    local key = API.OptionKey(encId, row.key)
    if db and type(db.mechanics) == "table" then
        local o = db.mechanics[key]
        if o and o.masterEnabled ~= nil then return o.masterEnabled and true or false end
    end
    return API.RowDefault(row)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  C. ENCOUNTER RUNTIME (one per engagement) — stage register, counters, states,
--     anti-spam, timer instances, and the trigger router.
-- ══════════════════════════════════════════════════════════════════════════════

local Runtime = {}
Runtime.__index = Runtime
API.Runtime = Runtime

function API.NewRuntime(def, ctx)
    local rt = setmetatable({}, Runtime)
    rt.def       = def
    rt.id        = def.id
    rt.stage     = 1
    rt.totality  = 0
    rt.counters  = {}
    rt.states    = {}
    rt.antispam  = {}
    rt.timers    = {}
    rt.healthFired = {}
    rt.engaged   = true
    rt.pullTime  = (ctx and ctx.pullTime) or (Addon.Sched and Addon.Sched:Now()) or 0
    rt.difficulty = ctx and ctx.difficulty
    rt.trigger   = ctx and ctx.trigger
    for _, row in ipairs(def.states) do rt.states[row.key] = row.initial or "initial" end
    for _, row in ipairs(def.counters) do rt.counters[row.key] = row.from or 0 end
    return rt
end

function Runtime:Now() return Addon.Sched:Now() end

-- ── Stage register (ENGINE SPEC §8.5) ─────────────────────────────────────────
-- Absolute number, or 0 to increment by one, or 0.5 to increment by a half.
-- A separate TOTALITY counter increments on every set. Setting a stage while not
-- engaged is silently ignored. Every set broadcasts.
function Runtime:SetStage(v)
    if not self.engaged then return false end
    if v == 0 then self.stage = self.stage + 1
    elseif v == 0.5 then self.stage = self.stage + 0.5
    else self.stage = v end
    self.totality = self.totality + 1
    Addon:FireEngineEvent("ENGINE_STAGE", self.id, self.stage, self.totality)
    return true
end

function Runtime:GetStage() return self.stage, self.totality end

-- Query API: equality / less-than / greater-than / not-equal against stage or totality.
function Runtime:StageIs(op, value, useTotality)
    local s = useTotality and self.totality or self.stage
    if op == "==" or op == "eq" then return s == value end
    if op == "<"  or op == "lt" then return s <  value end
    if op == ">"  or op == "gt" then return s >  value end
    if op == "~=" or op == "ne" then return s ~= value end
    if op == "<=" then return s <= value end
    if op == ">=" then return s >= value end
    return false
end

-- ── Anti-spam (ENCOUNTERS SPEC §1.6) ──────────────────────────────────────────
-- Returns true when the caller may proceed (i.e. the key is NOT throttled).
function Runtime:AntiSpam(key, seconds)
    if not seconds or seconds <= 0 then return true end
    local now = self:Now()
    local last = self.antispam[key]
    if last and (now - last) < seconds then return false end
    self.antispam[key] = now
    return true
end

-- ── Counters ──────────────────────────────────────────────────────────────────
function Runtime:Count(key, delta)
    local v = (self.counters[key] or 0) + (delta or 1)
    self.counters[key] = v
    Addon:FireEngineEvent("COUNTER", self.id, key, v, delta or 1)
    return v
end

function Runtime:GetCount(key) return self.counters[key] or 0 end

function Runtime:ResetCount(key, to)
    local row = self.def.rowsByKey and self.def.rowsByKey[key]
    self.counters[key] = to or (row and row.from) or 0
    Addon:FireEngineEvent("COUNTER", self.id, key, self.counters[key], 0)
    return self.counters[key]
end

-- ── State machines ────────────────────────────────────────────────────────────
function Runtime:SetState(key, to)
    local from = self.states[key]
    if from == to then return false end
    self.states[key] = to
    Addon:FireEngineEvent("STATE", self.id, key, from, to)
    return true
end

function Runtime:GetState(key) return self.states[key] end

-- ── Timer instances ───────────────────────────────────────────────────────────
function Runtime:Timer(key)
    local t = self.timers[key]
    if t then return t end
    local row = self.def.rowsByKey and self.def.rowsByKey[key]
    if not row or not Addon.Timers then return nil end
    t = Addon.Timers.New({
        id       = API.OptionKey(self.id, key),
        key      = key,
        encId    = self.id,
        kind     = row.kind or "cd",
        duration = row.duration,
        spellId  = type(row.spellId) == "table" and row.spellId[1] or row.spellId,
        text     = row.text, icon = row.icon, color = row.color,
        count    = row.count, allowDouble = row.allowDouble,
        keep     = row.keep, fade = row.fade,
        nameplate = row.nameplate,
        perTarget = row.perTarget,
        requiresCombat = row.requiresCombat,
        countdown = row.countdown,
        owner    = self,
    })
    self.timers[key] = t
    return t
end

-- Resolve the duration for the Nth occurrence of a timer row. This is where the
-- encounter grammar's four value shapes collapse into one number/variance string:
--   pull            first occurrence differs from the recurring cd
--   phaseDuration   per-stage override (Thaddius P2, Kel'Thuzad P2)
--   sequence        alternating table (Loatheb doom 29.1/32.4)
--   sequenceFrom    the sequence CHANGES at the Nth occurrence (Loatheb's 7th doom)
--   schedule        a hard-coded cycle whose last entry repeats (Noth teleports)
function API.ResolveDuration(row, occurrence, stage)
    occurrence = occurrence or 1
    if row.schedule and #row.schedule > 0 then
        return row.schedule[occurrence] or row.schedule[#row.schedule]
    end
    if row.sequenceFrom then
        local bestAt, bestSeq
        for at, seq in pairs(row.sequenceFrom) do
            if occurrence >= at and (bestAt == nil or at > bestAt) then bestAt, bestSeq = at, seq end
        end
        if bestSeq then
            local i = ((occurrence - bestAt) % #bestSeq) + 1
            return bestSeq[i]
        end
    end
    if occurrence <= 1 and row.pull ~= nil then return row.pull end
    if row.phaseDuration and stage ~= nil and row.phaseDuration[stage] ~= nil then
        return row.phaseDuration[stage]
    end
    if row.sequence and #row.sequence > 0 then
        local i = ((occurrence - 2) % #row.sequence) + 1
        if i < 1 then i = 1 end
        return row.sequence[i]
    end
    return row.duration
end

-- ── Trigger routing ───────────────────────────────────────────────────────────
-- `ev` is the normalised event table the lifecycle layer hands us:
--   { on=, spellId=, sourceGUID=, sourceId=, destGUID=, destId=, destName=,
--     sourceName=, amount=, school=, text=, pct=, stage=, unit= }
local function triggerMatches(rt, tr, ev)
    if tr.spellId ~= nil then
        if type(tr.spellId) == "table" then
            local hit = false
            for _, id in ipairs(tr.spellId) do if id == ev.spellId then hit = true break end end
            if not hit then return false end
        elseif tr.spellId ~= ev.spellId then
            return false
        end
    end
    if tr.creatureId ~= nil then
        local want, got = tr.creatureId, ev.sourceId or ev.destId or ev.creatureId
        if type(want) == "table" then
            local hit = false
            for _, id in ipairs(want) do if id == got then hit = true break end end
            if not hit then return false end
        elseif want ~= got then
            return false
        end
    end
    if tr.dest == "player" and not ev.destIsPlayer then return false end
    if tr.source == "player" and not ev.sourceIsPlayer then return false end
    if tr.source == "pet" and not ev.sourceIsPet then return false end
    if tr.school ~= nil then
        local s = ev.school or 0
        if s % (tr.school * 2) < tr.school then return false end   -- bitmask test, Lua-5.1 safe
    end
    if tr.stacks ~= nil and (ev.amount or 0) < tr.stacks then return false end
    if tr.stage ~= nil and rt.stage ~= tr.stage then return false end
    if tr.state ~= nil and rt.states[tr.stateKey or tr.key] ~= tr.state then return false end
    if tr.pct ~= nil and (ev.pct == nil or ev.pct > tr.pct) then return false end
    if tr.text ~= nil then
        local want, got = tr.text, ev.text or ""
        if type(want) == "table" then
            local hit = false
            for _, s in ipairs(want) do if s == got then hit = true break end end
            if not hit then return false end
        elseif want ~= got then
            return false
        end
    end
    if tr.textFind ~= nil then
        local got = ev.text or ""
        local want = type(tr.textFind) == "table" and tr.textFind or { tr.textFind }
        local hit = false
        for _, s in ipairs(want) do if got:find(s, 1, true) then hit = true break end end
        if not hit then return false end
    end
    if tr.textPattern ~= nil then
        local got = ev.text or ""
        local want = type(tr.textPattern) == "table" and tr.textPattern or { tr.textPattern }
        local hit = false
        for _, s in ipairs(want) do if got:match(s) then hit = true break end end
        if not hit then return false end
    end
    return true
end
API.TriggerMatches = triggerMatches

-- Dispatch one normalised event into an engagement. Returns the number of rows
-- that acted, which is what the harness asserts against.
function Runtime:Route(ev)
    if not self.engaged then return 0 end
    local bucket = self.def.index[ev.on]
    if not bucket then return 0 end
    local acted = 0
    for i = 1, #bucket do
        local entry = bucket[i]
        if triggerMatches(self, entry.trigger, ev) then
            if self:Act(entry, ev) then acted = acted + 1 end
        end
    end
    return acted
end

local function fmtCount(text, n)
    if not text then return text end
    if text:find("%%d") then return (text:format(n)) end
    return text .. " " .. tostring(n)
end

function Runtime:Act(entry, ev)
    local c, row = entry.consumer, entry.consumer.row
    local tr = entry.trigger

    if tr.antispam and not self:AntiSpam(row.key .. ":" .. tostring(tr.on), tr.antispam) then
        return false
    end
    if row.antispam and not self:AntiSpam(row.key, row.antispam) then return false end

    if c.kind == "timer" then
        if not Addon.API.IsRowEnabled(self.id, row) then return false end
        local t = self:Timer(row.key)
        if not t then return false end
        -- BAR IDENTITY (§4.1) is timerId + arguments, so the identity argument must
        -- be supplied ONLY for timers that genuinely have one bar per subject.
        -- Passing a per-event value (a target name, a GUID) to a plain cooldown
        -- timer would mint a NEW bar every cast — which silently disables the
        -- early-refresh tripwire, because there would never be a bar to measure.
        local ident
        if row.perTarget then ident = ev.destName
        elseif row.nameplate then ident = ev.sourceGUID or ev.destGUID end
        if c.act == "stop" then
            if ident ~= nil then t:Stop(ident) else t:Stop() end
            return true
        end
        local n = (self.counters["__occ:" .. row.key] or 0) + 1
        self.counters["__occ:" .. row.key] = n
        local dur = API.ResolveDuration(row, n, self.stage)
        if ident ~= nil then t:Start(dur, ident) else t:Start(dur) end
        return true
    end

    if c.kind == "warning" then
        if row.key and not Addon.API.IsRowEnabled(self.id, row) then return false end
        local text = row.text or row.key
        if row.count then text = fmtCount(text, self:Count("__warn:" .. row.key)) end
        if (row.tier or "announce") == "special" then
            Addon:EmitSpecial(self.id, row, text)
        else
            Addon:EmitAnnounce(self.id, row, text)
        end
        return true
    end

    if c.kind == "counter" then
        if c.act == "reset" then self:ResetCount(row.key)
        elseif c.act == "dec" then self:Count(row.key, -(row.step or 1))
        else self:Count(row.key, row.step or 1) end
        local v = self:GetCount(row.key)
        if row.threshold and row.threshold.at and v >= row.threshold.at and row.threshold.warning then
            local w = self.def.rowsByKey[row.threshold.warning]
            if w and Addon.API.IsRowEnabled(self.id, w) then
                Addon:EmitSpecial(self.id, w, fmtCount(w.text or w.key, v))
            end
        end
        if row.announceAt then
            for _, mark in ipairs(row.announceAt) do
                if v == mark and row.announce then
                    Addon:EmitAnnounce(self.id, row, fmtCount(row.announce, v))
                end
            end
        end
        return true
    end

    if c.kind == "phase" then
        return self:SetStage(row.stage)
    end

    if c.kind == "state" then
        local changed = self:SetState(row.key, tr.to)
        if changed and tr.announce then Addon:EmitAnnounce(self.id, row, tr.announce) end
        if changed and tr.actions then
            for _, a in ipairs(tr.actions) do
                if a.stopTimer then local t = self:Timer(a.stopTimer); if t then t:Stop() end end
                if a.startTimer then
                    local t = self:Timer(a.startTimer)
                    local r = self.def.rowsByKey[a.startTimer]
                    if t then t:Start(r and API.ResolveDuration(r, 1, self.stage)) end
                end
                if a.resetCounter then self:ResetCount(a.resetCounter) end
                if a.stage then self:SetStage(a.stage) end
            end
        end
        return changed
    end

    if c.kind == "scan" then
        Addon:FireEngineEvent("SCAN_REQUEST", self.id, row, ev)
        return true
    end

    if c.kind == "icon" then
        Addon:FireEngineEvent("ICON_REQUEST", self.id, row, ev)
        return true
    end
    return false
end

-- Pull-seeded schedules (Noth's teleports, Heigan's dance, Gothik's waves,
-- Chromaggus's two breath pre-warnings, C'Thun's Dark Glare loop).
function Runtime:StartPullSchedules()
    local S = Addon.Sched
    for _, row in ipairs(self.def.schedule) do
        if Addon.API.IsRowEnabled(self.id, row) then
            if row.gaps then
                S:LoopTable(row.gaps, function(_, i)
                    self:Route({ on = "schedule", key = row.key, index = i })
                    if row.announce then Addon:EmitAnnounce(self.id, row, fmtCount(row.announce, i)) end
                end, self, row.immediate)
            elseif row.at then
                local list = type(row.at) == "table" and row.at or { row.at }
                for _, t in ipairs(list) do
                    S:Schedule(t, function()
                        self:Route({ on = "schedule", key = row.key })
                        if row.announce then Addon:EmitAnnounce(self.id, row, row.announce) end
                    end, self)
                end
            end
        end
    end
    -- Timers whose start trigger is the pull itself.
    self:Route({ on = "pull" })
end

function Runtime:Teardown()
    self.engaged = false
    for _, t in pairs(self.timers) do t:Stop() end
    Addon.Sched:CancelOwner(self)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  D. THE ESCAPE HATCH — registered special modules (design item 8)
-- ══════════════════════════════════════════════════════════════════════════════
--  modules.lua is UNCHANGED and remains the registration surface for the five
--  shipped Naxx specials. This section preserves the two engine-owned surfaces
--  those modules reach for, with byte-identical signatures, and wires them to the
--  new lifecycle.

Addon._combatHooks = Addon._combatHooks or {}
-- fn(subevent, sourceGUID, sourceID, destGUID, destID, spellID, spellName)
-- ^ VERBATIM the signature the retired engine used. mod_fourhorsemen_tracker.lua
--   registers against exactly this and must keep working untouched.
function Addon:RegisterCombatHook(fn)
    if type(fn) == "function" then Addon._combatHooks[#Addon._combatHooks + 1] = fn end
end

function Addon:FireCombatHooks(subevent, sourceGUID, sourceID, destGUID, destID, spellID, spellName)
    if Addon.IsDebugOnly and Addon:IsDebugOnly() then return 0 end
    local hooks = Addon._combatHooks
    for i = 1, #hooks do
        pcall(hooks[i], subevent, sourceGUID, sourceID, destGUID, destID, spellID, spellName)
    end
    return #hooks
end

-- `Addon.active` is the legacy widget contract: { raidId, bossId, boss, startTime }.
-- The five specials, alerts.lua and options.lua all read it. The new lifecycle
-- keeps it populated so W4d's port is a data change, not a code change.
function API.SetLegacyActive(enc, rt)
    if enc and enc.legacy then
        Addon.active = {
            raidId    = enc.legacy.raidId,
            bossId    = enc.legacy.bossId,
            boss      = enc.legacy.boss or { id = enc.legacy.bossId, name = enc.name },
            startTime = rt and rt.pullTime or (Addon.Sched and Addon.Sched:Now()),
            encId     = enc.id,
        }
    else
        Addon.active = nil
    end
    return Addon.active
end

function API.StartSpecials(enc, rt)
    local started = 0
    if enc.legacy and type(Addon.StartBossModules) == "function" then
        local okc = pcall(Addon.StartBossModules, Addon, enc.legacy.raidId, enc.legacy.bossId)
        if okc then started = started + 1 end
    end
    for _, id in ipairs(enc.specials or {}) do
        for _, def in ipairs(Addon.modules or {}) do
            if def.id == id and type(Addon.StartModule) == "function" then
                pcall(Addon.StartModule, Addon, def)
                started = started + 1
            end
        end
    end
    if type(enc.OnEngage) == "function" then
        pcall(enc.OnEngage, enc, rt, rt and rt.delay or 0,
              rt and rt.trigger == "chat", rt and rt.trigger == "encounter")
    end
    return started
end

function API.StopSpecials(enc, rt, wiped)
    if type(Addon.StopAllModules) == "function" then pcall(Addon.StopAllModules, Addon) end
    if type(enc.OnEnd) == "function" then pcall(enc.OnEnd, enc, rt, wiped) end
end

return API
