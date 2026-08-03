--[[
    Daseeki Raid Mechanics — shared dark-mode theme

    Central palette + styling helpers so every UI element the addon creates has a
    consistent flat, dark look by default. Bars use a flat fill tinted by their
    own colour; frames get a dark panel + 1px border; text gets a readable shadow.

    SUITE ROUTING (Daseeki-Core is an OptionalDep, never a requirement): when Core
    is loaded, the palette below resolves through DaseekiUI's THEME TOKENS and text
    takes the user's PICKED FACE from the Core font picker, so this addon's HUD
    matches the rest of the suite and follows the theme the owner selected. Without
    Core every helper falls back to the literal palette / GameFont templates that
    shipped here, so the standalone look is byte-identical to before. Same guarded
    shape the rest of the suite uses (cf. Raid Prep's tc(), Armory's Try* helpers).
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
    warnText  = { 1.00, 0.90, 0.30, 1.00 },   -- caution/counter amber (was inline in alerts.lua)
}

-- Theme-field name -> DaseekiUI token. Only the fields that MEAN the same thing are
-- mapped; anything unmapped keeps its literal value in every configuration.
local TOKEN_FOR = {
    panelBG = "panel",
    barBG   = "inset",
    border  = "border",
    text    = "text",
    subText  = "muted",
    accent   = "accent",
    warnText = "warn",
}

-- r,g,b,a for a Theme field: the live suite token with Core, the literal without.
-- The ALPHA always comes from the literal, never from the token — these are HUD
-- surfaces drawn over the game world, and their translucency (panel 0.94, bar track
-- 0.90) is a legibility decision that belongs to this addon, not to the palette.
function Addon:ThemeColor(key)
    local lit = Addon.Theme[key] or Addon.Theme.text
    local UI  = _G.DaseekiUI
    local tok = TOKEN_FOR[key]
    if UI and UI.Color and tok then
        local r, g, b = UI.Color(tok)
        return r, g, b, lit[4] or 1
    end
    return lit[1], lit[2], lit[3], lit[4] or 1
end

-- Apply a shared DaseekiUI font object (the user's picked face, at the picked scale)
-- to a FontString when Core is present; leaves the caller's GameFont template alone
-- otherwise. Roles: body / muted / small / accent / danger / header / microLabel /
-- numeral. Because these are FontObjects, Core re-applies the face and tint on every
-- font/theme change, so RM's HUD tracks the picker with no local subscription.
--
-- CALL BEFORE Addon:StyleFont (or any SetTextColor): SetFontObject also re-applies
-- that object's own colour, which would otherwise overwrite the caller's tint.
function Addon:TrySetFont(fs, role)
    local UI = _G.DaseekiUI
    if fs and fs.SetFontObject and UI and UI.fonts then
        local fo = UI.fonts[role or "body"] or UI.fonts.body
        if fo then fs:SetFontObject(fo); return true end
    end
    return false
end

-- Swap ONLY the face of a FontString, keeping the size and flags its GameFont
-- template gave it. For the center/special warnings: their point size and outline are
-- the whole reason they read across a 40-man raid, so they must not be pulled down to
-- a body-text role — but the FACE should still follow the suite picker. No-op without
-- Core, and no-op if the picked face cannot be resolved.
function Addon:ReFaceKeepingSize(fs)
    if not (fs and fs.GetFont and fs.SetFont) then return false end
    local UI = _G.DaseekiUI
    if not (UI and UI.FontFile) then return false end
    local okPath, path = pcall(UI.FontFile)
    if not (okPath and type(path) == "string" and path ~= "") then return false end
    local _, size, flags = fs:GetFont()
    if not size then return false end
    fs:SetFont(path, size, flags or "")
    return true
end

-- Flat dark backdrop + 1px border on a BackdropTemplate frame.
function Addon:ApplyDarkBackdrop(f, bgAlpha)
    if not f.SetBackdrop then return end
    f:SetBackdrop({
        bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    local pr, pg, pb, pa = Addon:ThemeColor("panelBG")
    f:SetBackdropColor(pr, pg, pb, bgAlpha or pa)
    f:SetBackdropBorderColor(Addon:ThemeColor("border"))
end

-- Style a StatusBar's texture + track (caller still sets the fill colour).
function Addon:StyleBar(bar)
    bar:SetStatusBarTexture(Addon.Theme.statusbar)
    if bar.bg then bar.bg:SetColorTexture(Addon:ThemeColor("barBG")) end
end

-- Add a thin dark border framing a region/frame.
function Addon:AddBorder(parent, inset)
    inset = inset or 0
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", -inset, inset)
    b:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", inset, -inset)
    b:SetBackdrop({ edgeFile = FLAT, edgeSize = 1 })
    local r, g, bl = Addon:ThemeColor("border")
    b:SetBackdropBorderColor(r, g, bl, 1)
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

-- Readable shadowed text. `color` may be:
--   nil            -> the theme's `text` role (suite token with Core, literal without)
--   "subText" etc. -> a Theme FIELD NAME, resolved through Addon:ThemeColor (preferred:
--                     it keeps following the active suite theme)
--   {r,g,b[,a]}    -> an explicit literal, used verbatim (semantic colours a mechanic
--                     owns, e.g. a class or state tint, must not be re-themed)
function Addon:StyleFont(fs, color)
    if type(color) == "string" then
        fs:SetTextColor(Addon:ThemeColor(color))
    elseif color then
        fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    else
        fs:SetTextColor(Addon:ThemeColor("text"))
    end
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
end
