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

-- ── W5: SOUND PACKS ───────────────────────────────────────────────────────────
-- The sound list is FLAT and long — the bundled manifest alone is well over a
-- thousand entries across dozens of packs, plus whatever LibSharedMedia brings.
-- A flat list that long is not pickable, so the picker gains a PACK filter and the
-- options surface gains a default pack. The grouping is derived, not a second
-- source of truth: bundled keys are `pk:<Addon>/<Pack>/<file>.ogg`, so the pack
-- name falls straight out of the key.
Addon.SOUNDPACK_ALL      = "#all"
Addon.SOUNDPACK_BUILTIN  = "#builtin"
Addon.SOUNDPACK_LSM      = "#lsm"

-- Which pack does this sound key belong to? Returns a pack key and a display name.
function Addon:SoundPackOf(key)
    key = tostring(key or "")
    if key:sub(1, 4) == "lsm:" then return Addon.SOUNDPACK_LSM, "LibSharedMedia" end
    local body = key:match("^pk:(.+)$")
    if not body then return Addon.SOUNDPACK_BUILTIN, "Built-in" end
    -- "DBM-Core/Alexander/1.ogg" -> pack "DBM-Core/Alexander"; a file sitting
    -- directly in an addon's folder ("DBM-Core/AirHorn.ogg") -> pack "DBM-Core".
    local dir = body:match("^(.*)/[^/]+$")
    if not dir or dir == "" then return Addon.SOUNDPACK_BUILTIN, "Built-in" end
    return "pk:" .. dir, (dir:gsub("/", " "))
end

-- Ordered pack list for the picker's filter and the options dropdown:
--   { key, name, count }, "All sounds" first, then Built-in, then the bundled packs
-- alphabetically, then LibSharedMedia. Sorted (lesson Class 8) so the control does
-- not reshuffle between openings.
--
-- MEMOIZED, unlike GetSounds. GetSounds deliberately rebuilds on every call so
-- late-registering LibSharedMedia media appears — which is right for a list read
-- once per interaction, and wrong for one read on every KEYSTROKE in the picker's
-- search box: the bundled manifest alone is over a thousand entries, and deriving
-- the pack list walks it twice. The cache is dropped whenever the picker opens
-- (Addon:ShowSoundPicker), which is the only moment new media could matter.
Addon._soundPackCache = nil
function Addon:InvalidateSoundPacks() Addon._soundPackCache = nil end

function Addon:GetSoundPacks()
    if Addon._soundPackCache then return Addon._soundPackCache end
    local all = Addon:GetSounds()
    local byKey, order = {}, {}
    for _, e in ipairs(all) do
        local pk, name = Addon:SoundPackOf(e.key)
        local rec = byKey[pk]
        if not rec then
            rec = { key = pk, name = name, count = 0 }
            byKey[pk] = rec; order[#order + 1] = rec
        end
        rec.count = rec.count + 1
    end
    local function rank(r)
        if r.key == Addon.SOUNDPACK_BUILTIN then return 0 end
        if r.key == Addon.SOUNDPACK_LSM then return 2 end
        return 1
    end
    table.sort(order, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    local out = { { key = Addon.SOUNDPACK_ALL, name = "All sounds", count = #all } }
    for _, r in ipairs(order) do out[#out + 1] = r end
    Addon._soundPackCache = out
    return out
end

function Addon:GetSoundPackName(key)
    for _, p in ipairs(Addon:GetSoundPacks()) do
        if p.key == key then return p.name end
    end
    return "All sounds"
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

-- ── Wave 2: single-number + symbolic voice-line dispatch ──────────────────────--
-- PlayVoiceCountdown above speaks a whole 5..1 sequence off C_Timer. The 2.0 engine
-- does its own scheduling (ENGINE SPEC §4.4: "one scheduler task per second, keyed
-- by bar ID, so a restart cancels them wholesale"), so it needs to speak exactly ONE
-- number when its own task fires. That is this primitive; the sequencer stays for
-- the 1.x alert path, which still owns its own timing.

-- Max count the selected/first countdown pack declares (§5.5: packs declare 5 or 10;
-- §4.4: "count depth ... capped by the selected voice pack's declared maximum").
function Addon:VoiceCountMax(voiceKey)
    BuildVoicePacks()
    local pack = voiceByKey[voiceKey or (Addon.db and Addon.db.settings and Addon.db.settings.voiceCountKey)]
                 or voicePacks[1]
    return pack and pack.max or 0
end

-- Speak ONE number. Returns true when a file was actually played.
function Addon:PlayVoiceNumber(n, voiceKey)
    if not (Addon.db and Addon.db.settings.soundEnabled) then return false end
    BuildVoicePacks()
    local pack = voiceByKey[voiceKey or (Addon.db and Addon.db.settings.voiceCountKey)] or voicePacks[1]
    if not pack then return false end
    n = math.floor(tonumber(n) or 0)
    local path = n >= 1 and pack.files[n]
    if not path then return false end
    if type(_G.PlaySoundFile) == "function" then _G.PlaySoundFile(path, "Master") end
    return true
end

-- ENGINE SPEC §5.5: "Voice files are addressed by a SHORT SYMBOLIC NAME resolved to
-- a per-pack path; callers may also pass an explicit path." The bundled voice pack
-- ships one .ogg per symbolic line name, so resolution is a lookup in the generated
-- manifest — never a string built by hand, so a renamed/removed file resolves to nil
-- and degrades instead of erroring on a missing path (§9.3).
local voiceLines            -- symbolic name -> path
local VOICE_LINE_DIR = "DBM-VPVEM"
-- The pack directory contains a hyphen, which is a LUA PATTERN QUANTIFIER, so the
-- prefix must be escaped before it is used as a pattern. (Unescaped, "DBM-VPVEM"
-- silently matches nothing and every voice line resolves to nil.)
local VOICE_LINE_PATTERN = "^pk:" .. VOICE_LINE_DIR:gsub("(%W)", "%%%1") .. "/([%w_]+)%.ogg$"

local function BuildVoiceLines()
    if voiceLines then return end
    voiceLines = {}
    for _, e in ipairs(Addon.BundledSounds or {}) do
        local name = e.key:match(VOICE_LINE_PATTERN)
        if name then voiceLines[name] = e.value end
    end
end

function Addon:GetVoiceLine(name)
    if type(name) ~= "string" or name == "" then return nil end
    if name:find("[/\\]") then return name end        -- an explicit path wins
    BuildVoiceLines()
    return voiceLines[name]
end

function Addon:PlayVoiceLine(name)
    if not (Addon.db and Addon.db.settings.soundEnabled) then return false end
    local path = Addon:GetVoiceLine(name)
    if not path then return false end
    if type(_G.PlaySoundFile) == "function" then _G.PlaySoundFile(path, "Master") end
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

-- The path a font key resolves to. "default" is special: it means "whatever this UI's
-- default face is", so with Daseeki-Core loaded it resolves to the user's PICKED suite
-- face (UI.FontFile() — already load-verified, with Core's own Friz fallback) rather
-- than to the client's STANDARD_TEXT_FONT. A user who explicitly picked Arial Narrow /
-- Skurri / Morpheus / an LSM font still gets exactly that: only "default" defers.
function Addon:GetFontPath(key)
    if not key or key == "default" then
        local UI = _G.DaseekiUI
        if UI and UI.FontFile then
            local ok, path = pcall(UI.FontFile)
            if ok and type(path) == "string" and path ~= "" then return path end
        end
    end
    return Addon:GetFontByKey(key).path
end
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
