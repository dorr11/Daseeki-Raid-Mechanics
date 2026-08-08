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

    -- ── 2.0 wave 2: timer-bar + warning-tier tokens ───────────────────────────
    -- DREW_UI_STYLE standing rule: "Tokens only — any hardcoded colour/font is a
    -- defect. New visual behaviour = new token." The bar surface and the two
    -- warning tiers are new visual behaviour, so every colour they use is a token
    -- declared here and resolved through Addon:BarColor / Addon:WarnColor.
    barTrack    = { 0.06, 0.06, 0.08, 0.88 },   -- bar track behind the fill
    barVariance = { 1.00, 1.00, 1.00, 0.22 },   -- §4.2 variance-window overlay
    barSpark    = { 1.00, 1.00, 1.00, 0.70 },
    barFlash    = { 1.00, 1.00, 1.00, 0.35 },   -- §4.7 flash under 7.75 s
    barText     = { 0.95, 0.95, 0.98, 1.00 },
    barCount    = { 1.00, 0.90, 0.30, 1.00 },
}

-- ENGINE SPEC §4.5 colour indices: 1 add, 2 AoE, 3 targeted, 4 interrupt, 5 role,
-- 6 stage, 7 user — plus the three special categories (break / pull / berserk) that
-- §4.5 lists beside the four simplified ones. §4.7: "colour interpolates linearly
-- from a per-type START colour to a per-type END colour across the bar's life",
-- so each class is a PAIR, not a colour.
--
-- `token` names the DaseekiUI theme token this class defers to when Daseeki-Core is
-- present (so an interrupt bar is the suite's danger red, not a second opinion about
-- what red means). Classes with no honest suite equivalent stay literal in every
-- configuration — that is the same rule Addon:ThemeColor already follows.
Addon.Theme.barClass = {
    [1] = { label = "Adds",      from = { 0.20, 0.66, 0.45 }, to = { 0.11, 0.38, 0.26 } },
    [2] = { label = "AoE",       from = { 0.96, 0.62, 0.20 }, to = { 0.58, 0.35, 0.10 }, token = "warn" },
    [3] = { label = "Targeted",  from = { 0.72, 0.38, 0.88 }, to = { 0.42, 0.21, 0.54 } },
    [4] = { label = "Interrupt", from = { 0.90, 0.28, 0.28 }, to = { 0.53, 0.15, 0.15 }, token = "danger" },
    [5] = { label = "Role",      from = { 0.30, 0.58, 0.95 }, to = { 0.17, 0.33, 0.57 }, token = "accent" },
    [6] = { label = "Stage",     from = { 0.25, 0.78, 0.85 }, to = { 0.13, 0.44, 0.50 } },
    [7] = { label = "User",      from = { 0.73, 0.75, 0.81 }, to = { 0.41, 0.43, 0.49 }, token = "muted" },
    pull    = { label = "Pull",    from = { 0.86, 0.26, 0.31 }, to = { 0.52, 0.13, 0.17 }, token = "brand" },
    ["break"] = { label = "Break", from = { 0.40, 0.72, 0.42 }, to = { 0.22, 0.42, 0.24 } },
    berserk = { label = "Berserk", from = { 1.00, 0.42, 0.10 }, to = { 0.60, 0.21, 0.05 } },
}

-- ENGINE SPEC §5.1: "Four user-configurable colour slots (1 turquoise / 2 yellow /
-- 3 orange / 4 red) map to announce priority", and tier 3's "default colour a
-- yellow-orange".
Addon.Theme.warnTier = {
    [1] = { 0.30, 0.85, 0.82 },   -- turquoise
    [2] = { 1.00, 0.90, 0.30 },   -- yellow
    [3] = { 1.00, 0.62, 0.20 },   -- orange
    [4] = { 0.94, 0.30, 0.30 },   -- red
}
Addon.Theme.specialText = { 1.00, 0.72, 0.18 }   -- §5.1 tier 3 default yellow-orange

-- Per special-warning SOUND TIER (§5.1): screen-flash colour. The flash duration,
-- alpha and repeat count live with the tier defaults in ui_warnings.lua; only the
-- COLOURS are tokens, because only the colours are a palette decision.
Addon.Theme.flashTier = {
    [1] = { 1.00, 0.85, 0.30 },   -- personal
    [2] = { 0.35, 0.70, 1.00 },   -- everyone
    [3] = { 1.00, 0.35, 0.25 },   -- very important
    [4] = { 1.00, 0.20, 0.20 },   -- run away
    [5] = { 0.80, 0.45, 1.00 },   -- your name is in the user's note
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

-- ── Bar / warning colour resolvers (wave 2) ───────────────────────────────────
-- A colour CLASS resolved at a point in the bar's life. `t` is 0 at the start and 1
-- at the end, so this is ENGINE SPEC §4.7's linear interpolation from the class's
-- start colour to its end colour. A class that names a suite token takes the token
-- for its START colour (so the suite theme is visible in the class that means the
-- same thing) and keeps its own literal END colour, because the darkening ramp is
-- this HUD's legibility decision, not the palette's.
function Addon:BarColor(class, t)
    local c = Addon.Theme.barClass[class] or Addon.Theme.barClass[7]
    t = t or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local fr, fg, fb = c.from[1], c.from[2], c.from[3]
    local UI = _G.DaseekiUI
    if c.token and UI and UI.Color then
        local r, g, b = UI.Color(c.token)
        if r then fr, fg, fb = r, g, b end
    end
    local tr, tg, tb = c.to[1], c.to[2], c.to[3]
    return fr + (tr - fr) * t, fg + (tg - fg) * t, fb + (tb - fb) * t
end

-- Desaturate toward the bar's own luminance by `k` (0 = untouched, 1 = grey).
-- §4.7: "non-enlarged bars beyond the enlarge threshold are desaturated by a
-- configurable factor."
function Addon:Desaturate(r, g, b, k)
    k = k or 0
    local lum = 0.299 * r + 0.587 * g + 0.114 * b
    return r + (lum - r) * k, g + (lum - g) * k, b + (lum - b) * k
end

function Addon:WarnColor(slot)
    local c = Addon.Theme.warnTier[slot] or Addon.Theme.warnTier[2]
    return c[1], c[2], c[3]
end

function Addon:FlashColor(tier)
    local c = Addon.Theme.flashTier[tier] or Addon.Theme.flashTier[1]
    return c[1], c[2], c[3]
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

-- ── HUD anchors (wave 2) ──────────────────────────────────────────────────────
-- The bar lists and the two warning tiers each hang off ONE anchor frame. The
-- anchor is always present and always positioned (everything else points at it);
-- unlocking simply DRESSES it — dark backdrop, border, and a LABEL saying which
-- surface it is.
--
-- DREW_UI_STYLE principle 6, "every control is labeled": four unlabelled boxes on
-- screen is exactly the defect that reads as unfinished. Standing rule "every frame
-- sets BOTH dimensions at creation" applies here too. Positions ride the SAME saved
-- machinery alerts.lua already uses (db.mechanics[key].pos via SetMechanicPos), so
-- no new schema and no new migration.
--
-- 2.0 ANCHOR REWORK: an anchor's POSITION is no longer set here. Every anchor —
-- the four buckets, the Specials anchor, and every Custom row's own handle — is
-- installed into ui_anchors.lua's resolver, which decides between screen / attached
-- to a named game frame / docked, and re-decides whenever the world changes. This
-- function still owns the FRAME (size, label, dress, drag); it just no longer owns
-- where the frame is. Without the resolver (a load-order accident, or a headless
-- harness with no frames) it falls straight back to the stored screen position.
Addon._hudAnchors = {}

function Addon:HudAnchor(key, label, defaultPos, w, h)
    local a = Addon._hudAnchors[key]
    if a then return a end
    if type(_G.CreateFrame) ~= "function" then return nil end
    a = _G.CreateFrame("Frame", nil, _G.UIParent, "BackdropTemplate")
    a:SetSize(w or 220, h or 22)                       -- BOTH dimensions at creation
    Addon._hudAnchors[key] = a                         -- before Install: it looks itself up
    -- Claimed BEFORE Install, so Anchors.HookDrag does not add a HookScript that the
    -- explicit SetScript below would then replace (leaving a drag that saves twice, or
    -- not at all). This frame's drag handler is written here and only here.
    a._drmAnchorDragHooked = true
    if Addon.Anchors then
        Addon.Anchors.Install(key, a, { label = label, defaultPos = defaultPos })
    else
        local pos = Addon:GetAnchorPos(key, defaultPos)
        a:SetPoint(pos.point or "CENTER", _G.UIParent, pos.relPoint or "CENTER",
                   pos.x or 0, pos.y or 0)
    end
    a.label = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    a.label:SetPoint("CENTER")                         -- principle 3: centred in its panel
    a.label:SetJustifyH("CENTER")
    Addon:TrySetFont(a.label, "microLabel")
    Addon:StyleFont(a.label, "subText")
    a.label:SetText(label or key)
    a:SetMovable(true)
    a:SetScript("OnMouseDown", function(s) s:StartMoving() end)
    -- Where the drag LANDS depends on the anchor's mode: free anchors store a screen
    -- position, attached/docked ones store an offset from their host. That decision
    -- belongs to the resolver, not here.
    a:SetScript("OnMouseUp", function(s)
        s:StopMovingOrSizing()
        if Addon.Anchors then
            Addon.Anchors.SaveDrag(key, s)
        else
            local p, _, rp, x, y = s:GetPoint()
            Addon:SetMechanicPos(key, p, rp, x, y)
        end
    end)
    Addon:SetAnchorDressed(a, false)
    return a
end

function Addon:SetAnchorDressed(a, on)
    if not a then return false end
    if on then
        Addon:ApplyDarkBackdrop(a)
        a:EnableMouse(true)
        a:SetFrameStrata("FULLSCREEN_DIALOG")
        a.label:Show()
        a:Show()
    else
        if a.SetBackdrop then a:SetBackdrop(nil) end
        a:EnableMouse(false)                            -- never eat a click while locked
        a:SetFrameStrata("BACKGROUND")
        a.label:Hide()
    end
    return true
end

function Addon:ShowHudAnchors()
    local n = 0
    for _, a in pairs(Addon._hudAnchors) do
        if Addon:SetAnchorDressed(a, true) then n = n + 1 end
    end
    return n
end

function Addon:HideHudAnchors()
    local n = 0
    for _, a in pairs(Addon._hudAnchors) do
        if Addon:SetAnchorDressed(a, false) then n = n + 1 end
    end
    return n
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
