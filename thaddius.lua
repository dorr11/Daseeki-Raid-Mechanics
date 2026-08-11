--[[
    Daseeki Raid Mechanics — Thaddius-specific features

    1) Mini-Boss Health module: a draggable widget showing Stalagg (15929) +
       Feugen (15930) health (the adds you fight before Thaddius, same encounter).
       Scalable/opacity-adjustable like other items.

    2) Polarity-change watcher: monitors the player's charge debuff (by icon, like
       DBM: 135768 = Negative, 135769 = Positive) and fires only when it FLIPS
       (neg<->pos), never on a refresh.

       PROMOTED IN 2.1.1 (owner, 2026-08-10). The alert used to be a SUB-SECTION of
       the Polarity Shift options row — three checkboxes and a sound button that only
       appeared once you selected a row sitting next to a near-identical sibling
       ("Polarity Shift (cast)"). The owner asked whether the notification existed at
       all. It did; it was unfindable. It is now a first-class row of the encounter,
       `naxxramas:thaddius:polaritychanged`, and this file's job narrowed to the half
       only it can do:

         DETECTION stays here — the debuff-icon read is the only Era-correct way to
                   know your own charge, and no combat-log event announces a swap.
         PRESENTATION left — the row is emitted through `Addon:EmitAnnounce`, the same
                   seam the engine's own warning rows use, so ui_warnings.lua's router
                   decides where it lands (Major / Minor / Custom / Hidden), the sound
                   policy and the per-row sound picker decide whether and what it
                   plays, and the row's checkbox switches the whole thing off.

       WHY THE ROUTER AND NOT `Addon:ShowWarning`: ShowWarning is the 1.x centre-text
       surface. It has no bucket at all — it draws at a per-key saved position, and
       the key this alert used was the POLARITY SHIFT BAR's, so the alert and the bar
       shared one placement record and neither could be moved without the other. A
       Placement control over that would have been a dead control. Going through the
       router is what makes the full four-way choice honest for this row.

       The 2.1.0 settings (`pcEnabled` / `pcText` / `pcSound` / `pcSoundKey`, stored on
       the polarity bar's record) are adopted onto the new row at Init — see
       AdoptLegacyFlipConfig below.
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
    Addon:TrySetFont(c.header, "microLabel")   -- widget eyebrow (§3)
    -- Addon:Wrap resolves the brand token with Core and the legacy cyan without.
    c.header:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -2); c.header:SetText(Addon:Wrap("brand", "Mini-Bosses"))
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
        -- Suite face first (SetFontObject re-applies its colour), tint after.
        Addon:TrySetFont(row.name, "body"); Addon:TrySetFont(row.pct, "numeral")
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

    -- 2.0 placement seam (modules.lua). Metadata only; no logic moved.
    placeKey   = MH_KEY,
    placeLabel = "Thaddius add health",
    placeFrame = function() return mh end,

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
-- 2) Polarity-change watcher — DETECTION for the `polaritychanged` row
-- ════════════════════════════════════════════════════════════════════════════
local ENC_ID   = "naxxramas:thaddius"
local FLIP_ROW = "polaritychanged"
-- API.OptionKey(encId, rowKey) == Addon:MechKey(raidId, bossId, rowKey) by
-- construction (core_api §E), which is why this literal is the row's own key and not
-- a second namespace that would have to be kept in step with it.
local FLIP_KEY = ENC_ID .. ":" .. FLIP_ROW
-- Where 2.1.0 kept the four sub-panel settings: on the POLARITY SHIFT BAR's record.
local OLD_KEY  = "naxxramas:thaddius:polarity"
local NEG_ICON, POS_ICON = 135768, 135769
local lastCharge

-- PER-CHARGE COLOURING, KEPT. The old centre-text tinted the whole line gold or blue;
-- an announce line wears the surface's own palette for its colour class, so the tint
-- moves inside the text and marks the word that actually differs. A colour escape in
-- a string the warning surface renders is not a theme decision about a frame, which is
-- why these are literals and not tokens.
local CHARGE = {
    pos = { label = "Positive", hex = "|cffffd23a" },
    neg = { label = "Negative", hex = "|cff66a3ff" },
}

local function FlipRow()
    local enc = Addon.GetEncounter and Addon:GetEncounter(ENC_ID)
    return enc and enc.rowsByKey and enc.rowsByKey[FLIP_ROW] or nil
end

-- THE ONE RENDERER, and the only place this file draws the flip alert. The live aura
-- path calls it on a real flip; the testing suite calls it with a simulated one. Both
-- go out through `Addon:EmitAnnounce` — the engine's own warning seam — so the router,
-- the sound policy and the per-row sound override all apply without this file naming
-- any of them.
--
-- `force` is the rehearsal's: pressing Play is an explicit request to see this row
-- now, exactly as `T.Row` treats every other row's enable checkbox.
local function AnnounceFlip(charge, force)
    local row = FlipRow()
    if not row then return nil end
    local API = Addon.API
    if not force and API and API.IsRowEnabled and not API.IsRowEnabled(ENC_ID, row) then
        return nil
    end
    local c = CHARGE[charge] or CHARGE.neg
    return Addon:EmitAnnounce(ENC_ID, row,
        (row.text or "Polarity CHANGED") .. " \226\134\146 " .. c.hex .. c.label .. "|r")
end

local function CurrentCharge()
    for i = 1, 40 do
        local name, icon = UnitDebuff("player", i)
        if not name then break end
        if icon == NEG_ICON then return "neg"
        elseif icon == POS_ICON then return "pos" end
    end
    return nil
end

-- FLIP-ONLY, UNCHANGED. The charge is tracked on every aura event whether the row is
-- enabled or not — the alternative is a phantom "flip" the first time someone ticks
-- the row on mid-fight, because the watcher would have no previous charge to compare
-- against. Only the ANNOUNCE is gated, and it is gated by the row.
local function OnPlayerAura()
    local charge = CurrentCharge()
    if not charge then return end
    if lastCharge and charge ~= lastCharge then AnnounceFlip(charge) end
    lastCharge = charge
end

local polEv = CreateFrame("Frame")
polEv:RegisterUnitEvent("UNIT_AURA", "player")
polEv:RegisterEvent("PLAYER_REGEN_ENABLED")
polEv:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then lastCharge = nil   -- reset between pulls
    else OnPlayerAura() end
end)

-- THE PLAY BUTTON, through the real renderer. A row the engine cannot fire has nothing
-- for the suite's generic warning path to reconstruct, so this file publishes the
-- rehearsal for its own row: an alternating SIMULATED FLIP through `AnnounceFlip`. It
-- runs inside the suite's quarantine (T.active), so nothing it produces reaches the
-- stats, the sync channel or the timing tripwire. The Cue button needs nothing here —
-- a row's cue is `Warn.DispatchSound` over the row, and this row is a real one.
local previewCharge = "neg"
if Addon.Testing and Addon.Testing.RegisterRowPreview then
    Addon.Testing.RegisterRowPreview(ENC_ID, FLIP_ROW, function()
        previewCharge = (previewCharge == "pos") and "neg" or "pos"
        return AnnounceFlip(previewCharge, true)
    end)
end

-- ── 2.1.0 -> 2.1.1: the sub-panel's settings, adopted onto the row ─────────────
-- ADDITIVE AND RE-READABLE. The four `pc*` fields are left exactly where they are, and
-- the record they sat on is marked `pcAdopted` so a second login cannot re-apply
-- choices the player has since changed on the new row. DB_VERSION does not move:
-- nothing here changes the SHAPE of the config model, it copies four values between
-- two records that already have the shape they need.
--
-- THE MAPPING, and why each lands where it does:
--   pcEnabled  -> masterEnabled  the row's list checkbox IS "does this alert exist"
--   pcText     -> route          "Center-screen text" OFF meant sound-only, which is
--                                what Hidden means, verbatim: "Not drawn. Sounds and
--                                voice still play." Text ON leaves the route unset so
--                                the row follows its own severity, like any other.
--   pcSound    -> soundMode      an explicit On/Off: the player expressed an opinion,
--                                and an opinion outlives a policy default
--   pcSoundKey -> sound          the per-row sound file the picker already stores
--
-- An ABSENT field takes the 2.1.0 default (off / text on / sound on / raidwarning), so
-- what carries over is the behaviour the player actually had rather than the subset of
-- fields they happened to have written.
local function AdoptLegacyFlipConfig(db)
    local old = db and db.mechanics and db.mechanics[OLD_KEY]
    if type(old) ~= "table" or old.pcAdopted then return nil end
    if old.pcEnabled == nil and old.pcText == nil
       and old.pcSound == nil and old.pcSoundKey == nil then return nil end

    local enabled = old.pcEnabled and true or false
    local drawn   = (old.pcText  ~= false)
    local sounds  = (old.pcSound ~= false)

    Addon:SetMechanicOption(FLIP_KEY, "masterEnabled", enabled)
    Addon:SetMechanicOption(FLIP_KEY, "route", (not drawn) and "hidden" or nil)
    Addon:SetMechanicOption(FLIP_KEY, "soundMode", sounds and "on" or "off")
    Addon:SetMechanicOption(FLIP_KEY, "sound", old.pcSoundKey or "raidwarning")
    old.pcAdopted = true
    return FLIP_KEY
end
Addon.PROFILE_ADOPTERS[#Addon.PROFILE_ADOPTERS + 1] = AdoptLegacyFlipConfig
Addon.AdoptLegacyFlipConfig = AdoptLegacyFlipConfig   -- named so the harness drives it
