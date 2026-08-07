-- =====================================================================
-- Daseeki-Raid-Mechanics headless self-test harness (REAL Lua 5.1)
--
-- Suite harness pattern: stub the minimal WoW API, load the REAL addon files
-- under a real Lua interpreter, drive the REAL code through its REAL paths,
-- assert one rule per spec rule, exit non-zero on any failure.
--
-- 2.0 WAVE 1 — ENGINE CORE. Every assertion below names the DBM_ENGINE_BEHAVIOR_
-- SPEC.md rule it proves. Nothing is asserted against a mock of our own code: the
-- scheduler runs on an injected clock, the lifecycle runs on an injected world,
-- and both are the shipping implementations.
--
-- GATES
--   0        TOC PARSE   loadfile (parse only) every .lua in the folder + the toc list
--   FW       FIREWALL    clean-room firewall over the change surface
--   RETIRE   DEMOLITION  engine.lua / encounters.lua gone; data_*.lua parked out of toc
--   MIG-*    MIGRATION   the NW-5 stamp-don't-wipe regression proofs (kept)
--   HEAP     §3.1/§3.2   pure min-heap ordering, determinism, partial-match removal
--   SCHED    §3.1-§3.5   absolute time, drain-all, drift, recycling, idle self-hide,
--                        ceiling, cancel grammar, countdown/loop/looptable/delayed
--   TIMER    §4.1/§4.2   identity, dedup, count-replace, variance semantics,
--                        negative-shift incl. negative zero, update/pause/resume
--   TRIP     §4.3        the early-refresh tripwire verdict matrix + telemetry ring
--   LIFE     §2          five engage paths, lockout matrix, wipe verdict matrix,
--                        difficulty snapshot, kill paths, end accounting
--   API      item 8      grammar validation + one synthetic encounter using EVERY
--                        grammar feature, driven engage -> timers -> warnings ->
--                        wipe -> re-engage
--   HATCH    item 8      the registered-special-module escape hatch, verbatim seams
--   SYNC-*   §7/§9/§11.4 WAVE 3: our own addon-channel wire (format, transport and
--                        sub-protocol version gates, channel scope, two send
--                        priorities), corroboration thresholds on BOTH client rules,
--                        throttling/dedupe and the housekeeper prune, the version nag
--                        at 2 senders WITH the owner-vetoed self-disable asserted
--                        absent two ways, the full 7/10/13 s reload-recovery cascade
--                        on the fake clock, pull/break timers end to end, and the
--                        receive-only boss-mod ingest behind a two-layer transmit
--                        firewall.
--
-- Usage:  lua5.1 run-selftests.lua [RM_DIR]   (exit 0 = ALL PASS)
-- =====================================================================

local realprint = print

local HARNESS_DIR = (arg[0]:match("^(.*)[\\/][^\\/]+$")) or "."
local function slash(p) return (p:gsub("\\", "/")) end
HARNESS_DIR = slash(HARNESS_DIR)
local DIR = slash(arg[1] or (HARNESS_DIR .. "/.."))
local function P(rel) return DIR .. "/" .. rel end

local TOC_FILE   = "Daseeki-Raid-Mechanics.toc"
local ADDON_NAME = "Daseeki-Raid-Mechanics"

local FAILS, GATE_FAILS = 0, {}
local CURRENT_GATE = "?"
local function fail(m)
    FAILS = FAILS + 1
    GATE_FAILS[CURRENT_GATE] = (GATE_FAILS[CURRENT_GATE] or 0) + 1
    realprint("  FAIL  " .. m)
end
local function ok(m) realprint("  ok    " .. m) end
local function ck(cond, m) if cond then ok(m) else fail(m) end end
local function eq(got, want, m)
    if got == want then ok(m)
    else fail(m .. ("  (got %s, want %s)"):format(tostring(got), tostring(want))) end
end
local function near(got, want, tol, m)
    if type(got) == "number" and math.abs(got - want) <= (tol or 0.001) then ok(m)
    else fail(m .. ("  (got %s, want ~%s)"):format(tostring(got), tostring(want))) end
end
local function gate(name)
    CURRENT_GATE = name
    realprint("=== GATE " .. name .. " ===")
end
local function endgate()
    local n = GATE_FAILS[CURRENT_GATE] or 0
    realprint("=== GATE " .. CURRENT_GATE .. ": " .. (n == 0 and "PASS" or (n .. " FAIL")) .. " ===\n")
end

local function readFile(path)
    local fh = io.open(path, "r"); if not fh then return nil end
    local s = fh:read("*a"); fh:close(); return s
end
local function exists(path)
    if readFile(path) then return true end
    return os.rename(path, path) and true or false
end

----------------------------------------------------------------------
-- GATE 0: TOC PARSE
----------------------------------------------------------------------
local function readTocLuaFiles(tocPath)
    local fh = io.open(tocPath, "r"); if not fh then return nil end
    local out, set = {}, {}
    for line in fh:lines() do
        line = line:gsub("^\239\187\191", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 1) ~= "#" and line:lower():sub(-4) == ".lua" then
            local rel = (line:gsub("\\", "/"))
            out[#out + 1] = rel
            set[rel] = true
        end
    end
    fh:close()
    return out, set
end

local ALL_LUA = {
    "core.lua", "theme.lua", "media.lua", "soundpacks.lua",
    "core_heap.lua", "core_telemetry.lua", "core_sched.lua", "core_timers.lua",
    "core_api.lua", "core_lifecycle.lua", "core_boot.lua", "core_sync.lua",
    "alerts.lua", "dbm_bridge.lua", "modules.lua",
    "mod_loatheb_healers.lua", "mod_fourhorsemen_rotation.lua",
    "mod_fourhorsemen_tracker.lua", "mod_gothik_waves.lua",
    "mod_razuvious_understudy.lua", "thaddius.lua",
    "soundpicker.lua", "options.lua", "slash.lua",
    -- parked but must still COMPILE, so a stale syntax error can never surprise W4
    "data_naxxramas.lua", "data_bwl.lua", "data_aq40.lua",
}

gate("0  toc parse")
local TOC_LUA, TOC_SET = readTocLuaFiles(P(TOC_FILE))
if not TOC_LUA or #TOC_LUA == 0 then fail("cannot read .toc lua list"); os.exit(1) end
for _, rel in ipairs(TOC_LUA) do
    local chunk, err = loadfile(P(rel))
    if chunk then ok("toc parse " .. rel) else fail("toc parse " .. rel .. " -> " .. tostring(err)) end
end
for _, rel in ipairs(ALL_LUA) do
    if not TOC_SET[rel] then
        if exists(P(rel)) then
            local chunk, err = loadfile(P(rel))
            if chunk then ok("parked parse " .. rel)
            else fail("parked parse " .. rel .. " -> " .. tostring(err)) end
        end
    end
end
if FAILS > 0 then realprint("=== GATE 0: FAIL (a file does not compile) ==="); os.exit(1) end
endgate()

----------------------------------------------------------------------
-- GATE FW: CLEAN-ROOM FIREWALL
--
-- Raid-Mechanics is an ORIGINAL Daseeki addon that legitimately names other
-- addons in comments (bundled sound-pack provenance, LibSharedMedia interop, UI
-- analogies). This gate HARD-FAILS only on the files THIS WAVE authored, and
-- reports identifiers elsewhere as informational notes. "dbm" is a documented
-- OptionalDep and is deliberately NOT a forbidden token.
--
-- The 2.0 engine is additionally a CLEAN-ROOM build: it was written from the two
-- Room-1 behavioural specs and never from third-party source.
----------------------------------------------------------------------
local FORBIDDEN = {
    "portalmage", "totemtimers", "druidbar", "pallypower",
    "weakauras", "weakaurassaved", "aura_env",
    "shadownetwork", "novainstancetracker", "novaworldbuffs",
    "bigwigs", "elvui", "bartender4", "dominos",
}
local CHANGE_SURFACE = {
    ["core_heap.lua"] = true, ["core_telemetry.lua"] = true, ["core_sched.lua"] = true,
    ["core_timers.lua"] = true, ["core_api.lua"] = true, ["core_lifecycle.lua"] = true,
    ["core_boot.lua"] = true, [TOC_FILE] = true,
    -- wave 3 authored these two; they are clean-room from the behaviour spec alone.
    ["core_sync.lua"] = true, ["dbm_bridge.lua"] = true,
}
gate("FW  clean-room firewall")
local FW_FILES = { "CHANGELOG.md", "README.md", TOC_FILE, ".pkgmeta" }
for _, rel in ipairs(ALL_LUA) do FW_FILES[#FW_FILES + 1] = rel end
local noteCount = 0
for _, rel in ipairs(FW_FILES) do
    local src = readFile(P(rel))
    if src then
        local lower, hits = src:lower(), {}
        for _, tok in ipairs(FORBIDDEN) do if lower:find(tok, 1, true) then hits[#hits + 1] = tok end end
        if #hits > 0 then
            if CHANGE_SURFACE[rel] then
                fail(rel .. " (wave-1 change surface) contains: " .. table.concat(hits, ", "))
            else
                noteCount = noteCount + 1
                realprint("  note  " .. rel .. " references (original-addon, not copied source): "
                    .. table.concat(hits, ", "))
            end
        elseif CHANGE_SURFACE[rel] then
            ok(rel .. " (change surface, clean)")
        end
    end
end
realprint(("  (%d original-addon reference note(s))"):format(noteCount))
endgate()

----------------------------------------------------------------------
-- GATE RETIRE: the wave-1 demolition stays demolished
----------------------------------------------------------------------
local RETIRED_PATHS   = { "engine.lua", "encounters.lua" }
local PARKED_OUT_OF_TOC = { "data_naxxramas.lua", "data_bwl.lua", "data_aq40.lua" }

gate("RETIRE  demolition holds")
for _, rel in ipairs(RETIRED_PATHS) do
    ck(not exists(P(rel)),
       rel .. " is DELETED from disk (design verdict: SCRAP — rebuild spec-first)")
    ck(not TOC_SET[rel], rel .. " is absent from the load list")
end
for _, rel in ipairs(PARKED_OUT_OF_TOC) do
    ck(exists(P(rel)), rel .. " is still PARKED on disk (W4 cross-check input)")
    ck(not TOC_SET[rel], rel .. " is NOT in the load list (the 1.x data model is not loaded)")
end
for _, rel in ipairs({ "core_heap.lua", "core_telemetry.lua", "core_sched.lua",
                       "core_timers.lua", "core_api.lua", "core_lifecycle.lua",
                       "core_boot.lua", "core_sync.lua" }) do
    ck(TOC_SET[rel], rel .. " IS in the load list (the new core actually ships)")
end
do  -- load-order is a dependency chain and the toc must express it
    local pos = {}
    for i, rel in ipairs(TOC_LUA) do pos[rel] = i end
    local chain = { "core_heap.lua", "core_telemetry.lua", "core_sched.lua",
                    "core_timers.lua", "core_api.lua", "core_lifecycle.lua", "core_boot.lua",
                    "core_sync.lua" }
    local monotonic = true
    for i = 2, #chain do
        if not (pos[chain[i - 1]] and pos[chain[i]] and pos[chain[i - 1]] < pos[chain[i]]) then
            monotonic = false
        end
    end
    ck(monotonic, "engine load order is heap -> telemetry -> sched -> timers -> api -> lifecycle -> boot -> sync")
    ck(pos["core_sync.lua"] and pos["dbm_bridge.lua"]
       and pos["core_sync.lua"] < pos["dbm_bridge.lua"],
       "core_sync.lua loads before dbm_bridge.lua (the bridge writes into the transmit firewall at load)")
    ck(pos["core.lua"] and pos["core.lua"] < pos["core_heap.lua"],
       "core.lua (SavedVariables) loads before the engine")
    ck(pos["modules.lua"] and pos["core_api.lua"] < pos["modules.lua"],
       "the engine API loads before modules.lua (the special-module escape hatch)")
end
endgate()

----------------------------------------------------------------------
-- WoW API STUB + the fake world the lifecycle is driven against
----------------------------------------------------------------------
local CHAT = {}
_G.print = function(...) CHAT[#CHAT + 1] = table.concat({ ... }, " ") end
_G.strfind, _G.strmatch, _G.strsub, _G.format =
    string.find, string.match, string.sub, string.format
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.date = function() return "1970-01-01 00:00" end
_G.GetServerTime = function() return 1000000 end

local FRAMES = {}
local function newFrame()
    local f = { scripts = {}, events = {}, shown = false, points = {} }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:GetScript(k) return self.scripts[k] end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetSize() end
    function f:SetPoint() end
    function f:ClearAllPoints() end
    function f:SetFrameStrata() end
    function f:SetAlpha() end
    function f:CreateFontString() return setmetatable({}, { __index = function() return function() end end }) end
    function f:CreateAnimationGroup()
        local ag = { anims = {} }
        function ag:CreateAnimation()
            return setmetatable({}, { __index = function() return function() end end })
        end
        function ag:SetScript() end
        function ag:Play() end
        function ag:Stop() end
        return ag
    end
    FRAMES[#FRAMES + 1] = f
    return f
end
_G.CreateFrame = function() return newFrame() end
_G.UIParent = newFrame()

-- The fake world. Every field is read through Lifecycle.env, so the lifecycle
-- under test is the shipping one.
local W = {
    inInstance = true, instanceType = "raid", difficultyID = 9, instanceID = 533,
    maxPlayers = 40, difficultyName = "40 Player", zoneName = "Naxxramas",
    encounterInProgress = false,
    playerGUID = "Player-1-AAAA",
    units = {},        -- unit token -> { guid, cid, combat, dead, hp, hpmax, friend, player }
    group = { "player" },
    bossUnits = {},    -- boss1..boss10 existence
    nameplates = {},
}
local function unit(u) return W.units[u] end
local function setUnit(u, t)
    t = t or {}
    if t.cid and not t.guid then t.guid = "Creature-0-0-0-0-" .. t.cid .. "-0001" end
    W.units[u] = t
    return t
end
local function clearWorld()
    W.units, W.group, W.bossUnits, W.nameplates = {}, { "player" }, {}, {}
    W.encounterInProgress = false
    -- W3 additions: group shape and identity are now world facts too (the sync layer
    -- reads them). Defaults match what wave 1's injection hard-coded.
    W.inRaid, W.inGroup = true, true
    W.realm = "Whitemane"
    setUnit("player", { guid = W.playerGUID, player = true, combat = true, dead = false,
                        name = "Drew", realm = "Whitemane" })
end
clearWorld()

_G.GetInstanceInfo = function()
    return W.zoneName, W.instanceType, W.difficultyID, W.difficultyName,
           W.maxPlayers, 0, false, W.instanceID
end
_G.UnitAffectingCombat = function(u) return (unit(u) or {}).combat and true or false end

----------------------------------------------------------------------
-- Load the REAL addon files into one Addon namespace.
----------------------------------------------------------------------
local Addon = {}
local ENGINE_FILES = {
    "core.lua", "core_heap.lua", "core_telemetry.lua", "core_sched.lua",
    "core_timers.lua", "core_api.lua", "core_lifecycle.lua", "core_boot.lua",
    -- wave 3: the addon channel, then the receive-only interop bridge that writes
    -- its prefixes into the channel's transmit firewall at LOAD time.
    "core_sync.lua", "dbm_bridge.lua",
}
for _, rel in ipairs(ENGINE_FILES) do
    local chunk, err = loadfile(P(rel))
    if not chunk then realprint("  FAIL  loadfile " .. rel .. " -> " .. tostring(err)); os.exit(2) end
    local okc, rerr = pcall(chunk, ADDON_NAME, Addon)
    if not okc then realprint("  FAIL  executing " .. rel .. " -> " .. tostring(rerr)); os.exit(2) end
end
-- modules.lua is the untouched escape-hatch registration surface.
do
    local chunk = assert(loadfile(P("modules.lua")))
    assert(pcall(chunk, ADDON_NAME, Addon))
end

_G.DaseekiRaidMechanicsDB = {}
Addon:Init()

local Heap, Sched, Timers, API, Life, Tele =
    Addon.Heap, Addon.Sched, Addon.Timers, Addon.API, Addon.Lifecycle, Addon.Telemetry
local Sync, Bridge = Addon.Sync, Addon.DBMBridge

-- ── the injected clock (headless discipline) ──────────────────────────────────
local CLOCK = 1000
Sched:SetClock(function() return CLOCK end)
local ADVANCE_CEILING = 100000
local function advance(seconds, step)
    step = step or 0.05
    local target = CLOCK + seconds
    local guard = 0
    while CLOCK < target do
        guard = guard + 1
        if guard > ADVANCE_CEILING then error("harness advance() hit its iteration ceiling") end
        local prev = CLOCK
        CLOCK = math.min(CLOCK + step, target)
        -- Drive the REAL frame entry point (updaters -> drain -> idle self-hide),
        -- not just the drain, so the sleep rule is exercised by the shipping path.
        Sched:OnUpdate(CLOCK - prev)
    end
end

-- ── the injected world ────────────────────────────────────────────────────────
----------------------------------------------------------------------
-- W3: the injected COMMS environment + a wire recorder.
-- World facts stay on Lifecycle.env (one fake world, not two); only the
-- comms-specific calls are faked here.
----------------------------------------------------------------------
local WIRE       = {}       -- every message that reached the (fake) wire
local REGISTERED = {}       -- every prefix registered for RECEIVE

Sync:SetEnv({
    SendAddonMessage = function(prefix, msg, chatType, target)
        WIRE[#WIRE + 1] = { prefix = prefix, payload = msg, chatType = chatType, target = target }
        return 0
    end,
    RegisterAddonMessagePrefix = function(p) REGISTERED[p] = true return true end,
    IsInInstanceGroup    = function() return W.instanceGroup == true end,
    GetNetStats          = function() return 0, 0, 0, W.latencyMs or 0 end,
    GetRealmName         = function() return W.realm end,
    UnitIsConnected      = function(u) return (unit(u) or {}).connected ~= false end,
    UnitIsGroupLeader    = function() return W.leader ~= false end,
    UnitIsGroupAssistant = function() return false end,
    FlashClientIcon      = function() W.flashed = (W.flashed or 0) + 1 end,
    UnitNameRealm        = function(u)
        local t = unit(u) or {}
        return t.name or u, t.realm
    end,
    Time   = function() return W.wallClock or 1700000000 end,
    DateAt = function() return "20:15" end,
})

Life:SetEnv({
    UnitExists          = function(u) return unit(u) ~= nil end,
    UnitAffectingCombat = function(u) return (unit(u) or {}).combat and true or false end,
    UnitIsDeadOrGhost   = function(u) return (unit(u) or {}).dead and true or false end,
    UnitIsPlayer        = function(u) return (unit(u) or {}).player and true or false end,
    UnitGUID            = function(u) return (unit(u) or {}).guid end,
    UnitName            = function(u) return (unit(u) or {}).name or u end,
    UnitHealth          = function(u) return (unit(u) or {}).hp end,
    UnitHealthMax       = function(u) return (unit(u) or {}).hpmax end,
    UnitIsFriend        = function(_, u) return (unit(u) or {}).friend and true or false end,
    UnitInVehicle       = function() return false end,
    IsEncounterInProgress = function() return W.encounterInProgress end,
    GetInstanceInfo     = _G.GetInstanceInfo,
    IsInInstance        = function() return W.inInstance end,
    IsInRaid            = function() return W.inRaid ~= false end,
    IsInGroup           = function() return W.inGroup ~= false end,
    GetNumGroupMembers  = function() return #W.group end,
    ForEachGroupMember  = function(fn)
        for _, u in ipairs(W.group) do if fn(u) then return true end end
        return false
    end,
    ForEachNameplate    = function(fn)
        for _, u in ipairs(W.nameplates) do if fn(u) then return true end end
        return false
    end,
    AnyBossUnit         = function()
        for i = 1, 10 do if W.bossUnits[i] then return true end end
        return false
    end,
    IsGroupUnit         = function(u)
        for _, m in ipairs(W.group) do
            if m == u or (m .. "pet") == u then return true end
        end
        return (unit(u) or {}).groupPet and true or false
    end,
})

----------------------------------------------------------------------
-- GATE MIG-ALGO / MIG-INIT (kept from the 1.x harness — NW-5 regression proofs)
----------------------------------------------------------------------
gate("MIG-ALGO  stamp / newer / transform / gap-not-wipe")
do
    local db = { mechanics = { ["naxx:1:1"] = { masterEnabled = false } }, stats = { naxx = { kills = 7 } } }
    eq(Addon:MigrateDB(db), true, "(a) absent version returns true")
    eq(db.dbVersion, 3, "(a) absent version stamped to current")
    eq(db.mechanics["naxx:1:1"].masterEnabled, false, "(a) mechanic override preserved")
    eq(db.stats.naxx.kills, 7, "(a) db.stats preserved")
end
do
    local db = { dbVersion = 99, mechanics = { x = { scale = 2 } }, stats = { s = 1 } }
    eq(Addon:MigrateDB(db), false, "(b) newer version returns false")
    eq(db.dbVersion, 99, "(b) newer version not downgraded")
end
do
    Addon.MIGRATIONS[2] = function(d) d.__stepran = true end
    local db = { dbVersion = 2, mechanics = { y = { opacity = 0.5 } }, stats = { s = 3 } }
    eq(Addon:MigrateDB(db), true, "(c) older-with-step returns true")
    eq(db.__stepran, true, "(c) migration step ran (transform in place)")
    eq(db.mechanics.y.opacity, 0.5, "(c) override preserved through transform")
    Addon.MIGRATIONS[2] = nil
end
do
    local db = { dbVersion = 2, mechanics = { ["naxx:2:3"] = { masterEnabled = false } },
                 stats = { naxx = { kills = 12 } } }
    eq(Addon:MigrateDB(db), false, "(d) missing step returns false")
    eq(db.dbVersion, 2, "(d) version not stamped over a gap")
    eq(db.mechanics["naxx:2:3"].masterEnabled, false, "(d) db.mechanics NOT emptied (regression proof)")
    eq(db.stats.naxx.kills, 12, "(d) db.stats intact")
end
endgate()

----------------------------------------------------------------------
-- GATE HEAP — §3.1 ordering, §3.2 partial-match removal
----------------------------------------------------------------------
gate("HEAP  §3.1/§3.2 pure min-heap")
do
    local h = Heap.New()
    for _, t in ipairs({ 5, 1, 4, 1, 3, 2 }) do h:Push({ at = t, tag = t }) end
    local order = {}
    while h:Count() > 0 do order[#order + 1] = h:Pop().at end
    eq(table.concat(order, ","), "1,1,2,3,4,5", "delete-min yields ascending absolute due times")
end
do  -- ties break on insertion sequence => a batch of simultaneous expiries is DETERMINISTIC
    local h = Heap.New()
    for i = 1, 6 do h:Push({ at = 10, tag = i }) end
    local order = {}
    while h:Count() > 0 do order[#order + 1] = h:Pop().tag end
    eq(table.concat(order, ","), "1,2,3,4,5,6", "equal due times drain in insertion order (deterministic)")
end
do  -- O(1) peek
    local h = Heap.New()
    h:Push({ at = 9 }); h:Push({ at = 2 }); h:Push({ at = 7 })
    eq(h:Peek().at, 2, "Peek returns the next due task without popping")
    eq(h:Count(), 3, "Peek does not mutate")
end
do  -- linear sweep + rebuild preserves order of survivors
    local h = Heap.New()
    for i = 1, 8 do h:Push({ at = i, tag = i }) end
    local sink = {}
    local removed = h:RemoveWhere(function(t) return t.tag % 2 == 0 end, sink)
    eq(removed, 4, "RemoveWhere removes every matching task")
    eq(#sink, 4, "removed tasks are handed back for recycling")
    local order = {}
    while h:Count() > 0 do order[#order + 1] = h:Pop().tag end
    eq(table.concat(order, ","), "1,3,5,7", "the heap is correctly rebuilt after a sweep")
end
do
    local h = Heap.New()
    h:Push({ at = 1 }); h:Push({ at = 2 })
    local sink = {}
    eq(h:Clear(sink), 2, "Clear drops everything (the §9.4 hard-disable path)")
    eq(h:Count(), 0, "…and leaves the heap empty")
end
endgate()

----------------------------------------------------------------------
-- GATE SCHED — §3.1 to §3.5
----------------------------------------------------------------------
gate("SCHED  §3.1-§3.5 frame-driven scheduler")
Sched:Flush()
do  -- §3.1 absolute time + drain-ALL-per-frame
    local hits = {}
    Sched:Schedule(1, function() hits[#hits + 1] = "a" end)
    Sched:Schedule(1, function() hits[#hits + 1] = "b" end)
    Sched:Schedule(1, function() hits[#hits + 1] = "c" end)
    Sched:Schedule(5, function() hits[#hits + 1] = "late" end)
    CLOCK = CLOCK + 1
    local drained = Sched:Tick(CLOCK)
    eq(drained, 3, "one frame drains EVERY due task (no per-frame budget)")
    eq(table.concat(hits, ","), "a,b,c", "…in heap order, before anything else runs")
    Sched:Flush()
end
do  -- §3.1 drift correction is inherent: a slow frame delays but never accumulates
    local at
    Sched:Schedule(2, function() at = CLOCK end)
    CLOCK = CLOCK + 10          -- a catastrophically slow frame
    Sched:Tick(CLOCK)
    ck(at == CLOCK, "a slow frame runs the overdue task on the next tick (absolute due time)")
    local seq = {}
    local base = CLOCK
    Sched:Schedule(1, function() seq[#seq + 1] = CLOCK - base end)
    Sched:Schedule(2, function() seq[#seq + 1] = CLOCK - base end)
    Sched:Schedule(3, function() seq[#seq + 1] = CLOCK - base end)
    advance(4, 0.7)             -- deliberately ragged frame timing
    ck(seq[3] - seq[1] <= 2.7, "a chain of schedules does not accumulate error across ragged frames")
    Sched:Flush()
end
do  -- §3.2 recycling: <=4 args recycled, >4 allocate fresh, cache capped at 8
    Sched.stats.recycled, Sched.stats.allocated = 0, 0
    for i = 1, #Sched.pool do Sched.pool[i] = nil end
    local noop = function() end
    for i = 1, 6 do Sched:Schedule(0.1, noop, nil, 1, 2, 3, 4) end
    advance(0.2)
    eq(#Sched.pool, 6, "completed tasks with <=4 arguments go back on the recycle stack")
    for i = 1, 6 do Sched:Schedule(0.1, noop, nil, 1, 2, 3, 4) end
    advance(0.2)
    eq(Sched.stats.recycled, 6, "the second batch reuses the recycled tables")
    for i = 1, 5 do Sched:Schedule(0.1, noop, nil, 1, 2, 3, 4, 5, 6) end
    local before = #Sched.pool
    advance(0.2)
    ck(#Sched.pool <= math.max(before, Sched.POOL_MAX),
       "tasks with MORE than 4 arguments are not recycled (spec §3.2)")
    for i = 1, 20 do Sched:Schedule(0.1, noop, nil, 1) end
    advance(0.2)
    ck(#Sched.pool <= Sched.POOL_MAX, "the recycle stack is capped at 8 tables")
    Sched:Flush()
end
do  -- §3.2 cancellation: partial matching on (function, owner, first N arguments)
    local noop = function() end
    local owner, other = {}, {}
    Sched:Schedule(5, noop, owner, "boss", "cast", 1)
    Sched:Schedule(5, noop, owner, "boss", "cast", 2)
    Sched:Schedule(5, noop, owner, "boss", "fade", 1)
    Sched:Schedule(5, noop, other, "boss", "cast", 1)
    eq(Sched:Unschedule(noop, owner, "boss", "cast"), 2,
       "a cancel with FEWER arguments cancels every task whose LEADING arguments match")
    eq(Sched:Unschedule(noop, owner), 1, "cancel by (function, owner) sweeps the owner's remaining tasks")
    eq(Sched:Unschedule(nil, other), 1, "cancel by owner alone matches any function")
    eq(Sched:Count(), 0, "…and nothing is left behind")
    Sched:Flush()
end
do  -- §3.1 idle self-hide
    Sched:Flush()
    Sched:Schedule(1, function() end)
    ck(Sched:IsAwake(), "scheduling wakes the frame")
    local f = Sched.frame
    ck(f and f.shown, "…and shows it")
    advance(1.1)
    ck(not Sched:IsAwake(), "an empty heap with no per-frame handler puts the scheduler to sleep")
    ck(f and not f.shown and f.scripts.OnUpdate == nil,
       "…the frame is hidden AND the OnUpdate script is detached (zero idle cost)")
    Sched:RegisterUpdate({}, 1, function() end)
    ck(Sched:IsAwake(), "registering a per-frame handler wakes it again")
    Sched:Flush()
end
do  -- §3.3 per-module update handlers
    local owner, calls = {}, 0
    Sched:RegisterUpdate(owner, 0.5, function() calls = calls + 1 end)
    Sched:RunUpdaters(0.2); Sched:RunUpdaters(0.2)
    eq(calls, 0, "a per-module handler does not fire before its interval is met")
    Sched:RunUpdaters(0.2)
    eq(calls, 1, "…and fires once the accumulator reaches the interval")
    Sched:RunUpdaters(0.2)
    eq(calls, 1, "…the accumulator is zeroed after firing")
    local gated, gcalls = {}, 0
    Sched:RegisterUpdate(gated, 0, function() gcalls = gcalls + 1 end, function() return false end)
    Sched:RunUpdaters(1)
    eq(gcalls, 0, "a handler whose zone gate is false is skipped")
    Sched:Flush()
end
do  -- §3.4 countdown
    local fired = {}
    eq(Sched:Countdown(5, 3, function(n) fired[#fired + 1] = n end), 3,
       "Countdown(5,3) schedules three firings at time-1, time-2, time-3")
    advance(5)
    eq(table.concat(fired, ","), "3,2,1", "…delivering the REMAINING count, latest first")
    fired = {}
    eq(Sched:Countdown(2, 5, function(n) fired[#fired + 1] = n end), 1,
       "firings that would land under 1 s are discarded")
    Sched:Flush()
end
do  -- §3.4 fixed loop re-derives from the same absolute base (drift-free)
    local ticks, base = {}, CLOCK
    local st = Sched:Loop(1, function(_, i) ticks[i] = CLOCK - base end)
    advance(3.5, 0.37)          -- ragged frames
    near(ticks[3], 3, 0.4, "a fixed loop's 3rd iteration still lands ~3 s from the base (no drift)")
    Sched:CancelLoop(st)
    local n = #ticks
    advance(3)
    eq(#ticks, n, "CancelLoop stops it")
    Sched:Flush()
end
do  -- §3.4 interval-table loop; the LAST gap repeats (Noth's "4th+ = 35 s" shape)
    local gaps, base = { 2, 3, 5 }, CLOCK
    local seen = {}
    local st = Sched:LoopTable(gaps, function(_, i) seen[i] = CLOCK - base end)
    advance(16)
    near(seen[1], 2, 0.1, "LoopTable entry 1 at gap[1]")
    near(seen[2], 5, 0.1, "LoopTable entry 2 at gap[1]+gap[2]")
    near(seen[3], 10, 0.1, "LoopTable entry 3 at +gap[3]")
    near(seen[4], 15, 0.1, "LoopTable repeats the LAST gap forever")
    Sched:CancelLoop(st)
    seen = {}
    local st2 = Sched:LoopTable({ 10 }, function(_, i) seen[i] = CLOCK - CLOCK end, nil, true)
    advance(0.01)
    ck(seen[1] ~= nil, "the timer-flavoured loop fires entry 1 immediately (0.0001 s kick)")
    Sched:CancelLoop(st2)
    Sched:Flush()
end
do  -- §3.4 delayed call is a cancel-then-schedule debounce
    local calls = 0
    local fn = function() calls = calls + 1 end
    Sched:DelayedCall(1, fn, nil, "k")
    advance(0.5)
    Sched:DelayedCall(1, fn, nil, "k")
    advance(0.6)
    eq(calls, 0, "re-issuing a delayed call cancels the pending one (debounce)")
    advance(0.6)
    eq(calls, 1, "…and only the last one fires")
    Sched:Flush()
end
do  -- §3.5 housekeeping runs on the same loop, and ONLY while registered
    local runs = 0
    local hk = function() runs = runs + 1 end
    ck(Sched.housekeeping == nil, "no housekeeping heartbeat exists with nothing registered")
    Sched:AddHousekeeper(hk)
    advance(Sched.HOUSEKEEP_INTERVAL + 0.1)
    eq(runs, 1, "a registered housekeeper runs every 20 s on the scheduler's own loop")
    Sched:RemoveHousekeeper(hk)
    advance(Sched.HOUSEKEEP_INTERVAL + 0.1)
    eq(runs, 1, "…and stops (idle cost returns to zero)")
    Sched:Flush()
end
do  -- headless discipline: the drain ceiling
    Sched.stats.overflow = 0
    local function spin() Sched:Schedule(0, spin) end
    Sched:Schedule(0, spin)
    Sched:Tick(CLOCK)
    ck(Sched.stats.overflow >= 1, "a runaway zero-delay reschedule stops at the drain ceiling")
    ck(Tele.Count() > 0, "…and the overflow lands in the telemetry ring, not in a frozen client")
    Sched:Flush()
    Tele.Clear()
end
endgate()

----------------------------------------------------------------------
-- GATE TIMER — §4.1 identity/dedup, §4.2 variance
----------------------------------------------------------------------
gate("TIMER  §4.1/§4.2 identity, de-duplication, variance")
do  -- §4.2 the duration grammar
    local P1 = Timers.ParseDuration
    local d = P1("v25.9-34.7")
    ck(d and d.hasVariance and d.min == 25.9 and d.max == 34.7,
       "v<min>-<max> parses a variance window with decimals")
    near(d.variance, 8.8, 0.0001, "…and derives the variance duration")
    d = P1("d30")
    ck(d and not d.hasVariance and d.allowDouble and d.total == 30,
       "d<n> is a plain duration with the allow-double flag")
    d = P1("dv10-20")
    ck(d and d.hasVariance and d.allowDouble and d.min == 10 and d.max == 20,
       "dv<min>-<max> carries both")
    eq(P1(12).total, 12, "a plain number parses")
    eq(P1("v30-10"), nil, "an inverted window is rejected")
    eq(P1("nonsense"), nil, "garbage is rejected (and W4's data files fail validation loudly)")
end
do  -- §4.1 identity: same args address the same bar; a start REPLACES
    Timers.StopAll()
    local t = Timers.New({ id = "T1", kind = "cd", duration = 10 })
    local b1 = t:Start(nil, "Bob")
    local b2 = t:Start(nil, "Bob")
    eq(b1.id, b2.id, "two starts with the same arguments address the SAME bar")
    eq(Timers.Count(), 1, "…and do not stack")
    local b3 = t:Start(nil, "Alice")
    ck(b3.id ~= b1.id, "different arguments address a different bar")
    eq(Timers.Count(), 2, "…which coexists")
    eq(t:Stop(), 2, "Stop() with no arguments kills EVERY variant")
    eq(Timers.Count(), 0, "…leaving nothing behind")
end
do  -- §4.1 count timers replace previous variants; allow-double opts out
    Timers.StopAll()
    local t = Timers.New({ id = "T2", kind = "cd", duration = 10, count = true })
    t:Start(nil, 1); t:Start(nil, 2); t:Start(nil, 3)
    eq(Timers.Count(), 1, "a count timer CANCELS previously started variants ('Meteor (3)' replaces '(2)')")
    Timers.StopAll()
    local d = Timers.New({ id = "T3", kind = "cd", duration = 10, count = true, allowDouble = true })
    d:Start(nil, 1); d:Start(nil, 2)
    eq(Timers.Count(), 2, "…unless the object was declared allow-double")
    Timers.StopAll()
end
do  -- §4.1 residue: a bar that expires naturally leaves nothing on the live list
    Timers.StopAll()
    local t = Timers.New({ id = "T4", kind = "cd", duration = 3 })
    t:Start()
    eq(Timers.Count(), 1, "a started bar is live")
    advance(3.1)
    eq(Timers.Count(), 0, "a bar auto-removes itself on a schedule matching its own duration")
    eq(next(t.live), nil, "…and the timer object's live list is empty")
end
do  -- §4.2 the variance rendering/audio/sorting contract
    Timers.StopAll()
    local t = Timers.New({ id = "TV", kind = "cd", duration = "v40-60" })
    local bar = t:Start()
    eq(bar.renderTotal, 60, "with variance display ON the bar RUNS TO MAX")
    near(bar.varianceFrac, 20 / 60, 0.0001, "…and the painted window covers variance/total of its width")
    near(Timers.SortValue(bar, CLOCK), 40, 0.001,
         "sorting/enlarge/hide evaluate against the MINIMUM end (a v40-60 bar enlarges at 40)")
    near(Timers.Remaining(bar, CLOCK), 60, 0.001, "…while the rendered remaining runs to max")
    Timers.varianceDisplay = false
    local bar2 = t:Start(nil, "x")
    eq(bar2.renderTotal, 40, "with variance display OFF the bar runs to MIN and paints no window")
    Timers.varianceDisplay = true
    Timers.StopAll()
end
do  -- §4.2 audio and callbacks are fed the MINIMUM
    Timers.StopAll()
    local heard = {}
    Addon:RegisterEngineCallback("TIMER_COUNTDOWN", function(_, _, n) heard[#heard + 1] = n end)
    local t = Timers.New({ id = "TC", kind = "cd", duration = "v10-30", countdown = { depth = 3 } })
    local base = CLOCK
    t:Start()
    advance(11)
    eq(table.concat(heard, ","), "3,2,1",
       "the countdown voice counts down to the EARLIEST possible cast (min), not the latest")
    Addon._engineCallbacks["TIMER_COUNTDOWN"] = nil
    Timers.StopAll()
end
do  -- §4.2 negative start shifts the declared window earlier — INCLUDING negative zero
    Timers.StopAll()
    -- NOTE FOR W4: Lua 5.1's parser constant-folds the literal `-0.0` into `0.0`,
    -- so a negative-zero shift can never be WRITTEN in an encounter data file — it
    -- can only arrive computed. Build it the only way that works.
    local ZERO = tonumber("0")
    local NEGZERO = -1 * ZERO
    ck(Timers.IsNegativeStart(-3), "a negative start value is detected")
    ck(Timers.IsNegativeStart(NEGZERO), "…and so is NEGATIVE ZERO (which == 0 in every naive test)")
    ck(not Timers.IsNegativeStart(0), "…while plain zero is not")
    local t = Timers.New({ id = "TN", kind = "cd", duration = "v20-30" })
    local b = t:Start(-5)
    ck(b.min == 15 and b.max == 25, "a negative start recomputes the window as (min+delay)…(max+delay)")
    near(b.variance, 10, 0.0001, "…keeping the variance duration")
    local b0 = t:Start(NEGZERO, "z")
    ck(b0.min == 20 and b0.max == 30 and b0.hasVariance,
       "negative zero shifts by zero but KEEPS the variance window (a plain 0 would not)")
    Timers.StopAll()
end
do  -- §4.2 variance is cleared by a plain numeric total
    Timers.StopAll()
    local t = Timers.New({ id = "TU", kind = "cd", duration = "v10-20" })
    t:Start()
    local b = t:Update(0, 15)
    ck(b and not b.hasVariance and b.variance == 0 and b.renderTotal == 15,
       "updating a live bar with a plain numeric total CLEARS its variance")
    Timers.StopAll()
end
do  -- §4.1/§4.4 pause / resume / add / remove keep the residue schedule consistent
    Timers.StopAll()
    local t = Timers.New({ id = "TP", kind = "cd", duration = 10 })
    t:Start()
    advance(2)
    t:Pause()
    advance(5)
    near(Timers.Remaining(t:Get(), CLOCK), 8, 0.1, "a paused bar stops burning down")
    t:Resume()
    advance(1)
    near(Timers.Remaining(t:Get(), CLOCK), 7, 0.15, "…and resumes from where it stopped")
    t:AddTime(5)
    near(Timers.Remaining(t:Get(), CLOCK), 12, 0.2, "AddTime extends the bar")
    t:RemoveTime(2)
    near(Timers.Remaining(t:Get(), CLOCK), 10, 0.2, "RemoveTime shortens it")
    advance(11)
    eq(Timers.Count(), 0, "…and the residue schedule was re-armed, so it still expires cleanly")
end
do  -- §4.5 the external category contract
    local t = Timers.New({ id = "TX", kind = "cast", nameplate = true })
    eq(t:Category(), "castnp", "a nameplate cast timer collapses to castnp for external consumers")
    local t2 = Timers.New({ id = "TY", kind = "next", nameplate = true })
    eq(t2:Category(), "cdnp", "a nameplate cooldown timer collapses to cdnp")
    local t3 = Timers.New({ id = "TZ", kind = "stage" })
    eq(t3:Category(), "stage", "a stage timer collapses to stage")
end
endgate()

----------------------------------------------------------------------
-- GATE TRIP — §4.3 the early-refresh tripwire + the telemetry ring
----------------------------------------------------------------------
gate("TRIP  §4.3 early-refresh tripwire + telemetry ring")
do  -- the pure verdict matrix, rule by rule
    local C = Timers.ClassifyRefresh
    eq(C(0.1, nil), nil, "|remaining| <= 0.2 s is SILENT (normal jitter)")
    eq(C(-0.1, nil), nil, "…in both directions")
    eq(C(3, nil), "early", "non-variance: remaining > 1 s is a reportable EARLY refresh")
    eq(C(0.5, nil), "early_minor", "non-variance: remaining > 0.2 s is a debug-level observation")
    eq(C(-2, nil), "after_zero", "non-variance: a refresh well after zero is recorded")
    eq(C(12, 10), "early", "variance: measured against remaining - varianceDuration")
    eq(C(5, 10), nil, "variance: a refresh ANYWHERE INSIDE the declared window is silent")
    eq(C(10.5, 10), "early_minor", "variance: just outside the window is a debug-level observation")
    eq(C(-1, 10), "after_zero", "variance: a refresh after zero by more than 0.2 s is recorded")
end
do  -- GREEN: a restart inside the window writes NOTHING
    Timers.StopAll(); Tele.Clear()
    local t = Timers.New({ id = "TRIP-G", key = "green", encId = "fixture", kind = "cd",
                           duration = "v20-30" })
    t:Start()
    advance(25)                 -- inside the 20-30 window
    t:Start()
    eq(Tele.Count(), 0, "GREEN: restarting inside the declared variance window writes no telemetry")
end
do  -- RED: a deliberate out-of-window restart writes exactly one entry, with the numbers
    Timers.StopAll(); Tele.Clear()
    local t = Timers.New({ id = "TRIP-R", key = "boltvolley", encId = "viscidus", kind = "cd",
                           duration = "v20-30", spellId = 25991 })
    t:Start()
    advance(5)                  -- the boss cast 15 s before the window even opened
    t:Start()
    eq(Tele.Count(), 1, "RED: an out-of-window restart writes exactly ONE ring entry")
    local e = Tele.Ring(false)[1]
    eq(e.kind, "timer.refresh", "…tagged as the tripwire")
    eq(e.verdict, "early", "…with the verdict")
    eq(e.enc, "viscidus", "…carrying the ENCOUNTER identity")
    eq(e.key, "boltvolley", "…and the timer/row identity")
    eq(e.spell, 25991, "…and the spell id")
    eq(e.expMin, 20, "…the EXPECTED window minimum")
    eq(e.expMax, 30, "…the expected window maximum")
    near(e.obs, 5, 0.1, "…and the OBSERVED interval the bar actually ran")
    near(e.rem, 25, 0.1, "…plus the remaining time on the bar it replaced")
    eq(e.build, Tele.BUILD, "…build-stamped")
    ck(type(e.t) == "number", "…and wall-clock stamped")
end
do  -- the tripwire is skipped for the kinds §4.3 excludes
    Timers.StopAll(); Tele.Clear()
    for _, kind in ipairs({ "target", "active", "learning" }) do
        local t = Timers.New({ id = "TRIP-" .. kind, kind = kind, duration = 30 })
        t:Start(); advance(1); t:Start()
    end
    local faded = Timers.New({ id = "TRIP-fade", kind = "cd", duration = 30, fade = true })
    faded:Start(); advance(1); faded:Start()
    eq(Tele.Count(), 0, "target / active / learning / faded timers are exempt from the tripwire")
end
do  -- ring discipline: additive, bounded, cleared in place
    Tele.Clear()
    local db = Addon.db
    db[Tele.RING_KEY] = nil                 -- prove the key is created LAZILY, on first write
    local before = {}
    for k in pairs(db) do before[k] = true end
    Tele.Write("timer.refresh", { enc = "x" })
    local added = {}
    for k in pairs(db) do if not before[k] then added[#added + 1] = k end end
    eq(table.concat(added, ","), "engineLog", "the ring writes exactly ONE new SavedVariables key")
    local live = Tele.Ring(false)
    for i = 1, Tele.MAX + 30 do Tele.Write("timer.refresh", { enc = i }) end
    eq(Tele.Count(), Tele.MAX, "the ring is BOUNDED at its cap")
    ck(Tele.Dropped() > 0, "…and counts what it dropped")
    Tele.Clear()
    ck(Addon.db.engineLog == live, "Clear() preserves the SavedVariables table IDENTITY (in place)")
    eq(Tele.Count(), 0, "…and empties it")
end
endgate()

----------------------------------------------------------------------
-- GATE LIFE — §2 lifecycle
----------------------------------------------------------------------
gate("LIFE  §2 lifecycle: engage paths, lockouts, wipe matrix, end")

-- A minimal encounter used by the path tests.
local function freshEncounter(id, over)
    Addon.encounters, Addon.encountersById = {}, {}
    Addon.encByCreature, Addon.encByEncounterId, Addon.encByZone = {}, {}, {}
    local def = {
        id = id or "fixture", name = "Fixture Boss", zone = 533,
        encounterId = 1107, creatureId = { 15956 },
        detect = { mode = "combat", yell = { "You are mine now." } },
        combat = {},
    }
    if over then for k, v in pairs(over) do def[k] = v end end
    local enc = Addon:RegisterEncounter(def)
    return enc
end

local function resetLife()
    Life:Reset()
    Sched:Flush()
    Timers.StopAll()
    clearWorld()
    W.difficultyID, W.instanceType, W.instanceID, W.inInstance = 9, "raid", 533, true
    Life.armedCombat, Life.armedHealthBoot, Life.healthSuppressed = true, true, false
end

do  -- §1.2 the arming timeline
    Life:Reset(); Sched:Flush()
    Life:Boot()
    ck(not Life.armedCombat, "combat-state pull detection is NOT armed at load")
    ck(not Life:HealthArmed(), "health-based pull detection is NOT armed at load")
    advance(1.4)
    ck(not Life.armedCombat, "…still disarmed at 1.4 s")
    advance(0.2)
    ck(Life.armedCombat, "combat-state pull detection arms at +1.5 s (§12)")
    ck(not Life:HealthArmed(), "…health detection is still disarmed")
    advance(19)
    ck(Life:HealthArmed(), "health-based pull detection arms at +20 s (so a /reload is not a fresh pull)")
end

do  -- PATH (a) ENCOUNTER_START
    resetLife()
    local enc = freshEncounter("path_a")
    local rt = Life:OnEncounterStart(1107)
    ck(rt ~= nil, "PATH (a): ENCOUNTER_START starts combat on a matching encounter id")
    eq(rt and rt.delay, 0, "…with delay 0 (highest-fidelity path)")
    eq(rt and rt.trigger, "encounter", "…tagged with its trigger")
    Life:EndCombat(rt, false, "test")
    resetLife()
    freshEncounter("path_a_opt", { detect = { mode = "combat", noEncounterStart = true } })
    local rt2, why = Life:OnEncounterStart(1107)
    ck(rt2 == nil and why == "opted_out", "…and a module can OPT OUT of the path")
end

do  -- PATH (b) INSTANCE_ENCOUNTER_ENGAGE_UNIT is INERT on Era (§10.22)
    resetLife(); Tele.Clear()
    freshEncounter("path_b")
    W.bossUnits[1] = true
    setUnit("boss1", { cid = 15956, combat = true, hp = 100, hpmax = 100 })
    local rt, why = Life:OnEngageUnit()
    ck(rt == nil and why == "inert_on_era",
       "PATH (b): INSTANCE_ENCOUNTER_ENGAGE_UNIT NEVER starts combat on Era (§10.22)")
    eq(Life:AnyEngaged(), false, "…nothing is engaged")
    ck(Tele.Count() >= 1, "…but if it ever DOES fire with a known boss, that is recorded as news")
    eq(Tele.Ring(false)[1].kind, "lifecycle.inert", "…under the inert-path kind")
end

do  -- PATH (c) PLAYER_REGEN_DISABLED + the three sweeps
    resetLife()
    local enc = freshEncounter("path_c")
    Life.armedCombat = false
    eq(Life:OnRegenDisabled(), nil, "PATH (c): regen-disabled is IGNORED ENTIRELY before the 1.5 s arm")
    Life.armedCombat = true
    W.group = { "player", "raid1" }
    setUnit("raid1", { guid = "Player-1-BBBB", player = true, combat = true })
    setUnit("raid1target", { cid = 15956, combat = true, hp = 100, hpmax = 100 })
    Life:OnRegenDisabled()
    eq(Life.pendingSweeps, 3, "…and schedules THREE sweeps")
    ck(Life.healthSuppressed, "…disabling the health path while they are pending")
    advance(0.6)
    ck(Life:IsEngaged("path_c"), "the +0.5 s sweep finds the boss on a group member's target and engages")
    local rt = Life:GetRuntime("path_c")
    near(rt.delay, 0.5, 0.001, "…with the sweep's delay carried into the pull time")
    advance(1.6)
    ck(not Life.healthSuppressed, "the health path re-arms at +2.1 s after the sweeps (§12)")
    Life:EndCombat(rt, false, "test")
end

do  -- PATH (c) guards: pets and out-of-combat mobs are rejected at delay > 0
    resetLife()
    freshEncounter("path_c_pet")
    W.group = { "player", "raid1" }
    setUnit("raid1", { guid = "Player-1-BBBB", player = true, combat = true })
    setUnit("raid1target", { cid = 15956, combat = false, hp = 100, hpmax = 100 })
    Life:Sweep(0.5)
    eq(Life:AnyEngaged(), false, "a sweep at delay > 0 REQUIRES the matched mob to be in combat")
    setUnit("raid1target", { cid = 15956, combat = true, hp = 100, hpmax = 100, groupPet = true })
    Life:Sweep(0.5)
    eq(Life:AnyEngaged(), false,
       "…and rejects a group member's PET (a hunter pet is not the boss)")
    setUnit("raid1target", { cid = 15956, combat = true, hp = 100, hpmax = 100 })
    Life:Sweep(0.5)
    ck(Life:IsEngaged("path_c_pet"), "…while a genuine in-combat non-group mob engages")
end

do  -- PATH (c) delay-0 sweep needs only "somebody's target"
    resetLife()
    freshEncounter("path_c_zero")
    W.group = { "player" }
    setUnit("playertarget", { cid = 15956, combat = false, hp = 100, hpmax = 100 })
    Life:Sweep(0)
    ck(Life:IsEngaged("path_c_zero"),
       "a sweep at delay 0 (the world-boss chat path) requires only that the mob is somebody's target")
end

do  -- PATH (c) friendly veto
    resetLife()
    freshEncounter("path_c_friend", { detect = { mode = "combat", noFriendlyEngage = true } })
    W.group = { "player" }
    setUnit("playertarget", { cid = 15956, combat = true, hp = 100, hpmax = 100, friend = true })
    Life:Sweep(0.5)
    eq(Life:AnyEngaged(), false, "'don't engage friendly units' vetoes the sweep path")
end

do  -- PATH (d) chat trigger, inside vs outside an instance
    resetLife()
    freshEncounter("path_d")
    eq(Life:OnChat("CHAT_MSG_MONSTER_YELL", "You are mine now."), 1,
       "PATH (d): a matching boss yell INSIDE an instance starts combat outright")
    ck(Life:IsEngaged("path_d"), "…and the encounter is engaged")
    resetLife()
    freshEncounter("path_d_out")
    W.inInstance = false
    W.group = { "player" }
    setUnit("playertarget", { cid = 15956, combat = true, hp = 100, hpmax = 100 })
    Life:OnChat("CHAT_MSG_MONSTER_YELL", "You are mine now.")
    eq(Life:AnyEngaged(), false, "…OUTDOORS the same yell does NOT start combat immediately")
    advance(0.1)
    ck(Life:IsEngaged("path_d_out"),
       "…it triggers a delay-0 target sweep instead (a yell heard across a zone is not a pull)")
    resetLife()
    freshEncounter("path_d_none")
    eq(Life:OnChat("CHAT_MSG_MONSTER_YELL", "Some other yell"), 0, "a non-matching yell does nothing")
end

do  -- PATH (e) UNIT_HEALTH_FREQUENT, every gate
    resetLife()
    freshEncounter("path_e")
    setUnit("target", { cid = 15956, combat = true, hp = 99, hpmax = 100 })
    Life.armedHealthBoot = false
    local rt, why = Life:OnUnitHealth("target")
    ck(rt == nil and why == "unarmed", "PATH (e): the health path is inert before its 20 s arm")
    Life.armedHealthBoot = true
    Life.healthSuppressed = true
    rt, why = Life:OnUnitHealth("target")
    ck(rt == nil, "…and while a regen-disabled sweep is pending")
    Life.healthSuppressed = false
    setUnit("target", { cid = 15956, combat = false, hp = 99, hpmax = 100 })
    rt, why = Life:OnUnitHealth("target")
    eq(why, "not_in_combat", "…the unit must be in combat")
    setUnit("target", { cid = 15956, combat = true, hp = 1, hpmax = 100 })
    rt, why = Life:OnUnitHealth("target")
    eq(why, "below_two_percent", "…health below 2 % is ignored outright")
    setUnit("target", { cid = 15956, combat = true, hp = 99, hpmax = 100 })
    rt = Life:OnUnitHealth("target")
    ck(rt ~= nil, "…a boss above 97 % engages")
    near(rt.delay, 0.5, 0.001, "…with a flat 0.5 s delay (§12)")
    Life:EndCombat(rt, false, "t"); Life:ClearLockout("path_e")
    for k in pairs(Life.healthCache) do Life.healthCache[k] = nil end
    Life.lastCombatFlagAt = CLOCK - 7
    setUnit("target", { cid = 15956, combat = true, hp = 50, hpmax = 100 })
    rt = Life:OnUnitHealth("target")
    near(rt and rt.delay, 7, 0.05,
         "…a boss BELOW 97 % engages with min(time since the combat flag, 20 s)")
    Life:EndCombat(rt, false, "t"); Life:ClearLockout("path_e")
    for k in pairs(Life.healthCache) do Life.healthCache[k] = nil end
    Life.lastCombatFlagAt = CLOCK - 500
    rt = Life:OnUnitHealth("target")
    near(rt and rt.delay, 20, 0.001, "…clamped at 20 s")
    Life:EndCombat(rt, false, "t"); Life:ClearLockout("path_e")
    Life.healthCache[15956] = 55
    rt, why = Life:OnUnitHealth("target")
    eq(why, "cached", "…and a creature that already has a cached health entry is not re-started")
end

do  -- §2.2 the lockout matrix
    resetLife()
    local enc = freshEncounter("lock")
    local rt = Life:StartCombat(enc, 0, "encounter")
    Life:EndCombat(rt, false, "kill")            -- KILL
    local allowed, why, left = Life:CanStart(enc, "sweep")
    ck(not allowed and why == "kill", "after a KILL the module refuses to start")
    near(left, 120, 0.5, "…for 120 s (§12)")
    advance(121)
    ck((Life:CanStart(enc, "sweep")), "…and is free afterwards")

    resetLife()
    enc = freshEncounter("lock2")
    rt = Life:StartCombat(enc, 0, "encounter")
    Life:EndCombat(rt, true, "wipe")             -- WIPE
    allowed, why, left = Life:CanStart(enc, "sweep")
    ck(not allowed and why == "wipe", "after a WIPE the module refuses to start")
    near(left, 20, 0.5, "…for 20 s")
    allowed, why, left = Life:CanStart(enc, "encounter")
    near(left, 3, 0.5, "…reduced to 3 s when the trigger is ENCOUNTER_START (that event is trustworthy)")
    ck(Life:CanStart(enc, "zone"), "…and BYPASSED entirely by a zone load")

    resetLife()
    enc = freshEncounter("lock3", { combat = { killLockout = 5, wipeLockout = 2 } })
    rt = Life:StartCombat(enc, 0, "sweep")
    Life:EndCombat(rt, false, "kill")
    local _, _, l = Life:CanStart(enc, "sweep")
    near(l, 5, 0.5, "…both lockouts are module-overridable")

    resetLife()
    local a = freshEncounter("multi_a")
    local b = Addon:RegisterEncounter({ id = "multi_b", zone = 533, creatureId = { 15957 },
                                        detect = { mode = "combat", noMultiBoss = true }, combat = {} })
    Life:StartCombat(a, 0, "sweep")
    local okb, whyb = Life:CanStart(b, "sweep")
    ck(not okb and whyb == "multiboss",
       "'no multi-boss' refuses to start while any other module is engaged")
end

do  -- §2.3 the difficulty SNAPSHOT (§10.8/§10.9)
    resetLife()
    local enc = freshEncounter("diff")
    for id, want in pairs({ [9] = "raid40", [186] = "raid40", [148] = "raid20", [185] = "raid20",
                            [215] = "raid20", [3] = "raid10", [175] = "raid10", [198] = "raid10",
                            [0] = "worldboss", [1] = "party", [2] = "heroic" }) do
        W.difficultyID = id
        eq(Life:SnapshotDifficulty().bucket, want, ("Era difficulty %d maps to %s"):format(id, want))
    end
    W.difficultyID, W.instanceID = 9, 309
    eq(Life:SnapshotDifficulty().bucket, "raid10",
       "Zul'Gurub (instance 309) is FORCE-mapped to the 10-man bucket whatever the client says")
    W.instanceID, W.difficultyID = 533, 9
    local rt = Life:StartCombat(enc, 0, "sweep")
    W.difficultyID = 0                        -- a release corrupts the live value mid-wipe
    eq(rt.difficulty.bucket, "raid40",
       "the difficulty is SNAPSHOT at engage, so a post-release corruption cannot rewrite the report")
    Life:EndCombat(rt, true, "wipe")
end

do  -- §2.4 the wipe verdict matrix, row by row
    resetLife()
    local enc = freshEncounter("wipe")
    local rt = Life:StartCombat(enc, 0, "sweep")
    local V = Life.VERDICT

    rt.difficulty = { instanceType = "raid", id = 11 }
    eq(Life:ClassifyWipe(rt), V.NOT_WIPE_TRIVIAL, "ROW 1: difficulty index 11 is never a wipe")
    rt.difficulty = { instanceType = "scenario", id = 9 }
    eq(Life:ClassifyWipe(rt), V.NOT_WIPE_TRIVIAL, "ROW 1: scenario content is never a wipe")

    rt.difficulty = { instanceType = "raid", id = 9 }
    W.encounterInProgress = true
    eq(Life:ClassifyWipe(rt), V.NOT_WIPE_ENCOUNTER_PROGRESS,
       "ROW 2: IsEncounterInProgress() is not a wipe")
    W.encounterInProgress = false

    rt.difficulty = { instanceType = "none", id = 0, worldBoss = true }
    W.units.player.dead = true
    eq(Life:ClassifyWipe(rt), V.NOT_WIPE_WORLDBOSS_DEATH,
       "ROW 3: dying at a world boss is not a wipe")
    W.units.player.dead = false

    rt.difficulty = { instanceType = "raid", id = 9 }
    rt.bossSeen = true
    W.bossUnits = {}
    eq(Life:ClassifyWipe(rt), V.WIPE_BOSS_GONE,
       "ROW 4 (type 2): boss units existed, instance is a raid, and none of boss1..10 remains")
    rt.bossSeen = false

    W.group = { "player", "raid1" }
    setUnit("raid1", { guid = "P2", player = true, combat = true, dead = false })
    eq(Life:ClassifyWipe(rt), V.NOT_WIPE_COMBAT_LIVE,
       "ROW 5: a member in combat AND alive means the fight continues")
    W.units.raid1.dead = true
    W.units.player.dead = true
    eq(Life:ClassifyWipe(rt), V.WIPE_NO_COMBATANT,
       "ROW 5 (type 1): nobody is simultaneously in combat and not dead-or-ghost")

    -- feign death / vanish: the player drops combat, the rest of the raid holds
    W.units.player.dead, W.units.raid1.dead = false, false
    W.units.player.combat = false
    eq(Life:ClassifyWipe(rt), V.NOT_WIPE_COMBAT_LIVE,
       "…which is exactly why feign death / vanish does not trip a wipe")
    -- spirit release: a dead member is excluded from the in-combat test
    W.units.raid1.dead = true
    eq(Life:ClassifyWipe(rt), V.WIPE_NO_COMBATANT,
       "…and why spirit release DOES, once the confirmation window elapses")
    Life:EndCombat(rt, true, "t")
end

do  -- §2.4 poll + CONFIRMATION window
    resetLife()
    local enc = freshEncounter("confirm")
    W.group = { "player" }
    local rt = Life:StartCombat(enc, 0, "sweep")
    W.units.player.combat = false           -- everyone drops combat
    advance(3.1)
    ck(rt.confirming, "the poll enters CONFIRMATION mode on the first wipe verdict")
    ck(Life:IsEngaged("confirm"),
       "…without ending the fight yet (the window is measured from last-valid-combat)")
    W.units.player.combat = true            -- combat comes back: a false alarm
    advance(3.1)
    ck(not rt.confirming, "a 'not a wipe' pass STAMPS last-valid-combat and leaves confirmation mode")
    ck(Life:IsEngaged("confirm"), "…and the fight survives the false alarm")
    W.units.player.combat = false
    advance(3.1)
    ck(rt.confirming and Life:IsEngaged("confirm"),
       "…a fresh drop re-enters confirmation without ending immediately")
    advance(3.1)
    ck(not Life:IsEngaged("confirm"), "…and a sustained drop past the 5 s window ends the fight")

    resetLife()
    local wb = freshEncounter("wb")
    W.difficultyID = 0
    local rt2 = Life:StartCombat(wb, 0, "sweep")
    W.units.player.combat = false
    advance(9)
    ck(Life:IsEngaged("wb"), "a WORLD BOSS holds for the longer 15 s confirmation window")
    advance(12)
    ck(not Life:IsEngaged("wb"), "…then ends")
    W.difficultyID = 9

    resetLife()
    local ch = freshEncounter("chroma", { combat = { wipeWindow = 20 } })
    local rt3 = Life:StartCombat(ch, 0, "sweep")
    W.units.player.combat = false
    advance(12)
    ck(Life:IsEngaged("chroma"), "a module may RAISE its own wipe window (Chromaggus's 20 s)")
    advance(12)
    ck(not Life:IsEngaged("chroma"), "…and it then ends on the raised window")
end

do  -- §2.3 step 4: the first wipe check
    resetLife()
    local kt = freshEncounter("kt", { combat = { minCombatTime = 60 } })
    W.group = { "player" }
    local rt = Life:StartCombat(kt, 0, "sweep")
    W.units.player.combat = false
    advance(10)
    ck(Life:IsEngaged("kt"),
       "the first wipe check is max(minCombatTime - delay, 3 s), so a 60 s minimum holds the fight open")
    advance(56)
    ck(not Life:IsEngaged("kt"), "…and the poll takes over afterwards")
end

do  -- §2.5 the four kill paths
    resetLife()
    local enc = freshEncounter("kill_a")
    local rt = Life:StartCombat(enc, 0, "sweep")
    eq(Life:OnUnitDied(15956), 1, "KILL PATH 1: a matching UNIT_DIED creature id ends the fight")
    ck(not Life:IsEngaged("kill_a"), "…successfully")

    resetLife()
    enc = freshEncounter("kill_multi", { creatureId = { 16062, 16063 } })
    rt = Life:StartCombat(enc, 0, "sweep")
    Life:OnUnitDied(16062)
    ck(Life:IsEngaged("kill_multi"), "…a multi-mob encounter only ends when ALL ids are down")
    Life:OnUnitDied(16063)
    ck(not Life:IsEngaged("kill_multi"), "…and then it ends")

    resetLife()
    enc = freshEncounter("kill_several", { creatureId = { 16062, 16063 },
                                           combat = { severalCreatureIdsOneBoss = true } })
    rt = Life:StartCombat(enc, 0, "sweep")
    Life:OnUnitDied(16062); Life:OnUnitDied(16063)
    ck(Life:IsEngaged("kill_several"),
       "…'several creature ids, one boss' means death NEVER ends combat by itself")
    Life:EndCombat(rt, false, "t")

    resetLife()
    enc = freshEncounter("kill_nodeath", { combat = { noDeathKill = true } })
    rt = Life:StartCombat(enc, 0, "sweep")
    eq(Life:OnUnitDied(15956), 0, "…and death-based kill detection can be disabled entirely")
    Life:EndCombat(rt, false, "t")

    resetLife()
    enc = freshEncounter("kill_b")
    rt = Life:StartCombat(enc, 0, "sweep")
    eq(Life:OnEncounterEnd(1107, 1), 1, "KILL PATH 2: ENCOUNTER_END with success 1 ends the fight")

    resetLife()
    enc = freshEncounter("kill_c")
    rt = Life:StartCombat(enc, 0, "sweep")
    eq(Life:OnBossKill(1107), 1, "KILL PATH 3: BOSS_KILL on the encounter id ends the fight")

    resetLife()
    enc = freshEncounter("kill_d", { combat = { killMessage = { type = "yell", text = { "I die." } } } })
    rt = Life:StartCombat(enc, 0, "sweep")
    eq(Life:OnKillMessage("yell", "I die."), 1, "KILL PATH 4: a declared kill chat message ends the fight")
end

do  -- §2.6 what an end does
    resetLife()
    local enc = freshEncounter("endacct", { legacy = { raidId = "naxxramas", bossId = "anub" } })
    local rt = Life:StartCombat(enc, 0, "sweep")
    ck(Addon.active ~= nil and Addon.active.bossId == "anub",
       "engaging populates the legacy Addon.active contract")
    advance(10)
    local rep = Life:EndCombat(rt, true, "wipe")
    eq(rep.counted, false, "a wipe under 30 s is NOT counted as a real attempt (§2.6)")
    ck(rep.difficulty ~= nil, "the report carries the engage-time difficulty snapshot")

    resetLife()
    enc = freshEncounter("endacct2", { legacy = { raidId = "naxxramas", bossId = "anub2" } })
    rt = Life:StartCombat(enc, 0, "sweep")
    advance(45)
    rep = Life:EndCombat(rt, true, "wipe")
    eq(rep.counted, true, "…a wipe over 30 s is")
    local s = Addon:GetBossStats("naxxramas", "anub2")
    eq(s.wipes, 1, "…and lands in the persisted stats")

    resetLife()
    enc = freshEncounter("endkill", { legacy = { raidId = "naxxramas", bossId = "anub3" } })
    rt = Life:StartCombat(enc, 0, "sweep")
    advance(200)
    rep = Life:EndCombat(rt, false, "kill")
    local ks = Addon:GetBossStats("naxxramas", "anub3")
    eq(ks.kills, 1, "a kill increments the kill counter")
    ck(ks.kills <= (ks.pulls or 0), "…clamped so kills can never exceed pulls")
    near(ks.bestTime, 200, 1, "…and records the best time")
    ck(Addon.active == nil, "with the engaged list empty, Addon.active is cleared")
end

do  -- §2.6 the teardown timings: aura grace at +2 s, full timer sweep at +3 s
    resetLife()
    local enc = freshEncounter("teardown")
    local rt = Life:StartCombat(enc, 0, "sweep")
    rt.timers.manual = Timers.New({ id = "teardown:bar", kind = "cd", duration = 300 })
    rt.timers.manual:Start()
    Life:EndCombat(rt, false, "kill")
    eq(Timers.Count(), 1,
       "at the instant of the end the bars are STILL up (events arriving after the end resolve)")
    ck(rt.auraGrace, "…and aura-removed handling is inside its 2 s grace")
    advance(2.1)
    ck(not rt.auraGrace, "the aura grace closes at +2 s")
    ck(Timers.Count() == 1, "…the timer sweep has not run yet")
    advance(1.1)
    eq(Timers.Count(), 0, "…and the FULL timer stop sweeps them at +3 s")
end

do  -- §2.3 step 5 record eligibility
    resetLife()
    local enc = freshEncounter("rec")
    W.difficultyID = 0
    setUnit("target", { cid = 15956, combat = true, hp = 90, hpmax = 100 })
    W.group = { "player" }
    local rt = Life:StartCombat(enc, 0, "sweep")
    eq(rt.recordEligible, false, "a world boss engaged below 98 % is NOT record-eligible")
    Life:EndCombat(rt, false, "t")
    W.difficultyID = 9
    resetLife()
    enc = freshEncounter("rec2")
    local rt2 = Life:StartCombat(enc, 6, "health")
    eq(rt2.recordEligible, false, "a health-path start with a delay over 4 s is NOT record-eligible")
end
endgate()

----------------------------------------------------------------------
-- GATE API — grammar validation + the expressiveness smoke test
----------------------------------------------------------------------
gate("API  encounter grammar: validation + expressiveness")
do  -- validation refuses malformed data instead of throwing
    Addon.encounters, Addon.encountersById = {}, {}
    Addon.encByCreature, Addon.encByEncounterId, Addon.encByZone = {}, {}, {}
    local _, errs = Addon:RegisterEncounter({ id = "bad1" })
    ck(#errs > 0, "an encounter with no creature id / encounter id / chat trigger is refused")
    _, errs = Addon:RegisterEncounter({ id = "bad2", creatureId = 1,
        timers = { { key = "x", duration = "v30-10" } } })
    ck(#errs > 0, "an inverted variance window is refused")
    _, errs = Addon:RegisterEncounter({ id = "bad3", creatureId = 1,
        timers = { { key = "x", duration = 10, start = { on = "NOT_AN_EVENT" } } } })
    ck(#errs > 0, "an unknown trigger event is refused")
    _, errs = Addon:RegisterEncounter({ id = "bad4", creatureId = 1,
        warnings = { { key = "w", role = "Wizard" } } })
    ck(#errs > 0, "an unknown role gate is refused")
    _, errs = Addon:RegisterEncounter({ id = "bad5", creatureId = 1,
        timers = { { key = "dup", duration = 1 } }, warnings = { { key = "dup" } } })
    ck(#errs > 0, "a duplicate row key is refused (option keys must be unique)")
    _, errs = Addon:RegisterEncounter({ id = "bad6", creatureId = 1,
        warnings = { { key = "w", tier = "special", sound = 9 } } })
    ck(#errs > 0, "a special-warning sound tier outside 1..5 is refused")
    ck(Tele.Count() > 0, "…and every refusal is traceable in the telemetry ring")
    Tele.Clear()
end

do  -- per-occurrence duration resolution: pull / phase / sequence / sequenceFrom / schedule
    local R = API.ResolveDuration
    eq(R({ pull = "v5.7-11.8", duration = "v21-27" }, 1), "v5.7-11.8",
       "occurrence 1 takes the PULL value when one is declared (Lucifron)")
    eq(R({ pull = "v5.7-11.8", duration = "v21-27" }, 2), "v21-27", "…later occurrences take the CD")
    eq(R({ duration = 11.3, phaseDuration = { [2] = "v25.9-35.7" } }, 2, 2), "v25.9-35.7",
       "a per-stage override wins in that stage (Thaddius P2 polarity)")
    local loatheb = { pull = 121.3, sequence = { 29.1, 32.4 } }
    eq(R(loatheb, 2), 29.1, "an alternating sequence walks its entries (Loatheb doom 29.1/32.4)")
    eq(R(loatheb, 3), 32.4, "…alternating")
    eq(R(loatheb, 4), 29.1, "…and wrapping")
    local late = { duration = 5, sequenceFrom = { [7] = { 9.7, 19.4, 11.3 } } }
    eq(R(late, 7), 9.7, "a sequence can CHANGE at the Nth occurrence (Loatheb's 7th doom)")
    eq(R(late, 8), 19.4, "…and continues in the new sequence")
    local noth = { schedule = { 90.8, 109, 173, 93, 35 } }
    eq(R(noth, 1), 90.8, "a hard-coded cycle is walked verbatim (Noth's teleports)")
    eq(R(noth, 5), 35, "…and its LAST entry repeats forever ('4th+ = 35 s')")
    eq(R(noth, 9), 35, "…still repeating")
end

-- THE EXPRESSIVENESS SMOKE TEST: one synthetic encounter using EVERY grammar
-- feature the encounters spec needs, driven headless from engage to re-engage.
local SMOKE
do
    resetLife()
    Addon.encounters, Addon.encountersById = {}, {}
    Addon.encByCreature, Addon.encByEncounterId, Addon.encByZone = {}, {}, {}
    local errs
    SMOKE, errs = Addon:RegisterEncounter({
        id = "smoke", name = "Grammar Fixture", zone = 533,
        encounterId = { 9001, 9002 },                 -- multi-id encounter
        creatureId = { 90001, 90002 },                -- multi-mob
        legacy = { raidId = "naxxramas", bossId = "smoke" },   -- ESCAPE-HATCH SEAM
        special = "smoke_special",                    -- registered special module
        detect = {
            mode = "combat_yell",
            yell = { "Let the games begin!" },
            yellFind = { "partial trigger" },
            yellPattern = { "^Regex .+ trigger$" },
            emote = { "%s flinches as its skin shimmers." },
            noFriendlyEngage = true,
        },
        combat = {
            minCombatTime = 5, wipeWindow = 8, killLockout = 30, wipeLockout = 60,
            healthPoll = 1, highestHealth = true,
            killMessage = { type = "yell", text = { "You have won." } },
        },
        timers = {
            { key = "cd_var", spellId = 19702, kind = "cd",
              pull = "v2-4", duration = "v6-9",
              start = { on = "pull" }, restart = { on = "SPELL_CAST_SUCCESS", spellId = 19702 },
              color = 3, countdown = { depth = 3 } },
            { key = "cast", spellId = 19703, kind = "cast", duration = 2,
              start = { on = "SPELL_CAST_START", spellId = 19703 } },
            { key = "target_dot", spellId = 20604, kind = "target", duration = 15, perTarget = true,
              start = { on = "SPELL_AURA_APPLIED", spellId = 20604 },
              stop  = { on = "SPELL_AURA_REMOVED", spellId = 20604 } },
            { key = "np_cd", spellId = 22275, kind = "cd", duration = "v8.1-10.9", nameplate = true,
              start = { on = "SPELL_CAST_SUCCESS", spellId = 22275 } },
            { key = "berserk", kind = "berserk", duration = 300, start = { on = "pull" } },
            { key = "phase_cd", kind = "cd", duration = 11.3,
              phaseDuration = { [2] = "v25.9-35.7" },
              start = { on = "stage" } },
            { key = "seq_cd", kind = "cd", pull = 121.3, sequence = { 29.1, 32.4 },
              start = { on = "SPELL_CAST_SUCCESS", spellId = 29204 }, count = true },
            { key = "off_by_default", kind = "cd", duration = 10, default = false,
              start = { on = "pull" } },
            { key = "tank_only", kind = "cd", duration = 10, role = "Tank|Healer",
              start = { on = "pull" } },
            { key = "warlock_only", kind = "cd", duration = 30, classDefault = "WARLOCK",
              start = { on = "pull" } },
            { key = "stop_on_death", kind = "cd", duration = 12,
              start = { on = "pull" },
              stop = { on = "UNIT_DIED", creatureId = 90002 } },
        },
        warnings = {
            { key = "w_announce", tier = "announce", color = 3, text = "Doom incoming",
              trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19702 } },
            { key = "w_special", tier = "special", sound = 1, voice = "targetyou",
              text = "Mind control on YOU", yell = "MC on me!",
              trigger = { on = "SPELL_AURA_APPLIED", spellId = 20604, dest = "player" } },
            { key = "w_combined", tier = "announce", color = 2, combine = 0.3, noFilter = true,
              text = "Sting on group", triggers = {
                  { on = "SPELL_AURA_APPLIED", spellId = 26180 },
                  { on = "SPELL_AURA_REFRESH", spellId = 26180 } } },
            { key = "w_precise", tier = "announce", color = 2, precise = { total = 5 },
              text = "Everyone hit", trigger = { on = "SPELL_DAMAGE", spellId = 26102 } },
            { key = "w_antispam", tier = "announce", color = 2, antispam = 5, text = "Throttled",
              trigger = { on = "SPELL_CAST_SUCCESS", spellId = 21341 } },
            { key = "w_health", tier = "announce", color = 2, text = "Enrage soon",
              trigger = { on = "health", pct = 25, sync = true } },
            { key = "w_schedule", tier = "special", sound = 3, voice = "breathsoon",
              text = "Breath soon", trigger = { on = "schedule" } },
            { key = "w_stackhigh", tier = "special", sound = 1, voice = "stackhigh",
              text = "Stacks at %d" },
            { key = "w_school", tier = "announce", color = 1, text = "Frost hit",
              trigger = { on = "SPELL_DAMAGE", school = 16 } },
            { key = "w_interrupt", tier = "special", sound = 1, voice = "kickcast",
              filter = "interrupt", text = "Interrupt!",
              trigger = { on = "SPELL_CAST_START", spellId = 28478 } },
            { key = "w_count", tier = "announce", color = 2, count = true, text = "Spore %d",
              trigger = { on = "SPELL_CAST_SUCCESS", spellId = 29234 } },
        },
        scans = {
            { key = "scan_poll", type = "poll", interval = 0.2, tries = 5,
              filter = "playersOnly", excludeTank = true, delay = 0.1,
              on = { on = "SPELL_CAST_START", spellId = 26134 } },
            { key = "scan_event", type = "event", scope = "boss1..boss5", abort = 1.5, allowTank = true,
              on = { on = "targetChanged" } },
            { key = "scan_repeated", type = "repeated", interval = 0.1 },
        },
        phases = {
            { stage = 2, on = "UNIT_DIED", creatureId = 90002 },
            { stage = 0.5, on = "emote", textFind = "intermission" },
            { stage = 0, on = "yell", text = { "Phase up!" } },
            { stage = 3, on = "health", pct = 20, sync = true, pre = true },
        },
        counters = {
            { key = "mark", scope = "global", step = 1, antispam = 0,
              inc = { on = "SPELL_CAST_SUCCESS", spellId = 28832 },
              reset = { on = "pull" }, announce = "Mark %d", announceAt = { 3 } },
            { key = "mystacks", scope = "self",
              inc = { on = "SPELL_AURA_APPLIED_DOSE", spellId = 26050, dest = "player" },
              threshold = { at = 3, warning = "w_stackhigh" } },
            { key = "drakonid", scope = "census", from = 42, step = 1,
              dec = { on = "UNIT_DIED", creatureId = 14261 },
              announce = "%d left", announceAt = { 41, 40 } },
            { key = "frosthits", scope = "boss",
              inc = { on = "SPELL_DAMAGE", school = 16 },
              rate = { window = 7, fallback = 15 } },
        },
        states = {
            { key = "viscidus", initial = "normal", transitions = {
                { on = "emote", textFind = "begins to slow", to = "freeze1",
                  announce = "Freeze 1/3" },
                { on = "emote", textFind = "is frozen solid", to = "frozen",
                  announce = "Freeze 3/3",
                  actions = { { stopTimer = "cd_var" }, { resetCounter = "frosthits" } } },
                { on = "emote", textFind = "ready to shatter", to = "shatter2",
                  actions = { { startTimer = "berserk" } } },
            } },
        },
        schedule = {
            { key = "sched_gaps", gaps = { 2, 3, 5 }, announce = "Wave %d", immediate = false },
            { key = "sched_at", at = { 1.5, 4 }, announce = "Breath window" },
        },
        icons = {
            { key = "icon_mc", icon = 1, duration = 3, on = { on = "SPELL_AURA_APPLIED", spellId = 20604 } },
        },
        OnEngage = function(enc, rt) enc.__engaged = (enc.__engaged or 0) + 1 end,
        OnEnd    = function(enc, rt, wiped) enc.__ended = (enc.__ended or 0) + 1 end,
    })
    ck(SMOKE ~= nil, "the synthetic encounter using EVERY grammar feature REGISTERS")
    eq(errs and #errs or -1, 0, "…with zero validation errors")
end

if SMOKE then
    -- record everything the engine emits so the drive can be asserted without a UI
    Addon:SetEventRecording(true)
    Addon:ClearEventLog()
    Addon._suppressLegacyAlerts = true
    Addon.RoleResolver  = function(gateStr) return gateStr:find("Tank") ~= nil end
    Addon.ClassResolver = function() return "PRIEST" end

    resetLife()
    W.group = { "player" }
    setUnit("target", { cid = 90001, combat = true, hp = 100, hpmax = 100 })

    -- ENGAGE via the chat path
    eq(Life:OnChat("CHAT_MSG_MONSTER_YELL", "Let the games begin!"), 1,
       "SMOKE: the encounter engages through its declared yell")
    local rt = Life:GetRuntime("smoke")
    ck(rt ~= nil, "…producing a live runtime")
    eq(SMOKE.__engaged, 1, "…and calling the encounter's own OnEngage hook")

    -- pull-seeded timers and schedules
    ck(rt.timers.cd_var ~= nil, "pull-triggered timers started")
    local b = rt.timers.cd_var:Get()
    ck(b and b.min == 2 and b.max == 4, "…using the PULL variance value, not the recurring cd")
    ck(rt.timers.berserk ~= nil and rt.timers.berserk:Get(), "the berserk bar started at pull")
    ck(rt.timers.off_by_default == nil,
       "a row shipped OFF BY DEFAULT does not start (ship-off defaults honoured)")
    ck(rt.timers.tank_only ~= nil, "a Tank|Healer row starts for a resolved tank")
    ck(rt.timers.warlock_only == nil,
       "a Warlock dynamic class default does NOT start for a Priest")

    -- the declared schedules
    advance(2.1)
    local sawWave, sawBreath = false, false
    for _, e in ipairs(Addon:GetEventLog()) do
        if e.event == "WARN_ANNOUNCE" and tostring(e[3]):find("Wave") then sawWave = true end
        if e.event == "WARN_ANNOUNCE" and tostring(e[3]) == "Breath window" then sawBreath = true end
    end
    ck(sawWave, "a pull-seeded interval-table schedule announces its waves")
    ck(sawBreath, "…and a pull-seeded fixed schedule fires its pre-warnings")

    -- combat-log driven timers + warnings
    Addon:ClearEventLog()
    Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 19702, sourceId = 90001 })
    local sawDoom = false
    for _, e in ipairs(Addon:GetEventLog()) do
        if e.event == "WARN_ANNOUNCE" and e[3] == "Doom incoming" then sawDoom = true end
    end
    ck(sawDoom, "a cast-success trigger fires its announce")
    local b2 = rt.timers.cd_var:Get()
    ck(b2 and b2.min == 6 and b2.max == 9, "…and restarts the cooldown on the RECURRING value")

    -- per-target timers get one bar per name and stop on the aura falling off
    Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 20604, destName = "Bob" })
    Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 20604, destName = "Alice" })
    local n = 0
    for _ in pairs(rt.timers.target_dot.live) do n = n + 1 end
    eq(n, 2, "a per-target timer keeps ONE BAR PER PLAYER")
    Life:Deliver({ on = "SPELL_AURA_REMOVED", spellId = 20604, destName = "Bob" })
    n = 0
    for _ in pairs(rt.timers.target_dot.live) do n = n + 1 end
    eq(n, 1, "…and cancels that player's bar when the aura is removed early")

    -- anti-spam
    Addon:ClearEventLog()
    Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 21341 })
    Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 21341 })
    local throttled = 0
    for _, e in ipairs(Addon:GetEventLog()) do
        if e.event == "WARN_ANNOUNCE" and e[3] == "Throttled" then throttled = throttled + 1 end
    end
    eq(throttled, 1, "a per-key anti-spam window collapses a burst into one alert")

    -- school bitmask filtering
    Addon:ClearEventLog()
    Life:Deliver({ on = "SPELL_DAMAGE", spellId = 1, school = 16 })
    Life:Deliver({ on = "SPELL_DAMAGE", spellId = 1, school = 4 })
    local frost = 0
    for _, e in ipairs(Addon:GetEventLog()) do
        if e.event == "WARN_ANNOUNCE" and e[3] == "Frost hit" then frost = frost + 1 end
    end
    eq(frost, 1, "a school-bitmask filter admits Frost (16) and rejects Fire (4)")

    -- counters, thresholds and census announcements
    eq(rt:GetCount("drakonid"), 42, "a census counter seeds from its declared start")
    Life:Deliver({ on = "UNIT_DIED", creatureId = 14261, destId = 14261 })
    eq(rt:GetCount("drakonid"), 41, "…and counts DOWN on each death")
    Addon:ClearEventLog()
    for i = 1, 3 do
        Life:Deliver({ on = "SPELL_AURA_APPLIED_DOSE", spellId = 26050, destIsPlayer = true })
    end
    local stackWarn = false
    for _, e in ipairs(Addon:GetEventLog()) do
        if e.event == "WARN_SPECIAL" and tostring(e[3]):find("Stacks at 3") then stackWarn = true end
    end
    ck(stackWarn, "a self stack counter fires its threshold special warning at the declared count")

    -- emote state machine, including its actions
    ck(rt:GetState("viscidus") == "normal", "the state machine starts in its declared initial state")
    Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "Viscidus begins to slow down!")
    eq(rt:GetState("viscidus"), "freeze1", "an emote transition advances the machine")
    Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "Viscidus is frozen solid!")
    eq(rt:GetState("viscidus"), "frozen", "…to the frozen state")
    eq(rt.timers.cd_var:Get(), nil, "…and its declared action STOPPED the volley bar")

    -- phase machinery: absolute, half-step and increment
    eq(rt.stage, 1, "the stage register starts at 1")
    Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "the intermission begins")
    eq(rt.stage, 1.5, "0.5 increments by a half (the 'phase 2 intermission' numbering)")
    Life:OnChat("CHAT_MSG_MONSTER_YELL", "Phase up!")
    eq(rt.stage, 2.5, "0 increments by one")
    local tot = select(2, rt:GetStage())
    eq(tot, 2, "stage TOTALITY counts transitions independently of the number")
    ck(rt:StageIs(">", 2), "the stage query API supports greater-than")
    ck(rt:StageIs("~=", 1), "…and not-equal")

    -- health thresholds through the real poll
    Addon:ClearEventLog()
    setUnit("target", { cid = 90001, combat = true, hp = 20, hpmax = 100 })
    Life:PollHealth(rt)
    local enrage = false
    for _, e in ipairs(Addon:GetEventLog()) do
        if e.event == "WARN_ANNOUNCE" and e[3] == "Enrage soon" then enrage = true end
    end
    ck(enrage, "a declared health threshold fires off the 1 s boss-health poll")
    Addon:ClearEventLog()
    Life:PollHealth(rt)
    local again = false
    for _, e in ipairs(Addon:GetEventLog()) do
        if e.event == "WARN_ANNOUNCE" and e[3] == "Enrage soon" then again = true end
    end
    ck(not again, "…exactly once per engagement")

    -- target scanners are DECLARED here and SERVICED by W2; the engine routes them
    Addon:ClearEventLog()
    Life:Deliver({ on = "SPELL_CAST_START", spellId = 26134 })
    local scanned = false
    for _, e in ipairs(Addon:GetEventLog()) do
        if e.event == "SCAN_REQUEST" then scanned = true end
    end
    ck(scanned, "a declared target scan raises SCAN_REQUEST on the seam W2 builds against")

    -- WIPE, then RE-ENGAGE through the lockout
    W.units.player.combat = false
    advance(20)
    ck(not Life:IsEngaged("smoke"), "SMOKE: the fight wipes through the poll + confirmation model")
    advance(4)
    eq(SMOKE.__ended, 1, "…and the encounter's own OnEnd hook runs on the +3 s sweep")
    eq(Timers.Count(), 0, "…with every bar swept up")

    local allowed, why = Life:CanStart(SMOKE, "sweep")
    ck(not allowed and why == "wipe", "SMOKE: the wipe lockout refuses an immediate re-pull")
    advance(61)
    W.units.player.combat = true
    ck(Life:OnChat("CHAT_MSG_MONSTER_YELL", "Let the games begin!") == 1,
       "SMOKE: after the lockout the same yell RE-ENGAGES")
    ck(Life:IsEngaged("smoke"), "…and the encounter runs again from a clean runtime")
    local rt2 = Life:GetRuntime("smoke")
    eq(rt2.stage, 1, "…with the stage register reset")
    eq(rt2:GetCount("drakonid"), 42, "…and the counters re-seeded")
    Life:EndCombat(rt2, false, "test")
    Addon._suppressLegacyAlerts = nil
    Addon:SetEventRecording(false)
end
endgate()

----------------------------------------------------------------------
-- GATE HATCH — the registered-special-module escape hatch
----------------------------------------------------------------------
gate("HATCH  registered-special-module escape hatch")
do
    -- modules.lua is untouched: register a module with the EXACT def shape the five
    -- shipped Naxx specials use, and prove the new lifecycle drives it.
    local log = {}
    Addon:RegisterModule({
        id = "smoke_special", raidId = "naxxramas", bossId = "smoke",
        name = "Fixture Widget", desc = "shape-compatible with the shipped Naxx specials",
        defaults = { enabled = true },
        placeKey = "naxxramas:smoke:widget",
        placeDef = { name = "Widget", icon = "x", style = "icon" },
        Start = function(self) log[#log + 1] = "start" end,
        Stop  = function(self) log[#log + 1] = "stop" end,
        Test  = function(self) log[#log + 1] = "test" end,
        BuildConfig = function(self, parent) log[#log + 1] = "config" end,
    })
    ck(Addon:GetBossModules("naxxramas", "smoke")[1] ~= nil,
       "RegisterModule's def shape is UNCHANGED (the five Naxx specials port without edits)")

    -- the verbatim combat-hook signature
    local seen
    Addon:RegisterCombatHook(function(subevent, sourceGUID, sourceID, destGUID, destID, spellID, spellName)
        seen = { subevent, sourceGUID, sourceID, destGUID, destID, spellID, spellName }
    end)
    resetLife()
    Addon.encounters, Addon.encountersById = {}, {}
    Addon.encByCreature, Addon.encByEncounterId, Addon.encByZone = {}, {}, {}
    local enc = Addon:RegisterEncounter({
        id = "hatch", zone = 533, creatureId = { 90001 }, combat = {},
        detect = { mode = "combat" },
        legacy = { raidId = "naxxramas", bossId = "smoke" },
    })
    local rt = Life:StartCombat(enc, 0, "sweep")
    eq(log[1], "start",
       "engaging an encounter with a `legacy` seam STARTS its registered special modules")
    ck(Addon.active and Addon.active.raidId == "naxxramas" and Addon.active.bossId == "smoke",
       "…and populates the legacy Addon.active contract the widgets read")

    Life:Deliver({ on = "SPELL_CAST_SUCCESS", sourceGUID = "Creature-0-0-0-0-90001-1",
                   sourceId = 90001, destGUID = "Player-1-AAAA", destId = nil,
                   spellId = 28832, spellName = "Mark" })
    ck(seen ~= nil, "a registered combat hook still fires from the new combat-log path")
    eq(seen and seen[1], "SPELL_CAST_SUCCESS", "…with argument 1 = subevent")
    eq(seen and seen[3], 90001, "…argument 3 = source creature id")
    eq(seen and seen[6], 28832, "…argument 6 = spell id")
    eq(seen and seen[7], "Mark", "…argument 7 = spell name (signature unchanged)")

    Life:EndCombat(rt, false, "t")
    advance(4)
    eq(log[#log], "stop", "…and ending the fight STOPS them")
    ck(Addon.active == nil, "…and clears Addon.active")

    -- Debug Only remains a hard kill-switch over the hook path
    Addon.db.settings.debugOnly = true
    seen = nil
    Addon:FireCombatHooks("SPELL_CAST_SUCCESS", "g", 1, "g", 2, 3, "n")
    eq(seen, nil, "Debug Only silences the special-module hook path (blanket kill-switch preserved)")
    Addon.db.settings.debugOnly = false
end
do  -- the retired 1.x data format is REFUSED, not silently accepted
    local okr, why = Addon:RegisterRaid({ id = "naxxramas", bosses = {} })
    eq(okr, nil, "a parked 1.x data file re-added to the toc is REFUSED by RegisterRaid")
    ck(type(why) == "string", "…with a reason the maintainer can act on")
end
do  -- InitEngine boots headlessly and registers the Era unit-event token set
    Addon.engineFrame = nil
    local ef = Addon:InitEngine()
    ck(ef ~= nil and ef ~= false, "InitEngine creates the single engine event frame")
    ck(ef.events["ENCOUNTER_START"] and ef.events["PLAYER_REGEN_DISABLED"]
       and ef.events["COMBAT_LOG_EVENT_UNFILTERED"],
       "…registering the lifecycle's event set")
    ck(ef.events["UNIT_HEALTH_FREQUENT"],
       "…including UNIT_HEALTH_FREQUENT (never UNIT_HEALTH: too slow on Classic, §10.4)")
    local hasFocus = false
    for _, tok in ipairs(Life.HEALTH_TOKENS) do if tok == "focus" then hasFocus = true end end
    ck(not hasFocus, "…and the Era health-token set contains NO focus token (there is none on Era)")
end
endgate()

----------------------------------------------------------------------
-- WAVE 3 — SYNC + RECOVERY + BOSS-MOD INGEST
--
-- Every assertion below names the DBM_ENGINE_BEHAVIOR_SPEC.md rule it proves and
-- runs through the SHIPPING code: the real encoder, the real corroboration counter,
-- the real whisper cascade on the fake clock, the real timer API for restoration.
-- Nothing is asserted against a mock of our own code.
----------------------------------------------------------------------

-- The W3 fixture encounter. Small on purpose: it exists to be engaged, corroborated,
-- torn down and RECOVERED, so it carries one variance timer, one plain timer, one
-- state variable and one sync-triggered warning — and nothing else.
local W3ENC
do
    Addon.encounters, Addon.encountersById = {}, {}
    Addon.encByCreature, Addon.encByEncounterId, Addon.encByZone = {}, {}, {}
    local errs
    W3ENC, errs = Addon:RegisterEncounter({
        id = "w3boss", name = "Sync Fixture", zone = 533,
        creatureId = { 91001 }, encounterId = { 9101 },
        combat = { minCombatTime = 5 },
        timers = {
            { key = "vt",   kind = "cd", duration = "v40-60", start = { on = "pull" } },
            { key = "flat", kind = "cd", duration = 30,       start = { on = "pull" } },
        },
        states = { { key = "polarity", initial = "none" } },
        warnings = {
            { key = "syncwarn", text = "Polarity synced",
              trigger = { on = "sync", text = "polarity" } },
        },
    })
    if not W3ENC then
        realprint("  FAIL  W3 fixture did not register: " .. table.concat(errs or {}, "; "))
        FAILS = FAILS + 1
    end
end

local function resetSync()
    resetLife()
    Sync:Reset()
    Bridge:Reset()
    for i = #WIRE, 1, -1 do WIRE[i] = nil end
    W.latencyMs, W.leader, W.flashed = 0, true, 0
    W.instanceGroup = false
    W.wallClock = 1700000000
    Addon.db.settings.updateReminder = nil
    Addon.db.settings.pullTimerZoneFilter = nil
    Addon.db.breakTimer = nil
end

-- Encode + deliver one well-formed peer message through the REAL receive path.
local function rx(sender, sub, ...)
    local scope = Sync.SUB[sub].scope
    return Sync.Receive(Sync.PREFIX, Sync.Encode(sender, sub, ...),
                        scope == "whisper" and "WHISPER" or "RAID", sender)
end

local function countOnWire(sub, from)
    local n = 0
    for i = (from or 0) + 1, #WIRE do
        if Sync.Split(WIRE[i].payload)[3] == sub then n = n + 1 end
    end
    return n
end

-- A raid with the four candidate shapes §9.1 filters on.
local function makeRaid()
    W.units, W.group = {}, {}
    -- `player` and `raid1` are the SAME character, exactly as the client reports it:
    -- if they disagree the sync layer would happily ask itself for a recovery.
    setUnit("player", { guid = W.playerGUID, player = true, combat = true,
                        name = "Drew", realm = "Whitemane" })
    setUnit("raid1", { guid = W.playerGUID, player = true, combat = true,
                       name = "Drew", realm = "Whitemane" })
    local defs = {
        { u = "raid2", name = "Alpha", realm = "Whitemane" },
        { u = "raid3", name = "Bravo", realm = "Whitemane" },
        { u = "raid4", name = "Cross", realm = "Faerlina" },                  -- cross-realm
        { u = "raid5", name = "Dead",  realm = "Whitemane", dead = true },    -- ghost
        { u = "raid6", name = "Gone",  realm = "Whitemane", connected = false },
        { u = "raid7", name = "Echo",  realm = "Whitemane" },
    }
    W.group[1] = "raid1"
    for _, d in ipairs(defs) do
        setUnit(d.u, { player = true, name = d.name, realm = d.realm,
                       dead = d.dead, connected = d.connected })
        W.group[#W.group + 1] = d.u
    end
end

----------------------------------------------------------------------
-- GATE SYNC-WIRE — §7.1/§7.2 wire format, versioning, channel scope
----------------------------------------------------------------------
gate("SYNC-WIRE  §7.1/§7.2 wire format, protocol gates, channel scope")
do  -- boot facts, asserted BEFORE anything flushes the scheduler
    ck(Sync.booted, "Addon:InitEngine() booted the sync layer (one boot order for the engine)")
    ck(REGISTERED[Sync.PREFIX], "…registering our own prefix " .. Sync.PREFIX .. " for receive")
    local found = false
    for _, h in ipairs(Sched.housekeepers) do if h.fn == Sync.Prune then found = true end end
    ck(found, "…and hanging the sync-spam prune on the ENGINE housekeeper (§3.5), not a private ticker")
    ck(Sched.housekeeping ~= nil, "…which only runs because something is registered on it")
end
do
    resetSync()
    local f = Sync.Split(Sync.Encode("Peer-Whitemane", "C", 3, "w3boss", 100, "sweep", 533))
    eq(f[1], "Peer-Whitemane", "field 1 is the sender full name (§7.1)")
    eq(f[2], "1",              "field 2 is the transport protocol version")
    eq(f[3], "C",              "field 3 is the sub-prefix")
    eq(f[4], "1",              "field 4 is the per-message SUB-PROTOCOL version (hoisted, see the header)")
    eq(f[5], "3",              "…arguments follow from field 5")
    eq(#f, 9,                  "…and every declared argument survives the round trip")
end
do
    local f = Sync.Split(Sync.Encode("P", "PT", 10, nil, "Boss"))
    eq(f[6], "",     "an OMITTED optional argument encodes as an empty field, not a missing one…")
    eq(f[7], "Boss", "…so every later argument keeps its position")
    f = Sync.Split(Sync.Encode("P", "PT", "10\t99", 533))
    eq(f[5], "10 99", "a separator inside an argument is escaped: a field cannot be injected")
end
do  -- §7.1 / §7.2 the two version gates
    resetSync()
    local function raw(t, proto)
        return table.concat({ "Peer-Whitemane", t, "PT", proto, 10, 533 }, "\t")
    end
    eq(select(2, Sync.Receive(Sync.PREFIX, raw(0, 1), "RAID", "P")), "transport_version",
       "a message declaring a LOWER transport version is dropped (§7.1)")
    eq(select(2, Sync.Receive(Sync.PREFIX, raw(1, 0), "RAID", "P")), "subprotocol",
       "an OLDER sub-protocol number is HARD-DROPPED (§7.2)")
    eq(select(2, Sync.Receive(Sync.PREFIX, raw(1, 2), "RAID", "P")), "subprotocol",
       "…and so is a NEWER one — that is exactly how the format evolves without breaking old clients")
    eq(select(2, Sync.Receive("NOTOURS", raw(1, 1), "RAID", "P")), "not_our_prefix",
       "another addon's prefix is not ours to interpret")
    eq(select(2, Sync.Receive(Sync.PREFIX,
        table.concat({ "P", 1, "ZZZ", 1 }, "\t"), "RAID", "P")), "unknown_sub",
       "an unknown sub-prefix is dropped")
end
do  -- §7.1 receive-side channel validation
    resetSync()
    eq(select(2, Sync.Receive(Sync.PREFIX, Sync.Encode("P", "PT", 10, 533), "WHISPER", "P")),
       "channel_scope", "a GROUP-scoped sub-prefix is refused when it arrives by whisper")
    eq(select(2, Sync.Receive(Sync.PREFIX, Sync.Encode("P", "CI", "w3boss", 5), "RAID", "P")),
       "channel_scope", "…and a WHISPER-scoped one is refused when it arrives on raid chat")
end
do  -- §7.1 channel selection, incl. the solo loopback
    resetSync()
    W.inInstance, W.inGroup, W.inRaid = true, true, true
    eq(Sync.Channel(), "RAID",
       "an ordinary raid inside a raid instance is NOT an instance group — it uses RAID (§7.1)")
    W.instanceGroup = true
    eq(Sync.Channel(), "INSTANCE_CHAT", "…INSTANCE_CHAT needs an instance GROUP and an instance")
    W.instanceGroup = false
    W.inInstance = false
    eq(Sync.Channel(), "RAID", "…outside an instance, RAID")
    W.inRaid = false
    eq(Sync.Channel(), "PARTY", "…else PARTY")
    W.inGroup = false
    eq(Sync.Channel(), nil, "…else solo")
    local before = Sync.stats.received
    local _, how = Sync.Send("BT", 300)
    eq(how, "loopback", "solo LOOPS the message back into the local handler rather than sending (§7.1)")
    eq(Sync.stats.received, before + 1, "…the local handler really saw it")
    eq(#WIRE, 0, "…and nothing reached the wire")
    W.inInstance, W.inGroup, W.inRaid = true, true, true
end
do  -- §7.1 two send priorities
    resetSync()
    Sync.Enqueue(Sync.PREFIX, "n1", { priority = "NORMAL", chatType = "RAID" })
    Sync.Enqueue(Sync.PREFIX, "a1", { priority = "ALERT",  chatType = "RAID" })
    advance(0.3)
    eq(WIRE[1] and WIRE[1].payload, "a1", "ALERT traffic drains ahead of NORMAL (§7.1)")
    eq(WIRE[2] and WIRE[2].payload, "n1", "…and NORMAL follows")
end
endgate()

----------------------------------------------------------------------
-- GATE SYNC-CORR — §7.3 corroboration, throttling, de-duplication
----------------------------------------------------------------------
gate("SYNC-CORR  §7.3 corroboration thresholds, throttle, de-duplication")
do  -- BOTH client rules, kept as data so the Classic concession cannot be "tidied up"
    eq(Sync.Threshold("C",  "classic"), 3, "combat start needs THREE distinct senders on Classic (§7.3)")
    eq(Sync.Threshold("C",  "retail"),  3, "…and three on retail")
    eq(Sync.Threshold("EE", "retail"),  3, "encounter end needs THREE senders on retail")
    eq(Sync.Threshold("EE", "classic"), 1,
       "…but exactly ONE on Classic — the spec's explicit concession, not a typo")
    eq(Sync.CLIENT, "classic", "we ship for Era, so the Classic row is the live one")
end
do  -- the counter itself
    resetSync()
    W.latencyMs = 250
    local _, _, n1 = rx("A-Whitemane", "C", 2, "w3boss", 100, "sweep", 533)
    eq(n1, 1, "sender 1 is recorded…")
    ck(not Life:IsEngaged("w3boss"), "…and starts nothing")
    rx("A-Whitemane", "C", 2, "w3boss", 100, "sweep", 533)
    local _, _, n2 = rx("B-Whitemane", "C", 2, "w3boss", 100, "sweep", 533)
    eq(n2, 2, "a REPEAT from the same sender does not corroborate itself")
    ck(not Life:IsEngaged("w3boss"), "…two distinct senders still start nothing")
    rx("C-Whitemane", "C", 2, "w3boss", 100, "sweep", 533)
    ck(Life:IsEngaged("w3boss"), "the THIRD distinct sender starts the fight (§7.3)")
    local rt = Life:GetRuntime("w3boss")
    eq(rt.trigger, "sync", "…with trigger 'sync', so the start does not echo back onto the wire")
    near(rt.delay, 2.25, 0.01, "…and the receiver's own world latency is added to the reported delay")
end
do  -- the rejection list
    resetSync()
    eq(select(2, rx(Sync.Me(), "C", 0, "w3boss", 100, "sweep", 533)), "self",
       "a start sync from ourselves is rejected outright")
    W.instanceType = "pvp"
    eq(select(2, rx("A-Whitemane", "C", 0, "w3boss", 100, "sweep", 533)), "pvp",
       "…and any start sync inside a PvP instance")
    W.instanceType = "raid"
    eq(select(2, rx("A-Whitemane", "C", 0, "nosuch", 100, "sweep", 533)), "no_module",
       "…and one naming an encounter we have no module for")
    W.instanceID = 999
    eq(select(2, rx("A-Whitemane", "C", 0, "w3boss", 100, "sweep", 533)), "zone_not_in_module",
       "…and one whose module's zone list does not include where we are standing")
    W.instanceID = 533
    W.inInstance = false
    eq(select(2, rx("A-Whitemane", "C", 0, "w3boss", 100, "sweep", 4131)), "different_zone",
       "…and one from a sender in a different world zone while we are outdoors")
    W.inInstance = true
end
do  -- §7.3 encounter end: ONE sender on Classic
    resetSync()
    Life:StartCombat(W3ENC, 0, "encounter")
    ck(Life:IsEngaged("w3boss"), "fixture engaged locally")
    eq(rx("A-Whitemane", "EE", 9101, 1, "w3boss"), true,
       "ONE encounter-end sender ends the fight on Classic (§7.3 concession)")
    ck(not Life:IsEngaged("w3boss"), "…the encounter is no longer engaged")
end
do  -- §7.3 mob kill
    resetSync()
    W.difficultyID = 9
    eq(select(2, rx("A-Whitemane", "K", 91001, 148)), "difficulty_mismatch",
       "a kill sync from a raid on ANOTHER difficulty is rejected (§7.3)")
    W.instanceType = "none"
    eq(select(2, rx("A-Whitemane", "K", 91001, 9)), "instance_type",
       "…and one arriving while we are not in an instance at all")
    W.instanceType = "raid"
end
do  -- §7.3 module syncs: 8 s send-side dedupe + local self-delivery
    resetSync()
    Life:StartCombat(W3ENC, 0, "encounter")
    eq(Sync.DeliverModuleSync("Peer-Whitemane", "w3boss", "polarity", ""), 1,
       "an inbound module sync routes into the engaged encounter through the `sync` trigger vocabulary")
    local routed = 0
    local realDeliver = Sync.DeliverModuleSync
    Sync.DeliverModuleSync = function(...) routed = routed + 1 return realDeliver(...) end
    local sent = Sync.SendModuleSync("w3boss", "polarity")
    eq(sent, true, "an outbound module sync goes out…")
    eq(routed, 1,
       "…and the SENDER delivers it to itself locally, so sender and receivers behave identically (§7.3)")
    eq(select(2, Sync.SendModuleSync("w3boss", "polarity")), "deduped",
       "…an identical sync inside 8 s is de-duplicated ON SEND (§7.3)")
    Sync.DeliverModuleSync = realDeliver
    advance(9, 0.5)
    eq(Sync.SendModuleSync("w3boss", "polarity"), true, "…and allowed again once the 8 s window passes")
end
do  -- §7.3 break-timer throttle and cap
    resetSync()
    ck(rx("A-Whitemane", "BT", 300), "a break timer from a peer is accepted")
    eq(select(2, rx("A-Whitemane", "BT", 600)), "break_throttle",
       "…a second from the SAME sender inside one second is throttled (§7.3)")
    advance(1.2)
    ck(rx("A-Whitemane", "BT", 600), "…and allowed again after a second")
    rx("B-Whitemane", "BT", 99999)
    ck((Addon:BreakTimeLeft() or 0) <= Sync.BREAK_MAX,
       "…and every break timer is capped at 3600 s (§7.3/§11.4)")
end
do  -- §7.3/§12 spam-table pruning
    resetSync()
    rx("A-Whitemane", "C", 0, "w3boss", 100, "sweep", 533)
    ck(Sync.corroborate["C:w3boss"] ~= nil, "a partial corroboration is held")
    advance(9, 0.5)
    ck(Sync.Prune() >= 1, "the housekeeping pass drops entries older than 8 s (§12)")
    ck(Sync.corroborate["C:w3boss"] == nil, "…including a stale partial corroboration")
    ck(next(Sync.spam) == nil, "…and the sync-spam table with it")
end
endgate()

----------------------------------------------------------------------
-- GATE SYNC-VER — §7.4 version nag, and the OWNER-VETOED self-disable
----------------------------------------------------------------------
gate("SYNC-VER  §7.4 version nag at 2 senders — and no self-disable, ever")
do  -- §7.4 the 3 s debounced reply
    resetSync()
    W.inInstance = false
    local before = #WIRE
    rx("A-Whitemane", "H")
    rx("B-Whitemane", "H")
    rx("C-Whitemane", "H")
    advance(3.5)
    eq(countOnWire("V", before), 1,
       "a WAVE of hellos produces ONE version reply, not one per hello (§7.4 3 s debounce)")
    W.inInstance = true
end
do  -- §7.4 the nag threshold
    resetSync()
    local NEWER = Sync.VERSION.release + 1
    rx("A-Whitemane", "V", 20001, NEWER, "2.0.1", 20001)
    eq(Sync.newerCount, 1, "one sender on a newer release is tracked")
    ck(not Sync.nagged, "…and does NOT nag: the threshold is 2 DISTINCT senders")
    rx("A-Whitemane", "V", 20001, NEWER, "2.0.1", 20001)
    eq(Sync.newerCount, 1, "…a repeat from the same sender is not a second sender")
    ck(not Sync.nagged, "…still no nag")
    rx("B-Whitemane", "V", 20002, NEWER + 1, "2.0.2", 20002)
    ck(Sync.nagged, "the SECOND distinct newer sender nags (§7.4)")
    eq(Sync.stats.nagged, 1, "…exactly once")
    eq(Addon.db.settings.updateReminder, true, "…and sets the persistent reminder flag")
    eq(Sync.newestSeen.display, "2.0.2", "…tracking the NEWEST release seen, not the first")
    rx("C-Whitemane", "V", 20003, NEWER + 2, "2.0.3", 20003)
    eq(Sync.stats.nagged, 1, "…and never nags twice in one session")
    rx("D-Whitemane", "V", 1, Sync.VERSION.release - 5, "1.9.9", 1)
    eq(Sync.newerCount, 3, "…an OLDER peer is not counted as newer")
end
do  -- THE OWNER VETO, asserted behaviourally through the real handler
    resetSync()
    local disabled = 0
    local realDisable, realFlush = Life.Disable, Sched.Flush
    Life.Disable = function(...) disabled = disabled + 1 return realDisable(...) end
    Sched.Flush  = function(...) disabled = disabled + 1 return realFlush(...) end
    for i = 1, 5 do
        rx("D" .. i .. "-Whitemane", "V", 99999, Sync.VERSION.release + 10, "9.9.9", 99999)
    end
    Life.Disable, Sched.Flush = realDisable, realFlush
    eq(Sync.stats.forceDisableSeen, 5,
       "five senders reporting a newer FORCE-DISABLE revision are parsed and counted…")
    eq(disabled, 0,
       "…and NOTHING is disabled: the spec's hard self-disable is OWNER-VETOED (design doc R2)")
    eq(Sync.SELF_DISABLE, false, "…the constant that says so is pinned false")
    ck(Sync.booted, "…and the sync layer is still live afterwards")
    ck(Sync.Send("C", 0, "w3boss", 100, "sweep", 533) ~= false,
       "…and still speaking on the wire, which a force-disabled client would not be")
end
do  -- THE MUTATION GATE: restoring the reference behaviour must redden something
    local src = readFile(P("core_sync.lua"))
    ck(src ~= nil, "core_sync.lua is readable")
    ck(src and src:match("[:%.]Disable%s*%(") == nil,
       "core_sync.lua contains NO disable call at all — adding one reddens this gate")
    ck(src and src:find("SELF_DISABLE = false", 1, true) ~= nil,
       "…and the veto is stated as CODE, not only as a comment")
end
endgate()

----------------------------------------------------------------------
-- GATE SYNC-REC — §9.1 reload recovery, the whole cascade on the fake clock
----------------------------------------------------------------------
gate("SYNC-REC  §9.1 reload recovery: cascade, reply window, restoration")
do  -- step 1: ranking and the candidate filter
    resetSync(); makeRaid()
    Sync.peers["Echo-Whitemane"] = { rev = 30000, release = 1, at = 0 }
    local c = Sync.RankCandidates()
    eq(#c, 3, "cross-realm, ghost and disconnected candidates are skipped entirely (§9.1)")
    eq(c[1] and c[1].name, "Echo-Whitemane", "the group is ranked by version, highest first")
    eq(c[2] and c[2].name, "Alpha-Whitemane", "…then deterministically by name")
    eq(c[3] and c[3].name, "Bravo-Whitemane", "…")
end
do  -- steps 2 + 3: the 7/10/13 cascade and the 15 s suppression
    resetSync(); makeRaid()
    Sync.peers["Echo-Whitemane"] = { rev = 30000 }
    local ok, asked = Sync.BeginRecovery("reload")
    eq(ok, true, "a reload in a group with no boss engaged begins recovery")
    eq(asked, 3, "…queueing three requests")
    ck(Life:IsRecovering(), "the 'recovery in progress' flag is set immediately (§9.1 step 3)")
    ck(not Life:HealthArmed(),
       "…and the health combat-start path is suppressed while it is set (the Era translation)")
    eq(select(2, Life:OnEngageUnit()), "recovery_in_progress",
       "…as is the boss-frame path the spec names literally")
    advance(6.9); eq(countOnWire("RT"), 0, "nothing is asked before 7 s")
    advance(0.4); eq(countOnWire("RT"), 1, "the 1st-ranked candidate is whispered at 7 s (§12)")
    eq(WIRE[1] and WIRE[1].target, "Echo-Whitemane", "…in rank order")
    eq(WIRE[1] and WIRE[1].chatType, "WHISPER", "…by WHISPER")
    advance(3);   eq(countOnWire("RT"), 2, "the 2nd-ranked candidate at 10 s")
    advance(3);   eq(countOnWire("RT"), 3, "the 3rd at 13 s")
    advance(2.2)
    ck(not Life:IsRecovering(), "the in-progress flag clears after 15 s (§12)")
    ck(Life:HealthArmed(), "…and the health path is armed again")
end
do  -- step 4 + the 5 s reply-validity window
    resetSync(); makeRaid()
    Sync.BeginRecovery("reload")
    advance(7.3)
    eq(select(2, rx("Nobody-Whitemane", "CI", "w3boss", 12)), "reply_rejected",
       "a reply from a player we NEVER ASKED is refused (§9.1)")
    advance(5.2)
    eq(select(2, rx("Alpha-Whitemane", "CI", "w3boss", 12)), "reply_rejected",
       "…and a reply from one we DID ask is refused once the 5 s validity window has passed")
end
do
    resetSync(); makeRaid()
    Sync.BeginRecovery("reload")
    advance(7.3)
    rx("Alpha-Whitemane", "CI", "w3boss", 12)
    advance(8)
    eq(countOnWire("RT"), 1,
       "any reply invalidates the remaining requests — the 10 s and 13 s asks never happen (§9.1)")
end
do  -- restoration: combat, state, stage, timers
    resetSync(); makeRaid()
    W.latencyMs = 500
    Sync.BeginRecovery("reload")
    advance(7.3)
    rx("Alpha-Whitemane", "CI", "w3boss", 40)
    ck(Life:IsEngaged("w3boss"), "a combat-info reply RESTORES the fight (§9.1)")
    local rt = Life:GetRuntime("w3boss")
    near(rt.delay, 40.5, 0.01, "…with the reported elapsed time plus our own network latency")
    eq(rt.recordEligible, false, "…and marks the pull NOT record-eligible")
    eq(countOnWire("C"), 0, "…without echoing a combat-start broadcast back at the raid")

    rx("Alpha-Whitemane", "VI", "w3boss", "polarity", "positive")
    eq(rt:GetState("polarity"), "positive", "a variable-info reply restores state VERBATIM")
    rx("Alpha-Whitemane", "VI", "w3boss", "flag", "true")
    eq(rt.states.flag, true, "…converting \"true\"/\"false\" back to booleans")
    local stages = 0
    local scb = function() stages = stages + 1 end
    Addon:RegisterEngineCallback("ENGINE_STAGE", scb)
    rx("Alpha-Whitemane", "VI", "w3boss", "__stage", "3")
    eq(rt.stage, 3, "…and restores the stage")
    eq(stages, 1, "…RE-FIRING the stage-change broadcast so external consumers resync (§9.1)")
    Addon:UnregisterEngineCallback("ENGINE_STAGE", scb)

    Timers.StopAll("recovery-fixture")
    local bar = rx("Alpha-Whitemane", "TR", "w3boss", "vt", 22, 60, "", 0)
    ck(bar ~= nil, "a timer-info reply restores the bar through the REAL timer API")
    eq(bar and bar.hasVariance, true, "…and the VARIANCE WINDOW SURVIVES restoration (§4.2 + §9.1)")
    eq(bar and bar.min, 40, "…min intact")
    eq(bar and bar.max, 60, "…max intact")
    near(Timers.Remaining(bar), 21.5, 0.05, "…restored as total - timeLeft + latency")

    local pb = rx("Alpha-Whitemane", "TR", "w3boss", "flat", 10, 30, "", 1)
    ck(pb ~= nil and pb.paused, "a PAUSED bar is restored and re-paused")
    near(Timers.Remaining(pb), 10, 0.01, "…with latency omitted for paused bars")
end
do  -- the responder side
    resetSync(); makeRaid()
    Life:StartCombat(W3ENC, 0, "encounter")
    advance(5)
    local before = #WIRE
    Sync.OnRequestTimers("Alpha-Whitemane", "WHISPER")
    eq(select(2, Sync.OnRequestTimers("Alpha-Whitemane", "WHISPER")), "reply_throttle",
       "recovery replies are limited to one per requester per second (§7.3)")
    advance(3)
    local kinds = {}
    for i = before + 1, #WIRE do kinds[#kinds + 1] = Sync.Split(WIRE[i].payload)[3] end
    eq(kinds[1], "CI", "the responder answers CI first (§9.1 reply order)")
    eq(kinds[2], "VI", "…then a VI per state variable")
    local sawTR = false
    for _, k in ipairs(kinds) do if k == "TR" then sawTR = true end end
    ck(sawTR, "…then a TR per live bar")
end
do  -- §9.1: not in combat -> answer with the break timer instead
    resetSync(); makeRaid()
    Addon:StartBreakTimer(300, "manual")
    local before = #WIRE
    Sync.OnRequestTimers("Alpha-Whitemane", "WHISPER")
    advance(1)
    eq(countOnWire("BTR", before), 1,
       "a responder NOT in combat answers with its break timer instead (§9.1)")
end
do  -- the three trigger guards
    resetSync()
    W.inGroup, W.inRaid = false, false
    eq(select(2, Sync.BeginRecovery("reload")), "solo", "recovery does not run solo")
    W.inGroup, W.inRaid = true, true
    makeRaid()
    W.instanceType = "pvp"
    eq(select(2, Sync.BeginRecovery("reload")), "pvp", "…nor in a PvP instance")
    W.instanceType = "raid"
    Life:StartCombat(W3ENC, 0, "encounter")
    eq(select(2, Sync.BeginRecovery("reload")), "already_engaged", "…nor while a boss is engaged")
end
do  -- the W3 seam added to W1's lifecycle
    resetSync(); makeRaid()
    local fired = 0
    local cb = function() fired = fired + 1 end
    Addon:RegisterEngineCallback("ENGINE_LOGIN", cb)
    Life:OnEvent("PLAYER_ENTERING_WORLD", false, true)
    eq(fired, 1, "PLAYER_ENTERING_WORLD publishes ENGINE_LOGIN (the one seam W3 added to W1)")
    ck(Life:IsRecovering(), "…and the whole cascade hangs off it, with no comms in the engine core")
    Addon:UnregisterEngineCallback("ENGINE_LOGIN", cb)
end
endgate()

----------------------------------------------------------------------
-- GATE SYNC-PB — §11.4 / §9.2 pull and break timers, end to end, headless
----------------------------------------------------------------------
gate("SYNC-PB  §11.4/§9.2 pull + break timers end to end")
do
    resetSync()
    eq(select(2, Addon:StartPullTimer(1, "manual")), "too_short",
       "§11.4 REFUSES durations between 0 and 3 s exclusive (wave 1's shim silently clamped)")
    eq(Addon:StartPullTimer(3, "manual"), 3, "…3 s is accepted")
    eq(Addon:StartPullTimer(999, "manual"), Sync.PULL_MAX, "…and an absurd value is capped")
    ck((W.flashed or 0) > 0, "…starting one flashes the taskbar icon (§11.4)")
    eq(Addon:StartPullTimer(0, "manual"), true, "0 IS the cancel signal (§11.4)")
    ck(Sync._ensurePullTimer():Get() == nil, "…and the bar is gone")
end
do  -- rank gate, broadcast, and NO re-broadcast of a received pull
    resetSync(); makeRaid()
    local before = #WIRE
    Addon:StartPullTimer(10, "manual")
    advance(0.5)
    eq(countOnWire("PT", before), 1, "a MANUAL pull is broadcast on OUR OWN prefix")
    W.leader = false
    ck(not Sync.CanBroadcastPull(), "a member without rank cannot broadcast one (§11.4)")
    W.leader = true

    Addon:CancelPullTimer("manual")
    advance(0.5)                 -- let the cancel's own broadcast leave first
    before = #WIRE
    rx("Alpha-Whitemane", "PT", 12, 533, "")
    advance(0.5)
    eq(countOnWire("PT", before), 0,
       "a RECEIVED pull is rendered but NEVER re-broadcast (no amplification loop)")
    ck(Sync._ensurePullTimer():Get() ~= nil, "…and it really started our own bar")
    rx("Alpha-Whitemane", "PT", 0, 533, "")
    ck(Sync._ensurePullTimer():Get() == nil, "…and a peer sending 0 cancels it (§11.4)")
end
do  -- §11.4 reception zone filter, off by default
    resetSync()
    Addon.db.settings.pullTimerZoneFilter = true
    eq(select(2, rx("Alpha-Whitemane", "PT", 12, 4131, "")), "zone_filter",
       "the optional filter drops pull timers whose sender is on a different map (§11.4)")
    Addon.db.settings.pullTimerZoneFilter = nil
    ck(rx("Alpha-Whitemane", "PT", 12, 4131, ""), "…and is OFF by default")
end
do  -- §2.3 the engage cancel, and the in-encounter / PvP refusals
    resetSync()
    Addon:StartPullTimer(10, "manual")
    ck(Sync._ensurePullTimer():Get() ~= nil, "a pull bar is live")
    Life:StartCombat(W3ENC, 0, "encounter")
    ck(Sync._ensurePullTimer():Get() == nil, "§2.3: a combat start CANCELS any running pull timer")
    eq(select(2, Addon:StartPullTimer(10, "manual")), "in_encounter",
       "…and a new pull timer is refused during an encounter (§11.4)")
    Life:EndCombat(Life:GetRuntime("w3boss"), false, "fixture")
    W.instanceType = "pvp"
    eq(select(2, Addon:StartPullTimer(10, "manual")), "pvp", "…and inside a PvP instance")
    W.instanceType = "raid"
end
do  -- §11.4 break announcements at 10 / 5 / 2 / 1 minutes
    resetSync()
    local announces = 0
    local cb = function() announces = announces + 1 end
    Addon:RegisterEngineCallback("WARN_ANNOUNCE", cb)
    eq(Addon:StartBreakTimer(3600 * 2, "manual"), Sync.BREAK_MAX,
       "§11.4 break timers are capped at 60 minutes")
    Addon:CancelBreakTimer("manual")
    Addon:StartBreakTimer(660, "manual")
    local base = announces
    advance(61, 0.5);  eq(announces - base, 1, "…announcing at 10 minutes remaining")
    advance(300, 0.5); eq(announces - base, 2, "…at 5 minutes")
    advance(180, 0.5); eq(announces - base, 3, "…at 2 minutes")
    advance(60, 0.5);  eq(announces - base, 4, "…and at 1 minute")
    Addon:UnregisterEngineCallback("WARN_ANNOUNCE", cb)
    Addon:CancelBreakTimer("manual")
end
do  -- §9.2 break-timer persistence across a reload
    resetSync()
    Addon:StartBreakTimer(600, "manual")
    ck(type(Addon.db.breakTimer) == "table", "§9.2 a running break timer is written to disk…")
    eq(Addon.db.breakTimer.duration, 600, "…as duration / wallclock-at-start")
    W.wallClock = W.wallClock + 200
    Timers.StopAll("reload")
    near(Sync.RestorePersistedBreak(), 400, 0.5,
         "…and the remaining time is recomputed against the wall clock on the next load")
    W.wallClock = W.wallClock + 100000
    Timers.StopAll("reload")
    eq(select(2, Sync.RestorePersistedBreak()), "expired",
       "…while an EXPIRED record is discarded rather than restarted")
    eq(Addon.db.breakTimer, nil, "…and cleared from disk")
end
endgate()

----------------------------------------------------------------------
-- GATE SYNC-DBM — receive-only boss-mod ingest + the transmit firewall
----------------------------------------------------------------------
gate("SYNC-DBM  receive-only ingest + the transmit firewall (both layers)")
do  -- §7.1 wire decode, pure
    local m = Bridge.Decode("Peer-Whitemane\t1\tBT\t900")
    ck(m ~= nil, "the boss-mod payload decodes")
    eq(m and m.sender, "Peer-Whitemane", "…sender first (§7.1)")
    eq(m and m.protocol, 1, "…then the protocol version")
    eq(m and m.sub, "BT", "…then the sub-prefix")
    eq(m and m.args[1], "900", "…then the arguments")
end
do  -- ingest rows
    resetSync()
    eq(select(2, Bridge.OnAddonMessage("SOMETHINGELSE", "x", "RAID", "P")), "notOurs",
       "a prefix we do not listen on is ignored outright")
    eq(select(2, Bridge.OnAddonMessage("D5", "P\t0\tBT\t900", "RAID", "P")), "protocol",
       "a payload declaring a LOWER protocol version is dropped (§7.1)")
    eq(select(2, Bridge.OnAddonMessage("D5", "P\t1\tK\t1234", "RAID", "P")), "unknownSub",
       "their kill/version/combat traffic is counted and IGNORED — their engine never drives ours")
    ck(Bridge.OnAddonMessage("D5", "P\t1\tBT\t900", "RAID", "P"),
       "a BREAK timer on their wire renders through OUR §11.4 break timer")
    near(Addon:BreakTimeLeft(), 900, 0.5, "…for the reported duration")
    eq(Addon.breakSource, "P", "…with the sender attributed")
    eq(select(2, Bridge.OnAddonMessage("D5", "P\t1\tBT\t900", "RAID", "P")), "throttled",
       "…and a repeat inside a second is throttled")
end
do  -- the ingest is switchable, and the 1.x option name still works
    resetSync()
    Addon.db.settings.dbmIngest = false
    eq(select(2, Bridge.OnAddonMessage("D5", "P\t1\tBT\t900", "RAID", "P")), "disabled",
       "ingest can be turned off")
    Addon.db.settings.dbmIngest = nil
    Addon.db.settings.mirrorDBMPull = false
    eq(select(2, Bridge.OnAddonMessage("D5", "P\t1\tBT\t900", "RAID", "P")), "disabled",
       "…and the 1.x option still on screen (options.lua is W5's file) still switches it")
    Addon.db.settings.mirrorDBMPull = nil
    ck(Bridge.OnAddonMessage("D5", "P\t1\tBT\t900", "RAID", "P"), "…default is ON")
end
do  -- §10.19: pull timers are NOT on their addon channel — they ride Blizzard's countdown
    resetSync()
    ck(Bridge.OnStartCountdown("Alpha", 15),
       "§10.19 a pull arrives on the Blizzard countdown API, never the addon channel")
    ck(Sync._ensurePullTimer():Get() ~= nil, "…and renders through OUR pull-timer path")
    eq(select(2, Bridge.OnStartCountdown("Alpha", 15)), "throttled",
       "…a re-broadcast countdown inside the dedupe window is ONE pull, not two")
    Bridge.OnCancelCountdown("Alpha")
    ck(Sync._ensurePullTimer():Get() == nil, "…and the cancel event cancels it")
    eq(Bridge.stats.pullIngested, 1, "…exactly one pull was ingested")
end
do  -- THE TRANSMIT FIREWALL, both layers, through the real functions
    resetSync()
    eq(Sync.IsForbiddenTxPrefix("D5"), true,
       "the prefix the bridge listens on is in the transmit firewall — pushed there AT LOAD")
    eq(Sync.IsForbiddenTxPrefix(Sync.PREFIX), false, "…our own prefix is not")
    local blocked, n0 = Sync.forbiddenTxBlocked, #WIRE
    eq(Sync.Enqueue("D5", "anything", { chatType = "RAID", priority = "ALERT" }), false,
       "LAYER 1 (scheduler): a forbidden prefix cannot even ENTER the send queue")
    eq(Sync._rawSend("D5", "anything", "RAID"), false,
       "LAYER 2 (wire): …and cannot reach SendAddonMessage even when handed straight to it")
    eq(Sync.forbiddenTxBlocked - blocked, 2, "…both guard fires are counted")
    advance(0.5)
    eq(#WIRE, n0, "…and NOTHING carrying that prefix ever reached the wire")
    eq(Sync.Enqueue(Sync.PREFIX, "ours", { chatType = "RAID" }), true,
       "our own prefix still enqueues (or this gate would prove nothing)")
    advance(0.5)
    ck(#WIRE > n0, "…and still reaches the wire")
end
do  -- listening somewhere and being forbidden to speak there are ONE list
    for _, p in ipairs(Bridge.RECV_PREFIXES) do
        ck(Sync.IsForbiddenTxPrefix(p), "receive prefix " .. p .. " is transmit-forbidden")
        ck(REGISTERED[p], "…and was registered for RECEIVE at boot")
    end
    local src = readFile(P("dbm_bridge.lua")) or ""
    ck(src:find("SendAddonMessage", 1, true) == nil,
       "dbm_bridge.lua contains no send call of any kind")
end
endgate()

----------------------------------------------------------------------
-- GATE SYNC-RETIRE — the wave-1 pull-timer shim is gone from core_boot.lua
----------------------------------------------------------------------
gate("SYNC-RETIRE  core_boot.lua's W1 pull-timer shim is retired")
do
    local boot = readFile(P("core_boot.lua")) or ""
    ck(boot:find("function Addon:StartPullTimer", 1, true) == nil,
       "core_boot.lua no longer defines StartPullTimer (W3 owns pull timers for real)")
    ck(boot:find("function Addon:CancelPullTimer", 1, true) == nil, "…nor CancelPullTimer")
    local src = readFile(P("core_sync.lua")) or ""
    ck(src:find("function Addon:StartPullTimer", 1, true) ~= nil,
       "core_sync.lua defines it instead — the PUBLIC NAME is unchanged, so slash/options still work")
    ck(type(Addon.StartPullTimer) == "function" and type(Addon.CancelPullTimer) == "function",
       "…and both names resolve at runtime")
    ck(type(Addon.StartBreakTimer) == "function" and type(Addon.CancelBreakTimer) == "function",
       "…and the break timer the spec pairs them with exists too (§11.4)")
end
endgate()

----------------------------------------------------------------------
realprint("############################################################")
realprint("# Daseeki-Raid-Mechanics 2.0 engine self-tests (waves 1 + 3)")
for _, g in ipairs({ "0  toc parse", "FW  clean-room firewall", "RETIRE  demolition holds",
                     "MIG-ALGO  stamp / newer / transform / gap-not-wipe",
                     "HEAP  §3.1/§3.2 pure min-heap",
                     "SCHED  §3.1-§3.5 frame-driven scheduler",
                     "TIMER  §4.1/§4.2 identity, de-duplication, variance",
                     "TRIP  §4.3 early-refresh tripwire + telemetry ring",
                     "LIFE  §2 lifecycle: engage paths, lockouts, wipe matrix, end",
                     "API  encounter grammar: validation + expressiveness",
                     "HATCH  registered-special-module escape hatch",
                     "SYNC-WIRE  §7.1/§7.2 wire format, protocol gates, channel scope",
                     "SYNC-CORR  §7.3 corroboration thresholds, throttle, de-duplication",
                     "SYNC-VER  §7.4 version nag at 2 senders — and no self-disable, ever",
                     "SYNC-REC  §9.1 reload recovery: cascade, reply window, restoration",
                     "SYNC-PB  §11.4/§9.2 pull + break timers end to end",
                     "SYNC-DBM  receive-only ingest + the transmit firewall (both layers)",
                     "SYNC-RETIRE  core_boot.lua's W1 pull-timer shim is retired" }) do
    local n = GATE_FAILS[g] or 0
    realprint(("#   %-52s %s"):format(g, n == 0 and "PASS" or (n .. " FAIL")))
end
realprint("#")
realprint("#   RESULT: " .. (FAILS == 0 and "ALL PASS" or (FAILS .. " FAILURE(S) — RED")))
realprint("############################################################")
os.exit(FAILS == 0 and 0 or 1)
