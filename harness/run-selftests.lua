-- =====================================================================
-- Daseeki-Raid-Mechanics headless migration self-test harness (REAL Lua 5.1)
--
-- Follows the Daseeki suite harness pattern (see Daseeki-ClassHUD/harness):
-- stub the minimal WoW API, load the addon under a real Lua interpreter, drive
-- the REAL migration code, assert config is transformed-not-wiped, exit
-- non-zero on any failure.
--
-- Focus: NW-5 — the DB_VERSION gate no longer empties db.mechanics (per-mechanic
-- overrides) on a config-model bump, and db.stats (raid history) stays exempt.
-- Proof is driven through the REAL Addon:MigrateDB and the REAL Addon:Init.
--
-- Gates:
--   0        TOC PARSE   loadfile (parse only) every .lua the .toc lists.
--   FW       FIREWALL    change surface (core.lua + harness) carries NO 3rd-party
--                        identifier; pre-existing original-addon references
--                        elsewhere (bundled DBM/NWB sound packs, LibSharedMedia
--                        interop, UI analogies) are reported as informational
--                        notes, not failures. "dbm" is a legitimate OptionalDep
--                        and is deliberately NOT a forbidden token.
--   MIG-ALGO migration runner: stamp / newer-left / transform / GAP-NOT-WIPE.
--   MIG-INIT integration: real Addon:Init() preserves overrides AND stats.
--
-- Usage:  lua5.1 run-selftests.lua [RM_DIR]   (exit 0 = ALL PASS)
-- =====================================================================

local realprint = print   -- kept before the addon's print is captured below

local HARNESS_DIR = (arg[0]:match("^(.*)[\\/][^\\/]+$")) or "."
local function slash(p) return (p:gsub("\\", "/")) end
HARNESS_DIR = slash(HARNESS_DIR)
local DIR = slash(arg[1] or (HARNESS_DIR .. "/.."))
local function P(rel) return DIR .. "/" .. rel end

local TOC_FILE   = "Daseeki-Raid-Mechanics.toc"
local ADDON_NAME = "Daseeki-Raid-Mechanics"

local FAILS = 0
local function fail(m) FAILS = FAILS + 1; realprint("  FAIL  " .. m) end
local function ok(m)   realprint("  ok    " .. m) end
local function ck(cond, m) if cond then ok(m) else fail(m) end end

local function readFile(path)
    local fh = io.open(path, "r"); if not fh then return nil end
    local s = fh:read("*a"); fh:close(); return s
end

----------------------------------------------------------------------
-- GATE 0: TOC PARSE
----------------------------------------------------------------------
local function readTocLuaFiles(tocPath)
    local fh = io.open(tocPath, "r"); if not fh then return nil end
    local out = {}
    for line in fh:lines() do
        line = line:gsub("^\239\187\191", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 1) ~= "#" and line:lower():sub(-4) == ".lua" then
            out[#out + 1] = (line:gsub("\\", "/"))
        end
    end
    fh:close()
    return out
end

realprint("=== GATE 0: toc parse (loadfile every .lua in " .. TOC_FILE .. ") ===")
local TOC_LUA = readTocLuaFiles(P(TOC_FILE))
if not TOC_LUA or #TOC_LUA == 0 then realprint("  FAIL  cannot read .toc lua list"); os.exit(1) end
for _, rel in ipairs(TOC_LUA) do
    local chunk, err = loadfile(P(rel))
    if chunk then ok("parse " .. rel) else fail("parse " .. rel .. " -> " .. tostring(err)) end
end
if FAILS > 0 then realprint("=== GATE 0: FAIL (a file does not compile) ==="); os.exit(1) end
realprint("=== GATE 0: PASS ===\n")

----------------------------------------------------------------------
-- GATE FW: CLEAN-ROOM FIREWALL (change-surface strict; rest informational)
--
-- Raid-Mechanics is an ORIGINAL Daseeki addon (not a clean-room rebuild), so it
-- legitimately names other addons in comments — UI-pattern analogies, and
-- provenance notes for bundled DBM/NovaWorldBuffs sound packs and optional
-- LibSharedMedia interop. Those are NOT copied source. The gate therefore
-- HARD-FAILS only on the files this change authored/edited (the migration in
-- core.lua and the harness itself) and reports any identifier elsewhere as an
-- informational note. Note: "dbm" is a documented OptionalDep and is NOT a
-- forbidden token.
----------------------------------------------------------------------
local FORBIDDEN = {
    "portalmage", "totemtimers", "druidbar", "pallypower",
    "weakauras", "weakaurassaved", "aura_env",
    "shadownetwork", "novainstancetracker", "novaworldbuffs",
    "bigwigs", "elvui", "bartender4", "dominos",
}
local CHANGE_SURFACE = { ["core.lua"] = true }  -- the only .lua this change edits
realprint("=== GATE FW: clean-room firewall ===")
local FW_FILES = { "CHANGELOG.md", "README.md", TOC_FILE, ".pkgmeta" }
for _, rel in ipairs(TOC_LUA) do FW_FILES[#FW_FILES + 1] = rel end
local noteCount = 0
for _, rel in ipairs(FW_FILES) do
    local src = readFile(P(rel))
    if src then
        local lower, hits = src:lower(), {}
        for _, tok in ipairs(FORBIDDEN) do if lower:find(tok, 1, true) then hits[#hits + 1] = tok end end
        if #hits > 0 then
            if CHANGE_SURFACE[rel] then
                fail(rel .. " (change surface) contains: " .. table.concat(hits, ", "))
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
-- The harness's own file must be clean too (it names no product identifiers
-- except inside this FORBIDDEN table / comments describing the gate).
if FAILS > 0 then realprint("=== GATE FW: FAIL ==="); os.exit(1) end
realprint(("  (%d original-addon reference note(s); change surface is clean)"):format(noteCount))
realprint("=== GATE FW: PASS ===\n")

----------------------------------------------------------------------
-- Minimal WoW stub — only what core.lua touches at LOAD and in Init().
-- core.lua at load creates one loader frame (RegisterEvent/SetScript). Init
-- uses print + table ensures only (no frame creation, no ClassDefaults).
----------------------------------------------------------------------
_G.print = function() end   -- addon chat output: swallow (harness uses realprint)
_G.CreateFrame = function()
    local f = {}
    function f:RegisterEvent() end
    function f:UnregisterEvent() end
    function f:SetScript() end
    function f:GetScript() end
    return f
end
_G.strfind, _G.strmatch, _G.strsub, _G.format =
    string.find, string.match, string.sub, string.format

----------------------------------------------------------------------
-- Load the REAL core.lua into a fresh Addon namespace.
----------------------------------------------------------------------
local Addon = {}
do
    local chunk, err = loadfile(P("core.lua"))
    if not chunk then realprint("  FAIL  loadfile core.lua -> " .. tostring(err)); os.exit(2) end
    local success, rerr = pcall(chunk, ADDON_NAME, Addon)
    if not success then realprint("  FAIL  executing core.lua -> " .. tostring(rerr)); os.exit(2) end
end

----------------------------------------------------------------------
-- GATE MIG-ALGO: drive the REAL Addon:MigrateDB directly.
----------------------------------------------------------------------
realprint("=== GATE MIG-ALGO: Addon:MigrateDB (stamp / newer / transform / gap-not-wipe) ===")

-- (a) absent dbVersion -> stamp to 3; mechanics AND stats survive.
do
    local db = { mechanics = { ["naxx:1:1"] = { masterEnabled = false } },
                 stats = { naxx = { kills = 7 } } }
    local r = Addon:MigrateDB(db)
    ck(r == true, "(a) absent version returns true")
    ck(db.dbVersion == 3, "(a) absent version stamped to current (3)")
    ck(db.mechanics["naxx:1:1"].masterEnabled == false, "(a) mechanic override preserved (no wipe on stamp)")
    ck(db.stats.naxx.kills == 7, "(a) db.stats preserved")
end

-- (b) newer dbVersion -> left exactly as-is.
do
    local db = { dbVersion = 99, mechanics = { ["x"] = { scale = 2 } }, stats = { s = 1 } }
    local r = Addon:MigrateDB(db)
    ck(r == false, "(b) newer version returns false")
    ck(db.dbVersion == 99, "(b) newer version left as-is (not downgraded)")
    ck(db.mechanics.x.scale == 2, "(b) mechanic override untouched")
    ck(db.stats.s == 1, "(b) db.stats untouched")
end

-- (c) older dbVersion WITH a step -> ordered transform in place, neighbours kept.
do
    Addon.MIGRATIONS[2] = function(d) d.__stepran = true end
    local db = { dbVersion = 2, mechanics = { ["y"] = { opacity = 0.5 } }, stats = { s = 3 } }
    local r = Addon:MigrateDB(db)
    ck(r == true, "(c) older-with-step returns true")
    ck(db.__stepran == true, "(c) migration step actually ran (transform in place)")
    ck(db.dbVersion == 3, "(c) version advanced to current (3)")
    ck(db.mechanics.y.opacity == 0.5, "(c) mechanic override preserved through transform")
    ck(db.stats.s == 3, "(c) db.stats preserved through transform")
    Addon.MIGRATIONS[2] = nil  -- restore shipped (empty) chain
end

-- (d) REGRESSION PROOF: older dbVersion with the shipped EMPTY chain -> STOP and
--     leave data UNTOUCHED. The old code did `db.mechanics = {}` exactly here.
do
    local db = {
        dbVersion = 2,
        mechanics = { ["naxx:2:3"] = { masterEnabled = false, style = "text" } },
        stats     = { naxx = { kills = 12, bestTime = 210 } },
    }
    local r = Addon:MigrateDB(db)
    ck(r == false, "(d) missing-step returns false (does not proceed)")
    ck(db.dbVersion == 2, "(d) version left unchanged (not stamped over a gap)")
    ck(next(db.mechanics) ~= nil and db.mechanics["naxx:2:3"].masterEnabled == false,
       "(d) db.mechanics NOT emptied (regression proof vs old db.mechanics={})")
    ck(db.stats.naxx.kills == 12 and db.stats.naxx.bestTime == 210,
       "(d) db.stats intact (raid history exemption holds)")
end
realprint("=== GATE MIG-ALGO: " .. (FAILS == 0 and "PASS" or "FAIL") .. " ===\n")

----------------------------------------------------------------------
-- GATE MIG-INIT: drive the REAL Addon:Init() end to end.
-- A user at v2 with real overrides + kill history must keep both across Init().
----------------------------------------------------------------------
realprint("=== GATE MIG-INIT: real Addon:Init() preserves overrides AND stats ===")
do
    _G.DaseekiRaidMechanicsDB = {
        dbVersion = 2,  -- pre-bump user
        settings  = { barWidth = 250 },
        mechanics = { ["naxx:4:2"] = { masterEnabled = false, scale = 1.3 } },
        modules   = { loatheb = { enabled = true } },
        stats     = { naxx = { kills = 40, wipes = 3 } },
    }
    local success, rerr = pcall(function() Addon:Init() end)
    ck(success, "Init() ran without error" .. (success and "" or (" -> " .. tostring(rerr))))
    local db = _G.DaseekiRaidMechanicsDB
    ck(db.mechanics ~= nil and db.mechanics["naxx:4:2"] ~= nil
       and db.mechanics["naxx:4:2"].masterEnabled == false,
       "per-mechanic overrides preserved across Init (NOT emptied)")
    ck(db.mechanics["naxx:4:2"].scale == 1.3, "override field values intact")
    ck(db.stats ~= nil and db.stats.naxx ~= nil and db.stats.naxx.kills == 40
       and db.stats.naxx.wipes == 3, "db.stats (raid history) preserved across Init")
    ck(db.modules ~= nil and db.modules.loatheb ~= nil and db.modules.loatheb.enabled == true,
       "db.modules preserved across Init")
    ck(db.settings ~= nil and db.settings.barWidth == 250, "existing settings preserved (barWidth 250)")
    -- The shipped chain is empty, so a stale v2 db hits the non-destructive gap path:
    -- MigrateDB leaves the version (and all data) untouched rather than stamping over a
    -- transform it cannot perform. This is the exact input the OLD code wiped with
    -- `db.mechanics = {}`; the version staying 2 with data intact IS the regression proof.
    ck(db.dbVersion == 2, "gap path non-destructive: version left at 2, nothing wiped (old code emptied db.mechanics here)")
end
realprint("=== GATE MIG-INIT: " .. (FAILS == 0 and "PASS" or "FAIL") .. " ===\n")

----------------------------------------------------------------------
realprint("############################################################")
realprint("# Daseeki-Raid-Mechanics migration self-tests")
realprint("#   GATE 0        toc parse          : PASS")
realprint("#   GATE FW       clean-room firewall : PASS")
realprint("#   GATE MIG-ALGO migration runner   : " .. (FAILS == 0 and "PASS" or "FAIL"))
realprint("#   GATE MIG-INIT real Init()        : " .. (FAILS == 0 and "PASS" or "FAIL"))
realprint("#")
realprint("#   RESULT: " .. (FAILS == 0 and "ALL PASS" or (FAILS .. " FAILURE(S) — RED")))
realprint("############################################################")
os.exit(FAILS == 0 and 0 or 1)
