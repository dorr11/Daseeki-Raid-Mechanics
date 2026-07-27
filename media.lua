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

-- ── Voice countdown sequencer ──────────────────────────────────────────────────--
-- Speaks bundled per-number .oggs (Sounds/DBM-Core/<Voice>/1.ogg .. 10.ogg) as a
-- "5... 4... 3... 2... 1" count. The pack registry is derived from
-- Addon.BundledSounds at first use (soundpacks.lua loads AFTER this file, so it
-- must be lazy): any pack directory with contiguous "1.ogg".."N.ogg" files counts
-- as a voice pack (combined clips like Corsica's "threecount.ogg" don't qualify).
local voicePacks    -- sorted array of { key, name, files = { [n] = path }, max = N }
local voiceByKey    -- key -> pack

local function BuildVoicePacks()
    if voicePacks then return end
    voicePacks, voiceByKey = {}, {}
    local byDir = {}
    for _, e in ipairs(Addon.BundledSounds or {}) do
        local dir, n = e.key:match("^pk:(.+)/(%d+)%.ogg$")
        if dir then
            local p = byDir[dir]
            if not p then
                -- display name from the manifest entry ("DBM Alexander: 3" -> "DBM Alexander")
                p = { key = dir, name = e.name:match("^(.-):%s*%d+$") or dir, files = {} }
                byDir[dir] = p
            end
            p.files[tonumber(n)] = e.value
        end
    end
    for _, p in pairs(byDir) do
        local m = 0
        while p.files[m + 1] do m = m + 1 end   -- contiguous run from 1
        if m >= 1 then
            p.max = m
            voicePacks[#voicePacks + 1] = p
            voiceByKey[p.key] = p
        end
    end
    table.sort(voicePacks, function(a, b) return a.name < b.name end)
end

-- Pack list for a future options dropdown: array of { key, name }.
function Addon:GetVoiceCountPacks()
    BuildVoicePacks()
    local list = {}
    for _, p in ipairs(voicePacks) do list[#list + 1] = { key = p.key, name = p.name } end
    return list
end

-- Pending number timers for the active countdown (one handle per spoken number).
Addon._voiceTimers = {}

-- Cancel any in-flight countdown — no stray numbers after this returns.
function Addon:StopVoiceCountdown()
    for _, t in ipairs(Addon._voiceTimers) do
        if t.Cancel then t:Cancel() end
    end
    wipe(Addon._voiceTimers)
end

-- Speak each remaining whole second from min(seconds, pack max) down to 1.
-- voiceKey nil -> settings.voiceCountKey, else the first available pack. Calling
-- again cancels the previous countdown first. Returns true if started.
function Addon:PlayVoiceCountdown(seconds, voiceKey)
    Addon:StopVoiceCountdown()
    if not (Addon.db and Addon.db.settings.soundEnabled) then return end
    BuildVoicePacks()
    local pack = voiceByKey[voiceKey or (Addon.db and Addon.db.settings.voiceCountKey)] or voicePacks[1]
    if not pack then return false end
    local n = math.min(math.floor(tonumber(seconds) or 0), pack.max)
    if n < 1 then return false end
    PlaySoundFile(pack.files[n], "Master")
    for i = n - 1, 1, -1 do
        local num = i
        Addon._voiceTimers[#Addon._voiceTimers + 1] = C_Timer.NewTimer(n - num, function()
            PlaySoundFile(pack.files[num], "Master")
        end)
    end
    return true
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
