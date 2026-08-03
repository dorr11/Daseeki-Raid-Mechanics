--[[
    Module — Four Horsemen Tracker widget

    One row per horseman (ordered Thane / Mograine / Blaumeux / Zeliek): horse icon,
    name, a live health bar, and that horse's current target (the raid member carrying
    the most stacks of that horse's mark) + the stack count. Each horse's ability
    cooldown radial (Meteor / Void Zone / Holy Wrath; Mograine has none) is a standalone
    icon anchored OUTSIDE the widget's left border, aligned with its row. A horse's row
    fades when it dies. The header shows the running Mark count.

    Combat detection runs through the engine's shared combat hook (so it catches the
    engaging cast too). A configurable screen flash + sound fires when YOU reach 4+
    marks from any horse.
--]]

local _, Addon = ...

local MODID = "fourhorsemen_tracker"
local KEY   = "naxxramas:fourhorsemen:tracker_mod"
local MARKCD_KEY = "naxxramas:fourhorsemen:markcd"

-- Ordered top->bottom: Thane Korth'azz, Mograine, Blaumeux, Zeliek.
-- mark spellIDs: Korth'azz 28832, Mograine 28834, Blaumeux 28833, Zeliek 28835.
-- ability spellIDs: Meteor 28884, Void Zone 28863, Holy Wrath 28883 (Mograine none).
local HORSEMEN = {
    { name = "Korth'azz", npc = 16064, mark = 28832, icon = "Interface\\Icons\\Spell_Fire_Fire",
      ability = { spellID = 28884, name = "Meteor",     icon = "Interface\\Icons\\Spell_Fire_Meteorstorm" } },
    { name = "Mograine",  npc = 16062, mark = 28834, icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing" },
    { name = "Blaumeux",  npc = 16065, mark = 28833, icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
      ability = { spellID = 28863, name = "Void Zone",  icon = "Interface\\Icons\\Spell_Shadow_DemonBreath" } },
    { name = "Zeliek",    npc = 16063, mark = 28835, icon = "Interface\\Icons\\Spell_Holy_HolySmite",
      ability = { spellID = 28883, name = "Holy Wrath", icon = "Interface\\Icons\\Spell_Holy_Excorcism_02" } },
}
local ROW_H, HEADER_H, W = 40, 16, 215
local SHIELD_SPELL, SHIELD_DUR = 29061, 20   -- "Shield Wall" / Bone Barrier (~20s)
local SHIELD_ICON = "Interface\\Icons\\Ability_Warrior_ShieldWall"
local AB_FIRST, AB_CD = 21, 11.3            -- DBM: 21 from pull, then v11.3-16.2

local frame
local dead    = {}   -- npc -> true
local shield  = {}   -- npc -> { start, exp }
local abCd    = {}   -- npc -> { start, dur, applied }
local preview = false
local lastFlash = 0
local hookDone  = false

local function isHorse(id)
    for _, h in ipairs(HORSEMEN) do if h.npc == id then return true end end
    return false
end
local function horseByNpc(id)
    for _, h in ipairs(HORSEMEN) do if h.npc == id then return h end end
    return nil
end

local SAMPLE_HP   = { [16064] = 0.82, [16062] = 0.64, [16065] = 0.5, [16063] = 0 }
local SAMPLE_MARK = {
    [28832] = { name = "Offtank", stacks = 6 }, [28834] = { name = "Maintank", stacks = 4 },
    [28833] = { name = "Hunterx", stacks = 2 },
}

local function cfg() return Addon:GetModuleConfig(MODID) end

local function npcFromGUID(guid)
    if not guid then return nil end
    local _, _, _, _, _, id = strsplit("-", guid)
    return tonumber(id)
end
local function npcOf(unit) return UnitExists(unit) and npcFromGUID(UnitGUID(unit)) or nil end
local function shorten(n) return n and n:sub(1, 10) or "?" end

-- Resolve a spell's REAL icon from the client's own spell data when possible (avoids
-- hand-typed icon-path guesses going stale/wrong); falls back to the static path if
-- the spell isn't cached yet.
local function ResolveIcon(spellID, fallback)
    if not spellID then return fallback end
    local _, _, texture = GetSpellInfo(spellID)
    return texture or fallback
end

local function Scan()
    local hp, mark = {}, {}
    local function checkHorse(unit)
        local id = npcOf(unit); if not id then return end
        for _, h in ipairs(HORSEMEN) do
            if h.npc == id then
                local cur, max = UnitHealth(unit), UnitHealthMax(unit)
                if max and max > 0 then hp[id] = cur / max end
            end
        end
    end
    checkHorse("target"); checkHorse("targettarget"); checkHorse("focus"); checkHorse("mouseover")
    for i = 1, 5 do checkHorse("boss" .. i) end
    if IsInRaid() then for i = 1, 40 do checkHorse("raid" .. i .. "target") end end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, np in ipairs(C_NamePlate.GetNamePlates()) do
            if np.namePlateUnitToken then checkHorse(np.namePlateUnitToken) end
        end
    end

    local function checkMarks(unit)
        if not UnitExists(unit) then return end
        local nm = UnitName(unit)
        for j = 1, 40 do
            local name, _, count, _, _, _, _, _, _, spellID = UnitDebuff(unit, j)
            if not name then break end
            for _, h in ipairs(HORSEMEN) do
                if spellID == h.mark then
                    local c = count or 1
                    if not mark[h.mark] or c > mark[h.mark].stacks then
                        mark[h.mark] = { name = nm, stacks = c }
                    end
                end
            end
        end
    end
    checkMarks("player")
    if IsInRaid() then for i = 1, 40 do checkMarks("raid" .. i) end
    else for i = 1, 4 do checkMarks("party" .. i) end end
    return hp, mark
end

local function Position(c)
    local pos = Addon:GetAnchorPos(KEY)
    c:ClearAllPoints()
    c:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
end

local function ApplyCfg(c)
    c:SetScale(cfg().scale or 1); c:SetAlpha(cfg().opacity or 1)
end

-- Full-screen red flash (the "you have 4+ marks" warning).
local flashFrame
local function ScreenFlash()
    if not flashFrame then
        flashFrame = CreateFrame("Frame", nil, UIParent)
        flashFrame:SetAllPoints(UIParent)
        flashFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        flashFrame.tex = flashFrame:CreateTexture(nil, "BACKGROUND")
        flashFrame.tex:SetAllPoints(); flashFrame.tex:SetColorTexture(0.85, 0.1, 0.1, 1)
    end
    flashFrame._e = 0; flashFrame:SetAlpha(0); flashFrame:Show()
    flashFrame:SetScript("OnUpdate", function(self, el)
        self._e = self._e + el
        local t = self._e
        local a = (t < 0.15) and (t / 0.15) * 0.45 or math.max(0, 0.45 * (1 - (t - 0.15) / 0.5))
        self:SetAlpha(a)
        if t >= 0.65 then self:Hide(); self:SetScript("OnUpdate", nil) end
    end)
end

local function Refresh(c)
    local hp, mark = preview and SAMPLE_HP or nil, preview and SAMPLE_MARK or nil
    if not preview then hp, mark = Scan() end
    local now = GetTime()

    local cnt = (Addon._mechCount and Addon._mechCount[MARKCD_KEY]) or (preview and 5) or 0
    -- Theme tokens with Core, the legacy cyan/gold literals without (Addon:Wrap).
    c.header:SetText(Addon:Wrap("brand", "Four Horsemen")
        .. "  " .. Addon:Wrap("warn", ("Marks: %d"):format(cnt)))

    for _, row in ipairs(c.rows) do
        local h = row._h
        local isDead = (preview and h.npc == 16063) or dead[h.npc]
        row:SetAlpha(isDead and 0.35 or 1)

        -- Shield Wall: swap horse icon + overlay remaining time while active, else mark icon.
        local sh = shield[h.npc]
        if sh and sh.exp > now and not isDead then
            row.icon:SetTexture(SHIELD_ICON)
            row.sw:SetCooldown(sh.start, SHIELD_DUR); row.sw:Show()
            row.swText:SetText(string.format("%d", math.ceil(sh.exp - now))); row.swText:Show()
        else
            if sh and sh.exp <= now then shield[h.npc] = nil end
            row.icon:SetTexture(h.icon)
            row.sw:Hide(); row.swText:Hide()
        end

        -- Standalone ability cooldown radial, outside the widget's left border.
        if h.ability and not isDead then
            row.abIcon:Show(); row.abBorder:Show()
            local cd = abCd[h.npc]
            if cd then
                if not cd.applied then row.abCd:SetCooldown(cd.start, cd.dur); row.abCd:Show(); cd.applied = true end
                local rem = cd.start + cd.dur - now
                row.abText:SetText(rem > 0.5 and tostring(math.ceil(rem)) or "")
            else
                row.abCd:Hide(); row.abText:SetText("")
            end
        else
            row.abIcon:Hide(); row.abBorder:Hide(); row.abCd:Hide(); row.abText:SetText("")
        end

        local f = hp[h.npc]
        if isDead then
            row.bar:SetValue(0); row.pct:SetText("dead")
        elseif f then
            row.bar:SetValue(f)
            row.bar:SetStatusBarColor(0.85 - 0.55 * f, 0.2 + 0.6 * f, 0.2)
            row.pct:SetText(string.format("%d%%", math.floor(f * 100 + 0.5)))
        else
            row.bar:SetValue(0); row.pct:SetText("--")
        end
        local m = mark[h.mark]
        if m and not isDead then
            row.tgt:SetText(string.format("|cff888888\226\134\146|r %s |cffffd200(%d)|r", shorten(m.name), m.stacks))
        else
            row.tgt:SetText("|cff777777\226\134\146 --|r")
        end
    end
end

-- ── Shared combat hook (registered once; gated to the active 4H fight) ──────────--
local function HookFn(sub, sourceGUID, sourceID, destGUID, destID, spellID)
    if not (Addon.active and Addon.active.bossId == "fourhorsemen") then return end
    if preview or not (frame and frame:IsShown()) then return end  -- only when live
    local now = GetTime()

    -- Horse death / shield (keyed off the destination = the horse).
    if destID and isHorse(destID) then
        if sub == "UNIT_DIED" then
            dead[destID] = true; shield[destID] = nil; abCd[destID] = nil
        elseif spellID == SHIELD_SPELL then
            if sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH" then
                shield[destID] = { start = now, exp = now + SHIELD_DUR }
            elseif sub == "SPELL_AURA_REMOVED" then
                shield[destID] = nil
            end
        end
    end

    -- Ability cast (source = the horse) -> reset that horse's inline cooldown.
    if sub == "SPELL_CAST_SUCCESS" and sourceID then
        local h = horseByNpc(sourceID)
        if h and h.ability and spellID == h.ability.spellID then
            abCd[sourceID] = { start = now, dur = AB_CD }
        end
    end

    -- Marks: live-refresh target/stacks, and warn if YOU reach 4+.
    if sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_APPLIED_DOSE" then
        for _, h in ipairs(HORSEMEN) do
            if spellID == h.mark then
                if frame and frame:IsShown() then Refresh(frame) end
                if destGUID == UnitGUID("player") and (cfg().warn4 ~= false) then
                    local amount = select(16, CombatLogGetCurrentEventInfo()) or 1
                    if amount >= 4 and (now - lastFlash) > 2 then
                        lastFlash = now
                        ScreenFlash()
                        Addon:PlaySoundByKey(cfg().warn4Sound or "raidwarning", true)
                    end
                end
                break
            end
        end
    end
end

local function EnsureFrame()
    if frame then return frame end
    local c = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    c:SetSize(W, HEADER_H + #HORSEMEN * ROW_H + 4); c:SetFrameStrata("MEDIUM")
    c:SetMovable(true); c:EnableMouse(true)
    Addon:ApplyDarkBackdrop(c)
    c.header = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Addon:TrySetFont(c.header, "microLabel")   -- widget eyebrow (§3)
    -- Addon:Wrap resolves the brand token with Core and the legacy cyan without.
    c.header:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -2); c.header:SetText(Addon:Wrap("brand", "Four Horsemen"))
    c:SetScript("OnMouseDown", function(self, b) if b == "LeftButton" then self:StartMoving() end end)
    c:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        Addon:SetMechanicPos(KEY, p, rp, x, y)
    end)

    c.rows = {}
    for i, h in ipairs(HORSEMEN) do
        local row = CreateFrame("Frame", nil, c)
        row:SetSize(W - 12, ROW_H - 4)
        row:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -(HEADER_H + (i - 1) * ROW_H))
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(32, 32); row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.icon:SetTexture(h.icon); row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        Addon:AddIconBorder(row.icon, row)
        row.sw = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
        row.sw:SetAllPoints(row.icon)
        if row.sw.SetHideCountdownNumbers then row.sw:SetHideCountdownNumbers(true) end
        row.sw.noCooldownCount = true; row.sw:Hide()
        row.swText = row.sw:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.swText:SetPoint("CENTER", row.icon, "CENTER", 0, 0)

        -- Standalone ability cooldown icon, anchored OUTSIDE the widget's left border
        -- at this row's height (only for horses with one — Mograine has none). The
        -- border is a SEPARATE frame (its visibility doesn't follow the icon's
        -- :Hide()/:Show() automatically) so it must be toggled alongside abIcon
        -- everywhere, or Mograine's empty slot shows a hollow border with no icon.
        row.abIcon = row:CreateTexture(nil, "ARTWORK")
        row.abIcon:SetSize(28, 28)
        row.abIcon:SetPoint("RIGHT", row.icon, "LEFT", -8, 0)
        row.abIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.abBorder = Addon:AddIconBorder(row.abIcon, row)
        if h.ability then
            row.abIcon:SetTexture(ResolveIcon(h.ability.spellID, h.ability.icon))
        else
            row.abIcon:Hide(); row.abBorder:Hide()
        end
        row.abCd = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
        row.abCd:SetAllPoints(row.abIcon)
        if row.abCd.SetHideCountdownNumbers then row.abCd:SetHideCountdownNumbers(true) end
        row.abCd.noCooldownCount = true; row.abCd:Hide()
        row.abText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.abText:SetPoint("CENTER", row.abIcon, "CENTER", 0, 0)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 5, -1)
        row.name:SetText(h.name)
        row.bar = CreateFrame("StatusBar", nil, row)
        row.bar:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 5, -14); row.bar:SetSize(W - 55, 9)
        row.bar:SetMinMaxValues(0, 1); row.bar:SetValue(1)
        row.bar.bg = row.bar:CreateTexture(nil, "BACKGROUND"); row.bar.bg:SetAllPoints()
        Addon:StyleBar(row.bar); Addon:AddBorder(row.bar)
        row.pct = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.pct:SetPoint("RIGHT", row.bar, "RIGHT", -2, 0)
        row.tgt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.tgt:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 5, -25); row.tgt:SetJustifyH("LEFT")
        -- Suite face first (SetFontObject re-applies the object's colour), tint after.
        Addon:TrySetFont(row.name, "body")
        Addon:TrySetFont(row.pct,     "numeral")   -- health % readout → telemetry
        Addon:TrySetFont(row.swText,  "numeral")   -- mark-swap countdown
        Addon:TrySetFont(row.abText,  "numeral")   -- ability cooldown countdown
        Addon:TrySetFont(row.tgt, "small")
        Addon:StyleFont(row.name); Addon:StyleFont(row.pct); Addon:StyleFont(row.tgt)
        Addon:StyleFont(row.swText); Addon:StyleFont(row.abText)
        row._h = h
        c.rows[i] = row
    end

    c:SetScript("OnUpdate", function(self, el)
        self._acc = (self._acc or 0) + el
        if self._acc < 0.2 then return end
        self._acc = 0
        Refresh(self)
    end)
    frame = c
    return c
end

local function Show(asPreview)
    preview = asPreview and true or false
    wipe(dead); wipe(shield); wipe(abCd)
    local now = GetTime()
    if preview then
        shield[16064] = { start = now, exp = now + 12 }
        abCd[16064] = { start = now, dur = 11 }
        abCd[16065] = { start = now - 3, dur = 11 }
        abCd[16063] = { start = now, dur = 8 }
    else
        -- Predict each ability's first cast from pull (DBM-style), like the engine does.
        for _, h in ipairs(HORSEMEN) do
            if h.ability then abCd[h.npc] = { start = now, dur = AB_FIRST } end
        end
    end
    EnsureFrame(); Position(frame); ApplyCfg(frame); Refresh(frame); frame:Show()
end

Addon:RegisterModule({
    id = MODID, raidId = "naxxramas", bossId = "fourhorsemen",
    name = "Horsemen Tracker",
    desc = "Per-horse icon, inline ability cooldown, health, current target + that target's mark stacks, and a running Mark count. Dead horses fade. Drag the header to move.",
    defaults = { enabled = false },

    Start = function()
        Show(false)
        if not hookDone then hookDone = true; Addon:RegisterCombatHook(HookFn) end
    end,
    Stop = function()
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
        DS.MakeCheckbox(parent, "Flash + sound when YOU reach 4+ marks", 6, 104,
            function() return cfg().warn4 ~= false end,
            function(v) cfg().warn4 = v and true or false end)
        DS.MakeLabel(parent, "4-mark sound", nil, 6, 134)
        local sb
        sb = DS.MakeButton(parent, "None", 92, 130, 130, 22, function()
            Addon:ShowSoundPicker(cfg().warn4Sound or "raidwarning", function(key)
                cfg().warn4Sound = key; sb:SetText(Addon:GetSoundName(key))
            end, sb)
        end)
        sb:SetText(Addon:GetSoundName(cfg().warn4Sound or "raidwarning"))
    end,
})
