--[[
    Module — Razuvious Taunt Warner (ported from WeakAura "Razuvious Taunt Warner")

    Warrior understudy-control helper. Tracks spell 29060's ~20s cooldown vs
    Instructor Razuvious: on each cast a 20s icon countdown runs, glowing + turning
    the timer red in the last 5s (taunt almost ready). Self-contained frame anchored
    at a placeable position.
--]]

local _, Addon = ...

local KEY      = "naxxramas:razuvious:taunt_mod"
local SPELL    = 29060
local DURATION = 20
local GLOW_AT  = 5

local frame, ev

local function Position(f)
    local pos = Addon:GetAnchorPos(KEY)
    f:ClearAllPoints()
    f:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
end

local function EnsureFrame()
    if frame then return frame end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(48, 48)
    f:SetFrameStrata("HIGH")

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints(); f.icon:SetTexture(136080); f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Addon:AddIconBorder(f.icon, f)

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
    f.cd.noCooldownCount = true

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.text:SetPoint("CENTER")

    f.glow = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.glow:SetPoint("TOPLEFT", f, "TOPLEFT", -4, 4)
    f.glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -4)
    f.glow:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
    f.glow:SetBackdropBorderColor(1, 0, 0, 1)
    f.glow:Hide()

    f:SetScript("OnUpdate", function(self)
        local rem = (self._end or 0) - GetTime()
        if rem <= 0 then self:Hide(); return end
        self.text:SetText(rem >= 10 and string.format("%d", rem) or string.format("%.1f", rem))
        if rem <= GLOW_AT then
            self.glow:Show(); self.text:SetTextColor(1, 0.2, 0.2)
        else
            self.glow:Hide(); self.text:SetTextColor(1, 1, 1)
        end
    end)
    f:Hide()
    frame = f
    return f
end

local function StartTimer()
    local f = EnsureFrame()
    Position(f)
    f._end = GetTime() + DURATION
    f.cd:SetCooldown(GetTime(), DURATION)
    f.glow:Hide()
    f:Show()
end

Addon:RegisterModule({
    id = "razuvious_taunt", raidId = "naxxramas", bossId = "razuvious",
    name = "Taunt Warner (WA)",
    desc = "Tracks spell 29060's ~20s cooldown vs Razuvious; the icon glows and the timer turns red in the last 5s. (Warrior understudy-control helper.)",
    defaults = { enabled = false },
    placeKey = KEY, placeDef = { name = "Taunt Warner", icon = 136080, style = "icon" },

    Start = function()
        ev = ev or CreateFrame("Frame")
        ev:SetScript("OnEvent", function()
            local _, sub, _, _, _, _, _, _, _, _, _, spellID = CombatLogGetCurrentEventInfo()
            if sub == "SPELL_CAST_SUCCESS" and spellID == SPELL then StartTimer() end
        end)
        ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end,

    Stop = function()
        if ev then ev:UnregisterAllEvents(); ev:SetScript("OnEvent", nil) end
        if frame then frame:Hide() end
    end,

    Test = function() StartTimer() end,
})
