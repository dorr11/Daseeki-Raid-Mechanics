--[[
    Daseeki Raid Mechanics 2.0 — timer BAR surface (presentation, wave 2)

    ENGINE SPEC §4.2 variance rendering, §4.5 the external contract, §4.7 the
    status-bar layer, §5.4 the global suppressors, §11.4 pull timers.

    WHERE THIS SITS. The engine (core_timers.lua) owns bar STATE and publishes every
    transition on the dispatch seam. This file is the only thing that draws. It hangs
    off TIMER_START / TIMER_UPDATE / TIMER_STOP / TIMER_PAUSE / TIMER_RESUME /
    TIMER_COUNTDOWN and owns nothing the engine already decided.

    TWO LAYERS, DELIBERATELY SPLIT:

      Bars.Model   PURE. Rows, anchors, sort order, variance geometry, enlarge/hide
                   thresholds, flash phase, colour interpolation, count text, the
                   keep/fade rules. Every function takes `now` and returns a value —
                   no frames, no globals, no side effects. This is what the harness
                   asserts, which is why the layout rules are testable at all.

      Bars.View    THIN. Pooled frames that read the model each tick and set
                   position / width / colour / text. It contains no rule: if a
                   behaviour can be described as a number, it lives in the model.

    THE HUD IS A KEEP VERDICT (design doc verdicts table). These bars are built
    BESIDE the existing alert tiers in the same suite-themed family — same theme
    tokens, same font routing, same drag-to-place anchor machinery alerts.lua
    already uses (`Addon:GetAnchorPos` / `Addon:SetMechanicPos` with a pseudo-key,
    exactly like alerts.lua's "#special"). Nothing in alerts.lua is replaced.

    DREW_UI_STYLE compliance notes, since this is a new visual system:
      * Bars are a FIXED-WIDTH band (settings.barWidth), never stretched to fill —
        principle 1. One block = one grid: every bar on an anchor shares width,
        height and column edges — principle 5.
      * Icon sits flush against the bar's left edge, count badge inside the bar —
        proximity is relationship, principle 2.
      * Row spacing is ONE configured pad. There is no unexplained gap anywhere in
        the stack — principle 4.
      * Growth direction and sort are fixed settings, not a responsive fallback —
        principle 7.
      * Every anchor carries a LABELLED drag handle while unlocked — principle 6.
      * Every frame sets BOTH dimensions at creation and at arrange — standing rule.
      * Colours and faces are tokens (theme.lua barClass / barTrack / …) — standing
        rule. No literal colour appears below this line.
      * `/drm demo` renders the whole surface out of combat, including a variance
        bar and a pull countdown, and `/drm anchors` shows the labelled handles
        alone — so a placement pass never needs a live boss. The debug-affordance
        rule.

    ONE NOTE ON "LAYOUT ERRORS MUST SURFACE". The engine's dispatch seam wraps every
    consumer in a pcall (ENGINE SPEC §11.8's secure-call rule), so anything running
    inside a TIMER_* callback has its errors captured rather than thrown. That is
    why only MODEL work happens there — adopting a bar record touches no frame. All
    frame work runs from the scheduler's per-module update handler, which is NOT
    wrapped, so a real layout error still reaches geterrorhandler where Drew can see
    it. The split is deliberate, not incidental.
--]]

local _, Addon = ...

local Bars = {}
Addon.Bars = Bars

local Model = {}
Bars.Model = Model

local View = {}
Bars.View = View

local function S() return Addon.Sched end
local function T() return Addon.Timers end

-- ══════════════════════════════════════════════════════════════════════════════
--  CONSTANTS (ENGINE SPEC §4.7 + §12)
-- ══════════════════════════════════════════════════════════════════════════════
Model.ENLARGE_AT     = 11        -- §12 "bar auto-enlarge threshold: 11 s remaining"
Model.ENLARGE_ANIM   = 1.0       -- §4.7 "with a 1 s animated transition"
Model.FLASH_AT       = 7.75      -- §12 "bar flash threshold: 7.75 s remaining"
Model.FLASH_CYCLE    = 1.25      -- §4.7 "on a 1.25 s cycle"
Model.FLASH_BRIGHT   = 0.5       -- §4.7 "with a 0.5 s bright"
Model.FLASH_RAMP     = 0.25      -- §4.7 "/ 0.25 s ramp shape"
Model.HIDE_ABOVE     = 60        -- §12 "bar hide threshold: 60 s remaining"
Model.FADE_IN        = 0.5       -- §4.7 "fade-in over 0.5 s"
Model.DECIMAL_BELOW  = 10        -- §4.7 "one decimal below a configurable threshold"
Model.DESATURATE     = 0.5       -- §4.7 "desaturated by a configurable factor"
View.THROTTLE_IDLE   = 0.04      -- §12 "bar frame update throttle: 0.04 s idle"
View.THROTTLE_ANIM   = 0.01      -- §12 "…/ 0.01 s animating"

-- Anchor pseudo-keys. Same shape as alerts.lua's SPECIAL_ANCHOR, so the existing
-- saved-position machinery (db.mechanics[key].pos) carries them with no new schema.
Bars.ANCHOR_SMALL  = "#bars.small"
Bars.ANCHOR_LARGE  = "#bars.large"
Bars.DEFAULT_POS = {
    [Bars.ANCHOR_SMALL] = { point = "CENTER", relPoint = "CENTER", x = -300, y = 60 },
    [Bars.ANCHOR_LARGE] = { point = "CENTER", relPoint = "CENTER", x = -300, y = 150 },
}

-- The engine's simplified categories (§4.5) that have no declared colour index get
-- one here. A row that DOES declare `color` always wins; this is only the fallback,
-- and it is a table so it reads as data rather than a chain of ifs.
Model.CATEGORY_CLASS = {
    pull = "pull", ["break"] = "break", berserk = "berserk",
    target = 3, stage = 6, cast = 2, castnp = 2, cd = 5, cdnp = 5,
}
-- §4.7: "colour-type 7 bars and explicitly-flagged bars start large and never shrink."
-- The three special categories are the engine's own always-important bars (a pull
-- countdown that renders small among twelve cooldowns is a defect), so they join
-- colour type 7 in that rule.
Model.ALWAYS_LARGE = { pull = true, ["break"] = true, berserk = true }

-- ══════════════════════════════════════════════════════════════════════════════
--  SETTINGS — additive, lazily defaulted (the telemetry-ring house pattern)
-- ══════════════════════════════════════════════════════════════════════════════
-- ONE new key on db.settings, created on first read, so no DB_VERSION bump and
-- nothing existing is touched. core.lua's migration chain stays a no-op.
local SETTING_DEFAULTS = {
    hideAll        = false,     -- §5.4 global suppressor "hide all bar timers"
    pad            = 2,
    enlargeAt      = Model.ENLARGE_AT,
    hideAbove      = Model.HIDE_ABOVE,
    hiddenMode     = false,     -- §4.7 park long bars off-screen until they cross
    decimalBelow   = Model.DECIMAL_BELOW,
    desaturate     = Model.DESATURATE,
    animate        = true,      -- §4.7 "skipped in the no-animation bar style"
    variance          = true,   -- §4.2 variance display, default ON
    varianceCountdown = false,  -- §4.2 optional: readout hits zero at MIN, runs negative
    countdownVoice = true,      -- §4.4 spoken count off the engine's own scheduler
    icons          = true,
}

function Bars.Settings()
    local db = Addon.db
    if type(db) ~= "table" then return SETTING_DEFAULTS end
    local s = db.settings
    if type(s) ~= "table" then return SETTING_DEFAULTS end
    local b = s.bars
    if type(b) ~= "table" then b = {}; s.bars = b end
    for k, v in pairs(SETTING_DEFAULTS) do if b[k] == nil then b[k] = v end end
    if type(b.small) ~= "table" then b.small = { sort = "asc", grow = "DOWN" } end
    if type(b.large) ~= "table" then b.large = { sort = "asc", grow = "UP" } end
    return b
end

function Bars.Size()
    local s = Addon.db and Addon.db.settings
    return (s and s.barWidth) or 200, (s and s.barHeight) or 20
end

-- The user's variance-display option is a PRESENTATION option, but the engine needs
-- it because §4.2 makes it change what the bar's total MEANS (run to max vs run to
-- min). So the option lives here and is pushed down; the engine never reads a setting.
function Bars.PushVarianceOption()
    local t = T()
    if t then t.varianceDisplay = Bars.Settings().variance and true or false end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  MODEL — pure. `now` is always an argument; nothing here reads a clock itself.
-- ══════════════════════════════════════════════════════════════════════════════
Model.rows = {}        -- barId -> row
Model.count = 0

local function settingsOf() return Bars.Settings() end

-- §4.1 identity is `timerObjectId + tab-joined stringified arguments`. For a COUNT
-- timer the trailing argument IS the count, which is what §4.5 broadcasts as "the
-- numeric count for count timers" and what the display text formats.
function Model.CountOf(bar)
    local objs = T() and T().objects
    local timer = objs and objs[bar.timerId]
    if not (timer and timer.hasCount) then return nil end
    local last
    for part in tostring(bar.id):gmatch("[^\t]+") do last = part end
    return tonumber(last)
end

function Model.ClassOf(bar)
    if bar.color ~= nil then return bar.color end
    return Model.CATEGORY_CLASS[bar.category] or 5
end

-- Whether this bar would be DRAWN. §4.5: the broadcast fires even when this is
-- false; only the bar is withheld. The two gates are the global suppressor and the
-- row's own bar-display override.
function Model.IsDisplayEnabled(bar)
    if settingsOf().hideAll then return false end
    local db = Addon.db
    if db and type(db.mechanics) == "table" and bar.encId and bar.key then
        local o = db.mechanics[tostring(bar.encId) .. ":" .. tostring(bar.key)]
        if o and o.bar == false then return false end
    end
    return true
end

function Model.Adopt(bar)
    local row = Model.rows[bar.id]
    if not row then
        row = { id = bar.id, slot = 0 }
        Model.rows[bar.id] = row
        Model.count = Model.count + 1
        row.bornAt = bar.startedAt
    end
    row.bar        = bar
    row.timerId    = bar.timerId
    row.key        = bar.key
    row.encId      = bar.encId
    row.category   = bar.category
    row.class      = Model.ClassOf(bar)
    row.baseText   = bar.text or bar.key or bar.timerId
    row.icon       = bar.icon
    row.spellId    = bar.spellId
    row.nameplate  = bar.nameplate and true or false
    row.keep       = bar.keep and true or false
    row.fade       = bar.fade and true or false
    row.noColorFade = bar.noColorFade and true or false
    row.approx     = bar.approx and true or false
    row.priority   = bar.priority and true or false
    row.count      = Model.CountOf(bar)
    row.enabled    = Model.IsDisplayEnabled(bar)
    row.expiredKept = nil
    -- §4.7 "colour-type 7 bars and explicitly-flagged bars start large and never shrink"
    if row.class == 7 or Model.ALWAYS_LARGE[row.category] or bar.large then row.enlarged = true end
    return row
end

function Model.Drop(barId)
    if Model.rows[barId] then
        Model.rows[barId] = nil
        Model.count = Model.count - 1
    end
end

function Model.Clear()
    for id in pairs(Model.rows) do Model.rows[id] = nil end
    Model.count = 0
end

-- §4.7 keep-on-screen: an expired bar whose row asked to be kept STAYS, pinned at
-- zero, until something stops it explicitly. Returns true when the row survived.
function Model.OnStop(barId, reason)
    local row = Model.rows[barId]
    if not row then return false end
    if row.keep and reason == "expired" then
        row.expiredKept = true
        return true
    end
    Model.Drop(barId)
    return false
end

-- ── Geometry ──────────────────────────────────────────────────────────────────
-- Remaining to the RENDER end (max when variance display is on) — the number the
-- fill and the spark use.
function Model.Remaining(row, now)
    local b = row.bar
    if not b then return 0 end
    if row.expiredKept then return 0 end
    if b.paused then return b.endsAt - b.pausedAt end
    return b.endsAt - now
end

-- §4.2: "Bar auto-enlargement, hidden-bar thresholds and SORTING all evaluate
-- against the MINIMUM end of the window." This is that number, and it is the ONLY
-- number the three of them are allowed to use.
function Model.SortValue(row, now)
    local b = row.bar
    if not b then return 0 end
    if row.expiredKept then return 0 end
    if b.paused then return b.minEndsAt - b.pausedAt end
    return b.minEndsAt - now
end

function Model.Total(row)
    local b = row.bar
    if not b then return 1 end
    local total = b.renderTotal or b.total or 1
    if total <= 0 then total = 1 end
    return total
end

-- Fill fraction, 0..1, of the RENDER duration.
function Model.Fill(row, now)
    local rem = Model.Remaining(row, now)
    if rem < 0 then rem = 0 end
    local f = rem / Model.Total(row)
    if f > 1 then f = 1 elseif f < 0 then f = 0 end
    return f
end

-- §4.2: "the bar ... paints the variance window as a distinct textured overlay
-- covering varianceDuration / totalTime of the bar's width, ANCHORED TO THE FILL
-- EDGE." So the overlay is a WIDTH FRACTION, and its left edge is the fill edge:
-- returns (fraction, leftFraction). Zero when the bar has no variance or the
-- display option is off (in which case the bar already runs to min).
function Model.VarianceSpan(row, now)
    local b = row.bar
    if not b or not b.hasVariance then return 0, 0 end
    if not settingsOf().variance then return 0, 0 end
    local total = Model.Total(row)
    local span = (b.variance or 0) / total
    if span <= 0 then return 0, 0 end
    if span > 1 then span = 1 end
    -- The window is the LAST `variance` seconds of a bar that runs to max, so its
    -- left edge sits `span` before the fill edge and it shrinks as the fill passes.
    local fill = Model.Fill(row, now)
    local left = fill - span
    if left < 0 then span, left = fill, 0 end
    return span, left
end

-- §4.7 flash: "below 7.75 s remaining, on a 1.25 s cycle with a 0.5 s bright /
-- 0.25 s ramp shape". Returns the overlay strength 0..1.
function Model.FlashAlpha(row, now)
    local rem = Model.SortValue(row, now)
    if rem > Model.FLASH_AT or rem < 0 then return 0 end
    if not settingsOf().animate then return 0 end
    local phase = (now - (row.bornAt or now)) % Model.FLASH_CYCLE
    if phase < Model.FLASH_BRIGHT then return 1 end
    if phase < Model.FLASH_BRIGHT + Model.FLASH_RAMP then
        return 1 - (phase - Model.FLASH_BRIGHT) / Model.FLASH_RAMP
    end
    return 0
end

-- §4.7 "fade-in over 0.5 s (skipped in the no-animation bar style)".
function Model.FadeIn(row, now)
    if not settingsOf().animate then return 1 end
    local t = (now - (row.bornAt or now)) / Model.FADE_IN
    if t >= 1 then return 1 end
    if t < 0 then return 0 end
    return t
end

-- §4.7 colour: interpolate the class from its start to its end colour across the
-- bar's life unless "no fade"; a non-enlarged bar beyond the enlarge threshold is
-- desaturated.
function Model.ColorAt(row, now)
    local s = settingsOf()
    local t = row.noColorFade and 0 or (1 - Model.Fill(row, now))
    local r, g, b = Addon:BarColor(row.class, t)
    if not row.enlarged and Model.SortValue(row, now) > (s.enlargeAt or Model.ENLARGE_AT) then
        r, g, b = Addon:Desaturate(r, g, b, s.desaturate or Model.DESATURATE)
    end
    return r, g, b
end

-- §4.7 auto-enlarge is STICKY: nothing in the spec shrinks a bar back, and a bar
-- that is given time back must not bounce between the two anchors mid-fight.
function Model.EvaluateEnlarge(row, now)
    if row.enlarged then return true end
    if Model.SortValue(row, now) <= (settingsOf().enlargeAt or Model.ENLARGE_AT) then
        row.enlarged = true
        row.enlargedAt = now
    end
    return row.enlarged and true or false
end

-- §4.7 hidden-bar mode is NOT sticky: "bars longer than 60 s can be parked
-- off-screen and RE-ENTER the list when they cross the threshold."
function Model.IsHidden(row, now)
    local s = settingsOf()
    if not s.hiddenMode then return false end
    if row.enlarged then return false end
    return Model.SortValue(row, now) > (s.hideAbove or Model.HIDE_ABOVE)
end

function Model.AnchorOf(row, now)
    if Model.IsHidden(row, now) then return "hidden" end
    if Model.EvaluateEnlarge(row, now) then return "large" end
    return "small"
end

-- ── Text ──────────────────────────────────────────────────────────────────────
-- §4.7 numeric readout: "one decimal below a configurable threshold, whole seconds
-- up to 60, m:ss above. Approximate-cooldown bars are prefixed with `~`."
function Model.FormatTime(rem, approx, decimalBelow)
    decimalBelow = decimalBelow or Model.DECIMAL_BELOW
    local sign = ""
    if rem < 0 then sign = "-"; rem = -rem end
    local body
    if rem < decimalBelow then
        body = ("%.1f"):format(rem)
    elseif rem <= 60 then
        body = ("%d"):format(math.floor(rem + 0.5))
    else
        local whole = math.floor(rem)
        body = ("%d:%02d"):format(math.floor(whole / 60), whole % 60)
    end
    return (approx and "~" or "") .. sign .. body
end

function Model.TimeText(row, now)
    local s = settingsOf()
    -- §4.2 optional display mode: "the numeric readout hits zero at the MINIMUM
    -- timer and then runs negative through the window". The FILL still runs to max;
    -- only the readout changes, which is the whole point of the mode.
    local rem = s.varianceCountdown and Model.SortValue(row, now) or Model.Remaining(row, now)
    if row.expiredKept then rem = 0 end
    return Model.FormatTime(rem, row.approx, s.decimalBelow)
end

-- §4.1 count timers read "Meteor (3)". A text carrying %d formats; otherwise the
-- count is appended, so encounter data never has to remember which shape it used.
function Model.DisplayText(row)
    local text = row.baseText or ""
    if row.count then
        if text:find("%%d") then return (text:format(row.count)) end
        return ("%s (%d)"):format(text, row.count)
    end
    return text
end

-- ── Layout ────────────────────────────────────────────────────────────────────
-- The whole arrangement, as data. Each list is sorted by SortValue in the anchor's
-- configured direction, and each row is stamped with its 1-based slot. This is the
-- function the harness asserts; the view does nothing but read it.
local function sortRows(list, dir, now)
    table.sort(list, function(a, b)
        local av, bv = Model.SortValue(a, now), Model.SortValue(b, now)
        if av == bv then return tostring(a.id) < tostring(b.id) end   -- stable, deterministic
        if dir == "desc" then return av > bv end
        return av < bv
    end)
    for i = 1, #list do list[i].slot = i end
    return list
end

function Model.Layout(now)
    local s = settingsOf()
    local out = { small = {}, large = {}, hidden = {} }
    if s.hideAll then
        for _, row in pairs(Model.rows) do row.slot = 0; out.hidden[#out.hidden + 1] = row end
        return out
    end
    for _, row in pairs(Model.rows) do
        if row.enabled then
            local a = Model.AnchorOf(row, now)
            out[a][#out[a] + 1] = row
        else
            out.hidden[#out.hidden + 1] = row
        end
    end
    sortRows(out.small, (s.small and s.small.sort) or "asc", now)
    sortRows(out.large, (s.large and s.large.sort) or "asc", now)
    return out
end

-- Offset of slot `i` from the anchor, given the anchor's growth direction. One pad,
-- everywhere — DREW_UI_STYLE principle 4 ("zero unexplained vertical gaps").
function Model.SlotOffset(i, grow, height, pad)
    local step = (height + (pad or 2)) * (i - 1)
    if grow == "UP" then return 0, step end
    return 0, -step
end

-- ══════════════════════════════════════════════════════════════════════════════
--  MID-FIGHT RECOLOUR / RENAME — the Chromaggus contract
-- ══════════════════════════════════════════════════════════════════════════════
-- Chromaggus picks two of five breaths per attempt; until the raid sees which, the
-- bar is a generic "Breath". The moment it is identified the SAME running bar must
-- become "Frost Burn" in the interrupt colour without losing its elapsed time —
-- restarting it would lie about the remaining time AND trip the early-refresh
-- tripwire (§4.3) with a false positive.
--
-- So Restyle mutates three things in lockstep and nothing else:
--   1. the ENGINE's live bar record — the authority, so a later TIMER_UPDATE does
--      not revert the rename,
--   2. the owning timer OBJECT — so the next Start keeps the new identity for the
--      rest of the fight,
--   3. the model row — so the very next frame draws it.
-- It deliberately does NOT touch startedAt/endsAt: identity changes, time does not.
function Bars.Restyle(barId, style)
    local t = T()
    local bar = t and t.bars[barId]
    if not bar or type(style) ~= "table" then return nil end
    if style.text  ~= nil then bar.text  = style.text  end
    if style.icon  ~= nil then bar.icon  = style.icon  end
    if style.color ~= nil then bar.color = style.color end
    local obj = t.objects[bar.timerId]
    if obj then
        if style.text  ~= nil then obj.text  = style.text  end
        if style.icon  ~= nil then obj.icon  = style.icon  end
        if style.color ~= nil then obj.color = style.color end
    end
    local row = Model.rows[barId]
    if row then
        row.baseText = bar.text or row.baseText
        row.icon     = bar.icon
        row.class    = Model.ClassOf(bar)
    end
    Addon:FireEngineEvent("TIMER_UPDATE", bar)
    return row
end

-- W4b: the DECLARATIVE seam. `Bars.Restyle` shipped in W2 with the Chromaggus
-- contract written above it and nothing in the encounter grammar able to reach it;
-- a restyle row (core_api extension 19) raises RESTYLE_REQUEST and this answers it.
-- The engine has already decided WHICH identity the evidence means and has already
-- swallowed the no-change case — this is pure presentation.
function Bars.OnRestyleRequest(_, encId, row, style, ev, ident)
    if not (row and row.timer and type(style) == "table") then return nil end
    if ident ~= nil then return Bars.RestyleRow(encId, row.timer, style, ident) end
    return Bars.RestyleRow(encId, row.timer, style)
end

-- Convenience for encounter data: address the bar through the row key it was
-- started under rather than through the composed bar id.
function Bars.RestyleRow(encId, rowKey, style, ...)
    local t = T()
    if not t then return nil end
    local obj = t.objects[Addon.API.OptionKey(encId, rowKey)]
    if not obj then return nil end
    return Bars.Restyle(obj:BarId(...), style)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  VIEW — thin. Reads the model, sets pixels, decides nothing.
-- ══════════════════════════════════════════════════════════════════════════════
View.pool    = {}
View.live    = {}      -- barId -> frame
View.anchors = {}
View.acc     = 0
View.ready   = nil

-- One capability probe at boot rather than a pcall at every draw: the headless
-- harness supplies a frame factory that cannot texture, and DREW_UI_STYLE forbids
-- swallowing layout errors, so the decision is made ONCE and honestly.
function View.CanDraw()
    if View.ready ~= nil then return View.ready end
    if type(_G.CreateFrame) ~= "function" then View.ready = false; return false end
    local f = _G.CreateFrame("Frame", nil, _G.UIParent)
    View.ready = (type(f) == "table" and type(f.CreateTexture) == "function") and true or false
    return View.ready
end

Bars.ANCHOR_LABEL = {
    [Bars.ANCHOR_SMALL] = "Timer bars \226\128\148 small",
    [Bars.ANCHOR_LARGE] = "Timer bars \226\128\148 large",
}

local function anchorFrame(key)
    local a = View.anchors[key]
    if a then return a end
    local w, h = Bars.Size()
    a = Addon:HudAnchor(key, Bars.ANCHOR_LABEL[key], Bars.DEFAULT_POS[key], w, h)
    View.anchors[key] = a
    return a
end

-- Anchors are created lazily on the first bar, so a placement pass has to ask for
-- them explicitly — otherwise "unlock" on a quiet night shows nothing to drag.
function Bars.EnsureAnchors()
    if not View.CanDraw() then return 0 end
    anchorFrame(Bars.ANCHOR_SMALL)
    anchorFrame(Bars.ANCHOR_LARGE)
    return 2
end

local function newBarFrame()
    local w, h = Bars.Size()
    local d = _G.CreateFrame("Frame", nil, _G.UIParent)
    d:SetSize(w, h)
    d:SetFrameStrata("MEDIUM")

    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    d.iconBorder = Addon:AddIconBorder(d.icon, d)

    d.bar = _G.CreateFrame("StatusBar", nil, d)
    d.bar.bg = d.bar:CreateTexture(nil, "BACKGROUND")
    d.bar.bg:SetAllPoints()
    d.bar.bg:SetColorTexture(Addon:ThemeColor("barTrack"))
    d.border = Addon:AddBorder(d.bar)

    -- §4.2 the variance window: a distinct TEXTURED overlay, anchored to the fill
    -- edge. It is drawn above the fill and below the text so the numbers stay legible.
    d.variance = d.bar:CreateTexture(nil, "ARTWORK")
    d.variance:SetColorTexture(Addon:ThemeColor("barVariance"))
    d.variance:SetBlendMode("ADD")
    d.variance:Hide()

    d.spark = d.bar:CreateTexture(nil, "OVERLAY")
    d.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    d.spark:SetBlendMode("ADD")

    d.flash = d.bar:CreateTexture(nil, "OVERLAY")
    d.flash:SetAllPoints(d.bar)
    d.flash:SetColorTexture(Addon:ThemeColor("barFlash"))
    d.flash:SetBlendMode("ADD")
    d.flash:Hide()

    d.fg = _G.CreateFrame("Frame", nil, d)
    d.fg:SetAllPoints(d)
    d.fg:SetFrameLevel(d.bar:GetFrameLevel() + 3)

    d.label = d.fg:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.time  = d.fg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    d.count = d.fg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Addon:TrySetFont(d.label, "body")
    Addon:TrySetFont(d.time,  "numeral")     -- a countdown is telemetry (BRAND_SPEC §3)
    Addon:TrySetFont(d.count, "numeral")
    Addon:StyleFont(d.label, "barText")
    Addon:StyleFont(d.time,  "barText")
    Addon:StyleFont(d.count, "barCount")

    -- §4.7: "Right-click cancels a bar; shift+left-click announces it to chat."
    d:EnableMouse(true)
    d:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            Bars.CancelBar(self._barId)
        elseif button == "LeftButton" and _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
            Bars.AnnounceBar(self._barId)
        end
    end)
    d:Hide()
    return d
end

local function acquire()
    local d = table.remove(View.pool)
    if d then return d end
    return newBarFrame()
end

local function release(d)
    d:Hide()
    d._barId = nil
    View.pool[#View.pool + 1] = d
end

-- Arrange one frame for one model row. Every dimension is set here, every frame,
-- because a bar's height and width are user settings that can change mid-session.
local function arrange(d, row, now, anchorKey, slot)
    local s = Bars.Settings()
    local w, h = Bars.Size()
    if row.enlarged then w, h = w * 1.15, h * 1.25 end     -- the "large" list reads larger

    d:SetSize(w, h)
    local a = anchorFrame(anchorKey)
    local grow = anchorKey == Bars.ANCHOR_LARGE
                 and ((s.large and s.large.grow) or "UP")
                 or ((s.small and s.small.grow) or "DOWN")
    local ox, oy = Model.SlotOffset(slot, grow, h, s.pad)
    d:ClearAllPoints()
    d:SetPoint("CENTER", a, "CENTER", ox, oy)

    local iconW = s.icons and h or 0
    d.bar:ClearAllPoints()
    d.bar:SetPoint("TOPLEFT", d, "TOPLEFT", iconW, 0)
    d.bar:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 0, 0)
    d.bar:SetStatusBarTexture(Addon.Theme.statusbar)
    d.bar:SetMinMaxValues(0, 1)

    if s.icons then
        d.icon:ClearAllPoints()
        d.icon:SetPoint("RIGHT", d.bar, "LEFT", 0, 0)
        d.icon:SetSize(h, h)
        d.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        d.icon:Show(); d.iconBorder:Show()
    else
        d.icon:Hide(); d.iconBorder:Hide()
    end

    d.label:ClearAllPoints()
    d.label:SetPoint("LEFT", d.bar, "LEFT", 4, 0)
    d.label:SetJustifyH("LEFT")
    d.time:ClearAllPoints()
    d.time:SetPoint("RIGHT", d.bar, "RIGHT", -4, 0)
    d.time:SetJustifyH("RIGHT")
    d.count:ClearAllPoints()
    d.count:SetPoint("BOTTOMRIGHT", d.icon, "BOTTOMRIGHT", -1, 1)

    d.spark:SetSize(16, h * 2)
    d._barId = row.id
end

local function paint(d, row, now)
    local fill = Model.Fill(row, now)
    d.bar:SetValue(fill)
    d.bar:SetStatusBarColor(Model.ColorAt(row, now))
    d.label:SetText(Model.DisplayText(row))
    d.time:SetText(Model.TimeText(row, now))
    if row.count then d.count:SetText(tostring(row.count)); d.count:Show() else d.count:Hide() end

    local bw = d.bar:GetWidth() or 0
    d.spark:ClearAllPoints()
    d.spark:SetPoint("CENTER", d.bar, "LEFT", bw * fill, 0)

    local span, left = Model.VarianceSpan(row, now)
    if span > 0 and bw > 0 then
        d.variance:ClearAllPoints()
        d.variance:SetPoint("LEFT", d.bar, "LEFT", bw * left, 0)
        d.variance:SetSize(bw * span, d.bar:GetHeight() or 1)
        d.variance:Show()
    else
        d.variance:Hide()
    end

    local fa = Model.FlashAlpha(row, now)
    if fa > 0 then d.flash:SetAlpha(fa); d.flash:Show() else d.flash:Hide() end

    -- §4.5's fade flag is a de-emphasised bar; §4.7's fade-in is the first 0.5 s.
    local alpha = Model.FadeIn(row, now) * (row.fade and 0.55 or 1)
    d:SetAlpha(alpha)
end

function View.Refresh(now)
    if not View.CanDraw() then return 0 end
    local layout = Model.Layout(now)
    local seen, drawn = {}, 0
    for _, anchorKey in ipairs({ Bars.ANCHOR_SMALL, Bars.ANCHOR_LARGE }) do
        local list = anchorKey == Bars.ANCHOR_LARGE and layout.large or layout.small
        for i = 1, #list do
            local row = list[i]
            local d = View.live[row.id]
            if not d then d = acquire(); View.live[row.id] = d end
            arrange(d, row, now, anchorKey, i)
            paint(d, row, now)
            d:Show()
            seen[row.id] = true
            drawn = drawn + 1
        end
    end
    for id, d in pairs(View.live) do
        if not seen[id] then View.live[id] = nil; release(d) end
    end
    return drawn
end

-- §4.7's per-bar adaptive throttle, applied once on the shared driver. One OnUpdate
-- that walks the model is cheaper than N frame scripts and produces exactly the same
-- refresh cadence, which is the behaviour the spec constrains.
function View.OnUpdate(elapsed, now)
    View.acc = View.acc + (elapsed or 0)
    local animating = false
    for _, row in pairs(Model.rows) do
        if row.enlarged or Model.SortValue(row, now) <= Model.FLASH_AT then animating = true break end
    end
    local step = animating and View.THROTTLE_ANIM or View.THROTTLE_IDLE
    if View.acc < step then return false end
    View.acc = 0
    View.Refresh(now)
    return true
end

-- The bar surface rides the ENGINE's scheduler frame (§3.3 per-module update
-- handlers), so there is no second OnUpdate in the addon and the "idle cost outside
-- encounters is zero" guarantee survives: with no bars, nothing is registered.
-- Registration is checked against the SCHEDULER, not a local flag: Sched:Flush()
-- (the §9.4 hard-disable path, and the harness between fixtures) drops every
-- updater, and a private "am I driving" boolean would then be permanently wrong.
function View.Wake()
    if S().updaters[Bars] then return end
    S():RegisterUpdate(Bars, 0, function(_, elapsed) View.OnUpdate(elapsed, S():Now()) end)
end

function View.Sleep()
    S():UnregisterUpdate(Bars)
    for id, d in pairs(View.live) do View.live[id] = nil; release(d) end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  BAR ACTIONS (§4.7 right-click / shift+left-click)
-- ══════════════════════════════════════════════════════════════════════════════
function Bars.CancelBar(barId)
    local row = Model.rows[barId]
    if not row then return false end
    local t = T()
    local obj = t and t.objects[row.timerId]
    if obj then obj:StopBar(barId, "user-cancelled") end
    Model.Drop(barId)
    return true
end

-- A KEEP bar that has already expired no longer exists in the engine, so
-- `Timer:Stop()` cannot reach it — only the model still holds it. Dismiss is the
-- explicit removal for that state, and Bars.Sweep is the safety net that clears any
-- kept row left standing when the fight ends.
function Bars.Dismiss(barId)
    local row = Model.rows[barId]
    if not row then return false end
    Model.Drop(barId)
    return true
end

function Bars.Sweep(reason)
    local t = T()
    local n = 0
    for id, row in pairs(Model.rows) do
        -- Only rows the engine no longer owns: a live bar is still the engine's to
        -- stop, and W1 guarantees bars survive the instant of the end by design.
        if row.expiredKept and not (t and t.bars[id]) then
            Model.Drop(id)
            n = n + 1
        end
    end
    if Model.count == 0 then View.Sleep() end
    return n
end

function Bars.AnnounceBar(barId, now)
    local row = Model.rows[barId]
    if not row then return nil end
    now = now or S():Now()
    local line = ("%s - %s"):format(Model.DisplayText(row), Model.TimeText(row, now))
    if type(_G.SendChatMessage) == "function" and _G.IsInGroup and _G.IsInGroup() then
        _G.SendChatMessage(line, _G.IsInRaid and _G.IsInRaid() and "RAID" or "PARTY")
    elseif type(print) == "function" then
        print(Addon:Tag("[DRM]") .. " " .. line)
    end
    return line
end

-- ══════════════════════════════════════════════════════════════════════════════
--  ENGINE SEAM — the only place this file talks to the engine
-- ══════════════════════════════════════════════════════════════════════════════
local function onStart(_, bar)
    Model.Adopt(bar)
    View.Wake()
end

local function onUpdate(_, bar)
    if Model.rows[bar.id] then Model.Adopt(bar) end
end

local function onStop(_, barId, _, reason)
    Model.OnStop(barId, reason)
    if Model.count == 0 then View.Sleep() end
end

local function onPauseResume(_, bar)
    if Model.rows[bar.id] then Model.Adopt(bar) end
end

-- §4.4: the engine schedules one task per second per bar and hands us the REMAINING
-- COUNT. All we do is speak it — the depth, the cancellation on restart and the
-- "requires combat" drop are engine rules and already resolved by the time we run.
local function onCountdown(_, barId, n)
    if not Bars.Settings().countdownVoice then return end
    if Addon.db and Addon.db.settings and Addon.db.settings.countdownVoice == false then return end
    local row = Model.rows[barId]
    if row and row.enabled == false then return end
    Addon:PlayVoiceNumber(n)
end

function Bars.Init()
    if Bars._inited then return end
    Bars._inited = true
    Bars.PushVarianceOption()
    -- §4.4: "Count depth ... capped by the SELECTED VOICE PACK's declared maximum."
    -- The engine reads Addon.CountdownMax; the pack is ours to know about, so we set it.
    Addon.CountdownMax = Addon:VoiceCountMax()
    Addon:RegisterEngineCallback("TIMER_START",     onStart,        Bars)
    Addon:RegisterEngineCallback("TIMER_UPDATE",    onUpdate,       Bars)
    Addon:RegisterEngineCallback("TIMER_STOP",      onStop,         Bars)
    Addon:RegisterEngineCallback("TIMER_PAUSE",     onPauseResume,  Bars)
    Addon:RegisterEngineCallback("TIMER_RESUME",    onPauseResume,  Bars)
    Addon:RegisterEngineCallback("TIMER_COUNTDOWN", onCountdown,    Bars)
    -- W4b extension 19: the Chromaggus contract, now reachable from encounter data.
    Addon:RegisterEngineCallback("RESTYLE_REQUEST", Bars.OnRestyleRequest, Bars)
    -- Kept bars outlive their own expiry by design; they must not outlive the fight.
    Addon:RegisterEngineCallback("ENGINE_END", function() Bars.Sweep("fight-end") end, Bars)
    return true
end

-- ══════════════════════════════════════════════════════════════════════════════
--  DEMO MODE (§11.7) — the debug affordance DREW_UI_STYLE requires of every
--  visual system we build. Renders one bar of every colour class plus a variance
--  bar and a pull bar, out of combat, so placement never needs a live boss.
-- ══════════════════════════════════════════════════════════════════════════════
function Bars.Demo(seconds)
    seconds = seconds or 30
    local t = T()
    if not t then return 0 end
    local made = 0
    local rows = {
        { class = 1, text = "Add wave",        dur = seconds * 0.9 },
        { class = 2, text = "Ground effect",   dur = seconds * 0.75 },
        { class = 3, text = "Mind Control",    dur = seconds * 0.6 },
        { class = 4, text = "Interrupt cast",  dur = seconds * 0.45 },
        { class = 5, text = "Tank swap",       dur = seconds * 0.3 },
        { class = 6, text = "Phase 2",         dur = seconds * 1.4 },
        { class = 7, text = "Custom timer",    dur = seconds * 0.2 },
    }
    for i, r in ipairs(rows) do
        local obj = t.New({ id = "demo:" .. i, key = "demo" .. i, kind = "cd",
                            text = r.text, color = r.class })
        obj:Start(r.dur)
        made = made + 1
    end
    local varObj = t.New({ id = "demo:variance", key = "demovar", kind = "cd",
                           text = "Breath (window)", color = 2 })
    varObj:Start("v" .. (seconds * 0.5) .. "-" .. (seconds * 1.1))
    made = made + 1
    local cnt = t.New({ id = "demo:count", key = "democount", kind = "cd",
                        text = "Meteor", color = 3, count = true })
    cnt:Start(seconds * 0.8, 3)
    made = made + 1
    -- A NON-"manual" source on purpose: the pull timer is a broadcast surface, and a
    -- placement pass must never put a countdown on forty other people's screens.
    Addon:StartPullTimer(10, "demo")
    made = made + 1
    return made
end

function Bars.StopDemo()
    local t = T()
    if not t then return 0 end
    local n = 0
    for id, obj in pairs(t.objects) do
        if tostring(id):sub(1, 5) == "demo:" then n = n + obj:Stop() end
    end
    Addon:CancelPullTimer("demo")
    return n
end

return Bars
