--[[
    Daseeki Raid Mechanics — sound bucket

    A DBM-style pickable list of sounds. Built-ins (no dependency) PLUS every sound
    registered with LibSharedMedia-3.0 if present (so DBM / BigWigs / WeakAuras sound
    packs show up automatically). The list is rebuilt on demand so LSM media that
    registers after us is still picked up.

    Sound entries: { key, name, kind = "kit"|"file", value = <soundKitID|filepath> }
    "none" is always first.
--]]

local _, Addon = ...

-- Curated Blizzard built-ins. kit = SOUNDKIT id (reliable); file = path.
local BUILTINS = {
    { key = "none",        name = "None" },
    { key = "raidwarning", name = "Raid Warning", kind = "kit",  value = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959 },
    { key = "readycheck",  name = "Ready Check",  kind = "kit",  value = (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960 },
    { key = "ding",        name = "Ding",         kind = "file", value = "Sound\\Spells\\SimonGame_Visual_GameStart.ogg" },
    { key = "bell",        name = "Bell Toll",    kind = "file", value = "Sound\\Doodad\\BellTollAlliance.ogg" },
    { key = "boat",        name = "Boat Warning", kind = "file", value = "Sound\\Doodad\\BoatDockedWarning.ogg" },
    { key = "pvpflag",     name = "Flag Taken",   kind = "file", value = "Sound\\Interface\\PVPFlagTakenmono.ogg" },
    { key = "magic",       name = "Magic Click",  kind = "kit",  value = (SOUNDKIT and SOUNDKIT.IG_ABILITY_OPEN) or 852 },
}

local function GetLSM()
    if not LibStub then return nil end
    return LibStub:GetLibrary("LibSharedMedia-3.0", true)
end

-- Build the merged sound list (built-ins + LSM "sound" media). Rebuilt each call so
-- late-registering LSM media appears.
function Addon:GetSounds()
    local list = {}
    for _, e in ipairs(BUILTINS) do list[#list + 1] = e end

    -- Bundled DBM / NovaWorldBuffs sound packs (copied into Sounds/; see soundpacks.lua).
    -- These work even when DBM/Nova are disabled since the files live inside this addon.
    if Addon.BundledSounds then
        for _, e in ipairs(Addon.BundledSounds) do
            list[#list + 1] = { key = e.key, name = e.name, kind = "file", value = e.value }
        end
    end

    local LSM = GetLSM()
    if LSM then
        local seen = {}
        for _, e in ipairs(BUILTINS) do seen[e.name] = true end
        for _, name in ipairs(LSM:List("sound")) do
            if not seen[name] then
                local path = LSM:Fetch("sound", name, true)
                if path then
                    list[#list + 1] = { key = "lsm:" .. name, name = name, kind = "file", value = path }
                end
            end
        end
    end
    return list
end

function Addon:GetSoundByKey(key)
    if not key or key == "none" then return nil end
    for _, e in ipairs(Addon:GetSounds()) do
        if e.key == key then return e end
    end
    return nil
end

-- Resolve a sound key to its display name (for the dropdown's current value).
function Addon:GetSoundName(key)
    if not key or key == "none" then return "None" end
    local e = Addon:GetSoundByKey(key)
    return e and e.name or "None"
end

-- Array of display names (for the options dropdown).
function Addon:GetSoundNameList()
    local names = {}
    for _, e in ipairs(Addon:GetSounds()) do names[#names + 1] = e.name end
    return names
end

function Addon:GetSoundKeyByName(name)
    for _, e in ipairs(Addon:GetSounds()) do
        if e.name == name then return e.key end
    end
    return "none"
end

-- Play a sound by its bucket key (respects the global sound gate).
function Addon:PlaySoundByKey(key, ignoreGate)
    if not ignoreGate and not (Addon.db and Addon.db.settings.soundEnabled) then return end
    local e = Addon:GetSoundByKey(key)
    if not e then return end
    if e.kind == "kit" then
        PlaySound(e.value, "Master")
    elseif e.kind == "file" then
        PlaySoundFile(e.value, "Master")
    end
end

-- ── Font bucket (for "text" style alerts, e.g. on-cast notifications) ──────────--
-- Curated Blizzard built-ins (always present) PLUS any LibSharedMedia-3.0 "font" media.
local FONT_BUILTINS = {
    { key = "default",  name = "Default",       path = STANDARD_TEXT_FONT },
    { key = "arial",    name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { key = "skurri",   name = "Skurri",        path = "Fonts\\SKURRI.TTF" },
    { key = "morpheus", name = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
}

function Addon:GetFonts()
    local list = {}
    for _, e in ipairs(FONT_BUILTINS) do list[#list + 1] = e end

    local LSM = GetLSM()
    if LSM then
        local seen = {}
        for _, e in ipairs(FONT_BUILTINS) do seen[e.name] = true end
        for _, name in ipairs(LSM:List("font")) do
            if not seen[name] then
                local path = LSM:Fetch("font", name, true)
                if path then
                    list[#list + 1] = { key = "lsmfont:" .. name, name = name, path = path }
                end
            end
        end
    end
    return list
end

function Addon:GetFontByKey(key)
    if not key or key == "default" then return FONT_BUILTINS[1] end
    for _, e in ipairs(Addon:GetFonts()) do if e.key == key then return e end end
    return FONT_BUILTINS[1]
end

function Addon:GetFontPath(key) return Addon:GetFontByKey(key).path end
function Addon:GetFontName(key) return Addon:GetFontByKey(key).name end

function Addon:GetFontNameList()
    local names = {}
    for _, e in ipairs(Addon:GetFonts()) do names[#names + 1] = e.name end
    return names
end

function Addon:GetFontKeyByName(name)
    for _, e in ipairs(Addon:GetFonts()) do
        if e.name == name then return e.key end
    end
    return "default"
end
