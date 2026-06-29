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

-- v3: split "enabled" into masterEnabled (mechanics-list checkbox, gates everything)
-- vs enabled (Ability Tracker's own checkbox) — old saved "enabled" overrides would
-- now mean something different, so wipe them.
local DB_VERSION = 3  -- bump wipes per-mechanic overrides (config model changed)

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

-- ── SavedVariables ───────────────────────────────────────────────────────────--
function Addon:Init()
    DaseekiRaidMechanicsDB = DaseekiRaidMechanicsDB or {}
    local db = DaseekiRaidMechanicsDB

    if not db.settings then db.settings = {} end
    for k, v in pairs(DEFAULT_SETTINGS) do
        if db.settings[k] == nil then db.settings[k] = v end
    end

    db.mechanics = db.mechanics or {}   -- key -> override table (see GetMechanicConfig)
    db.modules   = db.modules or {}     -- moduleId -> { enabled, ...config } (see modules.lua)
    db.settings.locked = true           -- unlock is a transient positioning mode; never start unlocked
    -- Config model changed in v2: drop stale overrides from the v1 (bar/warning/sound) model.
    if (db.dbVersion or 1) < DB_VERSION then
        db.mechanics = {}
    end
    db.dbVersion = DB_VERSION
    Addon.db = db
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

-- ── Login flow ───────────────────────────────────────────────────────────────--
function Addon:OnLogin()
    if Addon.InitEngine then Addon:InitEngine() end       -- engine.lua
    if Addon.RegisterOptions then Addon:RegisterOptions() end  -- options.lua
    print("|cff66ccffDaseeki Raid Mechanics|r loaded. Type |cffffffff/drm|r for options.")
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
