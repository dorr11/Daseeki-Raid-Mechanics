--[[
    Module — Razuvious Understudy Nameplate Icons (ported from WeakAura
    "Razuvious Understudy Buff/Debuff Nameplate Icons").

    Attaches an icon to each understudy's NAMEPLATE showing the "Mind Exhaustion"
    debuff countdown (when an understudy can be mind-controlled again) — hidden
    while that understudy has "Shield Wall" up. Mirrors the WA's trigger logic
    (show when Mind Exhaustion present AND Shield Wall absent).

    Names are matched by aura name like the WA (enUS: "Mind Exhaustion" /
    "Shield Wall"); adjust below if your locale differs.
--]]

local _, Addon = ...

local MODID      = "razuvious_understudy"
local EXHAUST    = "Mind Exhaustion"
local SHIELDWALL = "Shield Wall"

local plates = {}   -- unit token -> icon frame
local pool   = {}
local ev

local function FindAura(unit, name, filter)
    for i = 1, 40 do
        local n, icon, count, _, duration, expiration = UnitAura(unit, i, filter)
        if not n then break end
        if n == name then return icon, count, duration, expiration end
    end
end

local function AcquireIcon()
    local f = table.remove(pool)
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(30, 30); f:SetFrameStrata("HIGH")
    f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetAllPoints(); f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Addon:AddIconBorder(f.icon, f)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
    f.cd.noCooldownCount = true
    f.timer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Addon:TrySetFont(f.timer, "numeral")   -- icon countdown → telemetry numeral
    f.timer:SetPoint("CENTER")
    f:SetScript("OnUpdate", function(self)
        if not self._expire then self.timer:SetText(""); return end
        local rem = self._expire - GetTime()
        if rem <= 0 then self.timer:SetText("") else self.timer:SetText(string.format("%d", math.ceil(rem))) end
    end)
    return f
end

local function Release(unit)
    local f = plates[unit]
    if f then f:Hide(); f:SetParent(UIParent); f._expire = nil; plates[unit] = nil; pool[#pool + 1] = f end
end

local function Update(unit)
    if not unit then return end
    local hasSW = FindAura(unit, SHIELDWALL, "HELPFUL")
    local icon, _, duration, expiration
    if not hasSW then icon, _, duration, expiration = FindAura(unit, EXHAUST, "HARMFUL") end

    if icon then
        local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
        if not np then Release(unit); return end
        local f = plates[unit] or AcquireIcon()
        plates[unit] = f
        f:SetParent(np); f:ClearAllPoints(); f:SetPoint("BOTTOM", np, "TOP", 0, 6)
        f.icon:SetTexture(icon)
        if duration and duration > 0 then
            f.cd:SetCooldown(expiration - duration, duration); f._expire = expiration
        else
            f.cd:SetCooldown(0, 0); f._expire = nil
        end
        f:Show()
    else
        Release(unit)
    end
end

Addon:RegisterModule({
    id = MODID, raidId = "naxxramas", bossId = "razuvious",
    name = "Understudy Nameplate Icons (WA)",
    desc = "Shows each understudy's Mind Exhaustion countdown on their nameplate (hidden while they have Shield Wall) — i.e. when they can be re-controlled. Requires enemy nameplates enabled.",
    defaults = { enabled = false },

    Start = function()
        ev = ev or CreateFrame("Frame")
        ev:SetScript("OnEvent", function(_, event, unit)
            if event == "NAME_PLATE_UNIT_ADDED" then
                Update(unit)
            elseif event == "NAME_PLATE_UNIT_REMOVED" then
                Release(unit)
            elseif event == "UNIT_AURA" then
                if unit and tostring(unit):find("nameplate") then Update(unit) end
            end
        end)
        ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        ev:RegisterEvent("UNIT_AURA")
        -- catch nameplates that already exist
        if C_NamePlate and C_NamePlate.GetNamePlates then
            for _, np in ipairs(C_NamePlate.GetNamePlates()) do
                if np.namePlateUnitToken then Update(np.namePlateUnitToken) end
            end
        end
    end,

    Stop = function()
        if ev then ev:UnregisterAllEvents(); ev:SetScript("OnEvent", nil) end
        for unit in pairs(plates) do Release(unit) end
        wipe(plates)
    end,

    Test = function()
        -- Nameplate attach can't be previewed off a real unit; show a sample icon
        -- at screen center for ~4s so you can confirm the look.
        local f = AcquireIcon()
        f:SetParent(UIParent); f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        f.icon:SetTexture("Interface\\Icons\\Spell_Shadow_Teleport")
        f.cd:SetCooldown(GetTime(), 8); f._expire = GetTime() + 8
        f:Show()
        C_Timer.After(8, function() f:Hide(); f._expire = nil; pool[#pool + 1] = f end)
    end,
})
