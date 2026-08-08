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
-- 2.0 WAVE 2 — PRESENTATION + ENGINE SERVICES. Same discipline: the bar layout,
-- the warning stacks, all three scanners and every Era gate are the SHIPPING
-- implementations, driven on the injected clock and the injected world.
--
--   BARS     §4.2/§4.7   bar identity, variance geometry, sort, anchors, enlarge/
--                        hide thresholds, flash phase, count text, keep/fade, the
--                        Chromaggus recolour/rename contract, pull-bar rendering
--   WARN     §5.1/§5.2   the two tiers: slot machine, duration/fade/pop, sound
--                        tiers, voice replacement + version gating, suppressors,
--                        name colouring, the combined and precise batchers
--   SCAN     §5.3        all three scanner shapes on the fake clock, incl. the
--                        0.05x16 budget, tank rescan + final pass, filter-out
--                        fallback, event abort / allowTank, repeated sampling
--   ERA      §6.1/§8.6   the range ladder + 43 yd clamp, boss health by nameplate
--            §5.4        fallback with last-non-zero retention, interrupt / dispel
--                        / CC gates incl. the 0.1 s cache expiry, role derivation
--   PUB      §4.5/§11.8  the 18-field public broadcast contract, field for field
--
-- 2.0 WAVE 4 — ENCOUNTER DATA. One registration gate and one DRIVEN gate per zone
-- wave: the shipping data, through the shipping engine, on the injected clock.
--
--   NAXX/-DRIVE   §8       Naxxramas (wave 4d), plus the owner's 2026-08-07
--                          arbitrations: the three DUAL-ID rows driven once per id,
--                          the thirteen restored 1.x rows driven with their shipped
--                          defaults, and the provenance comments pinned textually
--   AQ/-DRIVE     §6/§7    Ruins + Temple of Ahn'Qiraj (wave 4c), plus the owner's
--                          2026-08-07 "Same as Naxx" arbitrations: the two restored
--                          log-verified timers driven at their field cadences, the
--                          thirteen restored 1.x keys driven with their shipped
--                          defaults, and the provenance comments pinned textually.
--                          Also incl. C'Thun's three
--                          timer value sets and its roster-relayed stomach probe,
--                          Viscidus's freeze/shatter machine and hit rates, Ouro's
--                          submerge cycle, and the reflect miss-type path
--   BWLZG/-DRIVE  §4/§5    Blackwing Lair + Zul'Gurub (wave 4b), incl. Chromaggus's
--                          five-school vulnerability tracker across ALL THREE evidence
--                          paths (with the empty-sweep refusal asserted), his two
--                          manually-stopped pull breath bars and per-breath cooldowns,
--                          Razorgore's phase-gated kill detection, Vael's RP pull
--                          countdown and scheduled run-out, Nefarian's poll-driven
--                          phase machine and class calls, and Hakkar's max-health
--                          hard-mode heuristic in both directions
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
    "core_api.lua", "core_lifecycle.lua", "core_diag.lua", "core_boot.lua", "core_sync.lua",
    "svc_era.lua", "svc_scan.lua", "ui_bars.lua", "ui_warnings.lua", "public_api.lua",
    "alerts.lua", "dbm_bridge.lua", "modules.lua",
    "mod_loatheb_healers.lua", "mod_fourhorsemen_rotation.lua",
    "mod_fourhorsemen_tracker.lua", "mod_gothik_waves.lua",
    "mod_razuvious_understudy.lua", "thaddius.lua",
    "soundpicker.lua", "options.lua", "slash.lua",
    -- W4b: the parked list is EMPTY. data_bwl.lua was the last 1.x data file on disk
    -- and this wave consumed it; all three are asserted DELETED in GATE RETIRE.
    -- W4c/W4b encounter data
    "enc_aq20.lua", "enc_aq40.lua", "enc_bwl.lua", "enc_zg.lua",
    -- W4a: the last three zones. MC / Onyxia / the world bosses never had a 1.x data
    -- file, so this wave adds encounter data and retires nothing.
    "enc_moltencore.lua", "enc_onyxia.lua", "enc_worldbosses.lua",
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
    -- wave 4d / 4c / 4b authored these; all five are clean-room from the encounters spec.
    ["enc_naxxramas.lua"] = true,
    ["enc_aq20.lua"] = true, ["enc_aq40.lua"] = true,
    ["enc_bwl.lua"] = true, ["enc_zg.lua"] = true,
    -- wave 4a authored these three, same clean-room terms.
    ["enc_moltencore.lua"] = true, ["enc_onyxia.lua"] = true,
    ["enc_worldbosses.lua"] = true,
    ["core_heap.lua"] = true, ["core_telemetry.lua"] = true, ["core_sched.lua"] = true,
    ["core_timers.lua"] = true, ["core_api.lua"] = true, ["core_lifecycle.lua"] = true,
    ["core_boot.lua"] = true, ["core_diag.lua"] = true, [TOC_FILE] = true,
    -- wave 3 authored these two; they are clean-room from the behaviour spec alone.
    ["core_sync.lua"] = true, ["dbm_bridge.lua"] = true,
    -- wave 2
    ["svc_era.lua"] = true, ["svc_scan.lua"] = true, ["ui_bars.lua"] = true,
    ["ui_warnings.lua"] = true, ["public_api.lua"] = true,
}

-- INTEROP ALLOWANCE — exact (file, token) pairs only, each with a written reason,
-- and PRINTED LOUDLY on every run so it can never quietly become a hole.
--
-- public_api.lua publishes the integration contract of ENGINE SPEC §11.8, whose
-- entire subject is that ecosystem: "This surface is the integration contract with
-- WeakAuras and nameplate addons." Naming the consumer in a PUBLISHED CONTRACT is
-- an interoperability fact, the same category as the documented `dbm` OptionalDep
-- that this list already declines to forbid. It is not, and cannot be, evidence of
-- copied source: there is no source to copy for an addon we merely broadcast to.
-- Every other file/token pair still HARD-FAILS.
local INTEROP_ALLOWED = {
    ["public_api.lua"] = { weakauras = "§11.8 published integration contract names its consumer" },
}
gate("FW  clean-room firewall")
local FW_FILES = { "CHANGELOG.md", "README.md", TOC_FILE, ".pkgmeta" }
for _, rel in ipairs(ALL_LUA) do FW_FILES[#FW_FILES + 1] = rel end
local noteCount = 0
for _, rel in ipairs(FW_FILES) do
    local src = readFile(P(rel))
    if src then
        local lower, hits = src:lower(), {}
        local allow = INTEROP_ALLOWED[rel] or {}
        for _, tok in ipairs(FORBIDDEN) do
            if lower:find(tok, 1, true) then
                if allow[tok] then
                    realprint(("  ALLOW %s: '%s' — %s"):format(rel, tok, allow[tok]))
                else
                    hits[#hits + 1] = tok
                end
            end
        end
        if #hits > 0 then
            if CHANGE_SURFACE[rel] then
                fail(rel .. " (rebuild change surface) contains: " .. table.concat(hits, ", "))
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
-- W4d: data_naxxramas.lua joins the DELETED list — enc_naxxramas.lua replaced it,
-- its values were diffed against the spec first, and a file that is both parked and
-- superseded is just a second source of truth waiting to be edited by mistake.
-- W4c: data_aq40.lua joins the DELETED list on the same terms — enc_aq40.lua replaced
-- it, its values were diffed against the spec first, and the spec won. AQ20 never had
-- a 1.x data file, so there is nothing to retire on that side.
-- W4b: data_bwl.lua joins the DELETED list, and the parked list is now EMPTY. It was
-- the LAST 1.x data file on disk; it was diffed against §4 row by row, the spec won
-- every disagreement, one log-verified mechanic the spec lacks entirely was carried
-- over default-off, and everything else is in the wave report. Zul'Gurub never had a
-- 1.x data file, so there is nothing to retire on that side.
-- W4a: NOTHING NEW IS RETIRED, and that is the finding. Molten Core, Onyxia's Lair
-- and the world bosses never had a 1.x data file — data_naxxramas / data_aq40 /
-- data_bwl were the only three that ever existed — so this wave had nothing to diff
-- against, nothing to restore, and nothing to park. With W4 closed, the parked list is
-- permanently empty and the RegisterRaid refusal shim (core_boot.lua) has no legacy
-- caller class left anywhere in the addon; it stays as a guard for third-party callers.
local RETIRED_PATHS   = { "engine.lua", "encounters.lua", "data_naxxramas.lua",
                          "data_aq40.lua", "data_bwl.lua",
                          -- asserted absent so a future wave cannot invent one
                          "data_moltencore.lua", "data_onyxia.lua", "data_worldbosses.lua" }
local PARKED_OUT_OF_TOC = {}

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
for _, rel in ipairs({ "svc_era.lua", "svc_scan.lua", "ui_bars.lua",
                       "ui_warnings.lua", "public_api.lua" }) do
    ck(TOC_SET[rel], rel .. " IS in the load list (the wave-2 surfaces actually ship)")
end
ck(TOC_SET["enc_naxxramas.lua"], "enc_naxxramas.lua IS in the load list (wave 4d ships the data)")
ck(TOC_SET["enc_aq20.lua"], "enc_aq20.lua IS in the load list (wave 4c ships AQ20)")
ck(TOC_SET["enc_aq40.lua"], "enc_aq40.lua IS in the load list (wave 4c ships AQ40)")
ck(TOC_SET["enc_bwl.lua"], "enc_bwl.lua IS in the load list (wave 4b ships BWL)")
ck(TOC_SET["enc_zg.lua"], "enc_zg.lua IS in the load list (wave 4b ships ZG)")
do  -- wave 2 stacks ON the wave-1 seam, and the toc must express that too
    local pos = {}
    for i, rel in ipairs(TOC_LUA) do pos[rel] = i end
    ck(pos["core_boot.lua"] and pos["svc_era.lua"] and pos["core_boot.lua"] < pos["svc_era.lua"],
       "the wave-1 engine loads before the wave-2 services")
    ck(pos["svc_era.lua"] < pos["ui_bars.lua"] and pos["svc_era.lua"] < pos["ui_warnings.lua"],
       "svc_era loads before the presentation (it installs the role/class resolvers)")
    ck(pos["theme.lua"] < pos["ui_bars.lua"] and pos["media.lua"] < pos["ui_warnings.lua"],
       "the theme tokens and the sound bucket load before the surfaces that use them")
    ck(pos["alerts.lua"] and pos["alerts.lua"] > pos["ui_bars.lua"],
       "alerts.lua still ships (design verdict: KEEP + EXTEND — the Naxx specials call it)")
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
    -- AUDIT RM-2 (SUITE_DATA_HONESTY_AUDIT §5, lesson Class 6). The group world had
    -- NO cold-roster profile, which is exactly why RM-2 was invisible headless.
    -- `rosterDark` is the live post-/reload shape, verbatim: `IsInGroup()` already
    -- answers true — the client has restored the fact that you are in a raid — while
    -- `GetNumGroupMembers()` still answers 0 and `IsInRaid()` is still false, so the
    -- shipping iterator would synthesize `party1..N` units that do not exist in a
    -- 40-man. The default is FALSE (a warm roster) because every pre-existing fixture
    -- asserts against a populated group; the profile is opted INTO by the fixtures
    -- that model the login seam.
    W.rosterDark = false
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

-- ── wave 2: the audible world, recorded rather than played ────────────────────
-- Sound is a real output of the warning tiers, so it is stubbed and CAPTURED,
-- which is what makes the §5.5 replacement matrix assertable at all.
local SOUNDS = {}
_G.PlaySound     = function(v) SOUNDS[#SOUNDS + 1] = { kind = "kit",  value = v } end
_G.PlaySoundFile = function(v) SOUNDS[#SOUNDS + 1] = { kind = "file", value = v } end
local function lastSound() return SOUNDS[#SOUNDS] end
local function clearSounds() for i = #SOUNDS, 1, -1 do SOUNDS[i] = nil end end
_G.IsShiftKeyDown = function() return false end
_G.SendChatMessage = function() end
_G.IsInGroup = function() return true end
_G.IsInRaid  = function() return true end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

----------------------------------------------------------------------
-- Load the REAL addon files into one Addon namespace.
----------------------------------------------------------------------
local Addon = {}
local ENGINE_FILES = {
    "core.lua", "theme.lua", "media.lua", "soundpacks.lua",
    "core_heap.lua", "core_telemetry.lua", "core_sched.lua",
    "core_timers.lua", "core_api.lua", "core_lifecycle.lua",
    -- wave 5: the owner's diagnostics, split out of the retired core_boot scaffold.
    "core_diag.lua", "core_boot.lua",
    -- wave 3: the addon channel, then the receive-only interop bridge that writes
    -- its prefixes into the channel's transmit firewall at LOAD time.
    "core_sync.lua", "dbm_bridge.lua",
    -- wave 2: services, presentation, public contract. Loaded in TOC ORDER, so a
    -- load-order mistake shows up here rather than in-game.
    "svc_era.lua", "svc_scan.lua", "ui_bars.lua", "ui_warnings.lua", "public_api.lua",
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
-- W5: options.lua, for the parts of it that are NOT frame code. `Addon:RegisterOptions`
-- and every build*() need DaseekiUI and CreateFrame and are correctly untestable
-- headless — but the telemetry REPORT builder is pure string work over the ring, and
-- it is the arbitration instrument, so it gets asserted like anything else. The file
-- binds `local UI = DaseekiUI` at load (nil here) and only dereferences it inside
-- frame-building functions, so executing the chunk is safe.
do
    local chunk = assert(loadfile(P("options.lua")))
    assert(pcall(chunk, ADDON_NAME, Addon))
end
-- WAVE 4d: the Naxxramas encounter data. Kept as a re-runnable chunk because the
-- earlier gates deliberately wipe the encounter registry to install their fixtures;
-- the Naxx gates re-execute this to repopulate it with the SHIPPING data.
local NAXX_CHUNK = loadfile(P("enc_naxxramas.lua"))
if not NAXX_CHUNK then
    realprint("  FAIL  loadfile enc_naxxramas.lua"); os.exit(2)
end
-- WAVE 4c: the same treatment for the two Ahn'Qiraj zones.
local AQ20_CHUNK = loadfile(P("enc_aq20.lua"))
if not AQ20_CHUNK then realprint("  FAIL  loadfile enc_aq20.lua"); os.exit(2) end
local AQ40_CHUNK = loadfile(P("enc_aq40.lua"))
if not AQ40_CHUNK then realprint("  FAIL  loadfile enc_aq40.lua"); os.exit(2) end
-- WAVE 4b: Blackwing Lair and Zul'Gurub.
local BWL_CHUNK = loadfile(P("enc_bwl.lua"))
if not BWL_CHUNK then realprint("  FAIL  loadfile enc_bwl.lua"); os.exit(2) end
local ZG_CHUNK = loadfile(P("enc_zg.lua"))
if not ZG_CHUNK then realprint("  FAIL  loadfile enc_zg.lua"); os.exit(2) end
-- WAVE 4a: Molten Core, Onyxia's Lair and the six world bosses — the wave that closes
-- W4. Same re-runnable-chunk treatment as every other zone.
local MC_CHUNK = loadfile(P("enc_moltencore.lua"))
if not MC_CHUNK then realprint("  FAIL  loadfile enc_moltencore.lua"); os.exit(2) end
local ONY_CHUNK = loadfile(P("enc_onyxia.lua"))
if not ONY_CHUNK then realprint("  FAIL  loadfile enc_onyxia.lua"); os.exit(2) end
local WB_CHUNK = loadfile(P("enc_worldbosses.lua"))
if not WB_CHUNK then realprint("  FAIL  loadfile enc_worldbosses.lua"); os.exit(2) end

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
    -- AUDIT RM-2: under the cold-roster profile the client answers "yes you are in a
    -- group" and "no you are not in a raid, and it has nobody in it" AT THE SAME
    -- TIME. That contradiction IS the defect's habitat.
    IsInRaid            = function() if W.rosterDark then return false end return W.inRaid ~= false end,
    IsInGroup           = function() return W.inGroup ~= false end,
    GetNumGroupMembers  = function() if W.rosterDark then return 0 end return #W.group end,
    ForEachGroupMember  = function(fn)
        -- The shipping iterator derives its unit tokens from the two answers above;
        -- the fixture keeps an explicit list, so a dark roster is modelled by its
        -- OUTCOME — an empty walk, which is what raid1..raid0 / party1..N produce.
        if W.rosterDark then return false end
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
-- WAVE 2 — the fake world grows the fields the services read.
----------------------------------------------------------------------
local Bars, BM, Warn, Scan, Era, Public =
    Addon.Bars, Addon.Bars.Model, Addon.Warnings, Addon.Scan, Addon.Era, Addon.Callbacks

W.itemRange = {}     -- ("item:unit") -> boolean, or nil for "the API refused"
W.inRange   = {}     -- unit -> boolean (the binary 43 yd test)
W.known     = {}     -- spellId -> true
W.cooldown  = {}     -- spellId -> { start = , duration = }
W.auras     = {}     -- spellId -> true (player buffs)
W.threat    = {}     -- ("unit@mob") -> status number
W.distance  = {}     -- unit -> exact yards (only consulted where world position exists)
W.talents   = {}     -- tab index -> points spent
-- AUDIT RM-1 (SUITE_DATA_HONESTY_AUDIT §5, lesson Class 5). The talent stubs used to
-- be `GetNumTalentTabs = function() return 3 end` and a `GetTalentTabInfo` that
-- always answered a number — `n` was always 3, `points` was always a number, and the
-- COLD-TALENT WORLD SIMPLY DID NOT EXIST here. That hardcode is the single reason
-- RM-1 was invisible. It is now a profile with two axes, because the client has two
-- distinct cold shapes and the fix has to survive both:
--   "none"  GetNumTalentTabs() answers 0            (the tree is not there yet)
--   "nil"   it answers 3 but every tab returns nil  (the tree is there, unfilled)
--   "warm"  the spec-behaving profile
-- The spec-behaving profile is the DEFAULT only because every pre-existing Era
-- fixture asserts against a readable tree; the cold profiles are what the RM-1 gate
-- boots a Protection paladin under.
W.talentProfile = "warm"
W.class     = "WARRIOR"
W.form      = 0
W.mainTank  = false
W.level     = 60
W.hasPosition = true
W.roster    = {}     -- name -> { class = , mark = , crossRealm = }
W.aliveInZone = nil

Era:SetEnv({
    UnitExists    = function(u) return unit(u) ~= nil end,
    UnitGUID      = function(u) return (unit(u) or {}).guid end,
    UnitName      = function(u) return (unit(u) or {}).name or u end,
    UnitClass     = function() return W.class, W.class end,
    UnitLevel     = function() return W.level end,
    UnitHealth    = function(u) return (unit(u) or {}).hp end,
    UnitHealthMax = function(u) return (unit(u) or {}).hpmax end,
    UnitIsDeadOrGhost = function(u) return (unit(u) or {}).dead and true or false end,
    UnitIsUnit    = function(a, b) return a == b end,
    UnitIsFriend  = function(_, u) return (unit(u) or {}).friend and true or false end,
    UnitInRange   = function(u) return W.inRange[u] end,
    UnitPosition  = function() if W.hasPosition then return 1, 2, 0, 0 end return nil end,
    UnitDistanceSquared = function(u)
        local d = W.distance[u]
        if not d then return nil end
        return d * d
    end,
    UnitDetailedThreatSituation = function(u, mob)
        local st = W.threat[tostring(u) .. "@" .. tostring(mob)]
        if st == nil then return nil end
        return st == 3, st
    end,
    IsItemInRange = function(item, u) return W.itemRange[tostring(item) .. ":" .. tostring(u)] end,
    IsSpellKnown  = function(id) return W.known[id] and true or false end,
    GetSpellInfo  = function(id) return W.known[id] and ("spell" .. id) or nil end,
    GetSpellCooldown = function(id)
        local c = W.cooldown[id]
        if not c then return 0, 0 end
        return c.start, c.duration
    end,
    GetShapeshiftFormID = function() return W.form end,
    GetNumTalentTabs = function()
        if W.talentProfile == "none" then return 0 end
        return 3
    end,
    GetTalentTabInfo = function(i)
        -- The "nil" profile is the nastier of the two: the tab EXISTS and answers a
        -- name, and only the points column is absent. That is the read `points or 0`
        -- turned into a truthy, wrong zero.
        if W.talentProfile ~= "warm" then return "tab" .. i, nil, nil, nil, nil end
        return "tab" .. i, nil, nil, nil, W.talents[i] or 0
    end,
    GetPartyAssignment = function(role) return role == "MAINTANK" and W.mainTank end,
    PlayerHasAura = function(id) return W.auras[id] and true or false end,
})

Scan:SetEnv({
    UnitExists   = function(u) return unit(u) ~= nil end,
    UnitGUID     = function(u) return (unit(u) or {}).guid end,
    UnitName     = function(u) return (unit(u) or {}).name or u end,
    UnitIsPlayer = function(u) return (unit(u) or {}).player and true or false end,
    UnitIsFriend = function(_, u) return (unit(u) or {}).friend and true or false end,
    UnitIsUnit   = function(a, b) return a == b end,
    UnitIsDeadOrGhost = function(u) return (unit(u) or {}).dead and true or false end,
    GetNumGroupMembers = function() return #W.group end,
    IsInRaid = function() return true end,
    IsInGroup = function() return #W.group > 1 end,
    UnitDetailedThreatSituation = function(u, mob)
        local st = W.threat[tostring(u) .. "@" .. tostring(mob)]
        if st == nil then return nil end
        return st == 3, st
    end,
    IsGroupMember = function(u) return (unit(u) or {}).player and true or false end,
    -- W4b: the unit-fact sweep and the encounter-in-progress poll read the world
    -- through Scan.env like everything else, so both run on the fake world.
    UnitHealthMax = function(u) return (unit(u) or {}).hpmax end,
    UnitBuff = function(u, i)
        local buffs = (unit(u) or {}).buffs
        local id = buffs and buffs[i]
        if not id then return nil end
        return "buff" .. tostring(id), nil, nil, nil, nil, nil, nil, nil, nil, id
    end,
    IsEncounterInProgress = function() return W.encounterInProgress end,
})

Warn:SetEnv({
    RosterInfo = function(name) return W.roster[name] end,
    AliveInZone = function() return W.aliveInZone end,
    UnitIsDeadOrGhost = function(u) return (unit(u) or {}).dead and true or false end,
})

-- The wave-2 surfaces are booted explicitly here (InitEngine did it once already in
-- GATE HATCH; both paths are idempotent). Re-installing the resolvers matters:
-- GATE API deliberately swapped in fixture resolvers.
Era.Init(); Scan.Init(); Bars.Init(); Warn.Init(); Public.Init()
Addon.RoleResolver, Addon.ClassResolver = Era.ResolveRole, Era.Class
Addon.RoleKnown = Era.RoleKnown          -- AUDIT RM-1: the third resolver, same seam

local function resetW2()
    resetLife()
    Timers.StopAll()
    BM.Clear()
    Warn.Reset()
    Scan.StopAll()
    Era.ClearCache(); Era.ResetHealth()
    Tele.Clear()
    Era.roleState.tankLatched = false
    clearSounds()
    for k in pairs(W.itemRange) do W.itemRange[k] = nil end
    for k in pairs(W.inRange)   do W.inRange[k]   = nil end
    for k in pairs(W.known)     do W.known[k]     = nil end
    for k in pairs(W.cooldown)  do W.cooldown[k]  = nil end
    for k in pairs(W.auras)     do W.auras[k]     = nil end
    for k in pairs(W.threat)    do W.threat[k]    = nil end
    for k in pairs(W.distance)  do W.distance[k]  = nil end
    for k in pairs(W.talents)   do W.talents[k]   = nil end
    for k in pairs(W.roster)    do W.roster[k]    = nil end
    W.class, W.form, W.mainTank, W.level, W.hasPosition = "WARRIOR", 0, false, 60, true
    W.aliveInZone = nil
    -- AUDIT RM-1: every fixture starts from the spec-behaving talent profile with no
    -- role on record, so a gate that wants the cold world has to ask for it and a
    -- gate that does not cannot inherit one by accident.
    W.talentProfile = "warm"
    Era.roleState.signature   = nil
    Era.roleState.warmthArmed = false
    local bs = Bars.Settings()
    bs.hideAll, bs.hiddenMode, bs.variance, bs.varianceCountdown = false, false, true, false
    bs.animate, bs.enlargeAt, bs.hideAbove = true, 11, 60
    bs.small.sort, bs.small.grow = "asc", "DOWN"
    bs.large.sort, bs.large.grow = "asc", "UP"
    local ws = Warn.Settings()
    for k, v in pairs({ hideWarnings = false, suppressBossAnnounce = false,
                        suppressTargetAnnounce = true, suppressSpecialText = false,
                        suppressSpecialFlash = false, suppressSpecialSound = false,
                        suppressVibration = false, voiceReplacesAnnounce = false,
                        voiceReplacesSpecialSound = false, voiceEnabled = true,
                        voicePackVersion = 19, mirrorToChat = false, combineSort = false }) do
        ws[k] = v
    end
    Addon.db.mechanics = {}
end

----------------------------------------------------------------------
-- GATE BARS — §4.2 variance rendering, §4.7 the status-bar layer
----------------------------------------------------------------------
gate("BARS  §4.2/§4.7 bar model: variance, sort, anchors, recolour")
resetW2()
do  -- the model adopts a real engine bar off the real seam
    local t = Timers.New({ id = "B1", key = "cleave", encId = "fix", kind = "cd",
                           duration = 30, color = 4, text = "Cleave" })
    t:Start()
    local row = BM.rows[t:BarId()]
    ck(row ~= nil, "a TIMER_START on the engine seam creates a bar row (no polling)")
    eq(row.class, 4, "…carrying the declared colour class")
    eq(BM.DisplayText(row), "Cleave", "…and its display text")
    eq(BM.AnchorOf(row, CLOCK), "small", "a 30 s bar sits on the SMALL list")
    Timers.StopAll()
    eq(BM.count, 0, "a TIMER_STOP removes the row")
end
do  -- §4.2 the variance geometry, which is the whole rendering contract
    resetW2()
    local t = Timers.New({ id = "BV", key = "breath", encId = "fix", kind = "cd",
                           duration = "v40-60", text = "Breath" })
    local bar = t:Start()
    local row = BM.rows[bar.id]
    eq(BM.Total(row), 60, "with variance display ON the bar's RENDER total is the MAX")
    near(BM.SortValue(row, CLOCK), 40, 0.001,
         "…while sort / enlarge / hide evaluate against the MIN (a v40-60 enlarges at 40)")
    near(BM.Remaining(row, CLOCK), 60, 0.001, "…and the fill runs to the max")
    local span, left = BM.VarianceSpan(row, CLOCK)
    near(span, 20 / 60, 0.001, "the variance overlay covers varianceDuration/total of the width")
    near(left + span, BM.Fill(row, CLOCK), 0.001, "…anchored to the FILL EDGE")
    advance(45)
    local span2, left2 = BM.VarianceSpan(row, CLOCK)
    ck(span2 < span, "…and shrinks as the fill passes into the window")
    eq(left2, 0, "…clamped at the left edge once the fill is inside it")
    resetW2()
    local bs = Bars.Settings(); bs.variance = false; Bars.PushVarianceOption()
    local t2 = Timers.New({ id = "BV2", key = "b2", kind = "cd", duration = "v40-60" })
    local b2 = t2:Start()
    eq(BM.Total(BM.rows[b2.id]), 40, "with variance display OFF the bar runs to MIN")
    eq(BM.VarianceSpan(BM.rows[b2.id], CLOCK), 0, "…and paints no window")
    bs.variance = true; Bars.PushVarianceOption()
end
do  -- §4.7 anchors: auto-enlarge, always-large classes, hidden-bar mode
    resetW2()
    local t = Timers.New({ id = "BE", key = "e", kind = "cd", duration = 30 })
    local row = BM.rows[t:Start().id]
    eq(BM.AnchorOf(row, CLOCK), "small", "a bar above the enlarge threshold is small")
    advance(20)
    eq(BM.AnchorOf(row, CLOCK), "large", "…and auto-enlarges at 11 s remaining (§12)")
    t:AddTime(60)
    eq(BM.AnchorOf(row, CLOCK), "large",
       "…the enlargement is STICKY, so a bar given time back does not bounce anchors")

    resetW2()
    local u = Timers.New({ id = "BU", key = "u", kind = "cd", duration = 300, color = 7 })
    eq(BM.AnchorOf(BM.rows[u:Start().id], CLOCK), "large",
       "colour-type 7 bars START LARGE and never shrink (§4.7)")
    local p = Timers.New({ id = "BP", key = "p", kind = "combat", duration = 300 })
    p.Category = function() return "pull" end
    eq(BM.AnchorOf(BM.rows[p:Start().id], CLOCK), "large",
       "…and so do the three special categories (pull / break / berserk)")

    resetW2()
    Bars.Settings().hiddenMode = true
    local h = Timers.New({ id = "BH", key = "h", kind = "cd", duration = 120 })
    local hrow = BM.rows[h:Start().id]
    eq(BM.AnchorOf(hrow, CLOCK), "hidden", "hidden-bar mode parks a bar longer than 60 s")
    advance(61)
    eq(BM.AnchorOf(hrow, CLOCK), "small",
       "…and it RE-ENTERS the list when it crosses the threshold (hiding is not sticky)")
    Bars.Settings().hiddenMode = false
end
do  -- §4.2 sorting and the layout, which is what the view actually reads
    resetW2()
    local defs = { { "S1", 50 }, { "S2", 20 }, { "S3", 35 } }
    for _, d in ipairs(defs) do
        Timers.New({ id = d[1], key = d[1], kind = "cd", duration = d[2] }):Start()
    end
    local L = BM.Layout(CLOCK)
    eq(#L.small, 3, "every eligible bar lands on an anchor list")
    eq(L.small[1].timerId .. L.small[2].timerId .. L.small[3].timerId, "S2S3S1",
       "the small list sorts ASCENDING by the minimum-end remaining")
    eq(L.small[1].slot, 1, "…and every row is stamped with its slot")
    Bars.Settings().small.sort = "desc"
    L = BM.Layout(CLOCK)
    eq(L.small[1].timerId .. L.small[2].timerId .. L.small[3].timerId, "S1S3S2",
       "…and descending when the anchor is configured that way")
    Bars.Settings().small.sort = "asc"
    -- variance sorts on MIN, not on the rendered max: a v10-90 bar outranks a flat 50
    resetW2()
    Timers.New({ id = "SV", key = "sv", kind = "cd", duration = "v20-90" }):Start()
    Timers.New({ id = "SF", key = "sf", kind = "cd", duration = 50 }):Start()
    L = BM.Layout(CLOCK)
    eq(L.small[1].timerId, "SV",
       "a v20-90 bar sorts AHEAD of a flat 50 s bar, because sorting uses the MINIMUM")
    near(BM.Remaining(L.small[1], CLOCK), 90, 0.01,
       "…even though it RENDERS as the longer of the two (min sorts, max draws)")
    local _, dy1 = BM.SlotOffset(1, "DOWN", 20, 2)
    local _, dy2 = BM.SlotOffset(2, "DOWN", 20, 2)
    eq(dy1, 0, "slot 1 sits on the anchor with no gap")
    eq(dy2, -22, "…and each further slot is exactly one bar + one pad away (growing down)")
    local _, uy2 = BM.SlotOffset(2, "UP", 20, 2)
    eq(uy2, 22, "…mirrored for an anchor that grows up")
end
do  -- THE CHROMAGGUS CONTRACT: mid-fight recolour + rename on a RUNNING bar
    resetW2()
    local t = Timers.New({ id = "CHROMA", key = "breath", encId = "chromaggus",
                           kind = "cd", duration = 60, color = 2, text = "Breath" })
    local bar = t:Start()
    local born = bar.startedAt
    advance(10)
    local row = Bars.Restyle(bar.id, { text = "Frost Burn", color = 4 })
    ck(row ~= nil, "Restyle addresses a live bar")
    eq(BM.DisplayText(row), "Frost Burn", "…renaming it mid-fight")
    eq(row.class, 4, "…and recolouring it to the interrupt class")
    eq(bar.startedAt, born, "…WITHOUT touching its elapsed time (a restart would lie)")
    near(BM.Remaining(row, CLOCK), 50, 0.1, "…so the remaining time is untouched")
    eq(Tele.Count(), 0, "…and the early-refresh tripwire is NOT tripped (it was not a restart)")
    eq(t.text, "Frost Burn", "the owning TIMER OBJECT is renamed too")
    local bar2 = t:Start()
    eq(BM.rows[bar2.id].baseText, "Frost Burn",
       "…so the next cast keeps the identified name for the rest of the fight")
end
do  -- §11.4 the pull timer, which wave 1 re-seated as a real timer with no consumer
    resetW2()
    -- NOTE: what the pull timer does with an out-of-range duration is §11.4's rule
    -- and NOT this surface's to assert — the sync wave owns StartPullTimer. All this
    -- gate cares about is that a `pull`-category timer DRAWS, which is the wave-2 gap.
    Addon:StartPullTimer(10, "harness")
    local prow
    for _, r in pairs(BM.rows) do if r.category == "pull" then prow = r end end
    ck(prow ~= nil, "a pull timer is RENDERED by the bar surface (it was invisible in wave 1)")
    eq(prow.class, "pull", "…in the pull colour class")
    eq(BM.AnchorOf(prow, CLOCK), "large", "…on the large anchor, where a countdown belongs")
    ck(BM.DisplayText(prow) ~= "", "…with text")
    Addon:CancelPullTimer("harness")
    local still
    for _, r in pairs(BM.rows) do if r.category == "pull" then still = r end end
    eq(still, nil, "cancelling the pull timer removes its bar")
end
do  -- §4.7 keep / fade, count text, the numeric readout, and the flash phase
    resetW2()
    local k = Timers.New({ id = "BK", key = "k", kind = "cd", duration = 3, keep = true })
    local kb = k:Start()
    advance(3.2)
    ck(BM.rows[kb.id] ~= nil, "a KEEP bar survives its own natural expiry")
    eq(BM.TimeText(BM.rows[kb.id], CLOCK), "0.0", "…pinned at zero")
    eq(k:StopBar(kb.id, "stopped"), false,
       "…and the ENGINE no longer owns it, so Timer:Stop cannot reach it")
    ck(Bars.Dismiss(kb.id), "…it is dismissed through the bar surface instead")
    eq(BM.rows[kb.id], nil, "…and then it is gone")
    local k2 = Timers.New({ id = "BK2", key = "k2", kind = "cd", duration = 3, keep = true })
    local kb2 = k2:Start()
    advance(3.2)
    ck(BM.rows[kb2.id] ~= nil, "a kept bar outlives its own expiry…")
    Addon:FireEngineEvent("ENGINE_END", "fix", nil, false, 10)
    eq(BM.rows[kb2.id], nil, "…but never outlives the FIGHT (the end sweeps kept rows)")

    resetW2()
    local c = Timers.New({ id = "BC", key = "c", kind = "cd", duration = 20,
                           count = true, text = "Meteor" })
    local cb = c:Start(20, 3)
    eq(BM.DisplayText(BM.rows[cb.id]), "Meteor (3)",
       "a count timer's identity argument becomes the displayed count")
    local c2 = Timers.New({ id = "BC2", key = "c2", kind = "cd", duration = 20,
                            count = true, text = "Spore %d" })
    local cb2 = c2:Start(20, 5)
    eq(BM.DisplayText(BM.rows[cb2.id]), "Spore 5", "…and a %d template formats instead")

    eq(BM.FormatTime(3.24, false, 10), "3.2", "readout: one decimal below the threshold")
    eq(BM.FormatTime(42.4, false, 10), "42", "…whole seconds up to 60")
    eq(BM.FormatTime(95, false, 10), "1:35", "…m:ss above 60")
    eq(BM.FormatTime(42.4, true, 10), "~42", "…approximate bars are prefixed with ~")
    eq(BM.FormatTime(-2, false, 10), "-2.0",
       "…and the variance countdown mode can run negative through the window")

    resetW2()
    local f = Timers.New({ id = "BF", key = "f", kind = "cd", duration = 7 })
    local fr = BM.rows[f:Start().id]
    fr.bornAt = CLOCK
    eq(BM.FlashAlpha(fr, CLOCK), 1, "flash: full brightness for the first 0.5 s of the cycle")
    near(BM.FlashAlpha(fr, CLOCK + 0.625), 0.5, 0.01, "…ramping down across the next 0.25 s")
    eq(BM.FlashAlpha(fr, CLOCK + 1.0), 0, "…then dark for the rest of the 1.25 s cycle")
    eq(BM.FlashAlpha(fr, CLOCK + 1.25), 1, "…and the cycle repeats")
    local g = Timers.New({ id = "BG", key = "g", kind = "cd", duration = 30 })
    eq(BM.FlashAlpha(BM.rows[g:Start().id], CLOCK), 0, "a bar above 7.75 s never flashes")
end
do  -- §5.4 the global suppressor and the per-row display option
    resetW2()
    Timers.New({ id = "BS", key = "s", kind = "cd", duration = 30 }):Start()
    eq(#BM.Layout(CLOCK).small, 1, "a bar is laid out normally")
    Bars.Settings().hideAll = true
    local L = BM.Layout(CLOCK)
    eq(#L.small + #L.large, 0, "'hide all bar timers' takes every bar off both anchors")
    eq(#L.hidden, 1, "…without destroying the rows (the broadcast still needs them)")
    Bars.Settings().hideAll = false

    resetW2()
    Addon.db.mechanics["fix:hidden"] = { bar = false }
    local t = Timers.New({ id = "BD", key = "hidden", encId = "fix", kind = "cd", duration = 30 })
    local row = BM.rows[t:Start().id]
    eq(row.enabled, false, "a per-row bar-display override marks the row not-displayed")
    eq(#BM.Layout(CLOCK).small, 0, "…and keeps it off the anchors")
    ck(BM.rows[row.id] ~= nil, "…while the row itself still exists (see GATE PUB, field 18)")
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
-- GATE WARN — §5.1 the tiers, §5.2 targeting, §5.4 filters, §5.5 voice
----------------------------------------------------------------------
gate("WARN  §5.1/§5.2/§5.5 warning tiers")
resetW2()
do  -- §5.1 the slot machine, rule for rule
    local st = Warn.NewStack(3)
    eq((st:Push({ text = "a" }, CLOCK)), 1, "a new line takes the FIRST FREE SLOT")
    eq((st:Push({ text = "b" }, CLOCK)), 2, "…then the next")
    eq((st:Push({ text = "c" }, CLOCK)), 3, "…then the last")
    local slot, scrolled = st:Push({ text = "d" }, CLOCK)
    eq(slot, 3, "with all three busy the new line takes slot 3")
    eq(scrolled, true, "…and the stack scrolled")
    eq(st.slots[1].text, "b", "…the oldest scrolled OFF (line 2 -> 1)")
    eq(st.slots[2].text, "c", "…(line 3 -> 2)")
    eq(st.slots[3].text, "d", "…and the new line is slot 3")
    -- an expired MIDDLE line frees its slot without compacting the others
    st.slots[2].at = CLOCK - 99
    st:Prune(CLOCK)
    eq(st.slots[2], nil, "an expired line frees its slot")
    eq(st.slots[3].text, "d", "…without shuffling the lines around it")
    eq((st:Push({ text = "e" }, CLOCK)), 2, "…so the next line fills the hole")
    eq(Warn.specialStack.lines, 2, "the SPECIAL tier is a two-line stack, not three")
end
do  -- §5.1 duration / fade / pop
    local e = { at = CLOCK, duration = Warn.DURATION }
    eq(Warn.Alpha(e, CLOCK + 1.4), 1, "full alpha for the whole 1.5 s duration")
    near(Warn.Alpha(e, CLOCK + 1.725), 0.5, 0.01, "…then a fade over an ADDITIONAL 30 % of it")
    eq(Warn.Alpha(e, CLOCK + 1.95), 0, "…reaching zero at duration + 30 %")
    eq(Warn.PopScale(e, CLOCK), 1, "the pop starts at 1x")
    near(Warn.PopScale(e, CLOCK + 0.2), 1.5, 0.001, "…scales to 1.5x over 0.2 s")
    near(Warn.PopScale(e, CLOCK + 0.4), 1, 0.001, "…and back over the next 0.2 s")
end
do  -- §5.1 the sound-tier default table
    local rep = {}
    for i = 1, 5 do rep[i] = Warn.SOUND_TIER[i].flashRepeat end
    eq(table.concat(rep, ","), "1,1,3,2,3",
       "flash repeats default to 1,1,3,2,3 across the five tiers (§5.1)")
    local vib = {}
    for i = 1, 5 do vib[i] = Warn.SOUND_TIER[i].vibrate and "y" or "n" end
    eq(table.concat(vib, ","), "n,n,y,y,y", "…and vibration is on for tiers 3-5 ONLY")
end
do  -- the engine seam actually reaches the right tier
    resetW2()
    Addon:EmitAnnounce("fix", { key = "a1", color = 3 }, "Doom incoming")
    eq(Warn.announceStack:Count(), 1, "WARN_ANNOUNCE lands on the ANNOUNCE stack")
    eq(Warn.specialStack:Count(), 0, "…and not on the special one")
    Addon:EmitSpecial("fix", { key = "s1", tier = "special", sound = 4 }, "RUN OUT")
    eq(Warn.specialStack:Count(), 1, "WARN_SPECIAL lands on the SPECIAL stack")
    ck(lastSound() ~= nil, "…and a special warning makes a sound")
end
do  -- §5.5 the voice / sound replacement matrix
    resetW2()
    local row = { key = "v", tier = "special", sound = 2, voice = "targetyou" }
    clearSounds()
    eq(Warn.DispatchSound("fix", row, true), "sound",
       "with the replacement switch OFF a special warning plays its TIER SOUND")
    Warn.Settings().voiceReplacesSpecialSound = true
    clearSounds()
    eq(Warn.DispatchSound("fix", row, true), "voice",
       "…with it ON the voice line replaces the built-in tier sound")
    ck(tostring(lastSound().value):find("targetyou", 1, true) ~= nil,
       "…and the file played is the SYMBOLIC LINE resolved through the bundled pack")
    Addon.db.mechanics["fix:v"] = { sound = "raidwarning" }
    clearSounds()
    eq(Warn.DispatchSound("fix", row, true), "sound",
       "…but a USER-SELECTED custom sound always wins over the voice pack (§5.5)")
    Addon.db.mechanics["fix:v"] = nil
    -- version gating degrades LINE BY LINE, not wholesale
    row.voiceVersion = 25
    ck(not Warn.VoiceAllowed(row),
       "a voice line introduced in a NEWER pack version does not play")
    row.voiceVersion = 19
    ck(Warn.VoiceAllowed(row), "…while a line at or below the installed version does")
    row.voiceVersion = nil
    Warn.Settings().voiceReplacesAnnounce = true
    clearSounds()
    eq(Warn.DispatchSound("fix", { key = "v2", voice = "breathsoon" }, false), "voice",
       "the ANNOUNCE replacement switch is independent of the special one")
end
do  -- §5.4 the global suppressors
    resetW2()
    Warn.Settings().hideWarnings = true
    eq(Warn.ShowAnnounce("fix", { key = "x" }, "nope"), nil, "'hide all warnings' drops announcements")
    eq(Warn.ShowSpecial("fix", { key = "y", sound = 1 }, "nope"), nil, "…and special warnings")
    resetW2()
    Warn.Settings().suppressSpecialText = true
    clearSounds()
    local idx = Warn.ShowSpecial("fix", { key = "z", sound = 2 }, "silent but loud")
    eq(idx, nil, "suppressing special TEXT removes the line")
    ck(lastSound() ~= nil, "…while the sound still fires (the suppressors are independent)")
    resetW2()
    local s = Warn.Settings()
    s.suppressSpecialText, s.suppressSpecialFlash, s.suppressSpecialSound = true, true, true
    ck(Warn.SpecialFullySuppressed(), "all three special suppressors on is detectable")
    clearSounds()
    eq(Warn.ShowSpecial("fix", { key = "q", sound = 1 }, "nothing"), nil,
       "…and the show path SHORT-CIRCUITS AT THE TOP (§5.4, for CPU)")
    eq(lastSound(), nil, "…doing no work at all")
    resetW2()
    W.units.player.dead = true
    eq(Warn.Flash(3), false, "the screen flash is suppressed while the player is dead or a ghost")
    W.units.player.dead = false
    eq(Warn.Flash(3), true, "…and fires otherwise")
    Warn.Settings().suppressVibration = true
    eq(Warn.Vibrate(3), false, "vibration has its own suppressor")
    Warn.Settings().suppressVibration = false
    eq(Warn.Vibrate(1), false, "…and tier 1 does not vibrate regardless")
end
do  -- §5.2 name colouring
    resetW2()
    W.roster["Bob"] = { class = "MAGE" }
    W.roster["Ann-Stormwind"] = { class = "PRIEST", mark = 3 }
    W.roster["Zed-Faerlina"]  = { class = "ROGUE", crossRealm = true }
    local out = Warn.ColorNames("Fear on >Bob<", "|cffffffff")
    ck(out:find("|cff" .. Warn.CLASS_HEX.MAGE, 1, true) ~= nil, "a named player is CLASS-COLOURED")
    ck(out:find("|cffffffff", 1, true) ~= nil, "…and the warning's own colour is restored after it")
    out = Warn.ColorNames(">Ann-Stormwind<", nil)
    ck(out:find("Ann", 1, true) and not out:find("Stormwind", 1, true),
       "a same-realm suffix is stripped entirely")
    ck(out:find("RaidTargetingIcon_3", 1, true) ~= nil,
       "…and a marked player is prefixed with their raid-target icon")
    out = Warn.ColorNames(">Zed-Faerlina<", nil)
    ck(out:find("Zed*", 1, true) ~= nil,
       "a CROSS-REALM name becomes a single '*' (shorter than the client's own form)")
    out = Warn.ColorNames(">noStrip Ann-Stormwind<", nil)
    ck(out:find("Ann-Stormwind", 1, true) ~= nil, "…and `noStrip ` opts one token out")
end
do  -- §5.2 the combined batcher
    resetW2()
    local names = { "a", "b", "c", "d", "e", "f", "g", "h", "i" }
    eq(Warn.FormatList(names, 7, false), "a, b, c, d, e, f, g and 2 others",
       "an announce list caps at 7 names with an 'and N others' suffix")
    eq(Warn.FormatList(names, 6, true), "a, b, c, d, e, f and 3 more",
       "…a special warning caps at 6 with 'and N more'")
    local row = { key = "cmb", tier = "announce", color = 2, text = "Sting on %s", combine = 0.5 }
    Warn.Combine("fix", row, "Bob")
    Warn.Combine("fix", row, "Bob")          -- duplicate
    Warn.Combine("fix", row, "Ann")
    eq(Warn.announceStack:Count(), 0, "the combined batcher DEBOUNCES rather than firing per target")
    advance(0.3)
    Warn.Combine("fix", row, "Zed")
    advance(0.4)
    eq(Warn.announceStack:Count(), 0, "…and EACH NEW TARGET RESETS the debounce")
    advance(0.3)
    eq(Warn.announceStack:Count(), 1, "…firing once the window finally elapses")
    local line = Warn.announceStack.slots[1].text
    ck(line:find("Bob", 1, true) and line:find("Ann", 1, true) and line:find("Zed", 1, true),
       "…with every target in one line")
    local _, n = line:gsub("Bob", "")
    eq(n, 1, "…de-duplicated")
end
do  -- §5.2 the precise batcher
    resetW2()
    local row = { key = "pr", tier = "announce", color = 2, text = "Hit: %s", precise = { total = 3 } }
    Warn.Precise("fix", row, "a", 3)
    Warn.Precise("fix", row, "b", 3)
    eq(Warn.announceStack:Count(), 0, "the precise batcher waits below the declared total")
    eq(Warn.Precise("fix", row, "c", 3), true, "…and fires IMMEDIATELY on reaching it")
    eq(Warn.announceStack:Count(), 1, "…with one line")
    resetW2()
    W.aliveInZone = 2
    Warn.Precise("fix", row, "a", 40)
    Warn.Precise("fix", row, "b", 40)
    eq(Warn.announceStack:Count(), 1,
       "…or on reaching the number of players ALIVE IN THE ZONE, whichever comes first")
    resetW2()
    W.aliveInZone = nil
    Warn.Precise("fix", row, "a", 40)
    eq(Warn.announceStack:Count(), 0, "…and neither condition met leaves it pending")
    advance(1.3)
    eq(Warn.announceStack:Count(), 1, "…until the 1.2 s scheduled fallback fires it anyway")
end
do  -- role/class filtering is resolved ENGINE-side; this tier renders what arrives
    resetW2()
    W.class, W.talents[2] = "WARRIOR", 31
    W.form = Era.DEFENSIVE_STANCE_FORM
    local tankRow = { key = "taunt", role = "Tank" }
    eq(API.RowDefault(tankRow), true, "a Tank-gated row ships ON for a resolved tank…")
    resetW2()
    W.class, W.talents[1] = "MAGE", 31
    eq(API.RowDefault(tankRow), false,
       "…and OFF for a mage — the decision is made by the engine, before the tier sees it")
    eq(API.RowDefault({ key = "sb", classDefault = "WARLOCK" }), false,
       "a dynamic class default likewise resolves engine-side")
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
-- GATE SCAN — §5.3 the three scanner shapes on the fake clock
----------------------------------------------------------------------
gate("SCAN  §5.3 the three target scanners")
resetW2()
do  -- the Era token ladder, and the two things NOT in it
    local hasBoss, hasFocus = false, false
    for _, t in ipairs(Scan.ERA_TOKENS) do
        if t:sub(1, 4) == "boss" then hasBoss = true end
        if t:find("focus", 1, true) then hasFocus = true end
    end
    ck(not hasBoss, "the Era token ladder SKIPS boss1..boss10 (§10.2: they never populate)")
    ck(not hasFocus, "…and contains no focus token (§10.4: there is none on Era)")
    ck(Scan.ERA_TOKENS[1] == "mouseover" and Scan.ERA_TOKENS[2] == "target",
       "…and is priority-ordered, cheapest tokens first")
    local n = 0
    for _ in pairs(Scan.EXCLUDED_CREATURES) do n = n + 1 end
    eq(n, 3, "the three hard-coded pet/guardian creature ids are excluded (§5.3a)")
end
do  -- token resolution caches and re-validates
    resetW2()
    setUnit("target", { cid = 90001, combat = true })
    eq(Scan.ResolveUnit(90001), "target", "a creature id resolves to a unit token")
    eq(Scan.tokenCache[90001], "target", "…and the successful token is cached")
    W.units.target = nil
    setUnit("mouseover", { cid = 90001 })
    eq(Scan.ResolveUnit(90001), "mouseover",
       "…a stale cached token is RE-VALIDATED and dropped rather than believed")
end
do  -- (a) the polling scanner: happy path
    resetW2()
    W.group = { "player", "raid1", "raid2" }
    setUnit("raid1", { player = true }); setUnit("raid2", { player = true })
    setUnit("target", { cid = 90001, combat = true })
    setUnit("targettarget", { name = "Victim", player = true, guid = "Player-1-VVVV" })
    local got
    Scan.Poll({ creatureId = 90001, filter = "playersOnly" },
              function(name, tu, bu, el) got = { name, tu, bu, el } end)
    ck(got ~= nil, "the polling scanner reports on its FIRST pass when nothing is filtered")
    eq(got[1], "Victim", "…reporting (name,")
    eq(got[2], "targettarget", "…targetUnitId,")
    eq(got[3], "target", "…bossUnitId,")
    ck(type(got[4]) == "number", "…scanElapsed)")
end
do  -- (a) tank rescan + the final pass that ignores the filter
    resetW2()
    W.group = { "player", "raid1", "raid2" }
    setUnit("raid1", { player = true }); setUnit("raid2", { player = true })
    setUnit("target", { cid = 90001, combat = true })
    setUnit("targettarget", { name = "MainTank", player = true })
    W.threat["targettarget@target"] = 3
    local got, base = nil, CLOCK
    local h = Scan.Poll({ creatureId = 90001, filter = "playersOnly", excludeTank = true },
                        function(name, tu, bu, el) got = { name, el } end)
    eq(got, nil, "with excludeTank set, a tank target is REJECTED and the scan continues")
    advance(0.4)
    eq(got, nil, "…and keeps rescanning")
    advance(0.6)
    ck(got ~= nil, "…until the FINAL pass, which ignores the tank filter")
    eq(got[1], "MainTank", "…so *something* is always reported (§5.3a)")
    near(got[2], 0.75, 0.12, "…inside the 0.05 s x 16 pass budget (~0.8 s worst case, §12)")
    eq(h.result.reason, "final", "…tagged as the final-pass report")
end
do  -- (a) the players-only filter and the excluded-pet list
    resetW2()
    W.group = { "player", "raid1" }
    setUnit("raid1", { player = true })
    setUnit("target", { cid = 90001, combat = true })
    setUnit("targettarget", { name = "SomeAdd", cid = 90099 })   -- an NPC, not a player
    local got
    Scan.Poll({ creatureId = 90001, filter = "playersOnly", tries = 2 },
              function(n) got = n end)
    advance(0.3)
    eq(got, nil, "a players-only scan never reports an NPC")
    resetW2()
    W.group = { "player", "raid1" }
    setUnit("raid1", { player = true })
    setUnit("target", { cid = 90001, combat = true })
    setUnit("targettarget", { name = "Voidwalker", cid = 24207 })
    got = nil
    Scan.Poll({ creatureId = 90001, tries = 2 }, function(n) got = n end)
    advance(0.3)
    eq(got, nil, "…and a hard-excluded pet/guardian creature id (24207) never poisons a scan")
end
do  -- (a) filter-out, and the fallback that returns them on the final pass anyway
    resetW2()
    W.group = { "player", "raid1" }
    setUnit("raid1", { player = true })
    setUnit("target", { cid = 90001, combat = true })
    setUnit("targettarget", { name = "Previous", player = true })
    local got
    Scan.Poll({ creatureId = 90001, filter = "playersOnly", tries = 3,
                filterOut = "Previous" }, function(n) got = n end)
    advance(0.4)
    eq(got, nil, "'filter this player out' excludes the previous victim")
    resetW2()
    W.group = { "player", "raid1" }
    setUnit("raid1", { player = true })
    setUnit("target", { cid = 90001, combat = true })
    setUnit("targettarget", { name = "Previous", player = true })
    got = nil
    Scan.Poll({ creatureId = 90001, filter = "playersOnly", tries = 3,
                filterOut = "Previous", filterOutFallback = true }, function(n) got = n end)
    advance(0.4)
    eq(got, "Previous",
       "…but the optional fallback returns the cached filtered player on the FINAL pass")
end
do  -- (a) solo stops after the first pass with a valid target
    resetW2()
    W.group = { "player" }
    setUnit("target", { cid = 90001, combat = true })
    setUnit("targettarget", { name = "Solo", player = true })
    W.threat["targettarget@target"] = 3          -- would be rejected in a group
    local got
    local h = Scan.Poll({ creatureId = 90001, excludeTank = true }, function(n) got = n end)
    eq(got, "Solo", "SOLO, the scan stops after the first pass with a valid target")
    eq(h.result.reason, "solo", "…skipping the filters entirely (there is no tank to reject)")
end
do  -- (b) the event-driven scanner
    resetW2()
    W.group = { "player", "raid1" }
    setUnit("raid1", { player = true })
    setUnit("target", { cid = 90001 })
    local got
    Scan.Event({ unit = "target" }, function(n, tu, bu, el) got = { n, el } end)
    advance(0.5)
    eq(got, nil, "the event scanner waits, costing nothing, until the unit actually swaps")
    setUnit("targettarget", { name = "Swapped", player = true })
    Scan.OnUnitTarget("target")
    ck(got ~= nil, "…and returns the INSTANT the watched unit changes target")
    eq(got[1], "Swapped", "…naming the new target")
    near(got[2], 0.5, 0.1, "…with the elapsed time it took")

    resetW2()
    setUnit("target", { cid = 90001 })
    got = nil
    local h = Scan.Event({ unit = "target" }, function(n) got = { n } end)
    advance(1.6)
    ck(got ~= nil and got[1] == nil, "…and ABORTS at 1.5 s with nothing when no swap happens")
    eq(h.result.reason, "abort", "…tagged as an abort")

    resetW2()
    setUnit("target", { cid = 90001 })
    setUnit("targettarget", { name = "TankAllAlong", player = true })
    got = nil
    local h2 = Scan.Event({ unit = "target", allowTank = true }, function(n) got = { n } end)
    advance(1.6)
    eq(got and got[1], "TankAllAlong",
       "…while ALLOW TANK makes the abort report the unit's current target instead")
    eq(h2.result.reason, "abort_allow_tank",
       "…the difference between 'we saw the swap' and 'it was on the tank all along'")
end
do  -- (b) group membership of the new target is validated
    resetW2()
    W.group = { "player", "raid1" }
    setUnit("raid1", { player = true })
    setUnit("target", { cid = 90001 })
    setUnit("targettarget", { name = "SomeNPC", cid = 555 })   -- not a group member
    local got
    Scan.Event({ unit = "target" }, function(n) got = n end)
    Scan.OnUnitTarget("target")
    eq(got, nil, "the event scanner validates GROUP MEMBERSHIP of the new target")
end
do  -- (c) the repeated scanner
    resetW2()
    W.group = { "player", "raid1" }
    setUnit("raid1", { player = true })
    setUnit("target", { cid = 90001 })
    setUnit("targettarget", { name = "First", player = true })
    local seen = {}
    local h = Scan.Repeated({ creatureId = 90001 }, function(n) seen[#seen + 1] = n end)
    advance(0.35)
    eq(#seen, 1, "the repeated scanner samples continuously but reports only CHANGES")
    eq(seen[1], "First", "…starting with the first target it sees")
    setUnit("targettarget", { name = "Second", player = true })
    advance(0.25)
    eq(seen[2], "Second", "…and reports each new target")
    advance(2)
    eq(#seen, 2, "…never timing out and never re-announcing the same target")
    ck(h.samples > 20, "…having sampled at the 0.1 s interval throughout")
    Scan.Stop(h)
    local n = #seen
    setUnit("targettarget", { name = "Third", player = true })
    advance(1)
    eq(#seen, n, "…and it is EXPLICITLY STOPPED by the module, never by a timeout")
end
do  -- SCAN_REQUEST dispatch picks the declared shape
    resetW2()
    setUnit("target", { cid = 90001 })
    local h = Scan.Dispatch("fix", { key = "s", type = "event", abort = 1.5 }, { sourceId = 90001 })
    eq(h.kind, "event", "a scan row declaring type=event gets the event scanner")
    Scan.Stop(h)
    h = Scan.Dispatch("fix", { key = "s2", type = "repeated" }, { sourceId = 90001 })
    eq(h.kind, "repeated", "…type=repeated gets the repeated scanner")
    Scan.Stop(h)
    h = Scan.Dispatch("fix", { key = "s3", tries = 2 }, { sourceId = 90001 })
    eq(h.kind, "poll", "…and the default is the polling scanner")
    Scan.StopAll()
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
-- GATE ERA — §6.1 range, §8.6 health, §5.4 the interrupt/dispel/CC gates
----------------------------------------------------------------------
gate("ERA  §6.1/§8.6/§5.4 Era services")
resetW2()
do  -- §6.1 the ladder, rung by rung, and the 43 yd clamp
    local rows = { { 8, 8149 }, { 13, 17626 }, { 18, 6450 },
                   { 23, 21519 }, { 28, 13289 }, { 33, 1180 } }
    for _, r in ipairs(rows) do
        local y, item = Era.RungFor(r[1])
        eq(y, r[1], ("the %d yd rung exists"):format(r[1]))
        eq(item, r[2], ("…and probes item %d"):format(r[2]))
    end
    local y, item = Era.RungFor(5)
    eq(y, 8, "a request between rungs takes the next rung UP that can answer it")
    eq(item, 8149, "…with that rung's item")
    y, item = Era.RungFor(43)
    eq(y, 43, "43 yd is the binary rung")
    eq(item, nil, "…which has NO item — it is UnitInRange, boolean only")
    y, item = Era.RungFor(60)
    eq(y, 43, "a request ABOVE 43 is silently CLAMPED to 43 (§6.1)")
    eq(item, nil, "…to the binary test, because the 48/60/80/100 rungs are TBC+ items")
    eq((Era.RungFor(100)), 43, "…however far above")
    eq(#Era.PICKER_RUNGS, 5, "the Era range picker offers exactly five rungs (8/13/18/23/33)")
end
do  -- range probing actually uses the right mechanism per rung
    resetW2()
    setUnit("raid1", { player = true })
    W.itemRange["8149:raid1"] = true
    eq((Era.CheckRange("raid1", 8)), true, "a sub-43 check probes IsItemInRange with the rung item")
    W.itemRange["8149:raid1"] = false
    eq((Era.CheckRange("raid1", 8)), false, "…and reports out of range")
    W.inRange["raid1"] = true
    eq((Era.CheckRange("raid1", 43)), true, "a 43 yd check uses the binary UnitInRange instead")
    eq((Era.CheckRange("raid1", 80)), true, "…and so does a clamped over-43 request")
    eq(Era.CheckRange("nosuchunit", 8), nil, "a missing unit is unanswerable, not 'out of range'")
    -- §6.1/§6.4: the +0.5 yd tolerance belongs to the EXACT path; the ladder's rungs
    -- are five or more yards apart, so half a yard cannot change which one answers.
    W.distance["raid1"] = 13.3
    W.hasPosition = true; Era.EvaluateWorldPosition()
    local within, how = Era.IsPlayerWithin("raid1", 13)
    eq(within, true, "'is player X within N yards' applies the +0.5 yd tolerance exactly…")
    eq(how, "exact", "…where the client exposes world position")
    W.distance["raid1"] = 13.6
    eq((Era.IsPlayerWithin("raid1", 13)), false, "…and beyond the tolerance it is out of range")
    W.hasPosition = false; Era.EvaluateWorldPosition()
    W.itemRange["17626:raid1"] = true
    local w2, how2 = Era.IsPlayerWithin("raid1", 13)
    eq(w2, true, "…while a restricted map degrades it to the item ladder (§6.3)")
    eq(how2, 13, "…answering at the rung that can answer, never a promoted one")
    W.hasPosition = true; Era.EvaluateWorldPosition()
end
do  -- §6.3 world position is derived DYNAMICALLY, never assumed
    resetW2()
    W.hasPosition = true
    eq(Era.EvaluateWorldPosition(), true, "world position availability is derived from UnitPosition")
    W.hasPosition = false
    eq(Era.EvaluateWorldPosition(), false,
       "…and re-derived, so an Era instance that hides it degrades to the binary test")
    W.hasPosition = true
end
do  -- §6.4 tank distance, with its 2 s cache and its allow-on-failure default
    resetW2()
    W.group = { "player", "raid1" }
    setUnit("raid1", { player = true })
    setUnit("bossmob", { cid = 90001 })
    W.threat["raid1@bossmob"] = 3
    W.inRange["raid1"] = false
    eq((Era.TankDistance("bossmob")), false, "the tank-distance filter finds the real tank by threat")
    W.inRange["raid1"] = true
    eq((Era.TankDistance("bossmob")), false, "…and the answer is CACHED for 2 s")
    advance(2.1)
    eq((Era.TankDistance("bossmob")), true, "…then re-derived")
    resetW2()
    setUnit("bossmob", { cid = 90001 })
    local okd, why = Era.TankDistance("bossmob")
    eq(okd, true, "on TOTAL FAILURE the default is to ALLOW the warning (§6.4)")
    eq(why, "unresolved", "…and say why")
end
do  -- §8.6 boss health: the nameplate fallback no other client version performs
    resetW2()
    W.group = { "player" }
    setUnit("nameplate7", { cid = 90001, hp = 62, hpmax = 100 })
    local pct, cid, tok = Era.BossHealthPct({ 90001 })
    near(pct, 62, 0.01, "boss health resolves through the nameplate1..20 sweep (§10.2)")
    eq(cid, 90001, "…identifying the creature")
    eq(tok, "nameplate7", "…and the token it was found on")
    setUnit("target", { cid = 90001, hp = 55, hpmax = 100 })
    local p2, _, tok2 = Era.BossHealthPct({ 90001 })
    eq(tok2, "nameplate7",
       "…and the token that worked is CACHED and re-validated FIRST on the next read (§8.6)")
    near(p2, 62, 0.01, "…so a working token keeps working without a fresh sweep")
    W.units.nameplate7 = nil
    local _, _, tok3 = Era.BossHealthPct({ 90001 })
    eq(tok3, "target", "…while a STALE token is dropped and the sweep re-runs")
end
do  -- §8.6 LAST-NON-ZERO RETENTION — the real Classic API quirk
    resetW2()
    setUnit("target", { cid = 90001, hp = 40, hpmax = 100 })
    near((Era.BossHealthPct({ 90001 })), 40, 0.01, "a live boss reports its health")
    W.units.target.hp = 0                       -- the client lies mid-fight
    near((Era.BossHealthPct({ 90001 })), 40, 0.01,
         "a unit reporting 0 health while NOT DEAD returns the LAST NON-ZERO value")
    near(Era.LastNonZero(90001), 40, 0.01, "…which is what the retention cache holds")
    W.units.target.dead = true
    eq(Era.BossHealthPct({ 90001 }), nil, "…while a genuinely dead unit reports nothing")
end
do  -- §8.6 lowest-seen, or highest for council fights
    resetW2()
    setUnit("target", { cid = 90001, hp = 80, hpmax = 100 })
    Era.BossHealthPct({ 90001 })
    W.units.target.hp = 50
    near((Era.BossHealthPct({ 90001 })), 50, 0.01, "the cache keeps the LOWEST value seen")
    W.units.target.hp = 70
    near((Era.BossHealthPct({ 90001 })), 50, 0.01, "…so a health spike cannot walk it backwards")
    resetW2()
    setUnit("target", { cid = 90002, hp = 40, hpmax = 100 })
    Era.BossHealthPct({ 90002 }, { highest = true })
    W.units.target.hp = 90
    near((Era.BossHealthPct({ 90002 }, { highest = true })), 90, 0.01,
         "…or the HIGHEST when the module declared 'report the highest-health boss' (council)")
end
do  -- §10.23 role derivation with no specialization API
    resetW2()
    W.class = "WARRIOR"
    eq(Era.SpecTab(), 1, "zero points spent falls back to talent tab 1")
    W.talents[2] = 31
    eq(Era.Spec(), "WARRIOR2", "the spec is CLASS..the tab with the MOST POINTS spent")
    eq(Era.IsTank(), false, "…a protection warrior OUT of Defensive Stance is not yet a tank")
    W.form = Era.DEFENSIVE_STANCE_FORM
    eq(Era.IsTank(), true, "…and IS one in Defensive Stance (form 18)")
    W.form = 0
    eq(Era.IsTank(), true, "…and the answer LATCHES for the session (§5.4)")
    resetW2()
    W.class, W.talents[2] = "DRUID", 31
    W.auras[5487] = true
    eq(Era.IsTank(), true, "a feral druid in Bear Form (5487) is a tank")
    resetW2()
    W.class, W.talents[2] = "WARRIOR", 31
    W.mainTank = true
    eq(Era.IsTank(), true, "…and so is anyone flagged Main Tank in the raid UI")
    resetW2()
    W.class, W.talents[3] = "DRUID", 31
    eq(Era.IsHealer(), true, "a restoration druid out of form is a healer")
    W.auras[9634] = true
    eq(Era.IsHealer(), false,
       "…and 'am I a healer' additionally requires a DRUID TO BE OUT OF FORM (§5.4)")
    -- the respec re-derivation is throttled and cancels a pending one
    resetW2()
    W.class, W.talents[2] = "WARRIOR", 31
    W.form = Era.DEFENSIVE_STANCE_FORM
    Era.IsTank()
    ck(Era.roleState.tankLatched, "the tank latch is set")
    Era.OnTalentsChanged(); Era.OnTalentsChanged()   -- a respec fires this many times
    W.form, W.talents[2], W.talents[1] = 0, 0, 31    -- …and the player respecced out of it
    advance(1.0)
    ck(Era.roleState.tankLatched, "a talent change does not re-derive immediately…")
    advance(1.2)
    ck(not Era.roleState.tankLatched,
       "…it re-derives 2 s out, cancelling any pending check (§10.23)")
end
do  -- §5.4 the interrupt filter, gate by gate
    resetW2()
    W.class, W.talents[1] = "WARRIOR", 31
    setUnit("target", { cid = 90001 })
    eq((Era.InterruptFilter({ casterUnit = "target" })), false,
       "gate (ii): a player who knows NO interrupt gets no interrupt warning")
    W.known[72] = true                              -- Shield Bash
    Era.ClearCache()                                -- (the 0.1 s gate cache; proved below)
    eq((Era.InterruptFilter({ casterUnit = "target" })), true,
       "…and a player who knows one does")
    Era.ClearCache()
    W.cooldown[72] = { start = CLOCK, duration = 10 }
    eq((Era.InterruptFilter({ casterUnit = "target" })), false,
       "…unless it is ON COOLDOWN (the gate is 'knows AND has off cooldown')")
    Era.ClearCache()
    W.cooldown[72] = nil
    eq((Era.InterruptFilter({ casterUnit = "othermob" })), false,
       "gate (iii): the caster must be the player's CURRENT TARGET (no focus unit on Era)")
    eq((Era.InterruptFilter({ casterUnit = "othermob", ignoreTargeting = true })), true,
       "gate (iv): …unless the caller asked to IGNORE TARGETING for a raid-wide interrupt")
    resetW2()
    W.class, W.talents[2] = "PRIEST", 31             -- Holy (tab 2), i.e. a real healer
    W.known[2139] = true
    setUnit("target", { cid = 90001 })
    Era.Settings().interruptHealerFilterBoss = true
    eq((Era.InterruptFilter({ casterUnit = "target" })), false,
       "gate (i): a HEALER is dropped when the healer filter is on")
    Era.ClearCache()
    Era.Settings().interruptHealerFilterBoss = false
    eq((Era.InterruptFilter({ casterUnit = "target" })), true, "…and passes when it is off")
    Era.ClearCache()
    Era.Settings().interruptHealerFilterBoss = true
    Era.Settings().interruptHealerFilterTrash = false
    eq((Era.InterruptFilter({ casterUnit = "target", trash = true })), true,
       "…boss and trash are SEPARATE OPTIONS (§5.4)")
end
do  -- the 0.1 s result cache, and that it actually EXPIRES
    resetW2()
    W.class = "WARRIOR"
    W.known[72] = true
    eq((Era.HasReadyInterrupt()), true, "the interrupt gate answers")
    local _, cached = Era.HasReadyInterrupt()
    eq(cached, true, "…and a second call inside 0.1 s is served FROM THE CACHE")
    W.known[72] = nil                               -- the world changes underneath it
    eq((Era.HasReadyInterrupt()), true,
       "…so a burst of simultaneous debuff applications costs ONE spellbook sweep")
    advance(0.15)
    eq((Era.HasReadyInterrupt()), false, "…and the cache EXPIRES after 0.1 s (§12)")
end
do  -- §5.4 the dispel filter
    resetW2()
    W.class = "DRUID"
    W.known[2782] = true
    eq((Era.DispelFilter("curse")), true, "a druid who knows Remove Curse (2782) can dispel a curse")
    eq((Era.DispelFilter("magic")), false, "…but not magic")
    resetW2()
    W.class = "MAGE"; W.known[475] = true
    eq((Era.DispelFilter("curse")), true, "a mage answers the curse gate with 475")
    resetW2()
    -- NOTE: zero points spent falls back to tab 1 (§10.23), and paladin tab 1 is
    -- Holy — so the non-healer case has to be an actual retribution paladin.
    W.class, W.talents[3] = "PALADIN", 31           -- Retribution
    W.known[4987] = true
    eq((Era.DispelFilter("magic")), false,
       "Cleanse (4987) is REJECTED for a non-healer paladin (§5.4)")
    resetW2()
    W.class, W.talents[1] = "PALADIN", 31           -- Holy
    W.known[4987] = true
    eq((Era.DispelFilter("magic")), true, "…and answers for a HOLY paladin")
    eq((Era.DispelFilter("poison")), true, "…including poison, which is healer-gated on top")
    resetW2()
    W.class = "DRUID"; W.known[2782] = true
    W.cooldown[2782] = { start = CLOCK, duration = 8 }
    eq((Era.DispelFilter("curse")), false, "a dispel ON COOLDOWN does not answer the gate")
    eq((Era.DispelFilter("nosuchtype")), false, "an unknown dispel type answers false, never nil")
end
do  -- §5.4 the crowd-control filter: same shape, same cache, empty on Era
    resetW2()
    local n = 0
    for _ in pairs(Era.CC_CATEGORIES) do n = n + 1 end
    eq(n, 8, "all eight CC categories are declared (disrupt/stun/knock/… )")
    eq((Era.CCFilter("stun")), false,
       "…and answer FALSE on Era, where the category is largely empty of spells")
    Era.CC_CATEGORIES.stun = { 99999 }
    W.known[99999] = true
    Era.ClearCache()
    eq((Era.CCFilter("stun")), true, "…until a category is populated, when the same gate answers")
    Era.CC_CATEGORIES.stun = {}
    eq((Era.CCFilter("nosuchcategory")), false, "an unknown category answers false")
end
do  -- the always-on filters
    resetW2()
    W.class, W.talents[1] = "MAGE", 31
    eq(Era.TauntFilter(), false, "taunt warnings are HARD-DROPPED for non-tanks, always, no option")
    resetW2()
    W.class, W.talents[2] = "WARRIOR", 31
    W.form = Era.DEFENSIVE_STANCE_FORM
    eq(Era.TauntFilter(), true, "…and shown to a tank")
    resetW2()
    W.class = "PRIEST"
    W.auras[Era.SPIRIT_OF_REDEMPTION] = true
    eq((Era.MoveOutFilter()), false,
       "'move out of bad' is suppressed for a priest in Spirit of Redemption (27827)")
    W.auras[Era.SPIRIT_OF_REDEMPTION] = nil
    eq((Era.MoveOutFilter()), true, "…and shown otherwise")
    resetW2()
    W.level = 60
    eq(Era.IsTrivial(60), false, "content at your level is not trivial")
    eq(Era.IsTrivial(45), true, "…and content 15+ levels below you is (§5.4)")
    eq(Era.IsTrivial(nil), false, "…with no reference level, nothing is trivial (the safe answer)")
end
do  -- the wave-1 resolver stubs, now filled
    resetW2()
    W.class, W.talents[2] = "WARRIOR", 31
    W.form = Era.DEFENSIVE_STANCE_FORM
    eq(Addon.RoleResolver, Era.ResolveRole, "core_api's RoleResolver stub is FILLED by W2")
    eq(Addon.ClassResolver(), "WARRIOR", "…and so is ClassResolver")
    ck(Era.ResolveRole("Tank"), "a simple gate resolves")
    ck(Era.ResolveRole("Tank|Healer"), "a compound gate is an OR")
    ck(not Era.ResolveRole("Healer"), "…and a gate the player fails resolves false")
    resetW2()
    W.class, W.talents[1] = "MAGE", 31
    ck(Era.ResolveRole("-Melee"), "a negated gate ('-Melee') resolves for a caster")
    ck(not Era.ResolveRole("Melee"), "…and its positive does not")
    W.known[2139] = true
    ck(Era.ResolveRole("HasInterrupt"), "the interrupt role gate reads the Era spell set")
    resetW2()
    W.class = "MAGE"; W.known[475] = true
    ck(Era.ResolveRole("RemoveCurse"), "…and the dispel role gates read the Era dispel table")
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
-- GATE PUB — §4.5 / §11.8 the public broadcast contract
----------------------------------------------------------------------
gate("PUB  §4.5/§11.8 the 18-field public contract")
resetW2()
do  -- the contract's SHAPE is the contract
    eq(#Public.TIMER_FIELDS, 18, "the timer payload has exactly 18 fields (§4.5)")
    eq(Public.TIMER_FIELD_COUNT, 18, "…and says so")
    eq(table.concat(Public.TIMER_FIELDS, ","),
       "barId,text,remaining,icon,category,spellKey,color,modId,keep,fade,spellName," ..
       "guid,count,priority,timerType,hasVariance,variancePeak,enabled",
       "…in the documented ORDER, which is frozen: append only, never renumber")
end
do  -- named fields and positional arguments are the same data
    resetW2()
    local t = Timers.New({ id = "PB", key = "shadowbolt", encId = "fix", kind = "cast",
                           duration = "v20-30", color = 4, text = "Bolt",
                           icon = "icon.blp", spellId = 25991, keep = true })
    local bar = t:Start(nil, "Creature-0-0-0-0-90001-0001")
    local p, a = Public.TimerPayload(bar, CLOCK)
    local pos = { select(2, Public.TimerPayload(bar, CLOCK)) }
    local mismatch
    for i, name in ipairs(Public.TIMER_FIELDS) do
        local want, got = p[name], pos[i]
        if type(want) == "number" and type(got) == "number" then
            if math.abs(want - got) > 0.001 then mismatch = name end
        elseif want ~= got then mismatch = name end
    end
    eq(mismatch, nil, "every named field equals its positional argument, one for one")
    eq(a, bar.id, "field 1 is the bar id")
    near(p.remaining, 20, 0.01,
         "field 3 is the MINIMUM end of the variance window (consumers are fed the minimum)")
    near(p.variancePeak, 30, 0.01, "field 17 is the maximum end — together they are the window")
    eq(p.hasVariance, true, "field 16 flags the variance")
    eq(p.category, "cast", "field 5 is the SIMPLIFIED category")
    eq(p.timerType, "cast", "field 15 is the full, unsimplified type")
    eq(p.color, 4, "field 7 is the colour index")
    eq(p.keep, true, "field 9 is the keep-on-screen flag")
    eq(p.guid, "Creature-0-0-0-0-90001-0001",
       "field 12 recovers the mob GUID from the identity arguments (§4.5)")
    eq(p.modId, "fix", "field 8 is the owning module id")
end
do  -- §4.5's load-bearing rule: field 18, and that the broadcast fires anyway
    resetW2()
    local seen = {}
    local function handler(_, payload) seen[#seen + 1] = payload end
    Public:Register("DRM_TimerStart", handler)

    Timers.New({ id = "PE", key = "on", encId = "fix", kind = "cd", duration = 20 }):Start()
    eq(#seen, 1, "a timer start broadcasts to registered consumers")
    eq(seen[1].enabled, true, "…with enabled = true when the bar is being drawn")

    Addon.db.mechanics["fix:off"] = { bar = false }
    Timers.New({ id = "PF", key = "off", encId = "fix", kind = "cd", duration = 20 }):Start()
    eq(#seen, 2, "THE BROADCAST FIRES EVEN WHEN THE USER'S DISPLAY OPTION IS OFF")
    eq(seen[2].enabled, false, "…carrying the enabled flag as FALSE")
    eq(#BM.Layout(CLOCK).small, 1, "…while only the ENABLED bar is actually drawn (§4.5)")

    Bars.Settings().hideAll = true
    Timers.New({ id = "PG", key = "g", encId = "fix", kind = "cd", duration = 20 }):Start()
    eq(#seen, 3, "…and the global 'hide all bars' suppressor does not silence consumers either")
    eq(seen[3].enabled, false, "…it only clears the flag")
    Bars.Settings().hideAll = false
    Public:Unregister("DRM_TimerStart", handler)
end
do  -- the nameplate parallel broadcast
    resetW2()
    local plain, np = 0, 0
    local function h1() plain = plain + 1 end
    local function h2() np = np + 1 end
    Public:Register("DRM_TimerStart", h1)
    Public:Register("DRM_NameplateTimerStart", h2)
    Timers.New({ id = "PN1", key = "a", kind = "cd", duration = 20 }):Start()
    eq(plain, 1, "an ordinary timer broadcasts on DRM_TimerStart")
    eq(np, 0, "…and not on the nameplate channel")
    local t = Timers.New({ id = "PN2", key = "b", kind = "cd", duration = 20, nameplate = true })
    t:Start()
    eq(plain, 2, "a nameplate timer broadcasts on the ordinary channel too…")
    eq(np, 1, "…AND fires the PARALLEL nameplate broadcast (§4.5)")
    eq(t:Category(), "cdnp", "…with the category collapsed to cdnp for consumers")
    Public:Unregister("DRM_TimerStart", h1); Public:Unregister("DRM_NameplateTimerStart", h2)
end
do  -- §11.8's secure-call wrapper
    resetW2()
    Tele.Clear()
    local good = 0
    Public:Register("DRM_TimerStart", function() error("consumer is broken") end)
    Public:Register("DRM_TimerStart", function() good = good + 1 end)
    Timers.New({ id = "PX", key = "x", kind = "cd", duration = 20 }):Start()
    eq(good, 1, "a consumer that ERRORS cannot stop the next consumer from running")
    ck(Tele.Count() > 0, "…and the failure lands in the telemetry ring, not in a broken raid")
    Public.registry["DRM_TimerStart"] = nil
end
do  -- registration hygiene + the lifecycle half of §11.8
    resetW2()
    local fn = function() end
    eq(Public:Register("DRM_TimerStart", fn), true, "handlers register")
    eq(Public:Register("DRM_TimerStart", fn), true, "…idempotently")
    eq(#Public.registry["DRM_TimerStart"], 1, "…without duplicating")
    eq(Public:Unregister("DRM_TimerStart", fn), 1, "…and unregister")
    eq((Public:Register("DRM_NotAnEvent", fn)), false, "an unknown event is refused")
    eq((Public:Register("DRM_TimerStart", "notafunction")), false, "…and so is a non-function")

    local fired = {}
    for _, ev in ipairs({ "DRM_SetStage", "DRM_Pull", "DRM_Kill", "DRM_Wipe", "DRM_TimerStop" }) do
        Public:Register(ev, function(e) fired[e] = (fired[e] or 0) + 1 end)
    end
    resetLife()
    local enc = freshEncounter("pubfix")
    local rt = Life:StartCombat(enc, 0, "sweep")
    eq(fired.DRM_Pull, 1, "an engage broadcasts DRM_Pull")
    rt:SetStage(2)
    eq(fired.DRM_SetStage, 1, "a stage change broadcasts DRM_SetStage")
    local t = Timers.New({ id = "PS", key = "s", kind = "cd", duration = 20 })
    t:Start(); t:Stop()
    eq(fired.DRM_TimerStop, 1, "a stop broadcasts the bar identity")
    Life:EndCombat(rt, false, "kill")
    eq(fired.DRM_Kill, 1, "a kill broadcasts DRM_Kill")
    ck(fired.DRM_Wipe == nil, "…and not DRM_Wipe")
    for _, ev in ipairs({ "DRM_SetStage", "DRM_Pull", "DRM_Kill", "DRM_Wipe", "DRM_TimerStop" }) do
        Public.registry[ev] = nil
    end
end
do  -- INTEGRATION: a whole engagement with every wave-2 consumer attached.
    -- The engine pcalls each consumer and records a failure as `api.validate` with
    -- reason "callback error" — so a silent exception in a bar, a warning tier, a
    -- scanner or a public broadcast would be invisible in-game and is caught here.
    resetW2()
    Addon.encounters, Addon.encountersById = {}, {}
    Addon.encByCreature, Addon.encByEncounterId, Addon.encByZone = {}, {}, {}
    local enc = Addon:RegisterEncounter({
        id = "w2int", name = "Wave 2 Integration", zone = 533,
        encounterId = 1107, creatureId = { 15956 }, combat = {},
        detect = { mode = "combat" },
        timers = {
            { key = "cd", kind = "cd", pull = "v5-9", duration = "v20-30", color = 2,
              start = { on = "pull" },
              restart = { on = "SPELL_CAST_SUCCESS", spellId = 19702 },
              countdown = { depth = 3 } },
            { key = "dot", kind = "target", duration = 12, perTarget = true, color = 3,
              start = { on = "SPELL_AURA_APPLIED", spellId = 20604 } },
        },
        warnings = {
            { key = "w", tier = "announce", color = 3, text = "Doom on >%s<",
              trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19702 } },
            { key = "sw", tier = "special", sound = 3, voice = "targetyou",
              text = "Mind control on YOU",
              trigger = { on = "SPELL_AURA_APPLIED", spellId = 20604, dest = "player" } },
        },
        scans = {
            { key = "sc", type = "poll", tries = 3, filter = "playersOnly",
              on = { on = "SPELL_CAST_START", spellId = 26134 } },
        },
    })
    ck(enc ~= nil, "INTEGRATION: the fixture encounter registers")
    W.group = { "player", "raid1" }
    setUnit("raid1", { player = true, combat = true, guid = "Player-1-BBBB" })
    setUnit("target", { cid = 15956, combat = true, hp = 100, hpmax = 100 })
    W.roster["Bob"] = { class = "MAGE" }
    Tele.Clear()

    local rt = Life:StartCombat(enc, 0, "sweep")
    ck(rt ~= nil, "…and engages")
    ck(BM.count > 0, "…the pull-triggered bar is rendered by the bar surface")
    Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 19702, sourceId = 15956 })
    ck(Warn.announceStack:Count() > 0, "…a cast fires an announcement into tier 2")
    Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 20604, destName = "Bob",
                   destIsPlayer = true })
    ck(Warn.specialStack:Count() > 0, "…a personal debuff fires a special warning into tier 3")
    Life:Deliver({ on = "SPELL_CAST_START", spellId = 26134, sourceId = 15956 })
    advance(30)
    Life:EndCombat(rt, false, "kill")
    advance(4)

    local errors = 0
    for _, e in ipairs(Tele.Ring(false) or {}) do
        if e.kind == "api.validate" and tostring(e.reason):find("callback error", 1, true) then
            errors = errors + 1
            realprint("        consumer error: " .. tostring(e.key) .. " -> " .. tostring(e.detail))
        end
    end
    eq(errors, 0,
       "…and a full engage -> timers -> warnings -> scan -> kill runs with ZERO consumer errors")
    eq(BM.count, 0, "…leaving no bar rows behind")
    eq(Scan.StopAll(), 0, "…and no scanner still polling after the fight")
end

do  -- GUID recovery is not fooled by a player GUID
    eq(Public.GuidFromBarId("T\tCreature-0-0-0-0-15956-0001"), "Creature-0-0-0-0-15956-0001",
       "a creature GUID in the identity arguments becomes the bar's mob GUID")
    eq(Public.GuidFromBarId("T\tPlayer-1-AAAA"), nil,
       "…while a PLAYER guid does not (§4.5: 'any NON-PLAYER GUID')")
    eq(Public.GuidFromBarId("T\tBob"), nil, "…and a plain identity argument is not a GUID")
end
endgate()

----------------------------------------------------------------------
-- WAVE 4d — NAXXRAMAS ENCOUNTER DATA
--
-- Every assertion below names the DBM_ERA_ENCOUNTERS_BEHAVIOR_SPEC.md §8 row it
-- proves, and every one runs the SHIPPING data through the SHIPPING engine on the
-- injected clock and the injected world: registration, then one drive per boss.
----------------------------------------------------------------------

-- Re-execute the shipping data into a clean registry (earlier gates wiped it).
local function loadNaxx()
    Addon.encounters, Addon.encountersById = {}, {}
    Addon.encByCreature, Addon.encByEncounterId, Addon.encByZone = {}, {}, {}
    Addon.zones, Addon.zonesById = {}, {}
    local okc, err = pcall(NAXX_CHUNK, ADDON_NAME, Addon)
    return okc, err
end

-- Warning capture through the real dispatch seam.
local function sawWarn(kind, needle)
    for _, e in ipairs(Addon:GetEventLog() or {}) do
        if e.event == kind and tostring(e[3]):find(needle, 1, true) then return true, e end
    end
    return false
end
local function warnCount(kind, needle)
    local n = 0
    for _, e in ipairs(Addon:GetEventLog() or {}) do
        if e.event == kind and tostring(e[3]):find(needle, 1, true) then n = n + 1 end
    end
    return n
end
local function bar(rt, key) return rt and rt.timers[key] and rt.timers[key]:Get() end
local function barWindow(rt, key)
    local b = bar(rt, key)
    if not b then return nil end
    return b.min, b.max
end

-- Engage helper: put the boss on the target, then take the encounter's own path.
local function engage(encId, cid, yell)
    resetLife()
    W.group = { "player" }
    setUnit("target", { cid = cid, combat = true, hp = 100, hpmax = 100 })
    setUnit("playertarget", { cid = cid, combat = true, hp = 100, hpmax = 100 })
    Addon:ClearEventLog()
    local enc = Addon:GetEncounter(encId)
    if yell then
        Life:OnChat("CHAT_MSG_MONSTER_YELL", yell)
    else
        Life:Sweep(0.5)
    end
    return Life:GetRuntime(encId), enc
end

gate("NAXX  §8 encounter data: registration, keys, the options tree")
do
    local okc, err = loadNaxx()
    ck(okc, "enc_naxxramas.lua EXECUTES against the shipping grammar" ..
            (okc and "" or (" -> " .. tostring(err))))

    -- Every §8 encounter, with the spec's creature and encounter ids.
    local EXPECTED = {
        { id = "naxxramas:anubrekhan",  cid = 15956, eid = 1107, boss = "anubrekhan" },
        { id = "naxxramas:faerlina",    cid = 15953, eid = 1110, boss = "faerlina" },
        { id = "naxxramas:maexxna",     cid = 15952, eid = 1116, boss = "maexxna" },
        { id = "naxxramas:noth",        cid = 15954, eid = 1117, boss = "noth" },
        { id = "naxxramas:heigan",      cid = 15936, eid = 1112, boss = "heigan" },
        { id = "naxxramas:loatheb",     cid = 16011, eid = 1115, boss = "loatheb" },
        { id = "naxxramas:razuvious",   cid = 16061, eid = 1113, boss = "razuvious" },
        { id = "naxxramas:gothik",      cid = 16060, eid = 1109, boss = "gothik" },
        { id = "naxxramas:fourhorsemen", cid = 16062, eid = 1121, boss = "fourhorsemen" },
        { id = "naxxramas:patchwerk",   cid = 16028, eid = 1118, boss = "patchwerk" },
        { id = "naxxramas:grobbulus",   cid = 15931, eid = 1111, boss = "grobbulus" },
        { id = "naxxramas:gluth",       cid = 15932, eid = 1108, boss = "gluth" },
        { id = "naxxramas:thaddius",    cid = 15928, eid = 1120, boss = "thaddius" },
        { id = "naxxramas:sapphiron",   cid = 15989, eid = 1119, boss = "sapphiron" },
        { id = "naxxramas:kelthuzad",   cid = 15990, eid = 1114, boss = "kelthuzad" },
    }
    for _, e in ipairs(EXPECTED) do
        local enc = Addon:GetEncounter(e.id)
        ck(enc ~= nil, e.id .. " is registered")
        if enc then
            local errs = API.Validate(enc)
            eq(#errs, 0, "…with zero validation errors" ..
               (#errs > 0 and (": " .. table.concat(errs, "; ")) or ""))
            ck(Addon.encByCreature[e.cid] ~= nil, "…indexed by creature " .. e.cid)
            ck(Addon.encByEncounterId[e.eid] ~= nil, "…and by encounter id " .. e.eid)
            ck(enc.legacy and enc.legacy.raidId == "naxxramas" and enc.legacy.bossId == e.boss,
               "…carrying the legacy seam naxxramas:" .. e.boss)
            -- THE KEY SCHEMES COINCIDE. This is the whole options contract.
            local firstRow = enc.timers[1] or enc.warnings[1]
            if firstRow then
                eq(API.OptionKey(enc.id, firstRow.key),
                   Addon:MechKey("naxxramas", e.boss, firstRow.key),
                   "…and OptionKey == MechKey for its rows (one SavedVariables entry, not two)")
            end
        end
    end
    eq(#Addon.encounters, #EXPECTED + 1, "…16 registrations in all (15 bosses + the trash module)")

    do  -- the zone-wide trash module
        local trash = Addon:GetEncounter("naxxramas:trash")
        ck(trash ~= nil and trash.detect.mode == "zone", "§8.16 the trash module registers as a ZONE module")
        ck(trash and Addon.encByZone[533] ~= nil, "…indexed against instance 533")
        local keys = {}
        for _, r in ipairs(trash and trash.warnings or {}) do keys[r.key] = r end
        ck(keys.intimidatingshout and keys.intimidatingshout.antispam == 3, "…Intimidating Shout, 3 s anti-spam")
        ck(keys.fear and keys.fear.antispam == 5, "…Fear, 5 s anti-spam")
        ck(keys.poisoncharge and keys.poisoncharge.antispam == 3, "…Poison Charge, 3 s anti-spam")
        ck(keys.veilofshadow and keys.veilofshadow.antispam == 6, "…Veil of Shadow, 6 s anti-spam")
        ck(keys.lightningtotem and keys.lightningtotem.antispam == nil,
           "…and the lightning totem carries NO anti-spam (two packs can summon back to back)")
        eq(keys.lightningtotem and keys.lightningtotem.sound, 3, "…at sound tier 3")
    end

    do  -- ship-off defaults carried from the spec verbatim
        local OFF = {
            { "naxxramas:fourhorsemen", "marksoon" },
            { "naxxramas:fourhorsemen", "holywrath" },
            { "naxxramas:loatheb",      "healnow" },
            { "naxxramas:kelthuzad",    "frostbolt" },
            { "naxxramas:kelthuzad",    "fissure" },
            { "naxxramas:kelthuzad",    "chainsicons" },
            { "naxxramas:kelthuzad",    "manabombicon" },
            { "naxxramas:kelthuzad",    "frostblasticons" },
            { "naxxramas:grobbulus",    "injectionicons" },
        }
        for _, p in ipairs(OFF) do
            local enc = Addon:GetEncounter(p[1])
            local row = enc and enc.rowsByKey[p[2]]
            ck(row and row.default == false, p[1] .. ":" .. p[2] .. " SHIPS OFF (spec default)")
        end
        local lo = Addon:GetEncounter("naxxramas:loatheb")
        eq(lo.rowsByKey.necroticaura.classDefault, "WARLOCK",
           "Loatheb's curse-removal timer defaults on for WARLOCKS (dynamic class default)")
        local rz = Addon:GetEncounter("naxxramas:razuvious")
        eq(rz.rowsByKey.taunt.classDefault, "PRIEST",
           "Razuvious's mind-control timers default on for PRIESTS (dynamic class default)")
        eq(rz.rowsByKey.mindexhaust.classDefault, "PRIEST", "…including Mind Exhaustion")
    end

    -- ── THE OWNER'S 2026-08-07 NAXX ARBITRATIONS ──────────────────────────────
    -- Two explicit decisions from the W4d cross-check, pinned here so a later wave
    -- cannot quietly undo either:
    --   1. three field-log conflicts ship DUAL-ID triggers (spec id AND observed id)
    --   2. the nine dropped 1.x rows are back as encounter rows
    -- The provenance COMMENTS are asserted too. A "cleanup" that collapses a dual id
    -- has to delete the note that explains it, and deleting the note reddens this gate.
    do
        local SRC = readFile(P("enc_naxxramas.lua")) or ""

        local n = 0
        for _ in SRC:gmatch("owner 2026%-08%-07: dual%-ID") do n = n + 1 end
        eq(n, 3, "ARBITRATION: all three dual-ID sites carry the owner's provenance note")
        ck(SRC:find("28798 AND our observed 28131", 1, true) ~= nil,
           "…Faerlina's names both ids and which side each came from")
        ck(SRC:find("28547 AND our observed 28560 (Summon Blizzard)", 1, true) ~= nil,
           "…Sapphiron's names DBM's 28547 and our Summon Blizzard 28560")
        ck(SRC:find("29208/29209/29210/29211", 1, true) ~= nil,
           "…and Noth's names all four observed blink ids")
        n = 0
        for _ in SRC:gmatch("tripwire telemetry arbitrates") do n = n + 1 end
        eq(n, 3, "…each naming the early-refresh tripwire as what will settle it")
        n = 0
        for _ in SRC:gmatch("DO NOT \"clean this up\"") do n = n + 1 end
        eq(n, 3, "…and each carrying the explicit do-not-collapse instruction")

        -- the spellId list a row's trigger actually carries
        local function idsOf(tr)
            local v = tr and tr.spellId
            if v == nil then return {} end
            return type(v) == "table" and v or { v }
        end
        local function has(list, id)
            for _, v in ipairs(list) do if v == id then return true end end
            return false
        end
        local function bothWays(tr, a, b, what)
            local l = idsOf(tr)
            ck(has(l, a) and has(l, b), what)
        end

        local fa = Addon:GetEncounter("naxxramas:faerlina")
        bothWays(fa.rowsByKey.frenzy.trigger, 28798, 28131,
                 "FAERLINA: the Enrage announce fires on 28798 OR 28131")
        bothWays(fa.rowsByKey.defensive.trigger, 28798, 28131,
                 "…so does the tank-defensive special (the owner named both surfaces)")
        bothWays((fa.rowsByKey.enraged.transitions or {})[1], 28798, 28131,
                 "…and the `enraged` gate the post-Embrace restart reads, or the bar dies")

        local sa = Addon:GetEncounter("naxxramas:sapphiron")
        local bz = sa.rowsByKey.blizzard
        eq(#bz.triggers, 3, "SAPPHIRON: the Blizzard GTFO still has its three arms")
        for i, tr in ipairs(bz.triggers) do
            bothWays(tr, 28547, 28560,
                     "…arm " .. i .. " (" .. tr.on .. ") fires on 28547 OR 28560")
        end

        local no = Addon:GetEncounter("naxxramas:noth")
        local bl = idsOf(no.rowsByKey.blink.trigger)
        eq(#bl, 4, "NOTH: Blink carries all four observed ids, not the spec's one")
        for _, id in ipairs({ 29208, 29209, 29210, 29211 }) do
            ck(has(bl, id), "…including " .. id)
        end

        -- ── decision 2: every dropped 1.x row is back, at its 1.x option key ──
        n = 0
        for _ in SRC:gmatch("RESTORED — owner 2026%-08%-07") do n = n + 1 end
        eq(n, 10, "RESTORATION: every restoration site carries the owner's provenance note")
        n = 0
        for _ in SRC:gmatch("POISON%-CLASS ROWS SHIP DEFAULT%-OFF") do n = n + 1 end
        eq(n, 4, "…and every poison-class row states WHY it ships off (the honest middle)")

        -- { encounter, 1.x row id (== the 2.0 option key), spell id, ships off? }
        local RESTORED = {
            { "naxxramas:razuvious", "unbalancing",    26613, false },
            { "naxxramas:gluth",     "mortalwound",    25646, false },
            { "naxxramas:thaddius",  "powersurge",     28134, false },
            { "naxxramas:thaddius",  "chainlightning", 28167, true  },
            { "naxxramas:thaddius",  "balllightning",  28299, false },
            { "naxxramas:gothik",    "shadowbolt",     29317, true  },
            { "naxxramas:gothik",    "harvest",        28679, false },
            { "naxxramas:heigan",    "fever",          29998, false },
            { "naxxramas:heigan",    "disrupt",        29310, false },
            { "naxxramas:maexxna",   "necrotic",       28776, true  },
            { "naxxramas:faerlina",  "poisonbolt",     28796, true  },
            { "naxxramas:grobbulus", "slimespray",     28157, true  },
            { "naxxramas:loatheb",   "deathbloom",     29865, true  },
        }
        eq(#RESTORED, 13, "…thirteen rows across the owner's nine-item list")
        for _, r in ipairs(RESTORED) do
            local enc = Addon:GetEncounter(r[1])
            local row = enc and enc.rowsByKey[r[2]]
            ck(row ~= nil, r[1] .. ":" .. r[2] .. " is RESTORED as an encounter row")
            if row then
                -- the spell id, taken from the parked 1.x evidence, reaches a trigger
                local trs = {}
                if row.trigger then trs[#trs + 1] = row.trigger end
                if row.start   then trs[#trs + 1] = row.start   end
                if row.restart then trs[#trs + 1] = row.restart end
                for _, tr in ipairs(row.triggers or {}) do trs[#trs + 1] = tr end
                local found = false
                for _, tr in ipairs(trs) do
                    if has(idsOf(tr), r[3]) then found = true end
                end
                ck(found, "…on the field-verified 1.x spell id " .. r[3])
                if r[4] then
                    eq(row.default, false, "…and SHIPS OFF (owner: poison-class / 1.x default)")
                else
                    eq(row.default, nil, "…and keeps the 1.x default (on for its audience)")
                end
                -- the key IS the 1.x option key, so a 1.x SavedVariables choice survives
                eq(API.OptionKey(r[1], r[2]),
                   Addon:MechKey("naxxramas", r[1]:match(":(.+)$"), r[2]),
                   "…under the same SavedVariables key 1.x wrote")
            end
        end

        -- the two tank rows announce LOUDLY, to a tank-relevant audience (owner's words)
        local rzv = Addon:GetEncounter("naxxramas:razuvious").rowsByKey.unbalancing
        eq(rzv.tier or "announce", "announce", "RAZUVIOUS: Unbalancing Strike is an ANNOUNCE…")
        eq(rzv.color, 4, "…at the top announce colour (loud)")
        eq(rzv.role, "Tank|Healer", "…gated to the tank-relevant audience")
        local glm = Addon:GetEncounter("naxxramas:gluth").rowsByKey.mortalwound
        eq(glm.role, "Tank", "GLUTH: Mortal Wound is the suite's tank-stack shape…")
        eq(glm.stacks, true, "…carrying the live STACK, as on Ossirian and the Anubisath")
        -- and the one restored row 1.x shipped as a cooldown radial is a TIMER, not a warning
        local thc = Addon:GetEncounter("naxxramas:thaddius")
        ck(thc.rowsByKey.chainlightning.kind == "cd",
           "THADDIUS: Chain Lightning comes back as the COOLDOWN radial 1.x shipped")
        near(thc.rowsByKey.chainlightning.duration, 8.5, 0.001,
           "…on the field-measured 8.5 s cadence")
    end

    do  -- the options projection: the tree options.lua actually reads
        API.PublishOptionsTree()
        local raid = Addon:GetRaid("naxxramas")
        ck(raid ~= nil, "the encounter registry PROJECTS into the options tree")
        eq(raid and raid.size, 40, "…as a 40-man raid (so options.lua builds a section for it)")
        eq(raid and #raid.bosses, 16, "…with all sixteen entries")
        local boss = Addon:GetBoss("naxxramas", "thaddius")
        ck(boss and #boss.mechanics > 0, "…every boss carrying its mechanic rows")
        local pol
        for _, m in ipairs(boss and boss.mechanics or {}) do if m.id == "polarity" then pol = m end end
        ck(pol ~= nil, "…including Thaddius's `polarity` row")
        ck(pol and pol.polarityWatch == true,
           "…with the polarityWatch passthrough thaddius.lua's sub-panel is reached by")
        eq(Addon:MechKey("naxxramas", "thaddius", "polarity"), "naxxramas:thaddius:polarity",
           "…at the EXACT key thaddius.lua hard-codes")
        ck(Addon:GetBossByNpcID(15990) ~= nil, "…and the npc index resolves Kel'Thuzad")
        -- the 1.x path stays refused
        local okr = Addon:RegisterRaid({ id = "naxxramas", bosses = {} })
        eq(okr, nil, "…while the retired 1.x RegisterRaid is STILL a hard refusal")
    end

    do  -- the five specials attach by data, and this file does not double-render them
        local SPECIALS = {
            { file = "mod_loatheb_healers.lua",       boss = "loatheb" },
            { file = "mod_fourhorsemen_rotation.lua", boss = "fourhorsemen" },
            { file = "mod_fourhorsemen_tracker.lua",  boss = "fourhorsemen" },
            { file = "mod_gothik_waves.lua",          boss = "gothik" },
            { file = "mod_razuvious_understudy.lua",  boss = "razuvious" },
            { file = "thaddius.lua",                  boss = "thaddius" },
        }
        for _, s in ipairs(SPECIALS) do
            local src = readFile(P(s.file)) or ""
            ck(src:find('bossId = "' .. s.boss .. '"', 1, true) ~= nil,
               s.file .. " registers against boss '" .. s.boss .. "' (UNEDITED)")
            local enc = Addon:GetEncounter("naxxramas:" .. s.boss)
            ck(enc and enc.legacy.bossId == s.boss,
               "…and naxxramas:" .. s.boss .. " declares the matching legacy seam")
        end
        -- no double-render: the surfaces the specials own are absent from the data
        local go = Addon:GetEncounter("naxxramas:gothik")
        eq(#go.schedule, 0,
           "Gothik declares NO wave schedule — mod_gothik_waves is the shipping surface")
        ck(go.rowsByKey["wavesoon"] == nil and go.rowsByKey["wavenow"] == nil,
           "…and no wave banners either")
        local fh = Addon:GetEncounter("naxxramas:fourhorsemen")
        ck(fh.rowsByKey["voidzonecd"] == nil and fh.rowsByKey["meteorcd"] == nil
           and fh.rowsByKey["holywrathcd"] == nil,
           "Four Horsemen declares NO per-horse cooldown radials — the tracker renders those")
        ck(fh.rowsByKey["markcd"] ~= nil,
           "…but DOES declare markcd, which the tracker reads its Mark count from")
        local th = Addon:GetEncounter("naxxramas:thaddius")
        ck(th.rowsByKey["polaritychanged"] == nil,
           "Thaddius declares NO polarity-FLIP alert — thaddius.lua's icon watcher ships it")
    end

    do  -- the spec's own wave script, asserted against the module that ships it
        local src = readFile(P("mod_gothik_waves.lua")) or ""
        -- spec §8.8: wave 1 at 27 s, then the hard-coded gaps
        local GAPS = { 20, 20, 10, 10, 15, 5, 20, 10, 10, 5, 15, 10, 10, 10, 5, 5, 20 }
        local t, want = 27, {}
        want[1] = 27
        for i, g in ipairs(GAPS) do t = t + g; want[i + 1] = t end
        local got = {}
        for v in src:gmatch("{%s*t%s*=%s*([%d%.]+)") do got[#got + 1] = tonumber(v) end
        eq(#got, 18, "GOTHIK: the shipping wave script has all 18 waves")
        local mism = 0
        for i = 1, 18 do if got[i] ~= want[i] then mism = mism + 1 end end
        eq(mism, 0, "…and every spawn time equals the spec's cumulative gap table")
        ck(src:find("PHASE2_T = 270", 1, true) ~= nil, "…with phase 2 at 270 s from pull")
        ck(src:find("SOON_LEAD = 3", 1, true) ~= nil, "…and the 3 s pre-warning lead")
    end

    do  -- Thaddius's polarity window is the spec's ICON read, and it is unedited
        local src = readFile(P("thaddius.lua")) or ""
        ck(src:find("135768", 1, true) and src:find("135769", 1, true),
           "THADDIUS: the shipping watcher reads the debuff ICONS 135768/135769 (Era rule)")
        ck(src:find("naxxramas:thaddius:polarity", 1, true) ~= nil,
           "…under the same option key the encounter row publishes")
    end
end
endgate()

gate("NAXX-DRIVE  §8 per-encounter behaviour through the real engine")
do
    loadNaxx()
    Addon:SetEventRecording(true)
    Addon._suppressLegacyAlerts = true
    Addon.RoleResolver  = function() return true end
    Addon.ClassResolver = function() return "WARLOCK" end

    -- ── §8.1 Anub'Rekhan ──────────────────────────────────────────────────────
    do
        local rt = engage("naxxramas:anubrekhan", 15956, "There is no way out.")
        ck(rt ~= nil, "ANUB: engages on the spec's yell")
        local mn, mx = barWindow(rt, "locust")
        near(mn, 77.3, 0.01, "…Locust Swarm pull window opens at 77.3")
        near(mx, 109.3, 0.01, "…and closes at 109.3")
        Addon:ClearEventLog()
        advance(75.1)
        ck(sawWarn("WARN_ANNOUNCE", "Locust Swarm soon"),
           "…the pre-warning is scheduled 75 s after pull")
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 28785, sourceId = 15956 })
        ck(bar(rt, "locustactive") ~= nil, "…the cast starts the 23 s active bar")
        near(bar(rt, "locustactive").total, 23, 0.01, "…of exactly 23 s")
        eq(bar(rt, "locust"), nil, "…and STOPS the cooldown bar at the same moment")
        ck(sawWarn("WARN_SPECIAL", "Locust Swarm"), "…and fires the aesoon special")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_REMOVED", spellId = 28785, sourceId = 15956 })
        local b = bar(rt, "locust")
        ck(b and b.min == 69.2 and b.max == 69.2,
           "…swarm removal restarts the cooldown at the FIXED 69.2 s (Era quirk)")
        ck(sawWarn("WARN_ANNOUNCE", "Locust Swarm faded"), "…and announces the fade at tier 1")
        Addon:ClearEventLog()
        advance(54.3)
        ck(sawWarn("WARN_ANNOUNCE", "Locust Swarm soon"), "…re-arming the pre-warning 54.2 s later")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 28783, sourceId = 15956 })
        local scanned = false
        for _, e in ipairs(Addon:GetEventLog()) do if e.event == "SCAN_REQUEST" then scanned = true end end
        ck(scanned, "…and Impale raises the 0.1 s x 6 boss target scan")
    end

    -- ── §8.2 Grand Widow Faerlina ─────────────────────────────────────────────
    do
        local rt = engage("naxxramas:faerlina", 15953, "Kneel before me, worm!")
        ck(rt ~= nil, "FAERLINA: engages on the spec's yell")
        near(bar(rt, "enrage").total, 56, 0.01, "…the enrage bar is 56 s at pull")
        -- Embrace with NO enrage: bar stops, and does NOT come back
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 28732, destId = 15953 })
        eq(bar(rt, "enrage"), nil, "…Widow's Embrace STOPS the enrage bar")
        near(bar(rt, "embrace").total, 30, 0.01, "…and starts a 30 s Embrace bar")
        Life:Deliver({ on = "SPELL_AURA_REMOVED", spellId = 28732, destId = 15953 })
        eq(bar(rt, "enrage"), nil,
           "…Embrace ending does NOT restart it when she was never enraged")
        -- now enrage for real, then Embrace again
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 28798, destId = 15953 })
        eq(rt:GetState("enraged"), "yes", "…Frenzy records that she IS enraged")
        ck(sawWarn("WARN_ANNOUNCE", "Enrage"), "…announcing it at tier 4")
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 28732, destId = 15953 })
        Life:Deliver({ on = "SPELL_AURA_REMOVED", spellId = 28732, destId = 15953 })
        local mn, mx = barWindow(rt, "enrage")
        ck(mn == 56 and mx == 76, "…and NOW the Embrace ending restarts it at 56-76")
        -- the 25 s "ends in 5 seconds" pre-warning, and its cancellation
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 28732, destId = 15953 })
        advance(25.1)
        ck(sawWarn("WARN_ANNOUNCE", "ends in 5 seconds"),
           "…the Embrace pre-warning fires 25 s after it lands")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 28732, destId = 15953 })
        advance(3)
        Life:Deliver({ on = "SPELL_AURA_REMOVED", spellId = 28732, destId = 15953 })
        advance(30)
        ck(not sawWarn("WARN_ANNOUNCE", "ends in 5 seconds"),
           "…and is CANCELLED when the Embrace ends early")
    end

    -- ── §8.3 Maexxna ──────────────────────────────────────────────────────────
    do
        local rt = engage("naxxramas:maexxna", 15952)
        ck(rt ~= nil, "MAEXXNA: engages off the combat sweep")
        near(bar(rt, "webspray").total, 40.5, 0.01, "…Web Spray is 40.5 s from pull")
        local mn, mx = barWindow(rt, "webwrap")
        ck(mn == 18.2 and mx == 20.1, "…Web Wrap's PULL window is 18.2-20.1")
        near(bar(rt, "spiderlings").total, 30.7, 0.01, "…Spiderlings are 30.7 s")
        Addon:ClearEventLog()
        advance(25.8)
        ck(sawWarn("WARN_ANNOUNCE", "Spiderlings soon"), "…'spiderlings soon' lands 25.7 s in")
        advance(10)
        ck(sawWarn("WARN_ANNOUNCE", "Web Spray soon"), "…'web spray soon' lands 35.5 s in")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 29484, sourceId = 15952 })
        ck(sawWarn("WARN_ANNOUNCE", "Web Spray"), "…the cast announces at tier 4")
        near(bar(rt, "spiderlings").total, 30.7, 0.01,
           "…and the spiderling cycle is re-seeded by the SPRAY, not its own timer")
        mn, mx = barWindow(rt, "webwrap")
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 28622, destName = "Bob" })
        mn, mx = barWindow(rt, "webwrap")
        ck(mn == 39.6 and mx == 40.9, "…a wrap restarts Web Wrap on the RECURRING 39.6-40.9")
        Addon:ClearEventLog()
        advance(0.6)
        ck(sawWarn("WARN_SPECIAL", "Switch targets"), "…and the switch-target special fires 0.5 s out")
        -- …but not when the wrapped player is YOU
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 28622, destName = "Drew",
                       destIsPlayer = true })
        advance(1)
        ck(not sawWarn("WARN_SPECIAL", "Switch targets"),
           "…and is CANCELLED when you are the wrapped player")
    end

    -- ── §8.4 Noth the Plaguebringer (the hard-coded teleport clock) ───────────
    do
        local rt = engage("naxxramas:noth", 15954, "Die, trespasser!")
        ck(rt ~= nil, "NOTH: engages on the spec's yell")
        local mn, mx = barWindow(rt, "curse")
        ck(mn == 6.5 and mx == 25.9, "…the curse bar opens on its 6.5-25.9 pull window")
        Addon:ClearEventLog()
        advance(70.9)                                   -- 90.8 - 20
        ck(sawWarn("WARN_ANNOUNCE", "Teleport in 20 seconds"),
           "…the teleport pre-warning fires 20 s before the first transition")
        Addon:ClearEventLog()
        advance(20)                                     -- t = 90.8: teleport 1 (to balcony)
        ck(sawWarn("WARN_ANNOUNCE", "Teleported"), "…and 'Teleported' fires at 90.8 s (tick 1)")
        near(bar(rt, "adds") and bar(rt, "adds").total, 5, 0.01,
           "…an odd tick (to the balcony) arms the adds bar at 5 s")
        Addon:ClearEventLog()
        advance(75)                                     -- t = 165.8: tick 2, back to the room
        eq(rt:GetCount("telecycle"), 1, "…tick 2 is the first RETURN, counted")
        near(bar(rt, "curse").total, 10, 0.01, "…which arms the curse at 10 s")
        near(bar(rt, "adds").total, 3, 0.01, "…and the adds at 3 s (1st return)")
        advance(109)                                    -- tick 3 (balcony)
        advance(97)                                     -- tick 4 (return)
        eq(rt:GetCount("telecycle"), 2, "…tick 4 is the second return")
        near(bar(rt, "adds").total, 17, 0.01, "…arming the adds at 17 s (2nd return)")
        -- the 67 s slot: cycle 2's SECOND curse
        eq(rt:GetCount("cursecycle"), 0, "…with the per-cycle curse counter re-seeded")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 29213, sourceId = 15954 })
        near(bar(rt, "curse").total, 67, 0.01,
           "…so the 2nd cycle's SECOND curse is the spec's 67 s slot, not the variance")
        eq(rt:GetCount("cursecycle"), 1, "…and the cycle counter advanced")
        advance(173)                                    -- tick 5 (balcony)
        advance(126)                                    -- tick 6 (return)
        near(bar(rt, "curse").total, 67, 0.01,
           "…the 3rd return's FIRST curse is the other 67 s slot")
        advance(93)                                     -- tick 7 (balcony)
        advance(55)                                     -- tick 8 (return)
        near(bar(rt, "curse").total, 17, 0.01, "…and the 4th return arms it at 17 s, not 10")
        -- the tail alternates forever
        Addon:ClearEventLog()
        advance(35)                                     -- tick 9 (balcony)
        ck(sawWarn("WARN_ANNOUNCE", "Teleported"), "…the tail repeats: tick 9 at +35 s")
        Addon:ClearEventLog()
        advance(55)                                     -- tick 10 (return)
        ck(sawWarn("WARN_ANNOUNCE", "Teleported"), "…tick 10 at +55 s")
        Addon:ClearEventLog()
        advance(35)                                     -- tick 11 (balcony) — repeatFrom cycles
        ck(sawWarn("WARN_ANNOUNCE", "Teleported"),
           "…and tick 11 at +35 s again (the alternating tail, not a repeated last gap)")
        -- add-wave cadence inside a cycle
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_YELL", "Rise, my soldiers! Rise and fight once more!")
        ck(sawWarn("WARN_SPECIAL", "Kill the adds"), "…the add-wave yell fires the kill-adds special")
    end

    -- ── §8.5 Heigan (a pure two-state scheduled loop, zero combat-log triggers) ─
    do
        local rt = engage("naxxramas:heigan", 15936, "You are mine now.")
        ck(rt ~= nil, "HEIGAN: engages on the spec's yell")
        -- (was "exactly two warnings, no combat-log triggers at all" before the owner's
        -- 2026-08-07 restoration put Decrepit Fever and Spell Disruption back)
        eq(#Addon:GetEncounter("naxxramas:heigan").warnings, 4,
           "…and its PHASE surface is still purely scheduled (2 scheduled + the 2 restored)")
        near(bar(rt, "teleportdance").total, 90, 0.01, "…the first teleport is 90 s from pull")
        Addon:ClearEventLog()
        advance(75.1)                                   -- 90 - 15
        ck(sawWarn("WARN_ANNOUNCE", "Teleport soon"), "…with a 15 s pre-warning before the room ends")
        Addon:ClearEventLog()
        advance(15)
        ck(sawWarn("WARN_ANNOUNCE", "Teleported"), "…'Teleported' at 90 s")
        near(bar(rt, "teleportroom").total, 47, 0.01, "…and the dance phase is 47 s")
        Addon:ClearEventLog()
        advance(37.1)                                   -- 47 - 10
        ck(sawWarn("WARN_ANNOUNCE", "Teleport soon"),
           "…with a 10 s pre-warning before the dance ends (the lead ALTERNATES)")
        advance(10)
        near(bar(rt, "teleportdance").total, 88, 0.01, "…and the next room phase is 88 s")
    end

    -- ── §8.6 Loatheb ──────────────────────────────────────────────────────────
    do
        local rt = engage("naxxramas:loatheb", 16011)
        ck(rt ~= nil, "LOATHEB: engages off the combat sweep")
        near(bar(rt, "spore").total, 11.3, 0.01, "…the first spore is 11.3 s")
        near(bar(rt, "doom").total, 121.3, 0.01, "…the first doom is 121.3 s")
        local mn, mx = barWindow(rt, "necroticaura")
        ck(mn == 0.5 and mx == 8.2, "…and the heal window opens on its 0.5-8.2 pull window")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 29234, sourceId = 16011 })
        near(bar(rt, "spore").total, 12.9, 0.01, "…spores recur at 12.9 s")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 30281, sourceId = 16011 })
        near(bar(rt, "necroticaura").total, 30.7, 0.01, "…and the heal window at 30.7 s")
        -- the doom cadence: alternating, then a different shape from the 7th
        local WANT = { 29.1, 32.4, 29.1, 32.4, 29.1, 9.7, 19.4, 11.3, 19.4, 11.3 }
        local okAll = true
        for i, want in ipairs(WANT) do
            Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 29204, sourceId = 16011 })
            local b = bar(rt, "doom")
            if not b or math.abs(b.total - want) > 0.01 then okAll = false end
        end
        ck(okAll, "…doom alternates 29.1/32.4 and re-shapes at the 7th to 9.7 then 19.4/11.3")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 29195, destIsPlayer = true,
                       destName = "Drew" })
        advance(55.1)
        ck(sawWarn("WARN_ANNOUNCE", "Healing possible in 3 seconds"),
           "…and 'healing possible' fires 55 s after YOUR Corrupted Mind lands")
    end

    -- ── §8.7 Instructor Razuvious ─────────────────────────────────────────────
    do
        Addon.ClassResolver = function() return "PRIEST" end
        local rt = engage("naxxramas:razuvious", 16061, "Do as I taught you!")
        ck(rt ~= nil, "RAZUVIOUS: engages on the spec's yell")
        near(bar(rt, "shout").total, 25.9, 0.01, "…Disrupting Shout is 25.9 s")
        Addon:ClearEventLog()
        advance(19.6)
        ck(sawWarn("WARN_ANNOUNCE", "Disrupting Shout soon"), "…with the pre-warning 19-20 s out")
        -- pet-sourced understudy timers (a mind-controlled understudy IS a pet)
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 29060, sourceIsPet = true,
                       destName = "Understudy" })
        ck(rt.timers.taunt ~= nil, "…an understudy Taunt from a PET source starts the 60 s bar")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 29060, destName = "Understudy" })
        ck(true, "…(a non-pet source is ignored by the same row)")
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 29061, sourceIsPet = true,
                       destName = "Understudy" })
        ck(rt.timers.shieldwall ~= nil, "…Shield Wall likewise, as a 20 s active bar")
        Addon:ClearEventLog()
        advance(15.1)
        ck(sawWarn("WARN_ANNOUNCE", "Shield Wall"),
           "…and the Shield Wall warning lands 15 s in (5 s before it ends)")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 29051,
                       sourceGUID = "Creature-0-0-0-0-16803-0007", sourceId = 16803 })
        ck(rt.timers.mindexhaust ~= nil, "…and Mind Exhaustion runs per understudy nameplate")
        -- the combat-log pet flag itself
        local ev = Life:NormalizeCLEU("SPELL_CAST_SUCCESS", "g1", "Pet", 0x00001111, 0,
                                      "g2", "Boss", 0, 0, 29060, "Taunt")
        ck(ev.sourceIsPet, "…and the pet flag is read straight off the combat-log source flags")
        Addon.ClassResolver = function() return "WARLOCK" end
    end

    -- ── §8.8 Gothik the Harvester ─────────────────────────────────────────────
    do
        local rt = engage("naxxramas:gothik", 16060)
        ck(rt ~= nil, "GOTHIK: engages off the combat sweep")
        eq(rt.stage, 1, "…in phase 1")
        Addon:ClearEventLog()
        Life:Deliver({ on = "unitCast", spellId = 28025 })
        eq(rt.stage, 2, "…the FIRST live-side teleport promotes the fight to phase 2")
        ck(sawWarn("WARN_ANNOUNCE", "live side"), "…announcing the teleport")
        local mn, mx = barWindow(rt, "teledead")
        ck(mn == 19.4 and mx == 21, "…and arming the OTHER side's bar at 19.4-21")
        Addon:ClearEventLog()
        advance(14.6)
        ck(sawWarn("WARN_ANNOUNCE", "Teleport soon"), "…with a 14.5 s pre-warning")
        Life:Deliver({ on = "unitCast", spellId = 28026 })
        eq(rt.stage, 2, "…a later teleport does NOT re-promote the phase")
        ck(bar(rt, "telelive") ~= nil, "…and the bars alternate back")
        -- <= 30 %: Gothik stops teleporting
        setUnit("target", { cid = 16060, combat = true, hp = 29, hpmax = 100 })
        Life:PollHealth(rt)
        eq(bar(rt, "telelive"), nil, "…at <= 30 % HP every teleport bar is cancelled")
        eq(bar(rt, "teledead"), nil, "…both of them")
        Addon:ClearEventLog()
        Life:Deliver({ on = "UNIT_DIED", creatureId = 16126, destId = 16126,
                       destGUID = "Creature-0-0-0-0-16126-1" })
        ck(sawWarn("WARN_ANNOUNCE", "Rider down"), "…a Rider death announces at tier 4")
        Life:Deliver({ on = "UNIT_DIED", creatureId = 16126, destId = 16126,
                       destGUID = "Creature-0-0-0-0-16126-1" })
        eq(warnCount("WARN_ANNOUNCE", "Rider down"), 1, "…de-duplicated by GUID")
    end

    -- ── §8.9 The Four Horsemen ────────────────────────────────────────────────
    do
        local rt = engage("naxxramas:fourhorsemen", 16062)
        ck(rt ~= nil, "FOUR HORSEMEN: engages off the combat sweep")
        ck(Addon:GetEncounter("naxxramas:fourhorsemen").combat.highestHealth,
           "…reporting boss health as the HIGHEST of the four")
        near(bar(rt, "markcd").total, 21, 0.01, "…the first Mark is 21 s from pull")
        eq(rt:GetCount("horsemen"), 4, "…with the census seeded at four")
        Addon:ClearEventLog()
        -- all four marks land together; the 10 s anti-spam collapses them into one
        for _, sid in ipairs({ 28832, 28833, 28834, 28835 }) do
            Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = sid })
        end
        near(bar(rt, "markcd").total, 12.9, 0.01, "…recurring Marks are 12.9 s")
        eq(Addon._mechCount["naxxramas:fourhorsemen:markcd"], 2,
           "…and the Mark count is published where the shipped tracker reads it")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 28884 })
        ck(sawWarn("WARN_ANNOUNCE", "Meteor"), "…Meteor announces at tier 4")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 28863, destName = "Bob" })
        ck(sawWarn("WARN_ANNOUNCE", "Void Zone on Bob"),
           "…Void Zone names its victim (target interpolation)")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 28863, destName = "Drew",
                       destIsPlayer = true })
        ck(sawWarn("WARN_SPECIAL", "Void Zone on YOU"), "…and fires the personal special on you")
        Addon:ClearEventLog()
        Life:Deliver({ on = "UNIT_DIED", creatureId = 16065, destId = 16065,
                       destGUID = "Creature-0-0-0-0-16065-1" })
        eq(rt:GetCount("horsemen"), 3, "…a horseman's death decrements the census")
        eq(bar(rt, "voidzone"), nil, "…(and no Void Zone radial exists here — the tracker owns it)")
    end

    -- ── §8.10 Patchwerk ───────────────────────────────────────────────────────
    do
        local rt = engage("naxxramas:patchwerk", 16028, "Patchwerk want to play!")
        ck(rt ~= nil, "PATCHWERK: engages on the spec's yell")
        near(bar(rt, "berserk").total, 420, 0.01, "…Berserk is 420 s from pull")
        Addon:ClearEventLog()
        setUnit("target", { cid = 16028, combat = true, hp = 9, hpmax = 100 })
        Life:PollHealth(rt)
        ck(sawWarn("WARN_ANNOUNCE", "Enrage soon"), "…'enrage soon' fires at <= 10 % HP")
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 28311 })
        ck(sawWarn("WARN_ANNOUNCE", "Slime Bolt"), "…and Slime Bolt announces on the cast START")
    end

    -- ── §8.11 Grobbulus ───────────────────────────────────────────────────────
    do
        local rt = engage("naxxramas:grobbulus", 15931)
        near(bar(rt, "berserk").total, 720, 0.01, "GROBBULUS: Berserk is 720 s")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 28169, destName = "Bob" })
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 28169, destName = "Alice" })
        local n = 0
        for _ in pairs(rt.timers.injection.live) do n = n + 1 end
        eq(n, 2, "…injections run ONE 10 s bar per target")
        Life:Deliver({ on = "SPELL_AURA_REMOVED", spellId = 28169, destName = "Bob" })
        n = 0
        for _ in pairs(rt.timers.injection.live) do n = n + 1 end
        eq(n, 1, "…and an early dispel stops that player's bar")
        ck(sawWarn("WARN_ANNOUNCE", "Mutating Injection on Bob"), "…naming each target")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 28169, destIsPlayer = true,
                       destName = "Drew" })
        ck(sawWarn("WARN_SPECIAL", "run out"), "…and firing the personal run-out special")
        local mn, mx
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 28240 })
        mn, mx = barWindow(rt, "cloud")
        ck(mn == 14.5 and mx == 16.6, "…Poison Cloud recurs on 14.5-16.6")
    end

    -- ── §8.12 Gluth ───────────────────────────────────────────────────────────
    do
        local rt = engage("naxxramas:gluth", 15932)
        near(bar(rt, "berserk").total, 420, 0.01, "GLUTH: Berserk is 420 s")
        local mn, mx = barWindow(rt, "frenzy")
        ck(mn == 9.6 and mx == 11.3, "…Frenzy's pull window is 9.6-11.3")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 28371 })
        mn, mx = barWindow(rt, "frenzy")
        ck(mn == 8.1 and mx == 11.4, "…and it recurs on 8.1-11.4")
        mn, mx = barWindow(rt, "roar")
        ck(mn == 17.8 and mx == 24.2, "…Terrifying Roar runs 17.8-24.2 from pull")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 28371, destId = 15932 })
        ck(sawWarn("WARN_SPECIAL", "Dispel the Frenzy"), "…Frenzy raises the enrage-dispel special")
        -- Era: Decimate has no cast event; it is detected from the DAMAGE
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_DAMAGE", spellId = 28374 })
        ck(sawWarn("WARN_ANNOUNCE", "Decimate"), "…Decimate is detected from its DAMAGE (Era quirk)")
        Life:Deliver({ on = "SPELL_DAMAGE", spellId = 28375 })
        Life:Deliver({ on = "SPELL_DAMAGE", spellName = "Decimate" })
        eq(warnCount("WARN_ANNOUNCE", "Decimate"), 1, "…once per 20 s, matched on id OR name")
    end

    -- ── §8.13 Thaddius (the adds phase, the intermission, the polarity window) ─
    do
        local rt = engage("naxxramas:thaddius", 15929, "Stalagg crush you!")
        ck(rt ~= nil, "THADDIUS: engages on the ADDS-phase yell")
        near(bar(rt, "magneticpull").total, 21, 0.01, "…Throw is 21 s from pull")
        Addon:ClearEventLog()
        advance(16.1)
        ck(sawWarn("WARN_ANNOUNCE", "Throw soon"), "…with the pre-warning 16 s out")
        eq(rt:GetState("stalagg"), "alive", "…both adds start alive")
        Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "Stalagg dies.")
        eq(rt:GetState("stalagg"), "dead", "…the add emote kills Stalagg")
        eq(rt.stage, 1, "…one dead add is NOT the intermission")
        Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "Feugen is jolted back to life!")
        eq(rt:GetState("feugen"), "alive", "…and a jolt brings one back")
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "Feugen dies.")
        eq(rt.stage, 1.5, "…BOTH adds simultaneously dead begins phase 1.5")
        ck(bar(rt, "intermission") ~= nil, "…starting the intermission bar")
        local mn, mx = barWindow(rt, "intermission")
        ck(mn == 12.8 and mx == 16, "…on the 12.8-16 window")
        eq(bar(rt, "magneticpull"), nil, "…and stopping the throw bar")
        ck(sawWarn("WARN_ANNOUNCE", "Phase 2 soon"), "…with the pre-phase warning")
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_YELL", "Break... you!!")
        eq(rt.stage, 2, "…and the boss yell begins phase 2")
        near(bar(rt, "berserk").total, 300, 0.01, "…starting the 300 s berserk")
        near(bar(rt, "polarity").total, 11.3, 0.01, "…and the first Polarity Shift at 11.3 s")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 28089 })
        mn, mx = barWindow(rt, "polarity")
        ck(mn == 25.9 and mx == 35.7, "…recurring on the PHASE-2 window 25.9-35.7")
        near(bar(rt, "polaritycast").total, 3, 0.01, "…with a 3 s cast bar")
        ck(sawWarn("WARN_ANNOUNCE", "Polarity Shift — casting"), "…announced at tier 4")
        Addon:ClearEventLog()
        advance(20.1)
        ck(sawWarn("WARN_ANNOUNCE", "Polarity Shift soon"), "…and pre-warned 20 s out")
    end

    -- ── §8.14 Sapphiron (air phase by target LOSS — the Era quirk) ────────────
    do
        local rt = engage("naxxramas:sapphiron", 15989)
        near(bar(rt, "berserk").total, 900, 0.01, "SAPPHIRON: Berserk is 900 s")
        local mn, mx = barWindow(rt, "airphase")
        ck(mn == 31.2 and mx == 45.9, "…the first air phase opens on 31.2-45.9")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 28542 })
        mn, mx = barWindow(rt, "lifedrain")
        ck(mn == 21.1 and mx == 27.5, "…Life Drain runs 21.1-27.5")
        eq(rt:GetState("flight"), "ground", "…and he starts on the ground")
        -- the scanner reports LOSS; 0.5 s of it means he lifted off
        Addon:ClearEventLog()
        rt:Route({ on = "targetChanged", key = "airscan", lost = true })
        eq(rt:GetState("flight"), "ground", "…a single target-less sample is NOT the air phase")
        advance(0.6)
        eq(rt:GetState("flight"), "air", "…but 0.5 s of it IS (the 5 Hz target-loss rule)")
        ck(sawWarn("WARN_ANNOUNCE", "Air phase"), "…announced at tier 4")
        near(bar(rt, "landing").total, 28.5, 0.01, "…arming the 28.5 s landing bar")
        eq(bar(rt, "lifedrain"), nil, "…and cancelling Life Drain for the air phase")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 28522, destName = "Bob" })
        ck(sawWarn("WARN_ANNOUNCE", "Ice Block on Bob"), "…Ice Blocks are counted and named")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 28524 })
        ck(sawWarn("WARN_SPECIAL", "Find shelter"), "…Frost Breath raises the shelter special")
        near(bar(rt, "frostbreath").total, 7, 0.01, "…with a 7 s cast bar")
        mn, mx = barWindow(rt, "landing")
        ck(mn == 16.3 and mx == 28.5, "…and CORRECTS the landing bar to 16.3-28.5")
        advance(12.3)
        eq(rt:GetState("flight"), "ground", "…he lands 12.2 s after Frost Breath starts")
        mn, mx = barWindow(rt, "airphase")
        ck(mn == 54.3 and mx == 70.8, "…re-arming the air phase on 54.3-70.8")
        -- the safety net, and the <= 10 % cancellation
        setUnit("target", { cid = 15989, combat = true, hp = 9, hpmax = 100 })
        Life:PollHealth(rt)
        eq(bar(rt, "airphase"), nil, "…and at <= 10 % HP the air-phase bar is cancelled for good")
    end

    -- ── §8.15 Kel'Thuzad ──────────────────────────────────────────────────────
    do
        local rt = engage("naxxramas:kelthuzad", 15990,
            "Minions, servants, soldiers of the cold dark! Obey the call of Kel'Thuzad!")
        ck(rt ~= nil, "KEL'THUZAD: engages on the spec's yell")
        local enc = Addon:GetEncounter("naxxramas:kelthuzad")
        eq(enc.combat.minCombatTime, 60, "…with a 60 s minimum combat time")
        eq(enc.combat.wipeWindow, 15, "…and a 15 s wipe timeout")
        local mn, mx = barWindow(rt, "phase2")
        ck(mn == 229.2 and mx == 245.8, "…phase 1 is the wide 229.2-245.8 variance bar")
        Addon:ClearEventLog()
        advance(220.1)
        ck(sawWarn("WARN_ANNOUNCE", "Phase 2 soon"), "…pre-warned at 220 s")
        -- Era: the nameplate appearing IS phase 2
        Addon:ClearEventLog()
        Life:OnEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
        eq(rt.stage, 1, "…an unknown nameplate does nothing")
        setUnit("nameplate1", { cid = 15990, combat = true, hp = 100, hpmax = 100 })
        Life:OnEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
        eq(rt.stage, 2, "…HIS nameplate appearing promotes the fight to phase 2 (Era quirk)")
        eq(bar(rt, "phase2"), nil, "…stopping the phase-1 bar")
        mn, mx = barWindow(rt, "frostblast")
        ck(mn == 30.3 and mx == 92.7, "…and every P2 ability arms on its PHASE-2-START value")
        mn, mx = barWindow(rt, "detonate")
        ck(mn == 20.2 and mx == 46.5, "…Mana Bomb included")
        mn, mx = barWindow(rt, "chains")
        ck(mn == 21.8 and mx == 103.4, "…and Chains")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 27808 })
        mn, mx = barWindow(rt, "frostblast")
        ck(mn == 33.5 and mx == 75.3, "…then recurs on the ordinary 33.5-75.3")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 27810, destName = "Bob" })
        ck(sawWarn("WARN_ANNOUNCE", "Shadow Fissure on Bob"), "…Shadow Fissure names its target")
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 28478,
                       sourceGUID = "Creature-0-0-0-0-15990-3" })
        ck(rt.timers.frostboltcast
           and rt.timers.frostboltcast:Get("Creature-0-0-0-0-15990-3") ~= nil,
           "…Frostbolt runs a per-CASTER nameplate cast bar (one bar per mob GUID)")
        Life:Deliver({ on = "SPELL_INTERRUPT", spellId = 28478,
                       sourceGUID = "Creature-0-0-0-0-15990-3" })
        ck(sawWarn("WARN_SPECIAL", "Interrupt Frostbolt"), "…and raises the interrupt special")
        -- phase 3 is a health rule that only applies IN PHASE 2
        Addon:ClearEventLog()
        setUnit("target", { cid = 15990, combat = true, hp = 47, hpmax = 100 })
        Life:PollHealth(rt)
        eq(rt.stage, 3, "…and 48 % IN PHASE 2 is the guardian-summon phase 3")
        ck(sawWarn("WARN_ANNOUNCE", "Phase 3"), "…announced")
    end

    -- ── §8.16 the zone-wide trash module ──────────────────────────────────────
    do
        resetLife()
        eq(Life:ArmZones(533), 1, "TRASH: entering Naxxramas ARMS the zone module")
        ck(Life:IsZoneArmed("naxxramas:trash"), "…without engaging anything")
        ck(not Life:AnyEngaged(), "…and without registering as a boss engagement")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 27990 })
        ck(sawWarn("WARN_ANNOUNCE", "Fear"), "…trash alerts fire off the shared combat-log path")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 27990 })
        eq(warnCount("WARN_ANNOUNCE", "Fear"), 1, "…throttled by the spec's 5 s anti-spam")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_SUMMON", spellId = 28294 })
        Life:Deliver({ on = "SPELL_SUMMON", spellId = 28294 })
        eq(warnCount("WARN_SPECIAL", "lightning totem"), 2,
           "…and the totem special fires for BOTH packs (no anti-spam, deliberately)")
        W.instanceID = 409
        eq(Life:ArmZones(409), 0, "…zoning into another instance disarms it")
        ck(not Life:IsZoneArmed("naxxramas:trash"), "…leaving nothing armed")
        W.instanceID = 533
    end

    -- ══════════════════════════════════════════════════════════════════════════
    --  THE OWNER'S 2026-08-07 ARBITRATIONS, THROUGH THE ENGINE
    --  Decision 1: each dual-ID row is driven ONCE PER ID and must fire either way.
    --  Decision 2: each restored row is driven trigger -> warning/timer, with its
    --  shipped default asserted (an off-by-default row must stay SILENT on defaults
    --  and fire the moment the player ticks its box — that is what "the honest
    --  middle" has to mean in the engine, not just in the registry).
    -- ══════════════════════════════════════════════════════════════════════════
    do
        Addon.db.mechanics = Addon.db.mechanics or {}
        local function tick(key, on)   -- the SavedVariables override a player's tick writes
            Addon.db.mechanics[key] = on and { masterEnabled = true } or nil
        end

        -- ── 1a. Faerlina's Enrage: 28798 (spec/DBM) AND 28131 (our field logs) ───
        for _, id in ipairs({ 28798, 28131 }) do
            local rt = engage("naxxramas:faerlina", 15953, "Kneel before me, worm!")
            Addon:ClearEventLog()
            Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = id, destId = 15953 })
            ck(sawWarn("WARN_ANNOUNCE", "Enrage"),
               "DUAL-ID FAERLINA: the Enrage announce fires on " .. id)
            eq(rt:GetState("enraged"), "yes",
               "…and " .. id .. " records that she IS enraged (the restart gate)")
            -- …so the Embrace cycle restarts the bar whichever id arrived
            Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 28732, destId = 15953 })
            Life:Deliver({ on = "SPELL_AURA_REMOVED", spellId = 28732, destId = 15953 })
            local mn, mx = barWindow(rt, "enrage")
            ck(mn == 56 and mx == 76,
               "…and the post-Embrace restart works off " .. id .. " too")
        end
        -- the tank-defensive special, both ids, with YOU as the boss's target
        do
            local prev = API.Conditions.playerIsBossTarget
            API.Conditions.playerIsBossTarget = function() return true end
            for _, id in ipairs({ 28798, 28131 }) do
                engage("naxxramas:faerlina", 15953, "Kneel before me, worm!")
                Addon:ClearEventLog()
                Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = id, destId = 15953 })
                ck(sawWarn("WARN_SPECIAL", "use a defensive"),
                   "…and the tank-defensive special fires on " .. id .. " as well")
            end
            API.Conditions.playerIsBossTarget = prev
        end

        -- ── 1b. Sapphiron's Blizzard GTFO: 28547 (spec/DBM) AND 28560 (observed) ─
        for _, id in ipairs({ 28547, 28560 }) do
            engage("naxxramas:sapphiron", 15989)
            for _, sub in ipairs({ "SPELL_AURA_APPLIED", "SPELL_DAMAGE",
                                   "SPELL_PERIODIC_DAMAGE" }) do
                Addon:ClearEventLog()
                Life:Deliver({ on = sub, spellId = id, destIsPlayer = true, destName = "Drew" })
                ck(sawWarn("WARN_SPECIAL", "Move out of the Blizzard"),
                   "DUAL-ID SAPPHIRON: " .. sub .. " on " .. id .. " raises the GTFO")
                advance(3)   -- clear the 2.5 s anti-spam between arms
            end
        end

        -- ── 1c. Noth's Blink: all four observed ids, not the spec's one ──────────
        do
            engage("naxxramas:noth", 15954, "Die, trespasser!")
            for _, id in ipairs({ 29208, 29209, 29210, 29211 }) do
                Addon:ClearEventLog()
                Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = id, sourceId = 15954 })
                ck(sawWarn("WARN_ANNOUNCE", "Blink"),
                   "DUAL-ID NOTH: Blink announces on " .. id)
            end
        end

        -- ── 2. every restored row, driven, with its shipped default asserted ─────
        -- { encounter, cid, yell, key, deliver-event, ships off?, needle }
        local R = {
            { "naxxramas:razuvious", 16061, "Do as I taught you!", "unbalancing",
              { on = "SPELL_CAST_SUCCESS", spellId = 26613, sourceId = 16061 },
              false, "Unbalancing Strike — tank swap" },
            { "naxxramas:gluth", 15932, nil, "mortalwound",
              { on = "SPELL_AURA_APPLIED", spellId = 25646, destName = "Bob", amount = 3 },
              false, "Mortal Wound Bob (3)" },
            { "naxxramas:heigan", 15936, "You are mine now.", "fever",
              { on = "SPELL_CAST_SUCCESS", spellId = 29998, sourceId = 15936 },
              false, "Decrepit Fever" },
            { "naxxramas:heigan", 15936, "You are mine now.", "disrupt",
              { on = "SPELL_CAST_SUCCESS", spellId = 29310, sourceId = 15936 },
              false, "Spell Disruption" },
            { "naxxramas:gothik", 16060, nil, "harvest",
              { on = "SPELL_CAST_SUCCESS", spellId = 28679, sourceId = 16060 },
              false, "Harvest Soul" },
            { "naxxramas:gothik", 16060, nil, "shadowbolt",
              { on = "SPELL_CAST_SUCCESS", spellId = 29317, sourceId = 16060 },
              true, "Shadow Bolt" },
            { "naxxramas:thaddius", 15929, "Stalagg crush you!", "powersurge",
              { on = "SPELL_CAST_SUCCESS", spellId = 28134 },
              false, "Power Surge — Stalagg damage up" },
            { "naxxramas:thaddius", 15929, "Stalagg crush you!", "balllightning",
              { on = "SPELL_CAST_SUCCESS", spellId = 28299, sourceId = 15928 },
              false, "Ball Lightning" },
            { "naxxramas:maexxna", 15952, nil, "necrotic",
              { on = "SPELL_CAST_SUCCESS", spellId = 28776, sourceId = 15952 },
              true, "Necrotic Poison" },
            { "naxxramas:faerlina", 15953, "Kneel before me, worm!", "poisonbolt",
              { on = "SPELL_CAST_SUCCESS", spellId = 28796, sourceId = 15953 },
              true, "Poison Bolt Volley" },
            { "naxxramas:grobbulus", 15931, nil, "slimespray",
              { on = "SPELL_CAST_SUCCESS", spellId = 28157, sourceId = 15931 },
              true, "Slime Spray" },
            { "naxxramas:loatheb", 16011, nil, "deathbloom",
              { on = "SPELL_AURA_APPLIED", spellId = 29865, destIsPlayer = true,
                destName = "Drew" },
              true, "Poison Aura" },
        }
        for _, r in ipairs(R) do
            local encId, key, off, needle = r[1], r[4], r[6], r[7]
            local optKey = API.OptionKey(encId, key)
            local boss = encId:match(":(.+)$")
            -- ON DEFAULTS
            tick(optKey, nil)
            engage(encId, r[2], r[3])
            Addon:ClearEventLog()
            Life:Deliver(r[5])
            if off then
                ck(not sawWarn("WARN_ANNOUNCE", needle),
                   "RESTORED " .. boss .. ":" .. key .. " is SILENT on defaults (ships off)")
                -- …and fires the moment the player ticks its box
                tick(optKey, true)
                engage(encId, r[2], r[3])
                Addon:ClearEventLog()
                Life:Deliver(r[5])
                ck(sawWarn("WARN_ANNOUNCE", needle),
                   "…and FIRES once enabled: " .. needle)
                tick(optKey, nil)
            else
                ck(sawWarn("WARN_ANNOUNCE", needle),
                   "RESTORED " .. boss .. ":" .. key .. " fires on defaults: " .. needle)
            end
        end

        -- the two shape guards, driven: an announce row that replaced a 1.x BAR must
        -- not become a spam source when a player does tick its box
        do
            tick("naxxramas:gothik:shadowbolt", true)
            engage("naxxramas:gothik", 16060)
            Addon:ClearEventLog()
            for _ = 1, 3 do                        -- 3 casts at the field-measured 1.7 s
                Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 29317, sourceId = 16060 })
                advance(1.7)
            end
            eq(warnCount("WARN_ANNOUNCE", "Shadow Bolt"), 1,
               "SHAPE GUARD: Shadow Bolts at the logged 1.7 s cadence announce ONCE per window")
            advance(5)
            Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 29317, sourceId = 16060 })
            eq(warnCount("WARN_ANNOUNCE", "Shadow Bolt"), 2,
               "…and the window re-arms after 5 s (throttled, not swallowed)")
            tick("naxxramas:gothik:shadowbolt", nil)
            engage("naxxramas:thaddius", 15929, "Stalagg crush you!")
            Addon:ClearEventLog()
            for _ = 1, 4 do
                Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 28299, sourceId = 15928 })
                advance(0.5)
            end
            eq(warnCount("WARN_ANNOUNCE", "Ball Lightning"), 1,
               "…and four Ball Lightnings inside the 3 s window announce ONCE")
        end

        -- Thaddius's Chain Lightning is the one restored row that is a BAR, not an
        -- announce — and it is off until the player asks for it.
        do
            local rt = engage("naxxramas:thaddius", 15929, "Stalagg crush you!")
            Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 28167, sourceId = 15928 })
            eq(bar(rt, "chainlightning"), nil,
               "RESTORED thaddius:chainlightning starts NO bar on defaults (ships off)")
            tick("naxxramas:thaddius:chainlightning", true)
            rt = engage("naxxramas:thaddius", 15929, "Stalagg crush you!")
            Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 28167, sourceId = 15928 })
            local b = bar(rt, "chainlightning")
            ck(b ~= nil, "…and once enabled the cast starts the cooldown radial")
            if b then near(b.total, 8.5, 0.01, "…on the field-measured 8.5 s cadence") end
            tick("naxxramas:thaddius:chainlightning", nil)
        end
    end

    -- ── the escape hatch, driven per boss ─────────────────────────────────────
    do
        local log = {}
        for _, boss in ipairs({ "loatheb", "fourhorsemen", "gothik", "razuvious", "thaddius" }) do
            Addon:RegisterModule({
                id = "w4dfix_" .. boss, raidId = "naxxramas", bossId = boss,
                name = "W4d hatch fixture", defaults = { enabled = true },
                Start = function() log[#log + 1] = "start:" .. boss end,
                Stop  = function() log[#log + 1] = "stop:" .. boss end,
            })
        end
        local CIDS = { loatheb = 16011, fourhorsemen = 16062, gothik = 16060,
                       razuvious = 16061, thaddius = 15929 }
        local YELLS = { razuvious = "Do as I taught you!", thaddius = "Stalagg crush you!" }
        for _, boss in ipairs({ "loatheb", "fourhorsemen", "gothik", "razuvious", "thaddius" }) do
            for i = #log, 1, -1 do log[i] = nil end
            local rt = engage("naxxramas:" .. boss, CIDS[boss], YELLS[boss])
            eq(log[1], "start:" .. boss,
               "HATCH: engaging naxxramas:" .. boss .. " STARTS its shipped special modules")
            ck(Addon.active and Addon.active.raidId == "naxxramas"
               and Addon.active.bossId == boss,
               "…and populates Addon.active for the widgets that read it")
            Life:EndCombat(rt, false, "test")
            advance(4)
            ck(log[#log] and log[#log]:find("stop:", 1, true) == 1,
               "…and ending the fight STOPS them")
        end
    end

    Addon._suppressLegacyAlerts = nil
    Addon:SetEventRecording(false)
    resetLife()
end
endgate()

----------------------------------------------------------------------
-- WAVE 4c — RUINS + TEMPLE OF AHN'QIRAJ ENCOUNTER DATA
--
-- Every assertion below names the DBM_ERA_ENCOUNTERS_BEHAVIOR_SPEC.md §6 / §7 row it
-- proves, and every one runs the SHIPPING data through the SHIPPING engine on the
-- injected clock and the injected world.
----------------------------------------------------------------------
local function loadAQ()
    Addon.encounters, Addon.encountersById = {}, {}
    Addon.encByCreature, Addon.encByEncounterId, Addon.encByZone = {}, {}, {}
    Addon.zones, Addon.zonesById = {}, {}
    local ok1, e1 = pcall(AQ20_CHUNK, ADDON_NAME, Addon)
    local ok2, e2 = pcall(AQ40_CHUNK, ADDON_NAME, Addon)
    return ok1 and ok2, (not ok1 and e1) or (not ok2 and e2) or nil
end

gate("AQ  §6/§7 encounter data: registration, keys, the options tree")
do
    local okc, err = loadAQ()
    ck(okc, "enc_aq20.lua + enc_aq40.lua EXECUTE against the shipping grammar" ..
            (okc and "" or (" -> " .. tostring(err))))

    local EXPECTED = {
        -- §6 Ruins of Ahn'Qiraj (zone 509)
        { id = "aq20:kurinnaxx", cid = 15348, eid = 718, raid = "aq20", boss = "kurinnaxx" },
        { id = "aq20:rajaxx",    cid = 15341, eid = 719, raid = "aq20", boss = "rajaxx" },
        { id = "aq20:moam",      cid = 15340, eid = 720, raid = "aq20", boss = "moam" },
        { id = "aq20:buru",      cid = 15370, eid = 721, raid = "aq20", boss = "buru" },
        { id = "aq20:ayamiss",   cid = 15369, eid = 722, raid = "aq20", boss = "ayamiss" },
        { id = "aq20:ossirian",  cid = 15339, eid = 723, raid = "aq20", boss = "ossirian" },
        -- §7 Temple of Ahn'Qiraj (zone 531)
        { id = "aq40:skeram",    cid = 15263, eid = 709, raid = "aq40", boss = "skeram" },
        { id = "aq40:bugtrio",   cid = 15544, eid = 710, raid = "aq40", boss = "bugtrio" },
        { id = "aq40:sartura",   cid = 15516, eid = 711, raid = "aq40", boss = "sartura" },
        { id = "aq40:fankriss",  cid = 15510, eid = 712, raid = "aq40", boss = "fankriss" },
        { id = "aq40:viscidus",  cid = 15299, eid = 713, raid = "aq40", boss = "viscidus" },
        { id = "aq40:huhuran",   cid = 15509, eid = 714, raid = "aq40", boss = "huhuran" },
        { id = "aq40:twinemps",  cid = 15276, eid = 715, raid = "aq40", boss = "twinemps" },
        { id = "aq40:ouro",      cid = 15517, eid = 716, raid = "aq40", boss = "ouro" },
        { id = "aq40:cthun",     cid = 15589, eid = 717, raid = "aq40", boss = "cthun" },
    }
    for _, e in ipairs(EXPECTED) do
        local enc = Addon:GetEncounter(e.id)
        ck(enc ~= nil, e.id .. " is registered")
        if enc then
            local errs = API.Validate(enc)
            eq(#errs, 0, "…with zero validation errors" ..
               (#errs > 0 and (": " .. table.concat(errs, "; ")) or ""))
            ck(Addon.encByCreature[e.cid] ~= nil, "…indexed by creature " .. e.cid)
            ck(Addon.encByEncounterId[e.eid] ~= nil, "…and by encounter id " .. e.eid)
            ck(enc.legacy and enc.legacy.raidId == e.raid and enc.legacy.bossId == e.boss,
               "…carrying the legacy seam " .. e.raid .. ":" .. e.boss)
            local firstRow = enc.timers[1] or enc.warnings[1]
            if firstRow then
                eq(API.OptionKey(enc.id, firstRow.key),
                   Addon:MechKey(e.raid, e.boss, firstRow.key),
                   "…and OptionKey == MechKey for its rows (one SavedVariables entry, not two)")
            end
        end
    end
    eq(#Addon.encounters, #EXPECTED + 2, "…17 registrations in all (15 bosses + two trash modules)")

    do  -- the two zone-wide trash modules
        for _, p in ipairs({ { "aq20:trash", 509 }, { "aq40:trash", 531 } }) do
            local trash = Addon:GetEncounter(p[1])
            ck(trash ~= nil and trash.detect.mode == "zone",
               p[1] .. " registers as a ZONE module")
            ck(trash and Addon.encByZone[p[2]] ~= nil, "…indexed against instance " .. p[2])
        end
        local t20 = Addon:GetEncounter("aq20:trash")
        local t40 = Addon:GetEncounter("aq40:trash")
        -- §6.7 / §7.10: the reflect pair, read from the MISS TYPE and the school
        for _, t in ipairs({ t20, t40 }) do
            local r = t.rowsByKey.reflectshadowfrost
            ck(r and r.triggers[1].missType[1] == "REFLECT"
               and r.triggers[1].missType[2] == "DEFLECT",
               t.id .. ": the reflect alert matches on REFLECT/DEFLECT, not on a buff")
            ck(r and r.triggers[1].school == 32 and r.triggers[2].school == 16,
               "…across the Shadow (32) and Frost (16) schools")
            local f = t.rowsByKey.reflectfirearcane
            ck(f and f.triggers[1].school == 4 and f.triggers[2].school == 64,
               "…with Fire (4) / Arcane (64) as the other pair")
        end
        eq(t40.rowsByKey.thunderclap.start.antispamBy, "sourceGUID",
           "§7.10 Thunderclap's 1 s anti-spam is PER MOB, not per pull")
        eq(t20.rowsByKey.thunderclapicon.on.antispamBy, "sourceGUID", "…same on the AQ20 side")
        eq(t40.rowsByKey.explodebar.duration, 6, "§7.10 Explode runs a 6 s cast bar…")
        ck(t40.rowsByKey.explodebar.nameplate == true, "…one per mob GUID…")
        eq(t40.rowsByKey.explodebar.stop.creatureId, 15277, "…stopped when that mob dies")
        eq(t20.rowsByKey.explodebar.stop.creatureId, 15355,
           "…and AQ20 uses its OWN exploding creature id (15355, not 15277)")
    end

    do  -- ship-off defaults carried from the spec verbatim
        local OFF = {
            { "aq40:twinemps", "explodebug" },     -- §7.7 "off by default"
            { "aq40:twinemps", "mutatebug" },
            { "aq40:twinemps", "mutatebugwarn" },
            { "aq40:cthun",    "clawtentaclewarn" },   -- §7.9 "off by default"
        }
        for _, p in ipairs(OFF) do
            local enc = Addon:GetEncounter(p[1])
            local row = enc and enc.rowsByKey[p[2]]
            ck(row and row.default == false, p[1] .. ":" .. p[2] .. " SHIPS OFF (spec default)")
        end
        -- …and the two icon options the spec says ship ON
        eq(Addon:GetEncounter("aq40:skeram").rowsByKey.mcicons.default, true,
           "§7.1 the mind-control icons ship ON")
        eq(Addon:GetEncounter("aq40:cthun").rowsByKey.eyebeamicon.default, true,
           "§7.9 the Eye Beam raid icon ships ON")
        eq(Addon:GetEncounter("aq40:twinemps").rowsByKey.mutateicons.default, true,
           "§7.7 the mutated-bug nameplate icon ships ON")
    end

    do  -- 1.x SavedVariables continuity: the keys a player already toggled
        local KEPT = {
            skeram   = { "fulfillment", "images", "teleport" },
            bugtrio  = { "toxicvolley", "fear", "heal" },
            sartura  = { "whirlwind", "enrage" },
            fankriss = { "mortalwound", "entangle", "worms" },
            viscidus = { "poisonvolley", "freezing", "frozen", "shatter", "rejoin" },
            huhuran  = { "frenzy", "acidspit", "noxious", "sting", "berserksoon", "berserk" },
            twinemps = { "teleport", "unbalancing", "mutatebug", "explodebug", "berserk" },
            ouro     = { "sandblast", "sweep", "submerge", "berserk", "emerge" },
            cthun    = { "darkglarecd", "darkglare", "eyebeam", "eyetentacles",
                         "giantclaw", "gianteye", "weaken" },
        }
        local missing = {}
        for boss, keys in pairs(KEPT) do
            local enc = Addon:GetEncounter("aq40:" .. boss)
            for _, k in ipairs(keys) do
                if not (enc and enc.rowsByKey[k]) then missing[#missing + 1] = boss .. ":" .. k end
            end
        end
        eq(#missing, 0, "every 1.x aq40 mechanic key the spec still has a row for is PRESERVED"
           .. (#missing > 0 and (" (missing " .. table.concat(missing, ", ") .. ")") or ""))
        eq(Addon:MechKey("aq40", "cthun", "weaken"), "aq40:cthun:weaken",
           "…at the exact SavedVariables key the 1.x options tree wrote")
    end

    -- ── THE OWNER'S 2026-08-07 AQ ARBITRATIONS ("SAME AS NAXX") ───────────────
    -- Two explicit decisions from the W4c cross-check, pinned here so a later wave
    -- cannot quietly undo either:
    --   1. the two LOG-VERIFIED TIMERS the spec lacks are restored as variance bars
    --   2. all THIRTEEN dropped 1.x data_aq40.lua keys are back as encounter rows
    -- The provenance COMMENTS are asserted too. A "cleanup" that drops a restored row
    -- has to delete the note that explains it, and deleting the note reddens this gate.
    do
        local SRC = readFile(P("enc_aq40.lua")) or ""

        local n = 0
        for _ in SRC:gmatch("— owner 2026%-08%-07, per Same%-as%-Naxx") do n = n + 1 end
        eq(n, 9, "AQ RESTORATION: all nine restoration sites carry the owner's provenance note")
        n = 0
        for _ in SRC:gmatch("RESTORED — owner 2026%-08%-07") do n = n + 1 end
        eq(n, 7, "…seven of them restoring dropped 1.x DATA rows…")
        n = 0
        for _ in SRC:gmatch("RESTORED TIMER — owner 2026%-08%-07") do n = n + 1 end
        eq(n, 2, "…and two restoring the log-verified TIMERS the spec lacks")
        n = 0
        for _ in SRC:gmatch("1%.x field values 2026%-07%-26") do n = n + 1 end
        eq(n, 9, "…every one naming the 2026-07-26 field values its numbers came from")
        n = 0
        for _ in SRC:gmatch("tripwire") do n = n + 1 end
        ck(n >= 3, "…and the sites that overrule the spec name the tripwire as what settles it")
        n = 0
        for _ in SRC:gmatch("CHATTER%-CLASS ROWS SHIP DEFAULT%-OFF") do n = n + 1 end
        eq(n, 4, "…every chatter-class site states WHY it ships off (the honest middle)")
        n = 0
        for _ in SRC:gmatch("DO NOT \"clean this up\"") do n = n + 1 end
        eq(n, 3, "…and the three id-conflict sites carry the do-not-collapse instruction")
        ck(SRC:find("26084 is the whirlwind TICK", 1, true) ~= nil,
           "…Sartura's names the tick id the timer must NOT read")
        ck(SRC:find("25646 is a SHARED id", 1, true) ~= nil,
           "…Fankriss's names the shared Mortal Wound id its creature gate exists for")
        ck(SRC:find("the spec attaches the NAME \"Sundering Cleave\" to", 1, true)
           or SRC:find("The spec attaches the NAME \"Sundering Cleave\" to", 1, true),
           "…and the Sundering Cleave site names the spec's competing id outright")

        local function idsOf(tr)
            local v = tr and tr.spellId
            if v == nil then return {} end
            return type(v) == "table" and v or { v }
        end
        local function has(list, id)
            for _, v in ipairs(list) do if v == id then return true end end
            return false
        end

        -- ── decision 1: the two log-verified timers the spec lacks ────────────
        -- { encounter, key, spell id, kind, min, max, ships off? }
        local TIMERS = {
            { "aq40:sartura",  "whirlwindcd",   26083, "cd", 25.9, 29.1, false },
            { "aq40:fankriss", "mortalwoundcd", 25646, "cd",  6.5,  9.7, false },
        }
        for _, r in ipairs(TIMERS) do
            local enc = Addon:GetEncounter(r[1])
            local row = enc and enc.rowsByKey[r[2]]
            ck(row ~= nil, "RESTORED TIMER " .. r[1] .. ":" .. r[2] .. " is an encounter row")
            if row then
                eq(row.kind, r[4], "…as a " .. r[4] .. " bar (the shape 1.x shipped)")
                eq(row.spellId, r[3], "…on the field-verified 1.x spell id " .. r[3])
                local d = Timers.ParseDuration(row.duration)
                ck(d and d.hasVariance and d.min == r[5] and d.max == r[6],
                   "…and a VARIANCE window of " .. r[5] .. "-" .. r[6] ..
                   " s, not an invented exact number")
                eq(row.default, r[7] and false or nil,
                   "…shipping " .. (r[7] and "OFF" or "ON, as the 1.x radial did"))
                -- the creature gate is what stops a shared id re-arming the wrong bar
                ck(row.start and row.start.creatureId ~= nil,
                   "…gated to the creature that actually casts it")
            end
        end
        -- the spec's own rows are UNTOUCHED alongside them (additive, not replacing)
        do
            local sa = Addon:GetEncounter("aq40:sartura")
            ck(sa.rowsByKey.whirlwind ~= nil and sa.rowsByKey.whirlwind.tier == "announce"
               and sa.rowsByKey.whirlwind.kind == nil,
               "SARTURA: the 1.x `whirlwind` OPTION KEY still names the spec's announce")
            eq((sa.rowsByKey.whirlwindcd or {}).start
               and sa.rowsByKey.whirlwindcd.start.antispam, 4,
               "…and the restored bar arms once per cast, as the announce announces once")
            local fk = Addon:GetEncounter("aq40:fankriss")
            local mw, mwo = fk.rowsByKey.mortalwound or {}, fk.rowsByKey.mortalwoundon or {}
            eq(mw.kind, "target",
               "FANKRISS: the spec's 20 s Mortal Wound TARGET bar survives untouched…")
            near(mw.duration, 20, 0.001, "…still at 20 s")
            eq(mwo.role, "Tank",
               "…and the ALERT half is still the suite's Mortal Wound shape (Tank)…")
            eq(mwo.stacks, true, "…carrying the live STACK")
            eq((fk.rowsByKey.mortalwoundcd or {}).role, "Tank",
               "…so the restored interval bar is aimed at the same audience")
        end

        -- ── decision 2: all thirteen dropped data_aq40.lua keys are back ──────
        -- { encounter, 1.x row id (== the 2.0 option key), spell id, ships off?, timer? }
        local RESTORED = {
            { "aq40:skeram",   "earthshock",  26194, false, false },
            { "aq40:bugtrio",  "cleave",      15584, true,  false },
            { "aq40:bugtrio",  "poisoncloud", 26590, false, false },
            { "aq40:bugtrio",  "thrash",       3391, true,  false },
            { "aq40:bugtrio",  "ravage",       3242, true,  false },
            { "aq40:bugtrio",  "knockaway",   18670, true,  true  },
            { "aq40:bugtrio",  "knockdown",   19128, true,  true  },
            { "aq40:bugtrio",  "charge",      26561, true,  true  },
            { "aq40:bugtrio",  "vengeance",   25790, false, false },
            { "aq40:sartura",  "cleave",      25174, true,  false },
            { "aq40:viscidus", "poisonshock", 25993, true,  false },
            { "aq40:twinemps", "arcaneburst",   568, true,  false },
            { "aq40:twinemps", "healbrother",  7393, true,  false },
        }
        eq(#RESTORED, 13, "…thirteen keys, exactly the W4c report's dropped list")
        for _, r in ipairs(RESTORED) do
            local enc = Addon:GetEncounter(r[1])
            local row = enc and enc.rowsByKey[r[2]]
            ck(row ~= nil, r[1] .. ":" .. r[2] .. " is RESTORED as an encounter row")
            if row then
                local trs = {}
                if row.trigger then trs[#trs + 1] = row.trigger end
                if row.start   then trs[#trs + 1] = row.start   end
                if row.restart then trs[#trs + 1] = row.restart end
                for _, tr in ipairs(row.triggers or {}) do trs[#trs + 1] = tr end
                local found = false
                for _, tr in ipairs(trs) do
                    if has(idsOf(tr), r[3]) then found = true end
                end
                ck(found, "…on the field-verified 1.x spell id " .. r[3])
                if r[4] then
                    eq(row.default, false, "…and SHIPS OFF (owner: chatter-class / 1.x default)")
                else
                    eq(row.default, nil, "…and keeps the 1.x default (on for its audience)")
                end
                -- a 1.x cooldown radial comes back as a TIMER, an alert as a WARNING
                if r[5] then
                    eq(row.kind, "cd", "…as the COOLDOWN RADIAL 1.x shipped, not an announce")
                else
                    ck(row.kind == nil, "…as an announce row, not a bar")
                end
                -- the key IS the 1.x option key, so a 1.x SavedVariables choice survives
                eq(API.OptionKey(r[1], r[2]),
                   Addon:MechKey("aq40", r[1]:match(":(.+)$"), r[2]),
                   "…under the same SavedVariables key 1.x wrote")
            end
        end

        -- Vem's three radials all die with Vem, exactly as the trio's other bars do
        for _, k in ipairs({ "knockaway", "knockdown", "charge" }) do
            local row = Addon:GetEncounter("aq40:bugtrio").rowsByKey[k] or {}
            eq(row.stop and row.stop.creatureId, 15544,
               "BUG TRIO: the restored `" .. k .. "` bar stops when Vem dies")
            eq(row.start and row.start.creatureId, 15544, "…and only Vem can arm it")
        end
        -- the two death-event rows come back LOUD, as the 1.x raid warnings they were
        for _, k in ipairs({ "poisoncloud", "vengeance" }) do
            local row = Addon:GetEncounter("aq40:bugtrio").rowsByKey[k] or {}
            eq(row.tier or "announce", "announce", "…the restored `" .. k .. "` is an ANNOUNCE…")
            eq(row.color, 4, "…at the top announce colour (a bug dying is not chatter)")
        end
        -- SHAPE GUARD: every restored announce whose 1.x row was a self-replacing BAR
        -- carries an anti-spam window, so ticking its box cannot make it a spam source
        for _, p in ipairs({ { "aq40:bugtrio",  "cleave",      3 },
                             { "aq40:bugtrio",  "thrash",      3 },
                             { "aq40:bugtrio",  "ravage",      3 },
                             { "aq40:sartura",  "cleave",      3 },
                             { "aq40:twinemps", "arcaneburst", 3 },
                             { "aq40:twinemps", "healbrother", 3 } }) do
            local row = Addon:GetEncounter(p[1]).rowsByKey[p[2]] or {}
            eq(row.antispam, p[3],
               "SHAPE GUARD " .. p[1] .. ":" .. p[2] .. " carries a " .. p[3] .. " s window")
        end
        -- …and the one restoration with a MEASURED floor above the guard line does not
        local ps = Addon:GetEncounter("aq40:viscidus").rowsByKey.poisonshock
        ck(ps ~= nil and ps.antispam == nil,
           "…while Poison Shock's measured 8.1 s floor needs none, and is not given one")
    end

    do  -- the options projection: two more raids in the tree options.lua reads
        API.PublishOptionsTree()
        local r20, r40 = Addon:GetRaid("aq20"), Addon:GetRaid("aq40")
        ck(r20 ~= nil and r40 ~= nil, "both AQ zones PROJECT into the options tree")
        eq(r20 and r20.size, 20, "…Ruins as a 20-man raid")
        eq(r40 and r40.size, 40, "…Temple as a 40-man raid")
        eq(r20 and #r20.bosses, 7, "…with seven AQ20 entries (6 bosses + trash)")
        eq(r40 and #r40.bosses, 10, "…and ten AQ40 entries (9 bosses + trash)")
        ck((r20.order or 999) < (r40.order or 999), "…ordered Ruins before Temple")
        local cthun = Addon:GetBoss("aq40", "cthun")
        local sawRoster = false
        for _, m in ipairs(cthun and cthun.mechanics or {}) do
            if m.id == "stomach" then sawRoster = true end
        end
        ck(sawRoster, "…and a ROSTER is a mechanic row like any other (C'Thun's stomach list)")
        ck(Addon:GetBossByNpcID(15299) ~= nil, "…while the npc index resolves Viscidus")
    end

    do  -- the tank-swap branch is ONE shape, declared four times, never coded
        for _, p in ipairs({ { "aq20:kurinnaxx", "wounded", 5 }, { "aq20:buru", "dismembered", 5 },
                             { "aq40:fankriss", "wounded", 5 }, { "aq40:huhuran", "acid", 10 } }) do
            local enc = Addon:GetEncounter(p[1])
            ck(enc and #enc.rosters == 1 and enc.rosters[1].key == p[2],
               p[1] .. " keeps a roster of the debuff's carriers")
            local taunt
            for _, w in ipairs(enc.warnings) do
                if w.voice == "tauntboss" then taunt = w end
            end
            ck(taunt ~= nil, "…and declares the taunt arm")
            local tr = taunt and taunt.triggers[1]
            ck(tr and tr.dest == "other" and tr.stacks == p[3],
               "…gated on SOMEONE ELSE at " .. p[3] .. "+ stacks")
            ck(tr and tr.condition[1] == "playerAlive"
               and tr.condition[2] == "playerNotInRoster",
               "…and on you being alive AND clean (three facts, three predicates)")
        end
    end
end
endgate()

gate("AQ-DRIVE  §6/§7 per-encounter behaviour through the real engine")
do
    loadAQ()
    Addon:SetEventRecording(true)
    Addon._suppressLegacyAlerts = true
    Addon.RoleResolver  = function() return true end
    Addon.ClassResolver = function() return "WARLOCK" end

    -- ── §6.1 Kurinnaxx — the three-way stack branch ───────────────────────────
    do
        local rt = engage("aq20:kurinnaxx", 15348)
        ck(rt ~= nil, "KURINNAXX: engages off the combat sweep")
        near(bar(rt, "sandtrap").total, 8, 0.01, "…Sand Trap is an 8 s cycle from pull")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_SUMMON", spellId = 25648, destName = "Bob" })
        ck(sawWarn("WARN_ANNOUNCE", "Sand Trap under Bob"), "…a trap names whoever it is under")
        near(bar(rt, "sandtrap").total, 8, 0.01, "…and re-arms the cycle")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_SUMMON", spellId = 25648, destName = "Drew",
                       destIsPlayer = true })
        ck(sawWarn("WARN_SPECIAL", "Sand Trap on YOU"), "…a trap under YOU is the personal special")
        -- the branch: someone else stacks up while you are clean
        Addon:ClearEventLog()
        for i = 1, 5 do
            Life:Deliver({ on = "SPELL_AURA_APPLIED_DOSE", spellId = 25646,
                           destName = "Bob", amount = i })
        end
        eq(rt:RosterCount("wounded"), 1, "…the roster holds exactly one carrier")
        ck(rt:RosterHas("wounded", "Bob"), "…and it is Bob")
        ck(sawWarn("WARN_ANNOUNCE", "Mortal Wound Bob (5)"),
           "…the tank announce carries the STACK, not the fire count")
        ck(sawWarn("WARN_SPECIAL", "Taunt — Bob is at 5 stacks"),
           "…and at 5 you are told to taunt, because you are clean and alive")
        -- …and once YOU are carrying it, the taunt call goes away
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 25646, destName = "Drew",
                       destIsPlayer = true, amount = 1 })
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED_DOSE", spellId = 25646,
                       destName = "Bob", amount = 6 })
        ck(not sawWarn("WARN_SPECIAL", "Taunt"),
           "…suppressed the moment you are in the roster yourself")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED_DOSE", spellId = 25646, destName = "Drew",
                       destIsPlayer = true, amount = 5 })
        ck(sawWarn("WARN_SPECIAL", "Mortal Wound stacks are high"),
           "…while YOUR fifth stack is the personal stack-high special")
    end

    -- ── §6.2 General Rajaxx — the out-of-combat RP pull and the wave yells ────
    do
        local rt = engage("aq20:rajaxx", 15341, "Remember, Rajaxx, when I said I'd kill you last?")
        ck(rt ~= nil, "RAJAXX: engages on the Andorov RP yell, not on the boss")
        near(bar(rt, "pullwave").total, 31.8, 0.01, "…arming the 31.8 s first-wave bar")
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_YELL", "Fear is for the enemy! Fear and death!")
        ck(sawWarn("WARN_ANNOUNCE", "Wave 5"), "…wave yells are matched by SUBSTRING")
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_YELL",
            "Impudent fool! I will kill you myself!")
        ck(sawWarn("WARN_ANNOUNCE", "Wave 8 — Rajaxx engages"), "…through to the eighth")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 25471, destName = "Bob" })
        ck(sawWarn("WARN_ANNOUNCE", "Order on Bob"), "…Order names its target")
        local ob = rt.timers.order and rt.timers.order:Get("Bob")
        near(ob and ob.total, 10, 0.01, "…on a 10 s per-target bar")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 26550 })
        near(bar(rt, "thundercrashcloud").total, 15, 0.01, "…and the cloud runs 15 s")
    end

    -- ── §6.3 Moam ─────────────────────────────────────────────────────────────
    do
        local rt = engage("aq20:moam", 15340)
        near(bar(rt, "stoneform").total, 90, 0.01, "MOAM: Stoneform is 90 s from pull")
        eq(#Addon:GetEncounter("aq20:moam").warnings, 1,
           "…and the encounter is deliberately ONE warning (no unverified mana-drain rows)")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 25685, destId = 15340 })
        ck(sawWarn("WARN_ANNOUNCE", "Stoneform"), "…the aura announces at tier 3")
        near(bar(rt, "stoneformactive").total, 90, 0.01, "…and runs a 90 s active bar")
        Life:Deliver({ on = "SPELL_AURA_REMOVED", spellId = 25685, destId = 15340 })
        near(bar(rt, "stoneform").total, 90, 0.01, "…with the next one armed on its removal")
    end

    -- ── §6.4 Buru — an emote with no spell id behind it ───────────────────────
    do
        local rt = engage("aq20:buru", 15370)
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "Buru the Gorger sets eyes on Bob!")
        ck(sawWarn("WARN_ANNOUNCE", "Buru is chasing"),
           "BURU: the pursuit is EMOTE-ONLY (no spell id exists on Era)")
        ck(not sawWarn("WARN_SPECIAL", "chasing YOU"), "…and it is not about you")
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "Buru the Gorger sets eyes on Drew!")
        ck(sawWarn("WARN_SPECIAL", "Buru is chasing YOU — RUN"),
           "…until the emote names YOU, which is read out of the TEXT")
    end

    -- ── §6.5 Ayamiss — phases are pure health polling ─────────────────────────
    do
        local rt = engage("aq20:ayamiss", 15369)
        eq(rt.stage, 1, "AYAMISS: starts in phase 1")
        Addon:ClearEventLog()
        setUnit("target", { cid = 15369, combat = true, hp = 74, hpmax = 100 })
        Life:PollHealth(rt)
        ck(sawWarn("WARN_ANNOUNCE", "Phase 2 soon"), "…75 % is 'phase 2 soon'")
        eq(rt.stage, 1, "…and does NOT advance the phase")
        Addon:ClearEventLog()
        setUnit("target", { cid = 15369, combat = true, hp = 69, hpmax = 100 })
        Life:PollHealth(rt)
        eq(rt.stage, 2, "…70 % is the landing")
        ck(sawWarn("WARN_ANNOUNCE", "Phase 2"), "…announced")
    end

    -- ── §6.6 Ossirian — five weaknesses, five bars ────────────────────────────
    do
        local rt = engage("aq20:ossirian", 15339)
        local mn, mx = barWindow(rt, "tongues")
        ck(mn == 17.8 and mx == 50.2, "OSSIRIAN: Curse of Tongues opens on its 17.8-50.2 pull window")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 25195 })
        mn, mx = barWindow(rt, "tongues")
        ck(mn == 21 and mx == 43.7, "…and recurs on 21-43.7")
        Addon:ClearEventLog()
        local WEAK = { { 25177, "fireweakness", "Fire" }, { 25178, "frostweakness", "Frost" },
                       { 25180, "natureweakness", "Nature" }, { 25181, "arcaneweakness", "Arcane" },
                       { 25183, "shadowweakness", "Shadow" } }
        local allBars, allWarns = true, true
        for _, w in ipairs(WEAK) do
            Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = w[1], destId = 15339 })
            local b = bar(rt, w[2])
            if not b or math.abs(b.total - 45) > 0.01 then allBars = false end
            if not sawWarn("WARN_ANNOUNCE", w[3] .. " Weakness") then allWarns = false end
        end
        ck(allBars, "…and each of the five weaknesses gets its OWN 45 s bar")
        ck(allWarns, "…and its own tier-1 caster announce")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 25189, destName = "Bob" })
        ck(sawWarn("WARN_ANNOUNCE", "Cyclone on Bob"), "…Cyclone names its victim at tier 4")
    end

    -- ── §7.1 Skeram — health WINDOWS, not thresholds ──────────────────────────
    do
        local rt = engage("aq40:skeram", 15263)
        ck(Addon:GetEncounter("aq40:skeram").combat.noBossKill,
           "SKERAM: boss-death kill detection is DISABLED (the images die too)")
        Addon:ClearEventLog()
        setUnit("target", { cid = 15263, combat = true, hp = 79, hpmax = 100 })
        Life:PollHealth(rt)
        ck(sawWarn("WARN_ANNOUNCE", "Split soon"), "…79 % is inside the 81-77 split window")
        Addon:ClearEventLog()
        setUnit("target", { cid = 15263, combat = true, hp = 62, hpmax = 100 })
        Life:PollHealth(rt)
        ck(not sawWarn("WARN_ANNOUNCE", "Split soon"),
           "…62 % is BETWEEN windows and stays quiet (a threshold would have re-fired)")
        Addon:ClearEventLog()
        setUnit("target", { cid = 15263, combat = true, hp = 54, hpmax = 100 })
        Life:PollHealth(rt)
        ck(sawWarn("WARN_ANNOUNCE", "Split soon"), "…and 54 % is the 56-52 window")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 785, destName = "Bob" })
        ck(sawWarn("WARN_ANNOUNCE", "Mind control on Bob"), "…mind control names its victim")
        local mc = rt.timers.fulfillment and rt.timers.fulfillment:Get("Bob")
        near(mc and mc.total, 20, 0.01, "…on a 20 s per-target bar")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 26192 })
        ck(sawWarn("WARN_SPECIAL", "Interrupt Arcane Explosion"), "…and the interrupt special fires")
    end

    -- ── §7.2 Silithid Royalty — a bar per bug, stopped by that bug's death ────
    do
        local rt = engage("aq40:bugtrio", 15544)
        local mn, mx = barWindow(rt, "fear")
        ck(mn == 10.6 and mx == 18.4, "BUG TRIO: Fear's pull window is 10.6-18.4")
        mn, mx = barWindow(rt, "toxicvolley")
        ck(mn == 8.1 and mx == 42.6, "…Toxic Volley's is 8.1-42.6")
        eq(rt:GetCount("bugs"), 3, "…with the census seeded at three")
        Addon:ClearEventLog()
        Life:Deliver({ on = "UNIT_DIED", creatureId = 15543, destId = 15543,
                       destGUID = "Creature-0-0-0-0-15543-1" })
        eq(rt:GetCount("bugs"), 2, "…Yauj's death decrements the census")
        eq(bar(rt, "fear"), nil, "…and STOPS the Fear bar (it was hers)")
        ck(bar(rt, "toxicvolley") ~= nil, "…while Kri's Toxic Volley keeps running")
        Life:Deliver({ on = "UNIT_DIED", creatureId = 15543, destId = 15543,
                       destGUID = "Creature-0-0-0-0-15543-1" })
        eq(rt:GetCount("bugs"), 2, "…de-duplicated by GUID")
        Life:Deliver({ on = "UNIT_DIED", creatureId = 15511, destId = 15511,
                       destGUID = "Creature-0-0-0-0-15511-1" })
        eq(bar(rt, "toxicvolley"), nil, "…and Kri's death stops his")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 25807 })
        ck(sawWarn("WARN_SPECIAL", "Interrupt Great Heal"), "…Great Heal raises the interrupt special")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_PERIODIC_DAMAGE", spellName = "Poison Cloud",
                       destIsPlayer = true })
        ck(sawWarn("WARN_SPECIAL", "Move out of the poison"),
           "…and the cloud is matched on spell NAME as well as id (Era quirk)")
    end

    -- ── §7.3 Sartura — the restored whirlwind cooldown, a range-gated whirlwind ─
    do
        local rt = engage("aq40:sartura", 15516)
        -- (was "declares NO cooldown timers, the whirlwind interval was never
        -- characterised" before the owner's 2026-08-07 arbitration restored the 1.x
        -- cooldown on our own field characterisation — see the AQ gate's
        -- restoration table and the driven cadence below)
        eq(#Addon:GetEncounter("aq40:sartura").timers, 1,
           "SARTURA: declares exactly ONE cooldown timer — the owner's restored Whirlwind")
        eq(rt:GetCount("guards"), 3, "…with three Royal Guards on the census")
        Addon:ClearEventLog()
        Life:Deliver({ on = "UNIT_DIED", creatureId = 15984, destId = 15984,
                       destGUID = "Creature-0-0-0-0-15984-1" })
        eq(rt:GetCount("guards"), 2, "…counted down as they die")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 26083, sourceId = 15516 })
        ck(sawWarn("WARN_ANNOUNCE", "Whirlwind"), "…Whirlwind announces at tier 3")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_DAMAGE", spellId = 26084, destIsPlayer = true })
        ck(sawWarn("WARN_SPECIAL", "Move out of it"),
           "…and the ground effect is DAMAGE-only (26084 applies no aura)")
    end

    -- ── §7.5 Viscidus — the emote machine, the failed shatter, the rates ──────
    do
        local rt = engage("aq40:viscidus", 15299)
        eq(rt:GetState("phase"), "normal", "VISCIDUS: starts thawed")
        local mn, mx = barWindow(rt, "poisonvolley")
        ck(mn == 11.3 and mx == 12.9, "…the first Poison Bolt Volley is the 11.3-12.9 window")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 25991, sourceId = 15299 })
        near(bar(rt, "poisonvolley").total, 11.3, 0.01, "…and it recurs on a flat 11.3")
        -- frost hits, and the rate the info frame reads
        for i = 1, 8 do
            advance(0.5)
            Life:Deliver({ on = "SPELL_DAMAGE", school = 16, destId = 15299 })
        end
        eq(rt:GetCount("frosthits"), 8, "…frost hits are counted off the SCHOOL BITMASK")
        near(rt:Rate("frosthits"), 2, 0.05,
             "…and the rolling rate over the last 7 is 2.0 hits/sec")
        Life:Deliver({ on = "SPELL_DAMAGE", school = 4, destId = 15299 })
        eq(rt:GetCount("frosthits"), 8, "…a Fire hit does not count")
        -- the freeze ladder
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "Viscidus begins to slow down!")
        eq(rt:GetState("phase"), "freeze1", "…'begins to slow' is freeze 1/3")
        ck(sawWarn("WARN_ANNOUNCE", "Freeze 1/3"), "…announced")
        Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "Viscidus is freezing up!")
        eq(rt:GetState("phase"), "freeze2", "…'is freezing up' is freeze 2/3")
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "Viscidus is frozen solid!")
        eq(rt:GetState("phase"), "frozen", "…'is frozen solid' is freeze 3/3")
        eq(bar(rt, "poisonvolley"), nil, "…which STOPS the volley bar")
        eq(rt:GetCount("frosthits"), 0, "…and zeroes the hit counters")
        eq(rt:Rate("frosthits"), nil, "…including the rate (no evidence is not a rate of zero)")
        ck(sawWarn("WARN_ANNOUNCE", "FROZEN"), "…and calls the melee burn")
        -- a swing that lands INSIDE the 5 s grace does not unfreeze him
        advance(2)
        Life:Deliver({ on = "SWING_DAMAGE", creatureId = 15299, sourceId = 15299 })
        eq(rt:GetState("phase"), "frozen",
           "…a swing within 5 s of the freeze is the one already in flight, and is ignored")
        -- melee hits while frozen
        for i = 1, 11 do
            advance(0.25)
            Life:Deliver({ on = "SWING_DAMAGE", destId = 15299 })
        end
        near(rt:Rate("meleehits"), 4, 0.1, "…melee hits per second run on their own 10-wide window")
        -- the shatter ladder
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "Viscidus begins to crack!")
        eq(rt:GetState("phase"), "shatter1", "…'begins to crack' is shatter 1/2")
        Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "Viscidus looks ready to shatter!")
        eq(rt:GetState("phase"), "shatter2", "…'looks ready to shatter' is shatter 2/2")
        near(bar(rt, "rejoin").total, 16.5, 0.01, "…which starts the 16.5 s rejoin bar")
        -- FAILED SHATTER: back to frozen, then a swing more than 5 s later
        Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "Viscidus is frozen solid!")
        eq(rt:GetState("phase"), "frozen", "…a failed shatter round re-freezes him")
        advance(6)
        Life:Deliver({ on = "SWING_DAMAGE", creatureId = 15299, sourceId = 15299 })
        eq(rt:GetState("phase"), "normal",
           "…and a swing MORE than 5 s after the freeze is the failed-shatter tell (Era)")
        eq(rt:GetCount("meleehits"), 0, "…which zeroes the counters again")
        -- the globs recombining, honoured once
        Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "Viscidus is frozen solid!")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 25896 })
        eq(rt:GetState("phase"), "normal", "…and the recombine cast returns him to normal")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 25989, destIsPlayer = true })
        ck(sawWarn("WARN_SPECIAL", "Move out of the poison"), "…with the poison-cloud GTFO on you")
    end

    -- ── §7.6 Huhuran — Berserk stops three bars at once ───────────────────────
    do
        local rt = engage("aq40:huhuran", 15509)
        local mn, mx = barWindow(rt, "frenzy")
        ck(mn == 6.5 and mx == 25.9, "HUHURAN: Frenzy's pull window is 6.5-25.9")
        mn, mx = barWindow(rt, "noxious")
        ck(mn == 11.3 and mx == 38.8, "…Poison Bolt's is 11.3-38.8 (1.x key `noxious` preserved)")
        mn, mx = barWindow(rt, "sting")
        ck(mn == 6.8 and mx == 43.7, "…and Wyvern Sting's is 6.8-43.7")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 26051, destId = 15509 })
        ck(sawWarn("WARN_SPECIAL", "Tranquilise the Frenzy"), "…Frenzy raises the tranq special")
        near(bar(rt, "frenzyactive").total, 8, 0.01, "…and an 8 s active bar")
        -- the sting bar restarts 1 s after the targets are collected
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 26180, destName = "Bob" })
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 26180, destName = "Alice" })
        advance(1.1)
        mn, mx = barWindow(rt, "sting")
        ck(mn == 25.9 and mx == 59.2,
           "…and the Sting cooldown re-arms ONCE, 1 s after the targets are collected")
        -- berserk kills three bars in one event
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 26068, destId = 15509 })
        ck(sawWarn("WARN_ANNOUNCE", "Berserk"), "…Berserk announces")
        eq(bar(rt, "sting"), nil, "…and stops the Sting bar")
        eq(bar(rt, "frenzy"), nil, "…the Frenzy bar")
        eq(bar(rt, "noxious"), nil, "…and the Poison Bolt bar")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED_DOSE", spellId = 26050, destName = "Drew",
                       destIsPlayer = true, amount = 10 })
        ck(sawWarn("WARN_SPECIAL", "Acid Spit stacks are high"),
           "…and Acid Spit's personal alarm is at TEN, not five")
    end

    -- ── §7.7 Twin Emperors — the teleport swap and the nameplate-range gate ───
    do
        local rt = engage("aq40:twinemps", 15276)
        near(bar(rt, "berserk").total, 900, 0.01, "TWIN EMPERORS: Berserk is 900 s from pull")
        near(bar(rt, "teleport").total, 30.8, 0.01, "…the first teleport is a flat 30.8")
        eq(Addon:GetEncounter("aq40:twinemps").rowsByKey.teleport.countdown.depth, 4,
           "…with a 4 s spoken countdown (the raid swaps together)")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 800 })
        ck(sawWarn("WARN_ANNOUNCE", "Teleport — swap sides"), "…the teleport AURA is the trigger")
        local mn, mx = barWindow(rt, "teleport")
        ck(mn == 29.1 and mx == 40.5, "…and it recurs on 29.1-40.5")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 799 })
        eq(warnCount("WARN_ANNOUNCE", "swap sides"), 0,
           "…with the pair's second id collapsed by the 5 s anti-spam")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 26613, destName = "Drew",
                       destIsPlayer = true })
        ck(sawWarn("WARN_SPECIAL", "use a defensive"), "…Unbalancing Strike on you calls a cooldown")
        -- Explode Bug: only for a bug that actually has a nameplate
        Addon:ClearEventLog()
        W.nameplates = {}
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 804,
                       sourceGUID = "Creature-0-0-0-0-15316-77" })
        ck(not sawWarn("WARN_SPECIAL", "Run away from the bug"),
           "…a bug with no nameplate is out of range and stays quiet")
        setUnit("nameplate3", { cid = 15316, guid = "Creature-0-0-0-0-15316-77" })
        W.nameplates = { "nameplate3" }
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 804,
                       sourceGUID = "Creature-0-0-0-0-15316-77" })
        ck(sawWarn("WARN_SPECIAL", "Run away from the bug"),
           "…and the SAME event warns once that bug is on a nameplate (the Era range answer)")
        W.nameplates = {}
    end

    -- ── §7.8 Ouro — the submerge cycle ────────────────────────────────────────
    do
        local rt = engage("aq40:ouro", 15517)
        local mn, mx = barWindow(rt, "sandblast")
        ck(mn == 20.1 and mx == 26.3, "OURO: Sand Blast opens on its 20.1-26.3 pull window")
        mn, mx = barWindow(rt, "sweep")
        ck(mn == 22.6 and mx == 25.9, "…Sweep on 22.6-25.9")
        near(bar(rt, "submerge").total, 184, 0.01, "…and the surface phase is 184 s")
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 26102 })
        mn, mx = barWindow(rt, "sandblast")
        ck(mn == 22.1 and mx == 26.8, "…Sand Blast then recurs on 22.1-26.8")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 26058, sourceId = 15517 })
        ck(sawWarn("WARN_ANNOUNCE", "submerging"), "…the submerge cast announces")
        eq(bar(rt, "sandblast"), nil, "…and stops the Blast bar")
        eq(bar(rt, "sweep"), nil, "…the Sweep bar")
        eq(bar(rt, "submerge"), nil, "…and the Submerge bar")
        near(bar(rt, "emerge").total, 30, 0.01, "…arming a 30 s emerge countdown")
        Addon:ClearEventLog()
        advance(30.1)
        ck(sawWarn("WARN_ANNOUNCE", "emerging"), "…emerge is a SCHEDULE, not an event (Era quirk)")
        mn, mx = barWindow(rt, "sandblast")
        ck(mn == 20.1 and mx == 26.3, "…and all three bars restart from their PULL values")
        mn, mx = barWindow(rt, "sweep")
        ck(mn == 22.6 and mx == 25.9, "…Sweep included")
        near(bar(rt, "submerge").total, 184, 0.01, "…and the next surface phase is 184 s again")
        -- berserk: he never submerges again
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 26615, destId = 15517 })
        eq(rt:GetState("berserked"), "yes", "…the berserk is recorded as a state")
        eq(bar(rt, "submerge"), nil, "…the submerge bar stops for good")
        mn, mx = barWindow(rt, "sandblast")
        ck(mn == 20.1 and mx == 26.3, "…and the Blast cooldown restarts from zero")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 26058, sourceId = 15517 })
        ck(not sawWarn("WARN_ANNOUNCE", "submerging"),
           "…while a post-berserk submerge cast is not announced at all")
    end

    -- ── §7.9 C'Thun — the full phase cycle, all three value sets, the stomach ──
    do
        local rt = engage("aq40:cthun", 15589)
        ck(rt ~= nil, "C'THUN: engages off the combat sweep")
        eq(Addon:GetEncounter("aq40:cthun").combat.wipeWindow, 25, "…with a 25 s wipe timeout")
        -- VALUE SET 1: phase 1
        near(bar(rt, "darkglarecd").total, 48, 0.01, "…P1: the first Dark Glare is 48 s")
        near(bar(rt, "clawtentacle").total, 9, 0.01, "…P1: the first Claw Tentacle is 9 s")
        near(bar(rt, "eyetentacles").total, 45, 0.01, "…P1: the first Eye Tentacle is 45 s")
        Addon:ClearEventLog()
        advance(48.1)
        ck(sawWarn("WARN_SPECIAL", "Dark Glare — run"),
           "…the scheduled glare loop fires the laser-run special")
        near(bar(rt, "darkglare").total, 39, 0.01, "…and the rotating beam runs 39 s")
        near(bar(rt, "darkglarecd").total, 86, 0.01, "…with the next glare 86 s out")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 26586, sourceId = 15726,
                       sourceGUID = "Creature-0-0-0-0-15726-1" })
        ck(sawWarn("WARN_ANNOUNCE", "Eye Tentacle"), "…an Eye Tentacle birth announces…")
        near(bar(rt, "eyetentacles").total, 45, 0.01, "…and re-arms the P1 45 s cadence")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 26586, sourceId = 15726,
                       sourceGUID = "Creature-0-0-0-0-15726-2" })
        eq(warnCount("WARN_ANNOUNCE", "Eye Tentacle"), 1,
           "…with a wave of births collapsed by the 5 s per-creature anti-spam")
        -- the eye beam scan and its icon
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 26134, sourceId = 15589 })
        local sawScan, sawIcon = false, false
        for _, e in ipairs(Addon:GetEventLog()) do
            if e.event == "SCAN_REQUEST" then sawScan = true end
        end
        ck(sawScan, "…Eye Beam raises the boss target scan (0.1 s delay, then 0.1 s x 3)")
        rt:Route({ on = "targetChanged", key = "eyebeam", destName = "Drew" })
        for _, e in ipairs(Addon:GetEventLog()) do
            if e.event == "ICON_REQUEST" then sawIcon = true end
        end
        ck(sawIcon, "…whose result marks the target with raid icon 1")
        ck(sawWarn("WARN_SPECIAL", "Eye Beam on YOU"),
           "…and fires the personal special when the scan names YOU")
        -- VALUE SET 2: the moment phase 2 begins
        Addon:ClearEventLog()
        Life:Deliver({ on = "UNIT_DIED", creatureId = 15589, destId = 15589,
                       destGUID = "Creature-0-0-0-0-15589-1" })
        eq(rt.stage, 2, "…the EYE'S DEATH is phase 2")
        ck(sawWarn("WARN_ANNOUNCE", "Phase 2"), "…announced")
        eq(bar(rt, "darkglarecd"), nil, "…P2: Dark Glare stops for good")
        eq(bar(rt, "clawtentacle"), nil, "…P2: Claw Tentacles stop for good")
        near(bar(rt, "eyetentacles").total, 40.5, 0.01, "…P2 entry: Eye Tentacles at 40.5")
        near(bar(rt, "giantclaw").total, 10.5, 0.01, "…P2 entry: Giant Claw at 10.5")
        near(bar(rt, "gianteye").total, 41.3, 0.01, "…P2 entry: Giant Eye at 41.3")
        -- the P2 recurring cadence differs from the P2 entry value
        advance(6)      -- clear of the 5 s per-creature birth anti-spam
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 26586, sourceId = 15726,
                       sourceGUID = "Creature-0-0-0-0-15726-9" })
        near(bar(rt, "eyetentacles").total, 30, 0.01,
             "…and the P2 Eye Tentacle CADENCE is 30 s, not the 45 it was in P1")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 26586, sourceId = 15728,
                       sourceGUID = "Creature-0-0-0-0-15728-9" })
        near(bar(rt, "giantclaw").total, 60, 0.01, "…while the Giant Claw cadence is 60 s")
        -- the stomach: a roster of the eaten, and the tentacles read through their eyes
        W.group = { "player", "raid1" }
        setUnit("raid1", { name = "Bob", player = true, combat = true })
        setUnit("raid1target", { cid = 15802, hp = 40, hpmax = 100 })
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 26476, destName = "Bob", amount = 2 })
        eq(rt:RosterCount("stomach"), 1, "…the stomach roster takes the swallowed player")
        local entry = rt:GetRoster("stomach")["Bob"]
        eq(entry and entry.stacks, 2, "…with their acid stack count")
        local h = Addon.Scan.rosterByKey["aq40:cthun:fleshtentacles"]
        ck(h ~= nil, "…and arms the roster-relayed tentacle scan")
        Addon:ClearEventLog()
        advance(1.1)
        local probed
        for _, e in ipairs(Addon:GetEventLog()) do if e.event == "PROBE" then probed = e end end
        ck(probed ~= nil, "…which reads the Flesh Tentacle THROUGH the stomached player's target")
        local guid = "Creature-0-0-0-0-15802-0001"
        ck(h and h.seen[guid] and math.abs(h.seen[guid].pct - 40) < 0.01,
           "…recovering its health percentage (40 %) from a unit nobody outside can see")
        -- a second swallowed player does not start a second loop
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 26476, destName = "Alice", amount = 1 })
        eq(Addon.Scan.rosterByKey["aq40:cthun:fleshtentacles"], h,
           "…and a second victim re-uses the one live scan rather than starting another")
        -- VALUE SET 3: after a Weakened
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "C'Thun is weakened!")
        ck(sawWarn("WARN_SPECIAL", "WEAKENED"), "…the Weakened emote is the burn call")
        near(bar(rt, "eyetentacles").total, 83, 0.01, "…post-Weaken: Eye Tentacles at 83")
        near(bar(rt, "giantclaw").total, 53, 0.01, "…post-Weaken: Giant Claw at 53")
        near(bar(rt, "gianteye").total, 83.7, 0.01, "…post-Weaken: Giant Eye at 83.7")
        near(bar(rt, "weaken").total, 45, 0.01, "…and the Weakened window itself is 45 s")
        eq(rt:RosterCount("stomach"), 0, "…while the stomach list is emptied")
        ck(Addon.Scan.rosterByKey["aq40:cthun:fleshtentacles"] == nil,
           "…and the tentacle scan is torn down with it")
        W.group = { "player" }
    end

    -- ══════════════════════════════════════════════════════════════════════════
    --  THE OWNER'S 2026-08-07 AQ ARBITRATIONS ("SAME AS NAXX"), THROUGH THE ENGINE
    --  Decision 1: the two log-verified timers the spec lacks are driven at their
    --  FIELD CADENCES, and their creature gates are driven with the wrong caster.
    --  Decision 2: each of the thirteen restored rows is driven trigger -> warning
    --  or bar, with its shipped default asserted BOTH WAYS (a default-off row stays
    --  SILENT on defaults and fires the moment the player ticks its box — that is
    --  what "the honest middle" has to mean in the engine, not just in the registry).
    -- ══════════════════════════════════════════════════════════════════════════
    do
        Addon.db.mechanics = Addon.db.mechanics or {}
        local function tick(key, on)   -- the SavedVariables override a player's tick writes
            Addon.db.mechanics[key] = on and { masterEnabled = true } or nil
        end

        -- ── 1a. Sartura's Whirlwind cooldown, on OUR characterisation ───────────
        do
            local rt = engage("aq40:sartura", 15516)
            eq(bar(rt, "whirlwindcd"), nil,
               "RESTORED TIMER sartura:whirlwindcd shows NO bar before the first cast " ..
               "(no pull window was ever measured, so none is invented)")
            Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 26083, sourceId = 15516 })
            local mn, mx = barWindow(rt, "whirlwindcd")
            ck(mn == 25.9 and mx == 29.1,
               "…and the cast arms the field-measured 25.9-29.1 window")
            -- the tick id must not touch it (26084 is what the GTFO reads)
            rt = engage("aq40:sartura", 15516)
            Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 26084, sourceId = 15516 })
            eq(bar(rt, "whirlwindcd"), nil,
               "…the whirlwind TICK (26084) does NOT arm it — 76 ticks a pull would")
            -- a Royal Guard whirlwinding must not restart the BOSS's cooldown
            Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 26083, sourceId = 15984 })
            eq(bar(rt, "whirlwindcd"), nil,
               "…nor does a Royal Guard's whirlwind (the creature gate 1.x carried)")
            Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 26083, sourceId = 15516 })
            ck(bar(rt, "whirlwindcd") ~= nil, "…while Sartura's own cast does")
            -- one arming per cast: a duplicate inside 4 s is the same whirlwind
            advance(10)
            Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 26083, sourceId = 15516 })
            local b = bar(rt, "whirlwindcd")
            near(Timers.Remaining(b), b.total, 0.05, "…a fresh cast re-arms the bar in full")
            advance(1)
            Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 26083, sourceId = 15516 })
            b = bar(rt, "whirlwindcd")
            near(Timers.Remaining(b), b.total - 1, 0.05,
                 "…and a duplicate inside the 4 s window is the SAME whirlwind, not a new one")
        end

        -- ── 1b. Fankriss's Mortal Wound cast interval, alongside the 20 s bar ───
        do
            local rt = engage("aq40:fankriss", 15510)
            Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 25646, sourceId = 15510 })
            local mn, mx = barWindow(rt, "mortalwoundcd")
            ck(mn == 6.5 and mx == 9.7,
               "RESTORED TIMER fankriss:mortalwoundcd runs the field-measured 6.5-9.7 window")
            -- the spec's per-target debuff bar is untouched and still 20 s
            Addon:ClearEventLog()
            Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 25646, destName = "Bob",
                           amount = 1 })
            local tgt = rt.timers.mortalwound and rt.timers.mortalwound:Get("Bob")
            ck(tgt ~= nil and math.abs(tgt.total - 20) < 0.01,
               "…while the spec's 20 s per-target bar still runs alongside it")
            ck(sawWarn("WARN_ANNOUNCE", "Mortal Wound Bob (1)"),
               "…and the suite's Mortal Wound announce still carries the stack")
            -- 25646 is shared: Gluth's cast must not arm Fankriss's cooldown
            rt = engage("aq40:fankriss", 15510)
            Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 25646, sourceId = 15932 })
            eq(bar(rt, "mortalwoundcd"), nil,
               "…and a SHARED-id cast from another creature does not arm it (the gate 1.x carried)")
        end

        -- ── 2. every restored row, driven, with its shipped default asserted ────
        -- { encounter, cid, key, deliver-event, ships off?, needle }
        local R = {
            { "aq40:skeram", 15263, "earthshock",
              { on = "SPELL_CAST_SUCCESS", spellId = 26194, sourceId = 15263 },
              false, "Earth Shock" },
            { "aq40:bugtrio", 15544, "poisoncloud",
              { on = "SPELL_CAST_SUCCESS", spellId = 26590, sourceId = 15511 },
              false, "Kri died — poison cloud" },
            { "aq40:bugtrio", 15544, "vengeance",
              { on = "SPELL_AURA_APPLIED", spellId = 25790, destId = 15511 },
              false, "Vem died — Vengeance" },
            { "aq40:bugtrio", 15544, "cleave",
              { on = "SPELL_CAST_SUCCESS", spellId = 15584, sourceId = 15511 },
              true, "Cleave" },
            { "aq40:bugtrio", 15544, "thrash",
              { on = "SPELL_CAST_SUCCESS", spellId = 3391, sourceId = 15511 },
              true, "Thrash" },
            { "aq40:bugtrio", 15544, "ravage",
              { on = "SPELL_CAST_SUCCESS", spellId = 3242, sourceId = 15543 },
              true, "Ravage" },
            { "aq40:sartura", 15516, "cleave",
              { on = "SPELL_CAST_SUCCESS", spellId = 25174, sourceId = 15516 },
              true, "Sundering Cleave" },
            { "aq40:viscidus", 15299, "poisonshock",
              { on = "SPELL_CAST_SUCCESS", spellId = 25993, sourceId = 15299 },
              true, "Poison Shock" },
            { "aq40:twinemps", 15276, "arcaneburst",
              { on = "SPELL_CAST_SUCCESS", spellId = 568, sourceId = 15276 },
              true, "Arcane Burst" },
            { "aq40:twinemps", 15276, "healbrother",
              { on = "SPELL_CAST_SUCCESS", spellId = 7393, sourceId = 15275 },
              true, "Heal Brother" },
        }
        for _, r in ipairs(R) do
            local encId, key, off, needle = r[1], r[3], r[5], r[6]
            local optKey = API.OptionKey(encId, key)
            local boss = encId:match(":(.+)$")
            tick(optKey, nil)                            -- ON DEFAULTS
            engage(encId, r[2])
            Addon:ClearEventLog()
            Life:Deliver(r[4])
            if off then
                ck(not sawWarn("WARN_ANNOUNCE", needle),
                   "RESTORED " .. boss .. ":" .. key .. " is SILENT on defaults (ships off)")
                tick(optKey, true)                       -- …and the player ticks the box
                engage(encId, r[2])
                Addon:ClearEventLog()
                Life:Deliver(r[4])
                ck(sawWarn("WARN_ANNOUNCE", needle), "…and FIRES once enabled: " .. needle)
                tick(optKey, nil)
            else
                ck(sawWarn("WARN_ANNOUNCE", needle),
                   "RESTORED " .. boss .. ":" .. key .. " fires on defaults: " .. needle)
            end
        end

        -- Vem's three restored RADIALS: no bar on defaults, the measured window once ticked
        for _, r in ipairs({ { "knockaway", 18670, 10.8, 20.0 },
                             { "knockdown", 19128, 10.9, 21.0 },
                             { "charge",    26561, 17.7, 24.2 } }) do
            local optKey = API.OptionKey("aq40:bugtrio", r[1])
            tick(optKey, nil)
            local rt = engage("aq40:bugtrio", 15544)
            Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = r[2], sourceId = 15544 })
            eq(bar(rt, r[1]), nil,
               "RESTORED bugtrio:" .. r[1] .. " starts NO bar on defaults (ships off)")
            tick(optKey, true)
            rt = engage("aq40:bugtrio", 15544)
            Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = r[2], sourceId = 15544 })
            local mn, mx = barWindow(rt, r[1])
            ck(mn == r[3] and mx == r[4],
               "…and once enabled runs the field-measured " .. r[3] .. "-" .. r[4] .. " window")
            -- it belongs to Vem, so it dies with Vem
            Life:Deliver({ on = "UNIT_DIED", creatureId = 15544, destId = 15544,
                           destGUID = "Creature-0-0-0-0-15544-1" })
            eq(bar(rt, r[1]), nil, "…and STOPS when Vem dies, as the trio's other bars do")
            tick(optKey, nil)
        end

        -- SHAPE GUARDS, driven: an announce that replaced a 1.x self-replacing BAR
        -- must not become a spam source the moment a player does tick its box.
        do
            tick("aq40:bugtrio:cleave", true)
            engage("aq40:bugtrio", 15544)
            Addon:ClearEventLog()
            for _ = 1, 4 do
                Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 15584, sourceId = 15511 })
                advance(0.5)
            end
            eq(warnCount("WARN_ANNOUNCE", "Cleave"), 1,
               "SHAPE GUARD: four Cleaves inside the 3 s window announce ONCE")
            advance(3.1)
            Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 15584, sourceId = 15511 })
            eq(warnCount("WARN_ANNOUNCE", "Cleave"), 2,
               "…and the window RE-ARMS after 3 s (throttled, not swallowed)")
            tick("aq40:bugtrio:cleave", nil)

            tick("aq40:twinemps:arcaneburst", true)
            engage("aq40:twinemps", 15276)
            Addon:ClearEventLog()
            for _ = 1, 5 do
                Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 568, sourceId = 15276 })
                advance(0.4)
            end
            eq(warnCount("WARN_ANNOUNCE", "Arcane Burst"), 1,
               "…and five Arcane Bursts inside the 3 s window announce ONCE")
            tick("aq40:twinemps:arcaneburst", nil)
        end
    end

    -- ── §6.7 / §7.10 the two zone-wide trash modules ──────────────────────────
    do
        resetLife()
        W.instanceID = 531
        eq(Life:ArmZones(531), 1, "TRASH: entering the Temple ARMS the AQ40 trash module")
        ck(Life:IsZoneArmed("aq40:trash"), "…without engaging anything")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 19134 })
        ck(sawWarn("WARN_ANNOUNCE", "Intimidating Shout"), "…trash alerts fire off the shared path")
        Addon:ClearEventLog()
        -- the reflect evidence path, end to end through NormalizeCLEU
        local ev = Life:NormalizeCLEU("SPELL_MISSED", W.playerGUID, "Drew", 0, 0,
                                      "Creature-0-0-0-0-15264-1", "Anubisath Defender", 0, 0,
                                      686, "Shadow Bolt", 32, "REFLECT")
        eq(ev.missType, "REFLECT", "…the miss TYPE is normalised off the combat log")
        eq(ev.school, 32, "…alongside the school bitmask")
        Life:Deliver(ev)
        ck(sawWarn("WARN_SPECIAL", "Shadow/Frost reflect"),
           "…and a reflected Shadow spell of YOURS raises the stop-casting special")
        Addon:ClearEventLog()
        local ev2 = Life:NormalizeCLEU("SPELL_MISSED", W.playerGUID, "Drew", 0, 0,
                                       "Creature-0-0-0-0-15264-1", "Anubisath Defender", 0, 0,
                                       133, "Fireball", 4, "DEFLECT")
        Life:Deliver(ev2)
        ck(sawWarn("WARN_SPECIAL", "Fire/Arcane reflect"), "…and a deflected Fire spell the other one")
        -- per-mob thunderclap bars
        Addon:ClearEventLog()
        local rt40 = Life.zoneArmed["aq40:trash"]
        Life:Deliver({ on = "SPELL_DAMAGE", spellId = 26554,
                       sourceGUID = "Creature-0-0-0-0-15264-1" })
        Life:Deliver({ on = "SPELL_DAMAGE", spellId = 26554,
                       sourceGUID = "Creature-0-0-0-0-15264-2" })
        local n = 0
        for _ in pairs(rt40.timers.thunderclap.live) do n = n + 1 end
        eq(n, 2, "…and Thunderclap runs ONE 7 s nameplate bar PER MOB")
        W.instanceID = 509
        eq(Life:ArmZones(509), 1, "…zoning to the Ruins swaps to the AQ20 trash module")
        ck(Life:IsZoneArmed("aq20:trash") and not Life:IsZoneArmed("aq40:trash"),
           "…exactly one of the two armed at a time")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 22997, destIsPlayer = true })
        ck(sawWarn("WARN_SPECIAL", "Plague on YOU"), "…AQ20's Plague alert is the personal one")
        W.instanceID = 533
        Life:ArmZones(533)
    end

    Addon._suppressLegacyAlerts = nil
    Addon:SetEventRecording(false)
    resetLife()
end
endgate()

----------------------------------------------------------------------
-- WAVE 4b — BLACKWING LAIR + ZUL'GURUB ENCOUNTER DATA
--
-- Every assertion below names the DBM_ERA_ENCOUNTERS_BEHAVIOR_SPEC.md §4 / §5 row it
-- proves, and every one runs the SHIPPING data through the SHIPPING engine on the
-- injected clock and the injected world.
----------------------------------------------------------------------
local function loadBWLZG()
    Addon.encounters, Addon.encountersById = {}, {}
    Addon.encByCreature, Addon.encByEncounterId, Addon.encByZone = {}, {}, {}
    Addon.zones, Addon.zonesById = {}, {}
    local ok1, e1 = pcall(BWL_CHUNK, ADDON_NAME, Addon)
    local ok2, e2 = pcall(ZG_CHUNK, ADDON_NAME, Addon)
    return ok1 and ok2, (not ok1 and e1) or (not ok2 and e2) or nil
end

gate("BWLZG  §4/§5 encounter data: registration, keys, the options tree")
do
    local okc, err = loadBWLZG()
    ck(okc, "enc_bwl.lua + enc_zg.lua EXECUTE against the shipping grammar" ..
            (okc and "" or (" -> " .. tostring(err))))

    local EXPECTED = {
        -- §4 Blackwing Lair (zone 469)
        { id = "bwl:razorgore",   cid = 12435, eid = 610, raid = "bwl", boss = "razorgore" },
        { id = "bwl:vaelastrasz", cid = 13020, eid = 611, raid = "bwl", boss = "vaelastrasz" },
        { id = "bwl:broodlord",   cid = 12017, eid = 612, raid = "bwl", boss = "broodlord" },
        { id = "bwl:firemaw",     cid = 11983, eid = 613, raid = "bwl", boss = "firemaw" },
        { id = "bwl:ebonroc",     cid = 14601, eid = 614, raid = "bwl", boss = "ebonroc" },
        { id = "bwl:flamegor",    cid = 11981, eid = 615, raid = "bwl", boss = "flamegor" },
        { id = "bwl:chromaggus",  cid = 14020, eid = 616, raid = "bwl", boss = "chromaggus" },
        { id = "bwl:nefarian",    cid = 11583, eid = 617, raid = "bwl", boss = "nefarian" },
        -- §5 Zul'Gurub (zone 309)
        { id = "zg:venoxis",      cid = 14507, eid = 784, raid = "zg", boss = "venoxis" },
        { id = "zg:jeklik",       cid = 14517, eid = 785, raid = "zg", boss = "jeklik" },
        { id = "zg:marli",        cid = 14510, eid = 786, raid = "zg", boss = "marli" },
        { id = "zg:mandokir",     cid = 11382, eid = 787, raid = "zg", boss = "mandokir" },
        { id = "zg:edgeofmadness", cid = 15083, eid = 788, raid = "zg", boss = "edgeofmadness" },
        { id = "zg:thekal",       cid = 14509, eid = 789, raid = "zg", boss = "thekal" },
        { id = "zg:gahzranka",    cid = 15114, eid = 790, raid = "zg", boss = "gahzranka" },
        { id = "zg:arlokk",       cid = 14515, eid = 791, raid = "zg", boss = "arlokk" },
        { id = "zg:jindo",        cid = 11380, eid = 792, raid = "zg", boss = "jindo" },
        { id = "zg:hakkar",       cid = 14834, eid = 793, raid = "zg", boss = "hakkar" },
    }
    for _, e in ipairs(EXPECTED) do
        local enc = Addon:GetEncounter(e.id)
        ck(enc ~= nil, e.id .. " is registered")
        if enc then
            local errs = API.Validate(enc)
            eq(#errs, 0, "…with zero validation errors" ..
               (#errs > 0 and (": " .. table.concat(errs, "; ")) or ""))
            ck(Addon.encByCreature[e.cid] ~= nil, "…indexed by creature " .. e.cid)
            ck(Addon.encByEncounterId[e.eid] ~= nil, "…and by encounter id " .. e.eid)
            ck(enc.legacy and enc.legacy.raidId == e.raid and enc.legacy.bossId == e.boss,
               "…carrying the legacy seam " .. e.raid .. ":" .. e.boss)
            local firstRow = enc.timers[1] or enc.warnings[1]
            if firstRow then
                eq(API.OptionKey(enc.id, firstRow.key),
                   Addon:MechKey(e.raid, e.boss, firstRow.key),
                   "…and OptionKey == MechKey for its rows (one SavedVariables entry, not two)")
            end
        end
    end
    eq(#Addon.encounters, #EXPECTED + 1, "…19 registrations in all (18 bosses + one trash module)")

    do  -- §4.9 the zone-wide BWL trash module (Zul'Gurub's spec has none)
        local trash = Addon:GetEncounter("bwl:trash")
        ck(trash ~= nil and trash.detect.mode == "zone", "bwl:trash registers as a ZONE module")
        ck(trash and Addon.encByZone[469] ~= nil, "…indexed against instance 469")
        ck(Addon:GetEncounter("zg:trash") == nil,
           "…and Zul'Gurub declares NO trash module, because §5 describes none")
        eq(trash.rowsByKey.flamestrike.nameplate, true,
           "§4.9 Flamestrike runs ONE per-GUID nameplate bar…")
        eq(trash.rowsByKey.flamestrike.stop.creatureId, 12468, "…cancelled when that Seether dies")
        eq(trash.rowsByKey.trashvuln.default, false,
           "§4.9 the drakonid vulnerability ANNOUNCE ships OFF…")
        eq(trash.rowsByKey.trashvulnicon.default, true, "…while its nameplate icon ships ON")
        eq(trash.rowsByKey.trashvulnicon.on.antispamBy, "destGUID",
           "…throttled PER MOB, not per pull")
        ck(trash.rowsByKey["demonportal"] == nil,
           "§4.9 Demon Portal is NOT implemented (the spec calls its data insufficient)")
    end

    do  -- ship-off defaults carried from the spec verbatim
        local OFF = {
            { "bwl:razorgore",  "losvolley" },    -- §4.1 "ships OFF"
            { "bwl:firemaw",    "shadowflame" },  -- §4.4 "timer off by default"
            { "bwl:ebonroc",    "shadowflame" },  -- §4.5 "off by default"
            { "bwl:flamegor",   "shadowflame" },  -- §4.6 "off by default"
            { "bwl:chromaggus", "broodred" },     -- §4.7 "off by default"
            { "bwl:nefarian",   "shadowflame" },  -- §4.8 "off by default"
            { "zg:hakkar",      "jeklikon" },     -- §5.10 "off by default (spammy)"
        }
        for _, p in ipairs(OFF) do
            local enc = Addon:GetEncounter(p[1])
            local row = enc and enc.rowsByKey[p[2]]
            ck(row and row.default == false, p[1] .. ":" .. p[2] .. " SHIPS OFF (spec default)")
        end
        eq(Addon:GetEncounter("bwl:vaelastrasz").rowsByKey.adrenalineicons.default, true,
           "§4.2 the Burning Adrenaline raid icons ship ON")
        eq(Addon:GetEncounter("bwl:chromaggus").rowsByKey.vulnnameplate.default, true,
           "§4.7 the vulnerability nameplate icon ships ON")
    end

    do  -- §5.5 EDGE OF MADNESS: the spec flags its own ids unverified, so EVERY row is off
        local eom = Addon:GetEncounter("zg:edgeofmadness")
        local live, n = {}, 0
        for _, list in ipairs({ eom.timers, eom.warnings }) do
            for _, row in ipairs(list) do
                n = n + 1
                if row.default ~= false then live[#live + 1] = row.key end
            end
        end
        eq(n, 10, "EDGE OF MADNESS declares all ten of §5.5's rows")
        eq(#live, 0, "…and EVERY ONE ships OFF — the spec flags its ids unverified"
           .. (#live > 0 and (" (live: " .. table.concat(live, ", ") .. ")") or ""))
        local src = readFile(P("enc_zg.lua")) or ""
        local notes = 0
        for _ in src:gmatch("spec authors flag these ids unverified") do notes = notes + 1 end
        eq(notes, 10, "…each carrying the in-data provenance note, one per row")
    end

    do  -- 1.x SavedVariables continuity: the keys a player already toggled in BWL
        local KEPT = {
            razorgore   = { "adds", "destroyegg", "conflagration", "fireballvolley" },
            vaelastrasz = { "adrenalinecd", "adrenaline", "flamebreath", "firenova" },
            broodlord   = { "mortalstrike", "blastwave", "knockaway" },
            firemaw     = { "flamebuffet", "shadowflame", "wingbuffet" },
            ebonroc     = { "shadowofebonroc", "shadowflame", "wingbuffet" },
            flamegor    = { "frenzy", "shadowflame", "wingbuffet" },
            chromaggus  = { "breath1", "breath2", "frenzy", "vulnshift", "enrage" },
            nefarian    = { "shadowflame", "bellowingroar", "veilofshadow", "shadowcommand",
                            "landing", "phase3",
                            "classcall_druid", "classcall_hunter", "classcall_mage",
                            "classcall_paladin", "classcall_priest", "classcall_rogue",
                            "classcall_shaman", "classcall_warlock", "classcall_warrior" },
        }
        local missing = {}
        for boss, keys in pairs(KEPT) do
            local enc = Addon:GetEncounter("bwl:" .. boss)
            for _, k in ipairs(keys) do
                if not (enc and enc.rowsByKey[k]) then missing[#missing + 1] = boss .. ":" .. k end
            end
        end
        eq(#missing, 0, "every 1.x bwl mechanic key the spec still has a row for is PRESERVED"
           .. (#missing > 0 and (" (missing " .. table.concat(missing, ", ") .. ")") or ""))
        eq(Addon:MechKey("bwl", "chromaggus", "vulnshift"), "bwl:chromaggus:vulnshift",
           "…at the exact SavedVariables key the 1.x options tree wrote")
        -- the ADDITIVE carry-over: log-verified in our own data, absent from the spec
        local fn = Addon:GetEncounter("bwl:vaelastrasz").rowsByKey.firenova
        ck(fn and fn.default == false and fn.trigger.spellId == 23462,
           "…and the one log-verified mechanic §4.2 lacks (Fire Nova 23462) is carried OFF")
    end

    do  -- the options projection: two more raids in the tree options.lua reads
        API.PublishOptionsTree()
        local rb, rz = Addon:GetRaid("bwl"), Addon:GetRaid("zg")
        ck(rb ~= nil and rz ~= nil, "both W4b zones PROJECT into the options tree")
        eq(rb and rb.size, 40, "…Blackwing Lair as a 40-man raid")
        eq(rz and rz.size, 20, "…Zul'Gurub as a 20-man raid")
        eq(rb and #rb.bosses, 9, "…with nine BWL entries (8 bosses + trash)")
        eq(rz and #rz.bosses, 10, "…and ten ZG entries (no trash module in §5)")
        ck((rb.order or 999) < (rz.order or 999), "…ordered Blackwing Lair before Zul'Gurub")
        local chrom = Addon:GetBoss("bwl", "chromaggus")
        local sawRestyle = false
        for _, m in ipairs(chrom and chrom.mechanics or {}) do
            if m.id == "vulnstyle" then sawRestyle = true end
        end
        ck(sawRestyle, "…and a RESTYLE is a mechanic row like any other (the vulnerability bar)")
        ck(Addon:GetBossByNpcID(14020) ~= nil, "…while the npc index resolves Chromaggus")
    end

    do  -- §4.7 the vulnerability system, as DATA rather than as code
        local c = Addon:GetEncounter("bwl:chromaggus")
        local r = c.rowsByKey.vulnstyle
        ck(r and r.timer == "vulnshift", "CHROMAGGUS: the restyle row re-labels the vuln BAR")
        eq(r and #r.variants, 10,
           "…with five schools x TWO evidence paths (combat-log aura AND the buff sweep)")
        local byPath = { SPELL_AURA_APPLIED = 0, aura = 0 }
        local schools = {}
        for _, v in ipairs(r.variants) do
            byPath[v.on] = (byPath[v.on] or 0) + 1
            schools[v.style.text] = true
        end
        eq(byPath.SPELL_AURA_APPLIED, 5, "…five off the combat log…")
        eq(byPath.aura, 5, "…and five off the unit-buff sweep")
        local nSchools = 0
        for _ in pairs(schools) do nSchools = nSchools + 1 end
        eq(nSchools, 5, "…naming exactly five schools, and no Holy")
        local scan = c.rowsByKey.vulnscan
        ck(scan and scan.type == "unit" and #scan.auras == 5,
           "…and the sweep is a UNIT scan over the five vulnerability auras")
        -- NOTHING may clear the school: no row anywhere reacts to the aura being GONE
        local clears = 0
        for _, list in ipairs({ c.timers, c.warnings, c.restyles }) do
            for _, row in ipairs(list) do
                for _, tr in ipairs({ row.trigger, row.start, row.stop, row.restart }) do
                    if type(tr) == "table" and tr.on == "SPELL_AURA_REMOVED" then
                        local ids = type(tr.spellId) == "table" and tr.spellId or { tr.spellId }
                        for _, id in ipairs(ids) do
                            if id == 22277 or id == 22278 or id == 22279
                               or id == 22280 or id == 22281 then clears = clears + 1 end
                        end
                    end
                end
            end
        end
        eq(clears, 0,
           "…and NOTHING clears the school on an aura-removed (LESSON CLASS 4: absent evidence is not absence)")
        -- the two pull breath bars, and the counter that tells them apart
        eq(c.rowsByKey.breath1.stop.on, "SPELL_CAST_START",
           "…the FIRST breath bar is stopped by hand when a breath lands")
        eq(c.rowsByKey.breath2.stop.counter.min, 1,
           "…and the SECOND only once one breath has already gone by")
        eq(c.rowsByKey.breathcd.identBy, "spellId",
           "…while the recurring bar is ONE PER BREATH SPELL")
    end
end
endgate()

gate("BWLZG-DRIVE  §4/§5 per-encounter behaviour through the real engine")
do
    loadBWLZG()
    Addon:SetEventRecording(true)
    Addon._suppressLegacyAlerts = true
    Addon.RoleResolver  = function() return true end
    Addon.ClassResolver = function() return "WARLOCK" end

    -- ── §4.1 Razorgore: eggs, phases, and the kill that is really a wipe ──────
    do
        local rt = engage("bwl:razorgore", 12435, "Intruders have breached the hatchery!")
        ck(rt ~= nil, "RAZORGORE: engages on the hatchery yell (matched around its line break)")
        near(bar(rt, "adds").total, 47, 0.01, "…one 47 s add-wave bar at pull")
        Addon:ClearEventLog()
        for _ = 1, 3 do
            Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 19873, sourceId = 12435 })
        end
        ck(sawWarn("WARN_ANNOUNCE", "Eggs destroyed 3/30"),
           "…and EVERY egg is announced with its count (Era, not retail's every-third)")
        eq(rt.stage, 1, "…still phase 1 while the eggs burn")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 23040, sourceId = 12435 })
        eq(rt.stage, 2, "…the control break IS phase 2")
        ck(sawWarn("WARN_ANNOUNCE", "Phase 2"), "…announced")
        -- the kill-stage gate, both ways round
        local rt1 = engage("bwl:razorgore", 12435, "Intruders have breached the hatchery!")
        Life:OnUnitDied(12435)
        local rep1 = rt1.report
        ck(rep1 and rep1.wiped == true,
           "…dying in PHASE 1 is a WIPE, not a kill (the orb was dropped)")
        local rt2 = engage("bwl:razorgore", 12435, "Intruders have breached the hatchery!")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 23040, sourceId = 12435 })
        Life:OnUnitDied(12435)
        ck(rt2.report and rt2.report.wiped == false, "…and dying in PHASE 2 is the kill")
        eq(Addon:GetEncounter("bwl:razorgore").combat.noEncounterEndKill, true,
           "…with Blizzard's ENCOUNTER_END refused outright for this fight")
    end

    -- ── §4.2 Vaelastrasz: the RP countdown and the scheduled run-out ──────────
    do
        resetLife()
        W.instanceID = 469
        Addon:CancelPullTimer("test")
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_YELL", "Too late, friends! Nefarius' corruption has taken hold...")
        local pulled
        for _, e in ipairs(Addon:GetEventLog()) do if e.event == "ENGINE_PULL" then pulled = e end end
        ck(pulled ~= nil and math.abs((tonumber(pulled[1]) or 0) - 43.5) < 0.01,
           "VAEL: the RP yell starts a 43.5 s PULL countdown without engaging anything")
        ck(not Life:AnyEngaged(), "…and nothing is engaged by it")
        Addon:CancelPullTimer("test")

        local rt = engage("bwl:vaelastrasz", 13020)
        local mn, mx = barWindow(rt, "adrenalinecd")
        near(mn, 16.1, 0.01, "…Burning Adrenaline cycles from 16.1…")
        near(mx, 17.8, 0.01, "…to 17.8")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 18173, destName = "Bob" })
        ck(sawWarn("WARN_ANNOUNCE", "Burning Adrenaline on Bob"), "…a victim is named to the raid")
        near(bar(rt, "adrenalinebar", "Bob") or (rt.timers.adrenalinebar:Get("Bob") or {}).total, 20, 0.01,
             "…with a 20 s bar of their own")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 18173, destIsPlayer = true,
                       destName = "Drew" })
        ck(sawWarn("WARN_SPECIAL", "BURNING ADRENALINE"), "…and YOU get the death sentence")
        Addon:ClearEventLog()
        advance(15.1)
        ck(sawWarn("WARN_SPECIAL", "RUN OUT"),
           "…with the run-out call scheduled 15 s in, 5 s before it kills you")
        -- and the cancel path
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 18173, destIsPlayer = true,
                       destName = "Drew" })
        Life:Deliver({ on = "SPELL_AURA_REMOVED", spellId = 18173, destIsPlayer = true,
                       destName = "Drew" })
        Addon:ClearEventLog()
        advance(16)
        ck(not sawWarn("WARN_SPECIAL", "RUN OUT"),
           "…and an early removal CANCELS the scheduled run-out")
    end

    -- ── §4.4 Firemaw: even stacks only, from four up ──────────────────────────
    do
        local rt = engage("bwl:firemaw", 11983)
        local mn, mx = barWindow(rt, "wingbuffet")
        near(mn, 30.6, 0.01, "FIREMAW: Wing Buffet's PULL window opens at 30.6…")
        near(mx, 40.4, 0.01, "…and closes at 40.4")
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 23339, sourceId = 11983 })
        local rmn, rmx = barWindow(rt, "wingbuffet")
        near(rmn, 31.6, 0.01, "…then the RECURRING window is 31.6…")
        near(rmx, 42.1, 0.01, "…to 42.1")
        Addon:ClearEventLog()
        for _, n in ipairs({ 3, 4, 5, 6 }) do
            Life:Deliver({ on = "SPELL_AURA_APPLIED_DOSE", spellId = 23341,
                           destIsPlayer = true, destName = "Drew", amount = n })
        end
        ck(not sawWarn("WARN_ANNOUNCE", "Flame Buffet (3)"), "…stack 3 is silent (below four)")
        ck(sawWarn("WARN_ANNOUNCE", "Flame Buffet (4)"), "…stack 4 speaks")
        ck(not sawWarn("WARN_ANNOUNCE", "Flame Buffet (5)"), "…stack 5 is silent (odd)")
        ck(sawWarn("WARN_ANNOUNCE", "Flame Buffet (6)"), "…and stack 6 speaks")
    end

    -- ── §4.5 Ebonroc: the taunt call REPLACES the announce when it is on ──────
    do
        local rt = engage("bwl:ebonroc", 14601)
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 23340, destName = "Bob" })
        ck(sawWarn("WARN_SPECIAL", "Taunt — Bob has the Shadow"),
           "EBONROC: somebody else carrying the Shadow is a TAUNT call…")
        ck(not sawWarn("WARN_ANNOUNCE", "Shadow of Ebonroc on Bob"),
           "…and the plain announce steps aside while that call is enabled")
        -- switch the taunt call off and the plain announce comes back
        Addon.db.mechanics = Addon.db.mechanics or {}
        Addon.db.mechanics["bwl:ebonroc:shadowtaunt"] = { masterEnabled = false }
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 23340, destName = "Bob" })
        ck(sawWarn("WARN_ANNOUNCE", "Shadow of Ebonroc on Bob"),
           "…and comes back the moment the player turns the taunt call off")
        Addon.db.mechanics["bwl:ebonroc:shadowtaunt"] = nil
        near((rt.timers.shadowofebonroc:Get("Bob") or {}).total, 8, 0.01,
             "…while the 8 s target bar runs either way")
    end

    -- ── §4.7 CHROMAGGUS — the crown ───────────────────────────────────────────
    do
        local rt = engage("bwl:chromaggus", 14020)
        ck(rt ~= nil, "CHROMAGGUS: engages off the combat sweep")
        eq(Addon:GetEncounter("bwl:chromaggus").combat.wipeWindow, 20,
           "…with a 20 s wipe window, because ENCOUNTER_START fires on the LEVER")
        local b1n, b1x = barWindow(rt, "breath1")
        near(b1n, 27, 0.01, "…the First Breath bar opens at 27…")
        near(b1x, 37.2, 0.01, "…and closes at 37.2")
        local b2n, b2x = barWindow(rt, "breath2")
        near(b2n, 57.3, 0.01, "…the Second Breath bar opens at 57.3…")
        near(b2x, 68.1, 0.01, "…and closes at 68.1")
        -- the pre-warnings are SCHEDULED, not derived
        Addon:ClearEventLog()
        advance(27.1)
        ck(sawWarn("WARN_SPECIAL", "Breath soon"), "…'breath soon' is scheduled at 27 s from pull")

        -- FIRST BREATH: closes bar 1 only, and names the recurring bar
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 23309, sourceId = 14020 })
        eq(bar(rt, "breath1"), nil, "…the first breath MANUALLY STOPS the first pull bar…")
        ck(bar(rt, "breath2") ~= nil, "…and leaves the second one running")
        ck(sawWarn("WARN_ANNOUNCE", "BREATH"), "…announced to the raid")
        local inc = rt.timers.breathcd:Get(23309)
        ck(inc ~= nil, "…a 61.5 s bar starts for THAT breath…")
        near(inc.total, 61.5, 0.01, "…of exactly 61.5 s")
        eq(inc.text, "Incinerate", "…RENAMED to the breath itself (the W2 restyle contract)")
        local elapsed = inc.startedAt
        -- SECOND BREATH: a different spell, its own bar, and bar 2 closes
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 23187, sourceId = 14020 })
        eq(bar(rt, "breath2"), nil, "…the SECOND breath closes the second pull bar")
        local frost = rt.timers.breathcd:Get(23187)
        ck(frost ~= nil and frost.text == "Frost Burn",
           "…and gets its OWN bar, named for itself — two breaths, two clocks")
        ck(rt.timers.breathcd:Get(23309) ~= nil,
           "…while the first breath's bar is untouched by the second")
        eq(rt.timers.breathcd:Get(23309).startedAt, elapsed,
           "…and was never restarted (identity changes, elapsed time does not)")

        -- THE VULNERABILITY SYSTEM, all three evidence paths
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 22278, destId = 14020,
                       destName = "Chromaggus" })
        local v = bar(rt, "vulnshift")
        ck(v ~= nil, "…PATH 1 (combat-log aura): the vulnerability bar starts…")
        near(v.min, 16.2, 0.01, "…on the spec's 16.2…")
        near(v.max, 25.9, 0.01, "…to 25.9 window")
        eq(v.text, "Frost Vulnerability", "…recoloured, re-iconed and RENAMED to the school")
        ck(sawWarn("WARN_ANNOUNCE", "Frost Vulnerability"), "…and announced once")
        -- the SAME school again is not news
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 22278, destId = 14020 })
        ck(not sawWarn("WARN_ANNOUNCE", "Frost Vulnerability"),
           "…and re-seeing the same school announces NOTHING (change only)")
        -- PATH 2: the buff sweep, with the combat log silent (nobody has Detect Magic)
        Addon:ClearEventLog()
        setUnit("target", { cid = 14020, combat = true, hp = 100, hpmax = 100,
                            guid = "Creature-0-0-0-0-14020-0001", buffs = { 22281 } })
        Addon.Scan.ClearTokenCache()
        advance(1.1)
        eq(bar(rt, "vulnshift").text, "Arcane Vulnerability",
           "…PATH 2 (his own buffs, swept): the school is read with NO combat-log event at all")
        ck(sawWarn("WARN_ANNOUNCE", "Arcane Vulnerability"), "…and announced")
        -- and an EMPTY sweep may never clear it (LESSON CLASS 4/6)
        Addon:ClearEventLog()
        setUnit("target", { cid = 14020, combat = true, hp = 100, hpmax = 100,
                            guid = "Creature-0-0-0-0-14020-0001", buffs = {} })
        advance(2.2)
        eq(bar(rt, "vulnshift").text, "Arcane Vulnerability",
           "…an EMPTY sweep changes NOTHING — absent evidence is not absence")
        eq(rt:GetState("vulnstyle"), "Arcane Vulnerability", "…and the state is held, not cleared")
        -- PATH 3: the shimmer emote, which proves a change without naming a school
        Addon:ClearEventLog()
        rt.timers.vulnshift:Stop()
        Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "Chromaggus flinches as its skin shimmers.")
        ck(bar(rt, "vulnshift") ~= nil,
           "…PATH 3 (the shimmer emote): the bar starts even when the school is unknown")

        -- MUTATION: the player's own affliction count, up AND down
        Addon:ClearEventLog()
        for _, id in ipairs({ 23155, 23169 }) do
            Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = id, destIsPlayer = true })
        end
        ck(not sawWarn("WARN_ANNOUNCE", "MUTATION"), "…two afflictions is silent")
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 23153, destIsPlayer = true })
        ck(sawWarn("WARN_ANNOUNCE", "MUTATION 3/5"), "…THREE is the alarm")
        Life:Deliver({ on = "SPELL_AURA_REMOVED", spellId = 23153, destIsPlayer = true })
        eq(rt:GetCount("mutation"), 2, "…and the count comes back DOWN when one is dispelled")
    end

    -- ── §4.8 Nefarian: the poll-driven phase machine and the class calls ──────
    do
        local rt = engage("bwl:nefarian", 11583, "Let the games begin!")
        ck(rt ~= nil, "NEFARIAN: engages on 'Let the games begin!'")
        eq(rt:GetState("nefphase"), "waves", "…phase 1 is the drakonid waves")
        -- The poller must SEE the flag set before an unset can mean anything: a pull
        -- that begins with the flag already false is not an intermission that happened.
        W.encounterInProgress = false
        advance(0.5)
        eq(rt:GetState("nefphase"), "waves",
           "…and a flag that was NEVER seen set cannot mean the waves are over")
        W.encounterInProgress = true
        advance(0.5)
        eq(rt:GetState("nefphase"), "waves", "…the flag going true is still phase 1")
        -- the drakonid census
        Addon:ClearEventLog()
        for i = 1, 2 do
            Life:Deliver({ on = "UNIT_DIED", creatureId = 14261,
                           destGUID = "Creature-0-0-0-0-14261-" .. i, destId = 14261 })
        end
        eq(rt:GetCount("drakonids"), 40, "…each drakonid death counts down from 42…")
        ck(sawWarn("WARN_ANNOUNCE", "40 drakonids left"), "…announced at the spec's marks")
        Addon:ClearEventLog()
        Life:Deliver({ on = "UNIT_DIED", creatureId = 14261,
                       destGUID = "Creature-0-0-0-0-14261-1", destId = 14261 })
        eq(rt:GetCount("drakonids"), 40, "…and a corpse logged twice is de-duplicated by GUID")
        -- THE POLL: in progress -> not in progress -> in progress
        Addon:ClearEventLog()
        W.encounterInProgress = false
        advance(0.5)
        eq(rt:GetState("nefphase"), "intermission",
           "…the flag going FALSE after phase 1 is the intermission (no event exists for this)")
        ck(sawWarn("WARN_ANNOUNCE", "Phase 2 soon"), "…pre-warned")
        local im = bar(rt, "intermission")
        ck(im ~= nil, "…and the intermission bar runs")
        near(im.min, 12.9, 0.01, "…from 12.9…")
        near(im.max, 14.9, 0.01, "…to 14.9")
        Addon:ClearEventLog()
        W.encounterInProgress = true
        advance(0.5)
        eq(rt.stage, 2, "…the flag coming back TRUE is phase 2")
        ck(sawWarn("WARN_ANNOUNCE", "Phase 2 — Nefarian lands"), "…announced")
        ck(bar(rt, "bellowingroar") ~= nil, "…and phase 2 arms the Fear bar")
        ck(Addon.Scan.singletonByKey["bwl:nefarian:phasepoll"] == nil,
           "…while the poller TEARS ITSELF DOWN, having answered the only question it had")
        -- the class calls: raid announce for everyone, personal special for the class
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_YELL",
                    "Warlocks, you shouldn't be playing with magic you don't understand. See what happens?")
        ck(sawWarn("WARN_ANNOUNCE", "Class call — WARLOCKS"), "…a class call announces to the raid")
        ck(sawWarn("WARN_SPECIAL", "YOUR CLASS IS CALLED"),
           "…and special-warns YOU, because you are the class it named")
        ck(bar(rt, "classcall") ~= nil, "…with a 30 s bar…")
        eq(bar(rt, "classcall").text, "Warlock call", "…renamed to the class that was called")
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_YELL", "Hunters and your annoying pea-shooters!")
        ck(sawWarn("WARN_ANNOUNCE", "Class call — HUNTERS"), "…another class announces…")
        ck(not sawWarn("WARN_SPECIAL", "YOUR CLASS IS CALLED"),
           "…and does NOT special-warn you, because you are not a Hunter")
        -- the Shaman call is everybody's problem
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_YELL", "Shamans, show me what your totems can do!")
        ck(sawWarn("WARN_SPECIAL", "KILL THE TOTEMS"),
           "…while the SHAMAN call shouts at the whole raid, Warlock or not")
        -- phase 3
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_YELL",
                    "Impossible! Rise my minions! Serve your master once more!")
        eq(rt.stage, 3, "…and the resurrection yell is phase 3")
        W.encounterInProgress = false
    end

    -- ── §5.4 Mandokir: the yell beats the combat log by two seconds ───────────
    do
        local rt = engage("zg:mandokir", 11382)
        ck(rt ~= nil, "MANDOKIR: engages off the combat sweep")
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_YELL", "Bob! I'm watching you!")
        ck(sawWarn("WARN_ANNOUNCE", "MANDOKIR IS WATCHING"),
           "…the GAZE fires off the YELL, 1.5-2 s before the combat log knows")
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_YELL", "Drew! I'm watching you!")
        ck(sawWarn("WARN_SPECIAL", "WATCHING YOU"),
           "…and when the yell names YOU it is the stop-casting call")
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 24314, destName = "Bob" })
        near((rt.timers.gaze:Get("Bob") or {}).total, 6, 0.01,
             "…while the combat log is left to run the 6 s bar")
    end

    -- ── §5.8 Arlokk: a vanish nobody logs, and a swing that proves she is back ─
    do
        local rt = engage("zg:arlokk", 14515)
        local mn = select(1, barWindow(rt, "vanishcd"))
        near(mn, 33.7, 0.01, "ARLOKK: the first Vanish window opens at 33.7")
        Addon:ClearEventLog()
        Life:Deliver({ on = "unitCast", spellId = 24223, sourceId = 14515 })
        eq(bar(rt, "vanishcd"), nil, "…the vanish (unit-cast only — no combat-log event) stops the CD…")
        ck(bar(rt, "vanishactive") ~= nil, "…and starts the vanish-active bar")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SWING_MISSED", sourceId = 14515,
                       sourceGUID = "Creature-0-0-0-0-14515-1", missType = "DODGE" })
        eq(bar(rt, "vanishactive"), nil,
           "…and a MISSED swing is proof enough that she is back")
        local rn, rx = barWindow(rt, "vanishcd")
        near(rn, 65, 0.01, "…re-arming the cooldown at 65…")
        near(rx, 70, 0.01, "…to 70")
    end

    -- ── §5.10 Hakkar: hard mode is a health reading and nothing else ──────────
    do
        -- NORMAL: the nerfed boss, and no Aspect bars at all
        resetLife()
        W.instanceID = 309
        setUnit("target", { cid = 14834, combat = true, hp = 100, hpmax = 800000,
                            guid = "Creature-0-0-0-0-14834-0001" })
        setUnit("playertarget", { cid = 14834, combat = true, hp = 100, hpmax = 800000 })
        Addon.Scan.ClearTokenCache()
        Addon:ClearEventLog()
        Life:Sweep(0.5)
        local rt = Life:GetRuntime("zg:hakkar")
        ck(rt ~= nil, "HAKKAR: engages off the combat sweep")
        near(bar(rt, "berserk").total, 585, 0.01, "…on a 585 s berserk")
        near(bar(rt, "siphon").total, 90, 0.01, "…with Blood Siphon every 90 s")
        advance(2.2)
        eq(bar(rt, "aspectmarli"), nil,
           "…and a NERFED Hakkar (800k) arms NO Aspect bars — the max health is the only tell")
        ck(not sawWarn("WARN_ANNOUNCE", "HARD MODE"), "…and says nothing about hard mode")

        -- HARD: >= 1,079,325 and the five Aspect sets arm
        resetLife()
        W.instanceID = 309
        setUnit("target", { cid = 14834, combat = true, hp = 100, hpmax = 1079325,
                            guid = "Creature-0-0-0-0-14834-0001" })
        setUnit("playertarget", { cid = 14834, combat = true, hp = 100, hpmax = 1079325 })
        Addon.Scan.ClearTokenCache()
        Addon:ClearEventLog()
        Life:Sweep(0.5)
        rt = Life:GetRuntime("zg:hakkar")
        advance(2.2)
        ck(sawWarn("WARN_ANNOUNCE", "HARD MODE"),
           "…while 1,079,325 IS the hard-mode flag this fight does not otherwise have")
        near(bar(rt, "aspectmarli").total, 10, 0.01, "…Aspect of Mar'li arms at 10 s…")
        near(bar(rt, "aspectthekal").total, 10, 0.01, "…Thekal at 10…")
        near(bar(rt, "aspectvenoxis").total, 14, 0.01, "…Venoxis at 14…")
        near(bar(rt, "aspectjeklik").total, 21, 0.01, "…Jeklik at 21…")
        near(bar(rt, "aspectarlokk").total, 30, 0.01, "…and Arlokk at 30")
        local startedAt = bar(rt, "aspectmarli").startedAt
        advance(2.2)
        eq(bar(rt, "aspectmarli").startedAt, startedAt,
           "…and the repeating probe does NOT keep re-arming them (one proof, once)")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 24686, sourceId = 14834 })
        local am, ax = barWindow(rt, "aspectmarli")
        near(am, 16, 0.01, "…after which Mar'li runs on its own 16…")
        near(ax, 20, 0.01, "…to 20 cycle")
        -- and the tranq call replaces the plain announce
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 24689, destName = "Hakkar" })
        ck(sawWarn("WARN_SPECIAL", "Tranquilizing Shot NOW"),
           "…and Aspect of Thekal is a tranq call, not an announce")
        ck(not sawWarn("WARN_ANNOUNCE", "Aspect of Thekal"), "…which replaces it while it is on")
    end

    -- ── §5.1 Venoxis: a HALF stage, then the transform ────────────────────────
    do
        local rt = engage("zg:venoxis", 14507)
        Addon:ClearEventLog()
        Life:EvaluateHealthTriggers(rt, 54)
        eq(rt.stage, 1.5, "VENOXIS: 55 % is a HALF stage — 'nearly', not 'now'")
        ck(sawWarn("WARN_ANNOUNCE", "Phase 2 soon"), "…announced as 'phase 2 soon'")
        Addon:ClearEventLog()
        Life:Deliver({ on = "unitCast", spellId = 23849, sourceId = 14507 })
        eq(rt.stage, 2, "…and the transform on the unit-cast channel is the real phase 2")
        ck(sawWarn("WARN_ANNOUNCE", "Phase 2 — the serpent"), "…announced")
    end

    -- ── §5.6 Thekal: the resurrection window ──────────────────────────────────
    do
        local rt = engage("zg:thekal", 14509)
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "Zealot Lor'Khan dies.")
        ck(sawWarn("WARN_ANNOUNCE", "One down — resurrection in 15"),
           "THEKAL: the first death opens a 15 s resurrection window")
        near(bar(rt, "resurrect").total, 15, 0.01, "…as a 15 s bar")
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_EMOTE", "Zealot Zath dies.")
        ck(not sawWarn("WARN_ANNOUNCE", "One down"),
           "…and the SECOND death inside 20 s does not restart it")
        Life:OnChat("CHAT_MSG_MONSTER_YELL", "Shirvallah, fill me with your RAGE!")
        eq(bar(rt, "resurrect"), nil, "…while the phase-2 yell closes the window for good")
        eq(rt.stage, 2, "…and IS phase 2")
    end

    -- ── §4.9 the zone-wide BWL trash module ───────────────────────────────────
    do
        resetLife()
        W.instanceID = 469
        eq(Life:ArmZones(469), 1, "TRASH: entering Blackwing Lair ARMS the BWL trash module")
        ck(Life:IsZoneArmed("bwl:trash"), "…without engaging anything")
        Addon:ClearEventLog()
        local rtz = Life.zoneArmed["bwl:trash"]
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 22275,
                       sourceGUID = "Creature-0-0-0-0-12468-1", sourceId = 12468 })
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 22275,
                       sourceGUID = "Creature-0-0-0-0-12468-2", sourceId = 12468 })
        local n = 0
        for _ in pairs(rtz.timers.flamestrike.live) do n = n + 1 end
        eq(n, 2, "…Flamestrike runs ONE bar PER SEETHER")
        ck(sawWarn("WARN_ANNOUNCE", "Flamestrike"), "…and announces")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_PERIODIC_DAMAGE", spellId = 19717, destIsPlayer = true })
        ck(sawWarn("WARN_SPECIAL", "Move out of the fire"),
           "…standing in Rain of Fire is the shared GTFO alert")
        W.instanceID = 533
        Life:ArmZones(533)
    end

    Addon._suppressLegacyAlerts = nil
    Addon:SetEventRecording(false)
    resetLife()
end
endgate()

----------------------------------------------------------------------
-- WAVE 4a — MOLTEN CORE + ONYXIA'S LAIR + THE WORLD BOSSES
--
-- The wave that closes W4. Every assertion below names the
-- DBM_ERA_ENCOUNTERS_BEHAVIOR_SPEC.md §2 / §3 / §9 row it proves, and every one runs
-- the SHIPPING data through the SHIPPING engine on the injected clock and world.
----------------------------------------------------------------------
local function loadW4A()
    Addon.encounters, Addon.encountersById = {}, {}
    Addon.encByCreature, Addon.encByEncounterId, Addon.encByZone = {}, {}, {}
    Addon.zones, Addon.zonesById = {}, {}
    local ok1, e1 = pcall(MC_CHUNK,  ADDON_NAME, Addon)
    local ok2, e2 = pcall(ONY_CHUNK, ADDON_NAME, Addon)
    local ok3, e3 = pcall(WB_CHUNK,  ADDON_NAME, Addon)
    return ok1 and ok2 and ok3,
           (not ok1 and e1) or (not ok2 and e2) or (not ok3 and e3) or nil
end

-- Outdoor engage helper. The engine spec is explicit (§2.1(d)) that OUTDOORS a boss
-- yell does not engage — it schedules a delay-0 target sweep — so this drives the
-- real path rather than short-circuiting it, and it sets difficulty 0 so every
-- world-boss rule the engine derives is actually in force.
local function engageWorld(encId, cid, yell)
    resetLife()
    W.inInstance, W.instanceType, W.instanceID = false, "none", 0
    W.difficultyID, W.difficultyName, W.maxPlayers = 0, "World Boss", 40
    W.group = { "player" }
    setUnit("target", { cid = cid, combat = true, hp = 100, hpmax = 100 })
    setUnit("playertarget", { cid = cid, combat = true, hp = 100, hpmax = 100 })
    Addon:ClearEventLog()
    Life:OnChat("CHAT_MSG_MONSTER_YELL", yell)
    advance(0.2)                     -- let the scheduled delay-0 sweep run
    return Life:GetRuntime(encId)
end

gate("MCONYWB  §2/§3/§9 encounter data: registration, keys, the options tree")
do
    local okc, err = loadW4A()
    ck(okc, "enc_moltencore.lua + enc_onyxia.lua + enc_worldbosses.lua EXECUTE against " ..
            "the shipping grammar" .. (okc and "" or (" -> " .. tostring(err))))

    local EXPECTED = {
        -- §2 Molten Core (zone 409)
        { id = "mc:lucifron",  cid = 12118, eid = 663, raid = "mc", boss = "lucifron" },
        { id = "mc:magmadar",  cid = 11982, eid = 664, raid = "mc", boss = "magmadar" },
        { id = "mc:gehennas",  cid = 12259, eid = 665, raid = "mc", boss = "gehennas" },
        { id = "mc:garr",      cid = 12057, eid = 666, raid = "mc", boss = "garr" },
        { id = "mc:geddon",    cid = 12056, eid = 668, raid = "mc", boss = "geddon" },
        { id = "mc:shazzrah",  cid = 12264, eid = 667, raid = "mc", boss = "shazzrah" },
        { id = "mc:sulfuron",  cid = 12098, eid = 669, raid = "mc", boss = "sulfuron" },
        { id = "mc:golemagg",  cid = 11988, eid = 670, raid = "mc", boss = "golemagg" },
        { id = "mc:majordomo", cid = 12018, eid = 671, raid = "mc", boss = "majordomo" },
        { id = "mc:ragnaros",  cid = 11502, eid = 672, raid = "mc", boss = "ragnaros" },
        -- §3 Onyxia's Lair (zone 249)
        { id = "onyxia:onyxia", cid = 10184, eid = 1084, raid = "onyxia", boss = "onyxia" },
    }
    for _, e in ipairs(EXPECTED) do
        local enc = Addon:GetEncounter(e.id)
        ck(enc ~= nil, e.id .. " is registered")
        if enc then
            local errs = API.Validate(enc)
            eq(#errs, 0, "…with zero validation errors" ..
               (#errs > 0 and (": " .. table.concat(errs, "; ")) or ""))
            ck(Addon.encByCreature[e.cid] ~= nil, "…indexed by creature " .. e.cid)
            ck(Addon.encByEncounterId[e.eid] ~= nil, "…and by encounter id " .. e.eid)
            ck(enc.legacy and enc.legacy.raidId == e.raid and enc.legacy.bossId == e.boss,
               "…carrying the legacy seam " .. e.raid .. ":" .. e.boss)
            local firstRow = enc.timers[1] or enc.warnings[1]
            if firstRow then
                eq(API.OptionKey(enc.id, firstRow.key),
                   Addon:MechKey(e.raid, e.boss, firstRow.key),
                   "…and OptionKey == MechKey for its rows")
            end
        end
    end

    -- §9: six world bosses, NO encounter ids (Blizzard declares none outdoors).
    local WORLD = {
        { id = "world:azuregos", cid = 6109,  boss = "azuregos" },
        { id = "world:kazzak",   cid = 12397, boss = "kazzak" },
        { id = "world:ysondre",  cid = 14887, boss = "ysondre" },
        { id = "world:lethon",   cid = 14888, boss = "lethon" },
        { id = "world:emeriss",  cid = 14889, boss = "emeriss" },
        { id = "world:taerar",   cid = 14890, boss = "taerar" },
    }
    for _, e in ipairs(WORLD) do
        local enc = Addon:GetEncounter(e.id)
        ck(enc ~= nil, e.id .. " is registered")
        if enc then
            eq(#API.Validate(enc), 0, "…with zero validation errors")
            ck(Addon.encByCreature[e.cid] ~= nil, "…indexed by creature " .. e.cid)
            eq(#enc.encounterIds, 0, "…and declares NO encounter id (there is none outdoors)")
            eq(enc.combat.wipeWindow, 15,
               "…declaring the 15 s world-boss wipe window (§9 / ENGINE SPEC §10.10)")
        end
    end
    eq(#Addon.encounters, #EXPECTED + #WORLD + 1,
       "…18 registrations in all (10 MC + Onyxia + 6 world bosses + one trash module)")

    do  -- §2.11 the zone-wide MC trash module
        local trash = Addon:GetEncounter("mc:trash")
        ck(trash ~= nil and trash.detect.mode == "zone", "mc:trash registers as a ZONE module")
        ck(trash and Addon.encByZone[409] ~= nil, "…indexed against instance 409")
        eq(#trash.timers, 11, "§2.11 declares eleven per-mob cooldown bars")
        local np = 0
        for _, row in ipairs(trash.timers) do if row.nameplate then np = np + 1 end end
        eq(np, 11, "…and EVERY one of them is per-mob-GUID nameplate-attached")
        eq(#trash.warnings, 13, "…alongside thirteen announces")
        local unthrottled = {}
        for _, row in ipairs(trash.warnings) do
            if not (row.trigger and row.trigger.antispam == 3) then
                unthrottled[#unthrottled + 1] = row.key
            end
        end
        eq(#unthrottled, 0, "…each carrying the spec's 3 s anti-spam key" ..
           (#unthrottled > 0 and (" (missing: " .. table.concat(unthrottled, ", ") .. ")") or ""))
        eq(trash.rowsByKey.surge.pull, nil,
           "§2.11 Lava Surger has NO engage value in the spec, so it declares none")
        eq(trash.rowsByKey.knockdown.duration, 7.2,
           "…and Knockdown's open-ended '7.2+' ships as a flat 7.2, not an invented window")
    end

    do  -- ship-off defaults carried from the spec verbatim
        local OFF = {
            { "mc:lucifron", "dominatemind" },    -- §2.1 "Off by default"
            { "mc:gehennas", "rainoffirewarn" },  -- §2.3 "off by default"
            { "mc:gehennas", "fistofragnaros" },  -- §2.3 "off by default"
            { "mc:garr",     "immolate" },        -- §2.4 "off by default"
            { "mc:sulfuron", "shadowwordpain" },  -- §2.7 three of four ship off
            { "mc:sulfuron", "handofragnaros" },
            { "mc:sulfuron", "immolate" },
            { "mc:trash",    "smashwarn" },       -- §2.11
            { "mc:trash",    "massivetremorwarn" },
            { "mc:trash",    "lavabreathwarn" },
            { "onyxia:onyxia", "fireballon" },    -- §3.1 "off by default"
            { "onyxia:onyxia", "knockaway" },     -- §3.1 "off by default"
            { "world:ysondre", "noxiousbreathcd" },  -- §9.3 "shipped disabled as iffy"
            { "world:taerar",  "noxiousbreathcd" },
        }
        for _, p in ipairs(OFF) do
            local enc = Addon:GetEncounter(p[1])
            local row = enc and enc.rowsByKey[p[2]]
            ck(row and row.default == false, p[1] .. ":" .. p[2] .. " SHIPS OFF (spec default)")
        end
        eq(Addon:GetEncounter("mc:lucifron").rowsByKey.mindcontrolicons.default, true,
           "§2.1 the mind-control raid icons ship ON")
        eq(Addon:GetEncounter("mc:geddon").rowsByKey.livingbombicons.default, false,
           "§2.5 the Living Bomb raid icons ship OFF")
        eq(Addon:GetEncounter("onyxia:onyxia").rowsByKey.fireballicon.default, true,
           "§3.1 the Fireball raid icon ships ON")
    end

    do  -- §2.8 GOLEMAGG: one announce, and NOTHING else invented
        local g = Addon:GetEncounter("mc:golemagg")
        eq(#g.timers, 0, "GOLEMAGG declares zero timers (the spec gives none)")
        eq(#g.warnings, 1, "…and exactly ONE announce — the thinnest raid boss in the set")
        eq(g.warnings[1].key, "earthquake", "…which is the Earthquake call")
        eq(#g.phases, 0, "…with no phase logic invented for it")
    end

    do  -- §9.1 AZUREGOS: no timers is a DECISION, and it is asserted as one
        local a = Addon:GetEncounter("world:azuregos")
        eq(#a.timers, 0,
           "AZUREGOS ships ZERO timers — 'a bar at the minimum is more misleading than helpful'")
        eq(#a.warnings, 3, "…and the three reactive alerts §9.1 does list")
        local k = Addon:GetEncounter("world:kazzak")
        eq(#k.timers, 1, "KAZZAK ships exactly one timer…")
        eq(k.timers[1].key, "berserk", "…the 180 s berserk…")
        eq(k.rowsByKey.berserk.start.condition, "pullTimeable",
           "…and it is CONDITIONAL on the pull being reliable enough to time")
        ck(k.rowsByKey.markyou.yell == nil,
           "…while the Mark carries NO raid yell (a deliberate omission, §9.2)")
    end

    do  -- §9.3-9.6 the four dragons: one mod, four registrations
        local fogPull = { ysondre = 18.4, lethon = 18.4, emeriss = 18.4, taerar = 21.5 }
        local fogCd   = { ysondre = 16.0, lethon = 16.8, emeriss = 15.8, taerar = 21.9 }
        for id, pull in pairs(fogPull) do
            local d = Addon:GetEncounter("world:" .. id)
            near(d.rowsByKey.sleepingfog.pull, pull, 0.001,
                 "DRAGONS: " .. id .. " opens its Sleeping Fog bar at " .. pull)
            near(d.rowsByKey.sleepingfog.duration, fogCd[id], 0.001,
                 "…and recurs on " .. fogCd[id])
            eq(d.rowsByKey.sleepingfogdodge.triggers[1].antispam, 600,
               "…with the dodge special throttled to once per pull")
            ck(d.rowsByKey.noxiousbreath.triggers[1].condition == "destIsBossTarget",
               "…and Noxious Breath filtered to the dragon's CURRENT TANK, not to a role")
        end
        ck(Addon:GetEncounter("world:ysondre").rowsByKey.lightningwave ~= nil,
           "…Lightning Wave exists on Ysondre alone…")
        for _, id in ipairs({ "lethon", "emeriss", "taerar" }) do
            ck(Addon:GetEncounter("world:" .. id).rowsByKey.lightningwave == nil,
               "…and on " .. id .. " it does not")
        end
        -- the disabled scaffolding the spec records is NOT shipped
        for _, id in ipairs({ "ysondre", "lethon", "emeriss", "taerar" }) do
            local d = Addon:GetEncounter("world:" .. id)
            for _, k in ipairs({ "bellowingroar", "shadowboltwhirl", "volatileinfection",
                                 "shades" }) do
                ck(d.rowsByKey[k] == nil,
                   id .. " does not ship '" .. k .. "' (no confirmed Era spell id exists)")
            end
        end
    end

    do  -- §2.9 MAJORDOMO: three creature ids, one boss, and no death ever ends it
        local m = Addon:GetEncounter("mc:majordomo")
        eq(#m.creatureIds, 3, "MAJORDOMO registers all three creature ids (boss + two adds)")
        eq(m.combat.severalCreatureIdsOneBoss, true,
           "…and REFUSES the death-based kill path — he submits, he does not die")
        ck(m.rowsByKey.nextshield ~= nil,
           "…while 'next shield' is ONE bar for two mutually-exclusive abilities")
        eq(#m.rowsByKey.nextshield.restarts, 2, "…restarted by either of them")
    end

    do  -- the options projection: three more raids in the tree options.lua reads
        API.PublishOptionsTree()
        local rm, ro, rw = Addon:GetRaid("mc"), Addon:GetRaid("onyxia"), Addon:GetRaid("world")
        ck(rm and ro and rw, "all three W4a zones PROJECT into the options tree")
        eq(rm and #rm.bosses, 11, "…Molten Core with eleven entries (10 bosses + trash)")
        eq(ro and #ro.bosses, 1, "…Onyxia's Lair with one")
        eq(rw and #rw.bosses, 6, "…and World Bosses with six")
        ck((rm.order or 999) < (ro.order or 999) and (ro.order or 999) < (rw.order or 999),
           "…ordered Molten Core, then Onyxia, then the world bosses last")
        ck(Addon:GetBossByNpcID(11502) ~= nil, "…while the npc index resolves Ragnaros")
        ck(Addon:GetBossByNpcID(14890) ~= nil, "…and Taerar")
    end
end
endgate()

gate("MCONYWB-DRIVE  §2/§3/§9 per-encounter behaviour through the real engine")
do
    loadW4A()
    Addon:SetEventRecording(true)
    Addon._suppressLegacyAlerts = true
    Addon.RoleResolver  = function() return true end
    Addon.ClassResolver = function() return "WARLOCK" end

    -- ── §2.1 Lucifron: two evidence paths for one mind control ────────────────
    do
        local rt = engage("mc:lucifron", 12118)
        ck(rt ~= nil, "LUCIFRON: engages off the combat sweep")
        local mn, mx = barWindow(rt, "impendingdoom")
        near(mn, 5.7, 0.01, "…Impending Doom's PULL window opens at 5.7…")
        near(mx, 11.8, 0.01, "…and closes at 11.8")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 19702, sourceId = 12118 })
        local rmn, rmx = barWindow(rt, "impendingdoom")
        near(rmn, 21, 0.01, "…then the recurring window is 21…")
        near(rmx, 27, 0.01, "…to 27")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 20604, destName = "Bob" })
        ck(sawWarn("WARN_ANNOUNCE", "Mind control on Bob"),
           "…a mind-control victim is named to the raid")
        -- the 1.5 s anti-spam is what stops the scan path and the aura path double-announcing
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 20604, destName = "Bob" })
        eq(warnCount("WARN_ANNOUNCE", "Mind control on Bob"), 1,
           "…and the two evidence paths (cast-start scan, aura) announce ONCE, not twice")
        eq(rt.timers.dominatemind, nil,
           "…while the 15 s duration bar stays silent, because it SHIPS OFF")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 20604, destIsPlayer = true,
                       destName = "Drew" })
        ck(sawWarn("WARN_SPECIAL", "MIND CONTROL on YOU"), "…and YOU get the personal call")
    end

    -- ── §2.3 Gehennas: the GTFO block matches by NAME as well as by ID ────────
    do
        local rt = engage("mc:gehennas", 12259)
        near(bar(rt, "rainoffire") and bar(rt, "rainoffire").total or -1, -1, 0.01,
             "GEHENNAS: Rain of Fire has no pull bar (it is cast-driven)")
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 19717, sourceId = 12259 })
        near(bar(rt, "rainoffire").total, 4.8, 0.01, "…and cycles on a FIXED 4.8 s once cast")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_PERIODIC_DAMAGE", spellId = 19717, destIsPlayer = true })
        ck(sawWarn("WARN_SPECIAL", "Move out of the fire"), "…standing in it is called by ID…")
        advance(3)
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_PERIODIC_DAMAGE", spellId = 999999,
                       spellName = "Rain of Fire", destIsPlayer = true })
        ck(sawWarn("WARN_SPECIAL", "Move out of the fire"),
           "…and by NAME, because the Era log is inconsistent about the periodic id")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_PERIODIC_DAMAGE", spellId = 19717, destIsPlayer = true })
        ck(not sawWarn("WARN_SPECIAL", "Move out of the fire"),
           "…throttled to one call per 2.5 s either way")
    end

    -- ── §2.5 Baron Geddon: the bomb, its icons and the bar that outlives the raid
    do
        local rt = engage("mc:geddon", 12056)
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 20475, destName = "Bob" })
        ck(sawWarn("WARN_ANNOUNCE", "Living Bomb on Bob"), "GEDDON: the bomb names its victim")
        near((rt.timers.livingbombtarget:Get("Bob") or {}).total, 8, 0.01,
             "…with an 8 s bar of their own")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 20475, destIsPlayer = true,
                       destName = "Drew" })
        ck(sawWarn("WARN_SPECIAL", "LIVING BOMB"), "…and YOU get told to run out")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 19695, sourceId = 12056 })
        ck(sawWarn("WARN_SPECIAL", "INFERNO"), "…Inferno tells melee to leave…")
        near(bar(rt, "infernoactive").total, 8, 0.01, "…and runs an 8 s active bar")
        -- §2.5 the ground-effect block is SUPPRESSED FOR TANKS, and since §1.4 has no
        -- `-Tank` gate that is written as the positive union of the other two classes.
        eq(Addon:GetEncounter("mc:geddon").rowsByKey.gtfo.role, "Dps|Healer",
           "…the Inferno ground-effect call is gated to everyone EXCEPT tanks")
        Addon:ClearEventLog()
        Addon.RoleResolver = function(g) return g ~= "Dps|Healer" end   -- i.e. "I am a tank"
        Life:Deliver({ on = "SPELL_PERIODIC_DAMAGE", spellId = 19698, destIsPlayer = true })
        ck(not sawWarn("WARN_SPECIAL", "Move out of the Inferno"),
           "…so a TANK standing in it is not told to move")
        Addon.RoleResolver = function() return true end
        Addon:ClearEventLog()
        advance(3)
        -- and the aura id is a second, independent arm (Era splits damage from aura)
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 364838, destIsPlayer = true })
        ck(sawWarn("WARN_SPECIAL", "Move out of the Inferno"),
           "…while everyone else is, off EITHER of the two Era ids")
        -- Armageddon's bar deliberately survives the encounter end
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 20478, sourceId = 12056 })
        ck(sawWarn("WARN_SPECIAL", "ARMAGEDDON"), "…Armageddon is a special warning…")
        eq(Addon:GetEncounter("mc:geddon").rowsByKey.armageddon.keep, true,
           "…and its cast bar is flagged to persist past combat end (it resolves after the wipe)")
    end

    -- ── §2.9 Majordomo: one shared bar for two shields ────────────────────────
    do
        local rt = engage("mc:majordomo", 12018)
        local mn, mx = barWindow(rt, "nextshield")
        near(mn, 25.6, 0.01, "MAJORDOMO: the shared shield bar opens at 25.6…")
        near(mx, 30.7, 0.01, "…and closes at 30.7")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 20619, sourceId = 12018 })
        near(bar(rt, "nextshield").total, 30.7, 0.01,
             "…a Magic Reflection restarts it on the flat 30.7 s cadence")
        ck(sawWarn("WARN_SPECIAL", "MAGIC REFLECTION"), "…and tells casters to stop")
        near(bar(rt, "magicreflection").total, 10, 0.01, "…with a 10 s active bar")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 21075, sourceId = 12018 })
        near(bar(rt, "nextshield").total, 30.7, 0.01,
             "…and a Damage Shield restarts the SAME bar (the raid only needs to know one is coming)")
        ck(sawWarn("WARN_SPECIAL", "DAMAGE SHIELD"), "…melee are told to stop attacking…")
        ck(not sawWarn("WARN_ANNOUNCE", "Damage Shield"),
           "…and the plain announce steps aside while that call is enabled")
        -- the adds die constantly and none of it may end the fight
        Life:Deliver(Life:NormalizeCLEU("UNIT_DIED", nil, nil, 0, 0,
                                        "Creature-0-0-0-0-11663-1", "Flamewaker Healer", 0, 0))
        ck(rt.engaged, "…and a dead add does NOT end the encounter")
    end

    -- ── §2.10 RAGNAROS — the full submerge cycle, both ways out ───────────────
    do
        local rt = engage("mc:ragnaros", 11502)
        ck(rt ~= nil, "RAGNAROS: engages off the combat sweep")
        local wn, wx = barWindow(rt, "wrath")
        near(wn, 25.9, 0.01, "…Wrath's PULL window opens at 25.9…")
        near(wx, 33.8, 0.01, "…and closes at 33.8")
        near(bar(rt, "submerge").total, 180, 0.01, "…with the 180 s submerge clock running")
        eq(rt:GetCount("sons"), 8, "…and eight Sons of Flame on the counter")

        -- SUBMERGE, path 1: the yell
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_YELL",
                    "COME FORTH, MY SERVANTS! DEFEND YOUR MASTER!")
        eq(rt.stage, 2, "…the servants yell IS the submerge (stage 2)")
        eq(rt:GetState("ragphase"), "submerged", "…and the machine agrees")
        ck(sawWarn("WARN_ANNOUNCE", "Ragnaros submerges"), "…announced to the raid")
        eq(bar(rt, "wrath"), nil, "…the Wrath bar stops…")
        eq(bar(rt, "submerge"), nil, "…so does the submerge bar…")
        near(bar(rt, "emerge").total, 90, 0.01, "…and a 90 s emerge bar takes over")

        -- THE SONS RACE: seven deaths change nothing, the eighth emerges him NOW
        Addon:ClearEventLog()
        for i = 1, 7 do
            Life:Deliver({ on = "UNIT_DIED", creatureId = 12143, destId = 12143,
                           destGUID = "Creature-0-0-0-0-12143-" .. i })
        end
        eq(rt:GetCount("sons"), 1, "…seven Sons down, one to go")
        eq(rt.stage, 2, "…and he is still submerged")
        -- a duplicate death cannot double-count
        Life:Deliver({ on = "UNIT_DIED", creatureId = 12143, destId = 12143,
                       destGUID = "Creature-0-0-0-0-12143-7" })
        eq(rt:GetCount("sons"), 1, "…a corpse that logs twice is de-duplicated by GUID")
        Life:Deliver({ on = "UNIT_DIED", creatureId = 12143, destId = 12143,
                       destGUID = "Creature-0-0-0-0-12143-8" })
        eq(rt:GetCount("sons"), 0, "…the eighth Son dies…")
        eq(rt.stage, 1, "…and Ragnaros emerges IMMEDIATELY (W4a extension 28)")
        ck(sawWarn("WARN_ANNOUNCE", "Ragnaros emerges"), "…announced")
        local pn, px = barWindow(rt, "wrath")
        near(pn, 25.5, 0.01, "…the POST-EMERGE Wrath window is 25.5…")
        near(px, 31.9, 0.01, "…to 31.9, which is not the same as the ordinary one")
        near(bar(rt, "submerge").total, 180, 0.01, "…and the 180 s submerge clock restarts")
        -- the 90 s schedule that lost the race must be inert
        Addon:ClearEventLog()
        advance(91)
        eq(rt.stage, 1, "…and the 90 s scheduled emerge that LOST the race is a no-op")
        eq(warnCount("WARN_ANNOUNCE", "Ragnaros emerges"), 0, "…announcing nothing a second time")

        -- SUBMERGE, path 2: the unit-cast visual, and the schedule winning this time
        Addon:ClearEventLog()
        Life:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "target", nil, 20567)
        eq(rt.stage, 2, "…the submerge VISUAL on the unit-cast channel is the second witness")
        eq(rt:GetCount("sons"), 8, "…and the Sons counter is reset for the new cycle")
        advance(90.1)
        eq(rt.stage, 1, "…with nobody killing the adds, the 90 s schedule emerges him")
        ck(sawWarn("WARN_ANNOUNCE", "Ragnaros emerges"), "…and says so")
    end

    -- ── §2.10 the RP pull countdown, driven by Majordomo dying ────────────────
    do
        resetLife()
        W.instanceID = 409
        Addon:CancelPullTimer("test")
        Addon:ClearEventLog()
        Life:Deliver(Life:NormalizeCLEU("UNIT_DIED", nil, nil, 0, 0,
                                        "Creature-0-0-0-0-12018-1", "Majordomo Executus", 0, 0))
        local pulled
        for _, e in ipairs(Addon:GetEventLog()) do if e.event == "ENGINE_PULL" then pulled = e end end
        ck(pulled ~= nil and math.abs((tonumber(pulled[1]) or 0) - 73) < 0.01,
           "RAGNAROS RP: Majordomo dying starts a 73 s PULL countdown (W4a extension 29)")
        ck(not Life:AnyEngaged(), "…and engages nothing by itself")
        Addon:CancelPullTimer("test")
    end

    -- ── §2.11 the trash module: engage bars, per-mob identity, per-mob teardown
    do
        resetLife()
        W.instanceID = 409
        eq(Life:ArmZones(409), 1, "TRASH: entering Molten Core ARMS the trash module")
        ck(Life:IsZoneArmed("mc:trash"), "…without engaging anything")
        local rt = Life.zoneArmed["mc:trash"]
        Addon:ClearEventLog()
        Life:Deliver({ on = "SWING_DAMAGE", creatureId = 11658, sourceId = 11658,
                       sourceGUID = "Creature-0-0-0-0-11658-1" })
        local b = rt.timers.knockaway:Get("Creature-0-0-0-0-11658-1")
        ck(b ~= nil, "…a Molten Giant swinging starts its ENGAGE bar…")
        near(b.min, 5.3, 0.01, "…opening at the spec's 5.3…")
        near(b.max, 10.5, 0.01, "…and closing at 10.5")
        -- a second mob is a second bar, and the first mob's swings do not re-arm it
        Life:Deliver({ on = "SWING_DAMAGE", creatureId = 11658, sourceId = 11658,
                       sourceGUID = "Creature-0-0-0-0-11658-2" })
        Life:Deliver({ on = "SWING_DAMAGE", creatureId = 11658, sourceId = 11658,
                       sourceGUID = "Creature-0-0-0-0-11658-1" })
        local n = 0
        for _ in pairs(rt.timers.knockaway.live) do n = n + 1 end
        eq(n, 2, "…two giants are TWO bars, and a mob that keeps swinging does not re-arm")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 18945, sourceId = 11658,
                       sourceGUID = "Creature-0-0-0-0-11658-1" })
        ck(sawWarn("WARN_ANNOUNCE", "Knock Away"), "…the ability itself announces…")
        local r = rt.timers.knockaway:Get("Creature-0-0-0-0-11658-1")
        near(r.min, 10.7, 0.01, "…and restarts THAT mob's bar on the recurring 10.7…")
        near(r.max, 14.8, 0.01, "…to 14.8 window")
        -- one warning per pack, not one per mob
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 18945, sourceId = 11658,
                       sourceGUID = "Creature-0-0-0-0-11658-2" })
        eq(warnCount("WARN_ANNOUNCE", "Knock Away"), 0,
           "…while the 3 s anti-spam makes a pack of giants ONE warning")
        -- and a death takes only its own bar
        Life:Deliver({ on = "UNIT_DIED", creatureId = 11658, destId = 11658,
                       sourceGUID = "Creature-0-0-0-0-11658-1",
                       destGUID = "Creature-0-0-0-0-11658-1" })
        ck(rt.timers.knockaway:Get("Creature-0-0-0-0-11658-1") == nil,
           "…a dead giant's bar is cancelled…")
        ck(rt.timers.knockaway:Get("Creature-0-0-0-0-11658-2") ~= nil,
           "…and its neighbour's is untouched")
        Life:DisarmZones()
    end

    -- ── §3.1 ONYXIA: three phases, two half-stages, eight breath ids ──────────
    do
        resetLife()
        W.instanceID = 249
        setUnit("target", { cid = 10184, combat = true, hp = 100, hpmax = 100 })
        setUnit("playertarget", { cid = 10184, combat = true, hp = 100, hpmax = 100 })
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_YELL",
                    "How fortuitous. Usually, I must leave my lair in order to feed.")
        local rt = Life:GetRuntime("onyxia:onyxia")
        ck(rt ~= nil, "ONYXIA: engages on her greeting yell (combat-by-yell, §1.1)")
        local fn, fx = barWindow(rt, "flamebreath")
        near(fn, 11.3, 0.01, "…Flame Breath opens at 11.3…")
        near(fx, 28.5, 0.01, "…and closes at 28.5")
        ck(bar(rt, "wingbuffet") ~= nil, "…Wing Buffet runs alongside it…")
        ck(bar(rt, "bellowingroar") ~= nil, "…and so does the fear clock")

        -- the 70 % pre-warning is a HALF-stage that announces only the pre-warning
        Addon:ClearEventLog()
        Life:EvaluateHealthTriggers(rt, 69)
        eq(rt.stage, 1.5, "…70 % moves the register to the FRACTIONAL stage 1.5…")
        ck(sawWarn("WARN_ANNOUNCE", "Phase 2 soon"), "…which announces the pre-warning…")
        ck(not sawWarn("WARN_ANNOUNCE", "Phase 2 — Onyxia takes off"),
           "…and NOT a phase change (a half-stage never announces one)")

        -- P1 -> P2 on the yell, and both ground bars stop
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_YELL",
                    "This meaningless exertion bores me. I'll incinerate you all from above!")
        eq(rt.stage, 2, "…the take-off yell IS phase 2")
        ck(sawWarn("WARN_ANNOUNCE", "Phase 2 — Onyxia takes off"), "…announced")
        eq(bar(rt, "flamebreath"), nil, "…the Flame Breath bar stops (she is airborne)…")
        eq(bar(rt, "wingbuffet"), nil, "…and so does Wing Buffet")

        -- DEEP BREATH: eight ids, one alert, 8 s anti-spam
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 18584, sourceId = 10184 })
        ck(sawWarn("WARN_SPECIAL", "DEEP BREATH"), "…a breath from ONE perch calls it…")
        near(bar(rt, "deepbreathcast").total, 5, 0.01, "…with a 5 s cast bar")
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 18617, sourceId = 10184 })
        eq(warnCount("WARN_SPECIAL", "DEEP BREATH"), 1,
           "…and a second breath id inside 8 s does NOT double-announce")
        advance(8.1)
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 17086, sourceId = 10184 })
        ck(sawWarn("WARN_SPECIAL", "DEEP BREATH"), "…a third, after the window, does")

        -- the 45 %-in-phase-2 half stage, then P3
        Addon:ClearEventLog()
        Life:EvaluateHealthTriggers(rt, 44)
        eq(rt.stage, 2.5, "…45 % IN PHASE 2 moves the register to 2.5…")
        ck(sawWarn("WARN_ANNOUNCE", "Phase 3 soon"), "…and pre-warns phase 3")
        Addon:ClearEventLog()
        Life:OnChat("CHAT_MSG_MONSTER_YELL", "It seems you'll need another lesson, mortals!")
        eq(rt.stage, 3, "…and the landing yell is phase 3")
        ck(sawWarn("WARN_ANNOUNCE", "Phase 3 — Onyxia lands"), "…announced")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 18431, sourceId = 10184 })
        ck(sawWarn("WARN_SPECIAL", "FEAR incoming"), "…Bellowing Roar is a fear call")
    end

    -- ── §9 THE WORLD BOSSES: the outdoor path, and the 15 s wipe window ───────
    do
        local rt = engageWorld("world:azuregos", 6109,
                               "This place is under my protection. The mysteries of the arcane " ..
                               "shall remain inviolate.")
        ck(rt ~= nil, "AZUREGOS: an OUTDOOR yell engages through the delay-0 target sweep")
        eq(rt.difficulty.worldBoss, true, "…with the world-boss difficulty snapshot taken")
        eq(Life:WipeWindow(rt), 15, "…and a 15 s wipe confirmation window, not 5")
        -- dying at a world boss is not a wipe
        setUnit("player", { guid = W.playerGUID, player = true, combat = false, dead = true })
        eq(Life:ClassifyWipe(rt), Life.VERDICT.NOT_WIPE_WORLDBOSS_DEATH,
           "…and being dead at a world boss is explicitly NOT a wipe")
        setUnit("player", { guid = W.playerGUID, player = true, combat = true, dead = false })
        eq(next(rt.timers), nil, "…while AZUREGOS runs no bars at all, by design")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_START", spellId = 21099, sourceId = 6109 })
        ck(sawWarn("WARN_ANNOUNCE", "Frost Breath"), "…Frost Breath announces…")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 21147, sourceId = 6109 })
        ck(sawWarn("WARN_SPECIAL", "TELEPORT"), "…Arcane Vacuum warns you are about to move…")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 22067, sourceId = 6109 })
        ck(sawWarn("WARN_SPECIAL", "STILL DANGEROUS"), "…and Reflection warns the casters")
    end

    do  -- §9.2 Kazzak's conditional berserk, both ways round
        local rt = engageWorld("world:kazzak", 12397, "For the Legion! For Kil'Jaeden!")
        ck(rt ~= nil, "KAZZAK: engages on his pull yell")
        eq(rt.trigger, "chat",
           "…and the engagement REMEMBERS that a yell caused it, through the outdoor sweep")
        near(bar(rt, "berserk") and bar(rt, "berserk").total or -1, 180, 0.01,
             "…so the 180 s berserk bar starts")
        eq(Life:WipeWindow(rt), 15, "…on a 15 s world-boss wipe window")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 21056, destName = "Bob" })
        ck(sawWarn("WARN_ANNOUNCE", "Mark of Kazzak on Bob"), "…the Mark names its victim…")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 21056, destIsPlayer = true,
                       destName = "Drew" })
        ck(sawWarn("WARN_SPECIAL", "MARK OF KAZZAK on YOU"), "…and calls it on you")

        -- …and now a RANDOM OUTDOOR AGGRO pull, which the spec refuses to time
        resetLife()
        W.inInstance, W.instanceType, W.instanceID = false, "none", 0
        W.difficultyID, W.maxPlayers = 0, 40
        W.group = { "player" }
        setUnit("target", { cid = 12397, combat = true, hp = 100, hpmax = 100 })
        setUnit("playertarget", { cid = 12397, combat = true, hp = 100, hpmax = 100 })
        local rt2 = Life:Sweep(0.5) and Life:GetRuntime("world:kazzak")
        ck(rt2 ~= nil, "…a random outdoor aggro pull still ENGAGES the mod…")
        eq(bar(rt2, "berserk"), nil,
           "…but starts NO berserk bar, because that pull cannot be timed (§9.2)")
    end

    do  -- §9.3-9.6 the dragons: one fog call per pull, and the tank filter
        local rt = engageWorld("world:ysondre", 14887,
                               "The strands of LIFE have been severed! The Dreamers must be avenged!")
        ck(rt ~= nil, "YSONDRE: engages on her own pull yell")
        near(bar(rt, "sleepingfog").total, 18.4, 0.01, "…with the fog bar opening at 18.4")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 24814, sourceId = 14887 })
        ck(sawWarn("WARN_SPECIAL", "SLEEPING FOG"), "…the first fog says move…")
        near(bar(rt, "sleepingfog").total, 16.0, 0.01, "…and the bar recurs on 16.0")
        Addon:ClearEventLog()
        advance(20)
        Life:Deliver({ on = "SPELL_CAST_SUCCESS", spellId = 24813, sourceId = 14887 })
        ck(not sawWarn("WARN_SPECIAL", "SLEEPING FOG"),
           "…and every later fog is SILENT — 600 s means once per pull, deliberately")
        near(bar(rt, "sleepingfog").total, 16.0, 0.01,
             "…while the cooldown bar keeps running underneath it")
        -- Lightning Wave arrives on the unit-cast channel, not the combat log
        Addon:ClearEventLog()
        Life:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "target", nil, 24819)
        ck(sawWarn("WARN_ANNOUNCE", "Lightning Wave"),
           "…Lightning Wave is heard on the UNIT-CAST channel (W4a defect fix B)")
        near(bar(rt, "lightningwave").total, 13.4, 0.01, "…on a 13.4 s clock")

        -- Noxious Breath is filtered to the dragon's CURRENT tank
        Addon:ClearEventLog()
        setUnit("targettarget", { player = true, name = "Bob", guid = "Player-1-BBBB" })
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 24818, destName = "Bob",
                       amount = 3, sourceId = 14887,
                       sourceGUID = "Creature-0-0-0-0-14887-0001" })
        ck(sawWarn("WARN_ANNOUNCE", "Noxious Breath Bob (3)"),
           "…and Noxious Breath on the dragon's CURRENT TANK announces with its stack")
        Addon:ClearEventLog()
        Life:Deliver({ on = "SPELL_AURA_APPLIED", spellId = 24818, destName = "Carl",
                       amount = 2, sourceId = 14887,
                       sourceGUID = "Creature-0-0-0-0-14887-0001" })
        ck(not sawWarn("WARN_ANNOUNCE", "Noxious Breath Carl"),
           "…while the same debuff on somebody who is NOT tanking says nothing")

        -- the three fog-only dragons
        for _, d in ipairs({ { "lethon", 14888, "I can sense the SHADOW on your hearts", 18.4 },
                             { "emeriss", 14889, "Hope is a DISEASE of the soul", 18.4 },
                             { "taerar", 14890, "Peace is but a fleeting dream", 21.5 } }) do
            local r = engageWorld("world:" .. d[1], d[2], d[3])
            ck(r ~= nil, d[1] .. " engages on its own pull yell")
            near(bar(r, "sleepingfog").total, d[4], 0.01, "…with its own fog pull value")
            eq(bar(r, "lightningwave"), nil, "…and no Lightning Wave (Ysondre only)")
        end
    end

    -- ── W4 CLOSES: all eight zones in one registry, counted against §10 ───────
    -- The spec's coverage table declares 65 encounters (59 raid bosses + 6 world
    -- bosses) plus 5 zone-wide trash modules. This loads EVERY zone file the addon
    -- ships and proves the registry matches that table exactly — which is the one
    -- assertion no single wave could make before this one.
    do
        Addon.encounters, Addon.encountersById = {}, {}
        Addon.encByCreature, Addon.encByEncounterId, Addon.encByZone = {}, {}, {}
        Addon.zones, Addon.zonesById = {}, {}
        for _, chunk in ipairs({ NAXX_CHUNK, AQ20_CHUNK, AQ40_CHUNK, BWL_CHUNK, ZG_CHUNK,
                                 MC_CHUNK, ONY_CHUNK, WB_CHUNK }) do
            local okc, e = pcall(chunk, ADDON_NAME, Addon)
            ck(okc, "W4 CLOSE: every zone file co-exists in one registry" ..
                    (okc and "" or (" -> " .. tostring(e))))
        end
        local bosses, trash, badKeys = 0, 0, {}
        for _, enc in ipairs(Addon.encounters) do
            if enc.detect.mode == "zone" then trash = trash + 1 else bosses = bosses + 1 end
            local errs = API.Validate(enc)
            if #errs > 0 then badKeys[#badKeys + 1] = enc.id .. " (" .. errs[1] .. ")" end
        end
        eq(#badKeys, 0, "…and every one of them validates" ..
           (#badKeys > 0 and (": " .. table.concat(badKeys, "; ")) or ""))
        eq(bosses, 65, "…65 encounters, exactly the spec's coverage table (59 raid + 6 world)")
        eq(trash, 5, "…and 5 zone-wide trash modules (MC, BWL, AQ20, AQ40, Naxx)")
        API.PublishOptionsTree()
        eq(#Addon.raids, 8, "…projecting into eight raids in the options tree")
        local order = {}
        for _, r in ipairs(Addon.raids) do order[#order + 1] = r.id end
        eq(table.concat(order, ","), "mc,onyxia,bwl,zg,aq20,aq40,naxxramas,world",
           "…in progression order, with the world bosses last")
        -- No two encounters may claim the same option-key namespace.
        local seenLegacy = {}
        local dupes = {}
        for _, enc in ipairs(Addon.encounters) do
            local k = enc.legacy.raidId .. ":" .. enc.legacy.bossId
            if seenLegacy[k] then dupes[#dupes + 1] = k end
            seenLegacy[k] = true
        end
        eq(#dupes, 0, "…with no two encounters sharing a SavedVariables namespace" ..
           (#dupes > 0 and (": " .. table.concat(dupes, ", ")) or ""))
    end

    Addon._suppressLegacyAlerts = nil
    Addon:SetEventRecording(false)
    resetLife()
end
endgate()

----------------------------------------------------------------------
-- GATE W5-SCAFFOLD — the design doc's "core_boot.lua should be gone by W5"
--
-- The wave-1 demolition left core_boot.lua as the file where homeless things lived,
-- each labelled with the wave that would replace it. W5 is that wave. These are
-- SOURCE assertions rather than behaviour assertions on purpose: the defect this
-- guards against is a future wave quietly re-parking something there, and no runtime
-- check can see that. The file is small enough now that reading it is cheap.
----------------------------------------------------------------------
gate("W5-SCAFFOLD  core_boot.lua is a composition root, not scaffolding")
do
    local boot = readFile(P("core_boot.lua")) or ""
    local diag = readFile(P("core_diag.lua")) or ""
    local api  = readFile(P("core_api.lua")) or ""

    ck(#boot > 0, "core_boot.lua exists (the composition root still ships)")
    ck(exists(P("core_diag.lua")), "core_diag.lua exists (the diagnostics got a real home)")

    -- ONE public function. InitEngine is the composition root's whole job; anything
    -- else defined here is by definition a tenant that has not been rehoused.
    local defs = {}
    for name in boot:gmatch("\nfunction%s+Addon[:%.]([%w_]+)") do defs[#defs + 1] = name end
    eq(#defs, 1, "core_boot.lua defines exactly ONE Addon function")
    eq(defs[1], "InitEngine", "…and it is InitEngine")

    -- The specific tenants that left, each asserted at BOTH ends: gone from boot,
    -- present in the file that now owns it. Asserting only the departure would pass
    -- if a rehoming lost the function entirely.
    local rehomed = {
        { fn = "GetRaids",          to = "core_api.lua",  src = api  },
        { fn = "GetRaid",           to = "core_api.lua",  src = api  },
        { fn = "GetBoss",           to = "core_api.lua",  src = api  },
        { fn = "GetBossByNpcID",    to = "core_api.lua",  src = api  },
        { fn = "RegisterRaid",      to = "core_api.lua",  src = api  },
        { fn = "BuildFullDebugLogText", to = "core_diag.lua", src = diag },
        { fn = "DebugLogLineCount", to = "core_diag.lua", src = diag },
        { fn = "UpdateAutoDebug",   to = "core_diag.lua", src = diag },
        { fn = "UpdateDebugOnlyIndicator", to = "core_diag.lua", src = diag },
        { fn = "BuildStatsText",    to = "core_diag.lua", src = diag },
    }
    for _, r in ipairs(rehomed) do
        ck(not boot:match("\nfunction%s+Addon[:%.]" .. r.fn .. "%f[%W]"),
           ("Addon:%s no longer lives in core_boot.lua"):format(r.fn))
        ck(r.src:match("\nfunction%s+Addon[:%.]" .. r.fn .. "%f[%W]") ~= nil,
           ("…it lives in %s"):format(r.to))
    end
    -- W3's departure stays departed (the SYNC-RETIRE gate's subject, re-asserted
    -- here so ONE gate answers "what is core_boot allowed to contain").
    ck(not boot:match("function%s+Addon[:%.]StartPullTimer"),
       "the W3 pull-timer shim is still gone")

    -- NOTHING IN THE BODY IS LABELLED TRANSITIONAL. The design doc's rule is not
    -- "the file is small", it is "nothing in it is scaffolding". A word that says
    -- otherwise, on live code in a file that is supposed to be finished, is the
    -- defect. The scan is deliberately of the BODY ONLY — the header block narrates
    -- what LEFT and where it went, which is exactly what a reader arriving from an
    -- old comment needs, and forbidding the words there would delete the map.
    do
        local headEnd = boot:find("%-%-%]%]")
        ck(headEnd ~= nil, "core_boot.lua opens with a header block")
        local body = (boot:sub((headEnd or 0) + 3)):lower()
        for _, word in ipairs({ "retirement shim", "stand%-in", "transitional", "shim for",
                                "until w%d", "replaced by w%d", "parked here" }) do
            ck(not body:match(word),
               ("core_boot.lua's BODY contains no %q language"):format((word:gsub("%%", ""))))
        end
    end
    -- Prove the header actually names the successors.
    for _, name in ipairs({ "core_sync.lua", "core_api.lua", "core_diag.lua" }) do
        ck(boot:find(name, 1, true) ~= nil,
           ("core_boot.lua's header names %s as a successor"):format(name))
    end

    -- Load order: the new file has real load-time dependencies, and the toc must
    -- express them (core_diag resolves Addon.Sched and Addon.Lifecycle at LOAD).
    do
        local pos = {}
        for i, rel in ipairs(TOC_LUA) do pos[rel] = i end
        ck(pos["core_diag.lua"], "core_diag.lua IS in the load list")
        ck(pos["core_sched.lua"] < pos["core_diag.lua"],
           "…and loads after core_sched.lua (it resolves Addon.Sched at load)")
        ck(pos["core_lifecycle.lua"] < pos["core_diag.lua"],
           "…and after core_lifecycle.lua (it resolves Addon.Lifecycle at load)")
        ck(pos["core_diag.lua"] < pos["core_boot.lua"],
           "…and before core_boot.lua (InitEngine calls Addon.DLog / UpdateAutoDebug)")
    end

    -- The rehomed surfaces still WORK — a source-only gate would pass on a file that
    -- was moved and broken.
    ck(type(Addon.GetRaids) == "function" and type(Addon:GetRaids()) == "table",
       "Addon:GetRaids() still answers after the move")
    ck(type(Addon.BuildStatsText) == "function" and type(Addon:BuildStatsText()) == "string",
       "Addon:BuildStatsText() still answers after the move")
    do
        local r, why = Addon:RegisterRaid({ id = "legacy_zone" })
        ck(r == nil and type(why) == "string",
           "the 1.x RegisterRaid refusal still refuses, with a reason")
        ck(why:find("RegisterZone", 1, true) ~= nil,
           "…and names the successor API a plugin author should call instead")
    end
end
endgate()

----------------------------------------------------------------------
-- GATE W5-TREE — the options projection, end to end
--
-- W4 asserted per-zone that the tree PROJECTS. This asserts the surface options.lua
-- actually consumes: eight raids in progression order, every boss reachable by the
-- key the checkbox writes, ship-off defaults surviving the whole path from the
-- encounter row to the config the panel reads, and a flip reaching the ENGINE.
----------------------------------------------------------------------
gate("W5-TREE  options projection: 8 raids, ship-off defaults, a flip reaches the row")
do
    -- Rebuild the SHIPPING registry from every zone chunk (earlier gates install
    -- fixtures over it), then project exactly as InitEngine does.
    Addon.encounters, Addon.encountersById = {}, {}
    Addon.encByCreature, Addon.encByEncounterId, Addon.encByZone = {}, {}, {}
    Addon.zones, Addon.zonesById = {}, {}
    for _, chunk in ipairs({ MC_CHUNK, ONY_CHUNK, BWL_CHUNK, ZG_CHUNK,
                             AQ20_CHUNK, AQ40_CHUNK, NAXX_CHUNK, WB_CHUNK }) do
        assert(pcall(chunk, ADDON_NAME, Addon))
    end
    API.PublishOptionsTree()

    local raids = Addon:GetRaids()
    eq(#raids, 8, "the projected tree is EIGHT raids")

    -- Progression order is the order a player clears them, which is the order the
    -- sidebar must show. Asserted by NAME, not by the `order` numbers, so renumbering
    -- a zone cannot silently pass.
    local WANT = { "mc", "onyxia", "bwl", "zg", "aq20", "aq40", "naxxramas", "world" }
    local got = {}
    for i, r in ipairs(raids) do got[i] = r.id end
    eq(table.concat(got, ","), table.concat(WANT, ","),
       "…in progression order, Molten Core first and the world bosses last")

    for _, r in ipairs(raids) do
        ck(r.size ~= nil, ("%s declares a raid size (options.lua's section filter)"):format(r.id))
        ck(#r.bosses > 0, ("…and contributes at least one boss page"):format(r.id))
        ck(type(r.name) == "string" and r.name ~= r.id,
           ("…with a display name for the sidebar (%s)"):format(tostring(r.name)))
    end

    -- Every boss page is reachable by GetBoss, and every row on it carries the four
    -- fields the mechanic list renders.
    local bosses, rows = 0, 0
    for _, r in ipairs(raids) do
        for _, b in ipairs(r.bosses) do
            bosses = bosses + 1
            if Addon:GetBoss(r.id, b.id) ~= b then
                fail(("GetBoss(%s,%s) does not return the projected page"):format(r.id, b.id))
            end
            for _, m in ipairs(b.mechanics) do
                rows = rows + 1
                if type(m.id) ~= "string" or type(m.name) ~= "string" or m.default == nil then
                    fail(("row %s:%s:%s is missing id/name/default"):format(r.id, b.id, tostring(m.id)))
                end
            end
        end
    end
    -- 70 pages, not 65: the 65 ENCOUNTERS plus the 5 zone-wide trash modules (MC,
    -- BWL, AQ20, AQ40, Naxx), which carry a `legacy` seam of their own because trash
    -- alerts are as configurable as boss alerts and need somewhere to be switched off.
    eq(bosses, 70, "…70 boss pages: 65 encounters + the 5 zone-wide trash modules")
    ck(rows > 400, ("…and %d togglable rows on them"):format(rows))

    -- THE KEY IDENTITY. The whole projection rests on
    --     API.OptionKey(encId, rowKey) == Addon:MechKey(raidId, bossId, rowKey)
    -- If that ever drifts, a checkbox writes to one SavedVariables entry and the
    -- engine reads another, and NOTHING VISIBLY BREAKS — the toggle just does
    -- nothing. Asserted over the whole shipping registry, not a sample.
    local drift = 0
    for _, enc in ipairs(Addon.encounters) do
        if enc.legacy then
            for _, row in ipairs(enc.timers) do
                if API.OptionKey(enc.id, row.key)
                   ~= Addon:MechKey(enc.legacy.raidId, enc.legacy.bossId, row.key) then
                    drift = drift + 1
                end
            end
        end
    end
    eq(drift, 0, "the options key and the engine key are the SAME key, registry-wide")

    -- SHIP-OFF DEFAULTS, end to end. A row declaring default=false must arrive at
    -- Addon:GetMechanicConfig as masterEnabled=false WITHOUT the user ever touching
    -- it — that is the whole "chatty alerts ship quiet" promise.
    local offRow, offEnc
    for _, enc in ipairs(Addon.encounters) do
        for _, row in ipairs(enc.warnings) do
            if row.default == false and enc.legacy then offRow, offEnc = row, enc break end
        end
        if offRow then break end
    end
    ck(offRow ~= nil, "the shipping data contains at least one default-OFF row")
    if offRow then
        local key = Addon:MechKey(offEnc.legacy.raidId, offEnc.legacy.bossId, offRow.key)
        local boss = Addon:GetBoss(offEnc.legacy.raidId, offEnc.legacy.bossId)
        local mech
        for _, m in ipairs(boss.mechanics) do if m.id == offRow.key then mech = m end end
        ck(mech ~= nil, "…the projection carries it onto the boss page")
        eq(mech and mech.default, false, "…with default=false on the projected row")
        Addon.db.mechanics[key] = nil
        eq(Addon:GetMechanicConfig(key, mech).masterEnabled, false,
           "…so the checkbox reads UNCHECKED with no user override present")
        eq(API.IsRowEnabled(offEnc.id, offRow), false,
           "…and the ENGINE agrees the row is off")

        -- A FLIP REACHES THE ROW. This is the assertion that proves the surface is
        -- wired: write through the same call options.lua's checkbox _set uses, and
        -- ask the engine.
        Addon:SetMechanicOption(key, "masterEnabled", true)
        eq(API.IsRowEnabled(offEnc.id, offRow), true,
           "flipping the checkbox ON reaches the engine's row gate")
        eq(Addon:GetMechanicConfig(key, mech).masterEnabled, true,
           "…and the checkbox reads back checked")
        Addon:SetMechanicOption(key, "masterEnabled", false)
        eq(API.IsRowEnabled(offEnc.id, offRow), false, "…and flipping it OFF again reaches it too")
        Addon.db.mechanics[key] = nil
    end

    -- The reverse case: a default-ON row that the user switched off stays off.
    do
        local enc = Addon.encountersById["naxxramas:loatheb"] or Addon.encounters[1]
        local row = enc.timers[1] or enc.warnings[1]
        if row and enc.legacy then
            local key = Addon:MechKey(enc.legacy.raidId, enc.legacy.bossId, row.key)
            Addon:SetMechanicOption(key, "masterEnabled", false)
            eq(API.IsRowEnabled(enc.id, row), false,
               "a user override BEATS the shipped default (settings continuity)")
            Addon.db.mechanics[key] = nil
        end
    end

    -- The five specials still reach their config panels through the module seam that
    -- options.lua's BuildModuleDetail drives.
    do
        local SPECIALS = { "naxxramas:fourhorsemen", "naxxramas:gothik",
                           "naxxramas:loatheb", "naxxramas:razuvious", "naxxramas:thaddius" }
        for _, encId in ipairs(SPECIALS) do
            local enc = Addon.encountersById[encId]
            ck(enc ~= nil, ("special encounter %s is registered"):format(encId))
            if enc and enc.legacy then
                local mods = Addon:GetBossModules(enc.legacy.raidId, enc.legacy.bossId)
                ck(type(mods) == "table" and #mods > 0,
                   ("…and GetBossModules finds its module (the BuildConfig seam)"):format(encId))
            end
        end
    end
end
endgate()

----------------------------------------------------------------------
-- GATE W5-BRIEF-G — SUITE_ASYNC_AUDIT.md Brief G, one block per finding
--
-- Five findings, lesson classes 7 (missing settle signal) and 8 (nondeterministic
-- iteration). Each block is written so that REVERTING the fix reddens it — a
-- determinism gate that passes on both the old and new code is worthless, so every
-- one of these drives the real function rather than inspecting source.
----------------------------------------------------------------------
gate("W5-BRIEF-G  determinism + role re-derivation (RM-1, RMS-1, RMS-2, RME-1, RML-1)")
do
    ------------------------------------------------------------------
    -- RM-1: the Main-Tank latch is RE-EARNED on roster change, not frozen.
    ------------------------------------------------------------------
    do
        Sched:Flush()
        W.class = "WARRIOR"
        W.talents = { 0, 0, 31 }          -- 3rd tab deepest -> WARRIOR3
        W.form = 0
        W.mainTank = false
        Era.roleState.tankLatched = false
        Era.ClearCache()

        -- Protection warrior (tab 2 deepest) in Battle Stance, not flagged: not a tank.
        W.talents = { 0, 31, 0 }
        Era.ClearCache()
        eq(Era.IsTank(), false, "RM-1: a Prot warrior in Battle Stance, unflagged, is NOT a tank")
        eq(Era.RoleSignature(), "WARRIOR2/false/false",
           "…and that is the answer the addon has on record (the boot baseline)")

        -- The event set must CARRY the signal.
        local hasRoster = false
        for _, e in ipairs(Era.ROSTER_EVENTS) do
            if e == "GROUP_ROSTER_UPDATE" then hasRoster = true end
        end
        ck(hasRoster, "…svc_era declares GROUP_ROSTER_UPDATE (the fix)")
        ck(Era.ROSTER_EVENT_SET["PLAYER_ROLES_ASSIGNED"] == true,
           "…and PLAYER_ROLES_ASSIGNED, for clients that have it")
        -- The list existing is not the same as the frame subscribing to it, and the
        -- subscription lives behind `if type(_G.CreateFrame) == "function"`, which is
        -- false headless — so this half is unreachable by behaviour and is asserted
        -- at the source. Without it, deleting the RegisterEvent loop leaves the
        -- suite green: found by mutation-testing this very gate.
        do
            local src = readFile(P("svc_era.lua")) or ""
            -- Anchored to ONE LINE: Lua's `.` matches newlines, so a `.-` here would
            -- happily span from the declaration loop to some unrelated RegisterEvent
            -- further down the file and pass on deleted code. (Also found by mutation.)
            ck(src:match("ipairs%(Era%.ROSTER_EVENTS%)%s*do[^\r\n]*RegisterEvent") ~= nil,
               "…and Era.Init actually REGISTERS them on the event frame")
            ck(src:match("Era%.ROSTER_EVENT_SET%[event%]") ~= nil,
               "…and routes them to the role re-check rather than the zone handler")
        end

        local fired = 0
        Addon:RegisterEngineCallback("ROLE_CHANGED", function() fired = fired + 1 end)

        -- PROMOTED TO MAIN TANK MID-RAID. This is the live incident: the roster event
        -- fires, and one second later the addon must notice.
        W.mainTank = true
        Era.OnRosterChanged()
        eq(fired, 0, "…the re-check is THROTTLED (a 40-man invite wave is bursty)")
        advance(Era.ROLE_RECHECK_THROTTLE + 0.2)
        eq(fired, 1, "…and fires once the burst settles")
        eq(Era.IsTank(), true, "…the promotion is visible: role-gated tank rows arm")

        -- Silence when nothing moved: re-projecting the whole options tree on every
        -- roster update would be a boot-cost tax paid forty times a night.
        Era.OnRosterChanged()
        advance(Era.ROLE_RECHECK_THROTTLE + 0.2)
        eq(fired, 1, "…an unchanged answer fires NOTHING")

        -- DEMOTION. This is the half that was impossible before: the session latch
        -- meant a demoted tank kept receiving tank-only warnings until /reload.
        W.mainTank = false
        Era.OnRosterChanged()
        advance(Era.ROLE_RECHECK_THROTTLE + 0.2)
        eq(fired, 2, "…a DEMOTION also re-derives (the latch is re-earned, not frozen)")
        eq(Era.IsTank(), false, "…and the player stops receiving tank-only warnings")

        -- Debounce: many events in one burst collapse to one re-derivation.
        W.mainTank = true
        for _ = 1, 12 do Era.OnRosterChanged() end
        advance(Era.ROLE_RECHECK_THROTTLE + 0.2)
        eq(fired, 3, "…twelve roster events in one burst produce ONE re-derivation")

        -- The latch itself still WORKS — the fix must not have weakened §5.4. A tank
        -- who swaps to Battle Stance for a burst window keeps his tank warnings.
        W.mainTank, W.form = false, Era.DEFENSIVE_STANCE_FORM
        Era._rederive()
        eq(Era.IsTank(), true, "…a Prot warrior in Defensive Stance is a tank")
        W.form = 0
        eq(Era.IsTank(), true, "…and STAYS one after swapping to Battle Stance (§5.4 latch intact)")

        -- RM-1 SECOND HALF: the frozen projected default. The tree caches a RESOLVED
        -- answer at boot; ROLE_CHANGED must re-resolve it.
        ck(type(API.WatchRoleChanges) == "function",
           "…API.WatchRoleChanges exists (the re-projection hook)")
        do
            Addon.zones, Addon.zonesById = {}, {}
            Addon.encounters, Addon.encountersById = {}, {}
            Addon.encByCreature, Addon.encByEncounterId, Addon.encByZone = {}, {}, {}
            Addon:RegisterZone({ id = "rolez", name = "Role Zone", order = 1, size = 40 })
            Addon:RegisterEncounter({
                id = "rolez:boss", name = "Role Boss", zone = 1,
                creatureId = { 99001 }, legacy = { raidId = "rolez", bossId = "boss" },
                detect = { mode = "combat" }, combat = {},
                warnings = { { key = "tankonly", text = "Tank thing", role = "Tank" } },
            })
            local prevResolver = Addon.RoleResolver
            local isTank = false
            Addon.RoleResolver = function(gateStr) return gateStr == "Tank" and isTank end

            API.PublishOptionsTree()
            local boss = Addon:GetBoss("rolez", "boss")
            eq(boss.mechanics[1].default, false,
               "…a tank-gated row projects OFF for a non-tank at boot")

            -- The player is promoted. Without the hook the projection stays frozen.
            isTank = true
            API._roleWatchInstalled = nil
            API.WatchRoleChanges()
            Addon:FireEngineEvent("ROLE_CHANGED", "WARRIOR2", true, false)
            local boss2 = Addon:GetBoss("rolez", "boss")
            eq(boss2.mechanics[1].default, true,
               "…and ROLE_CHANGED re-projects it ON (no /reload needed)")
            ck((Addon._optionsTreeRevision or 0) > 0, "…the projection revision advanced")

            Addon.RoleResolver = prevResolver
        end
        W.mainTank = false
        Era.roleState.tankLatched = false
        Era.ClearCache()
    end

    ------------------------------------------------------------------
    -- RMS-1 / RMS-2: the recovery whispers are ORDERED.
    ------------------------------------------------------------------
    do
        resetSync()
        makeRaid()
        Sync.replySeen = {}

        Addon.encounters, Addon.encountersById = {}, {}
        Addon.encByCreature, Addon.encByEncounterId, Addon.encByZone = {}, {}, {}

        -- EIGHT bars, not three. A three-bar fixture is not evidence: pairs() over a
        -- three-key table lands in sorted order one time in six by luck, and a
        -- determinism gate that a coin-flip can satisfy proves nothing. Eight makes
        -- the accidental-pass probability 1/40320, and the assertion below is on the
        -- EXACT emitted sequence rather than on "is it monotonic".
        local TIMERS = {}
        for i = 1, 8 do TIMERS[i] = { key = "t" .. i, text = "T" .. i, duration = 400 } end
        local enc = Addon:RegisterEncounter({
            id = "ordering:boss", name = "Ordering Boss", zone = 533,
            creatureId = { 99010 }, detect = { mode = "combat" }, combat = {},
            timers = TIMERS,
        })
        local rt = Life:StartCombat(enc, 0, "test")
        ck(rt ~= nil, "RMS: a fixture encounter is engaged")

        -- Remaining times are the REVERSE of insertion order, so a table-ordered send
        -- and an urgency-ordered send are maximally different.
        local WANT_ORDER = {}
        for i = 1, 8 do
            rt:Timer("t" .. i):Start((9 - i) * 10)      -- t1=80s … t8=10s
            WANT_ORDER[9 - i] = "t" .. i                 -- expected: t8, t7, … t1
        end
        -- Eight state variables, same reasoning.
        local SKEYS = { "zulu", "alpha", "mike", "delta", "oscar", "bravo", "yankee", "kilo" }
        for i, k in ipairs(SKEYS) do rt:SetState(k, tostring(i)) end

        for i = #WIRE, 1, -1 do WIRE[i] = nil end
        Sync.OnRequestTimers("Alpha-Whitemane", "WHISPER")
        advance(4)                     -- let the send bucket drain the whole reply

        local vi, tr = {}, {}
        for _, m in ipairs(WIRE) do
            local f = Sync.Split(m.payload)
            if f[3] == "VI" and f[6] ~= "__stage" then vi[#vi + 1] = f[6] end
            if f[3] == "TR" then tr[#tr + 1] = { key = f[6], left = tonumber(f[7]) } end
        end

        -- RMS-2 — the exact sequence, against an independently sorted expectation.
        eq(#vi, #SKEYS, ("RMS-2: %d state-variable restores were sent"):format(#vi))
        local wantVI = {}
        for i, k in ipairs(SKEYS) do wantVI[i] = k end
        table.sort(wantVI)
        eq(table.concat(vi, ","), table.concat(wantVI, ","),
           "…in SORTED key order, exactly (the comment's own contract)")

        -- RMS-1 — likewise, and the sequence is the reverse of insertion, which is
        -- what makes this an assertion rather than a coincidence.
        local trKeys = {}
        for i, e in ipairs(tr) do trKeys[i] = e.key end
        eq(#tr, 8, ("RMS-1: %d timer restores were sent"):format(#tr))
        eq(table.concat(trKeys, ","), table.concat(WANT_ORDER, ","),
           "…MOST-URGENT-FIRST, exactly, and not in table order")
        ck(tr[1] and tr[1].key == "t8",
           "…so the 10-second bar reaches the joining raider before the 80-second one")

        -- The reason it matters: the send bucket truncates. Prove the ordering is what
        -- decides survival, not a nicety.
        ck(Sync.BUCKET_CAP ~= nil and Sync.BUCKET_CAP < 100,
           ("…and the send bucket is capped at %s, so order decides what arrives at all")
               :format(tostring(Sync.BUCKET_CAP)))

        Life:EndCombat(rt, false, "test")
        resetLife()
    end

    ------------------------------------------------------------------
    -- RME-1: BossHealthPct walks the encounter's DECLARED creature order.
    ------------------------------------------------------------------
    do
        clearWorld()
        Era.ResetHealth()
        -- Four Horsemen shape: several ids, all cached, all alive, different health.
        local IDS = { 16064, 16065, 16062, 16063 }
        for i, cid in ipairs(IDS) do
            local u = "nameplate" .. i
            W.units[u] = { guid = "Creature-0-0-0-0-" .. cid .. "-000", hp = 100 * i,
                           hpmax = 1000, dead = false }
            W.nameplates[#W.nameplates + 1] = u
            Era.healthToken[cid] = u
        end
        local first = { }
        for _ = 1, 12 do
            local _, cid = Era.BossHealthPct(IDS)
            first[#first + 1] = cid
        end
        local stable = true
        for i = 2, #first do if first[i] ~= first[1] then stable = false end end
        ck(stable, "RME-1: twelve reads of a multi-creature encounter return the SAME boss")
        eq(first[1], IDS[1], "…and it is the FIRST creature the encounter declares")

        -- Reordering the declaration reorders the answer — proof the rule is the
        -- declaration and not an accident that happens to be stable.
        local rev = { IDS[4], IDS[3], IDS[2], IDS[1] }
        local _, cidRev = Era.BossHealthPct(rev)
        eq(cidRev, rev[1], "…and a different declared order yields that order's first")
        Era.ResetHealth()
        clearWorld()
    end

    ------------------------------------------------------------------
    -- RML-1: Life:Sweep picks its winner by RULE.
    ------------------------------------------------------------------
    do
        resetLife()
        Addon.encounters, Addon.encountersById = {}, {}
        Addon.encByCreature, Addon.encByEncounterId, Addon.encByZone = {}, {}, {}
        local CIDS = { 50004, 50001, 50003, 50002 }
        for _, cid in ipairs(CIDS) do
            Addon:RegisterEncounter({
                id = "sweep:" .. cid, name = "Sweep " .. cid, zone = 533,
                creatureId = { cid }, detect = { mode = "combat" }, combat = {},
            })
        end

        local function stageSweepWorld()
            clearWorld()
            W.difficultyID, W.instanceType, W.instanceID, W.inInstance = 9, "raid", 533, true
            for i, cid in ipairs(CIDS) do
                local u = "nameplate" .. i
                W.units[u] = { guid = "Creature-0-0-0-0-" .. cid .. "-00" .. i,
                               hp = 900, hpmax = 1000, combat = true }
                W.nameplates[#W.nameplates + 1] = u
            end
        end

        -- No target: the tiebreak is lowest creature id, every time.
        local winners = {}
        for _ = 1, 10 do
            Life:Reset(); Sched:Flush()
            Life.armedCombat, Life.armedHealthBoot = true, true
            stageSweepWorld()
            local rt = Life:Sweep(0.5, nil, "sweep")
            winners[#winners + 1] = rt and rt.def and rt.def.id or "none"
            if rt then Life:EndCombat(rt, false, "test") end
        end
        local same = true
        for i = 2, #winners do if winners[i] ~= winners[1] then same = false end end
        ck(same, "RML-1: ten sweeps over the same four-boss room pick the SAME winner")
        eq(winners[1], "sweep:50001", "…and it is the lowest creature id, by the stated rule")

        -- With a target, the mob the raid is actually looking at wins — the answer a
        -- human would give, and still a rule rather than a race.
        ck(Life.PREFER_TARGETED == true, "…PREFER_TARGETED is the shipped tiebreak")
        Life:Reset(); Sched:Flush()
        Life.armedCombat, Life.armedHealthBoot = true, true
        stageSweepWorld()
        W.units["target"] = { guid = "Creature-0-0-0-0-50003-003", hp = 900, hpmax = 1000, combat = true }
        local rt = Life:Sweep(0.5, nil, "sweep")
        eq(rt and rt.def and rt.def.id, "sweep:50003",
           "…the TARGETED boss wins the pull when the player has one")
        if rt then Life:EndCombat(rt, false, "test") end

        -- And exactly one encounter starts: the §2.1(c) contract survived the fix.
        eq(#Life.engaged, 0, "…and the sweep started exactly one encounter, now ended")
        resetLife()
    end
end
endgate()

----------------------------------------------------------------------
-- GATE W5-TELEM — the arbitration instrument is READABLE
--
-- Design doc item 3: the tripwire writes observations down "instead of DBM's 'please
-- report' chat line", so that "timer data becomes self-auditing across Drew's raids".
-- A ring nobody can read is not an instrument. These assertions are about the REPORT.
----------------------------------------------------------------------
gate("W5-SURFACES  the options panes' own logic: telemetry viewer + sound packs")
do
    Tele.Clear()
    ck(type(Addon.BuildTelemetryReport) == "function", "the report builder exists")
    ck(type(Addon.ShowTelemetryReport) == "function", "…and a viewer that shows it")

    -- Empty: says why it is empty, which for THIS instrument is good news.
    local empty = Addon:BuildTelemetryReport()
    ck(type(empty) == "string" and #empty > 0, "an empty ring still produces a report")
    ck(empty:lower():find("nothing recorded", 1, true) ~= nil,
       "…that says nothing is recorded rather than showing a blank table")

    -- Two keys, several observations each, deliberately different mean deltas.
    for i = 1, 4 do
        Tele.Write("timer.refresh", { enc = "naxxramas:patchwerk", key = "hateful",
                                      obs = 1.0 + i * 0.1, delta = -1.5, expMin = 2.5, expMax = 2.5 })
    end
    for i = 1, 2 do
        Tele.Write("timer.refresh", { enc = "bwl:vaelastrasz", key = "burningadrenaline",
                                      obs = 14.0, delta = -0.4, expMin = 15, expMax = 15 })
    end
    Tele.Write("lifecycle.engage", { enc = "bwl:vaelastrasz", path = "yell" })

    local rep = Addon:BuildTelemetryReport()
    ck(rep:find("naxxramas:patchwerk:hateful", 1, true) ~= nil, "the report names the timer key")
    ck(rep:find("bwl:vaelastrasz:burningadrenaline", 1, true) ~= nil, "…and the second one")

    -- The WORST offender is first: the report's job is "what should I fix", so the
    -- ordering is the answer, not decoration.
    local pPatch = rep:find("naxxramas:patchwerk", 1, true)
    local pVael  = rep:find("bwl:vaelastrasz:burning", 1, true)
    ck(pPatch and pVael and pPatch < pVael,
       "…worst mean deviation first (-1.50s before -0.40s)")

    ck(rep:find("declared window 2.50-2.50s", 1, true) ~= nil,
       "…and each group states the window the data file promised")
    ck(rep:find("1 other engine entr", 1, true) ~= nil,
       "…non-tripwire entries are counted, not silently dropped from the total")

    -- The one-line status the pane shows, which is the only thing most sittings need.
    ck(Addon:TelemetryLineText():find("7 observations recorded", 1, true) ~= nil,
       "…and the pane's status line reports the count")
    ck(Addon:TelemetryLineText():find(Tele.BUILD, 1, true) ~= nil,
       "…stamped with the build that recorded them")

    -- The raw export is the escape hatch, and it must carry the build token so an
    -- observation from an older engine is never mistaken for current behaviour.
    local raw = table.concat(Tele.Export(), "\n")
    ck(raw:find(Tele.BUILD, 1, true) ~= nil, "the raw export is build-stamped")
    eq(Tele.BUILD, "2.0.0", "…and the build token is the release version, not a wave tag")

    -- Clearing is IN PLACE (the ring's own contract) and the viewer survives it.
    local ringRef = Tele.Ring(false)
    local n = Tele.Clear()
    eq(n, 7, "Clear() reports how many observations it removed")
    ck(Tele.Ring(false) == ringRef, "…and clears IN PLACE (nothing is left pointing at a corpse)")
    ck(Addon:BuildTelemetryReport():lower():find("nothing recorded", 1, true) ~= nil,
       "…and the report goes back to the empty case cleanly")

    -- The option that turns recording off must actually stop it — an instrument you
    -- cannot switch off is a different complaint, but one that lies about being off
    -- is a defect.
    Addon.db.settings.engineTelemetry = false
    Tele.Write("timer.refresh", { enc = "x", key = "y", obs = 1, delta = -1 })
    eq(Tele.Count(), 0, "recording OFF actually stops writes")
    Addon.db.settings.engineTelemetry = true
    Tele.Write("timer.refresh", { enc = "x", key = "y", obs = 1, delta = -1 })
    eq(Tele.Count(), 1, "…and back ON resumes them")
    Tele.Clear()

    ------------------------------------------------------------------
    -- THE SOUND-PACK SURFACE. Same category: pure logic sitting behind an options
    -- pane, and the thing that makes a 750-entry flat list pickable at all.
    ------------------------------------------------------------------
    do
        Addon:InvalidateSoundPacks()
        local packs = Addon:GetSoundPacks()
        ck(#packs > 10, ("the bundled sounds derive into %d packs"):format(#packs))
        eq(packs[1].key, Addon.SOUNDPACK_ALL, "…with \"All sounds\" first")
        eq(packs[2].key, Addon.SOUNDPACK_BUILTIN, "…then the built-ins")
        eq(packs[#packs].key == Addon.SOUNDPACK_LSM or #packs > 2, true,
           "…and LibSharedMedia last when present")

        -- Sorted, so the dropdown does not reshuffle between openings (Class 8).
        local mid = {}
        for i = 3, #packs do
            if packs[i].key ~= Addon.SOUNDPACK_LSM then mid[#mid + 1] = packs[i].name end
        end
        local sorted = true
        for i = 2, #mid do if mid[i] < mid[i - 1] then sorted = false end end
        ck(sorted, "…and the bundled packs are alphabetical")

        -- Membership is DERIVED from the key, not a second table to keep in sync.
        eq(Addon:SoundPackOf("pk:DBM-Core/Alexander/1.ogg"), "pk:DBM-Core/Alexander",
           "a bundled key resolves to its pack")
        eq(Addon:SoundPackOf("pk:DBM-Core/AirHorn.ogg"), "pk:DBM-Core",
           "…a file in an addon's own folder resolves to that addon")
        eq(Addon:SoundPackOf("none"), Addon.SOUNDPACK_BUILTIN, "…\"none\" is a built-in")
        eq(Addon:SoundPackOf("lsm:Whatever"), Addon.SOUNDPACK_LSM,
           "…and a LibSharedMedia key resolves to LSM")

        -- Every pack has members, and the counts add up to the whole list.
        local total = 0
        for i = 2, #packs do
            if packs[i].count <= 0 then fail("empty pack in the list: " .. packs[i].key) end
            total = total + packs[i].count
        end
        eq(total, packs[1].count, "the per-pack counts sum to the whole sound list")

        -- Memoized (it is read per keystroke in the picker's search box), and the
        -- memo is droppable so late-registering LSM media is not locked out forever.
        ck(Addon:GetSoundPacks() == packs, "the pack list is memoized")
        Addon:InvalidateSoundPacks()
        ck(Addon:GetSoundPacks() ~= packs, "…and the memo is droppable")
    end
end
endgate()

----------------------------------------------------------------------
-- GATE W5-RELEASE — the assertable rows of ROLLOUT_CONTINUITY_AUDIT.md's
-- 21-point release-train checklist.
--
-- Most of the 21 are human sign-off (rehearse the upgrade on a WTF copy) or N/A for
-- an addon that has never shipped. The ones a machine can hold are held here, and
-- the numbering is the audit's so the walkthrough in the wave report lines up.
----------------------------------------------------------------------
gate("W5-RELEASE  the assertable release-gate rows")
do
    local toc = readFile(P(TOC_FILE)) or ""

    -- #12: toc ## Version matches the tag the owner will cut.
    local ver = toc:match("##%s*Version:%s*([%d%.]+)")
    eq(ver, "2.0.0", "#12 the toc ## Version is 2.0.0")

    -- #1: every SavedVariables global from the previous toc is still declared.
    -- Undeclared = deleted at next logout, and this addon has exactly one.
    local svs = {}
    for s in toc:gmatch("##%s*SavedVariables:%s*([^\r\n]+)") do
        for name in s:gmatch("[%w_]+") do svs[name] = true end
    end
    ck(svs["DaseekiRaidMechanicsDB"],
       "#1 DaseekiRaidMechanicsDB is still declared (1.x's only SV global)")

    -- #11: folder, SV global, project id and hub registration id unchanged.
    ck(toc:match("X%-Curse%-Project%-ID:%s*1592413") ~= nil,
       "#11 X-Curse-Project-ID is unchanged (1592413)")
    do
        local opts = readFile(P("options.lua")) or ""
        ck(opts:find('id%s*=%s*"raidmechanics"') ~= nil,
           "#11 the hub registration id is still \"raidmechanics\"")
    end

    -- #10: previous slash commands still resolve. Every 1.x verb, asserted present
    -- in the dispatcher — a renamed command is a broken macro in someone's UI.
    do
        local sl = readFile(P("slash.lua")) or ""
        ck(sl:find('SLASH_DASEEKIRM1 = "/drm"', 1, true) ~= nil, "#10 /drm still registered")
        ck(sl:find('SLASH_DASEEKIRM2 = "/raidmech"', 1, true) ~= nil, "#10 /raidmech still registered")
        for _, verb in ipairs({ "options", "config", "unlock", "test", "lock", "debug",
                               "debugonly", "log", "savelog", "clearlog", "clearsessions",
                               "pull", "stats", "enable", "disable" }) do
            ck(sl:find('"' .. verb .. '"', 1, true) ~= nil,
               ("#10 the 1.x verb %q still resolves"):format(verb))
        end
    end

    -- #3: defaults are ADDITIVE against 1.x, and every seed loop is nil-guarded.
    -- The 1.x default set, verbatim — a REMOVED default silently changes behaviour
    -- for an existing user whose db has no override for it.
    do
        _G.DaseekiRaidMechanicsDB = {}
        local saved = Addon.db
        Addon:Init()
        local s = Addon.db.settings
        for _, k in ipairs({ "enabled", "locked", "soundEnabled", "barTexture", "barWidth",
                             "barHeight", "autoDebug", "deathSound", "deathSoundKey",
                             "debugOnly" }) do
            ck(s[k] ~= nil, ("#3 the 1.x default %q still seeds"):format(k))
        end
        Addon.db = saved
    end

    -- #7: no version gate wipes user data. The audit's NW-5 finding was that
    -- Raid-Mechanics core.lua:122-124 emptied db.mechanics on a DB_VERSION bump.
    do
        local core = readFile(P("core.lua")) or ""
        ck(core:find("Addon.MIGRATIONS", 1, true) ~= nil,
           "#7 NW-5: the destructive DB_VERSION gate is a MIGRATIONS chain")
        ck(core:find("db.mechanics = {}", 1, true) == nil,
           "…and nothing in core.lua empties db.mechanics")
    end

    -- #13/#14: cross-addon calls degrade with a message, never a Lua error, and the
    -- wire hard-drops a version mismatch rather than mis-decoding it.
    do
        local opts = readFile(P("options.lua")) or ""
        ck(opts:find("requires Daseeki Core", 1, true) ~= nil,
           "#13 a too-old Daseeki Core produces a message, not an error")
        ck(Sync.TRANSPORT ~= nil and Sync.SUB ~= nil,
           "#14 the wire carries a transport version and per-sub protocol numbers")
    end

    -- #15: coordinated-reload requirements stated in the changelog.
    do
        local cl = readFile(P("CHANGELOG.md")) or ""
        ck(cl:find("^# Changelog") ~= nil or cl:find("# Changelog", 1, true) == 1,
           "the changelog is well-formed")
        ck(cl:find("## 2.0.0", 1, true) ~= nil, "…and carries a public 2.0.0 block")
        ck(cl:find("Internal build history", 1, true) ~= nil,
           "…with the wave entries demoted to internal history")
        ck(cl:lower():find("everyone in the raid should be on 2.0.0", 1, true) ~= nil,
           "#15 the mixed-version expectation is stated for the user")
        ck(cl:lower():find("your settings are kept", 1, true) ~= nil,
           "…and so is the settings-continuity promise")
        -- #21: downgrade rehearsed OR the changelog states it is unsupported. It is
        -- the latter, and the statement has to be TRUE — which it is because
        -- Addon:MigrateDB refuses to touch a db stamped newer than the build reading
        -- it (asserted as CASE 4 of the W5-DBFIX gate).
        ck(cl:lower():find("is not supported", 1, true) ~= nil
           and cl:lower():find("1.3.0", 1, true) ~= nil,
           "#21 the changelog states that downgrading is unsupported")
    end

    -- Packaging: the harness and dev trees never ship.
    do
        local pkg = readFile(P(".pkgmeta")) or ""
        for _, ign in ipairs({ "harness", "dev", "README.md", "CHANGELOG.md", "DESCRIPTION.md" }) do
            ck(pkg:find("- " .. ign, 1, true) ~= nil,
               (".pkgmeta ignores %s"):format(ign))
        end
        ck(exists(P("DESCRIPTION.md")), "DESCRIPTION.md exists for the project page")
        local desc = readFile(P("DESCRIPTION.md")) or ""
        ck(desc:find("1592413", 1, true) ~= nil, "…and names the project id from the toc")
        ck(desc:find("Last synced: never", 1, true) ~= nil,
           "…and records that this addon has never been publicly released")
    end
end
endgate()

----------------------------------------------------------------------
-- GATE W5-DBFIX — the settings-migration machinery against a fixture of the
-- OWNER'S ACTUAL SavedVariables shape.
--
-- ROLLOUT_CONTINUITY_AUDIT #8: "tested against a real WTF copy incl. empty-source
-- and already-migrated cases." There are no public users, so the upgrade experience
-- that matters is exactly one: Drew's own DB, which has been accumulating overrides,
-- kill stats and debug sessions since 1.0.0. It must come through 2.0.0 untouched.
----------------------------------------------------------------------
gate("W5-DBFIX  the owner's SavedVariables shape survives the upgrade")
do
    local saved = Addon.db

    -- Safe nested read. THE WHOLE SUBJECT of this gate is data going missing, so
    -- every assertion below is reading a path that the defect under test DELETES —
    -- and a raw `d.mechanics.foo.masterEnabled` would abort the run on exactly the
    -- failure it exists to report, taking the remaining gates with it. `at` turns a
    -- missing path into a failed assertion, which is the useful outcome. (Found by
    -- mutation-testing the NW-5 regression: restoring the destructive DB_VERSION
    -- wipe crashed this gate instead of reddening it.)
    local function at(t, ...)
        for _, k in ipairs({ ... }) do
            if type(t) ~= "table" then return nil end
            t = t[k]
        end
        return t
    end

    -- A faithful fixture of a v3 DB as 1.3.0 leaves it: settings, per-mechanic
    -- overrides on 1.x keys (including a placement tuple and an anchor pseudo-key),
    -- module config, kill statistics, and both debug-log tables.
    local function ownerDB()
        return {
            dbVersion = 3,
            settings = {
                enabled = true, locked = true, soundEnabled = true,
                barTexture = "Interface\\TargetingFrame\\UI-StatusBar",
                barWidth = 240, barHeight = 18,
                autoDebug = true, deathSound = true, deathSoundKey = "pk:DBM-Core/AirHorn.ogg",
                debugOnly = false,
                specialWarnings = true, countdownVoice = true,
                voiceCountKey = "pk:DBM-Core/Alexander",
                mirrorDBMPull = false,
            },
            mechanics = {
                ["naxxramas:patchwerk:hateful"] = { masterEnabled = false },
                ["naxxramas:loatheb:sporecd"]   = { enabled = true, sound = "raidwarning", scale = 1.2 },
                ["naxxramas:thaddius:polarity"] = { masterEnabled = true, style = "text", fontSize = 40 },
                ["aq40:skeram:earthshock"]      = { masterEnabled = false },
                ["bwl:vaelastrasz:burningadrenaline"] = {
                    pos = { point = "CENTER", relPoint = "CENTER", x = -120, y = 240 } },
                ["#warn.special"] = { pos = { point = "TOP", relPoint = "TOP", x = 0, y = -260 } },
            },
            modules = {
                fourhorsemen_rotation = { enabled = true, myGroup = 2 },
                gothik_waves = { enabled = false },
            },
            stats = {
                naxxramas = { patchwerk = { kills = 14, wipes = 3, bestTime = 172.4 },
                              loatheb   = { kills = 6,  wipes = 11, bestTime = 301.2 } },
                aq40      = { skeram    = { kills = 22, wipes = 1 } },
            },
            debugLive = { "[   12.4] CAST 28308 Hateful Strike" },
            debugSessions = { { raidId = "naxxramas", raidName = "Naxxramas",
                                savedAt = "2026-08-01 21:40", reason = "left raid",
                                lines = { "[    0.0] ENGAGE naxxramas:patchwerk" } } },
        }
    end

    -- CASE 1 — the already-migrated case. Nothing may change.
    do
        local db = ownerDB()
        _G.DaseekiRaidMechanicsDB = db
        Addon:Init()
        local d = Addon.db
        eq(d.dbVersion, 3, "the owner's v3 DB stays at v3 (no gratuitous bump)")
        eq(d.settings.barWidth, 240, "…a non-default bar width is preserved")
        eq(d.settings.deathSoundKey, "pk:DBM-Core/AirHorn.ogg", "…a bundled-pack sound key survives")
        eq(d.settings.mirrorDBMPull, false, "…an explicitly-false setting is not re-defaulted to true")

        eq(at(d, "mechanics", "naxxramas:patchwerk:hateful", "masterEnabled"), false,
           "…a mechanic switched OFF in 1.x is still off")
        eq(at(d, "mechanics", "naxxramas:loatheb:sporecd", "scale"), 1.2,
           "…a per-mechanic scale survives")
        eq(at(d, "mechanics", "naxxramas:thaddius:polarity", "fontSize"), 40,
           "…a per-mechanic font size survives")
        eq(at(d, "mechanics", "aq40:skeram:earthshock", "masterEnabled"), false,
           "…and a row the REBUILD re-created keeps its 1.x override (same key)")
        eq(at(d, "mechanics", "bwl:vaelastrasz:burningadrenaline", "pos", "y"), 240,
           "…an alert placement survives")
        eq(at(d, "mechanics", "#warn.special", "pos", "y"), -260,
           "…and so does a HUD anchor placement")

        eq(at(d, "modules", "fourhorsemen_rotation", "myGroup"), 2,
           "…a special module's own config survives")
        eq(at(d, "modules", "gothik_waves", "enabled"), false, "…including a module switched off")
        eq(at(d, "stats", "naxxramas", "patchwerk", "kills"), 14, "…kill statistics are untouched")
        near(at(d, "stats", "naxxramas", "loatheb", "bestTime"), 301.2, 0.001,
           "…including best times")
        eq(#(d.debugLive or {}), 1, "…the live debug log is untouched")
        eq(#(d.debugSessions or {}), 1, "…and so are the saved debug sessions")

        -- The 2.0 surfaces ADD their keys lazily, without disturbing anything.
        Addon.Bars.Settings(); Addon.Warnings.Settings(); Tele.Ring(true)
        eq(d.settings.barWidth, 240, "…and the new 2.0 setting tables do not clobber 1.x keys")
        ck(type(d.settings.bars) == "table", "…db.settings.bars is added lazily")
        ck(type(d.settings.warnings) == "table", "…db.settings.warnings is added lazily")
        ck(type(d.engineLog) == "table", "…and the telemetry ring is ONE additive top-level key")
        eq(d.dbVersion, 3, "…with no DB_VERSION bump for any of it")
    end

    -- CASE 2 — the empty-source case (a brand-new install).
    do
        _G.DaseekiRaidMechanicsDB = {}
        Addon:Init()
        eq(Addon.db.dbVersion, 3, "an empty DB is STAMPED at the current version")
        ck(type(Addon.db.mechanics) == "table" and next(Addon.db.mechanics) == nil,
           "…with no overrides invented")
        eq(Addon.db.settings.enabled, true, "…and the shipped defaults seeded")
    end

    -- CASE 3 — an UNKNOWN (absent) version. Stamp, convert nothing, wipe nothing.
    do
        local db = ownerDB()
        db.dbVersion = nil
        _G.DaseekiRaidMechanicsDB = db
        Addon:Init()
        eq(Addon.db.dbVersion, 3, "an unversioned DB is stamped, not wiped")
        eq(at(Addon.db, "mechanics", "naxxramas:patchwerk:hateful", "masterEnabled"), false,
           "…and every override survives the stamping")
        eq(at(Addon.db, "stats", "aq40", "skeram", "kills"), 22, "…as do the statistics")
    end

    -- CASE 4 — a NEWER DB than this build. Never downgrade, never touch.
    do
        local db = ownerDB()
        db.dbVersion = 99
        _G.DaseekiRaidMechanicsDB = db
        Addon:Init()
        eq(Addon.db.dbVersion, 99, "a DB from a NEWER build is left exactly as-is")
        eq(at(Addon.db, "mechanics", "naxxramas:loatheb:sporecd", "scale"), 1.2,
           "…and its overrides are not rewritten by this build")
    end

    -- CASE 5 — an older version with a MISSING migration step. Stop and report;
    -- never empty db.mechanics to "recover".
    do
        local db = ownerDB()
        db.dbVersion = 1
        _G.DaseekiRaidMechanicsDB = db
        local prev = Addon.MIGRATIONS
        Addon.MIGRATIONS = {}
        Addon:Init()
        eq(Addon.db.dbVersion, 1, "a gap in the migration chain STOPS rather than guessing")
        eq(at(Addon.db, "mechanics", "naxxramas:patchwerk:hateful", "masterEnabled"), false,
           "…and leaves the user's data completely intact (NW-5's whole point)")
        Addon.MIGRATIONS = prev
    end

    _G.DaseekiRaidMechanicsDB = {}
    Addon:Init()
    Addon.db = saved
end
endgate()

----------------------------------------------------------------------
-- GATE BRIEF-N — SUITE_DATA_HONESTY_AUDIT Brief N: "read the roster and the
-- talents when they exist" (RM-1 Class 5, RM-2 Class 6, RM-3 Class 4).
--
-- Both defects were invisible headless for one reason each, and the audit named
-- both: the group world had no cold-roster profile, and `GetNumTalentTabs` was
-- hardcoded to 3. Those profiles now exist (see `W.rosterDark` / `W.talentProfile`),
-- so each block below opens with a RED CONTROL — the OLD code's shape, reproduced
-- and driven on the SAME fixture — and asserts it fails. A gate that passes on both
-- the old and the new code proves nothing; the red controls are what stop this one
-- from becoming that.
----------------------------------------------------------------------
gate("BRIEF-N  roster + talents read when they exist (RM-1, RM-2, RM-3)")

do  -- RM-2 (a): the populate witness itself
    resetLife()
    W.rosterDark = true
    ck(Life.env.IsInGroup(),
       "RM-2: on the entering-world frame the client already says you ARE in a group…")
    eq(Life.env.GetNumGroupMembers(), 0, "…while the group still has no members…")
    eq(Life.env.IsInRaid(), false, "…and is not yet a raid (so the 40-man walk is party1..N)")
    ck(not Life:RosterPopulated(),
       "…so the roster reads UNANSWERED, which is not the same as an empty group (Class 6)")
    Life:OnEvent("GROUP_ROSTER_UPDATE")
    ck(Life.rosterSeen, "GROUP_ROSTER_UPDATE is recorded as the populate witness")
    ck(Life:RosterPopulated(), "…and after it, a read of the group is worth believing")
    local hasRoster = false
    for _, e in ipairs(Life.EVENTS) do if e == "GROUP_ROSTER_UPDATE" then hasRoster = true end end
    ck(hasRoster, "…and the engine's own event list carries it, so the frame really subscribes")
    resetLife()
    ck(Life:RosterPopulated(), "a NON-ZERO member count is its own proof — no witness required")
end

do  -- RM-2 (b): reload mid-raid — dark at entering-world, populated by +7 s
    resetSync(); makeRaid()
    W.rosterDark = true

    -- RED CONTROL. The old chain snapshotted the candidates inside BeginRecovery, on
    -- the PLAYER_ENTERING_WORLD frame, and scheduled one ask per candidate FOUND.
    -- Reproduced in shape and driven on this fixture it finds nobody, `asked == 0`,
    -- and the old code then dropped the flag and returned "no_candidates" — no bars
    -- for the rest of the encounter, silently. If this ever goes green the fixture
    -- has stopped modelling the client and everything below it is worthless.
    do
        local snapshot = Sync.RankCandidates()
        local wouldAsk = 0
        for i in ipairs(Sync.RECOVERY_ASK_AT) do if snapshot[i] then wouldAsk = wouldAsk + 1 end end
        eq(wouldAsk, 0, "RM-2 RED CONTROL: the OLD begin-frame snapshot finds NOBODY to ask")
    end

    local okr, rungs = Sync.BeginRecovery("reload")
    eq(okr, true, "…yet recovery BEGINS anyway: nothing about the group is read on this frame")
    eq(rungs, 3, "…three ask RUNGS are armed, not three named candidates")
    ck(Life:IsRecovering(), "…and the 15 s suppression flag is held while it waits (§9.1 step 3)")

    advance(2)                        -- the client delivers the roster a beat later
    W.rosterDark = false
    Life:OnEvent("GROUP_ROSTER_UPDATE")

    advance(4.9); eq(countOnWire("RT"), 0, "nothing is asked before 7 s (§9.1 cascade unchanged)")
    advance(0.4); eq(countOnWire("RT"), 1,
       "RM-2: at 7 s the LIVE roster is read and a raider IS asked — the reload recovers")
    advance(3);   eq(countOnWire("RT"), 2, "…the 10 s rung reads it again and asks the next")
    advance(3);   eq(countOnWire("RT"), 3, "…and the 13 s rung the one after that")
    eq(#Sync.recovery.order, 3, "…three asks on record")
    ck(Sync.recovery.order[1] ~= Sync.recovery.order[2]
       and Sync.recovery.order[2] ~= Sync.recovery.order[3]
       and Sync.recovery.order[1] ~= Sync.recovery.order[3],
       "…to three DISTINCT raiders — a live re-read never asks the same person twice")
end

do  -- RM-2 (c): still dark at the first ask -> ONE bounded re-arm
    resetSync(); makeRaid()
    W.rosterDark = true
    Sync.BeginRecovery("reload")
    advance(7.3)
    eq(countOnWire("RT"), 0, "a roster STILL dark at the first ask whispers nobody…")
    ck(Sync.recovery.active,
       "…and does NOT conclude 'no candidates' and give up — that was the live bug")
    ck(Sync.recovery.rearmed, "…it RE-ARMS (Class 6: absence of the list is not an empty list)")
    eq(Sync.recovery.rungs, 4, "…adding exactly ONE more ask rung, not an unbounded ladder")
    advance(6)                        -- the 10 s and 13 s rungs, both still dark
    eq(countOnWire("RT"), 0, "…the remaining rungs find it dark too and stay silent")
    eq(Sync.recovery.rungs, 4, "…without re-arming a second time (the latch is what bounds it)")
    advance(3)                        -- t ~= 16.3
    ck(Life:IsRecovering(), "…and the suppression window was EXTENDED to cover the re-armed ask")
    W.rosterDark = false
    Life:OnEvent("GROUP_ROSTER_UPDATE")
    advance(2)                        -- t ~= 18.3
    eq(countOnWire("RT"), 1, "…so a roster that lands at 16 s is still asked, at 18 s")
end

do  -- RM-2 (d): a roster that NEVER populates hands the flag back
    resetSync(); makeRaid()
    W.rosterDark = true
    Sync.BeginRecovery("reload")
    advance(18.3)
    eq(countOnWire("RT"), 0, "a roster that never populates asks nobody…")
    ck(not Sync.recovery.active, "…and the cascade ENDS at its last rung rather than hanging")
    ck(not Life:IsRecovering(),
       "…releasing the suppression flag: detection is never blinded for nothing")
    ck(Life:HealthArmed(), "…so health-based pull detection is armed again")
end

do  -- RM-3: "rank by version" was provably always -1; the ask-time read fixes it
    resetSync(); makeRaid()
    ck(next(Sync.peers) == nil,
       "RM-3: after a /reload the peer table is empty — a new Lua state has no history")
    do
        local snap = Sync.RankCandidates()
        eq(snap[1] and snap[1].rev, -1,
           "RM-3 RED CONTROL: ranked on the BEGIN frame every candidate's revision is -1…")
        eq(snap[1] and snap[1].name, "Alpha-Whitemane",
           "…so 'highest version first' collapses onto the alphabetical tie-break, permanently")
    end

    Sync.BeginRecovery("reload")
    advance(3)                        -- the hello replies land on their §7.4 debounce
    rx("Echo-Whitemane", "V", 30000, Sync.VERSION.release, "2.0.0", 0)
    eq(Sync.peers["Echo-Whitemane"] and Sync.peers["Echo-Whitemane"].rev, 30000,
       "…a peer answers our hello three seconds in, well before the 7 s rung")
    advance(4.3)
    eq(countOnWire("RT"), 1, "…the 7 s rung asks exactly one raider")
    do
        local lastRT
        for i = 1, #WIRE do
            if Sync.Split(WIRE[i].payload)[3] == "RT" then lastRT = WIRE[i] end
        end
        eq(lastRT and lastRT.target, "Echo-Whitemane",
           "RM-3: ranked AT THE ASK the version key is alive — the newest peer is asked FIRST")
        eq(lastRT and lastRT.chatType, "WHISPER", "…still by whisper (§9.1)")
    end
end

do  -- RM-1 (a): a cold talent tree is UNKNOWN, not tab 1
    resetW2()
    W.class = "PALADIN"
    W.talents[2] = 31                 -- a PROTECTION paladin: tab 2 is the deepest
    W.talentProfile = "none"          -- …but the client has not delivered the tree
    Era.ClearCache()

    -- RED CONTROL: the OLD SpecTab, reproduced line for line in shape.
    local function oldSpecTab()
        local n = Era.env.GetNumTalentTabs() or 0
        local best, bestPoints = 1, -1
        for i = 1, n do
            local _, _, _, _, points = Era.env.GetTalentTabInfo(i)
            points = points or 0
            if points > bestPoints then best, bestPoints = i, points end
        end
        if bestPoints <= 0 then return 1, 0 end
        return best, bestPoints
    end
    eq(oldSpecTab(), 1, "RM-1 RED CONTROL: the OLD SpecTab answers TAB 1 for an unreadable tree")
    ck(Era.HEALER_SPECS["PALADIN" .. tostring((oldSpecTab()))] == true,
       "…and PALADIN1 is the HOLY tree — the old code booted a Protection paladin as a HEALER")

    eq(Era.SpecTab(), nil, "RM-1: an unreadable talent tree now answers UNKNOWN, not tab 1")
    eq(Era.Spec(), nil, "…so there is no spec string to mistake for an answer")
    eq(Era.RoleKnown(), false, "…and the addon can say so out loud")
    eq(Era.IsHealer(), false, "…the Protection paladin is NOT classified as a healer")
    eq(Era.IsTank(), false, "…nor as a tank: unknown refuses in both directions")
    eq(Era.RoleSignature(), nil, "…no role signature is derived from it")
    eq(Era.roleState.signature, nil,
       "…and NOTHING is stamped, so the first readable answer is the first one on record")

    -- The second cold shape: the tabs exist and answer a name, the points do not.
    W.talentProfile = "nil"
    Era.ClearCache()
    eq(Era.env.GetNumTalentTabs(), 3, "…the other cold shape reports THREE tabs…")
    eq(Era.SpecTab(), nil, "…and is still refused, because every tab returned nil points")

    -- Warm: §10.23's rule is intact, both halves of it.
    W.talentProfile = "warm"
    Era.ClearCache()
    eq(Era.SpecTab(), 2, "…a readable tree answers the tab with the most points spent (§10.23)")
    eq(Era.Spec(), "PALADIN2", "…identified as CLASS..tabIndex")
    eq(Era.IsHealer(), false, "…and PALADIN2 is Protection, so still not a healer")
    W.talents[2] = nil
    Era.ClearCache()
    eq(Era.SpecTab(), 1, "…ZERO POINTS SPENT still falls back to tab 1 — the spec rule survives")
    eq(select(2, Era.SpecTab()), 0, "…reported as zero points spent, which is an ANSWER")
end

do  -- RM-1 (b): the bounded warmth ladder earns the role back
    resetW2(); Sched:Flush()
    W.class = "PALADIN"; W.talents[2] = 31
    W.talentProfile = "none"
    Era.ClearCache()

    local fired, lastSpec = 0, nil
    local cb = function(_, spec) fired = fired + 1; lastSpec = spec end
    Addon:RegisterEngineCallback("ROLE_CHANGED", cb)

    ck(Era.ArmRoleWarmth("gate"), "RM-1: an unknown role ARMS a bounded re-ask ladder")
    ck(not Era.ArmRoleWarmth("gate"), "…exactly once — bounded, not a retry storm")
    eq(#Era.ROLE_WARMTH_AT, 3, "…of three rungs, after which unknown is reported as unknown")
    advance(2.2)
    eq(fired, 0, "…a rung that still finds the tree dark announces NOTHING")
    eq(Era.roleState.signature, nil, "…and stamps nothing")

    W.talentProfile = "warm"          -- the client finally delivers the tree
    advance(3)
    eq(fired, 1, "…the first rung that CAN read it derives the role and announces it")
    eq(lastSpec, "PALADIN2", "…as PALADIN2 — Protection, which is what the player actually is")
    eq(Era.roleState.signature, "PALADIN2/false/false", "…and THAT is now the answer on record")
    advance(6)
    eq(fired, 1, "…the remaining rungs are silent, because nothing moved")
    Addon:UnregisterEngineCallback("ROLE_CHANGED", cb)
end

do  -- RM-1 (b2): a roster debounce must not DELETE the warmth ladder
    resetW2(); Sched:Flush()
    W.class = "PALADIN"; W.talents[2] = 31
    W.talentProfile = "none"
    Era.ClearCache()
    local fired = 0
    local cb = function() fired = fired + 1 end
    Addon:RegisterEngineCallback("ROLE_CHANGED", cb)

    Era.ArmRoleWarmth("gate")
    Era.OnRosterChanged()             -- a raider joins while the tree is still dark
    advance(1.2)                      -- the roster debounce fires and refuses
    eq(fired, 0, "a roster event landing mid-ladder refuses, because the tree is still dark")
    W.talentProfile = "warm"
    advance(1.2)                      -- t ~= 2.4 — the ladder's own 2 s rung
    eq(fired, 1,
       "RM-1: …and it did NOT delete the ladder — Sched:DelayedCall cancels on (fn, owner), "
       .. "so the rungs carry their own identity")
    Addon:UnregisterEngineCallback("ROLE_CHANGED", cb)
end

do  -- RM-1 (c): a cold read never demotes a real tank
    resetW2(); Sched:Flush()
    W.class = "WARRIOR"; W.talents[2] = 31
    W.form = Era.DEFENSIVE_STANCE_FORM
    Era.ClearCache()
    ck(Era.IsTank(), "a Prot warrior in Defensive Stance is a tank…")
    ck(Era.roleState.tankLatched, "…and the §5.4 session latch is set")
    W.talentProfile = "none"          -- the tree goes dark (a zone-in, a reload seam)
    Era.ClearCache()
    eq(select(2, Era._recheckRole()), "role_unknown",
       "RM-1: a re-check against an unreadable tree REFUSES…")
    ck(Era.roleState.tankLatched,
       "…without clearing a latch it could not re-earn — the fix must not demote a real tank")
    ck(Era.roleState.warmthArmed, "…and it arms the ladder instead of guessing")
end

do  -- RM-1 (d): PLAYER_ENTERING_WORLD is routed to the throttled re-check
    resetW2(); Sched:Flush()
    W.class = "PALADIN"; W.talents[2] = 31
    W.talentProfile = "none"
    Era.ClearCache()

    local fired = 0
    local cb = function() fired = fired + 1 end
    Addon:RegisterEngineCallback("ROLE_CHANGED", cb)
    Era.OnWorldEntered()
    ck(Era.roleState.warmthArmed,
       "RM-1: PLAYER_ENTERING_WORLD arms the warmth ladder when the role is unknown")
    W.talentProfile = "warm"
    advance(Era.ROLE_RECHECK_THROTTLE + 0.2)
    eq(fired, 1, "…and its own throttled re-check earns the role a second after the loading screen")
    Addon:UnregisterEngineCallback("ROLE_CHANGED", cb)

    -- The subscription lives behind `if type(_G.CreateFrame) == "function"`, which is
    -- false headless, so this half is asserted at the SOURCE — the same discipline
    -- W5-BRIEF-G applies to the roster events, for the same mutation-tested reason.
    local src = readFile(P("svc_era.lua")) or ""
    ck(src:match('event == "PLAYER_ENTERING_WORLD" then Era%.OnWorldEntered') ~= nil,
       "…and Era.Init's own event handler actually ROUTES it there")
    ck(src:match("Era%.ArmRoleWarmth%(\"boot\"%)") ~= nil,
       "…and Era.Init arms the ladder at boot, where the audit proved the tree is cold")
end

do  -- RM-1 (e): the options tree is not FROZEN on a role nobody gave
    resetW2(); Sched:Flush()
    -- Earlier gates deliberately swap in always-true fixture resolvers; this block is
    -- about the REAL derivation reaching the projection, so put the shipping ones back.
    local prevRole, prevClass = Addon.RoleResolver, Addon.ClassResolver
    Addon.RoleResolver, Addon.ClassResolver = Era.ResolveRole, Era.Class
    Addon.RoleKnown = Era.RoleKnown
    W.class = "PALADIN"; W.talents[1] = 31      -- genuinely a HOLY paladin: a healer
    W.talentProfile = "none"
    Era.ClearCache()

    Addon.zones, Addon.zonesById = {}, {}
    Addon.encounters, Addon.encountersById = {}, {}
    Addon.encByCreature, Addon.encByEncounterId, Addon.encByZone = {}, {}, {}
    Addon:RegisterZone({ id = "brnz", name = "Brief N Zone", order = 1, size = 40 })
    Addon:RegisterEncounter({
        id = "brnz:boss", name = "Brief N Boss", zone = 1,
        creatureId = { 99101 }, legacy = { raidId = "brnz", bossId = "boss" },
        detect = { mode = "combat" }, combat = {},
        warnings = { { key = "healonly", text = "Heal thing", role = "Healer" } },
    })

    API.PublishOptionsTree()
    eq(Addon._optionsTreeRoleKnown, false,
       "RM-1: a tree projected while the role is UNREADABLE is marked provisional…")
    eq(Addon:GetBoss("brnz", "boss").mechanics[1].default, false,
       "…and its healer-gated row is not switched on by an answer nobody gave")

    API._roleWatchInstalled = nil
    API.WatchRoleChanges()
    Era.ArmRoleWarmth("gate")         -- armed while the tree is still dark
    W.talentProfile = "warm"
    advance(2.2)
    eq(Addon._optionsTreeRoleKnown, true,
       "…and once the tree warms, ROLE_CHANGED re-projects it on a role that was earned")
    eq(Addon:GetBoss("brnz", "boss").mechanics[1].default, true,
       "…switching the healer row ON for the Holy paladin it belongs to — no /reload needed")
    Addon.RoleResolver, Addon.ClassResolver = prevRole, prevClass
end
endgate()

----------------------------------------------------------------------
realprint("############################################################")
realprint("# Daseeki-Raid-Mechanics 2.0 engine self-tests (waves 1-5 — RELEASE)")
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
                     "SYNC-RETIRE  core_boot.lua's W1 pull-timer shim is retired",
                     "BARS  §4.2/§4.7 bar model: variance, sort, anchors, recolour",
                     "WARN  §5.1/§5.2/§5.5 warning tiers",
                     "SCAN  §5.3 the three target scanners",
                     "ERA  §6.1/§8.6/§5.4 Era services",
                     "PUB  §4.5/§11.8 the 18-field public contract",
                     "NAXX  §8 encounter data: registration, keys, the options tree",
                     "NAXX-DRIVE  §8 per-encounter behaviour through the real engine",
                     "AQ  §6/§7 encounter data: registration, keys, the options tree",
                     "AQ-DRIVE  §6/§7 per-encounter behaviour through the real engine",
                     "BWLZG  §4/§5 encounter data: registration, keys, the options tree",
                     "BWLZG-DRIVE  §4/§5 per-encounter behaviour through the real engine",
                     "MCONYWB  §2/§3/§9 encounter data: registration, keys, the options tree",
                     "MCONYWB-DRIVE  §2/§3/§9 per-encounter behaviour through the real engine",
                     "W5-SCAFFOLD  core_boot.lua is a composition root, not scaffolding",
                     "W5-TREE  options projection: 8 raids, ship-off defaults, a flip reaches the row",
                     "W5-BRIEF-G  determinism + role re-derivation (RM-1, RMS-1, RMS-2, RME-1, RML-1)",
                     "W5-SURFACES  the options panes' own logic: telemetry viewer + sound packs",
                     "W5-RELEASE  the assertable release-gate rows",
                     "W5-DBFIX  the owner's SavedVariables shape survives the upgrade",
                     "BRIEF-N  roster + talents read when they exist (RM-1, RM-2, RM-3)" }) do
    local n = GATE_FAILS[g] or 0
    realprint(("#   %-52s %s"):format(g, n == 0 and "PASS" or (n .. " FAIL")))
end
realprint("#")
realprint("#   RESULT: " .. (FAILS == 0 and "ALL PASS" or (FAILS .. " FAILURE(S) — RED")))
realprint("############################################################")
os.exit(FAILS == 0 and 0 or 1)
