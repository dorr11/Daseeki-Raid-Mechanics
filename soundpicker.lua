--[[
    Daseeki Raid Mechanics — scrollable, searchable sound picker

    Replaces the (un-scrollable) Core dropdown for sound selection so large
    LibSharedMedia sound lists are usable. A themed popup with a search box, a
    mouse-wheel + scrollbar list, and a per-row preview (►) button.

    Public:
        Addon:ShowSoundPicker(currentKey, onPick, anchorFrame)
        Addon:HideSoundPicker()
--]]

local _, Addon = ...

local WIDTH   = 240
local ROW_H   = 20
local VISIBLE = 12
local SEARCH_H = 26
local PAD = 8

local picker, catcher
local offset, results, onPickCb = 0, {}, nil

local function Filter(query)
    query = (query or ""):lower()
    local out = {}
    for _, e in ipairs(Addon:GetSounds()) do
        if query == "" or (e.name and e.name:lower():find(query, 1, true)) then
            out[#out + 1] = e
        end
    end
    return out
end

local function Rebuild()
    if not picker then return end
    results = Filter(picker.search:GetText())
    local maxOffset = math.max(0, #results - VISIBLE)
    if offset > maxOffset then offset = maxOffset end
    if offset < 0 then offset = 0 end

    for i = 1, VISIBLE do
        local row = picker.rows[i]
        local entry = results[i + offset]
        if entry then
            row._entry = entry
            row.name:SetText(entry.name)
            row.name:SetTextColor(entry.key == picker._current and 1 or 0.9,
                                  entry.key == picker._current and 0.82 or 0.9,
                                  entry.key == picker._current and 0 or 0.9)
            row.play:SetShown(entry.key ~= "none")
            row:Show()
        else
            row._entry = nil
            row:Hide()
        end
    end

    picker.scroll:SetMinMaxValues(0, maxOffset)
    picker.scroll:SetValue(offset)
    picker.scroll:SetShown(maxOffset > 0)
end

local function EnsurePicker()
    if picker then return picker end
    local DS = _G.DaseekiSuite

    -- Click-catcher behind the popup closes it.
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:Hide()
    catcher:SetScript("OnClick", function() Addon:HideSoundPicker() end)

    local f = CreateFrame("Frame", "DaseekiRMSoundPicker", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, SEARCH_H + VISIBLE * ROW_H + PAD * 2 + 4)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(catcher:GetFrameLevel() + 10)
    Addon:ApplyDarkBackdrop(f, 0.97)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        Rebuild()
    end)
    f:SetScript("OnHide", function() if catcher then catcher:Hide() end end)
    tinsert(UISpecialFrames, "DaseekiRMSoundPicker")  -- Escape closes it

    -- Search box
    if DS and DS.MakeEditBox then
        f.search = DS.MakeEditBox(f, PAD + 2, PAD, WIDTH - PAD * 2 - 6)
    else
        f.search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        f.search:SetSize(WIDTH - PAD * 2 - 6, 20)
        f.search:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 2, -PAD)
        f.search:SetAutoFocus(false); f.search:SetFontObject(ChatFontNormal)
    end
    f.search:SetScript("OnTextChanged", function() offset = 0; Rebuild() end)
    f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Addon:HideSoundPicker() end)

    -- Scrollbar
    local sb = CreateFrame("Slider", nil, f)
    sb:SetWidth(12)
    sb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD + 2, -(SEARCH_H + PAD))
    sb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD + 2, PAD)
    sb:SetOrientation("VERTICAL")
    sb:SetValueStep(1); sb:SetObeyStepOnDrag(true)
    sb:SetMinMaxValues(0, 0); sb:SetValue(0)
    sb:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    local thumb = sb:GetThumbTexture(); thumb:SetSize(12, 32)
    local track = sb:CreateTexture(nil, "BACKGROUND"); track:SetAllPoints()
    track:SetColorTexture(0, 0, 0, 0.4)
    sb:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        if v ~= offset then offset = v; Rebuild() end
    end)
    f.scroll = sb

    -- Rows
    f.rows = {}
    for i = 1, VISIBLE do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(WIDTH - PAD * 2 - 16, ROW_H)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(SEARCH_H + PAD + (i - 1) * ROW_H))
        row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
        row.bg:SetColorTexture(0.2, 0.4, 0.7, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", row, "LEFT", 4, 0); row.name:SetJustifyH("LEFT")
        row.name:SetWidth(WIDTH - PAD * 2 - 44)

        -- preview (►) button
        row.play = CreateFrame("Button", nil, row)
        row.play:SetSize(18, 18); row.play:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.play.txt = row.play:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.play.txt:SetPoint("CENTER"); row.play.txt:SetText("|cff00ff00>|r")
        row.play:SetScript("OnClick", function()
            if row._entry then Addon:PlaySoundByKey(row._entry.key, true) end
        end)

        row:SetScript("OnEnter", function(s) s.bg:SetColorTexture(0.2, 0.4, 0.7, 0.5) end)
        row:SetScript("OnLeave", function(s) s.bg:SetColorTexture(0.2, 0.4, 0.7, 0) end)
        row:SetScript("OnClick", function(s)
            local e = s._entry
            if not e then return end
            if onPickCb then onPickCb(e.key) end
            if e.key ~= "none" then Addon:PlaySoundByKey(e.key, true) end
            Addon:HideSoundPicker()
        end)
        f.rows[i] = row
    end

    picker = f
    return f
end

function Addon:ShowSoundPicker(currentKey, onPick, anchorFrame)
    local f = EnsurePicker()
    onPickCb = onPick
    f._current = currentKey or "none"
    offset = 0
    f.search:SetText("")

    f:ClearAllPoints()
    if anchorFrame then
        f:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
    else
        f:SetPoint("CENTER")
    end

    -- Jump the list to the current selection.
    local all = Filter("")
    for i, e in ipairs(all) do
        if e.key == f._current then offset = math.max(0, i - 3); break end
    end

    if catcher then catcher:Show() end
    f:Show()
    Rebuild()
end

function Addon:HideSoundPicker()
    if picker then picker:Hide() end
end
