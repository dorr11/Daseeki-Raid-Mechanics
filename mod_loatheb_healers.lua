--[[
    Module — Loatheb Healer Tracker (ported from WeakAura "Loatheb Healer Tracker" /
    its "Corrupted Mind" TSU).

    Lists raid healers (DRUID/PALADIN/PRIEST/SHAMAN, online + alive + in your zone,
    minus excluded) as a vertical list of class-icon entries with a class-coloured
    name and a 60s "ready" cooldown. When a healer gets one of the Loatheb heal
    debuffs (29184/29195/29197/29199) and their ready timer is up, they go on a 60s
    cooldown — so you can see whose turn is coming. Optional "you're healing next"
    whisper to the next healer in order.

    Config (in the module panel): Order = Alphabetical | Manual (drag with the
    up/down arrows), exclude players (uncheck them), and the whisper toggle.

    NOTE: debuff IDs + 60s timer come straight from the WA — verify live with
    /drm debug and tweak DEBUFFS / READY if your pull shows different ids.
--]]

local _, Addon = ...

local MODID  = "loatheb_healers"
local KEY    = "naxxramas:loatheb:healers_mod"
local READY  = 60
local HEAL_CLASSES = { DRUID = true, PALADIN = true, PRIEST = true, SHAMAN = true }
local DEBUFFS = { [29184] = true, [29197] = true, [29195] = true, [29199] = true }
local ENTRY_H, HEADER_H = 22, 16
local CLASS_TEX = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

local container, ev
local entries     = {}   -- name -> entry frame
local cd          = {}   -- name -> ready GetTime()
local shownOrder  = {}   -- ordered array of currently shown names

local function cfg() return Addon:GetModuleConfig(MODID) end

local function classColor(fileName)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[fileName]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function isExcluded(name)
    local ex = cfg().excluded
    return ex and ex[name:lower()] and true or false
end

-- Order a list of names per the config (alpha or manual rank).
local function sortNames(names)
    if cfg().order == "manual" then
        local rank = {}
        for i, nm in ipairs(cfg().manualOrder or {}) do rank[nm:lower()] = i end
        table.sort(names, function(a, b)
            local ra, rb = rank[a:lower()] or 999, rank[b:lower()] or 999
            if ra ~= rb then return ra < rb end
            return a < b
        end)
    else
        table.sort(names, function(a, b) return a < b end)
    end
end

-- ── Live roster scan ────────────────────────────────────────────────────────────
local function scanRoster()
    local found = {}
    if IsInRaid() then
        local myZone = GetRealZoneText()
        for i = 1, 40 do
            local name, _, _, _, _, fileName, zone, online, isDead = GetRaidRosterInfo(i)
            if name and HEAL_CLASSES[fileName] and online and not isDead
               and zone == myZone and not isExcluded(name) then
                found[name] = fileName
                local c = cfg(); c.seen = c.seen or {}; c.seen[name] = fileName
            end
        end
    end
    return found
end

-- ── Entry frames ────────────────────────────────────────────────────────────────
local function makeEntry()
    local e = CreateFrame("Frame", nil, container)
    e:SetSize(150, ENTRY_H)
    e.icon = e:CreateTexture(nil, "ARTWORK")
    e.icon:SetSize(ENTRY_H - 2, ENTRY_H - 2); e.icon:SetPoint("LEFT")
    e.icon:SetTexture(CLASS_TEX)
    Addon:AddIconBorder(e.icon, e)
    e.cd = CreateFrame("Cooldown", nil, e, "CooldownFrameTemplate")
    e.cd:SetAllPoints(e.icon)
    if e.cd.SetHideCountdownNumbers then e.cd:SetHideCountdownNumbers(true) end
    e.cd.noCooldownCount = true
    e.name = e:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Addon:TrySetFont(e.name, "body")       -- tinted per healer by styleEntry (class colour)
    e.name:SetPoint("LEFT", e.icon, "RIGHT", 4, 0); e.name:SetJustifyH("LEFT")
    e.timer = e:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Addon:TrySetFont(e.timer, "numeral")   -- cooldown readout → telemetry numeral
    e.timer:SetPoint("RIGHT", e, "RIGHT", -2, 0)
    return e
end

local function styleEntry(e, name, fileName)
    local t = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[fileName]
    if t then e.icon:SetTexCoord(t[1], t[2], t[3], t[4]) else e.icon:SetTexCoord(0, 1, 0, 1) end
    e.name:SetText(name)
    e.name:SetTextColor(classColor(fileName))
end

local function Layout(found)
    local names = {}
    for nm in pairs(found) do names[#names + 1] = nm end
    sortNames(names)
    shownOrder = names

    for _, e in pairs(entries) do e:Hide() end
    local y = HEADER_H
    for _, nm in ipairs(names) do
        local e = entries[nm] or makeEntry()
        entries[nm] = e
        styleEntry(e, nm, found[nm])
        if cd[nm] and cd[nm] > GetTime() then
            e.cd:SetCooldown(cd[nm] - READY, READY)
        else
            e.cd:SetCooldown(0, 0)
        end
        e:ClearAllPoints()
        e:SetPoint("TOPLEFT", container, "TOPLEFT", 6, -y)
        e:Show()
        y = y + ENTRY_H + 2
    end
    container:SetHeight(math.max(40, y + 4))
end

-- ── Container ────────────────────────────────────────────────────────────────────
local function Position(c)
    local pos = Addon:GetAnchorPos(KEY)
    c:ClearAllPoints()
    c:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
end

local function EnsureContainer()
    if container then return container end
    local c = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    c:SetSize(170, 60); c:SetFrameStrata("MEDIUM")
    c:SetMovable(true); c:EnableMouse(true)
    Addon:ApplyDarkBackdrop(c)
    c.header = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Addon:TrySetFont(c.header, "microLabel")   -- widget eyebrow (§3)
    -- Addon:Wrap resolves the brand token with Core and the legacy cyan without.
    c.header:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -1); c.header:SetText(Addon:Wrap("brand", "Loatheb Healers"))
    c:SetScript("OnMouseDown", function(self, b) if b == "LeftButton" then self:StartMoving() end end)
    c:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        Addon:SetMechanicPos(KEY, p, rp, x, y)
    end)
    c:SetScript("OnUpdate", function(self, el)
        self._acc = (self._acc or 0) + el
        if self._acc < 0.1 then return end
        self._acc = 0
        local now = GetTime()
        for nm, e in pairs(entries) do
            if e:IsShown() then
                local exp = cd[nm]
                if exp and exp > now then
                    e.timer:SetText(string.format("%d", math.ceil(exp - now)))
                    e.timer:SetTextColor(1, 0.35, 0.35)
                else
                    e.timer:SetText("rdy")
                    e.timer:SetTextColor(0.35, 1, 0.35)
                end
            end
        end
    end)
    container = c
    return c
end

-- ── Cooldown trigger + whisper ───────────────────────────────────────────────────
local function WhisperNext(fromName)
    if #shownOrder < 2 then return end
    for i, nm in ipairs(shownOrder) do
        if nm == fromName then
            local nextName = shownOrder[i == #shownOrder and 1 or i + 1]
            if nextName and nextName ~= fromName then
                SendChatMessage("YOU'RE HEALING NEXT", "WHISPER", nil, nextName)
            end
            return
        end
    end
end

local function CheckAuras()
    if not IsInRaid() then return end
    local now = GetTime()
    for i = 1, 40 do
        local fileName = select(2, UnitClass("raid" .. i))
        if HEAL_CLASSES[fileName] then
            local nm = UnitName("raid" .. i)
            if nm and entries[nm] then
                local hit = false
                for j = 1, 16 do
                    local sid = select(10, UnitDebuff("raid" .. i, j))
                    if sid and DEBUFFS[sid] then hit = true break end
                end
                if hit and (not cd[nm] or cd[nm] <= now) then
                    cd[nm] = now + READY
                    entries[nm].cd:SetCooldown(now, READY)
                    if cfg().whisper and nm == UnitName("player") then WhisperNext(nm) end
                end
            end
        end
    end
end

local function Rescan() if container and container:IsShown() then Layout(scanRoster()) end end

-- ── Test preview (out of raid) ────────────────────────────────────────────────────
local function ShowPreview()
    EnsureContainer(); Position(container); container:Show()
    local sample = { ["Alphapriest"] = "PRIEST", ["Betadruid"] = "DRUID", ["Gammapala"] = "PALADIN", ["Deltashaman"] = "SHAMAN" }
    cd["Betadruid"] = GetTime() + 42
    Layout(sample)
end

-- ── Module registration ───────────────────────────────────────────────────────────
local def
def = Addon:RegisterModule({
    id = MODID, raidId = "naxxramas", bossId = "loatheb",
    name = "Healer Tracker (WA)",
    desc = "Raid healers with a 60s ready-cooldown each, ordered for the rotation. Drag the list header to position it.",
    defaults = { enabled = false },

    Start = function()
        wipe(cd)
        EnsureContainer(); Position(container); container:Show()
        Layout(scanRoster())
        ev = ev or CreateFrame("Frame")
        ev:SetScript("OnEvent", function(_, event, arg1)
            if event == "UNIT_AURA" then
                CheckAuras()
            elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
                local _, sub, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
                if sub == "UNIT_DIED" then
                    local _, _, _, _, _, id = strsplit("-", destGUID or "")
                    if tonumber(id) == 16011 then
                        if container then container:Hide() end   -- Loatheb dead -> hide list
                    else
                        Rescan()
                    end
                end
            else
                Rescan()
            end
        end)
        ev:RegisterEvent("GROUP_ROSTER_UPDATE")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        ev:RegisterEvent("UNIT_AURA")
        ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end,

    Stop = function()
        if ev then ev:UnregisterAllEvents(); ev:SetScript("OnEvent", nil) end
        if container then container:Hide() end
    end,

    Test = function()
        if container and container:IsShown() then container:Hide(); wipe(cd)
        else ShowPreview() end
    end,

    -- Boss-level unlock shows/hides the draggable container.
    SetPreview = function(_, on)
        if on then ShowPreview()
        elseif container then container:Hide(); wipe(cd) end
    end,

    BuildConfig = function(self, parent)
        local DS = _G.DaseekiSuite

        DS.MakeLabel(parent, "Order", nil, 0, 4)
        parent.orderDD = DS.MakeSimpleDropdown(parent, 48, 0, 120, { "Alphabetical", "Manual" }, function(v)
            cfg().order = (v == "Manual") and "manual" or "alpha"
            if def.RefreshConfig then def:RefreshConfig() end
            Rescan()
        end)

        DS.MakeButton(parent, "Refresh", 184, 0, 84, 22, function()
            scanRoster(); if def.RefreshConfig then def:RefreshConfig() end
        end)

        parent.whisper = DS.MakeCheckbox(parent, "Whisper next healer", 0, 28,
            function() return cfg().whisper end,
            function(v) cfg().whisper = v and true or false end)

        DS.MakeLabel(parent, "|cffffffffHealers|r (uncheck to exclude):", nil, 0, 60)
        parent.rows = {}
        self._cfgParent = parent
    end,

    RefreshConfig = function(self)
        local parent = self._cfgParent
        if not parent then return end
        local DS = _G.DaseekiSuite
        local manual = (cfg().order == "manual")
        if parent.orderDD then parent.orderDD:SetValue(manual and "Manual" or "Alphabetical") end

        -- Build the union of seen + current-raid healers.
        local set = {}
        for nm, cl in pairs(cfg().seen or {}) do set[nm] = cl end
        if IsInRaid() then
            for i = 1, 40 do
                local nm = UnitName("raid" .. i)
                if nm then
                    local fileName = select(2, UnitClass("raid" .. i))
                    if HEAL_CLASSES[fileName] then set[nm] = fileName end
                end
            end
        end
        local names = {}
        for nm in pairs(set) do names[#names + 1] = nm end
        sortNames(names)

        -- Keep manualOrder seeded with every known healer (stable indices).
        if manual then
            cfg().manualOrder = cfg().manualOrder or {}
            local present = {}
            for _, nm in ipairs(cfg().manualOrder) do present[nm:lower()] = true end
            for _, nm in ipairs(names) do
                if not present[nm:lower()] then cfg().manualOrder[#cfg().manualOrder + 1] = nm end
            end
        end

        for _, r in ipairs(parent.rows) do r:Hide() end
        for i, nm in ipairs(names) do
            local r = parent.rows[i]
            if not r then
                r = CreateFrame("Frame", nil, parent)
                r:SetSize(270, 22)
                r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
                r.check:SetSize(20, 20); r.check:SetPoint("LEFT", r, "LEFT", 0, 0)
                r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                Addon:TrySetFont(r.label, "body")   -- tinted per class below
                r.label:SetPoint("LEFT", r.check, "RIGHT", 2, 0); r.label:SetWidth(150); r.label:SetJustifyH("LEFT")
                r.up = DS.MakeButton(r, "^", 200, 0, 22, 20, nil)
                r.down = DS.MakeButton(r, "v", 224, 0, 22, 20, nil)
                parent.rows[i] = r
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(84 + (i - 1) * 22))
            r.label:SetText(nm); r.label:SetTextColor(classColor(set[nm]))
            r.check:SetChecked(not isExcluded(nm))
            r.check:SetScript("OnClick", function(s)
                cfg().excluded = cfg().excluded or {}
                cfg().excluded[nm:lower()] = (not s:GetChecked()) or nil
                Rescan()
            end)
            r.up:SetShown(manual); r.down:SetShown(manual)
            r.up:SetScript("OnClick", function() self:MoveOrder(nm, -1) end)
            r.down:SetScript("OnClick", function() self:MoveOrder(nm, 1) end)
            r:Show()
        end
    end,

    MoveOrder = function(self, name, dir)
        local mo = cfg().manualOrder; if not mo then return end
        for i, nm in ipairs(mo) do
            if nm:lower() == name:lower() then
                local j = i + dir
                if j >= 1 and j <= #mo then mo[i], mo[j] = mo[j], mo[i] end
                break
            end
        end
        if self.RefreshConfig then self:RefreshConfig() end
        Rescan()
    end,
})
