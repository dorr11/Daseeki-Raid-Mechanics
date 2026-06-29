--[[
    Module — Four Horsemen Healer Rotation (ported from WeakAura "4 Horsemen Healer
    Rotation").

    A personal positioning bar: tells you which corner to stand at and when to move,
    rotating one corner every N marks. Shows your current mark-stack (warns at the
    alarm threshold) and a 12s timer per mark. A dead horseman's corner becomes a
    "Safe Zone". Drag the bar to position it.

    Clockwise order (corner 1->4):
        Highlord Mograine -> Thane Korth'azz -> Lady Blaumeux -> Sir Zeliek
    Config: rotate step, direction, starting corner, stack alarm, move/wrong sounds.
--]]

local _, Addon = ...

local MODID = "fourhorsemen_rotation"
local KEY   = "naxxramas:fourhorsemen:rotation_mod"

-- corner index -> { mark spellID, horseman npcID, name }
local ORDER = {
    { mark = 28834, npc = 16062, name = "Highlord Mograine" },
    { mark = 28832, npc = 16064, name = "Thane Korth'azz" },
    { mark = 28833, npc = 16065, name = "Lady Blaumeux" },
    { mark = 28835, npc = 16063, name = "Sir Zeliek" },
}
local MARK_INDEX, IS_HORSEMAN = {}, {}
for i, e in ipairs(ORDER) do MARK_INDEX[e.mark] = i; IS_HORSEMAN[e.npc] = i end

local DEFAULTS = { step = 3, direction = "cw", startCorner = 3, stackAlarm = 4, optStart = 1,
                   moveSound = true, wrongSound = true }

local function cfg()
    local c = Addon:GetModuleConfig(MODID)
    for k, v in pairs(DEFAULTS) do if c[k] == nil then c[k] = v end end
    return c
end

-- runtime state
local bar, ev
local names      -- mutable corner names (Safe Zone substitution)
local markCount, currentNum, last, timer, expiration, wrongMark

local function npcFromGUID(guid)
    if not guid then return nil end
    local _, _, _, _, _, id = strsplit("-", guid)
    return tonumber(id)
end

local function playerStack(spellID)
    for j = 1, 16 do
        local name, _, count, _, _, _, _, _, _, sid = UnitDebuff("player", j)
        if not name then break end
        if sid == spellID then return count or 1 end
    end
    return 0
end

-- ── Bar ───────────────────────────────────────────────────────────────────────
local function Position(f)
    local pos = Addon:GetAnchorPos(KEY)
    f:ClearAllPoints()
    f:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
end

local function EnsureBar()
    if bar then return bar end
    local f = CreateFrame("StatusBar", nil, UIParent)
    f:SetSize(240, 26); f:SetFrameStrata("MEDIUM")
    f:SetMinMaxValues(0, 1); f:SetValue(1)
    f:SetMovable(true); f:EnableMouse(true)
    f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints()
    Addon:StyleBar(f)
    Addon:AddBorder(f)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("LEFT", f, "LEFT", 6, 0); f.text:SetJustifyH("LEFT")
    f.timer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.timer:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    Addon:StyleFont(f.text); Addon:StyleFont(f.timer)
    f:SetScript("OnMouseDown", function(self, b) if b == "LeftButton" then self:StartMoving() end end)
    f:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        Addon:SetMechanicPos(KEY, p, rp, x, y)
    end)
    f:SetScript("OnUpdate", function(self)
        if not expiration then return end
        local rem = expiration - GetTime()
        if rem < 0 then rem = 0 end
        self:SetValue(timer > 0 and (rem / timer) or 0)
        self.timer:SetText(string.format("%.0f", rem))
    end)
    bar = f
    return f
end

local function UpdateBar(message, name)
    local f = EnsureBar()
    f.text:SetText((message or "") .. (name or ""))
    if wrongMark then f:SetStatusBarColor(0.85, 0.2, 0.2)
    else f:SetStatusBarColor(0.12, 0.09, 0.77) end
end

-- ── Rotation logic ───────────────────────────────────────────────────────────--
local function Reset()
    local c = cfg()
    markCount   = 0
    currentNum  = c.startCorner
    last        = 0
    wrongMark   = false
    timer       = 20
    expiration  = GetTime() + 20
    names = {}
    for i, e in ipairs(ORDER) do names[i] = e.name end
    UpdateBar("Start at ", names[currentNum])
end

local function OnMark(spellID)
    local c = cfg()
    local now = GetTime()
    if now <= last + 5 then return end       -- one mark "batch" per 5s
    last = now
    markCount = markCount + 1

    local moved = (markCount == c.optStart)
        or (markCount > c.optStart and ((markCount - c.optStart) % c.step) == 0)
    local message
    if moved then
        if c.direction == "cw" then
            currentNum = (currentNum < 4) and (currentNum + 1) or 1
        else
            currentNum = (currentNum > 1) and (currentNum - 1) or 4
        end
        message = "MOVE to "
    else
        message = "Currently at "
    end

    local stack = playerStack(spellID)
    if stack >= c.stackAlarm then message = stack .. " STACKS " .. message end

    wrongMark = (MARK_INDEX[spellID] ~= currentNum)

    timer = 12; expiration = now + 12
    UpdateBar(message, names[currentNum])

    if moved and c.moveSound then Addon:PlaySoundByKey("readycheck", true) end
    if wrongMark and c.wrongSound then Addon:PlaySoundByKey("ding", true) end
end

local function OnHorsemanDeath(npc)
    local idx = IS_HORSEMAN[npc]
    if not idx or not names then return end
    names[idx] = "Safe Zone"
    if idx == currentNum then UpdateBar("MOVE to ", names[currentNum]) end
end

-- ── Module ────────────────────────────────────────────────────────────────────
local def
def = Addon:RegisterModule({
    id = MODID, raidId = "naxxramas", bossId = "fourhorsemen",
    name = "Healer Rotation (WA)",
    desc = "Personal corner-rotation bar: MOVE / Currently-at, your mark stacks, 12s timer; dead horseman = Safe Zone. Drag the bar to position it.",
    defaults = { enabled = false },

    Start = function()
        EnsureBar(); Position(bar); bar:Show()
        Reset()
        ev = ev or CreateFrame("Frame")
        ev:SetScript("OnEvent", function()
            local _, sub, _, sourceGUID, _, _, _, destGUID, _, _, _, spellID = CombatLogGetCurrentEventInfo()
            if sub == "SPELL_CAST_SUCCESS" or sub == "SPELL_AURA_APPLIED" then
                if MARK_INDEX[spellID] and IS_HORSEMAN[npcFromGUID(sourceGUID)] then OnMark(spellID) end
            elseif sub == "UNIT_DIED" then
                OnHorsemanDeath(npcFromGUID(destGUID))
            end
        end)
        ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end,

    Stop = function()
        if ev then ev:UnregisterAllEvents(); ev:SetScript("OnEvent", nil) end
        if bar then bar:Hide() end
    end,

    Test = function()
        if bar and bar:IsShown() then bar:Hide()
        else EnsureBar(); Position(bar); bar:Show(); Reset(); UpdateBar("MOVE to ", "Sir Zeliek") end
    end,

    -- Boss-level unlock shows/hides the draggable bar.
    SetPreview = function(_, on)
        if on then EnsureBar(); Position(bar); bar:Show(); Reset(); UpdateBar("MOVE to ", "Sir Zeliek")
        elseif bar then bar:Hide() end
    end,

    BuildConfig = function(self, parent)
        local DS = _G.DaseekiSuite
        DS.MakeSlider(parent, 6, 20, 150, "Move every N marks", 1, 6, 1,
            function() return cfg().step end,
            function(v) cfg().step = v end,
            function(v) return string.format("%d", v) end)

        DS.MakeLabel(parent, "Direction", nil, 0, 56)
        local dd = DS.MakeSimpleDropdown(parent, 80, 52, 150, { "Clockwise", "Counter-clockwise" }, function(v)
            cfg().direction = (v == "Clockwise") and "cw" or "ccw"
        end)
        dd:SetValue(cfg().direction == "cw" and "Clockwise" or "Counter-clockwise")

        DS.MakeLabel(parent, "Start corner", nil, 0, 84)
        local cornerNames = {}
        for _, e in ipairs(ORDER) do cornerNames[#cornerNames + 1] = e.name end
        local sd = DS.MakeSimpleDropdown(parent, 80, 80, 150, cornerNames, function(v)
            for i, e in ipairs(ORDER) do if e.name == v then cfg().startCorner = i end end
        end)
        sd:SetValue(ORDER[cfg().startCorner] and ORDER[cfg().startCorner].name or ORDER[1].name)

        DS.MakeSlider(parent, 6, 128, 150, "Stack alarm", 1, 8, 1,
            function() return cfg().stackAlarm end,
            function(v) cfg().stackAlarm = v end,
            function(v) return string.format("%d", v) end)

        DS.MakeCheckbox(parent, "Sound on move", 0, 162,
            function() return cfg().moveSound end,
            function(v) cfg().moveSound = v and true or false end)
        DS.MakeCheckbox(parent, "Sound on wrong mark", 0, 188,
            function() return cfg().wrongSound end,
            function(v) cfg().wrongSound = v and true or false end)
    end,
})
