--[[
    Daseeki Raid Mechanics 2.0 — warning TIERS (presentation, wave 2)

    ENGINE SPEC §5.1 the three tiers, §5.2 targeting/name colouring and the combined
    and precise batchers, §5.4 the filtering rules and global suppressors, §5.5 the
    voice-pack contract, §12 the numbers.

    TIER 1 is the bar surface (ui_bars.lua). This file owns TIERS 2 AND 3:

      Tier 2 — ANNOUNCEMENTS.  Three stacked lines at their own anchor. 1.5 s at
               full alpha then a fade over an additional 30 % of that, on a 0.05 s
               ticker. A new line takes the first free slot; when all three are busy
               the oldest scrolls off (2 -> 1, 3 -> 2) and the new line takes slot 3.
               A pop animation scales to 1.5x over 0.2 s and back over 0.2 s. Four
               colour slots map to announce priority.

      Tier 3 — SPECIAL WARNINGS.  Two stacked lines at a SEPARATE anchor, a much
               larger THICKOUTLINE face, the same duration/fade model, plus a sound
               tier 1-4 (personal / everyone / very important / run away) and a
               fifth tier reserved for "your name appeared in the user's note".
               Each tier carries its own sound, screen-flash colour, flash duration,
               alpha and repeat count. Flashes are suppressed entirely while the
               player is dead or a ghost.

    THE VISUAL WEIGHT DIFFERENCE IS THE POINT. Two tiers that look alike are one
    tier with extra steps: tier 2 is body-scale text that scrolls, tier 3 is a
    raid-legible headline with a screen flash and a voice line. That separation is
    what makes "move NOW" readable at a glance during a 40-man pull.

    ROLE / CLASS FILTERING IS ALREADY RESOLVED ENGINE-SIDE. core_api's
    `API.IsRowEnabled` gates every warning row through `API.RowDefault` (ship-off
    defaults, role gates, dynamic class defaults) BEFORE `Runtime:Act` emits it. By
    the time WARN_ANNOUNCE / WARN_SPECIAL reach this file the decision is made, so
    this file RENDERS WHAT ARRIVES and re-litigates nothing. What it does supply is
    the RESOLVERS the engine calls (Addon.RoleResolver / Addon.ClassResolver) —
    those were W1 stubs and are filled from the Era services in svc_era.lua.

    DREW_UI_STYLE: both stacks CENTRE horizontally at their anchor (principle 3),
    lines are one configured pad apart with no dead band (principle 4), the anchors
    carry labelled drag handles while unlocked (principle 6), faces come from the
    suite picker through Addon:ReFaceKeepingSize (so tier 3 keeps the point size
    that makes it readable across a raid), and every colour is a theme token.
--]]

local _, Addon = ...

local Warn = {}
Addon.Warnings = Warn

local function S() return Addon.Sched end

-- ══════════════════════════════════════════════════════════════════════════════
--  CONSTANTS (ENGINE SPEC §5.1, §5.2, §12)
-- ══════════════════════════════════════════════════════════════════════════════
Warn.DURATION       = 1.5     -- §12 "warning display duration: 1.5 s"
Warn.FADE_FRACTION  = 0.30    -- §12 "+ 30 % fade tail"
Warn.TICK           = 0.05    -- §12 "0.05 s tick"
Warn.POP_UP         = 0.2     -- §12 "warning pop animation: 0.2 s up"
Warn.POP_DOWN       = 0.2     -- §12 "0.2 s down"
Warn.POP_SCALE      = 1.5     -- §12 "1.5x scale"
Warn.ANNOUNCE_LINES = 3       -- §5.1 "three stacked text lines"
Warn.SPECIAL_LINES  = 2       -- §5.1 "two stacked lines"
Warn.ANNOUNCE_FONT  = 20      -- §5.1 "default font size 20"
Warn.SPECIAL_FONT   = 35      -- §5.1 "default font size 35"
Warn.COMBINE_DEBOUNCE = 0.5   -- §12 "combined-warning debounce"
Warn.COMBINE_CAP_ANNOUNCE = 7 -- §12 "7 names"
Warn.COMBINE_CAP_SPECIAL  = 6 -- §12 "(6 for special warnings)"
Warn.PRECISE_FALLBACK = 1.2   -- §12 "precise-warning fallback: 1.2 s"
Warn.VOICE_MIN_VERSION = 19   -- §5.5 "minimum acceptable voice-pack version (currently 19)"

-- 2.0 ANCHOR REWORK: the two anchors are unchanged, and so are their saved-position
-- keys. What changed is that they are now BUCKETS a row can be routed to: the
-- announcement anchor is Minor, the special-warning anchor is Major, and a per-row
-- control decides which one a warning arrives at (owner design item 1). Routing a
-- warning to Major gives it the full special-warning treatment — the big face, the
-- screen flash, the tier sound — because that IS the Major surface; the control's
-- hint says so.
Warn.ANCHOR_ANNOUNCE = "#warn.announce"
Warn.ANCHOR_SPECIAL  = "#warn.special"
Warn.ANCHOR_MINOR    = Warn.ANCHOR_ANNOUNCE
Warn.ANCHOR_MAJOR    = Warn.ANCHOR_SPECIAL
Warn.DEFAULT_POS = {
    [Warn.ANCHOR_ANNOUNCE] = { point = "TOP", relPoint = "TOP", x = 0, y = -190 },
    [Warn.ANCHOR_SPECIAL]  = { point = "TOP", relPoint = "TOP", x = 0, y = -120 },
}
-- Where a Custom warning's own anchor starts before the user drags it.
Warn.CUSTOM_DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = 100 }

-- §5.1: "Each special warning carries a SOUND TIER 1-4 (personal / everyone / very
-- important / run away), and a fifth tier reserved for 'your name appeared in the
-- user's note'. Per tier the user configures: sound file, screen-flash colour, flash
-- duration, flash alpha, flash repeat count, and controller vibration. Defaults:
-- tiers 1-2 flash once, tier 4 twice, tiers 3 and 5 three times; vibration on for
-- tiers 3-5 only."
--
-- The sound keys are OUR bundled bucket keys (media.lua / soundpacks.lua), so the
-- tier defaults work with every third-party pack uninstalled. Flash COLOURS are
-- theme tokens (Addon:FlashColor).
Warn.SOUND_TIER = {
    [1] = { label = "Personal",       sound = "readycheck",                    flashDuration = 0.4, flashAlpha = 0.22, flashRepeat = 1, vibrate = false },
    [2] = { label = "Everyone",       sound = "raidwarning",                   flashDuration = 0.4, flashAlpha = 0.22, flashRepeat = 1, vibrate = false },
    [3] = { label = "Very important", sound = "pk:DBM-Core/alarmclockbeeps.ogg", flashDuration = 0.5, flashAlpha = 0.30, flashRepeat = 3, vibrate = true },
    [4] = { label = "Run away",       sound = "pk:DBM-Core/AirHorn.ogg",       flashDuration = 0.5, flashAlpha = 0.32, flashRepeat = 2, vibrate = true },
    [5] = { label = "Your note",      sound = "pk:DBM-Core/blip_8.ogg",        flashDuration = 0.4, flashAlpha = 0.26, flashRepeat = 3, vibrate = true },
}
-- §5.5: the voice-replacement switch for special warnings "only applies when the
-- object's sound is one of the FOUR BUILT-IN TIERS — a user-selected custom sound
-- file always wins over the voice pack."
Warn.BUILTIN_TIERS = { [1] = true, [2] = true, [3] = true, [4] = true }

-- ══════════════════════════════════════════════════════════════════════════════
--  SETTINGS — additive, lazily defaulted (same house pattern as the bar surface)
-- ══════════════════════════════════════════════════════════════════════════════
local SETTING_DEFAULTS = {
    -- §5.4 global suppressors, each a single option
    hideWarnings         = false,
    suppressBossAnnounce = false,
    suppressTargetAnnounce = true,     -- §5.4: "on by default"
    suppressSpecialText  = false,
    suppressSpecialFlash = false,
    suppressSpecialSound = false,
    suppressVibration    = false,
    -- §5.5 the two independent replacement switches
    voiceReplacesAnnounce     = false,
    voiceReplacesSpecialSound = false,
    voiceEnabled              = true,
    voicePackVersion          = Warn.VOICE_MIN_VERSION,
    -- presentation
    announceFont = Warn.ANNOUNCE_FONT,
    specialFont  = Warn.SPECIAL_FONT,
    pad          = 4,
    mirrorToChat = false,              -- §5.1 "optional mirror to a chat frame"
    combineSort  = false,              -- §5.2 "optional alphabetical sort before display"
}

function Warn.Settings()
    local db = Addon.db
    if type(db) ~= "table" or type(db.settings) ~= "table" then return SETTING_DEFAULTS end
    local w = db.settings.warnings
    if type(w) ~= "table" then w = {}; db.settings.warnings = w end
    for k, v in pairs(SETTING_DEFAULTS) do if w[k] == nil then w[k] = v end end
    return w
end

-- §5.4: "When ALL THREE special-warning suppressors are on the engine SHORT-CIRCUITS
-- AT THE TOP of the show path for CPU." Cheap, and it is the difference between a
-- muted raider paying nothing and paying for a full render they never see.
function Warn.SpecialFullySuppressed()
    local s = Warn.Settings()
    return s.suppressSpecialText and s.suppressSpecialFlash and s.suppressSpecialSound
end

-- ══════════════════════════════════════════════════════════════════════════════
--  MODEL — the line stack. Pure: every function takes `now`.
-- ══════════════════════════════════════════════════════════════════════════════
local Stack = {}
Stack.__index = Stack
Warn.Stack = Stack

function Warn.NewStack(lines)
    return setmetatable({ lines = lines, slots = {}, pushed = 0 }, Stack)
end

function Stack:Expired(entry, now)
    return (now - entry.at) >= (entry.duration + entry.duration * Warn.FADE_FRACTION)
end

-- Free every slot whose line has finished its fade. Slots are NOT compacted: §5.1
-- says a new line takes "the first free slot", which only means anything if an
-- expired middle line leaves a hole.
function Stack:Prune(now)
    local freed = 0
    for i = 1, self.lines do
        local e = self.slots[i]
        if e and self:Expired(e, now) then self.slots[i] = nil; freed = freed + 1 end
    end
    return freed
end

-- §5.1: "Each new line takes the first free slot; if all three are busy the oldest
-- scrolls off (line 2->1, 3->2) and the new one takes slot 3."
function Stack:Push(entry, now)
    self:Prune(now)
    entry.at = now
    entry.duration = entry.duration or Warn.DURATION
    entry.seq = self.pushed + 1
    self.pushed = entry.seq
    for i = 1, self.lines do
        if not self.slots[i] then self.slots[i] = entry; return i, false end
    end
    for i = 1, self.lines - 1 do self.slots[i] = self.slots[i + 1] end
    self.slots[self.lines] = entry
    return self.lines, true
end

function Stack:Count()
    local n = 0
    for i = 1, self.lines do if self.slots[i] then n = n + 1 end end
    return n
end

function Stack:Clear()
    for i = 1, self.lines do self.slots[i] = nil end
end

-- §5.1 duration/fade model: full alpha for `duration`, then a fade over an
-- additional 30 % of it.
function Warn.Alpha(entry, now)
    local t = now - entry.at
    local d = entry.duration or Warn.DURATION
    local tail = d * Warn.FADE_FRACTION
    if t <= d then return 1 end
    if t >= d + tail then return 0 end
    return 1 - (t - d) / tail
end

-- §5.1 pop animation: "scales the text to 1.5x over 0.2 s and back over the next 0.2 s."
function Warn.PopScale(entry, now)
    local t = now - entry.at
    if t < 0 then return 1 end
    if t < Warn.POP_UP then return 1 + (Warn.POP_SCALE - 1) * (t / Warn.POP_UP) end
    if t < Warn.POP_UP + Warn.POP_DOWN then
        return Warn.POP_SCALE - (Warn.POP_SCALE - 1) * ((t - Warn.POP_UP) / Warn.POP_DOWN)
    end
    return 1
end

Warn.announceStack = Warn.NewStack(Warn.ANNOUNCE_LINES)
Warn.specialStack  = Warn.NewStack(Warn.SPECIAL_LINES)

-- CUSTOM WARNINGS. One entry per option key, not a stack: a Custom row has its OWN
-- place on screen, so a second occurrence of the same row replaces the first rather
-- than pushing it down a stack that does not exist.
Warn.customStacks = {}     -- optionKey -> entry

-- ══════════════════════════════════════════════════════════════════════════════
--  ROUTING (owner design item 1) — which bucket this warning goes to
-- ══════════════════════════════════════════════════════════════════════════════
function Warn.OptionKey(encId, row)
    return tostring(encId) .. ":" .. tostring(row and row.key)
end

-- `shipsOff` is false here on purpose: by the time a warning reaches this file the
-- engine's enable gate has already passed it (API.IsRowEnabled), so "the encounter
-- ships this off" is a question that has been answered.
function Warn.RouteOf(encId, row)
    local R = Addon.Route
    if not R then return (row and row.tier == "special") and "major" or "minor" end
    return R.Of(Warn.OptionKey(encId, row), R.DescribeWarning(row), false)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §5.2 NAME COLOURING — pure, over an injectable roster
-- ══════════════════════════════════════════════════════════════════════════════
-- Warnings that name players run every `>name<`-delimited token through a pass that
-- looks the name up in the roster, prefixes the raid-target icon texture when the
-- player carries one, class-colours the name, then restores the warning's own
-- colour, and strips the realm suffix — replacing it with a single `*` for
-- cross-realm players. A `noStrip ` marker opts an individual token out.
Warn.env = {
    RosterInfo = function() return nil end,   -- name -> { class=, mark=, realm=, crossRealm= }
    PlayerRealm = function() return nil end,
    UnitIsDeadOrGhost = function(u)
        local f = _G.UnitIsDeadOrGhost
        return type(f) == "function" and f(u) or false
    end,
}

function Warn:SetEnv(t)
    if type(t) ~= "table" then return end
    for k, v in pairs(t) do Warn.env[k] = v end
end

local CLASS_HEX = {
    WARRIOR = "c69b6d", PALADIN = "f48cba", HUNTER = "aad372", ROGUE = "fff468",
    PRIEST = "ffffff", SHAMAN = "0070dd", MAGE = "3fc7eb", WARLOCK = "8788ee",
    DRUID = "ff7c0a",
}
Warn.CLASS_HEX = CLASS_HEX

Warn.MARK_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"

function Warn.ColorOneName(raw, ownHex)
    -- `noStrip ` opts this individual token out of realm stripping entirely.
    local noStrip = false
    local name = raw
    if name:sub(1, 8) == "noStrip " then noStrip = true; name = name:sub(9) end

    local info = Warn.env.RosterInfo(name) or {}
    local shown = name
    if not noStrip then
        local base, realm = name:match("^(.-)%-(.+)$")
        if base then
            -- Same realm: drop the suffix entirely. Cross realm: a single `*`,
            -- which is shorter than the client's own "(*)" form.
            shown = info.crossRealm and (base .. "*") or base
        end
    end

    local hex = CLASS_HEX[info.class or ""]
    local out = hex and ("|cff" .. hex .. shown .. "|r") or shown
    if info.mark and info.mark >= 1 and info.mark <= 8 then
        out = ("|T" .. Warn.MARK_TEXTURE .. ":0|t"):format(info.mark) .. out
    end
    if ownHex then out = out .. ownHex end        -- restore the warning's own colour
    return out
end

function Warn.ColorNames(text, ownHex)
    if type(text) ~= "string" or not text:find(">", 1, true) then return text end
    return (text:gsub(">(.-)<", function(tok) return Warn.ColorOneName(tok, ownHex) end))
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §5.2 COMBINED + PRECISE SHOW — the two batchers, pure over the scheduler
-- ══════════════════════════════════════════════════════════════════════════════
Warn.batches = {}     -- key -> { names, seen, cap, debounce, tier, row, encId }

-- Format the accumulated list, honouring the cap and the overflow suffix.
-- §5.2: cap 7 for announcements, 6 for special warnings; "overflow becomes an
-- 'and N others' / 'and N more' suffix."
function Warn.FormatList(names, cap, special, sorted)
    local list = {}
    for i = 1, #names do list[i] = names[i] end
    if sorted then table.sort(list) end
    local shown, overflow = {}, 0
    for i = 1, #list do
        if i <= cap then shown[#shown + 1] = list[i] else overflow = overflow + 1 end
    end
    local body = table.concat(shown, ", ")
    if overflow > 0 then
        body = body .. (special and (" and %d more"):format(overflow)
                                or  (" and %d others"):format(overflow))
    end
    return body
end

local function flushBatch(key)
    local b = Warn.batches[key]
    if not b then return end
    Warn.batches[key] = nil
    local body = Warn.FormatList(b.names, b.cap, b.special, Warn.Settings().combineSort)
    local text = b.template and b.template:gsub("%%s", body) or body
    -- Through the router, not straight at a tier: a batched row the user routed to
    -- Major must arrive on the Major surface like an unbatched one does.
    Warn.Emit(b.encId, b.row, text)
end

-- §5.2 combined show: "arguments accumulate into a DE-DUPLICATED list ... and the
-- actual display is DEBOUNCED by a configurable delay (default 0.5 s), with EACH NEW
-- TARGET RESETTING the debounce."
function Warn.Combine(encId, row, target, opts)
    opts = opts or {}
    -- The cap and the overflow wording belong to the tier the list will ACTUALLY be
    -- shown in, which is the routed bucket, not the declared tier.
    local special = (Warn.RouteOf(encId, row) == "major")
    local key = tostring(encId) .. ":" .. tostring(row.key)
    local b = Warn.batches[key]
    if not b then
        b = { names = {}, seen = {}, encId = encId, row = row, special = special,
              template = row.text,
              cap = opts.cap or (special and Warn.COMBINE_CAP_SPECIAL or Warn.COMBINE_CAP_ANNOUNCE),
              debounce = opts.debounce or row.combine or Warn.COMBINE_DEBOUNCE }
        Warn.batches[key] = b
    end
    if target and not b.seen[target] then
        b.seen[target] = true
        b.names[#b.names + 1] = target
    end
    S():DelayedCall(b.debounce, flushBatch, Warn, key)
    return b
end

-- §5.2 precise show: "the caller declares the EXPECTED TOTAL; the warning fires
-- IMMEDIATELY once the accumulated count reaches that total OR reaches the number of
-- players currently alive in the player's own zone, with a 1.2 s scheduled fallback
-- if neither condition is met."
Warn.env.AliveInZone = function() return nil end

function Warn.Precise(encId, row, target, total)
    local key = tostring(encId) .. ":" .. tostring(row.key)
    local b = Warn.batches[key]
    if not b then
        local special = (Warn.RouteOf(encId, row) == "major")
        b = { names = {}, seen = {}, encId = encId, row = row,
              special = special, template = row.text,
              cap = special and Warn.COMBINE_CAP_SPECIAL or Warn.COMBINE_CAP_ANNOUNCE }
        Warn.batches[key] = b
        S():Schedule(Warn.PRECISE_FALLBACK, flushBatch, Warn, key)
    end
    if target and not b.seen[target] then
        b.seen[target] = true
        b.names[#b.names + 1] = target
    end
    local alive = Warn.env.AliveInZone()
    if (total and #b.names >= total) or (alive and #b.names >= alive) then
        S():Unschedule(flushBatch, Warn, key)
        flushBatch(key)
        return true
    end
    return false
end

-- ══════════════════════════════════════════════════════════════════════════════
--  SOUND + VOICE DISPATCH (§5.5) — through the existing soundpacks machinery
-- ══════════════════════════════════════════════════════════════════════════════
-- The user's per-row custom sound, if any. This is what "a user-selected custom
-- sound file always wins over the voice pack" reads.
function Warn.RowSoundKey(encId, row)
    local db = Addon.db
    if db and type(db.mechanics) == "table" then
        local o = db.mechanics[tostring(encId) .. ":" .. tostring(row.key)]
        if o and o.sound and o.sound ~= "none" then return o.sound, true end
    end
    local tier = Warn.SOUND_TIER[row.sound or 1] or Warn.SOUND_TIER[1]
    return tier.sound, false
end

-- §5.5 graceful degradation: "each warning object declares the pack version its
-- chosen voice line was introduced in, and a line only plays if
-- objectRequiredVersion <= installedVersion. Out-of-date packs therefore degrade
-- LINE BY LINE instead of failing wholesale."
function Warn.VoiceAllowed(row)
    local s = Warn.Settings()
    if not s.voiceEnabled then return false end
    if not row.voice then return false end
    local required = row.voiceVersion or 1
    return required <= (s.voicePackVersion or Warn.VOICE_MIN_VERSION)
end

-- Returns what was played: "voice" | "sound" | nil. The decision table is the whole
-- of §5.5's replacement rules, in one place, so it can be asserted as a table.
function Warn.DispatchSound(encId, row, special)
    local s = Warn.Settings()
    if special and s.suppressSpecialSound then return nil end
    local voiceOk = Warn.VoiceAllowed(row)
    local key, custom = Warn.RowSoundKey(encId, row)
    if voiceOk then
        if not special and s.voiceReplacesAnnounce then
            if Addon:PlayVoiceLine(row.voice) then return "voice" end
        elseif special and s.voiceReplacesSpecialSound
               and not custom and Warn.BUILTIN_TIERS[row.sound or 1] then
            if Addon:PlayVoiceLine(row.voice) then return "voice" end
        end
    end
    if key and key ~= "none" then
        Addon:PlaySoundByKey(key, special and true or false)
        return "sound"
    end
    return nil
end

-- ══════════════════════════════════════════════════════════════════════════════
--  VIEW — two anchored stacks + the tiered screen flash
-- ══════════════════════════════════════════════════════════════════════════════
local View = {}
Warn.View = View
View.ready = nil
View.lines = { announce = {}, special = {} }
View.anchors = {}
View.acc = 0

function View.CanDraw()
    if View.ready ~= nil then return View.ready end
    if type(_G.CreateFrame) ~= "function" then View.ready = false; return false end
    local f = _G.CreateFrame("Frame", nil, _G.UIParent)
    View.ready = (type(f) == "table" and type(f.CreateFontString) == "function"
                  and type(f.CreateTexture) == "function") and true or false
    return View.ready
end

Warn.ANCHOR_LABEL = {
    [Warn.ANCHOR_ANNOUNCE] = "Announcements \226\128\148 Minor",
    [Warn.ANCHOR_SPECIAL]  = "Special warnings \226\128\148 Major",
}

local function anchorFrame(key)
    local a = View.anchors[key]
    if a then return a end
    a = Addon:HudAnchor(key, Warn.ANCHOR_LABEL[key], Warn.DEFAULT_POS[key], 260, 22)
    View.anchors[key] = a
    return a
end

-- A Custom warning's own anchor — the identical machinery the two tier anchors use,
-- so it drags the same way and answers to the same attach-to resolver.
function Warn.RowAnchor(key, label)
    if not key or not View.CanDraw() then return nil end
    local existing = Addon._hudAnchors and Addon._hudAnchors[key]
    if existing then return existing end
    return Addon:HudAnchor(key, label or key, Warn.CUSTOM_DEFAULT_POS, 260, 22)
end

function Warn.EnsureAnchors()
    if not View.CanDraw() then return 0 end
    anchorFrame(Warn.ANCHOR_ANNOUNCE)
    anchorFrame(Warn.ANCHOR_SPECIAL)
    return 2
end

-- One line frame. Tier 2 takes the suite body face at the announce point size;
-- tier 3 keeps a THICKOUTLINE at the special point size, because that outline and
-- that size are exactly why a special warning reads across a 40-man raid — the
-- suite picker supplies the FACE only (Addon:ReFaceKeepingSize).
local function newLine(which)
    local s = Warn.Settings()
    local f = _G.CreateFrame("Frame", nil, _G.UIParent)
    local size = (which == "special") and (s.specialFont or Warn.SPECIAL_FONT)
                                     or  (s.announceFont or Warn.ANNOUNCE_FONT)
    f:SetSize(700, size + 8)
    f:SetFrameStrata("HIGH")
    f.text = f:CreateFontString(nil, "OVERLAY",
        which == "special" and "GameFontNormalHuge" or "GameFontNormalLarge")
    f.text:SetPoint("CENTER")                    -- DREW_UI_STYLE principle 3: centred
    f.text:SetJustifyH("CENTER")
    Addon:ReFaceKeepingSize(f.text)
    local path = f.text:GetFont()
    f.text:SetFont(path, size, which == "special" and "THICKOUTLINE" or "OUTLINE")
    f:Hide()
    return f
end

local function lineFrame(which, i)
    local list = View.lines[which]
    local f = list[i]
    if not f then f = newLine(which); list[i] = f end
    return f
end

local function drawStack(which, stack, anchorKey, now)
    local s = Warn.Settings()
    local a = anchorFrame(anchorKey)
    local pad = s.pad or 4
    local size = (which == "special") and (s.specialFont or Warn.SPECIAL_FONT)
                                     or  (s.announceFont or Warn.ANNOUNCE_FONT)
    local step = size + 8 + pad
    local shown = 0
    for i = 1, stack.lines do
        local f = lineFrame(which, i)
        local e = stack.slots[i]
        if e then
            f:ClearAllPoints()
            -- Line 1 is the TOP line; the stack grows downward from the anchor with
            -- one pad between lines and no dead band above line 1.
            f:SetPoint("TOP", a, "TOP", 0, -(i - 1) * step)
            f:SetSize(700, size + 8)
            f.text:SetText(e.text or "")
            f.text:SetTextColor(e.r, e.g, e.b)
            f.text:SetScale(Warn.PopScale(e, now))
            f:SetAlpha(Warn.Alpha(e, now))
            f:Show()
            shown = shown + 1
        else
            f:Hide()
        end
    end
    return shown
end

-- The Custom bucket. Each entry has its own anchor and its own size multiplier; it
-- keeps the face of the tier the encounter declared, because Custom is a decision
-- about WHERE a warning appears, not about how loud it is.
View.customLines = {}      -- optionKey -> line frame

local function drawCustom(now)
    local shown = 0
    for key, e in pairs(Warn.customStacks) do
        local dead = (now - e.at) >= (e.duration + e.duration * Warn.FADE_FRACTION)
        local f = View.customLines[key]
        if dead then
            Warn.customStacks[key] = nil
            if f then f:Hide() end
        else
            if not f then f = newLine(e.which); View.customLines[key] = f end
            local s = Warn.Settings()
            local size = (e.which == "special") and (s.specialFont or Warn.SPECIAL_FONT)
                                                or  (s.announceFont or Warn.ANNOUNCE_FONT)
            local a = Warn.RowAnchor(key, e.label)
            f:ClearAllPoints()
            if a then
                f:SetPoint("CENTER", a, "CENTER", 0, 0)
            elseif Addon.Anchors then
                Addon.Anchors.Place(key, f, Warn.CUSTOM_DEFAULT_POS)
            end
            f:SetSize(700, size + 8)               -- BOTH dimensions, every arrange
            local k = Addon.Anchors and Addon.Anchors.GetSize(key) or 1
            f.text:SetText(e.text or "")
            f.text:SetTextColor(e.r, e.g, e.b)
            f.text:SetScale(Warn.PopScale(e, now) * k)
            f:SetAlpha(Warn.Alpha(e, now))
            f:Show()
            shown = shown + 1
        end
    end
    return shown
end

function Warn.CustomCount()
    local n = 0
    for _ in pairs(Warn.customStacks) do n = n + 1 end
    return n
end

function View.Refresh(now)
    if not View.CanDraw() then return 0 end
    Warn.announceStack:Prune(now)
    Warn.specialStack:Prune(now)
    local n = drawStack("announce", Warn.announceStack, Warn.ANCHOR_ANNOUNCE, now)
            + drawStack("special",  Warn.specialStack,  Warn.ANCHOR_SPECIAL,  now)
            + drawCustom(now)
    return n
end

-- §5.1's 0.05 s ticker, riding the engine scheduler like the bar surface does.
function View.OnUpdate(elapsed, now)
    View.acc = View.acc + (elapsed or 0)
    if View.acc < Warn.TICK then return false end
    View.acc = 0
    View.Refresh(now)
    if Warn.announceStack:Count() == 0 and Warn.specialStack:Count() == 0
       and Warn.CustomCount() == 0 then View.Sleep() end
    return true
end

-- Same rule as the bar surface: the scheduler is the source of truth about whether
-- this surface is being driven, so a Flush cannot strand it.
function View.Wake()
    if S().updaters[Warn] then return end
    S():RegisterUpdate(Warn, 0, function(_, elapsed) View.OnUpdate(elapsed, S():Now()) end)
end

function View.Sleep()
    S():UnregisterUpdate(Warn)
end

-- ── The tiered screen flash (§5.1) ────────────────────────────────────────────
local flashFrame

function Warn.Flash(tier, now)
    local s = Warn.Settings()
    if s.suppressSpecialFlash then return false end
    -- §5.1: "Flashes are suppressed entirely while the player is dead or a ghost."
    if Warn.env.UnitIsDeadOrGhost("player") then return false end
    local cfg = Warn.SOUND_TIER[tier or 1] or Warn.SOUND_TIER[1]
    if not View.CanDraw() then return true end          -- headless: the decision stands
    if not flashFrame then
        local f = _G.CreateFrame("Frame", nil, _G.UIParent)
        f:SetAllPoints(_G.UIParent)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(false)
        if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
        f.tex = f:CreateTexture(nil, "BACKGROUND")
        f.tex:SetAllPoints(f)
        f.tex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
        f.tex:SetBlendMode("ADD")
        f:SetScript("OnUpdate", function(self, elapsed)
            self._e = (self._e or 0) + elapsed
            local cycle = self._duration or 0.4
            if self._e >= cycle then
                self._left = (self._left or 1) - 1
                self._e = 0
                if self._left <= 0 then self:Hide(); return end
            end
            local k = (self._e < cycle * 0.5) and (self._e / (cycle * 0.5))
                                              or  (1 - (self._e - cycle * 0.5) / (cycle * 0.5))
            self:SetAlpha(k * (self._peak or 0.25))
        end)
        f:Hide()
        flashFrame = f
    end
    flashFrame.tex:SetVertexColor(Addon:FlashColor(tier))
    flashFrame._e, flashFrame._left = 0, cfg.flashRepeat
    flashFrame._duration, flashFrame._peak = cfg.flashDuration, cfg.flashAlpha
    flashFrame:SetAlpha(0)
    flashFrame:Show()
    return true
end

-- §5.1's controller vibration, gated by its own suppressor and the tier default.
function Warn.Vibrate(tier)
    local s = Warn.Settings()
    if s.suppressVibration then return false end
    local cfg = Warn.SOUND_TIER[tier or 1] or Warn.SOUND_TIER[1]
    if not cfg.vibrate then return false end
    local f = _G.C_GamePad and _G.C_GamePad.SetVibration
    if type(f) == "function" then f("High", 1) end
    return true
end

-- ══════════════════════════════════════════════════════════════════════════════
--  SHOW PATHS
-- ══════════════════════════════════════════════════════════════════════════════
local function hexOf(r, g, b)
    local function c(v) return math.max(0, math.min(255, math.floor((v or 0) * 255 + 0.5))) end
    return ("|cff%02x%02x%02x"):format(c(r), c(g), c(b))
end

function Warn.MirrorToChat(text)
    if not Warn.Settings().mirrorToChat then return false end
    -- §5.1 "optional mirror to a chat frame (with TEXTURES STRIPPED unless the user
    -- wants them)" — the raid-icon textures a coloured name carries are unreadable
    -- in a chat log, so they come out by default.
    local clean = tostring(text):gsub("|T.-|t", "")
    if type(print) == "function" then print(Addon:Tag("[DRM]") .. " " .. clean) end
    return true
end

function Warn.ShowAnnounce(encId, row, text, now)
    local s = Warn.Settings()
    if s.hideWarnings then return nil end
    if s.suppressBossAnnounce and not (row and row.userTimer) then return nil end
    if s.suppressTargetAnnounce and row and row.generic then return nil end
    now = now or S():Now()
    local slot = row and row.color or 2
    local r, g, b = Addon:WarnColor(slot)
    local body = Warn.ColorNames(text, hexOf(r, g, b))
    local idx = Warn.announceStack:Push({ text = body, r = r, g = g, b = b,
                                          duration = row and row.duration or Warn.DURATION,
                                          key = row and row.key }, now)
    Warn.DispatchSound(encId, row or {}, false)
    Warn.MirrorToChat(body)
    View.Wake()
    View.Refresh(now)
    return idx, body
end

function Warn.ShowSpecial(encId, row, text, now)
    local s = Warn.Settings()
    if s.hideWarnings then return nil end
    -- §5.4's CPU short-circuit, at the very top of the show path.
    if Warn.SpecialFullySuppressed() then return nil end
    now = now or S():Now()
    local tier = (row and row.sound) or 1
    local st = Addon.Theme.specialText
    local r, g, b = st[1], st[2], st[3]
    local body = Warn.ColorNames(text, hexOf(r, g, b))
    local idx
    if not s.suppressSpecialText then
        idx = Warn.specialStack:Push({ text = body, r = r, g = g, b = b,
                                       duration = row and row.duration or Warn.DURATION,
                                       key = row and row.key }, now)
        View.Wake()
        View.Refresh(now)
    end
    Warn.DispatchSound(encId, row or {}, true)
    Warn.Flash(tier, now)
    Warn.Vibrate(tier)
    Warn.MirrorToChat(body)
    return idx, body
end

-- A CUSTOM WARNING: the row's own place on screen, its own size, and the tier
-- treatment the encounter declared. It is deliberately NOT a stack — a Custom row
-- owns one spot, so a second occurrence replaces the first.
function Warn.ShowCustom(encId, row, text, now)
    local s = Warn.Settings()
    if s.hideWarnings then return nil end
    row = row or {}
    local special = (row.tier == "special")
    if special and Warn.SpecialFullySuppressed() then return nil end
    now = now or S():Now()

    local r, g, b
    if special then
        local st = Addon.Theme.specialText
        r, g, b = st[1], st[2], st[3]
    else
        r, g, b = Addon:WarnColor(row.color or 2)
    end
    local body = Warn.ColorNames(text, hexOf(r, g, b))
    local key  = Warn.OptionKey(encId, row)

    if not (special and s.suppressSpecialText) then
        Warn.customStacks[key] = {
            text = body, r = r, g = g, b = b, at = now,
            duration = row.duration or Warn.DURATION,
            which = special and "special" or "announce",
            label = row.name or row.text or row.key or key,
            key = key,
        }
        View.Wake()
        View.Refresh(now)
    end
    Warn.DispatchSound(encId, row, special)
    if special then
        Warn.Flash(row.sound or 1, now)
        Warn.Vibrate(row.sound or 1)
    end
    Warn.MirrorToChat(body)
    return key, body
end

-- THE ROUTER (owner design item 1). Every warning that reaches a surface goes
-- through here, batched or not.
--
-- HIDDEN IS NOT MUTE. A hidden row still plays its sound and its voice line: the
-- raider who picks Hidden is the one who wants the cue without the clutter, and
-- silencing them as well is what the three global suppressors are for.
function Warn.Emit(encId, row, text, now)
    row = row or {}
    local bucket = Warn.RouteOf(encId, row)
    if bucket == "hidden" then
        Warn.DispatchSound(encId, row, row.tier == "special")
        return nil, nil, "hidden"
    end
    if bucket == "custom" then
        local idx, body = Warn.ShowCustom(encId, row, text, now)
        return idx, body, "custom"
    end
    if bucket == "major" then
        local idx, body = Warn.ShowSpecial(encId, row, text, now)
        return idx, body, "major"
    end
    local idx, body = Warn.ShowAnnounce(encId, row, text, now)
    return idx, body, "minor"
end

-- ══════════════════════════════════════════════════════════════════════════════
--  ENGINE SEAM
-- ══════════════════════════════════════════════════════════════════════════════
-- The engine has already applied ship-off defaults, role gates and class defaults
-- (core_api API.IsRowEnabled). A row that declares batching is routed into the
-- batchers; everything else shows immediately.
-- W4d added the 4th payload argument: the player the warning is ABOUT, resolved from
-- the event by the engine. Before it, a batched row could only ever list a STATIC
-- `row.target`, so "Web Wrap on <name>" / "Frost Blast on <names>" had no names to
-- collect. A row that still declares a static target keeps it as the fallback.
local function onAnnounce(_, encId, row, text, target)
    row = row or {}
    target = target or row.target
    if row.combine then return Warn.Combine(encId, row, target, nil) end
    if row.precise then return Warn.Precise(encId, row, target, row.precise.total) end
    return Warn.Emit(encId, row, text)
end

local function onSpecial(_, encId, row, text, target)
    row = row or {}
    target = target or row.target
    if row.combine then return Warn.Combine(encId, row, target, nil) end
    if row.precise then return Warn.Precise(encId, row, target, row.precise.total) end
    return Warn.Emit(encId, row, text)
end

function Warn.Init()
    if Warn._inited then return end
    Warn._inited = true
    Addon:RegisterEngineCallback("WARN_ANNOUNCE", onAnnounce, Warn)
    Addon:RegisterEngineCallback("WARN_SPECIAL",  onSpecial,  Warn)
    return true
end

function Warn.Reset()
    Warn.announceStack:Clear()
    Warn.specialStack:Clear()
    for k in pairs(Warn.customStacks) do
        Warn.customStacks[k] = nil
        local f = View.customLines[k]
        if f then f:Hide() end
    end
    for k in pairs(Warn.batches) do Warn.batches[k] = nil end
end

-- §11.7 demo mode: one line of every announce colour and one of every sound tier,
-- out of combat, so the two anchors can be placed without a boss.
function Warn.Demo()
    local n = 0
    for slot = 1, 4 do
        Warn.ShowAnnounce("demo", { key = "demo" .. slot, color = slot },
                          ("Announcement colour %d"):format(slot))
        n = n + 1
    end
    for tier = 1, 5 do
        Warn.ShowSpecial("demo", { key = "demospecial" .. tier, sound = tier, tier = "special" },
                         ("Special warning - %s"):format(Warn.SOUND_TIER[tier].label))
        n = n + 1
    end
    return n
end

return Warn
