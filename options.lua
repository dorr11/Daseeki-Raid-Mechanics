--[[
    Daseeki Raid Mechanics — options sections for the Daseeki-Core hub.

    Migrated to the DaseekiUI flow API (Core commit 1d7d942). Each section's
    build(flow) receives the flow object; the General section is expressed purely
    through flow rows/checklists (it scrolls for free). The per-raid sections keep
    their 3-column drill-down UX — Bosses -> Mechanics/Modules -> Detail editor —
    but the whole drill-down is one custom flow block that fills the pane and
    reflows on resize, and the detail editor is re-expressed as a DaseekiUI scroll
    pane whose rows/sub-groups stack on a running cursor. That eliminates the old
    magic dynamic-anchor offsets (232/106/152): a shown group simply follows
    whichever group precedes it, and a hidden group collapses to zero height.

    Nothing here uses caller-supplied y-offsets into the shared hub content frame,
    and no colors/fonts are hardcoded — everything reads DaseekiUI theme tokens and
    re-skins live on ThemeChanged. Chat prints route through Addon:Tag/Wrap (core.lua)
    so identity + status words wear the Field Ledger palette when Daseeki-Core is
    present, and fall back to the exact shipped literals when it isn't.

    The SavedVariables schema and every settings key are unchanged from the
    pre-migration panel (same Addon:SetMechanicOption / db.settings field names).
--]]

local _, Addon = ...
local UI = DaseekiUI

-- ── Named layout metrics (single source; no magic literals in the code below) ──
local ROW_H       = 24    -- list row height
local LIST_INSET  = 4     -- scroll viewport inset inside a list host
local COL_GAP     = 10    -- horizontal gap between drill-down columns
local BOSS_W      = 140   -- bosses column width
local MECH_W      = 160   -- mechanics/modules column width
local LOCK_ROW    = 22    -- height reserved for the lock checkbox row
local TOP_STRIP_H = 44    -- lock checkbox + stats line strip
local HDR_H       = 20    -- column-header label strip
local LIST_TOP    = TOP_STRIP_H + HDR_H
local TIMING_H    = 44    -- read-only timing reference strip (top of detail column)
local TIMING_LINE = 18    -- vertical pitch between the two timing rows
local MIN_DRILL_H = 360   -- floor for the drill block height
local MOD_CFG_H   = 560   -- reserved height for a module's own BuildConfig frame
local DETAIL_PAD  = 8     -- inner padding of the detail scroll panes

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

local function rowGap() return (UI.Token and UI.Token("rowGap")) or 10 end

-- Set a DaseekiUI button's caption (MakeButton exposes the FontString as _label).
local function btnText(b, t) if b and b._label then b._label:SetText(t) end end

-- ── Collapsible flow blocks (Armory's conditional-row pattern, generalized) ────
-- After adding any block to a flow, wrap the just-added block so it can collapse
-- to zero height (and swallow its top gap) when not applicable. This is how the
-- detail editor's sub-groups (Window / Reminder / Polarity / On Cast / Damage)
-- appear or vanish with no magic offsets — the running cursor does the stacking.
local function lastHandle(flow)
    local blk = flow.pane.blocks[#flow.pane.blocks]
    local h = { blk = blk, baseGap = blk.topGap, orig = blk.arrange, shown = true }
    blk.arrange = function(width)
        if not h.shown then
            if blk.frame and blk.frame.Hide then blk.frame:Hide() end
            return 0
        end
        if blk.frame and blk.frame.Show then blk.frame:Show() end
        return h.orig(width)
    end
    return h
end
local function setShown(h, on)
    h.shown = on and true or false
    h.blk.topGap = h.shown and h.baseGap or 0
end
local function groupShown(g, on) for _, h in ipairs(g) do setShown(h, on) end end
local function addTo(g, ...) for _, h in ipairs({ ... }) do g[#g + 1] = h end end

-- A separator + accent "sub-header" label; returns their collapse handles.
local function subHeader(flow, text)
    flow:AddSeparator()
    local sepH = lastHandle(flow)
    local lbl = flow:Label(text)
    lbl._label:SetFontObject(UI.fonts.accent)
    return sepH, lastHandle(flow)
end

-- ── Scrollable list host + row factories (token-skinned custom widgets) ────────
local function makeScrollHost(parent)
    local host = UI.FlatFrame(parent, "inset", "border")
    local scroll = CreateFrame("ScrollFrame", nil, host)
    scroll:SetPoint("TOPLEFT", host, "TOPLEFT", LIST_INSET, -LIST_INSET)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -LIST_INSET, LIST_INSET)
    scroll:SetClipsChildren(true)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxs = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxs, cur - delta * 24)))
    end)
    host.child, host.scroll = child, scroll
    return host
end

-- Plain selectable row (bosses list).
local function makeNavRow(child)
    local r = CreateFrame("Button", nil, child)
    r:SetHeight(ROW_H)
    r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:Hide()
    UI.Skin(r.sel, function(self) self:SetColorTexture(UI.Color("accent", 0.28)) end)
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
    UI.Skin(hl, function(self) self:SetColorTexture(UI.Color("accent", 0.10)) end)
    r:SetHighlightTexture(hl)
    r.label = r:CreateFontString(nil, "OVERLAY"); r.label:SetFontObject(UI.fonts.body)
    r.label:SetPoint("LEFT", r, "LEFT", 6, 0); r.label:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.label:SetJustifyH("LEFT"); r.label:SetWordWrap(false)
    return r
end

-- Selectable row with an enable checkbox (mechanics / reminders / modules list).
-- The checkbox toggles enable; clicking anywhere else on the row selects it.
local function makeMechRow(child)
    local r = CreateFrame("Button", nil, child)
    r:SetHeight(ROW_H)
    r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:Hide()
    UI.Skin(r.sel, function(self) self:SetColorTexture(UI.Color("accent", 0.28)) end)
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
    UI.Skin(hl, function(self) self:SetColorTexture(UI.Color("accent", 0.10)) end)
    r:SetHighlightTexture(hl)
    r.cb = UI.MakeCheckbox(r, {})
    r.cb:SetSize(22, ROW_H)
    r.cb:ClearAllPoints(); r.cb:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.label = r:CreateFontString(nil, "OVERLAY"); r.label:SetFontObject(UI.fonts.body)
    r.label:SetPoint("LEFT", r.cb, "RIGHT", 4, 0); r.label:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.label:SetJustifyH("LEFT"); r.label:SetWordWrap(false)
    return r
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

-- Polarity-change accessors (charge FLIP watch). Read/write raw mechanic overrides
-- so the defaults surface without creating db entries just by browsing.
local function pcGet(panel, field, def)
    local o = panel.selMechKey and Addon.db.mechanics[panel.selMechKey]
    if o and o[field] ~= nil then return o[field] end
    return def
end
local function pcSet(panel, field, v)
    if panel.selMechKey then Addon:SetMechanicOption(panel.selMechKey, field, v) end
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
local BuildMechDetail, BuildModuleDetail

-- ── Detail editor: mechanic pane (persistent widgets, repopulated on selection) ─
-- Every widget below reads its current value from the SELECTED mechanic through the
-- Cur* accessors, so the single set of rows serves whichever mechanic is chosen.
-- The conditional sub-groups (cooldown "Window", reminder, polarity, on-cast,
-- personal-damage) collapse when they don't apply; the flow's running cursor makes
-- the ones that remain stack directly under each other.
BuildMechDetail = function(panel)
    local flow = panel._mechFlow
    local d = {}
    panel.detailRefs = d

    d.title = flow:Label("")
    d.title._label:SetFontObject(UI.fonts.header)

    -- ── Sub-section 1: Ability Tracker (always shown for a selected mechanic) ──
    flow:AddSeparator()
    local atl = flow:Label("Ability Tracker")
    atl._label:SetFontObject(UI.fonts.accent)

    -- Ability Tracker's OWN enable (cfg.enabled) — a DIFFERENT field from the
    -- mechanics-list checkbox (masterEnabled, which gates the tracker + on-cast +
    -- damage + reminder + count all at once). This one only suppresses the
    -- tracker's own visual/sound.
    d.enable = flow:Checkbox({
        label = "Enable Ability Tracker",
        get = function() return CurCfg(panel).enabled end,
        set = function(v)
            if not CurKey(panel) then return end
            Addon:SetMechanicOption(CurKey(panel), "enabled", v and true or false)
            RebuildMechs(panel)
            if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
        end,
    })
    d.styleDD = flow:Dropdown({
        label = "Style", width = 180, choices = StyleNames(),
        get = function() return STYLE_NAME[CurCfg(panel).style] or "Timer Bar" end,
        set = function(name) SetMechOpt(panel, "style", STYLE_KEY[name] or "bar") end,
    })
    d.scale = flow:Slider({
        label = "Scale", width = 180, min = 0.5, max = 2.0, step = 0.05,
        get = function() return CurCfg(panel).scale or 1 end,
        set = function(v) if not panel._pop then SetMechOpt(panel, "scale", v) end end,
        format = function(v) return string.format("%.2f", v) end,
    })
    d.opacity = flow:Slider({
        label = "Opacity", width = 180, min = 0.1, max = 1.0, step = 0.05,
        get = function() return CurCfg(panel).opacity or 1 end,
        set = function(v) if not panel._pop then SetMechOpt(panel, "opacity", v) end end,
        format = function(v) return string.format("%.2f", v) end,
    })
    -- Border glow on icon styles when the timer drops below this (0 = off).
    d.glowS = flow:Slider({
        label = "Glow under", width = 180, min = 0, max = 30, step = 1,
        get = function() return CurCfg(panel).glowThreshold or 0 end,
        set = function(v) if not panel._pop then SetMechOpt(panel, "glowThreshold", v) end end,
        format = function(v) return (v == 0) and "Off" or string.format("%ds", v) end,
    })

    local sr = flow:AddRow()
    sr:Label("Sound")
    d.soundBtn = sr:Button({ text = "None", width = 150, onClick = function()
        if not CurKey(panel) then return end
        Addon:ShowSoundPicker(CurCfg(panel).sound, function(key)
            Addon:SetMechanicOption(CurKey(panel), "sound", key)
            btnText(d.soundBtn, Addon:GetSoundName(key))
        end, d.soundBtn)
    end })
    sr:Button({ text = "Test", width = 56, onClick = function()
        Addon:PlaySoundByKey(CurCfg(panel).sound, true)
    end })

    d.resetPos = flow:Button({ text = "Reset Position", width = 120, onClick = function()
        if not CurKey(panel) then return end
        Addon:SetMechanicOption(CurKey(panel), "pos", nil)
        if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
    end })
    d.testAlert = flow:Button({ text = "Test Alert", width = 140, onClick = function()
        if CurKey(panel) then Addon:FireAlert(CurKey(panel), CurDef(panel), true) end
    end })

    -- ── Cooldown "Window" group (mechanics with mode == "cooldown") ──
    d._cdGroup = {}
    local s1, s2 = subHeader(flow, "Window"); addTo(d._cdGroup, s1, s2)
    flow:Hint("When the window opens (icon always glows):"); addTo(d._cdGroup, lastHandle(flow))
    d.winWarn = flow:Checkbox({
        label = "Show warning text",
        get = function() return CurCfg(panel).winWarning end,
        set = function(v) if CurKey(panel) then Addon:SetMechanicOption(CurKey(panel), "winWarning", v and true or false) end end,
    }); addTo(d._cdGroup, lastHandle(flow))
    d.winSound = flow:Checkbox({
        label = "Play sound",
        get = function() return CurCfg(panel).winSound end,
        set = function(v) if CurKey(panel) then Addon:SetMechanicOption(CurKey(panel), "winSound", v and true or false) end end,
    }); addTo(d._cdGroup, lastHandle(flow))

    -- Lead-up "reminder" sub-alert (e.g. Maexxna Snowball). Its own collapse group,
    -- shown only when the mechanic defines a reminder AND is a cooldown mechanic.
    d._remGroup = {}
    local r1, r2 = subHeader(flow, "Reminder"); addTo(d._remGroup, r1, r2)
    d.remEnable = flow:Checkbox({
        label = "Enable lead-up reminder",
        get = function() return CurRemCfg(panel).enabled end,
        set = function(v)
            if not CurRemKey(panel) then return end
            Addon:SetMechanicOption(CurRemKey(panel), "enabled", v and true or false)
            RebuildMechs(panel)
            if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
        end,
    }); addTo(d._remGroup, lastHandle(flow))
    d.remLead = flow:Slider({
        label = "Lead (sec)", width = 180, min = 1, max = 20, step = 1,
        get = function() return CurRemCfg(panel).leadTime or 5 end,
        set = function(v) if not panel._pop and CurRemKey(panel) then Addon:SetMechanicOption(CurRemKey(panel), "leadTime", v) end end,
        format = function(v) return string.format("%ds", v) end,
    }); addTo(d._remGroup, lastHandle(flow))
    flow:Hint("Enabled? Select its row in the list to set icon/scale/sound/position."); addTo(d._remGroup, lastHandle(flow))

    -- ── Polarity-change group (mechanics flagged polarityWatch) ──
    d._pcGroup = {}
    local p1, p2 = subHeader(flow, "Polarity Change Alert"); addTo(d._pcGroup, p1, p2)
    flow:Hint("Fires when your charge FLIPS (+ <-> -), not on refresh."); addTo(d._pcGroup, lastHandle(flow))
    d.pcEnable = flow:Checkbox({
        label = "Enable polarity-change alert",
        get = function() return pcGet(panel, "pcEnabled", false) end,
        set = function(v) pcSet(panel, "pcEnabled", v and true or false) end,
    }); addTo(d._pcGroup, lastHandle(flow))
    d.pcText = flow:Checkbox({
        label = "Center-screen text",
        get = function() return pcGet(panel, "pcText", true) end,
        set = function(v) pcSet(panel, "pcText", v and true or false) end,
    }); addTo(d._pcGroup, lastHandle(flow))
    d.pcSound = flow:Checkbox({
        label = "Play sound",
        get = function() return pcGet(panel, "pcSound", true) end,
        set = function(v) pcSet(panel, "pcSound", v and true or false) end,
    }); addTo(d._pcGroup, lastHandle(flow))
    local pcr = flow:AddRow(); addTo(d._pcGroup, lastHandle(flow))
    pcr:Label("Sound")
    d.pcSoundBtn = pcr:Button({ text = "None", width = 150, onClick = function()
        if not panel.selMechKey then return end
        Addon:ShowSoundPicker(pcGet(panel, "pcSoundKey", "raidwarning"), function(key)
            pcSet(panel, "pcSoundKey", key); btnText(d.pcSoundBtn, Addon:GetSoundName(key))
        end, d.pcSoundBtn)
    end })

    -- ── On Cast Notification group (mechanics that fire on a detectable event) ──
    d._ocGroup = {}
    local o1, o2 = subHeader(flow, "On Cast Notification"); addTo(d._ocGroup, o1, o2)
    flow:Hint("Pops a text banner (top of screen by default) when triggered."); addTo(d._ocGroup, lastHandle(flow))
    d.ocEnable = flow:Checkbox({
        label = "Enable on-cast notification",
        get = function() return CurCastCfg(panel).enabled end,
        set = function(v)
            local k = CurCastKey(panel); if not k then return end
            Addon:SetMechanicOption(k, "enabled", v and true or false)
            if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
        end,
    }); addTo(d._ocGroup, lastHandle(flow))
    d.ocScale = flow:Slider({
        label = "Scale", width = 180, min = 0.5, max = 3.0, step = 0.05,
        get = function() return CurCastCfg(panel).scale or 1 end,
        set = function(v)
            if panel._pop then return end
            local k = CurCastKey(panel); if not k then return end
            Addon:SetMechanicOption(k, "scale", v)
            if Addon:IsUnlocked() then Addon:RefreshPlacement(k, CurCastDef(panel)) end
        end,
        format = function(v) return string.format("%.2f", v) end,
    }); addTo(d._ocGroup, lastHandle(flow))
    d.ocFontDD = flow:Dropdown({
        label = "Font", width = 180, choices = Addon:GetFontNameList(),
        get = function() return Addon:GetFontName(CurCastCfg(panel).fontKey) end,
        set = function(name)
            local k = CurCastKey(panel); if not k then return end
            Addon:SetMechanicOption(k, "fontKey", Addon:GetFontKeyByName(name))
            if Addon:IsUnlocked() then Addon:RefreshPlacement(k, CurCastDef(panel)) end
        end,
    }); addTo(d._ocGroup, lastHandle(flow))
    d.ocFontSize = flow:Slider({
        label = "Font Size", width = 180, min = 12, max = 60, step = 2,
        get = function() return CurCastCfg(panel).fontSize or 32 end,
        set = function(v)
            if panel._pop then return end
            local k = CurCastKey(panel); if not k then return end
            Addon:SetMechanicOption(k, "fontSize", v)
            if Addon:IsUnlocked() then Addon:RefreshPlacement(k, CurCastDef(panel)) end
        end,
        format = function(v) return string.format("%dpt", v) end,
    }); addTo(d._ocGroup, lastHandle(flow))
    local ocr = flow:AddRow(); addTo(d._ocGroup, lastHandle(flow))
    ocr:Label("Sound")
    d.ocSoundBtn = ocr:Button({ text = "None", width = 150, onClick = function()
        local k = CurCastKey(panel); if not k then return end
        Addon:ShowSoundPicker(CurCastCfg(panel).sound, function(key)
            Addon:SetMechanicOption(k, "sound", key)
            btnText(d.ocSoundBtn, Addon:GetSoundName(key))
        end, d.ocSoundBtn)
    end })
    ocr:Button({ text = "Test", width = 56, onClick = function()
        Addon:PlaySoundByKey(CurCastCfg(panel).sound, true)
    end })
    d.ocReset = flow:Button({ text = "Reset Position", width = 120, onClick = function()
        local k = CurCastKey(panel); if not k then return end
        Addon:SetMechanicOption(k, "pos", nil)
        if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
    end }); addTo(d._ocGroup, lastHandle(flow))
    d.ocPreview = flow:Button({ text = "Preview", width = 100, onClick = function()
        local k = CurCastKey(panel); if not k then return end
        Addon:FireAlert(k, CurCastDef(panel), true)
    end }); addTo(d._ocGroup, lastHandle(flow))

    -- ── Personal Damage Warning group (mechanics with a concrete spellID) ──
    d._dmgGroup = {}
    local w1, w2 = subHeader(flow, "Personal Damage Warning"); addTo(d._dmgGroup, w1, w2)
    flow:Hint("Fires when YOU take damage from this ability (e.g. standing in it)."); addTo(d._dmgGroup, lastHandle(flow))
    d.dwEnable = flow:Checkbox({
        label = "Enable damage warning",
        get = function() return CurDmgCfg(panel).enabled end,
        set = function(v)
            local k = CurDmgKey(panel); if not k then return end
            Addon:SetMechanicOption(k, "enabled", v and true or false)
            if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
        end,
    }); addTo(d._dmgGroup, lastHandle(flow))
    d.dwScale = flow:Slider({
        label = "Scale", width = 180, min = 0.5, max = 3.0, step = 0.05,
        get = function() return CurDmgCfg(panel).scale or 1 end,
        set = function(v)
            if panel._pop then return end
            local k = CurDmgKey(panel); if not k then return end
            Addon:SetMechanicOption(k, "scale", v)
            if Addon:IsUnlocked() then Addon:RefreshPlacement(k, CurDmgDef(panel)) end
        end,
        format = function(v) return string.format("%.2f", v) end,
    }); addTo(d._dmgGroup, lastHandle(flow))
    d.dwFontDD = flow:Dropdown({
        label = "Font", width = 180, choices = Addon:GetFontNameList(),
        get = function() return Addon:GetFontName(CurDmgCfg(panel).fontKey) end,
        set = function(name)
            local k = CurDmgKey(panel); if not k then return end
            Addon:SetMechanicOption(k, "fontKey", Addon:GetFontKeyByName(name))
            if Addon:IsUnlocked() then Addon:RefreshPlacement(k, CurDmgDef(panel)) end
        end,
    }); addTo(d._dmgGroup, lastHandle(flow))
    d.dwFontSize = flow:Slider({
        label = "Font Size", width = 180, min = 12, max = 60, step = 2,
        get = function() return CurDmgCfg(panel).fontSize or 32 end,
        set = function(v)
            if panel._pop then return end
            local k = CurDmgKey(panel); if not k then return end
            Addon:SetMechanicOption(k, "fontSize", v)
            if Addon:IsUnlocked() then Addon:RefreshPlacement(k, CurDmgDef(panel)) end
        end,
        format = function(v) return string.format("%dpt", v) end,
    }); addTo(d._dmgGroup, lastHandle(flow))
    local dwr = flow:AddRow(); addTo(d._dmgGroup, lastHandle(flow))
    dwr:Label("Sound")
    d.dwSoundBtn = dwr:Button({ text = "None", width = 150, onClick = function()
        local k = CurDmgKey(panel); if not k then return end
        Addon:ShowSoundPicker(CurDmgCfg(panel).sound, function(key)
            Addon:SetMechanicOption(k, "sound", key)
            btnText(d.dwSoundBtn, Addon:GetSoundName(key))
        end, d.dwSoundBtn)
    end })
    dwr:Button({ text = "Test", width = 56, onClick = function()
        Addon:PlaySoundByKey(CurDmgCfg(panel).sound, true)
    end })
    d.dwReset = flow:Button({ text = "Reset Position", width = 120, onClick = function()
        local k = CurDmgKey(panel); if not k then return end
        Addon:SetMechanicOption(k, "pos", nil)
        if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
    end }); addTo(d._dmgGroup, lastHandle(flow))
    d.dwPreview = flow:Button({ text = "Preview", width = 100, onClick = function()
        local k = CurDmgKey(panel); if not k then return end
        Addon:FireAlert(k, CurDmgDef(panel), true)
    end }); addTo(d._dmgGroup, lastHandle(flow))
end

PopulateDetail = function(panel)
    local d = panel.detailRefs
    local mech = panel.selMechDef
    if not panel.selMechKey or not mech then
        panel._mechPane:Hide(); UpdateTimingInfo(panel, nil); return
    end
    local cfg = Addon:GetMechanicConfig(panel.selMechKey, mech)

    panel._pop = true   -- suppress slider setters while syncing values
    d.title._label:SetText(mech.name)
    d.enable:Refresh()
    d.styleDD.Refresh()
    d.scale.Refresh(); d.opacity.Refresh(); d.glowS.Refresh()
    btnText(d.soundBtn, Addon:GetSoundName(cfg.sound))
    UpdateTimingInfo(panel, mech)

    local isCd   = mech.mode == "cooldown"
    local hasRem = isCd and (mech.reminder ~= nil)
    groupShown(d._cdGroup, isCd)
    groupShown(d._remGroup, hasRem)
    if isCd then d.winWarn:Refresh(); d.winSound:Refresh() end
    if hasRem then d.remEnable:Refresh(); d.remLead.Refresh() end

    local isPolarity = mech.polarityWatch and true or false
    groupShown(d._pcGroup, isPolarity)
    if isPolarity then
        d.pcEnable:Refresh(); d.pcText:Refresh(); d.pcSound:Refresh()
        btnText(d.pcSoundBtn, Addon:GetSoundName(pcGet(panel, "pcSoundKey", "raidwarning")))
    end

    local ocShown = HasOnCast(mech)
    groupShown(d._ocGroup, ocShown)
    if ocShown then
        d.ocEnable:Refresh(); d.ocScale.Refresh(); d.ocFontDD.Refresh(); d.ocFontSize.Refresh()
        btnText(d.ocSoundBtn, Addon:GetSoundName(CurCastCfg(panel).sound))
    end

    local dwShown = HasDamageWarning(mech)
    groupShown(d._dmgGroup, dwShown)
    if dwShown then
        d.dwEnable:Refresh(); d.dwScale.Refresh(); d.dwFontDD.Refresh(); d.dwFontSize.Refresh()
        btnText(d.dwSoundBtn, Addon:GetSoundName(CurDmgCfg(panel).sound))
    end

    panel._mechPane:Show()
    panel._mechPane:Layout()
    panel._pop = false
end

-- ── Detail editor: module pane ────────────────────────────────────────────────
BuildModuleDetail = function(panel)
    local flow = panel._modFlow
    local m = {}
    panel.modRefs = m

    m.title = flow:Label("")
    m.title._label:SetFontObject(UI.fonts.header)
    m.desc = flow:Hint("")
    m.enable = flow:Checkbox({
        label = "Enable this module",
        get = function() local def = panel.selModule; return def and Addon:IsModuleEnabled(def.id, def) end,
        set = function(v)
            local def = panel.selModule; if not def then return end
            Addon:SetModuleEnabled(def.id, v)
            if v then
                if Addon.active and Addon.active.bossId == def.bossId then Addon:StartModule(def) end
            else
                Addon:StopModule(def)
            end
            RebuildMechs(panel)
        end,
    })
    m.test = flow:Button({ text = "Test", width = 90, onClick = function()
        local def = panel.selModule; if not def then return end
        if def.Test then def:Test()
        elseif Addon:IsModuleActive(def.id) then Addon:StopModule(def)
        else Addon:StartModule(def) end
    end })

    -- Host block for a module's own BuildConfig frame (built lazily per module).
    -- Reserves MOD_CFG_H when a config exists, or 0 (collapsed) when it doesn't.
    local host = CreateFrame("Frame", nil, flow.pane.child)
    host._fillWidth = true
    host._h = 0
    host.arrange = function(width) host:SetWidth(width); return host._h or 0 end
    flow.pane:AddBlock(host, host.arrange, rowGap(), 0)
    m.cfgHost = host
end

PopulateModuleDetail = function(panel)
    local m = panel.modRefs
    local def = panel.selModule
    UpdateTimingInfo(panel, nil)   -- modules have no CD/firstCast concept here
    if not def then panel._modPane:Hide(); return end

    m.title._label:SetText(def.name)
    m.desc._label:SetText(def.desc or "")
    m.enable:Refresh()

    -- Per-module config frame (built once, lazily, hosted under the buttons). The
    -- module's BuildConfig lays out its own controls into cf with its private
    -- offsets (mod_*.lua, untouched); we only supply and size the host.
    if panel._curCfgFrame then panel._curCfgFrame:Hide(); panel._curCfgFrame = nil end
    m.cfgHost._h = 0
    if def.BuildConfig then
        if not def._cfgFrame then
            local cf = CreateFrame("Frame", nil, m.cfgHost)
            cf:SetPoint("TOPLEFT", m.cfgHost, "TOPLEFT", 0, 0)
            cf:SetPoint("TOPRIGHT", m.cfgHost, "TOPRIGHT", 0, 0)
            cf:SetHeight(MOD_CFG_H)
            def._cfgFrame = cf
            def:BuildConfig(cf)
        end
        if def.RefreshConfig then def:RefreshConfig() end
        def._cfgFrame:Show()
        panel._curCfgFrame = def._cfgFrame
        m.cfgHost._h = MOD_CFG_H
    end

    panel._modPane:Show()
    panel._modPane:Layout()
end

-- ── Rebuilds ─────────────────────────────────────────────────────────────────--
RebuildMechs = function(panel)
    local boss    = Addon:GetBoss(panel.selRaid, panel.selBoss)
    local mechs   = (boss and boss.mechanics) or {}
    local modules = Addon:GetBossModules(panel.selRaid, panel.selBoss)
    local child   = panel.mechHost.child

    -- Selected boss's kill-stats strip (recorded by engine.lua's Disengage). Peeks
    -- at db.stats without creating entries; hidden when nothing is recorded yet.
    if panel.statsLine then
        local rs = Addon.db.stats and Addon.db.stats[panel.selRaid]
        local s  = rs and rs[panel.selBoss]
        if s and ((s.kills or 0) > 0 or (s.wipes or 0) > 0) then
            local txt = string.format("%s \226\128\148 Kills %d \194\183 Wipes %d",
                (boss and boss.name) or panel.selBoss, s.kills or 0, s.wipes or 0)
            if s.bestTime and Addon.FmtStatsTime then
                txt = txt .. " \194\183 Best " .. Addon.FmtStatsTime(s.bestTime)
            end
            panel.statsLine:SetText(txt)
            panel.statsLine:Show()
        else
            panel.statsLine:Hide()
        end
    end

    for _, r in ipairs(panel._mechRows) do r:Hide() end
    for _, r in ipairs(panel._modRows) do r:Hide() end
    panel.mechEmpty:Hide()

    if #mechs == 0 and #modules == 0 then
        panel.mechEmpty:Show()
        panel.selKind = nil
        panel._mechPane:Hide(); panel._modPane:Hide()
        child:SetHeight(1)
        return
    end

    -- Build the row list: each mechanic, plus a reminder pseudo-row if it defines one.
    -- (On-cast notification is a sub-setting inside the mechanic's own detail pane —
    -- see HasOnCast/d._ocGroup in PopulateDetail — not a separate list row.)
    local entries = {}
    for _, mech in ipairs(mechs) do
        local key = Addon:MechKey(panel.selRaid, boss.id, mech.id)
        entries[#entries + 1] = { id = mech.id, key = key, def = mech, label = mech.name, isMain = true }
        if mech.reminder then
            entries[#entries + 1] = {
                id = mech.id .. "#rem", key = key .. "#rem", def = mech.reminder,
                label = "   \194\187 " .. (mech.reminder.name or "Reminder"),
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
        if not r then r = makeMechRow(child); panel._mechRows[i] = r end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT",  child, "TOPLEFT",  0, -((i - 1) * ROW_H))
        r:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -((i - 1) * ROW_H))
        -- Main mechanic row -> masterEnabled (gates EVERYTHING under this key). The
        -- reminder sub-row -> its OWN "enabled".
        local rowField = e.isMain and "masterEnabled" or "enabled"
        r.label:SetText(e.label)
        r.cb._get = function()
            local cfg = Addon:GetMechanicConfig(e.key, e.def)
            return e.isMain and cfg.masterEnabled or cfg.enabled
        end
        r.cb._set = function(v)
            Addon:SetMechanicOption(e.key, rowField, v and true or false)
            RebuildMechs(panel)
            if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
        end
        r.cb:Refresh()
        local on = r.cb._get()
        r.label:SetTextColor(UI.Color(on and "text" or "faint"))
        r.sel:SetShown(panel.selKind == "mech" and e.id == panel.selMechId)
        r:SetScript("OnClick", function()
            panel.selKind = "mech"; panel.selMechId = e.id
            panel.selMechKey = e.key; panel.selMechDef = e.def
            RebuildMechs(panel)
        end)
        r:Show()
    end

    -- Module rows (below the mechanics, with a one-row gap if any rows exist).
    local modBase = (#entries + (#entries > 0 and 1 or 0)) * ROW_H
    for j, def in ipairs(modules) do
        local r = panel._modRows[j]
        if not r then r = makeMechRow(child); panel._modRows[j] = r end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT",  child, "TOPLEFT",  0, -(modBase + (j - 1) * ROW_H))
        r:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -(modBase + (j - 1) * ROW_H))
        r.label:SetText("* " .. def.name)
        r.cb._get = function() return Addon:IsModuleEnabled(def.id, def) end
        r.cb._set = function(v)
            Addon:SetModuleEnabled(def.id, v)
            if v then
                if Addon.active and Addon.active.bossId == def.bossId then Addon:StartModule(def) end
            else
                Addon:StopModule(def)
            end
            RebuildMechs(panel)
        end
        r.cb:Refresh()
        local on = r.cb._get()
        r.label:SetTextColor(UI.Color(on and "text" or "faint"))
        r.sel:SetShown(panel.selKind == "module" and def.id == panel.selModuleId)
        r:SetScript("OnClick", function()
            panel.selKind = "module"; panel.selModuleId = def.id; panel.selModule = def
            RebuildMechs(panel)
        end)
        r:Show()
    end

    child:SetHeight(math.max(1, modBase + #modules * ROW_H))

    -- Resolve refs + populate the matching detail editor.
    if panel.selKind == "mech" then
        for _, e in ipairs(entries) do
            if e.id == panel.selMechId then
                panel.selMechKey = e.key; panel.selMechDef = e.def
            end
        end
        panel._modPane:Hide()
        PopulateDetail(panel)
    else
        for _, def in ipairs(modules) do
            if def.id == panel.selModuleId then panel.selModule = def end
        end
        panel._mechPane:Hide()
        PopulateModuleDetail(panel)
    end
end

RebuildBosses = function(panel)
    local raid   = Addon:GetRaid(panel.selRaid)
    local bosses = (raid and raid.bosses) or {}
    local child  = panel.bossHost.child
    for _, b in ipairs(panel._bossBtns) do b:Hide() end
    for i, boss in ipairs(bosses) do
        local r = panel._bossBtns[i]
        if not r then r = makeNavRow(child); panel._bossBtns[i] = r end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT",  child, "TOPLEFT",  0, -((i - 1) * ROW_H))
        r:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -((i - 1) * ROW_H))
        r.label:SetText(boss.name)
        local selc = boss.id == panel.selBoss
        r.label:SetTextColor(UI.Color(selc and "accent" or "text"))
        r.sel:SetShown(selc)
        r:SetScript("OnClick", function()
            panel.selBoss = boss.id; panel.selKind = nil
            RebuildBosses(panel); RebuildMechs(panel)
            if Addon:IsUnlocked() then Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
        end)
        r:Show()
    end
    child:SetHeight(math.max(1, #bosses * ROW_H))
end

-- ── Per-raid section build / refresh ─────────────────────────────────────────────
-- Each 20/40-man raid is its own Core flow section. The whole drill-down (Bosses ->
-- Mechanics/Modules -> Detail editor, scoped to that raid) is a single custom flow
-- block that fills the pane and reflows on resize — so the pane's own scroll never
-- pans the lists away, while the detail editor scrolls independently.
-- Section state lives on the flow object, registered here so the Refresh* helpers
-- can find it — the hub passes its own scroll-child frame (not the flow) to
-- refresh(), so refresh looks the panel up by section instead of using its arg
-- (same convention as the merged Armory / Raid-Prep migrations).
Addon.optFrames = Addon.optFrames or {}

function Addon:BuildRaidSection(flow, raidId)
    local panel = flow
    Addon.optFrames[raidId] = flow
    panel.selKind = "mech"
    panel.selRaid = raidId
    panel._bossBtns = {}; panel._mechRows = {}; panel._modRows = {}
    local raid = Addon:GetRaid(raidId)
    panel.selBoss = (raid and raid.bosses[1] and raid.bosses[1].id) or "other"

    -- Lock + clear previews whenever the section is hidden (switch raid/addon / close
    -- hub). flow.pane is the frame the hub hides on section switch.
    flow.pane:HookScript("OnHide", function() Addon:LockAll() end)

    local drill = CreateFrame("Frame", nil, flow.pane.child)
    drill._fillWidth = true

    -- Top strip: Bartender-style lock toggle + the selected boss's kill-stats line.
    -- (Master Enable / Sound / Auto-log live in the Raid Mechanics -> General section.)
    panel.lockCB = UI.MakeCheckbox(drill, {
        label = "Lock (placement)",
        get = function() return Addon.db.settings.locked end,
        set = function(v)
            if v then Addon:LockAll() else Addon:UnlockBoss(panel.selRaid, panel.selBoss) end
        end,
    })
    panel.lockCB:SetPoint("TOPLEFT", drill, "TOPLEFT", 0, 0)

    panel.statsLine = drill:CreateFontString(nil, "OVERLAY")
    panel.statsLine:SetFontObject(UI.fonts.small)
    panel.statsLine:SetPoint("TOPLEFT", drill, "TOPLEFT", 0, -LOCK_ROW)
    panel.statsLine:SetJustifyH("LEFT")
    panel.statsLine:Hide()

    -- Column headers.
    local function hdr(text) local fs = drill:CreateFontString(nil, "OVERLAY"); fs:SetFontObject(UI.fonts.accent); fs:SetText(text); return fs end
    local bossHdr = hdr("Bosses")
    local mechHdr = hdr("Mechanics")
    local setHdr  = hdr("Settings")

    -- Boss + mechanic lists (fixed-width columns; token-skinned scroll hosts).
    panel.bossHost = makeScrollHost(drill)
    panel.bossHost.child:SetWidth(BOSS_W - 2 * LIST_INSET)
    panel.mechHost = makeScrollHost(drill)
    panel.mechHost.child:SetWidth(MECH_W - 2 * LIST_INSET)

    panel.mechEmpty = panel.mechHost.child:CreateFontString(nil, "OVERLAY")
    panel.mechEmpty:SetFontObject(UI.fonts.muted)
    panel.mechEmpty:SetPoint("TOPLEFT", panel.mechHost.child, "TOPLEFT", 2, 0)
    panel.mechEmpty:SetPoint("TOPRIGHT", panel.mechHost.child, "TOPRIGHT", -2, 0)
    panel.mechEmpty:SetJustifyH("LEFT"); panel.mechEmpty:SetText("No mechanics or modules here yet.")
    panel.mechEmpty:Hide()

    -- Read-only Timing reference (CD from start / CD) — always visible at the top of
    -- the detail column, outside the detail scroll, so it stays put as you scroll.
    local timing = CreateFrame("Frame", nil, drill)
    local function tlabel(text, muted) local fs = timing:CreateFontString(nil, "OVERLAY"); fs:SetFontObject(muted and UI.fonts.muted or UI.fonts.accent); fs:SetText(text); return fs end
    local tf1 = tlabel("CD from start", true); tf1:SetPoint("TOPLEFT", timing, "TOPLEFT", 0, 0)
    local tv1 = tlabel("\226\128\148", false); tv1:SetPoint("TOPRIGHT", timing, "TOPRIGHT", 0, 0)
    local tf2 = tlabel("CD", true); tf2:SetPoint("TOPLEFT", timing, "TOPLEFT", 0, -TIMING_LINE)
    local tv2 = tlabel("\226\128\148", false); tv2:SetPoint("TOPRIGHT", timing, "TOPRIGHT", 0, -TIMING_LINE)
    panel.timingInfo = { fromStart = tv1, cd = tv2 }

    -- Detail host: two overlapping scroll panes (mechanic + module), one shown at a
    -- time. Each pane's flow re-expresses the old dynamic-anchor stack.
    local detailHost = CreateFrame("Frame", nil, drill)
    panel._mechPane = UI.CreatePane(detailHost, { padX = DETAIL_PAD, padTop = DETAIL_PAD, padBottom = DETAIL_PAD })
    panel._mechFlow = panel._mechPane.flow
    panel._modPane  = UI.CreatePane(detailHost, { padX = DETAIL_PAD, padTop = DETAIL_PAD, padBottom = DETAIL_PAD })
    panel._modFlow  = panel._modPane.flow
    BuildMechDetail(panel)
    BuildModuleDetail(panel)
    panel._modPane:Hide()

    -- One block that fills the whole pane; lays the columns out at computed offsets
    -- (all y-offsets are negated named metrics — no literal offsets, resize-safe).
    drill.arrange = function(width)
        local vh = flow.pane.scroll:GetHeight()
        local H = math.max(MIN_DRILL_H, (vh or 0) - flow.pane._padTop - flow.pane._padBot)
        drill:SetSize(width, H)

        bossHdr:ClearAllPoints(); bossHdr:SetPoint("TOPLEFT", drill, "TOPLEFT", 0, -TOP_STRIP_H)
        mechHdr:ClearAllPoints(); mechHdr:SetPoint("TOPLEFT", drill, "TOPLEFT", BOSS_W + COL_GAP, -TOP_STRIP_H)
        local detailX = BOSS_W + COL_GAP + MECH_W + COL_GAP
        setHdr:ClearAllPoints(); setHdr:SetPoint("TOPLEFT", drill, "TOPLEFT", detailX, -TOP_STRIP_H)

        local colH = math.max(1, H - LIST_TOP)
        panel.bossHost:ClearAllPoints()
        panel.bossHost:SetPoint("TOPLEFT", drill, "TOPLEFT", 0, -LIST_TOP)
        panel.bossHost:SetSize(BOSS_W, colH)
        panel.mechHost:ClearAllPoints()
        panel.mechHost:SetPoint("TOPLEFT", drill, "TOPLEFT", BOSS_W + COL_GAP, -LIST_TOP)
        panel.mechHost:SetSize(MECH_W, colH)

        local detailW = math.max(1, width - detailX)
        timing:ClearAllPoints()
        timing:SetPoint("TOPLEFT", drill, "TOPLEFT", detailX, -LIST_TOP)
        timing:SetSize(detailW, TIMING_H)
        detailHost:ClearAllPoints()
        detailHost:SetPoint("TOPLEFT", drill, "TOPLEFT", detailX, -(LIST_TOP + TIMING_H))
        detailHost:SetSize(detailW, math.max(1, colH - TIMING_H))
        return H
    end
    flow.pane:AddBlock(drill, drill.arrange, 0, 0)

    RebuildBosses(panel)
    RebuildMechs(panel)
end

function Addon:RefreshRaidSection(raidId)
    local panel = Addon.optFrames and Addon.optFrames[raidId]
    if panel and panel._bossBtns then RebuildBosses(panel); RebuildMechs(panel) end
end

-- ── General section (master settings + boss-death sound + alerts/pull) ────────────
function Addon:BuildGeneralOptions(flow)
    local panel = flow
    Addon.optFrames.general = flow

    local gen = flow:AddSection("General")
    gen:Checkbox({
        label = "Enable Raid Mechanics",
        get = function() return Addon.db.settings.enabled end,
        set = function(v) Addon.db.settings.enabled = v and true or false end,
    })
    gen:Checkbox({
        label = "Sound (master)",
        get = function() return Addon.db.settings.soundEnabled end,
        set = function(v) Addon.db.settings.soundEnabled = v and true or false end,
    })
    gen:Checkbox({
        label = "Auto-log raids (debug intervals)",
        get = function() return Addon.db.settings.autoDebug end,
        set = function(v) Addon.db.settings.autoDebug = v and true or false; Addon:UpdateAutoDebug() end,
    })

    local dbg = flow:AddSection("Debug Only")
    dbg:Hint("Silences ALL Raid Mechanics output (Ability Tracker, On Cast / Personal Damage "
        .. "Notifications, custom widgets, boss-death sound) and just logs combat-log events to "
        .. "chat - use this to gather real fight timing data without the addon's current "
        .. "(possibly wrong) guesses firing alongside it.")
    dbg:Checkbox({
        label = "Debug Only",
        get = function() return Addon.db.settings.debugOnly end,
        set = function(v)
            Addon.db.settings.debugOnly = v and true or false
            Addon:UpdateAutoDebug()
            print(Addon:Tag("[DRM]") .. " Debug Only " .. (v and (Addon:Wrap("ok", "ON") .. " - all mechanic output silenced; combat events log while in 20/40-man raids.")
                or (Addon:Wrap("danger", "OFF") .. " - mechanics resumed.")))
        end,
    })
    local dbgRow = dbg:AddRow()
    dbgRow:Button({ text = "View Debug Log", width = 130, onClick = function()
        -- Re-read the hub live (parity with slash.lua) in case Daseeki Core unloaded.
        local DS2 = _G.DaseekiSuite
        if not (DS2 and DS2.ShowTextDialog) then
            print(Addon:Tag("[DRM]") .. " Install " .. Addon:Wrap("text", "Daseeki Core") .. " to view the log.")
            return
        end
        local n = Addon:DebugLogLineCount()
        if n == 0 then
            print(Addon:Tag("[DRM]") .. " No debug log captured yet. Enable Debug Only (or " .. Addon:Wrap("text", "/drm debug") .. ") and pull a boss first.")
        else
            DS2.ShowTextDialog("DRM Debug Log (" .. n .. " lines, all sessions)", Addon:BuildFullDebugLogText(), true)
        end
    end })
    dbgRow:Button({ text = "Clear Log", width = 100, onClick = function()
        if Addon.db then Addon.db.debugLive = {} end
        print(Addon:Tag("[DRM]") .. " Current (live) debug log cleared. Saved sessions kept -- use " .. Addon:Wrap("text", "Clear Saved Sessions") .. " to wipe those too.")
    end })
    -- Wipes all finalized past sittings (same as /drm clearsessions); the live log is kept.
    dbgRow:Button({ text = "Clear Saved Sessions", width = 160, onClick = function()
        if Addon.db then Addon.db.debugSessions = {} end
        print(Addon:Tag("[DRM]") .. " All saved debug sessions cleared. (The current live log is kept -- use " .. Addon:Wrap("text", "Clear Log") .. " for that.)")
    end })

    local bd = flow:AddSection("Boss Death")
    bd:Hint("Play a sound when a boss dies.")
    bd:Checkbox({
        label = "Boss-death sound",
        get = function() return Addon.db.settings.deathSound end,
        set = function(v) Addon.db.settings.deathSound = v and true or false end,
    })
    local bdRow = bd:AddRow()
    bdRow:Label("Sound")
    panel.deathSoundBtn = bdRow:Button({ text = "None", width = 150, onClick = function()
        Addon:ShowSoundPicker(Addon.db.settings.deathSoundKey or "raidwarning", function(key)
            Addon.db.settings.deathSoundKey = key
            btnText(panel.deathSoundBtn, Addon:GetSoundName(key))
        end, panel.deathSoundBtn)
    end })
    bdRow:Button({ text = "Test", width = 56, onClick = function()
        Addon:PlaySoundByKey(Addon.db.settings.deathSoundKey or "raidwarning", true)
    end })

    -- Alerts & Pull: special-warning tier + voice countdown (E1) and the pull-timer
    -- / DBM pull mirroring (E2). Toggles use ~= false semantics (default ON).
    local ap = flow:AddSection("Alerts & Pull")
    ap:Hint("Special-warning banner, voice countdowns, and the pull-timer bar (/drm pull).")
    ap:Checkbox({
        label = "Special warnings (big center text + screen flash)",
        get = function() return Addon.db.settings.specialWarnings ~= false end,
        set = function(v) Addon.db.settings.specialWarnings = v and true or false end,
    })
    ap:Checkbox({
        label = "Voice countdown near ability windows",
        get = function() return Addon.db.settings.countdownVoice ~= false end,
        set = function(v) Addon.db.settings.countdownVoice = v and true or false end,
    })
    -- The countdown VOICE PACK picker moved to the Sounds section in W5 (all pack
    -- choices in one place; DREW_UI_STYLE principle 2 — related things sit together).
    -- What stays here is the end-to-end preview, because what it previews is the PULL
    -- TIMER, which is this section's subject: countdown bar + voice count + "PULL!".
    local vrow = ap:AddRow()
    vrow:Label("Preview the pull sequence")
    vrow:Button({ text = "Test", width = 70, onClick = function()
        Addon:StartPullTimer(5, "test")
    end })
    ap:Checkbox({
        label = "Mirror DBM pull timers",
        get = function() return Addon.db.settings.mirrorDBMPull ~= false end,
        set = function(v) Addon.db.settings.mirrorDBMPull = v and true or false end,
    })

    Addon:BuildBarOptions(flow, panel)
    Addon:BuildWarningOptions(flow, panel)
    Addon:BuildSoundOptions(flow, panel)
    Addon:BuildTelemetryOptions(flow, panel)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  W5 — TIMER BARS
-- ══════════════════════════════════════════════════════════════════════════════
-- ui_bars.lua owns two anchors (small / large) and one settings table; this is the
-- surface for both. DREW_UI_STYLE: fixed-width bands (the sliders are a single
-- SLIDER_W, the segmented pickers a single SEG_W), every control labelled, the two
-- anchors laid out as one grid rather than two ragged stacks, and the placement
-- affordances (anchors / demo) sit with the thing they place.
local SLIDER_W = 210

function Addon:BuildBarOptions(flow, panel)
    local B = Addon.Bars
    if not B then return end
    local function S() return B.Settings() end

    local sec = flow:AddSection("Timer Bars")
    sec:Hint("Countdown bars for boss abilities. Two lists: SMALL is the normal stack, "
        .. "LARGE holds the bars the encounter marked important (and the pull timer). "
        .. "Use Show anchors below to drag either list where you want it.")

    sec:Checkbox({
        label = "Hide all timer bars",
        get = function() return S().hideAll and true or false end,
        set = function(v) S().hideAll = v and true or false end,
    })

    -- Size band. Bar width/height are top-level settings (barWidth/barHeight) that
    -- shipped in 1.x and are read by Bars.Size — kept on those exact keys so an
    -- existing user's sizing survives the rebuild untouched.
    local szRow = sec:AddRow()
    szRow:Slider({
        label = "Bar width", width = SLIDER_W, min = 120, max = 400, step = 5,
        format = function(v) return ("%dpx"):format(v) end,
        get = function() return Addon.db.settings.barWidth or 200 end,
        set = function(v) Addon.db.settings.barWidth = math.floor(v + 0.5) end,
    })
    szRow:Slider({
        label = "Bar height", width = SLIDER_W, min = 10, max = 40, step = 1,
        format = function(v) return ("%dpx"):format(v) end,
        get = function() return Addon.db.settings.barHeight or 20 end,
        set = function(v) Addon.db.settings.barHeight = math.floor(v + 0.5) end,
    })
    local padRow = sec:AddRow()
    padRow:Slider({
        label = "Gap between bars", width = SLIDER_W, min = 0, max = 12, step = 1,
        format = function(v) return ("%dpx"):format(v) end,
        get = function() return S().pad or 2 end,
        set = function(v) S().pad = math.floor(v + 0.5) end,
    })
    padRow:Slider({
        label = "Enlarge below", width = SLIDER_W, min = 0, max = 30, step = 1,
        format = function(v) return v > 0 and ("%ds left"):format(v) or "off" end,
        get = function() return S().enlargeAt or 0 end,
        set = function(v) S().enlargeAt = math.floor(v + 0.5) end,
    })

    -- ONE GRID for the two anchors (principle 5): each list gets a titled block with
    -- the SAME two controls in the SAME order, so the two blocks read as one grid.
    --
    -- The controls are NOT paired with bare Label row-items. UI.MakeLabel sets no
    -- uiWidth, so the flow row measures it with GetWidth() — which is 0 for a frame
    -- that never had a width set — and a "column header" built that way does not
    -- reliably line up with the control beneath it. Column headers over columnar
    -- controls is principle 6, so the honest way to satisfy it here is a titled block
    -- per list plus segment captions that say what they are: Up/Down is manifestly a
    -- growth direction and Soonest/Latest is manifestly a sort order.
    sec:AddSeparator()
    local function anchorBlock(title, field, defGrow)
        sec:Label(title)
        local r = sec:AddRow()
        r:SegmentedChoice({
            compact = true,
            choices = { { value = "UP", text = "Grows up" }, { value = "DOWN", text = "Grows down" } },
            get = function()
                local t = S()[field]; return (t and t.grow) or defGrow
            end,
            set = function(v)
                local t = S()[field]; if t then t.grow = v end
            end,
        })
        r:SegmentedChoice({
            compact = true,
            choices = { { value = "asc", text = "Soonest first" }, { value = "desc", text = "Latest first" } },
            get = function()
                local t = S()[field]; return (t and t.sort) or "asc"
            end,
            set = function(v)
                local t = S()[field]; if t then t.sort = v end
            end,
        })
    end
    anchorBlock("Small bars \226\128\148 the normal stack", "small", "DOWN")
    anchorBlock("Large bars \226\128\148 important abilities and the pull timer", "large", "UP")

    sec:AddSeparator()
    sec:Checkbox({
        label = "Show spell icons on bars",
        get = function() return S().icons and true or false end,
        set = function(v) S().icons = v and true or false end,
    })
    sec:Checkbox({
        label = "Show variance windows (a shaded band for \"between X and Y seconds\")",
        get = function() return S().variance and true or false end,
        set = function(v)
            S().variance = v and true or false
            if B.PushVarianceOption then B.PushVarianceOption() end
        end,
    })
    sec:Checkbox({
        label = "Variance countdown reaches zero at the EARLIEST time (then runs negative)",
        get = function() return S().varianceCountdown and true or false end,
        set = function(v) S().varianceCountdown = v and true or false end,
    })
    sec:Checkbox({
        label = "Fade and animate bars",
        get = function() return S().animate and true or false end,
        set = function(v) S().animate = v and true or false end,
    })
    sec:Checkbox({
        label = "Park long bars off-screen until they get close",
        get = function() return S().hiddenMode and true or false end,
        set = function(v) S().hiddenMode = v and true or false end,
    })

    -- Placement affordances sit WITH the thing they place (principle 2), and the
    -- button row shares one grid with itself (principle 5).
    local place = sec:AddRow()
    place:Button({ text = "Show anchors", width = 130, onClick = function()
        if Addon.Bars then Addon.Bars.EnsureAnchors() end
        if Addon.Warnings then Addon.Warnings.EnsureAnchors() end
        Addon:ShowHudAnchors()
    end })
    place:Button({ text = "Demo", width = 130, onClick = function()
        if Addon.Bars then Addon.Bars.EnsureAnchors() end
        if Addon.Warnings then Addon.Warnings.EnsureAnchors() end
        Addon:ShowHudAnchors()
        if Addon.Bars then Addon.Bars.Demo() end
        if Addon.Warnings then Addon.Warnings.Demo() end
    end })
    place:Button({ text = "Lock", width = 130, onClick = function()
        if Addon.Bars then Addon.Bars.StopDemo() end
        if Addon.Warnings then Addon.Warnings.Reset() end
        Addon:HideHudAnchors()
    end })
end

-- ══════════════════════════════════════════════════════════════════════════════
--  W5 — WARNINGS
-- ══════════════════════════════════════════════════════════════════════════════
-- ui_warnings.lua's §5.4 suppressors, one checkbox each, grouped by the tier they
-- silence so the page reads as "announcements" then "special warnings" rather than
-- as a flat list of seven negatives.
function Addon:BuildWarningOptions(flow, panel)
    local W = Addon.Warnings
    if not W then return end
    local function S() return W.Settings() end

    local sec = flow:AddSection("Warnings")
    sec:Hint("Text warnings above the bars. ANNOUNCEMENTS are the ordinary line stack; "
        .. "SPECIAL WARNINGS are the big centred text with the screen flash, used for "
        .. "the things that kill you. Drag either with Show anchors under Timer Bars.")

    sec:Checkbox({
        label = "Hide all warnings",
        get = function() return S().hideWarnings and true or false end,
        set = function(v) S().hideWarnings = v and true or false end,
    })

    sec:AddSeparator()
    sec:Checkbox({
        label = "Silence boss-ability announcements",
        get = function() return S().suppressBossAnnounce and true or false end,
        set = function(v) S().suppressBossAnnounce = v and true or false end,
    })
    sec:Checkbox({
        label = "Silence \"who has it\" target announcements",
        tooltip = "On by default: on a 40-man these are the noisiest tier.",
        get = function() return S().suppressTargetAnnounce and true or false end,
        set = function(v) S().suppressTargetAnnounce = v and true or false end,
    })
    sec:Checkbox({
        label = "Mirror warnings to the chat frame",
        get = function() return S().mirrorToChat and true or false end,
        set = function(v) S().mirrorToChat = v and true or false end,
    })
    sec:Checkbox({
        label = "Sort combined target lists alphabetically",
        get = function() return S().combineSort and true or false end,
        set = function(v) S().combineSort = v and true or false end,
    })

    sec:AddSeparator()
    sec:Checkbox({
        label = "Silence special-warning TEXT",
        get = function() return S().suppressSpecialText and true or false end,
        set = function(v) S().suppressSpecialText = v and true or false end,
    })
    sec:Checkbox({
        label = "Silence the special-warning screen FLASH",
        get = function() return S().suppressSpecialFlash and true or false end,
        set = function(v) S().suppressSpecialFlash = v and true or false end,
    })
    sec:Checkbox({
        label = "Silence special-warning SOUNDS",
        get = function() return S().suppressSpecialSound and true or false end,
        set = function(v) S().suppressSpecialSound = v and true or false end,
    })
end

-- ══════════════════════════════════════════════════════════════════════════════
--  W5 — SOUNDS (the sound pack + the countdown voice pack)
-- ══════════════════════════════════════════════════════════════════════════════
function Addon:BuildSoundOptions(flow, panel)
    local sec = flow:AddSection("Sounds")
    sec:Hint("Raid Mechanics ships the DBM and NovaWorldBuffs sound packs INSIDE the "
        .. "addon, so they work whether or not those addons are installed, and picks up "
        .. "anything registered with LibSharedMedia on top. Choosing a default pack "
        .. "here is what makes the picker usable — it opens filtered to that pack.")

    -- Default sound pack. Cycle-free: a plain labelled dropdown of pack NAMES, which
    -- is what the picker's own filter strip mirrors.
    local packs = Addon:GetSoundPacks()
    local packNames = {}
    for _, p in ipairs(packs) do packNames[#packNames + 1] = p.name end
    local prow = sec:AddRow()
    prow:Label("Default pack")
    panel.soundPackDD = prow:Dropdown({
        width = 220, choices = packNames,
        get = function()
            local cur = Addon.db.settings.soundPack or Addon.SOUNDPACK_ALL
            for _, p in ipairs(packs) do if p.key == cur then return p.name end end
            return packNames[1]
        end,
        set = function(name)
            for _, p in ipairs(packs) do
                if p.name == name then Addon.db.settings.soundPack = p.key break end
            end
        end,
    })

    -- The countdown VOICE pack is a different bucket (numbered lines, not one-shots),
    -- so it gets its own labelled control rather than sharing the one above.
    local vpacks = Addon:GetVoiceCountPacks()
    local vnames = {}
    for _, pk in ipairs(vpacks) do vnames[#vnames + 1] = pk.name end
    local vrow = sec:AddRow()
    vrow:Label("Countdown voice")
    panel.voicePackDD = vrow:Dropdown({
        width = 220, choices = vnames,
        get = function()
            local cur = vpacks[1] and vpacks[1].name or "None"
            for _, pk in ipairs(vpacks) do
                if pk.key == Addon.db.settings.voiceCountKey then cur = pk.name break end
            end
            return cur
        end,
        set = function(name)
            for _, pk in ipairs(vpacks) do
                if pk.name == name then Addon.db.settings.voiceCountKey = pk.key break end
            end
        end,
    })
    vrow:Button({ text = "Test", width = 70, onClick = function()
        Addon:PlayVoiceCountdown(5, Addon.db.settings.voiceCountKey)
    end })
end

-- ══════════════════════════════════════════════════════════════════════════════
--  W5 — TIMER TELEMETRY (the arbitration instrument, made readable)
-- ══════════════════════════════════════════════════════════════════════════════
-- Design doc, target architecture item 3: the early-refresh tripwire writes every
-- out-of-window bar restart to the telemetry ring "INSTEAD OF DBM's 'please report'
-- chat line", so that "timer data becomes self-auditing across Drew's raids".
--
-- A ring nobody can read is not an instrument, it is a landfill. This is the pane
-- that turns it back into evidence: how many observations, how many were dropped by
-- the cap, and a SUMMARY BY TIMER KEY — because the question the ring exists to
-- answer is "which declared value is wrong", and that is answered by grouping the
-- observations per key and reading the average delta, not by scrolling raw lines.
-- The raw export is one button away for the cases where the summary is not enough.
function Addon:BuildTelemetryOptions(flow, panel)
    local T = Addon.Telemetry
    if not T then return end

    local sec = flow:AddSection("Timer Telemetry")
    sec:Hint("Every time a countdown bar restarts EARLIER than its declared window "
        .. "allows, that observation is written down here instead of being shouted at "
        .. "your raid. After a few nights this is the evidence for correcting a timer.")

    -- Built with its real text, not with "" and a later SetText: a Hint recomputes
    -- its height from the WRAPPED string at layout time, so a placeholder that grows
    -- later leaves the block sized for the placeholder until something relayouts.
    -- RefreshTelemetryLine sets the text AND relayouts, for the same reason.
    panel.telemetryLine = sec:Hint(Addon:TelemetryLineText())
    panel.telemetryPane = sec.pane

    local trow = sec:AddRow()
    trow:Button({ text = "View observations", width = 160, onClick = function()
        Addon:ShowTelemetryReport()
    end })
    trow:Button({ text = "Copy raw log", width = 160, onClick = function()
        local DS = _G.DaseekiSuite
        if not (DS and DS.ShowTextDialog) then
            print(Addon:Tag("[DRM]") .. " Install " .. Addon:Wrap("text", "Daseeki Core") .. " to view the log.")
            return
        end
        DS.ShowTextDialog("DRM Engine Log (raw)", table.concat(Addon.Telemetry.Export(), "\n"), true)
    end })
    trow:Button({ text = "Clear", width = 100, onClick = function()
        local n = Addon.Telemetry.Clear()
        print(Addon:Tag("[DRM]") .. (" Timer telemetry cleared (%d observations)."):format(n))
        Addon:RefreshTelemetryLine()
    end })

    sec:Checkbox({
        label = "Record timer observations",
        tooltip = "Off means the addon stops learning which of its timers are wrong.",
        get = function() return Addon.db.settings.engineTelemetry ~= false end,
        set = function(v) Addon.db.settings.engineTelemetry = v and true or false end,
    })

    Addon:RefreshTelemetryLine()
end

-- The one-line status the pane shows. Pure string work, so it is assertable.
function Addon:TelemetryLineText()
    local T = Addon.Telemetry
    if not T then return "" end
    local n, dropped = T.Count(), T.Dropped()
    if n == 0 then return "No observations recorded yet." end
    return ("%d observation%s recorded%s (build %s)."):format(
        n, n == 1 and "" or "s",
        dropped > 0 and (", %d older dropped by the cap"):format(dropped) or "",
        T.BUILD)
end

function Addon:RefreshTelemetryLine()
    local panel = Addon.optFrames and Addon.optFrames.general
    local lbl = panel and panel.telemetryLine
    if not lbl or not lbl._label then return end
    lbl._label:SetText(Addon:TelemetryLineText())
    -- The Hint's block height comes from the wrapped string, so a longer or shorter
    -- line needs the pane re-laid or it leaves a gap (or clips) under itself.
    if panel.telemetryPane and panel.telemetryPane.Layout then panel.telemetryPane:Layout() end
end

-- The SUMMARY the ring exists to produce: one line per timer key, sorted by how far
-- out of its declared window the observations sit. `n` observations, mean observed
-- duration, mean signed delta, the declared window. This is the arbitration table.
function Addon:BuildTelemetryReport()
    local T = Addon.Telemetry
    local ring = T.Ring(false)
    local out = {}
    out[#out + 1] = ("Daseeki Raid Mechanics — timer observations (build %s)"):format(T.BUILD)
    out[#out + 1] = ""
    if not ring or #ring == 0 then
        out[#out + 1] = "Nothing recorded yet. Bars only write here when they restart"
        out[#out + 1] = "EARLIER than the declared window allows, so an empty report"
        out[#out + 1] = "means the shipped timers matched what your raid actually saw."
        return table.concat(out, "\n")
    end

    local groups, order = {}, {}
    local other = 0
    for _, e in ipairs(ring) do
        if e.kind == "timer.refresh" and e.key then
            local id = tostring(e.enc or "?") .. ":" .. tostring(e.key)
            local g = groups[id]
            if not g then
                g = { id = id, enc = e.enc, key = e.key, n = 0, obs = 0, delta = 0,
                      expMin = e.expMin, expMax = e.expMax, worst = 0 }
                groups[id] = g; order[#order + 1] = g
            end
            g.n = g.n + 1
            g.obs = g.obs + (tonumber(e.obs) or 0)
            local d = tonumber(e.delta) or 0
            g.delta = g.delta + d
            if math.abs(d) > math.abs(g.worst) then g.worst = d end
        else
            other = other + 1
        end
    end

    -- Worst mean delta first — the timer most in need of correction at the top.
    table.sort(order, function(a, b)
        local ma, mb = math.abs(a.delta / a.n), math.abs(b.delta / b.n)
        if ma ~= mb then return ma > mb end
        return a.id < b.id
    end)

    out[#out + 1] = ("%-38s %5s %9s %9s %9s"):format("ENCOUNTER:TIMER", "N", "MEAN OBS", "MEAN DEV", "WORST")
    out[#out + 1] = string.rep("-", 74)
    for _, g in ipairs(order) do
        out[#out + 1] = ("%-38s %5d %8.2fs %+8.2fs %+8.2fs"):format(
            g.id:sub(1, 38), g.n, g.obs / g.n, g.delta / g.n, g.worst)
        if g.expMin then
            out[#out + 1] = ("%-38s       declared window %.2f-%.2fs"):format(
                "", g.expMin, g.expMax or g.expMin)
        end
    end
    out[#out + 1] = ""
    out[#out + 1] = ("%d timer observation group%s; %d other engine entr%s."):format(
        #order, #order == 1 and "" or "s", other, other == 1 and "y" or "ies")
    local dropped = T.Dropped()
    if dropped > 0 then
        out[#out + 1] = ("%d older entries were dropped by the %d-entry cap."):format(dropped, T.MAX)
    end
    out[#out + 1] = ""
    out[#out + 1] = "MEAN DEV is how far outside the declared window the bar actually ran."
    out[#out + 1] = "Negative = the ability came back SOONER than the addon expected."
    return table.concat(out, "\n")
end

function Addon:ShowTelemetryReport()
    local text = Addon:BuildTelemetryReport()
    local DS = _G.DaseekiSuite
    if DS and DS.ShowTextDialog then
        DS.ShowTextDialog("DRM Timer Observations", text, true)
    else
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            if line ~= "" then print(Addon:Tag("[DRM]") .. " " .. line) end
        end
    end
    return text
end

function Addon:RefreshGeneral()
    local panel = Addon.optFrames and Addon.optFrames.general
    if not panel then return end
    if panel.deathSoundBtn then
        btnText(panel.deathSoundBtn, Addon:GetSoundName(Addon.db.settings.deathSoundKey or "raidwarning"))
    end
    if panel.soundPackDD and panel.soundPackDD.Refresh then panel.soundPackDD.Refresh() end
    if panel.voicePackDD and panel.voicePackDD.Refresh then panel.voicePackDD.Refresh() end
    Addon:RefreshTelemetryLine()
end

-- AUDIT RM-1: repaint every raid section that has been built. Called from the
-- ROLE_CHANGED re-projection in core_api.lua §E, so a mid-raid Main-Tank promotion
-- moves the checkboxes the projection just re-resolved. Sorted (lesson Class 8) so
-- the repaint order is stable — it is observable through the selection each rebuild
-- validates, and a repaint that reshuffles selections is a bug report waiting to
-- happen.
function Addon:RefreshAllRaidSections()
    local frames = Addon.optFrames
    if type(frames) ~= "table" then return 0 end
    local ids = {}
    for id in pairs(frames) do
        if id ~= "general" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local n = 0
    for _, id in ipairs(ids) do
        Addon:RefreshRaidSection(id)
        n = n + 1
    end
    return n
end

function Addon:RegisterOptions()
    if not _G.DaseekiSuite then return end
    if not (_G.DaseekiUI and _G.DaseekiUI.Token) then
        print(Addon:Tag("Daseeki Raid Mechanics") .. " requires Daseeki Core v2.0.0 or newer — please update Daseeki Core.")
        return
    end
    -- General first, then one section per 20/40-man raid (raid.size set). Each raid
    -- section is a Bosses -> Mechanics -> Detail editor scoped to that raid.
    local sections = {
        { id = "general", title = "General",
          build = function(flow) Addon:BuildGeneralOptions(flow) end,
          refresh = function() Addon:RefreshGeneral() end },
    }
    for _, raid in ipairs(Addon:GetRaids()) do
        if raid.size then
            local rid = raid.id
            sections[#sections + 1] = {
                id = rid, title = raid.name,
                build = function(flow) Addon:BuildRaidSection(flow, rid) end,
                refresh = function() Addon:RefreshRaidSection(rid) end,
            }
        end
    end
    DaseekiSuite:RegisterAddon({
        id    = "raidmechanics",
        title = "Raid Mechanics",
        icon  = "Interface\\Icons\\Spell_Shadow_RaiseDead",
        order = 50,
        flow  = true,   -- opt in to the DaseekiUI flow API (Core defaults to legacy)
        sections = sections,
    })
end
