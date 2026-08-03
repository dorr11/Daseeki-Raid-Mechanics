--[[
    Daseeki Raid Mechanics — styled alert displays + cooldown/window engine

    A single pooled "Display" frame renders any of the per-mechanic styles:
        bar       — DBM-style countdown bar (icon + name + countdown + spark)
        castbar   — bar that fills over the boss's actual cast time
        icon      — skill icon + radial cooldown sweep + time text inside
        nameplate — like icon, attached to the boss's nameplate when visible
        number    — large countdown number only
        text      — text-only banner (fades)
        flash     — large center icon + text (scale-in / fade)
        pulse     — icon that pulses (scale) to grab attention

    Behaviour modes (mechDef.mode):
        alert    — one-shot: on trigger, show for a duration then auto-hide.
        cooldown — persistent recurring cycle (the Kel'Thuzad case):
                   count down to the window -> glow until the cast is detected ->
                   reset and count down again. Window-open is configurable per
                   mechanic (always glows; optional sound and/or warning text).

    Each display anchors at the mechanic's OWN saved position and uses its own
    scale + opacity. Placement preview reuses the real display (WYSIWYG).

    Public:
        Addon:FireAlert(key, mechDef [, force])      -- one-shot
        Addon:StartCooldown(key, mechDef)            -- begin a cooldown tracker
        Addon:ResetCooldown(key)                     -- cast detected -> restart cycle
        Addon:StopAllCooldowns()
        Addon:UnlockBoss(raidId, bossId) / Addon:LockAll()  -- boss-level drag-to-place
        Addon:ShowPlacement(key, mechDef) / Addon:HideAllPlacements()
--]]

local _, Addon = ...

local QUESTION   = "Interface\\Icons\\INV_Misc_QuestionMark"
local ICON_BASE  = 40
local ATTN_TIME  = 2.2      -- seconds an attention-style one-shot stays up
local DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = 160 }
-- On-cast text popups default to the top-middle of the screen.
local DEFAULT_TOP_POS = { point = "TOP", relPoint = "TOP", x = 0, y = -120 }
Addon.DEFAULT_TOP_POS = DEFAULT_TOP_POS

-- style -> rendering kind + whether it shows a countdown
local STYLE_INFO = {
    bar       = { kind = "bar",  countdown = true },
    castbar   = { kind = "bar",  countdown = true },
    icon      = { kind = "icon", countdown = true },
    nameplate = { kind = "icon", countdown = true, attach = true },
    number    = { kind = "num",  countdown = true },
    text      = { kind = "text", countdown = false },
    flash     = { kind = "icon", countdown = false, big = true },
    pulse     = { kind = "icon", countdown = false, pulse = true },
}

function Addon:GetAnchorPos(key, defaultPos)
    local m = Addon.db and Addon.db.mechanics[key]
    if m and m.pos then return m.pos end
    return defaultPos or DEFAULT_POS
end

-- Merged per-mechanic flag read (DB override > data-file default), for flags that
-- aren't part of GetMechanicConfig's schema (e.g. `special`, `countdownVoice`).
local function MechFlag(key, mechDef, field)
    local o = Addon.db and Addon.db.mechanics[key]
    if o and o[field] ~= nil then return o[field] end
    return mechDef and mechDef[field]
end

local function FmtTime(secs)
    secs = math.max(0, secs)
    if secs >= 60 then return string.format("%d:%02d", math.floor(secs / 60), secs % 60) end
    if secs >= 10 then return string.format("%d", math.floor(secs + 0.5)) end
    return string.format("%.1f", secs)
end

-- ── Boss nameplate lookup (for the "nameplate" style) ───────────────────────────
local function BossNameplate()
    if not Addon.active or not C_NamePlate then return nil end
    local npcs = Addon.active.boss.npcIDs or {}
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken
        if unit then
            local guid = UnitGUID(unit)
            if guid then
                local _, _, _, _, _, id = strsplit("-", guid)
                id = tonumber(id)
                for _, n in ipairs(npcs) do if n == id then return plate end end
            end
        end
    end
    return nil
end

-- ── Display construction ────────────────────────────────────────────────────────
Addon._displayPool     = {}
Addon._activeOneshot   = {}   -- key -> display (transient)
Addon._cooldownDisplays = {}  -- key -> display (persistent)

local OnUpdate  -- fwd

local function NewDisplay()
    local s = Addon.db.settings
    local d = CreateFrame("Frame", nil, UIParent)
    d:SetFrameStrata("HIGH")

    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    d.iconBorder = Addon:AddIconBorder(d.icon, d)
    d.iconBorder:Hide()

    d.cd = CreateFrame("Cooldown", nil, d, "CooldownFrameTemplate")
    if d.cd.SetHideCountdownNumbers then d.cd:SetHideCountdownNumbers(true) end
    if d.cd.SetDrawEdge then d.cd:SetDrawEdge(true) end
    d.cd.noCooldownCount = true   -- opt out of OmniCC-style external countdown text

    -- Host frame the "glow under X sec" overlay attaches to (sized to the icon).
    d.glowHost = CreateFrame("Frame", nil, d)

    d.bar = CreateFrame("StatusBar", nil, d)
    d.bar.bg = d.bar:CreateTexture(nil, "BACKGROUND"); d.bar.bg:SetAllPoints()
    d.bar.bg:SetColorTexture(Addon:ThemeColor("barBG"))
    Addon:AddBorder(d.bar)
    d.bar.spark = d.bar:CreateTexture(nil, "OVERLAY")
    d.bar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    d.bar.spark:SetBlendMode("ADD")

    -- Foreground frame stacked ABOVE the bar fill so the name/time text stays
    -- readable (font strings on `d` itself render under the StatusBar child).
    d.fg = CreateFrame("Frame", nil, d)
    d.fg:SetAllPoints(d)
    d.fg:SetFrameLevel(d.bar:GetFrameLevel() + 3)

    -- Bar name + countdown. TrySetFont FIRST, StyleFont after: SetFontObject also
    -- re-applies that object's colour, so the token tint has to land last.
    d.label = d.fg:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.time  = d.fg:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Addon:TrySetFont(d.label, "body")
    Addon:TrySetFont(d.time,  "numeral")   -- a countdown is telemetry (BRAND_SPEC §3)
    Addon:StyleFont(d.label); Addon:StyleFont(d.time)

    -- Small running cast-count badge (corner of the icon) for showCount mechanics.
    d.count = d.fg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Addon:TrySetFont(d.count, "numeral")
    Addon:StyleFont(d.count, "warnText")   -- was a literal amber; now the theme's warn role
    d.count:Hide()

    -- Glow border (shown during a cooldown window). Works on any rectangle.
    d.glow = CreateFrame("Frame", nil, d, "BackdropTemplate")
    d.glow:SetPoint("TOPLEFT", d, "TOPLEFT", -4, 4)
    d.glow:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 4, -4)
    d.glow:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
    d.glow:SetBackdropBorderColor(1, 0.85, 0.2, 1)
    d.glow:Hide()

    d:SetScript("OnUpdate", OnUpdate)
    d:Hide()
    return d
end

local function AcquireDisplay()
    return table.remove(Addon._displayPool) or NewDisplay()
end

-- WeakAuras-style overlay glow (same as Daseeki Buff Tracker) used by the
-- per-mechanic "glow under X sec" option. Idempotent via d._oglow.
local function OverlayGlowOn(d)
    if d._oglow then return end
    d._oglow = true
    local host = d.glowHost
    if ActionButton_ShowOverlayGlow and host then
        ActionButton_ShowOverlayGlow(host)
        local g = host.overlay or host.SpellActivationAlert or host.__LBGoverlay
        if g then
            local w, h = host:GetSize()
            g:ClearAllPoints(); g:SetSize(w * 1.5, h * 1.5); g:SetPoint("CENTER", host, "CENTER", 0, 0)
        end
    end
end

local function OverlayGlowOff(d)
    if not d._oglow then return end
    d._oglow = false
    if ActionButton_HideOverlayGlow and d.glowHost then ActionButton_HideOverlayGlow(d.glowHost) end
end

local function ReleaseDisplay(d)
    d:Hide()
    d.glow:Hide()
    OverlayGlowOff(d)
    -- A display going away mid-count must silence its pending voice numbers.
    if d._voiceLive then Addon:StopVoiceCountdown() end
    d._voiceLive, d._voiceFired, d._voiceEnabled = nil, nil, nil
    d.cd:Hide()
    d.count:Hide(); d._showCount = nil
    d:SetScale(1); d:SetAlpha(1)
    -- Fully reset so a recycled placement frame returns to the pool clean.
    d:EnableMouse(false); d:SetMovable(false)
    d:SetScript("OnMouseDown", nil); d:SetScript("OnMouseUp", nil)
    d:SetScript("OnUpdate", OnUpdate)
    d:SetFrameStrata("HIGH")
    if d._key and Addon._activeOneshot[d._key] == d then
        Addon._activeOneshot[d._key] = nil
    end
    d._key, d._mode, d._state, d._info, d._cfg, d._mechDef = nil, nil, nil, nil, nil, nil
    Addon._displayPool[#Addon._displayPool + 1] = d
end
Addon.ReleaseDisplay = ReleaseDisplay

-- ── Layout for a given style ────────────────────────────────────────────────────
local function HideParts(d)
    d.icon:Hide(); d.iconBorder:Hide(); d.cd:Hide(); d.bar:Hide(); d.label:Hide(); d.time:Hide(); d.glow:Hide()
    d.count:Hide()
end

local function PositionDisplay(d, key)
    local pos = Addon:GetAnchorPos(key, d._mechDef and d._mechDef._defaultPos)
    d:ClearAllPoints()
    d:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
end

local function Configure(d, key, cfg, mechDef)
    local info = STYLE_INFO[cfg.style] or STYLE_INFO.bar
    d._info, d._cfg, d._mechDef, d._key = info, cfg, mechDef, key

    -- Optional lead-up "reminder" sub-alert (its own keyed pseudo-mechanic).
    if mechDef.reminder then d._remDef, d._remKey = mechDef.reminder, key .. "#rem"
    else d._remDef, d._remKey, d._remEnabled = nil, nil, false end

    d._showCount = mechDef.showCount or false

    HideParts(d)
    d:SetScale(cfg.scale or 1)
    d:SetAlpha(cfg.opacity or 1)

    local s = Addon.db.settings
    local color = mechDef.barColor or { 0.25, 0.55, 0.95 }
    d.icon:SetTexture(mechDef.icon or QUESTION)

    if info.kind == "bar" then
        d:SetSize(s.barWidth, s.barHeight)
        d.bar:ClearAllPoints(); d.bar:SetPoint("TOPLEFT", s.barHeight, 0); d.bar:SetPoint("BOTTOMRIGHT", 0, 0)
        d.bar:SetStatusBarTexture(Addon.Theme.statusbar)
        d.bar:SetStatusBarColor(color[1], color[2], color[3])
        d.bar:SetMinMaxValues(0, 1); d.bar:SetValue(1)
        d.bar.spark:SetSize(16, s.barHeight * 2)
        d.icon:ClearAllPoints(); d.icon:SetPoint("RIGHT", d.bar, "LEFT", 0, 0); d.icon:SetSize(s.barHeight, s.barHeight)
        d.glowHost:ClearAllPoints(); d.glowHost:SetPoint("RIGHT", d.bar, "LEFT", 0, 0); d.glowHost:SetSize(s.barHeight, s.barHeight)
        d.label:ClearAllPoints(); d.label:SetPoint("LEFT", d.bar, "LEFT", 4, 0); d.label:SetJustifyH("LEFT")
        d.label:SetText(mechDef.name or "")
        d.time:ClearAllPoints(); d.time:SetPoint("RIGHT", d.bar, "RIGHT", -4, 0); d.time:SetJustifyH("RIGHT")
        d.icon:Show(); d.iconBorder:Show(); d.bar:Show(); d.label:Show(); d.time:Show()

    elseif info.kind == "icon" then
        local sz = info.big and ICON_BASE * 1.6 or ICON_BASE
        d:SetSize(sz, sz)
        d.icon:ClearAllPoints(); d.icon:SetAllPoints(d)
        d.glowHost:ClearAllPoints(); d.glowHost:SetAllPoints(d)
        d.cd:ClearAllPoints(); d.cd:SetAllPoints(d)
        d.time:ClearAllPoints(); d.time:SetPoint("CENTER", d, "CENTER", 0, 0); d.time:SetJustifyH("CENTER")
        d.icon:Show(); d.iconBorder:Show()
        if info.countdown then d.cd:Show(); d.time:Show() end
        if d._showCount then
            d.count:ClearAllPoints()
            d.count:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -1, 1)
            d.count:Show()
        end
        if info.big then
            d.label:ClearAllPoints(); d.label:SetPoint("TOP", d, "BOTTOM", 0, -2)
            d.label:SetText(mechDef.warningText or mechDef.name or ""); d.label:Show()
        end

    elseif info.kind == "num" then
        d:SetSize(64, 40)
        d.time:ClearAllPoints(); d.time:SetPoint("CENTER", d, "CENTER", 0, 0); d.time:SetJustifyH("CENTER")
        d.time:Show()

    elseif info.kind == "text" then
        -- Configurable typeface + point size (defaults to a large, readable banner —
        -- e.g. the on-cast notification). Box auto-sizes to the chosen font/text.
        local fontSize = cfg.fontSize or 32
        d.label:ClearAllPoints()
        d.label:SetFont(Addon:GetFontPath(cfg.fontKey), fontSize, "OUTLINE")
        d.label:SetJustifyH("CENTER")
        d.label:SetText(mechDef.warningText or mechDef.name or "")
        d.label:SetTextColor((mechDef.warningColor or color)[1], (mechDef.warningColor or color)[2], (mechDef.warningColor or color)[3])
        local w = math.max(360, math.min(820, (d.label:GetStringWidth() or 0) + 40))
        d:SetSize(w, fontSize + 26)
        d.label:SetPoint("CENTER", d, "CENTER", 0, 0)
        d.label:Show()
    end

    PositionDisplay(d, key)
end

-- ── Per-frame update ────────────────────────────────────────────────────────────
local function UpdateCountdownVisual(d, rem, dur)
    local info = d._info
    if info.attach then
        local plate = BossNameplate()
        if plate then
            d:ClearAllPoints(); d:SetPoint("CENTER", plate, "CENTER", 0, 0)
        else
            PositionDisplay(d, d._key)
        end
    end
    if info.kind == "bar" then
        local frac = dur > 0 and (rem / dur) or 0
        d.bar:SetValue(frac)
        d.time:SetText(FmtTime(rem))
        local w = d.bar:GetWidth() or 0
        d.bar.spark:ClearAllPoints()
        d.bar.spark:SetPoint("CENTER", d.bar, "LEFT", w * frac, 0)
    else
        d.time:SetText(FmtTime(rem))
    end

    -- "Glow under X sec": WA-style overlay glow when time is low. Applies to the
    -- icon (icon/radial styles) or the bar's left icon (bar/castbar styles).
    local thr = (d._cfg and d._cfg.glowThreshold) or 0
    if thr > 0 and (info.kind == "icon" or info.kind == "bar") then
        if rem <= thr then OverlayGlowOn(d) else OverlayGlowOff(d) end
    elseif d._oglow then
        OverlayGlowOff(d)
    end
end

local function ShowGlow(d) d.glow:Show() end
local function HideGlow(d) d.glow:Hide() end

local function PulseGlow(d)
    local a = 0.4 + 0.6 * math.abs(math.sin(GetTime() * 3))
    d.glow:SetBackdropBorderColor(1, 0.85, 0.2, a)
end

local function EnterOpen(d)
    d._state = "open"
    d.time:SetText("")
    if d._info.kind == "bar" then d.bar:SetValue(1) end
    ShowGlow(d)
    local cfg, mech = d._cfg, d._mechDef
    d._voiceLive = nil   -- any voice count for this cycle has finished naturally
    if cfg.winWarning and MechFlag(d._key, mech, "special") == true then
        -- Special-flagged mechanics escalate to the big tier (sound rides along).
        Addon:ShowSpecialWarning(d._key, (mech.warningText or mech.name or "") .. " — ready!",
            mech.warningColor or mech.barColor, cfg.winSound and cfg.sound or nil)
    else
        if cfg.winWarning then
            Addon:ShowWarning(d._key, (mech.warningText or mech.name or "") .. " — ready!", mech.warningColor or mech.barColor)
        end
        if cfg.winSound then
            Addon:PlaySoundByKey(cfg.sound)
        end
    end
    -- noLoop (e.g. a one-shot phase countdown): warn once at 0, then clear — don't
    -- sit pulsing forever or restart on a recast.
    if mech.noLoop then
        if Addon._cooldownDisplays[d._key] == d then Addon._cooldownDisplays[d._key] = nil end
        ReleaseDisplay(d)
    end
end

-- Substitutes a live cast count into a "%d"-templated text (e.g. "Spore %d"), for
-- mechanics that define `showCount`. `offset` accounts for WHEN the text fires
-- relative to the count increment (which happens at cast time, in engine.lua's
-- Dispatch): 0 for on-cast text (count already incremented), +1 for the reminder/
-- "soon" warning (fires BEFORE the next cast, so show the upcoming number).
local function FormatCountText(text, mechDef, key, offset)
    if not text or not mechDef or not mechDef.showCount then return text end
    if not text:find("%%d") then return text end
    local n = (Addon._mechCount and Addon._mechCount[key] or 0) + (offset or 0)
    return string.format(text, n)
end

-- Fire the lead-up reminder (a one-shot radial/text at its own anchor/scale/sound).
local function FireReminder(d)
    local rd = d._remDef
    if not rd then return end
    d._remSynth = d._remSynth or {}
    local s = d._remSynth
    s.name, s.icon, s.style = rd.name or "Reminder", rd.icon, rd.style or "icon"
    s.barColor, s.sound = rd.barColor, rd.sound
    s.warningText = FormatCountText(rd.warningText, d._mechDef, d._key, 1)
    s.default, s.glowThreshold = rd.default, rd.glowThreshold
    s.barDuration = d._remLead or 5
    Addon:FireAlert(d._remKey, s)
end

OnUpdate = function(d)
    local now = GetTime()
    if d._mode == "oneshot" then
        if d._countdown then
            local rem = d._endTime - now
            if rem <= 0 then ReleaseDisplay(d); return end
            UpdateCountdownVisual(d, rem, d._duration)
        else
            -- attention animation (flash / pulse / text)
            local t = now - d._startTime
            if now >= d._expireAt then ReleaseDisplay(d); return end
            if d._info.pulse then
                d:SetScale((d._cfg.scale or 1) * (1 + 0.25 * math.abs(math.sin(t * 6))))
            elseif d._info.big then
                local k = math.min(1, t / 0.15)
                d:SetScale((d._cfg.scale or 1) * (1.6 - 0.6 * k))
            end
            -- fade out in the last 0.5s
            local left = d._expireAt - now
            if left < 0.5 then d:SetAlpha((d._cfg.opacity or 1) * (left / 0.5)) end
        end
    elseif d._mode == "cooldown" then
        if d._showCount and Addon._mechCount then
            local c = Addon._mechCount[d._key]
            d.count:SetText(c and c > 0 and tostring(c) or "")
        end
        if d._state == "counting" then
            local rem = d._endTime - now
            if rem <= 0 then EnterOpen(d); return end
            UpdateCountdownVisual(d, rem, d._duration)
            if d._remEnabled and not d._remFired and rem <= (d._remLead or 5) then
                d._remFired = true
                FireReminder(d)
            end
            -- Voice count: once per cycle, when the window-open moment crosses 5s
            -- out, speak "5... 4... 3... 2... 1". Floor+round covers short cycles
            -- and frame hitches (never speaks more seconds than actually remain).
            if d._voiceEnabled and not d._voiceFired and rem <= 5 then
                d._voiceFired = true
                local n = math.min(5, math.floor(rem + 0.5))
                if n >= 1 and Addon:PlayVoiceCountdown(n) then
                    d._voiceLive = true
                end
            end
        elseif d._state == "open" then
            PulseGlow(d)
        end
    end
end

-- ── One-shot alert duration ─────────────────────────────────────────────────────
local function AlertDuration(cfg, mechDef)
    if cfg.style == "castbar" then
        if mechDef.castTime then return mechDef.castTime end
        if mechDef.trigger and mechDef.trigger.spellID then
            local _, _, _, castMs = GetSpellInfo(mechDef.trigger.spellID)
            if castMs and castMs > 0 then return castMs / 1000 end
        end
    end
    return mechDef.barDuration or 5
end

-- ── Public: one-shot ────────────────────────────────────────────────────────────
function Addon:FireAlert(key, mechDef, force)
    local cfg = Addon:GetMechanicConfig(key, mechDef)
    if not force and (not Addon.db.settings.enabled or not cfg.enabled) then return end

    -- Special-flagged mechanics escalate their trigger warning to the big tier
    -- (same MechFlag routing as the cooldown winWarning hook in EnterOpen). The
    -- configured sound rides along as soundKey so it isn't double-played; fallback
    -- when settings.specialWarnings == false degrades inside ShowSpecialWarning.
    if MechFlag(key, mechDef, "special") == true then
        Addon:ShowSpecialWarning(key, mechDef.warningText or mechDef.name or "",
            mechDef.warningColor or mechDef.barColor, cfg.sound)
    else
        Addon:PlaySoundByKey(cfg.sound)
    end

    local info = STYLE_INFO[cfg.style] or STYLE_INFO.bar
    local d = Addon._activeOneshot[key] or AcquireDisplay()
    Addon._activeOneshot[key] = d
    Configure(d, key, cfg, mechDef)

    local now = GetTime()
    d._mode = "oneshot"
    if info.countdown then
        local dur = AlertDuration(cfg, mechDef)
        d._countdown = true; d._duration = dur; d._endTime = now + dur
        if info.kind == "icon" then d.cd:SetCooldown(now, dur) end
        UpdateCountdownVisual(d, dur, dur)
    else
        d._countdown = false; d._startTime = now; d._expireAt = now + ATTN_TIME
    end
    d:Show()
    return d
end

-- ── Public: cooldown / window cycle ─────────────────────────────────────────────
local function EnterCounting(d, cooldown)
    local now = GetTime()
    d._state = "counting"; d._duration = cooldown; d._endTime = now + cooldown
    HideGlow(d)
    if d._info.kind == "icon" then d.cd:SetCooldown(now, cooldown) end
    UpdateCountdownVisual(d, cooldown, cooldown)
    -- Voice countdown state: cancel anything in flight from the previous cycle
    -- (an early ResetCooldown resync must not leave stray numbers), then re-read
    -- the toggles for this cycle.
    if d._voiceLive then Addon:StopVoiceCountdown(); d._voiceLive = nil end
    d._voiceFired = false
    d._voiceEnabled = MechFlag(d._key, d._mechDef, "countdownVoice") == true
        and Addon.db.settings.countdownVoice ~= false
    -- Refresh reminder state each cycle (picks up option toggles).
    d._remFired = false
    if d._remDef then
        local rc = Addon:GetMechanicConfig(d._remKey, d._remDef)
        d._remEnabled = rc.enabled
        d._remLead = rc.leadTime or 5
    else
        d._remEnabled = false
    end
end

-- `initial` overrides the first countdown length (e.g. mechDef.firstCast for an
-- ability with a known opening time); subsequent ResetCooldowns use cfg.cooldown.
function Addon:StartCooldown(key, mechDef, initial)
    local cfg = Addon:GetMechanicConfig(key, mechDef)
    if not Addon.db.settings.enabled or not cfg.enabled then return end
    local d = Addon._cooldownDisplays[key] or AcquireDisplay()
    Addon._cooldownDisplays[key] = d
    Configure(d, key, cfg, mechDef)
    d._mode = "cooldown"
    EnterCounting(d, initial or cfg.cooldown or 10)
    d:Show()
end

function Addon:ResetCooldown(key)
    local d = Addon._cooldownDisplays[key]
    if not d then return end
    EnterCounting(d, (d._cfg and d._cfg.cooldown) or 10)
end

function Addon:StopAllCooldowns()
    for _, d in pairs(Addon._cooldownDisplays) do ReleaseDisplay(d) end
    wipe(Addon._cooldownDisplays)
end

-- ── Center / anchored warning text (used by winWarning and the "flash" path) ────
Addon._warnPool = {}

local function NewWarning()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(500, 40); f:SetFrameStrata("HIGH")
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    -- Keep the Huge tier's SIZE + outline (that is what makes a center warning read
    -- across a raid) but take the FACE from the suite picker when Core is present.
    -- ShowWarning tints per call, so no colour is set here.
    Addon:ReFaceKeepingSize(f.text)
    f.text:SetPoint("CENTER"); f.text:SetJustifyH("CENTER")
    f:SetScript("OnUpdate", function(self, elapsed)
        self._e = self._e + elapsed
        local t = self._e
        if t < 0.15 then self.text:SetScale(1.6 - 0.6 * (t / 0.15)); self:SetAlpha(t / 0.15)
        elseif t < 1.7 then self.text:SetScale(1); self:SetAlpha(1)
        elseif t < 2.2 then self:SetAlpha(1 - (t - 1.7) / 0.5)
        else self:Hide(); self.text:SetScale(1); Addon._warnPool[#Addon._warnPool + 1] = self end
    end)
    return f
end

function Addon:ShowWarning(key, text, color, defaultPos)
    local f = table.remove(Addon._warnPool) or NewWarning()
    f.text:SetText(text or "")
    color = color or { 1, 0.3, 0.3 }
    f.text:SetTextColor(color[1], color[2], color[3])
    local pos = Addon:GetAnchorPos(key, defaultPos)
    f:ClearAllPoints()
    f:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, (pos.y or 0) + 34)
    f._e = 0; f:SetAlpha(0); f:Show()
    return f
end

-- ── Special Warning tier (bigger, higher, louder — DBM "special warning" parity) ─
-- A tier ABOVE ShowWarning: larger font, longer hold, its own shared drag anchor
-- (SPECIAL_ANCHOR — one saved position for the whole tier, like DBM's), plus a
-- brief low-alpha screen-edge flash. Callable outside combat for previews.
Addon._specialPool = {}

local DEFAULT_SPECIAL_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = 260 }
Addon.DEFAULT_SPECIAL_POS = DEFAULT_SPECIAL_POS
local SPECIAL_ANCHOR = "#special"   -- pseudo-key for the tier's saved position
Addon.SPECIAL_ANCHOR = SPECIAL_ANCHOR

-- Full-screen edge flash (lazily created, reused). Never blocks the mouse.
local specialFlash

local function EdgeFlash(color)
    if not specialFlash then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetAllPoints(UIParent)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(false)
        if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
        f.tex = f:CreateTexture(nil, "BACKGROUND")
        f.tex:SetAllPoints(f)
        f.tex:SetTexture("Interface\\FullScreenTextures\\LowHealth")   -- stock edge vignette
        f.tex:SetBlendMode("ADD")
        f:SetScript("OnUpdate", function(self, elapsed)
            self._e = self._e + elapsed
            local t = self._e
            if t >= 0.6 then self:Hide(); return end
            local k = (t < 0.3) and (t / 0.3) or (1 - (t - 0.3) / 0.3)   -- in 0.3s, out 0.3s
            self:SetAlpha(k * 0.25)
        end)
        f:Hide()
        specialFlash = f
    end
    local c = color or { 1, 0.3, 0.3 }
    specialFlash.tex:SetVertexColor(c[1], c[2], c[3])
    specialFlash._e = 0
    specialFlash:SetAlpha(0)
    specialFlash:Show()
end

local function NewSpecialWarning()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(700, 60); f:SetFrameStrata("HIGH")
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.text:SetPoint("CENTER"); f.text:SetJustifyH("CENTER")
    Addon:ReFaceKeepingSize(f.text)          -- suite face, Huge size + flags preserved
    local path, size, flags = f.text:GetFont()
    f.text:SetFont(path, math.floor(size * 1.4 + 0.5), flags)   -- ~1.4x the normal tier
    Addon:StyleFont(f.text)
    f:SetScript("OnUpdate", function(self, elapsed)
        self._e = self._e + elapsed
        local t = self._e
        if t < 0.15 then self.text:SetScale(1.6 - 0.6 * (t / 0.15)); self:SetAlpha(t / 0.15)
        elseif t < 3.15 then self.text:SetScale(1); self:SetAlpha(1)
        elseif t < 3.65 then self:SetAlpha(1 - (t - 3.15) / 0.5)
        else self:Hide(); self.text:SetScale(1); Addon._specialPool[#Addon._specialPool + 1] = self end
    end)
    return f
end

function Addon:ShowSpecialWarning(key, text, color, soundKey)
    color = color or { 1, 0.3, 0.3 }
    if Addon.db and Addon.db.settings.specialWarnings == false then
        -- Tier disabled: degrade to an ordinary warning so the info still lands.
        Addon:ShowWarning(key, text, color)
        if soundKey then Addon:PlaySoundByKey(soundKey) end
        return
    end
    local f = table.remove(Addon._specialPool) or NewSpecialWarning()
    f.text:SetText(text or "")
    f.text:SetTextColor(color[1], color[2], color[3])
    local pos = Addon:GetAnchorPos(SPECIAL_ANCHOR, DEFAULT_SPECIAL_POS)
    f:ClearAllPoints()
    f:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
    EdgeFlash(color)
    if soundKey then Addon:PlaySoundByKey(soundKey, true) end
    f._e = 0; f:SetAlpha(0); f:Show()
    return f
end

-- On-cast alert: a popup the moment a mechanic fires, defaulting to a top-middle
-- text banner. Opt-in by default (`mechDef.onCastDefault` lets a specific mechanic
-- default it ON instead, e.g. Loatheb's Spore). Stored under its own pseudo-key
-- (key.."#cast"). Routed through FireAlert so the per-#cast style/scale/sound/
-- position the user sets in the detail editor all apply. `castText` supports a
-- "%d" placeholder for `showCount` mechanics (substituted with the live count).
function Addon:FireOnCast(key, mechDef)
    if not Addon.db.settings.enabled then return end
    local castKey = key .. "#cast"
    if not Addon:GetMechanicConfig(castKey, { default = mechDef.onCastDefault and true or false }).enabled then return end
    local text = FormatCountText(mechDef.castText, mechDef, key, 0)
        or mechDef.castText or mechDef.warningText or mechDef.name
    Addon:FireAlert(castKey, {
        name = "On-cast: " .. (mechDef.name or ""),
        style = "text", default = false,
        warningText = text,
        barColor = mechDef.barColor, warningColor = mechDef.warningColor,
        _defaultPos = DEFAULT_TOP_POS,
    }, true)
end

-- Personal Damage Warning (opt-in): fires when YOU actually take damage from a
-- mechanic's spell — e.g. standing in a ground effect like Rain of Fire / Blizzard
-- (matches DBM's detection: the debuff/damage event landing on you, not distance).
-- Independent of the mechanic's own trigger.type — engine.lua's MatchDamage calls
-- this off any damage-dealing combat-log event regardless of how the main mechanic
-- is triggered. Stored under its own pseudo-key (key.."#dmg"); default disabled.
function Addon:FireDamageWarning(key, mechDef)
    if not Addon.db.settings.enabled then return end
    local dmgKey = key .. "#dmg"
    if not Addon:GetMechanicConfig(dmgKey, { default = false }).enabled then return end
    Addon:FireAlert(dmgKey, {
        name = "Damage Warning: " .. (mechDef.name or ""),
        style = "text", default = false,
        warningText = mechDef.dmgText or ("You are taking damage from " .. (mechDef.name or "this") .. "!"),
        barColor = mechDef.barColor, warningColor = mechDef.warningColor,
        _defaultPos = DEFAULT_TOP_POS,
    }, true)
end

-- ── Placement previews (boss-level unlock; WYSIWYG, reuses real displays) ────────
Addon._placements = {}   -- key -> draggable preview display

local function FreezeSample(d)
    local info = d._info
    if info.kind == "bar" then
        d.bar:SetValue(0.7); d.time:SetText("5")
        d.bar.spark:ClearAllPoints()
        d.bar.spark:SetPoint("CENTER", d.bar, "LEFT", (d.bar:GetWidth() or 0) * 0.7, 0)
    elseif info.kind == "icon" then
        d.cd:SetCooldown(GetTime() - 3, 8); d.time:SetText("5")
    elseif info.kind == "num" then
        d.time:SetText("5")
    end
    d.glow:Hide()
end

-- One draggable preview for a single mechanic/module key. `stagger` cascades
-- frames that have no saved position yet so they don't stack on top of each other.
function Addon:ShowPlacement(key, mechDef, stagger)
    if Addon._placements[key] then return end
    local cfg = Addon:GetMechanicConfig(key, mechDef)
    local d = AcquireDisplay()
    Addon._placements[key] = d
    Configure(d, key, cfg, mechDef)
    if stagger and stagger > 0 and not (Addon.db.mechanics[key] and Addon.db.mechanics[key].pos) then
        local pos = Addon:GetAnchorPos(key)
        d:ClearAllPoints()
        d:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER",
            (pos.x or 0) + stagger, (pos.y or 0) - stagger)
    end
    d:SetScript("OnUpdate", nil)
    FreezeSample(d)
    d:EnableMouse(true); d:SetMovable(true)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetScript("OnMouseDown", function(s) s:StartMoving() end)
    d:SetScript("OnMouseUp", function(s)
        s:StopMovingOrSizing()
        local p, _, rp, x, y = s:GetPoint()
        Addon:SetMechanicPos(key, p, rp, x, y)
    end)
    d:Show()
end

-- Re-apply style/scale/opacity/etc to a live preview (real-time options editing
-- while unlocked). Preserves the frame's current on-screen anchor so it doesn't jump.
function Addon:RefreshPlacement(key, mechDef)
    local d = Addon._placements[key]
    if not d then return end
    local p, _, rp, x, y = d:GetPoint()
    local cfg = Addon:GetMechanicConfig(key, mechDef)
    Configure(d, key, cfg, mechDef)
    d:SetScript("OnUpdate", nil)
    FreezeSample(d)
    if p then d:ClearAllPoints(); d:SetPoint(p, UIParent, rp, x, y) end
end

function Addon:HideAllPlacements()
    for _, d in pairs(Addon._placements) do ReleaseDisplay(d) end
    wipe(Addon._placements)
end

-- Boss-level unlock: a draggable preview for every mechanic + placeable module so
-- the whole fight's frames can be arranged together.
function Addon:UnlockBoss(raidId, bossId)
    Addon.db.settings.locked = false
    Addon:HideAllPlacements()
    -- clear any previous boss's container-module previews first
    for _, def in ipairs(Addon.modules or {}) do
        if def.SetPreview then def:SetPreview(false) end
    end
    local n = 0
    local boss = Addon:GetBoss(raidId, bossId)
    if boss then
        for _, mech in ipairs(boss.mechanics or {}) do
            local mk = Addon:MechKey(raidId, bossId, mech.id)
            local mcfg = Addon:GetMechanicConfig(mk, mech)
            -- masterEnabled gates the WHOLE mechanic — nothing under it previews if off.
            if mcfg.masterEnabled then
                -- "enabled" here is the Ability Tracker's own toggle.
                if mcfg.enabled then
                    Addon:ShowPlacement(mk, mech, n * 34); n = n + 1
                end
                if mech.reminder and Addon:GetMechanicConfig(mk .. "#rem", mech.reminder).enabled then
                    Addon:ShowPlacement(mk .. "#rem", mech.reminder, n * 34); n = n + 1
                end
                -- On-cast text popup placement (top-middle default) when enabled.
                if Addon:GetMechanicConfig(mk .. "#cast", { default = mech.onCastDefault and true or false }).enabled then
                    Addon:ShowPlacement(mk .. "#cast",
                        { name = (mech.castText or mech.warningText or mech.name or "On-cast"), style = "text",
                          warningText = (mech.castText or mech.warningText or mech.name),
                          barColor = mech.barColor, warningColor = mech.warningColor,
                          _defaultPos = Addon.DEFAULT_TOP_POS },
                        n * 34); n = n + 1
                end
                -- Personal Damage Warning placement (top-middle default) when enabled.
                if Addon:GetMechanicConfig(mk .. "#dmg", { default = false }).enabled then
                    Addon:ShowPlacement(mk .. "#dmg",
                        { name = "Damage Warning: " .. (mech.name or ""), style = "text",
                          warningText = mech.dmgText or ("You are taking damage from " .. (mech.name or "this") .. "!"),
                          barColor = mech.barColor, warningColor = mech.warningColor,
                          _defaultPos = Addon.DEFAULT_TOP_POS },
                        n * 34); n = n + 1
                end
            end
        end
    end
    for _, def in ipairs(Addon:GetBossModules(raidId, bossId)) do
        if Addon:IsModuleEnabled(def.id, def) then
            if def.placeKey then
                Addon:ShowPlacement(def.placeKey, def.placeDef or { name = def.name, style = "icon" }, n * 34)
                n = n + 1
            elseif def.SetPreview then
                def:SetPreview(true)
            end
        end
    end
end

function Addon:LockAll()
    Addon.db.settings.locked = true
    Addon:HideAllPlacements()
    for _, def in ipairs(Addon.modules or {}) do
        if def.SetPreview then def:SetPreview(false) end
    end
end

function Addon:IsUnlocked() return not Addon.db.settings.locked end
