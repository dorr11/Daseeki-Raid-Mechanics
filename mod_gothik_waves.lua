--[[
    Module — Gothik Wave Tracker

    Gothik's Phase 1 is a SCRIPTED, fixed-schedule sequence of 18 add waves (not a
    simple repeating interval), ending when Phase 2 begins (~270s after pull, when
    Gothik leaves the balcony and the gate between the two sides opens). This module
    tracks that schedule independently of the generic mechanic system since each wave
    fires at its own specific time with its own mob composition.

    Shows a small persistent widget (current wave + composition, countdown to the next
    wave, and a Phase 2 countdown), plus a "Wave N incoming" text banner ~3s before each
    wave and a "Wave N: <composition>" banner the moment it spawns.
--]]

local _, Addon = ...

local MODID = "gothik_waves"
local KEY   = "naxxramas:gothik:wavetracker_mod"
local SOON_KEY, NOW_KEY = "naxxramas:gothik:wavesoon", "naxxramas:gothik:wavenow"
local SOON_LEAD = 3

-- Fixed wave schedule: `t` = seconds after pull the wave SPAWNS (cumulative from the
-- per-wave gaps), `text` = that wave's composition.
local WAVES = {
    { t = 27,  text = "3 Trainees" },
    { t = 47,  text = "3 Trainees" },
    { t = 67,  text = "3 Trainees" },
    { t = 77,  text = "2 Knights" },
    { t = 87,  text = "3 Trainees" },
    { t = 102, text = "2 Knights" },
    { t = 107, text = "3 Trainees" },
    { t = 127, text = "2 Knights + 3 Trainees" },
    { t = 137, text = "1 Rider" },
    { t = 147, text = "3 Trainees" },
    { t = 152, text = "2 Knights" },
    { t = 167, text = "1 Rider + 3 Trainees" },
    { t = 177, text = "2 Knights" },
    { t = 187, text = "3 Trainees" },
    { t = 197, text = "1 Rider" },
    { t = 202, text = "2 Knights" },
    { t = 207, text = "3 Trainees" },
    { t = 227, text = "1 Rider + 2 Knights + 3 Trainees" },
}
local PHASE2_T = 270

local frame, timers
local startTime

local function cfg() return Addon:GetModuleConfig(MODID) end

local function Position(c)
    local pos = Addon:GetAnchorPos(KEY)
    c:ClearAllPoints()
    c:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
end
local function ApplyCfg(c)
    c:SetScale(cfg().scale or 1); c:SetAlpha(cfg().opacity or 1)
end

local function CurrentWaveIndex(elapsed)
    local idx = 0
    for i, w in ipairs(WAVES) do
        if elapsed >= w.t then idx = i else break end
    end
    return idx
end

local function Refresh(c)
    local elapsed = startTime and (GetTime() - startTime) or 0
    local idx = CurrentWaveIndex(elapsed)
    if idx > 0 then
        c.wave:SetText(string.format("Wave %d/%d: %s", idx, #WAVES, WAVES[idx].text))
    else
        c.wave:SetText("Wave: --")
    end
    if idx < #WAVES then
        local nw = WAVES[idx + 1]
        c.next:SetText(string.format("Next (Wave %d) in %ds", idx + 1, math.ceil(math.max(0, nw.t - elapsed))))
    else
        c.next:SetText("All waves spawned")
    end
    local p2rem = PHASE2_T - elapsed
    if p2rem > 0 then
        c.phase2:SetText(string.format("Phase 2 in %ds", math.ceil(p2rem)))
    else
        c.phase2:SetText("|cff66ff66Phase 2 active|r")
    end
end

local function EnsureFrame()
    if frame then return frame end
    local c = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    c:SetSize(200, 76); c:SetFrameStrata("MEDIUM")
    c:SetMovable(true); c:EnableMouse(true)
    Addon:ApplyDarkBackdrop(c)
    c.header = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Addon:TrySetFont(c.header, "microLabel")   -- widget eyebrow (§3)
    -- Addon:Wrap resolves the brand token with Core and the legacy cyan without.
    c.header:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -4); c.header:SetText(Addon:Wrap("brand", "Gothik Waves"))
    c.wave = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.wave:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -22); c.wave:SetJustifyH("LEFT")
    c.next = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.next:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -42)
    c.phase2 = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.phase2:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -58)
    -- Suite face first, tint after. The two sub-lines pass the Theme FIELD NAME so the
    -- muted role keeps following the active suite theme (was a literal table).
    Addon:TrySetFont(c.wave, "body")
    Addon:TrySetFont(c.next, "small"); Addon:TrySetFont(c.phase2, "small")
    Addon:StyleFont(c.wave); Addon:StyleFont(c.next, "subText"); Addon:StyleFont(c.phase2, "subText")
    c:SetScript("OnMouseDown", function(self, b) if b == "LeftButton" then self:StartMoving() end end)
    c:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        Addon:SetMechanicPos(KEY, p, rp, x, y)
    end)
    c:SetScript("OnUpdate", function(self, el)
        self._acc = (self._acc or 0) + el
        if self._acc < 0.2 then return end
        self._acc = 0
        Refresh(self)
    end)
    frame = c
    return c
end

-- Schedules the "Wave N incoming" / "Wave N: composition" text banners + Phase 2
-- banner, all relative to `startTime`. Independent of the persistent widget above.
local function CancelTimers()
    if not timers then return end
    for _, t in ipairs(timers) do if t.Cancel then t:Cancel() end end
    wipe(timers)
end

local function ScheduleAlerts()
    timers = timers or {}
    CancelTimers()
    for i, w in ipairs(WAVES) do
        local soonAt = w.t - SOON_LEAD
        if soonAt > 0 then
            timers[#timers + 1] = C_Timer.NewTimer(soonAt, function()
                if cfg().soonEnabled == false then return end
                Addon:ShowWarning(SOON_KEY, string.format("Wave %d Incoming \226\128\148 %s", i, w.text),
                    { 1, 0.85, 0.2 }, Addon.DEFAULT_TOP_POS)
                if cfg().sound ~= false then Addon:PlaySoundByKey(cfg().soundKey or "raidwarning", true) end
            end)
        end
        timers[#timers + 1] = C_Timer.NewTimer(w.t, function()
            if cfg().nowEnabled == false then return end
            Addon:ShowWarning(NOW_KEY, string.format("Wave %d: %s", i, w.text),
                { 1, 0.3, 0.3 }, Addon.DEFAULT_TOP_POS)
            if cfg().sound ~= false then Addon:PlaySoundByKey(cfg().soundKey or "raidwarning", true) end
        end)
    end
    timers[#timers + 1] = C_Timer.NewTimer(PHASE2_T, function()
        if cfg().nowEnabled == false then return end
        Addon:ShowWarning(NOW_KEY, "Phase 2 \226\128\148 Gothik Engaging!", { 0.6, 0.6, 1 }, Addon.DEFAULT_TOP_POS)
    end)
end

local function Show(asPreview)
    if asPreview then
        startTime = GetTime() - 5   -- a few seconds into the schedule, for a meaningful preview
    elseif not startTime then
        startTime = GetTime()
    end
    EnsureFrame(); Position(frame); ApplyCfg(frame); Refresh(frame); frame:Show()
end

Addon:RegisterModule({
    id = MODID, raidId = "naxxramas", bossId = "gothik",
    name = "Wave Tracker",
    desc = "Tracks Gothik's scripted 18-wave add schedule before Phase 2: a countdown widget (current wave, next wave, Phase 2 timer) plus 'incoming'/'spawned' text banners naming each wave's composition. Drag the widget header to move.",
    -- Default ON for DBM parity (the wave schedule above is DBM-verified). Existing
    -- characters with a saved enabled=false keep their setting; this is fresh-profile only.
    defaults = { enabled = true },

    -- 2.0 placement seam (modules.lua). Metadata only — the widget, its logic and
    -- its own drag handler are untouched; the anchor system simply owns where it
    -- sits from here on, docked to the Specials anchor unless detached.
    placeKey   = KEY,
    placeLabel = "Gothik wave tracker",
    placeFrame = function() return frame end,

    Start = function()
        startTime = GetTime()
        Show(false)
        ScheduleAlerts()
    end,
    Stop = function()
        CancelTimers()
        startTime = nil
        if frame then frame:Hide() end
    end,
    Test = function()
        if frame and frame:IsShown() then frame:Hide() else Show(true) end
    end,
    SetPreview = function(_, on)
        if on then Show(true) elseif frame then frame:Hide() end
    end,

    BuildConfig = function(_, parent)
        local DS = _G.DaseekiSuite
        DS.MakeSlider(parent, 6, 24, 150, "Scale", 0.5, 2.0, 0.05,
            function() return cfg().scale or 1 end,
            function(v) cfg().scale = v; if frame then frame:SetScale(v) end end,
            function(v) return string.format("%.2f", v) end)
        DS.MakeSlider(parent, 6, 70, 150, "Opacity", 0.1, 1.0, 0.05,
            function() return cfg().opacity or 1 end,
            function(v) cfg().opacity = v; if frame then frame:SetAlpha(v) end end,
            function(v) return string.format("%.2f", v) end)
        DS.MakeCheckbox(parent, "\"Wave Soon\" text banner", 6, 104,
            function() return cfg().soonEnabled ~= false end,
            function(v) cfg().soonEnabled = v and true or false end)
        DS.MakeCheckbox(parent, "\"Wave Spawned\" text banner", 6, 130,
            function() return cfg().nowEnabled ~= false end,
            function(v) cfg().nowEnabled = v and true or false end)
        DS.MakeCheckbox(parent, "Play sound with each banner", 6, 156,
            function() return cfg().sound ~= false end,
            function(v) cfg().sound = v and true or false end)
        DS.MakeLabel(parent, "Sound", nil, 6, 186)
        local sb
        sb = DS.MakeButton(parent, "None", 92, 182, 130, 22, function()
            Addon:ShowSoundPicker(cfg().soundKey or "raidwarning", function(key)
                cfg().soundKey = key; sb:SetText(Addon:GetSoundName(key))
            end, sb)
        end)
        sb:SetText(Addon:GetSoundName(cfg().soundKey or "raidwarning"))
    end,
})
