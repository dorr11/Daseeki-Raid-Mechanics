--[[
    Daseeki Raid Mechanics — core
    Per-raid, per-fight boss-mechanic alert tool for WoW Classic Era (1.14.x).

    Plugs into the Daseeki-Core hub (DaseekiSuite) as the "raidmechanics" section.
    Keeps its own account-wide SavedVariables (DaseekiRaidMechanicsDB); the DB only
    stores USER OVERRIDES of the encounter-data defaults (enable/alert-type/position).
--]]

local AddonName, Addon = ...
DaseekiRaidMechanics       = Addon
_G["Daseeki-Raid-Mechanics"] = Addon

-- ── Field Ledger chat helpers (Core-optional; graceful without Daseeki-Core) ──────
-- BRAND_SPEC §2/§6: chat identity + status words reach the Field Ledger palette
-- through these when Daseeki-Core (DaseekiUI) is present. Without Core they fall back
-- to the exact literals this addon shipped with, so the standalone chat output is
-- byte-identical to what raiders already see. Alert-path HUD visuals are untouched.
local LEGACY_HEX = {   -- pre-Ledger colors, keyed by token role (no leading |cff)
    brand = "66ccff",  -- old cyan identity tag
    ok    = "00ff00",  -- green ON / enabled
    danger= "ff0000",  -- red OFF / disabled / locked / cancelled
    warn  = "ff8800",  -- amber reminder / caution
    text  = "ffffff",  -- white command names / emphasis
}

-- Token → "|cffRRGGBB" prefix. Uses the live Ledger token with Core; else the legacy
-- literal above; nil for an unknown token with no legacy mapping.
function Addon:Hex(token)
    local UI = _G.DaseekiUI
    if UI and UI.Color then
        local r, g, b = UI.Color(token)
        local function b255(v) return math.max(0, math.min(255, math.floor((v or 0) * 255 + 0.5))) end
        return ("|cff%02x%02x%02x"):format(b255(r), b255(g), b255(b))
    end
    local lg = LEGACY_HEX[token]
    return lg and ("|cff" .. lg) or nil
end

-- Wrap `text` in a token color for chat strings; plain text if the token can't resolve.
function Addon:Wrap(token, text)
    local h = Addon:Hex(token)
    if not h then return tostring(text) end
    return h .. tostring(text) .. "|r"
end

-- Brand-tinted chat identity tag (crimson wax seal with Core; legacy cyan without).
function Addon:Tag(text)
    text = text or "[DRM]"
    return (Addon:Hex("brand") or "|cff66ccff") .. text .. "|r"
end

-- v3: split "enabled" into masterEnabled (mechanics-list checkbox, gates everything)
-- vs enabled (Ability Tracker's own checkbox). A future config-model change is
-- handled by the migration chain below (transform in place), never by wiping.
local DB_VERSION = 3  -- current config-model version; migrations transform in place, never wipe

local DEFAULT_SETTINGS = {
    enabled      = true,    -- master on/off
    locked       = true,    -- false = alert anchors draggable (placement mode)
    soundEnabled = true,    -- global sound gate
    barTexture   = "Interface\\TargetingFrame\\UI-StatusBar",
    barWidth     = 200,
    barHeight    = 20,
    autoDebug    = false,   -- auto-enable /drm debug logging in 20/40-man raids
    deathSound    = false,  -- play a sound when a boss npc dies
    deathSoundKey = "raidwarning",
    debugOnly     = false,  -- kill-switch: silence ALL mechanic output, just log combat-log data
}

-- Hardcoded fallbacks when neither the DB override nor the data file specify a value.
local DEF_STYLE   = "bar"
local DEF_SCALE   = 1.0
local DEF_OPACITY = 1.0
local DEF_SOUND   = "none"
local DEF_COOLDOWN = 10
local DEF_FONT      = "default"
local DEF_FONT_SIZE = 32   -- "text" style banners (e.g. on-cast notifications) default LARGE/readable

-- ── Utilities ──────────────────────────────────────────────────────────────────
function Addon:DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = type(v) == "table" and Addon:DeepCopy(v) or v
    end
    return copy
end

-- "raidId:bossId:mechId"
function Addon:MechKey(raidId, bossId, mechId)
    return raidId .. ":" .. bossId .. ":" .. mechId
end

-- ── SavedVariables migration chain ───────────────────────────────────────────────
-- Stamp-don't-wipe, generalized from the suite template (Daseeki-ClassHUD store.lua
-- Store.Migrate). The next DB_VERSION bump must TRANSFORM a player's saved config, not
-- erase it. MIGRATIONS[n] upgrades a db stamped dbVersion n up to n+1, in place.
--
-- It is EMPTY today on purpose: every existing user is already at v3 with v3-shaped
-- overrides, so the chain is a no-op. The runner exists now so the FIRST real
-- config-model change is a transform step here, not the old db.mechanics wipe.
--
-- db.stats (raid kill/wipe history) is NOT config and is never in a migration's
-- purview — it is ensured and left untouched in Init regardless of version, exactly
-- as before. RENAME-AND-PARK: if a future model change is ever genuinely
-- unconvertible, a step must PARK the old overrides (e.g. db.mechanics_v3 =
-- db.mechanics) rather than empty them — data stays recoverable. Never wipe.
Addon.MIGRATIONS = {}

-- ── PROFILE ADOPTERS (additive, version-free) ────────────────────────────────────
-- A MIGRATIONS step is for a CONFIG-MODEL change: the shape of the db moved, so the
-- version has to move with it. This list is for the other thing — a setting that used
-- to live somewhere ELSE in a shape the current model already understands, and now
-- has a proper home. Nothing changes shape, nothing is destroyed, and DB_VERSION does
-- not move; the old fields are left exactly where they are so the change is
-- recoverable, and each adopter marks the record it read so a second login is a no-op.
--
-- The first (2.1.1): thaddius.lua's polarity-change alert. Its four settings lived on
-- the POLARITY SHIFT row's record as `pcEnabled` / `pcText` / `pcSound` / `pcSoundKey`
-- because the alert was a sub-section of that row's options page. The alert is its own
-- row now, so those four become that row's ordinary enable / route / sound-mode /
-- sound-file fields. The adopter is registered by the file that owns the alert.
--
-- Each entry is `function(db)`; they run in registration order, AFTER the ensures
-- below (so `db.mechanics` exists) and never before Init. Failures are the caller's
-- to notice: nothing here is pcall-wrapped, because a silent half-adopted profile is
-- worse than a visible error.
Addon.PROFILE_ADOPTERS = {}

-- Migrate db in place. Returns true when it is safe to proceed onto seeding.
--   absent/unknown dbVersion -> stamp to current, convert nothing (ensures fill gaps)
--   dbVersion NEWER than this build -> leave EXACTLY as-is (never downgrade), report
--   dbVersion OLDER -> run MIGRATIONS steps in order; a MISSING step STOPS and leaves
--                      the data untouched (reported) rather than emptying db.mechanics.
function Addon:MigrateDB(db)
    local from = tonumber(db.dbVersion)
    if from == nil then
        db.dbVersion = DB_VERSION
        return true
    end
    if from > DB_VERSION then
        print(Addon:Tag("[DRM]") .. " settings were saved by a newer version; left untouched.")
        return false
    end
    while (db.dbVersion or 0) < DB_VERSION do
        local step = Addon.MIGRATIONS[db.dbVersion]
        if not step then
            print(Addon:Tag("[DRM]") .. " settings could not be upgraded from v"
                .. tostring(db.dbVersion) .. "; left untouched.")
            return false
        end
        step(db)
        db.dbVersion = db.dbVersion + 1
    end
    return true
end

-- ── SavedVariables ───────────────────────────────────────────────────────────--
function Addon:Init()
    DaseekiRaidMechanicsDB = DaseekiRaidMechanicsDB or {}
    local db = DaseekiRaidMechanicsDB

    -- Migrate the saved config model in place before seeding. Never wipes: an
    -- unknown version is stamped, an older one transformed step-by-step, a newer
    -- one left as-is. db.stats is untouched by this and by the ensures below.
    Addon:MigrateDB(db)

    if not db.settings then db.settings = {} end
    for k, v in pairs(DEFAULT_SETTINGS) do
        if db.settings[k] == nil then db.settings[k] = v end
    end

    db.mechanics = db.mechanics or {}   -- key -> override table (see GetMechanicConfig)
    db.modules   = db.modules or {}     -- moduleId -> { enabled, ...config } (see modules.lua)
    -- 2.0 anchor rework: anchorKey -> { attach, frameName, point, relPoint, ox, oy,
    -- size, detached } (see ui_anchors.lua). PURELY ADDITIVE — the bucket a row routes
    -- to lives on db.mechanics[key].route and the screen position still lives on
    -- db.mechanics[key].pos, so DB_VERSION does not move and the migration chain
    -- stays a no-op. Records are written only when something is actually configured.
    db.anchors   = db.anchors or {}
    -- Debug log: persisted to SavedVariables (NOT a transient in-memory table) so it
    -- survives /reload and disk-writes automatically on logout, like everything else
    -- here. debugLive = the in-progress current raid sitting; debugSessions = past
    -- sittings finalized (tagged with raidId) on logout/leaving the raid — see
    -- engine.lua FinalizeDebugSession.
    db.debugLive     = db.debugLive or {}
    db.debugSessions = db.debugSessions or {}
    -- Kill statistics: db.stats[raidId][bossId] = { kills, wipes, bestTime, lastTime,
    -- lastResult, firstKillAt } — written by engine.lua's Disengage, read by
    -- Addon:BuildStatsText and the options boss panels. Only the root is ensured here;
    -- per-boss tables are created lazily on first record (GetBossStats below). NOT
    -- wiped on DB_VERSION bumps — it's raid history, not config overrides.
    db.stats = db.stats or {}
    db.settings.locked = true           -- unlock is a transient positioning mode; never start unlocked
    Addon.db = db
    -- Additive adoptions, last: they read and write db.mechanics, which is ensured
    -- above, and they need Addon.db set because they go through the ordinary writers.
    for _, adopt in ipairs(Addon.PROFILE_ADOPTERS) do adopt(db) end
end

-- ── Mechanic config (data-file defaults merged with per-key DB overrides) ───────
-- Precedence per field: DB override > data-file default > hardcoded fallback.
-- Returns { mode, masterEnabled, enabled, style, scale, opacity, sound, cooldown,
--           window, winSound, winWarning, pos }.
--
-- `masterEnabled` (mechanics-list checkbox) vs `enabled` (Ability Tracker checkbox
-- in the detail pane) are deliberately SEPARATE fields: masterEnabled gates EVERYTHING
-- under this mechanic key (Ability Tracker + On Cast Notification + Personal Damage
-- Warning + reminder + count) — checked once, early, by the engine before anything
-- dispatches. `enabled` only gates the Ability Tracker's own visual/sound (FireAlert/
-- StartCooldown/ResetCooldown). A mechanic's `default=false` in the data file means
-- "off entirely by default", so it feeds masterEnabled, not enabled.
function Addon:GetMechanicConfig(key, mechDef)
    mechDef = mechDef or {}
    local o = Addon.db.mechanics[key] or {}
    local function pick(field, dataVal, fallback)
        if o[field] ~= nil then return o[field] end
        if dataVal ~= nil then return dataVal end
        return fallback
    end

    local cfg = {}
    cfg.mode          = mechDef.mode or "alert"             -- not user-overridable
    cfg.masterEnabled = pick("masterEnabled", mechDef.default, true)
    cfg.enabled       = pick("enabled", mechDef.default, true)
    cfg.style      = pick("style",      mechDef.style,    DEF_STYLE)
    cfg.scale      = pick("scale",      mechDef.scale,    DEF_SCALE)
    cfg.opacity    = pick("opacity",    mechDef.opacity,  DEF_OPACITY)
    cfg.sound      = pick("sound",      mechDef.sound,    DEF_SOUND)
    cfg.cooldown   = mechDef.cooldown or DEF_COOLDOWN       -- hardcoded data, not user-overridable
    cfg.window     = pick("window",     mechDef.window,   nil)
    cfg.winSound   = pick("winSound",   mechDef.winSound, false)
    cfg.winWarning = pick("winWarning", mechDef.winWarning, false)
    cfg.glowThreshold = pick("glowThreshold", mechDef.glowThreshold, 0)  -- 0 = off
    cfg.leadTime   = pick("leadTime", mechDef.leadTime, 5)   -- reminder lead (sec)
    cfg.fontKey    = pick("fontKey",  mechDef.fontKey,  DEF_FONT)       -- "text" style typeface
    cfg.fontSize   = pick("fontSize", mechDef.fontSize, DEF_FONT_SIZE)  -- "text" style point size
    cfg.pos        = o.pos
    return cfg
end

-- Debug Only mode: a blanket kill-switch checked by every alert/cooldown/module
-- dispatch path in engine.lua — silences ALL mechanic output (visuals, sounds,
-- custom widgets) while combat-log debug capture keeps running, so real fights can
-- be used to gather accurate timing data without the addon's (possibly wrong)
-- guesses firing alongside it.
function Addon:IsDebugOnly()
    return Addon.db and Addon.db.settings and Addon.db.settings.debugOnly == true
end

-- Persist a single override field for a mechanic key.
function Addon:SetMechanicOption(key, field, value)
    local m = Addon.db.mechanics[key]
    if not m then m = {}; Addon.db.mechanics[key] = m end
    m[field] = value
end

-- Persist a mechanic's alert anchor (verbatim GetPoint tuple).
function Addon:SetMechanicPos(key, point, relPoint, x, y)
    local m = Addon.db.mechanics[key]
    if not m then m = {}; Addon.db.mechanics[key] = m end
    m.pos = { point = point, relPoint = relPoint, x = x, y = y }
end

-- ── Kill statistics ──────────────────────────────────────────────────────────--
-- Lazily creates (and returns) the per-boss stats table — schema in Init's comment.
-- Only the RECORD path (engine.lua Disengage) should call this; readers (options
-- panel, BuildStatsText) peek at Addon.db.stats directly so browsing the UI never
-- litters the DB with empty zero-kill entries.
function Addon:GetBossStats(raidId, bossId)
    local stats = Addon.db.stats
    local r = stats[raidId]
    if not r then r = {}; stats[raidId] = r end
    local s = r[bossId]
    if not s then
        -- bestTime/lastTime/lastResult/firstKillAt stay absent (nil) until first record.
        s = { kills = 0, wipes = 0 }
        r[bossId] = s
    end
    return s
end

-- ── Login flow ───────────────────────────────────────────────────────────────--
function Addon:OnLogin()
    if Addon.InitEngine then Addon:InitEngine() end       -- engine.lua
    if Addon.RegisterOptions then Addon:RegisterOptions() end  -- options.lua
    print(Addon:Tag("Daseeki Raid Mechanics") .. " loaded. Type " .. Addon:Wrap("text", "/drm") .. " for options.")
    -- Persistent reminder so Debug Only (a blanket alert kill-switch) is never left on
    -- silently across sessions. Pairs with the on-screen indicator (engine.lua).
    if Addon:IsDebugOnly() then
        print(Addon:Tag("[DRM]") .. " " .. Addon:Wrap("warn", "Reminder:") .. " Debug Only is ON — ALL mechanic alerts are silenced (combat data is only being logged). Turn it off in " .. Addon:Wrap("text", "/drm") .. " -> General, or with " .. Addon:Wrap("text", "/drm debugonly") .. ".")
    end
    if Addon.UpdateDebugOnlyIndicator then Addon:UpdateDebugOnlyIndicator() end
end

-- ── Events ───────────────────────────────────────────────────────────────────--
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == AddonName then Addon:Init() end
    elseif event == "PLAYER_LOGIN" then
        Addon:OnLogin()
    end
end)
