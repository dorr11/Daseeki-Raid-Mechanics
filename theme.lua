--[[
    Daseeki Raid Mechanics — shared dark-mode theme

    Central palette + styling helpers so every UI element the addon creates has a
    consistent flat, dark look by default. Bars use a flat fill tinted by their
    own colour; frames get a dark panel + 1px border; text gets a readable shadow.
--]]

local _, Addon = ...

local FLAT = "Interface\\Buttons\\WHITE8X8"   -- solid 1px texture (flat fills / borders)

Addon.Theme = {
    statusbar = FLAT,
    panelBG   = { 0.05, 0.05, 0.06, 0.94 },   -- frame background
    barBG     = { 0.07, 0.07, 0.09, 0.90 },   -- bar track
    border    = { 0.22, 0.22, 0.27, 1.00 },   -- subtle border
    text      = { 0.93, 0.93, 0.96, 1.00 },
    subText   = { 0.60, 0.60, 0.66, 1.00 },
    accent    = { 0.35, 0.55, 0.95, 1.00 },
}

-- Flat dark backdrop + 1px border on a BackdropTemplate frame.
function Addon:ApplyDarkBackdrop(f, bgAlpha)
    if not f.SetBackdrop then return end
    local T = Addon.Theme
    f:SetBackdrop({
        bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(T.panelBG[1], T.panelBG[2], T.panelBG[3], bgAlpha or T.panelBG[4])
    f:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], T.border[4])
end

-- Style a StatusBar's texture + track (caller still sets the fill colour).
function Addon:StyleBar(bar)
    local T = Addon.Theme
    bar:SetStatusBarTexture(T.statusbar)
    if bar.bg then bar.bg:SetColorTexture(T.barBG[1], T.barBG[2], T.barBG[3], T.barBG[4]) end
end

-- Add a thin dark border framing a region/frame.
function Addon:AddBorder(parent, inset)
    inset = inset or 0
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", -inset, inset)
    b:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", inset, -inset)
    b:SetBackdrop({ edgeFile = FLAT, edgeSize = 1 })
    local T = Addon.Theme
    b:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    return b
end

-- Black 1px border framing an icon texture (or any region), so icons stand out.
-- Anchors to `anchorTo` (usually the icon texture) and follows it automatically.
function Addon:AddIconBorder(anchorTo, parent)
    parent = parent or anchorTo:GetParent()
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", -1, 1)
    b:SetPoint("BOTTOMRIGHT", anchorTo, "BOTTOMRIGHT", 1, -1)
    b:SetBackdrop({ edgeFile = FLAT, edgeSize = 1 })
    b:SetBackdropBorderColor(0, 0, 0, 1)
    return b
end

-- Readable shadowed text.
function Addon:StyleFont(fs, color)
    color = color or Addon.Theme.text
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
end
