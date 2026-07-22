--[[
    Daseeki Raid Mechanics — options section for the Daseeki-Core hub.

    4-pane drill-down:
        Raids -> Bosses (+ "Other (Trash)") -> Mechanics & Modules -> Detail editor.
    The mechanic list shows the boss's declarative mechanics PLUS any ported-WA
    "modules" (prefixed with a blue *). Selecting a mechanic shows the style/scale/
    sound/position editor; selecting a module shows its enable + description + config.
--]]

local _, Addon = ...

local HEADER_Y = 52
local LIST_Y   = 78
local ROW_H    = 24
-- Each raid is its own section now, so there's no raids column: Bosses -> Mechanics -> Detail.
local BOSS_X, BOSS_W   = 0,   140
local MECH_X, MECH_W   = 148, 150
local DETAIL_X, DETAIL_W = 306, 290
-- Read-only timing reference box, to the right of Settings (cooldowns are hardcoded
-- addon data — see UpdateTimingInfo — not a user-adjustable slider).
local TIMING_X = DETAIL_X + DETAIL_W + 24

local STYLE_CHOICES = {
    { key = "bar",       name = "Timer Bar" },
    { key = "icon",      name = "Icon + Radial" },
    { key = "number",    name = "Big Number" },
    { key = "text",      name = "Text Banner" },
    { key = "flash",     name = "Center Flash" },
    { key = "pulse",     name = "Pulse Icon" },
    { key = "castbar",   name = "Cast Bar" },
    { key = "nameplate", name = "Nameplate Icon" },
}
local STYLE_NAME, STYLE_KEY = {}, {}
do
    for _, s in ipairs(STYLE_CHOICES) do STYLE_NAME[s.key] = s.name; STYLE_KEY[s.name] = s.key end
end
local function StyleNames()
    local t = {}; for _, s in ipairs(STYLE_CHOICES) do t[#t + 1] = s.name end; return t
end

-- ── List widgets ─────────────────────────────────────────────────────────────--
local function NavButton(parent, w)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, ROW_H)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(0.2, 0.4, 0.8, 0)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.label:SetPoint("LEFT", b, "LEFT", 6, 0); b.label:SetJustifyH("LEFT"); b.label:SetWidth(w - 12)
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0.3, 0.5, 0.9, 0.25)
    b:SetHighlightTexture(hl)
    return b
end

local function MechListRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(MECH_W, ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(0.2, 0.4, 0.8, 0)
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0.3, 0.5, 0.9, 0.2)
    r:SetHighlightTexture(hl)
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(20, 20); r.check:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.label:SetPoint("LEFT", r.check, "RIGHT", 2, 0); r.label:SetWidth(MECH_W - 26); r.label:SetJustifyH("LEFT")
    return r
end

local function LayoutList(pool, parent, x, yTop, w, items, getText, isSel, onClick)
    for _, b in ipairs(pool) do b:Hide() end
    for i, item in ipairs(items) do
        local b = pool[i]
        if not b then b = NavButton(parent, w); pool[i] = b end
        b:SetWidth(w); b:ClearAllPoints()
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(yTop + (i - 1) * ROW_H))
        b.label:SetText(getText(item))
        b.bg:SetColorTexture(0.2, 0.4, 0.8, isSel(item) and 0.5 or 0)
        b:SetScript("OnClick", function() onClick(item) end)
        b:Show()
    end
end

-- ── Selection accessors ──────────────────────────────────────────────────────--
local function CurKey(panel)  return panel.selMechKey end
local function CurDef(panel)  return panel.selMechDef end
local function CurCfg(panel)
    if not panel.selMechKey then return {} end
    return Addon:GetMechanicConfig(panel.selMechKey, panel.selMechDef)
end

-- Set a mechanic option and, while unlocked, live-refresh its on-screen preview.
local function SetMechOpt(panel, field, v)
    local k = panel.selMechKey; if not k then return end
    Addon:SetMechanicOption(k, field, v)
    if Addon:IsUnlocked() then Addon:RefreshPlacement(k, panel.selMechDef) end
end

-- Reminder (snowball-style sub-alert) accessors for the selected mechanic.
local function CurRemDef(panel) return panel.selMechDef and panel.selMechDef.reminder end
local function CurRemKey(panel) return panel.selMechKey and (panel.selMechKey .. "#rem") end
local function CurRemCfg(panel)
    local rd = CurRemDef(panel); if not rd then return {} end
    return Addon:GetMechanicConfig(CurRemKey(panel), rd)
end

-- On-cast text-notification accessors (a sub-setting of the mechanic itself, not a
-- separate list row). Synthesizes the same pseudo-mechDef alerts.lua's FireOnCast uses.
local function CurCastKey(panel) return panel.selMechKey and (panel.selMechKey .. "#cast") end
local function CurCastDef(panel)
    local mech = panel.selMechDef
    if not mech then return nil end
    return {
        name = "On-cast: " .. (mech.name or ""), style = "text",
        default = mech.onCastDefault and true or false,
        warningText = mech.castText or mech.warningText or mech.name,
        barColor = mech.barColor, warningColor = mech.warningColor,
        _defaultPos = Addon.DEFAULT_TOP_POS,
    }
end
local function CurCastCfg(panel)
    local k = CurCastKey(panel); if not k then return {} end
    return Addon:GetMechanicConfig(k, CurCastDef(panel))
end
-- Only mechanics that actually fire on a detectable event support an on-cast popup
-- (matches the trigger types the engine dispatches through Addon:FireOnCast).
local function HasOnCast(mech)
    if not mech or mech.noLoop then return false end
    local tt = mech.trigger and mech.trigger.type
    return tt == "cast" or tt == "aura" or tt == "health" or tt == "yell" or tt == "emote"
end

-- Personal Damage Warning accessors — independent of trigger.type (fires off the
-- player actually taking damage from the same spellID, see engine.lua's MatchDamage).
local function CurDmgKey(panel) return panel.selMechKey and (panel.selMechKey .. "#dmg") end
local function CurDmgDef(panel)
    local mech = panel.selMechDef
    if not mech then return nil end
    return {
        name = "Damage Warning: " .. (mech.name or ""), style = "text", default = false,
        warningText = mech.dmgText or ("You are taking damage from " .. (mech.name or "this") .. "!"),
        barColor = mech.barColor, warningColor = mech.warningColor,
        _defaultPos = Addon.DEFAULT_TOP_POS,
    }
end
local function CurDmgCfg(panel)
    local k = CurDmgKey(panel); if not k then return {} end
    return Addon:GetMechanicConfig(k, CurDmgDef(panel))
end
-- Only mechanics with a concrete spellID can be matched against a damage event.
local function HasDamageWarning(mech)
    if not mech then return false end
    local t = mech.trigger
    return t ~= nil and (t.spellID ~= nil or t.spellIDs ~= nil)
end

-- Read-only timing reference (CD from start / CD) — these are hardcoded addon data
-- (mech.firstCast / mech.cooldown), not user-adjustable, so just display them.
local function UpdateTimingInfo(panel, mech)
    local ti = panel.timingInfo
    if not ti then return end
    if not mech then
        ti.fromStart:SetText("\226\128\148"); ti.cd:SetText("\226\128\148")
        return
    end
    ti.fromStart:SetText(mech.firstCast and (mech.firstCast .. "s") or "\226\128\148")
    ti.cd:SetText((mech.mode == "cooldown" and mech.cooldown) and (mech.cooldown .. "s") or "\226\128\148")
end

-- Forward declarations (mutually referenced below).
local RebuildMechs, RebuildBosses
local PopulateDetail, PopulateModuleDetail

-- ── Detail editors (persistent widgets, repopulated on selection) ────────────────
-- Wrap a detail pane in a scrollable viewport so a tall stack of controls (cooldown
-- group + reminder + on-cast notification, etc.) can never spill outside the hub
-- window — it scrolls instead. The viewport's height tracks the panel's REAL
-- available space (TOPLEFT+BOTTOMLEFT anchors, not a guessed fixed SetSize), so it
-- keeps fitting even if hub geometry changes. Recurring overflow bug — always wrap
-- any detail/config pane that can grow when adding new controls here.
-- Generous fixed height; current worst case (cooldown+reminder + On Cast Notification +
-- Personal Damage Warning all stacked) is ~1300px. It scrolls regardless, so err high.
local SCROLL_CHILD_H = 1450
-- The viewport's MOUSE-WHEEL hit area stretches to the panel's right edge (not just
-- the `w`-wide settings column) so the cursor doesn't have to be precisely over a
-- slider/widget to scroll — anywhere in the blank space to the right works too. The
-- scroll CHILD (the actual widgets) stays at width `w`; only the hit-test area widens.
local function WrapInScroll(panel, x, y, w)
    local viewport = CreateFrame("ScrollFrame", nil, panel)
    viewport:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
    viewport:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 8)
    viewport:EnableMouseWheel(true)

    local child = CreateFrame("Frame", nil, viewport)
    child:SetSize(w, SCROLL_CHILD_H)
    viewport:SetScrollChild(child)

    viewport:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
        local cur = self:GetVerticalScroll()
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, cur - delta * 40)))
    end)
    return child
end

local function BuildDetail(panel)
    local DS = _G.DaseekiSuite

    -- (A) Mechanic detail
    local d = WrapInScroll(panel, DETAIL_X, HEADER_Y, DETAIL_W)
    panel.detail = d

    -- Read-only timing reference, to the right of Settings. Static (parented to
    -- `panel`, not the scrollable `d`) so it stays visible regardless of scroll
    -- position, and reflects whichever mechanic is selected (see UpdateTimingInfo).
    local ti = CreateFrame("Frame", nil, panel)
    ti:SetPoint("TOPLEFT", panel, "TOPLEFT", TIMING_X, -HEADER_Y)
    ti:SetSize(160, 110)
    panel.timingInfo = ti
    DS.MakeLabel(ti, "CD from start", nil, 0, 0):SetTextColor(0.6, 0.6, 0.6)
    ti.fromStart = DS.MakeLabel(ti, "\226\128\148", 18, 0, 18)
    DS.MakeLabel(ti, "CD", nil, 0, 56):SetTextColor(0.6, 0.6, 0.6)
    ti.cd = DS.MakeLabel(ti, "\226\128\148", 18, 0, 74)

    d.title = DS.MakeLabel(d, "", 15, 0, 0); d.title:SetTextColor(1, 0.82, 0)

    -- ── Sub-section 1: Ability Tracker (the original style/scale/sound/position editor) ──
    DS.MakeSeparator(d, 0, 22, DETAIL_W - 10, 0)
    DS.MakeLabel(d, "|cffffffffAbility Tracker|r", nil, 0, 28)

    -- Ability Tracker's OWN enable (`cfg.enabled`) — deliberately a DIFFERENT field
    -- from the mechanics-list row's checkbox (`cfg.masterEnabled`, which gates this
    -- mechanic's Ability Tracker + On Cast Notification + Personal Damage Warning +
    -- reminder + count ALL at once). This one only suppresses the tracker's own
    -- visual/sound; the other sub-sections keep working independently if their own
    -- enable checkboxes are on. Mirrors On Cast Notification's own enable checkbox.
    d.enable = DS.MakeCheckbox(d, "Enable Ability Tracker", 0, 50,
        function() return CurCfg(panel).enabled end,
        function(v)
            if not CurKey(panel) then return end
            Addon:SetMechanicOption(CurKey(panel), "enabled", v and true or false)
            RebuildMechs(panel)
            if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
        end)

    DS.MakeLabel(d, "Style", nil, 0, 80)
    d.styleDD = DS.MakeSimpleDropdown(d, 56, 76, 180, StyleNames(), function(name)
        SetMechOpt(panel, "style", STYLE_KEY[name] or "bar")
    end)

    -- Sliders are centered in the ~290px column: x 55 + width 180 -> track centre 145.
    d.scale = DS.MakeSlider(d, 55, 124, 180, "Scale", 0.5, 2.0, 0.05,
        function() return CurCfg(panel).scale or 1 end,
        function(v) if not panel._pop then SetMechOpt(panel, "scale", v) end end,
        function(v) return string.format("%.2f", v) end)

    d.opacity = DS.MakeSlider(d, 55, 168, 180, "Opacity", 0.1, 1.0, 0.05,
        function() return CurCfg(panel).opacity or 1 end,
        function(v) if not panel._pop then SetMechOpt(panel, "opacity", v) end end,
        function(v) return string.format("%.2f", v) end)

    -- Border glow on icon styles when the timer drops below this (0 = off).
    d.glowS = DS.MakeSlider(d, 55, 212, 180, "Glow under", 0, 30, 1,
        function() return CurCfg(panel).glowThreshold or 0 end,
        function(v) if not panel._pop then SetMechOpt(panel, "glowThreshold", v) end end,
        function(v) return (v == 0) and "Off" or string.format("%ds", v) end)

    DS.MakeLabel(d, "Sound", nil, 0, 260)
    d.soundBtn = DS.MakeButton(d, "None", 56, 256, 150, 22, function()
        if not CurKey(panel) then return end
        Addon:ShowSoundPicker(CurCfg(panel).sound, function(key)
            Addon:SetMechanicOption(CurKey(panel), "sound", key)
            d.soundBtn:SetText(Addon:GetSoundName(key))
        end, d.soundBtn)
    end)
    d.soundTest = DS.MakeButton(d, "Test", 212, 256, 56, 22, function()
        Addon:PlaySoundByKey(CurCfg(panel).sound, true)
    end)

    d.resetPos = DS.MakeButton(d, "Reset Position", 0, 290, 120, 22, function()
        if not CurKey(panel) then return end
        Addon:SetMechanicOption(CurKey(panel), "pos", nil)
        if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
    end)
    d.testAlert = DS.MakeButton(d, "Test Alert", 0, 320, 140, 22, function()
        if CurKey(panel) then Addon:FireAlert(CurKey(panel), CurDef(panel), true) end
    end)

    -- Bottom of the Ability Tracker section (from d's top) -- cdGroup/pcGroup/ocGroup anchor below it.
    local AT_BOTTOM = 342
    local GROUP_GAP = 24
    local GROUP_Y = AT_BOTTOM + GROUP_GAP   -- top offset for cdGroup / pcGroup
    panel._detailLayout = { atBottom = AT_BOTTOM, groupGap = GROUP_GAP, groupY = GROUP_Y }

    local g = CreateFrame("Frame", nil, d)
    g:SetPoint("TOPLEFT", d, "TOPLEFT", 0, -GROUP_Y); g:SetSize(DETAIL_W, 160)
    d.cdGroup = g
    -- The cooldown VALUE is hardcoded data (see the "Timing" reference box to the
    -- right of Settings) — not a slider here anymore; only the window-open behavior
    -- is user-configurable.
    DS.MakeSeparator(g, 0, 2, DETAIL_W - 10, 0)
    DS.MakeLabel(g, "|cffffffffWindow|r", nil, 0, 8)
    DS.MakeLabel(g, "When the window opens (icon always glows):", nil, 0, 42)
    g.winWarn = DS.MakeCheckbox(g, "Show warning text", 0, 60,
        function() return CurCfg(panel).winWarning end,
        function(v) if CurKey(panel) then Addon:SetMechanicOption(CurKey(panel), "winWarning", v and true or false) end end)
    g.winSound = DS.MakeCheckbox(g, "Play sound", 0, 86,
        function() return CurCfg(panel).winSound end,
        function(v) if CurKey(panel) then Addon:SetMechanicOption(CurKey(panel), "winSound", v and true or false) end end)

    -- Lead-up "reminder" sub-alert (e.g. Maexxna Snowball). Only shown when the
    -- mechanic defines one. Its icon/scale/sound is configured via its own list row.
    g.remSep   = DS.MakeSeparator(g, 0, 112, DETAIL_W - 10, 0)
    g.remTitle = DS.MakeLabel(g, "|cffffffffReminder|r", nil, 0, 118)
    g.remEnable = DS.MakeCheckbox(g, "Enable lead-up reminder", 0, 136,
        function() return CurRemCfg(panel).enabled end,
        function(v)
            if not CurRemKey(panel) then return end
            Addon:SetMechanicOption(CurRemKey(panel), "enabled", v and true or false)
            RebuildMechs(panel)
            if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
        end)
    g.remLead = DS.MakeSlider(g, 55, 182, 180, "Lead (sec)", 1, 20, 1,
        function() return CurRemCfg(panel).leadTime or 5 end,
        function(v) if not panel._pop and CurRemKey(panel) then Addon:SetMechanicOption(CurRemKey(panel), "leadTime", v) end end,
        function(v) return string.format("%ds", v) end)
    g.remHint = DS.MakeLabel(g, "Enabled? Select its row in the list to set icon/scale/sound/position.", nil, 0, 212)
    g.remHint:SetTextColor(0.6, 0.6, 0.6); g.remHint:SetWidth(DETAIL_W - 8); g.remHint:SetJustifyH("LEFT")

    -- (A2) Polarity-change group (shown only for mechanics flagged polarityWatch).
    local pg = CreateFrame("Frame", nil, d)
    pg:SetPoint("TOPLEFT", d, "TOPLEFT", 0, -GROUP_Y); pg:SetSize(DETAIL_W, 200)
    d.pcGroup = pg
    local function pcGet(field, def)
        local o = panel.selMechKey and Addon.db.mechanics[panel.selMechKey]
        if o and o[field] ~= nil then return o[field] end
        return def
    end
    local function pcSet(field, v) if panel.selMechKey then Addon:SetMechanicOption(panel.selMechKey, field, v) end end
    DS.MakeSeparator(pg, 0, 2, DETAIL_W - 10, 0)
    DS.MakeLabel(pg, "|cffffffffPolarity Change Alert|r", nil, 0, 8)
    DS.MakeLabel(pg, "Fires when your charge FLIPS (+ <-> -), not on refresh.", nil, 0, 28)
        :SetTextColor(0.6, 0.6, 0.6)
    pg.pcEnable = DS.MakeCheckbox(pg, "Enable polarity-change alert", 0, 48,
        function() return pcGet("pcEnabled", false) end,
        function(v) pcSet("pcEnabled", v and true or false) end)
    pg.pcText = DS.MakeCheckbox(pg, "Center-screen text", 0, 74,
        function() return pcGet("pcText", true) end,
        function(v) pcSet("pcText", v and true or false) end)
    pg.pcSound = DS.MakeCheckbox(pg, "Play sound", 0, 100,
        function() return pcGet("pcSound", true) end,
        function(v) pcSet("pcSound", v and true or false) end)
    DS.MakeLabel(pg, "Sound", nil, 0, 132)
    pg.pcSoundBtn = DS.MakeButton(pg, "None", 56, 128, 150, 22, function()
        if not panel.selMechKey then return end
        Addon:ShowSoundPicker(pcGet("pcSoundKey", "raidwarning"), function(key)
            pcSet("pcSoundKey", key); pg.pcSoundBtn:SetText(Addon:GetSoundName(key))
        end, pg.pcSoundBtn)
    end)
    pg.pcGet = pcGet
    pg:Hide()

    -- ── Sub-section 2: On Cast Notification (a sub-setting of this mechanic, not a
    -- separate list row) — a top-of-screen text popup the moment the ability fires.
    -- Anchored dynamically in PopulateDetail since its Y depends on whether the
    -- cooldown/reminder or polarity group above it is shown.
    local oc = CreateFrame("Frame", nil, d)
    oc:SetSize(DETAIL_W, 320)
    d.ocGroup = oc
    DS.MakeSeparator(oc, 0, 2, DETAIL_W - 10, 0)
    DS.MakeLabel(oc, "|cffffffffOn Cast Notification|r", nil, 0, 8)
    DS.MakeLabel(oc, "Pops a text banner (top of screen by default) when triggered.", nil, 0, 28)
        :SetTextColor(0.6, 0.6, 0.6)
    oc.enable = DS.MakeCheckbox(oc, "Enable on-cast notification", 0, 52,
        function() return CurCastCfg(panel).enabled end,
        function(v)
            local k = CurCastKey(panel); if not k then return end
            Addon:SetMechanicOption(k, "enabled", v and true or false)
            if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
        end)

    -- Scale / font / font size: a much larger default than the old fixed-size banner,
    -- and fully adjustable since this is meant to be an attention-grabbing announcement.
    oc.scale = DS.MakeSlider(oc, 55, 82, 180, "Scale", 0.5, 3.0, 0.05,
        function() return CurCastCfg(panel).scale or 1 end,
        function(v)
            if panel._pop then return end
            local k = CurCastKey(panel); if not k then return end
            Addon:SetMechanicOption(k, "scale", v)
            if Addon:IsUnlocked() then Addon:RefreshPlacement(k, CurCastDef(panel)) end
        end,
        function(v) return string.format("%.2f", v) end)

    DS.MakeLabel(oc, "Font", nil, 0, 130)
    oc.fontDD = DS.MakeSimpleDropdown(oc, 56, 126, 180, Addon:GetFontNameList(), function(name)
        local k = CurCastKey(panel); if not k then return end
        Addon:SetMechanicOption(k, "fontKey", Addon:GetFontKeyByName(name))
        if Addon:IsUnlocked() then Addon:RefreshPlacement(k, CurCastDef(panel)) end
    end)

    oc.fontSize = DS.MakeSlider(oc, 55, 174, 180, "Font Size", 12, 60, 2,
        function() return CurCastCfg(panel).fontSize or 32 end,
        function(v)
            if panel._pop then return end
            local k = CurCastKey(panel); if not k then return end
            Addon:SetMechanicOption(k, "fontSize", v)
            if Addon:IsUnlocked() then Addon:RefreshPlacement(k, CurCastDef(panel)) end
        end,
        function(v) return string.format("%dpt", v) end)

    DS.MakeLabel(oc, "Sound", nil, 0, 222)
    oc.soundBtn = DS.MakeButton(oc, "None", 56, 218, 150, 22, function()
        local k = CurCastKey(panel); if not k then return end
        Addon:ShowSoundPicker(CurCastCfg(panel).sound, function(key)
            Addon:SetMechanicOption(k, "sound", key)
            oc.soundBtn:SetText(Addon:GetSoundName(key))
        end, oc.soundBtn)
    end)
    oc.soundTest = DS.MakeButton(oc, "Test", 212, 218, 56, 22, function()
        Addon:PlaySoundByKey(CurCastCfg(panel).sound, true)
    end)
    oc.resetPos = DS.MakeButton(oc, "Reset Position", 0, 252, 120, 22, function()
        local k = CurCastKey(panel); if not k then return end
        Addon:SetMechanicOption(k, "pos", nil)
        if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
    end)
    oc.preview = DS.MakeButton(oc, "Preview", 0, 282, 100, 22, function()
        local k = CurCastKey(panel); if not k then return end
        Addon:FireAlert(k, CurCastDef(panel), true)
    end)
    oc:Hide()

    -- ── Sub-section 3: Personal Damage Warning (independent of trigger.type) — fires
    -- when YOU actually take damage from this mechanic's spell, e.g. standing in a
    -- ground effect (Rain of Fire / Blizzard). Anchored dynamically below On Cast
    -- Notification, same pattern. Mirrors its widget set exactly.
    local dw = CreateFrame("Frame", nil, d)
    dw:SetSize(DETAIL_W, 320)
    d.dmgGroup = dw
    DS.MakeSeparator(dw, 0, 2, DETAIL_W - 10, 0)
    DS.MakeLabel(dw, "|cffffffffPersonal Damage Warning|r", nil, 0, 8)
    DS.MakeLabel(dw, "Fires when YOU take damage from this ability (e.g. standing in it).", nil, 0, 28)
        :SetTextColor(0.6, 0.6, 0.6)
    dw.enable = DS.MakeCheckbox(dw, "Enable damage warning", 0, 52,
        function() return CurDmgCfg(panel).enabled end,
        function(v)
            local k = CurDmgKey(panel); if not k then return end
            Addon:SetMechanicOption(k, "enabled", v and true or false)
            if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
        end)

    dw.scale = DS.MakeSlider(dw, 55, 82, 180, "Scale", 0.5, 3.0, 0.05,
        function() return CurDmgCfg(panel).scale or 1 end,
        function(v)
            if panel._pop then return end
            local k = CurDmgKey(panel); if not k then return end
            Addon:SetMechanicOption(k, "scale", v)
            if Addon:IsUnlocked() then Addon:RefreshPlacement(k, CurDmgDef(panel)) end
        end,
        function(v) return string.format("%.2f", v) end)

    DS.MakeLabel(dw, "Font", nil, 0, 130)
    dw.fontDD = DS.MakeSimpleDropdown(dw, 56, 126, 180, Addon:GetFontNameList(), function(name)
        local k = CurDmgKey(panel); if not k then return end
        Addon:SetMechanicOption(k, "fontKey", Addon:GetFontKeyByName(name))
        if Addon:IsUnlocked() then Addon:RefreshPlacement(k, CurDmgDef(panel)) end
    end)

    dw.fontSize = DS.MakeSlider(dw, 55, 174, 180, "Font Size", 12, 60, 2,
        function() return CurDmgCfg(panel).fontSize or 32 end,
        function(v)
            if panel._pop then return end
            local k = CurDmgKey(panel); if not k then return end
            Addon:SetMechanicOption(k, "fontSize", v)
            if Addon:IsUnlocked() then Addon:RefreshPlacement(k, CurDmgDef(panel)) end
        end,
        function(v) return string.format("%dpt", v) end)

    DS.MakeLabel(dw, "Sound", nil, 0, 222)
    dw.soundBtn = DS.MakeButton(dw, "None", 56, 218, 150, 22, function()
        local k = CurDmgKey(panel); if not k then return end
        Addon:ShowSoundPicker(CurDmgCfg(panel).sound, function(key)
            Addon:SetMechanicOption(k, "sound", key)
            dw.soundBtn:SetText(Addon:GetSoundName(key))
        end, dw.soundBtn)
    end)
    dw.soundTest = DS.MakeButton(dw, "Test", 212, 218, 56, 22, function()
        Addon:PlaySoundByKey(CurDmgCfg(panel).sound, true)
    end)
    dw.resetPos = DS.MakeButton(dw, "Reset Position", 0, 252, 120, 22, function()
        local k = CurDmgKey(panel); if not k then return end
        Addon:SetMechanicOption(k, "pos", nil)
        if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
    end)
    dw.preview = DS.MakeButton(dw, "Preview", 0, 282, 100, 22, function()
        local k = CurDmgKey(panel); if not k then return end
        Addon:FireAlert(k, CurDmgDef(panel), true)
    end)
    dw:Hide()

    d:Hide()

    -- (B) Module detail
    local md = WrapInScroll(panel, DETAIL_X, HEADER_Y, DETAIL_W)
    panel.modDetail = md

    md.title = DS.MakeLabel(md, "", 15, 0, 0); md.title:SetTextColor(1, 0.82, 0)
    md.desc = DS.MakeLabel(md, "", nil, 0, 30)
    md.desc:SetWidth(DETAIL_W - 8); md.desc:SetJustifyH("LEFT"); md.desc:SetTextColor(0.8, 0.8, 0.8)
    md.enable = DS.MakeCheckbox(md, "Enable this module", 0, 108,
        function() local m = panel.selModule; return m and Addon:IsModuleEnabled(m.id, m) end,
        function(v)
            local m = panel.selModule; if not m then return end
            Addon:SetModuleEnabled(m.id, v)
            if v then
                if Addon.active and Addon.active.bossId == m.bossId then Addon:StartModule(m) end
            else
                Addon:StopModule(m)
            end
            RebuildMechs(panel)
        end)
    md.test = DS.MakeButton(md, "Test", 0, 144, 90, 22, function()
        local m = panel.selModule; if not m then return end
        if m.Test then m:Test()
        elseif Addon:IsModuleActive(m.id) then Addon:StopModule(m)
        else Addon:StartModule(m) end
    end)
    md:Hide()
end

PopulateDetail = function(panel)
    local d = panel.detail
    if not panel.selMechKey then d:Hide(); UpdateTimingInfo(panel, nil); return end

    local mech = panel.selMechDef
    local cfg  = Addon:GetMechanicConfig(panel.selMechKey, mech)

    panel._pop = true   -- suppress slider setters while syncing values
    if mech.mode == "cooldown" then d.cdGroup:Show() else d.cdGroup:Hide() end
    if mech.polarityWatch then d.pcGroup:Show() else d.pcGroup:Hide() end
    d:Show()

    d.title:SetText(mech.name)
    d.enable:SetChecked(cfg.enabled)
    d.styleDD:SetValue(STYLE_NAME[cfg.style] or "Timer Bar")
    d.soundBtn:SetText(Addon:GetSoundName(cfg.sound))
    d.scale:SetValue(cfg.scale or 1)
    d.opacity:SetValue(cfg.opacity or 1)
    d.glowS:SetValue(cfg.glowThreshold or 0)
    UpdateTimingInfo(panel, mech)
    if mech.mode == "cooldown" then
        d.cdGroup.winWarn:SetChecked(cfg.winWarning)
        d.cdGroup.winSound:SetChecked(cfg.winSound)
        -- Reminder sub-controls: only for mechanics that define a reminder.
        local g, hasRem = d.cdGroup, (mech.reminder ~= nil)
        g.remSep:SetShown(hasRem); g.remTitle:SetShown(hasRem)
        g.remEnable:SetShown(hasRem); g.remLead:SetShown(hasRem); g.remHint:SetShown(hasRem)
        if hasRem then
            g.remEnable:SetChecked(CurRemCfg(panel).enabled)
            g.remLead:SetValue(CurRemCfg(panel).leadTime or 5)
        end
    end
    if mech.polarityWatch then
        local pg = d.pcGroup
        pg.pcEnable:SetChecked(pg.pcGet("pcEnabled", false))
        pg.pcText:SetChecked(pg.pcGet("pcText", true))
        pg.pcSound:SetChecked(pg.pcGet("pcSound", true))
        pg.pcSoundBtn:SetText(Addon:GetSoundName(pg.pcGet("pcSoundKey", "raidwarning")))
    end

    -- On Cast Notification + Personal Damage Warning: anchor below whichever group
    -- (cooldown+reminder / polarity / neither) is showing above them, then stack the
    -- damage-warning group below on-cast (if on-cast is shown) so they never overlap.
    local L = panel._detailLayout
    local top
    if mech.mode == "cooldown" then
        top = L.groupY + (mech.reminder and 232 or 106) + L.groupGap
    elseif mech.polarityWatch then
        top = L.groupY + 152 + L.groupGap
    else
        top = L.atBottom + L.groupGap
    end

    local oc, ocShown = d.ocGroup, HasOnCast(mech)
    if ocShown then
        oc:ClearAllPoints()
        oc:SetPoint("TOPLEFT", d, "TOPLEFT", 0, -top)
        local occfg = CurCastCfg(panel)
        oc.enable:SetChecked(occfg.enabled)
        oc.scale:SetValue(occfg.scale or 1)
        oc.fontDD:SetValue(Addon:GetFontName(occfg.fontKey))
        oc.fontSize:SetValue(occfg.fontSize or 32)
        oc.soundBtn:SetText(Addon:GetSoundName(occfg.sound))
        oc:Show()
    else
        oc:Hide()
    end

    local dw = d.dmgGroup
    if HasDamageWarning(mech) then
        local dwTop = top + (ocShown and (304 + L.groupGap) or 0)
        dw:ClearAllPoints()
        dw:SetPoint("TOPLEFT", d, "TOPLEFT", 0, -dwTop)
        local dwcfg = CurDmgCfg(panel)
        dw.enable:SetChecked(dwcfg.enabled)
        dw.scale:SetValue(dwcfg.scale or 1)
        dw.fontDD:SetValue(Addon:GetFontName(dwcfg.fontKey))
        dw.fontSize:SetValue(dwcfg.fontSize or 32)
        dw.soundBtn:SetText(Addon:GetSoundName(dwcfg.sound))
        dw:Show()
    else
        dw:Hide()
    end

    panel._pop = false
end

PopulateModuleDetail = function(panel)
    local md = panel.modDetail
    local def = panel.selModule
    UpdateTimingInfo(panel, nil)   -- modules have no CD/firstCast concept here
    if not def then md:Hide(); return end
    md:Show()
    md.title:SetText(def.name)
    md.desc:SetText(def.desc or "")
    md.enable:SetChecked(Addon:IsModuleEnabled(def.id, def))

    -- Per-module config frame (built once, lazily, hosted under the detail buttons).
    if panel._curCfgFrame then panel._curCfgFrame:Hide(); panel._curCfgFrame = nil end
    if def.BuildConfig then
        if not def._cfgFrame then
            local cf = CreateFrame("Frame", nil, md)
            cf:SetPoint("TOPLEFT", md, "TOPLEFT", 0, -184)
            cf:SetPoint("BOTTOMRIGHT", md, "BOTTOMRIGHT", 0, 0)
            def._cfgFrame = cf
            def:BuildConfig(cf)
        end
        if def.RefreshConfig then def:RefreshConfig() end
        def._cfgFrame:Show()
        panel._curCfgFrame = def._cfgFrame
    end
end

-- ── Rebuilds ─────────────────────────────────────────────────────────────────--
RebuildMechs = function(panel)
    local boss    = Addon:GetBoss(panel.selRaid, panel.selBoss)
    local mechs   = (boss and boss.mechanics) or {}
    local modules = Addon:GetBossModules(panel.selRaid, panel.selBoss)

    for _, r in ipairs(panel._mechRows) do r:Hide() end
    for _, r in ipairs(panel._modRows) do r:Hide() end
    panel.mechEmpty:Hide()

    if #mechs == 0 and #modules == 0 then
        panel.mechEmpty:Show()
        panel.selKind = nil
        panel.detail:Hide(); panel.modDetail:Hide()
        return
    end

    -- Build the row list: each mechanic, plus a reminder pseudo-row if it defines one.
    -- (On-cast notification is a sub-setting inside the mechanic's own detail pane —
    -- see HasOnCast/d.ocGroup in PopulateDetail — not a separate list row.)
    local entries = {}
    for _, mech in ipairs(mechs) do
        local key = Addon:MechKey(panel.selRaid, boss.id, mech.id)
        entries[#entries + 1] = { id = mech.id, key = key, def = mech, label = mech.name, isMain = true }
        if mech.reminder then
            entries[#entries + 1] = {
                id = mech.id .. "#rem", key = key .. "#rem", def = mech.reminder,
                label = "   |cff66ccff>|r " .. (mech.reminder.name or "Reminder"),
            }
        end
    end
    panel._entries = entries

    -- Validate / default the current selection.
    local mechValid = false
    if panel.selKind == "mech" then
        for _, e in ipairs(entries) do if e.id == panel.selMechId then mechValid = true break end end
    end
    local moduleValid = false
    if panel.selKind == "module" then
        for _, dmod in ipairs(modules) do if dmod.id == panel.selModuleId then moduleValid = true break end end
    end
    if not mechValid and not moduleValid then
        if #entries > 0 then
            panel.selKind = "mech"; panel.selMechId = entries[1].id
        else
            panel.selKind = "module"; panel.selModuleId = modules[1].id; panel.selModule = modules[1]
        end
    end

    -- Mechanic (+ reminder) rows.
    for i, e in ipairs(entries) do
        local r = panel._mechRows[i]
        if not r then r = MechListRow(panel); panel._mechRows[i] = r end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", panel, "TOPLEFT", MECH_X, -(LIST_Y + (i - 1) * ROW_H))
        local cfg = Addon:GetMechanicConfig(e.key, e.def)
        -- Main mechanic row -> masterEnabled (gates EVERYTHING under this key: Ability
        -- Tracker, On Cast Notification, Personal Damage Warning, reminder, count).
        -- Reminder sub-row -> its OWN "enabled" (unaffected by the master/tracker split).
        local rowField = e.isMain and "masterEnabled" or "enabled"
        local rowOn = e.isMain and cfg.masterEnabled or cfg.enabled
        r.label:SetText(e.label)
        local lit = rowOn and 1 or 0.5
        r.label:SetTextColor(lit, lit, lit)
        r.check:SetChecked(rowOn)
        r.bg:SetColorTexture(0.2, 0.4, 0.8, (panel.selKind == "mech" and e.id == panel.selMechId) and 0.5 or 0)
        r.check:SetScript("OnClick", function(s)
            Addon:SetMechanicOption(e.key, rowField, s:GetChecked() and true or false)
            RebuildMechs(panel)
            if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
        end)
        r:SetScript("OnClick", function()
            panel.selKind = "mech"; panel.selMechId = e.id
            panel.selMechKey = e.key; panel.selMechDef = e.def
            RebuildMechs(panel)
        end)
        r:Show()
    end

    -- Module rows (below the mechanics, with a one-row gap if any rows exist).
    local modBaseY = LIST_Y + (#entries + (#entries > 0 and 1 or 0)) * ROW_H
    for j, def in ipairs(modules) do
        local r = panel._modRows[j]
        if not r then r = MechListRow(panel); panel._modRows[j] = r end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", panel, "TOPLEFT", MECH_X, -(modBaseY + (j - 1) * ROW_H))
        local on = Addon:IsModuleEnabled(def.id, def)
        r.label:SetText("|cff66ccff*|r " .. def.name)
        local lit = on and 1 or 0.5
        r.label:SetTextColor(lit, lit, lit)
        r.check:SetChecked(on)
        r.bg:SetColorTexture(0.2, 0.4, 0.8, (panel.selKind == "module" and def.id == panel.selModuleId) and 0.5 or 0)
        r.check:SetScript("OnClick", function(s)
            Addon:SetModuleEnabled(def.id, s:GetChecked())
            if s:GetChecked() then
                if Addon.active and Addon.active.bossId == def.bossId then Addon:StartModule(def) end
            else
                Addon:StopModule(def)
            end
            RebuildMechs(panel)
        end)
        r:SetScript("OnClick", function()
            panel.selKind = "module"; panel.selModuleId = def.id; panel.selModule = def
            RebuildMechs(panel)
        end)
        r:Show()
    end

    -- Resolve refs + populate the matching detail editor.
    if panel.selKind == "mech" then
        for _, e in ipairs(entries) do
            if e.id == panel.selMechId then
                panel.selMechKey = e.key; panel.selMechDef = e.def
            end
        end
        panel.modDetail:Hide()
        PopulateDetail(panel)
    else
        for _, def in ipairs(modules) do
            if def.id == panel.selModuleId then panel.selModule = def end
        end
        panel.detail:Hide()
        PopulateModuleDetail(panel)
    end
end

RebuildBosses = function(panel)
    local raid = Addon:GetRaid(panel.selRaid)
    local bosses = (raid and raid.bosses) or {}
    LayoutList(panel._bossBtns, panel, BOSS_X, LIST_Y, BOSS_W, bosses,
        function(b) return b.name end,
        function(b) return b.id == panel.selBoss end,
        function(b)
            panel.selBoss = b.id; panel.selKind = nil
            RebuildBosses(panel); RebuildMechs(panel)
            if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
        end)
end

-- ── Per-raid section build / refresh ─────────────────────────────────────────────
-- Each 20/40-man raid is its own Core section: Bosses (left) -> Mechanics (middle)
-- -> Detail editor (right), scoped to that one raid (no raids column).
function Addon:BuildRaidSection(panel, raidId)
    local DS = _G.DaseekiSuite
    panel._bossBtns = {}; panel._mechRows = {}; panel._modRows = {}
    panel.selKind = "mech"
    panel.selRaid = raidId
    local raid = Addon:GetRaid(raidId)
    panel.selBoss = (raid and raid.bosses[1] and raid.bosses[1].id) or "other"

    -- Bartender-style lock toggle: UNCHECK to show all of the selected boss's frames
    -- (draggable); CHECK (default) to lock + hide them. Also locks when the panel closes.
    -- (Master Enable / Sound / Auto-log live in the Raid Mechanics → General section.)
    panel.lockCB = DS.MakeCheckbox(panel, "Lock (placement)", 0, 6,
        function() return Addon.db.settings.locked end,
        function(v)
            if v then Addon:LockAll() else Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
        end)

    -- Lock + clear previews whenever the section is hidden (switch raid/addon / close hub).
    panel:HookScript("OnHide", function() Addon:LockAll() end)

    DS.MakeSeparator(panel, 0, 38, nil, 0)
    DS.MakeLabel(panel, "|cffffffffBosses|r",    14, BOSS_X, HEADER_Y)
    DS.MakeLabel(panel, "|cffffffffMechanics|r", 14, MECH_X, HEADER_Y)
    DS.MakeLabel(panel, "|cffffffffSettings|r",  14, DETAIL_X, HEADER_Y - 22)
    DS.MakeLabel(panel, "|cffffffffTiming|r",    14, TIMING_X, HEADER_Y - 22)

    DS.MakeSeparator(panel, MECH_X - 6,   HEADER_Y, 1, 0):SetHeight(560)
    DS.MakeSeparator(panel, DETAIL_X - 8, HEADER_Y, 1, 0):SetHeight(560)
    DS.MakeSeparator(panel, TIMING_X - 8, HEADER_Y, 1, 0):SetHeight(560)

    panel.mechEmpty = DS.MakeLabel(panel, "No mechanics or modules here yet.", nil, MECH_X, LIST_Y)
    panel.mechEmpty:SetTextColor(0.6, 0.6, 0.6); panel.mechEmpty:Hide()

    BuildDetail(panel)
    RebuildBosses(panel); RebuildMechs(panel)
end

function Addon:RefreshRaidSection(panel)
    if panel._bossBtns then RebuildBosses(panel); RebuildMechs(panel) end
end

-- ── General section (master settings + boss-death sound) ─────────────────────────
function Addon:BuildGeneralOptions(panel)
    local DS = _G.DaseekiSuite
    DS.MakeLabel(panel, "|cffffffffGeneral|r", 15, 8, 8)

    DS.MakeCheckbox(panel, "Enable Raid Mechanics", 8, 42,
        function() return Addon.db.settings.enabled end,
        function(v) Addon.db.settings.enabled = v and true or false end)
    DS.MakeCheckbox(panel, "Sound (master)", 8, 68,
        function() return Addon.db.settings.soundEnabled end,
        function(v) Addon.db.settings.soundEnabled = v and true or false end)
    DS.MakeCheckbox(panel, "Auto-log raids (debug intervals)", 8, 94,
        function() return Addon.db.settings.autoDebug end,
        function(v) Addon.db.settings.autoDebug = v and true or false; Addon:UpdateAutoDebug() end)

    DS.MakeSeparator(panel, 8, 130, 420, 0)
    DS.MakeLabel(panel, "|cffffffffDebug Only|r", nil, 8, 138)
    DS.MakeLabel(panel, "Silences ALL Raid Mechanics output (Ability Tracker, On Cast / Personal", nil, 8, 158)
        :SetTextColor(0.6, 0.6, 0.6)
    DS.MakeLabel(panel, "Damage Notifications, custom widgets, boss-death sound) and just logs", nil, 8, 174)
        :SetTextColor(0.6, 0.6, 0.6)
    DS.MakeLabel(panel, "combat-log events to chat — use this to gather real fight timing data", nil, 8, 190)
        :SetTextColor(0.6, 0.6, 0.6)
    DS.MakeLabel(panel, "without the addon's current (possibly wrong) guesses firing alongside it.", nil, 8, 206)
        :SetTextColor(0.6, 0.6, 0.6)
    DS.MakeCheckbox(panel, "Debug Only", 8, 230,
        function() return Addon.db.settings.debugOnly end,
        function(v)
            Addon.db.settings.debugOnly = v and true or false
            Addon:UpdateAutoDebug()
            print("|cff66ccff[DRM]|r Debug Only " .. (v and "|cff00ff00ON|r — all mechanic output silenced; combat events log while in 20/40-man raids."
                or "|cffff0000OFF|r — mechanics resumed."))
        end)
    DS.MakeButton(panel, "View Debug Log", 8, 256, 130, 22, function()
        -- Re-read the hub live (parity with slash.lua) in case Daseeki Core unloaded.
        local DS2 = _G.DaseekiSuite
        if not (DS2 and DS2.ShowTextDialog) then
            print("|cff66ccff[DRM]|r Install |cffffffffDaseeki Core|r to view the log.")
            return
        end
        local n = Addon:DebugLogLineCount()
        if n == 0 then
            print("|cff66ccff[DRM]|r No debug log captured yet. Enable Debug Only (or |cffffffff/drm debug|r) and pull a boss first.")
        else
            DS2.ShowTextDialog("DRM Debug Log (" .. n .. " lines, all sessions)", Addon:BuildFullDebugLogText(), true)
        end
    end)
    DS.MakeButton(panel, "Clear Log", 146, 256, 100, 22, function()
        if Addon.db then Addon.db.debugLive = {} end
        print("|cff66ccff[DRM]|r Current (live) debug log cleared. Saved sessions kept -- use |cffffffffClear Saved Sessions|r to wipe those too.")
    end)
    -- Wipes all finalized past sittings (same as /drm clearsessions); the live log is kept.
    DS.MakeButton(panel, "Clear Saved Sessions", 252, 256, 160, 22, function()
        if Addon.db then Addon.db.debugSessions = {} end
        print("|cff66ccff[DRM]|r All saved debug sessions cleared. (The current live log is kept -- use |cffffffffClear Log|r for that.)")
    end)

    DS.MakeSeparator(panel, 8, 302, 420, 0)
    DS.MakeLabel(panel, "|cffffffffBoss Death|r", nil, 8, 310)
    DS.MakeLabel(panel, "Play a sound when a boss dies.", nil, 8, 330):SetTextColor(0.6, 0.6, 0.6)
    DS.MakeCheckbox(panel, "Boss-death sound", 8, 350,
        function() return Addon.db.settings.deathSound end,
        function(v) Addon.db.settings.deathSound = v and true or false end)
    DS.MakeLabel(panel, "Sound", nil, 8, 382)
    panel.deathSoundBtn = DS.MakeButton(panel, "None", 64, 378, 150, 22, function()
        Addon:ShowSoundPicker(Addon.db.settings.deathSoundKey or "raidwarning", function(key)
            Addon.db.settings.deathSoundKey = key
            panel.deathSoundBtn:SetText(Addon:GetSoundName(key))
        end, panel.deathSoundBtn)
    end)
    DS.MakeButton(panel, "Test", 220, 378, 56, 22, function()
        Addon:PlaySoundByKey(Addon.db.settings.deathSoundKey or "raidwarning", true)
    end)
end

function Addon:RefreshGeneral(panel)
    if panel.deathSoundBtn then
        panel.deathSoundBtn:SetText(Addon:GetSoundName(Addon.db.settings.deathSoundKey or "raidwarning"))
    end
end

function Addon:RegisterOptions()
    if not _G.DaseekiSuite then return end
    -- General first, then one section per 20/40-man raid (raid.size set). Each raid
    -- tab is a Bosses -> Mechanics -> Detail editor scoped to that raid.
    local sections = {
        { id = "general", title = "General",
          build = function(panel) Addon:BuildGeneralOptions(panel) end,
          refresh = function(panel) Addon:RefreshGeneral(panel) end },
    }
    for _, raid in ipairs(Addon:GetRaids()) do
        if raid.size then
            local rid = raid.id
            sections[#sections + 1] = {
                id = rid, title = raid.name,
                build = function(panel) Addon:BuildRaidSection(panel, rid) end,
                refresh = function(panel) Addon:RefreshRaidSection(panel) end,
            }
        end
    end
    DaseekiSuite:RegisterAddon({
        id    = "raidmechanics",
        title = "Raid Mechanics",
        icon  = "Interface\\Icons\\Spell_Shadow_RaiseDead",
        order = 50,
        sections = sections,
    })
end
