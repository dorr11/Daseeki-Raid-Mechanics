--[[
    Daseeki Raid Mechanics — Thaddius-specific features

    1) Mini-Boss Health module: a draggable widget showing Stalagg (15929) +
       Feugen (15930) health (the adds you fight before Thaddius, same encounter).
       Scalable/opacity-adjustable like other items.

    2) Polarity-change watcher: a sub-option of the Polarity Shift mechanic. Monitors
       the player's charge debuff (by icon, like DBM: 135768 = Negative, 135769 =
       Positive) and fires a sound and/or center-screen text only when it FLIPS
       (neg<->pos), not on refresh. Config lives in db.mechanics[<polarity key>].
--]]

local _, Addon = ...

-- ════════════════════════════════════════════════════════════════════════════
-- 1) Mini-Boss Health module
-- ════════════════════════════════════════════════════════════════════════════
local MH_ID  = "thaddius_minihealth"
local MH_KEY = "naxxramas:thaddius:minihealth_mod"
local UNITS  = { { id = 15929, name = "Stalagg" }, { id = 15930, name = "Feugen" } }

local mh, mhEv
local hp = {}        -- npcID -> fraction (0-1)
local deadAdds = {}  -- npcID -> true (Stalagg/Feugen); both dead -> hide widget

local function mhCfg() return Addon:GetModuleConfig(MH_ID) end

local function npcOf(unit)
    local guid = UnitGUID(unit); if not guid then return nil end
    local _, _, _, _, _, id = strsplit("-", guid)
    return tonumber(id)
end

local function ScanHealth()
    local function check(unit)
        if not UnitExists(unit) then return end
        local id = npcOf(unit)
        if not id then return end
        for _, u in ipairs(UNITS) do
            if u.id == id then
                local cur, max = UnitHealth(unit), UnitHealthMax(unit)
                if max and max > 0 then hp[id] = cur / max end
            end
        end
    end
    check("target"); check("targettarget"); check("focus"); check("mouseover")
    for i = 1, 5 do check("boss" .. i) end
    if IsInRaid() then
        for i = 1, 40 do check("raid" .. i .. "target") end
    else
        for i = 1, 4 do check("party" .. i .. "target") end
    end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, np in ipairs(C_NamePlate.GetNamePlates()) do
            if np.namePlateUnitToken then check(np.namePlateUnitToken) end
        end
    end
end

local function Position(c)
    local pos = Addon:GetAnchorPos(MH_KEY)
    c:ClearAllPoints()
    c:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
end

local function ApplyMHCfg(c)
    c:SetScale(mhCfg().scale or 1)
    c:SetAlpha(mhCfg().opacity or 1)
end

local function EnsureMH()
    if mh then return mh end
    local c = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    c:SetSize(170, 72); c:SetFrameStrata("MEDIUM")
    c:SetMovable(true); c:EnableMouse(true)
    Addon:ApplyDarkBackdrop(c)
    c.header = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.header:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -2); c.header:SetText("|cff66ccffMini-Bosses|r")
    c:SetScript("OnMouseDown", function(self, b) if b == "LeftButton" then self:StartMoving() end end)
    c:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        Addon:SetMechanicPos(MH_KEY, p, rp, x, y)
    end)

    c.rows = {}
    for i, u in ipairs(UNITS) do
        local row = CreateFrame("Frame", nil, c)
        row:SetSize(158, 26)
        row:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -(16 + (i - 1) * 28))
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0); row.name:SetText(u.name)
        row.bar = CreateFrame("StatusBar", nil, row)
        row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -12); row.bar:SetSize(158, 12)
        row.bar:SetMinMaxValues(0, 1); row.bar:SetValue(1)
        row.bar.bg = row.bar:CreateTexture(nil, "BACKGROUND"); row.bar.bg:SetAllPoints()
        Addon:StyleBar(row.bar); Addon:AddBorder(row.bar)
        row.pct = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.pct:SetPoint("RIGHT", row.bar, "RIGHT", -3, 0)
        Addon:StyleFont(row.name); Addon:StyleFont(row.pct)
        row._id = u.id
        c.rows[i] = row
    end

    c:SetScript("OnUpdate", function(self, el)
        self._acc = (self._acc or 0) + el
        if self._acc < 0.2 then return end
        self._acc = 0
        ScanHealth()
        for _, row in ipairs(self.rows) do
            local f = hp[row._id]
            if f then
                row.bar:SetValue(f)
                row.bar:SetStatusBarColor(0.85 - 0.55 * f, 0.2 + 0.6 * f, 0.2)  -- red->green
                row.pct:SetText(string.format("%d%%", math.floor(f * 100 + 0.5)))
            else
                row.bar:SetValue(0); row.pct:SetText("--")
            end
        end
    end)
    mh = c
    return c
end

local function ShowMH(preview)
    wipe(hp)
    if preview then hp[15929] = 0.72; hp[15930] = 0.55 end
    EnsureMH(); Position(mh); ApplyMHCfg(mh); mh:Show()
end

Addon:RegisterModule({
    id = MH_ID, raidId = "naxxramas", bossId = "thaddius",
    name = "Mini-Boss Health",
    desc = "Live health of Stalagg + Feugen (the adds before Thaddius). Drag the header to move.",
    defaults = { enabled = false },

    Start = function()
        wipe(deadAdds)
        ShowMH(false)
        mhEv = mhEv or CreateFrame("Frame")
        mhEv:SetScript("OnEvent", function(_, event)
            if event == "COMBAT_LOG_EVENT_UNFILTERED" then
                local _, sub, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
                if sub == "UNIT_DIED" then
                    local _, _, _, _, _, id = strsplit("-", destGUID or "")
                    id = tonumber(id)
                    if id == 15929 or id == 15930 then
                        deadAdds[id] = true
                        if deadAdds[15929] and deadAdds[15930] and mh then mh:Hide() end  -- both adds dead -> Thaddius up
                    end
                end
            else
                ScanHealth()
            end
        end)
        mhEv:RegisterEvent("UNIT_HEALTH")
        mhEv:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        mhEv:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end,
    Stop = function()
        if mhEv then mhEv:UnregisterAllEvents() end
        if mh then mh:Hide() end
    end,
    Test = function()
        if mh and mh:IsShown() then mh:Hide() else ShowMH(true) end
    end,
    SetPreview = function(_, on)
        if on then ShowMH(true) elseif mh then mh:Hide() end
    end,

    BuildConfig = function(_, parent)
        local DS = _G.DaseekiSuite
        DS.MakeSlider(parent, 6, 24, 150, "Scale", 0.5, 2.0, 0.05,
            function() return mhCfg().scale or 1 end,
            function(v) mhCfg().scale = v; if mh then mh:SetScale(v) end end,
            function(v) return string.format("%.2f", v) end)
        DS.MakeSlider(parent, 6, 70, 150, "Opacity", 0.1, 1.0, 0.05,
            function() return mhCfg().opacity or 1 end,
            function(v) mhCfg().opacity = v; if mh then mh:SetAlpha(v) end end,
            function(v) return string.format("%.2f", v) end)
    end,
})

-- ════════════════════════════════════════════════════════════════════════════
-- 2) Polarity-change watcher (sub-option of the Polarity Shift mechanic)
-- ════════════════════════════════════════════════════════════════════════════
local POL_KEY  = "naxxramas:thaddius:polarity"
local NEG_ICON, POS_ICON = 135768, 135769
local lastCharge

local function polCfg() return Addon.db and Addon.db.mechanics[POL_KEY] or {} end

local function CurrentCharge()
    for i = 1, 40 do
        local name, icon = UnitDebuff("player", i)
        if not name then break end
        if icon == NEG_ICON then return "neg"
        elseif icon == POS_ICON then return "pos" end
    end
    return nil
end

local function OnPlayerAura()
    local c = polCfg()
    if not c.pcEnabled then return end
    local charge = CurrentCharge()
    if not charge then return end
    if lastCharge and charge ~= lastCharge then
        local label = (charge == "pos") and "Positive" or "Negative"
        local color = (charge == "pos") and { 1, 0.82, 0.2 } or { 0.4, 0.6, 1 }
        if c.pcText  then Addon:ShowWarning(POL_KEY, "Polarity CHANGED \226\134\146 " .. label, color) end
        if c.pcSound then Addon:PlaySoundByKey(c.pcSoundKey or "raidwarning", true) end
    end
    lastCharge = charge
end

local polEv = CreateFrame("Frame")
polEv:RegisterUnitEvent("UNIT_AURA", "player")
polEv:RegisterEvent("PLAYER_REGEN_ENABLED")
polEv:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then lastCharge = nil   -- reset between pulls
    else OnPlayerAura() end
end)
