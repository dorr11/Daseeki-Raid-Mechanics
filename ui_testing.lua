--[[
    Daseeki Raid Mechanics 2.0 — THE TESTING SUITE

    Owner design, 2026-08-07. Six features, one file, and one rule underneath all of
    them: EVERYTHING GOES THROUGH THE REAL PATH. A rehearsal bar is started by the real
    `Runtime:Timer`, adopted by the real bar model, routed by the real bucket resolver,
    placed by the real anchor resolver and sounded by the real sound dispatch. Nothing
    below draws a pixel or picks a colour of its own; if a test looks wrong, the addon
    IS wrong, which is the only kind of test surface worth having.

      1  PER-ROW PLAY      one row, fired through the real dispatch. Real duration and
                           real variance for a timer; a sample target name filled into
                           a warning. Pressing it again restarts the same bar.
      2  PER-BOSS TEST     the rehearsal: an engage banner, every enabled timer started
                           at its real pull values (the true mid-fight bar population),
                           the warnings walked out ~1 s apart within their tier, the
                           phases stepped, and the boss's special module's own Test
                           invoked where one exists. Stop sweeps all of it.
      3  LAYOUT MODE       a persistent placement workbench. Populates EVERYTHING — a
                           bar of every colour class in BOTH buckets, both warning
                           tiers, a docked special sample — and KEEPS it alive while the
                           anchors are dragged, re-applying placement as it changes.
      4  COMPRESSED PLAYBACK
                           an encounter's scheduled script on a TIME-SCALED clock, so a
                           five-minute sequence is watchable in one. Built on the
                           engine's own min-heap scheduler: the heap reads absolute
                           time, so the test injects a scaled CLOCK and never touches
                           the live one. See `BeginScaledClock` for why the swap is
                           continuous in and rebased out.
      5  PER-ROW SOUND     exactly the cue that row resolves to today, through the real
                           sound dispatch, respecting the selected packs.
      6  VALIDATE          an in-game sweep of the WHOLE encounter registry against the
                           live client: every spell id, icon, sound path and voice cue.
                           Patch-day insurance, and a permanent keep.
      7  PREVIEW           the Placement section's one-shot (owner rework 2026-08-10):
                           a bar on each list and a line on each warning tier, all at
                           once, through the same real paths — layout mode's little
                           sibling, with no upkeep tick and no pull timer.

    ── THE QUARANTINE ───────────────────────────────────────────────────────────
    A test surface that can reach the raid is a liability, not a feature. Four rules,
    each enforced in the file that owns the thing being protected rather than here,
    because a guard that lives next to the caller is a guard someone can route around:

      1  NO SYNC        core_sync.lua, gate 3 of 3 (`Sync.TestQuarantined`), checked in
                        Send / Whisper / Enqueue / rawSend. Nothing a test does can be
                        composed, queued or transmitted — including the pull timer,
                        which calls `Sync.Send` directly rather than through the seam.
      2  NO STATS       core_lifecycle.lua `Life:RecordStats` refuses while a test is up.
      3  NO TRIPWIRE    core_timers.lua `Timers.CheckEarlyRefresh` refuses. A rehearsal
                        restarts bars ON PURPOSE; writing those observations into the
                        arbitration ring would poison the dataset that tells Drew which
                        shipped timer values are wrong.
      4  A REAL PULL WINS
                        core_lifecycle.lua `Life:StartCombat` tears the test down BEFORE
                        the real runtime exists. The ordering is the rule: aborting off
                        ENGINE_ENGAGE would leave a rehearsal bar and a real bar
                        addressing the same timer object, and the tear-down would then
                        stop the real one.

    ── WHY A TEST RUNTIME IS A REAL RUNTIME ─────────────────────────────────────
    Every encounter-flavoured feature drives a genuine `API.NewRuntime` over the
    genuine encounter definition, carrying the genuine encounter id. That is what makes
    a rehearsal bar read the player's own route, their own Custom placement, their own
    attach target and their own per-row sound: those are all keyed on
    `encId .. ":" .. rowKey`, and a test that invented its own namespace would quietly
    be testing something else. The collision that identity implies is prevented by
    ORDERING (quarantine rule 4), not by a second namespace.

    DREW_UI_STYLE compliance: this file creates exactly one frame kind (the layout
    mode's sample special pad), sets both its dimensions, hardcodes no colour and no
    font, and pcall-wraps no layout call. Every visible thing it produces is produced by
    the shipping surfaces.
--]]

local _, Addon = ...

local T = {}
Addon.Testing = T

local function S()  return Addon.Sched end
local function API() return Addon.API end

-- ── Constants ─────────────────────────────────────────────────────────────────
T.WARN_STAGGER     = 1.0    -- seconds between warnings WITHIN a tier (readable)
T.PHASE_STAGGER    = 4.0    -- seconds between phase steps
T.LAYOUT_REFRESH   = 2.0    -- layout mode's upkeep tick
T.LAYOUT_BAR       = 40     -- layout sample bar length, seconds
T.LAYOUT_PULL      = 30     -- layout sample pull countdown, seconds
-- A warning lives 1.5 s by design (§12). A placement pass needs the lines to STAY, and
-- a row may declare its own duration, so the samples declare a very long one instead of
-- being re-pushed on a timer — which would strobe the screen flash and scroll the very
-- stacks the pass is trying to position.
T.LAYOUT_WARN_HOLD = 3600
T.PLAYBACK_SPEED   = 5      -- `/drm playback <boss>` default time scale
T.PLAYBACK_MIN     = 1
T.PLAYBACK_MAX     = 20
T.PLAYBACK_HORIZON = 600    -- SCALED seconds a playback runs before it stops itself
T.SAMPLE_NAME      = "Testdummy"
T.PREFIX           = "test:"   -- synthetic (non-encounter) timer objects

-- The engage banner and the layout samples are rows in every sense the warning surface
-- cares about — they carry a key, a tier and a sound tier, and they route through
-- `Warn.Emit` like anything else. Their keys are namespaced so they can never collide
-- with an encounter row's.
T.BANNER_ROW = { key = "__test_engage", tier = "special", sound = 2 }

-- ── State ─────────────────────────────────────────────────────────────────────
T.active   = false          -- THE quarantine flag; every rule above reads this
T.mode     = nil            -- nil | "row" | "boss" | "layout" | "playback" | "preview"
T.encId    = nil            -- the encounter a boss test / playback is running
T.speed    = nil            -- the live time scale, while one is installed
T.runtimes = {}             -- encId -> the test runtime driving it
T.previewed = {}            -- moduleId -> def (a special whose preview we turned on)
T.layoutKeys = {}           -- the transient route keys layout mode owns

function T.IsActive() return T.active and true or false end
function T.Mode()    return T.mode end
function T.Speed()   return T.speed end

-- ══════════════════════════════════════════════════════════════════════════════
--  THE TEST RUNTIME
-- ══════════════════════════════════════════════════════════════════════════════
-- One per encounter, created lazily and reused, so pressing play on a second row of
-- the same boss addresses the same timer objects the first one made — which is what
-- makes "click again restarts" true rather than "click again adds another bar".
function T.RuntimeFor(encId)
    local rt = T.runtimes[encId]
    if rt then return rt end
    local enc = Addon:GetEncounter(encId)
    if not enc or not API() then return nil end
    rt = API().NewRuntime(enc, { trigger = "test" })
    T.runtimes[encId] = rt
    return rt
end

-- A NON-encounter timer object: layout mode's samples, and nothing else. Prefixed so
-- the sweep can find them, since no runtime owns them.
local function syntheticTimer(id, def)
    local Tm = Addon.Timers
    if not Tm then return nil end
    local key = T.PREFIX .. id
    local t = Tm.objects[key]
    if t then return t end
    def.id = key
    return Tm.New(def)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  BEGIN / STOP — the quarantine's two ends
-- ══════════════════════════════════════════════════════════════════════════════
function T.Begin(mode, encId)
    T.active = true
    T.mode   = mode
    T.encId  = encId
    -- The anchors have to exist before anything is drawn at them; they are created
    -- lazily on the first bar, so a placement pass on a quiet night would otherwise
    -- have nothing to drag.
    if Addon.Bars then Addon.Bars.EnsureAnchors() end
    if Addon.Warnings then Addon.Warnings.EnsureAnchors() end
    return true
end

-- Stop every synthetic bar. The encounter-owned ones are stopped by their runtime's
-- own Teardown, which is the shipping sweep and knows about its own scheduled work.
function T.SweepSynthetic()
    local Tm = Addon.Timers
    if not Tm then return 0 end
    local n, pre = 0, #T.PREFIX
    for id, obj in pairs(Tm.objects) do
        if tostring(id):sub(1, pre) == T.PREFIX then n = n + obj:Stop() end
    end
    return n
end

-- Put back whatever a special module's own Test / SetPreview turned on. Five of the
-- six shipped specials declare `SetPreview(on)`, which is the explicit off switch;
-- the one that does not has a Test that TOGGLES, so calling it again is its off switch.
local function endPreviews()
    for id, def in pairs(T.previewed) do
        T.previewed[id] = nil
        if type(def.SetPreview) == "function" then
            def:SetPreview(false)
        elseif type(def.Test) == "function" then
            def:Test()
        end
    end
end

-- IDEMPOTENT AND TOTAL. Called by the owner, by a mode switch, and by the engine on a
-- real pull — so it must be safe to call when nothing is running, and it must leave
-- nothing behind when something is.
function T.Stop(reason)
    if not T.active and not T.layoutOn and not T._realClock and not next(T.runtimes) then
        return false
    end

    -- The clock comes back FIRST, so everything below is cancelled and swept against
    -- the same clock it was scheduled on.
    T.EndScaledClock()

    for encId, rt in pairs(T.runtimes) do
        T.runtimes[encId] = nil
        rt:Teardown()                       -- stops its timers, cancels its scheduled work
    end
    T.SweepSynthetic()
    S():CancelOwner(T)

    if Addon.Warnings then
        Addon.Warnings.Reset()
        if Addon.Warnings.View and Addon.Warnings.View.Sleep then Addon.Warnings.View.Sleep() end
    end
    if Addon.Bars then Addon.Bars.Sweep("test-stop") end
    -- ONLY THE COUNTDOWN WE STARTED. The quarantine stops a test SENDING sync, not
    -- receiving it, so a real pull timer broadcast by the raid can perfectly well be
    -- running while someone has a layout pass open — and cancelling that on the way out
    -- would take the raid's countdown off their screen along with the sample.
    if Addon.CancelPullTimer and Addon.pullSource == "layout" then
        Addon:CancelPullTimer("layout")
    end

    endPreviews()

    -- Layout mode's own residue: the transient buckets, the sample special's anchor,
    -- and the dressed drag handles.
    if Addon.Route then Addon.Route.ClearTransient() end
    for i = #T.layoutKeys, 1, -1 do T.layoutKeys[i] = nil end
    if T.layoutOn then
        if T.sampleSpecial and T.sampleSpecial.Hide then T.sampleSpecial:Hide() end
        if Addon.Anchors then Addon.Anchors.Forget("#layout:special") end
        if Addon.HideHudAnchors then Addon:HideHudAnchors() end
    end
    T.layoutOn = false

    T.active, T.mode, T.encId, T.speed = false, nil, nil, nil
    T.stoppedBecause = reason
    return true
end

-- ══════════════════════════════════════════════════════════════════════════════
--  FEATURE 1 + 5 — ONE ROW: the play button and the speaker button
-- ══════════════════════════════════════════════════════════════════════════════
function T.SampleName()
    local n = API() and API().PlayerName()
    if type(n) == "string" and n ~= "" then return n end
    return T.SAMPLE_NAME
end

-- The warning text a row would produce, built by the SAME rules `Runtime:Act` uses —
-- stack interpolation, count interpolation, target interpolation — with a sample event
-- standing in for the real one. Kept beside them deliberately: if Act's rules change
-- and this does not, the rehearsal starts lying, and the harness asserts both.
T.SAMPLE_STACKS = 3
T.SAMPLE_COUNT  = 2

function T.WarnText(row, target)
    local text = row.text or row.name or row.key or "?"
    if row.stacks and text:find("%%d") then
        text = (text:gsub("%%d", tostring(T.SAMPLE_STACKS)))
    elseif row.count then
        if text:find("%%d") then text = (text:format(T.SAMPLE_COUNT))
        else text = text .. " " .. tostring(T.SAMPLE_COUNT) end
    end
    if target and text:find("%%s") then text = (text:gsub("%%s", target)) end
    return text
end

-- Fire one warning row through the real dispatch seam — the very calls `Runtime:Act`
-- makes, so batching, routing, name colouring, the flash and the sound all apply.
function T.FireWarning(encId, row)
    local target = T.SampleName()
    local text   = T.WarnText(row, target)
    if (row.tier or "announce") == "special" then
        Addon:EmitSpecial(encId, row, text, target)
    else
        Addon:EmitAnnounce(encId, row, text, target)
    end
    return text
end

-- Start one timer row on the test runtime at its REAL value for the given occurrence.
-- Occurrence 1 is what a pull produces, which is the honest default for "show me this
-- bar": a row with a `pull` value shows its pull value, exactly as it will in the fight.
function T.FireTimer(encId, row, occurrence)
    local rt = T.RuntimeFor(encId)
    if not rt then return nil end
    local t = rt:Timer(row.key)
    if not t then return nil end
    local dur = API().ResolveDuration(row, occurrence or 1, rt.stage)
    if dur == nil then return nil end
    -- A `requiresCombat` countdown is dropped out of combat by design (§4.4), and a
    -- rehearsal is always out of combat, so the row would be silent for the wrong
    -- reason. The test object is the runtime's own, so the relaxation is scoped to it.
    t.requiresCombat = nil
    -- A COUNTED row's label embeds the occurrence it runs toward, read off the
    -- `Addon._mechCount` mirror that `Runtime:Act` writes one line before Start.
    -- This is that same write for the rehearsal's chosen occurrence — without it the
    -- rehearsal bar would wear whatever number the LAST REAL FIGHT left behind
    -- ("Spore 23" on a quiet Tuesday), which is exactly the kind of lie the preview
    -- rules forbid.
    if row.count then
        Addon._mechCount = Addon._mechCount or {}
        Addon._mechCount[API().OptionKey(encId, row.key)] = occurrence or 1
    end
    return t:Start(dur), dur
end

-- Look a row up across every list of the compiled encounter. `rowsByKey` already
-- indexes all of them, so this is one lookup plus a kind classification.
function T.FindRow(encId, rowKey)
    local enc = Addon:GetEncounter(encId)
    if not enc then return nil end
    local row = enc.rowsByKey and enc.rowsByKey[rowKey]
    if not row then return nil end
    for _, r in ipairs(enc.timers)   do if r == row then return row, "timer",    enc end end
    for _, r in ipairs(enc.warnings) do if r == row then return row, "warning",  enc end end
    for _, r in ipairs(enc.schedule) do if r == row then return row, "schedule", enc end end
    return row, "other", enc
end

-- FEATURE 1. Deliberately NOT gated on the row's enable checkbox: pressing play is an
-- explicit request to see this row now, the same way the shipped "Test Alert" button
-- has always ignored it. Everything downstream of the fire IS gated normally.
function T.Row(encId, rowKey)
    local row, kind = T.FindRow(encId, rowKey)
    if not row then return nil, "unknown_row" end
    if Addon.Lifecycle and Addon.Lifecycle:AnyEngaged() then return nil, "engaged" end
    if not T.active then T.Begin("row", encId) end

    if kind == "timer" then
        local bar = T.FireTimer(encId, row, 1)
        return bar and "timer" or nil, bar
    end
    if kind == "warning" then
        return "warning", T.FireWarning(encId, row)
    end
    -- A schedule row's user-visible output is its announce line; a row with neither an
    -- announce nor a pre-announce has nothing to show and says so rather than pretending.
    local text = row.announce or row.preAnnounce
    if not text then return nil, "nothing_to_show" end
    Addon:EmitAnnounce(encId, row, (text:gsub("%%d", "1")))
    return "schedule", text
end

-- FEATURE 5. The cue this row resolves to TODAY, through the real dispatch, respecting
-- the selected packs — not an approximation of it.
--
-- A warning row's cue is `Warn.DispatchSound`, which IS the §5.5 decision table (custom
-- sound beats voice pack, voice replaces an announce only when the user asked, a special
-- tier's sound is suppressible on its own). A TIMER row has no warning tier, so its
-- audible cue is either the sound the user attached to the row or the spoken countdown
-- the row declares — in that order, because a user-chosen sound always wins.
function T.RowSound(encId, rowKey)
    local row, kind = T.FindRow(encId, rowKey)
    if not row then return nil, "unknown_row" end
    local W = Addon.Warnings

    if kind == "warning" then
        if not W then return nil, "no_surface" end
        -- THE PREVIEW IS HONEST OR IT IS USELESS (owner directive 2026-08-07). This
        -- goes through the SAME DispatchSound the fight uses, so the sound policy and
        -- the row's three-state override are already applied: a row that is silent by
        -- default is silent here, and one the user switched On is not. The button
        -- never plays "what this row COULD sound like".
        local played = W.DispatchSound(encId, row, (row.tier or "announce") == "special")
        if played then return played end
        return nil, "silent"
    end

    local db = Addon.db
    local o  = (db and type(db.mechanics) == "table") and db.mechanics[API().OptionKey(encId, rowKey)] or nil
    if o and o.sound and o.sound ~= "none" then
        Addon:PlaySoundByKey(o.sound, true)
        return "sound"
    end
    if row.countdown and Addon.PlayVoiceNumber then
        local depth = row.countdown.depth or (Addon.Timers and Addon.Timers.COUNTDOWN_DEPTH) or 4
        local cap   = Addon.CountdownMax
        if cap and depth > cap then depth = cap end
        if depth >= 1 and Addon:PlayVoiceNumber(depth) then return "count" end
    end
    return nil, "silent"
end

-- ══════════════════════════════════════════════════════════════════════════════
--  FEATURE 2 — THE PER-BOSS REHEARSAL
-- ══════════════════════════════════════════════════════════════════════════════
-- Scheduled steps are PLAIN functions with a stable identity and `T` as their owner,
-- so `Sched:CancelOwner(T)` in Stop sweeps every one of them (§3.2).
local function warnStep(encId, rowKey)
    if not T.active then return end
    local row = T.FindRow(encId, rowKey)
    if row then T.FireWarning(encId, row) end
end

local function phaseStep(encId, stage)
    if not T.active then return end
    local rt = T.runtimes[encId]
    if rt then rt:SetStage(stage) end
end

-- The specials, invoked through the seam `RegisterModule` has always published.
function T.StartBossPreviews(raidId, bossId)
    local n = 0
    for _, def in ipairs(Addon:GetBossModules(raidId, bossId)) do
        if Addon:IsModuleEnabled(def.id, def) and not T.previewed[def.id] then
            local ran = false
            if type(def.SetPreview) == "function" then def:SetPreview(true); ran = true
            elseif type(def.Test) == "function" then def:Test(); ran = true end
            if ran then
                T.previewed[def.id] = def
                -- A module's own preview re-runs its Position(), which points at the
                -- screen; re-installing puts the previewed widget where it will
                -- actually be in the fight. Idempotent — it costs one SetPoint.
                Addon:InstallModuleAnchor(def)
                n = n + 1
            end
        end
    end
    return n
end

function T.Boss(encId)
    local enc = Addon:GetEncounter(encId)
    if not enc then return nil, "unknown_encounter" end
    if Addon.Lifecycle and Addon.Lifecycle:AnyEngaged() then return nil, "engaged" end
    T.Stop("restart")
    T.Begin("boss", encId)

    local rt = T.RuntimeFor(encId)
    if not rt then T.Stop("no_runtime"); return nil, "no_runtime" end

    -- 1. The engage banner, on the Major warning surface where a real one lands.
    Addon:EmitSpecial(encId, T.BANNER_ROW,
        (enc.name or encId) .. " \226\128\148 rehearsal")

    -- 2. THE TRUE MID-FIGHT BAR POPULATION: every ENABLED timer row, at its real
    -- first-occurrence value, all at once. This is the screen a raider sees a second
    -- after the pull, and seeing all of it together is the entire point of the feature.
    local bars = 0
    for _, row in ipairs(enc.timers) do
        if API().IsRowEnabled(encId, row) then
            if T.FireTimer(encId, row, 1) then bars = bars + 1 end
        end
    end

    -- 3. The warnings, walked out one per second WITHIN each tier — two ladders, run
    -- concurrently, so an announcement and a special can share a second without either
    -- becoming unreadable. Firing them all at once would prove nothing except that the
    -- stacks overflow.
    local ladder, warns = { announce = 0, special = 0 }, 0
    for _, row in ipairs(enc.warnings) do
        if API().IsRowEnabled(encId, row) then
            local tier = ((row.tier or "announce") == "special") and "special" or "announce"
            ladder[tier] = ladder[tier] + 1
            S():Schedule(ladder[tier] * T.WARN_STAGGER, warnStep, T, encId, row.key)
            warns = warns + 1
        end
    end

    -- 4. The phases, stepped in declaration order. `SetStage` is the real one, so it
    -- broadcasts ENGINE_STAGE and routes the synthetic `stage` event — which is how a
    -- phase-gated bar gets to show up in a rehearsal at all.
    local steps = 0
    for _, prow in ipairs(enc.phases) do
        if prow.stage ~= nil then
            steps = steps + 1
            S():Schedule(steps * T.PHASE_STAGGER, phaseStep, T, encId, prow.stage)
        end
    end

    -- 5. The boss's own specials.
    local lg = enc.legacy or {}
    local mods = T.StartBossPreviews(lg.raidId, lg.bossId)

    return { bars = bars, warnings = warns, phases = steps, modules = mods }
end

-- ══════════════════════════════════════════════════════════════════════════════
--  FEATURE 3 — LAYOUT MODE
-- ══════════════════════════════════════════════════════════════════════════════
-- The persistent placement workbench. `/drm demo` stays exactly what it is — the
-- one-shot quick version, fire and forget. This is the other thing: it populates every
-- surface at once and then KEEPS them populated, so both hands are free to drag.
T.layoutOn = false

-- One sample per colour class per bucket. Class 1..7 are ENGINE SPEC §4.5's, and the
-- durations descend so the stack sorts visibly rather than sitting in registration order.
T.LAYOUT_CLASSES = {
    { color = 1, text = "Add wave" },
    { color = 2, text = "Ground effect" },
    { color = 3, text = "Mind Control" },
    { color = 4, text = "Interrupt cast" },
    { color = 5, text = "Tank swap" },
    { color = 6, text = "Phase change" },
    { color = 7, text = "Custom timer" },
}

local function layoutBar(bucket, i, spec, seconds)
    local key = ("layout%s%d"):format(bucket, i)
    local optionKey = "#layout:" .. key
    -- The transient bucket is what puts a class-1 bar in the MINOR list and a class-5
    -- bar in the MAJOR one — something severity alone can never do, and something a
    -- placement pass needs to see.
    Addon.Route.SetTransient(optionKey, bucket)
    T.layoutKeys[#T.layoutKeys + 1] = optionKey
    local t = syntheticTimer(("layout:%s:%d"):format(bucket, i), {
        key = key, encId = "#layout", kind = "cd",
        text = spec.text, color = spec.color,
    })
    if t then t:Start(seconds) end
    return t
end

-- Everything the layout pass shows, (re)started from scratch. Called on entry and by
-- the upkeep tick, which is why it is idempotent: a bar that is still running is simply
-- restarted, and a warning line that faded is pushed again.
function T.PopulateLayout()
    local n = 0
    -- Rebuilt, not appended to: this runs again on every upkeep tick, and a list that
    -- only ever grew would be a slow leak for as long as a placement pass is open.
    for i = #T.layoutKeys, 1, -1 do T.layoutKeys[i] = nil end
    for i, spec in ipairs(T.LAYOUT_CLASSES) do
        local secs = T.LAYOUT_BAR - i          -- descending, so the sort is visible
        if layoutBar("major", i, spec, secs) then n = n + 1 end
        if layoutBar("minor", i, spec, secs) then n = n + 1 end
    end
    -- The two shapes a placement pass otherwise never sees: a variance window, and a
    -- count bar with its number embedded in the label ("Meteor 3").
    local v = syntheticTimer("layout:variance", {
        key = "layoutvariance", encId = "#layout", kind = "cd",
        text = "Breath (window)", color = 2,
    })
    if v then
        Addon.Route.SetTransient("#layout:layoutvariance", "minor")
        T.layoutKeys[#T.layoutKeys + 1] = "#layout:layoutvariance"
        v:Start("v" .. (T.LAYOUT_BAR * 0.5) .. "-" .. T.LAYOUT_BAR)
        n = n + 1
    end
    local c = syntheticTimer("layout:count", {
        key = "layoutcount", encId = "#layout", kind = "cd",
        text = "Meteor", color = 3, count = true,
    })
    if c then
        Addon.Route.SetTransient("#layout:layoutcount", "major")
        T.layoutKeys[#T.layoutKeys + 1] = "#layout:layoutcount"
        c:Start(T.LAYOUT_BAR * 0.8, 3)
        n = n + 1
    end

    -- BOTH warning tiers, and through `Warn.Emit` rather than at the two tier surfaces
    -- directly: the router is the thing a placement pass is placing the output of, so
    -- driving the surfaces behind its back would be testing the wrong code. The
    -- transient buckets make which line lands where a fact rather than a derivation.
    --
    -- THE HOLD IS THE WHOLE TRICK. A warning's shipped lifetime is 1.5 s (§12), so a
    -- pass that re-pushed the lines on a timer would strobe the screen flash several
    -- times a second and scroll its own stacks. A warning row may carry its own
    -- duration, so the samples simply declare a very long one and then sit still —
    -- one flash on entry, and a stable screen to drag against (principle 7).
    n = n + T.PopulateLayoutWarnings(false)

    -- The pull countdown is a bar a raider places, so a placement pass needs one. It is
    -- (re)started only when there is no live pull bar: restarting it on every upkeep
    -- tick would put a fresh "Pull in 30" announcement on the stack every two seconds.
    -- A non-"manual" source on purpose — a placement pass must never put a countdown on
    -- forty other people's screens (and the quarantine would refuse it anyway; this is
    -- the belt to that brace).
    local Tm = Addon.Timers
    if Addon.StartPullTimer and not (Tm and Tm.bars["engine:pull"]) then
        Addon:StartPullTimer(T.LAYOUT_PULL, "layout")
        n = n + 1
    end
    return n
end

-- `force` re-pushes regardless; otherwise a tier is refilled only when it has actually
-- emptied, which with the long hold above means "essentially never".
function T.PopulateLayoutWarnings(force)
    local W = Addon.Warnings
    if not W then return 0 end
    local n = 0
    if force or W.announceStack:Count() == 0 then
        for slot = 1, 4 do
            local row = { key = "layoutann" .. slot, tier = "announce", color = slot,
                          duration = T.LAYOUT_WARN_HOLD }
            local k = W.OptionKey("#layout", row)
            Addon.Route.SetTransient(k, "minor")
            T.layoutKeys[#T.layoutKeys + 1] = k
            W.Emit("#layout", row, ("Announcement colour %d"):format(slot))
            n = n + 1
        end
    end
    if force or W.specialStack:Count() == 0 then
        for tier = 1, 5 do
            local row = { key = "layoutspec" .. tier, tier = "special", sound = tier,
                          duration = T.LAYOUT_WARN_HOLD }
            local k = W.OptionKey("#layout", row)
            Addon.Route.SetTransient(k, "major")
            T.layoutKeys[#T.layoutKeys + 1] = k
            W.Emit("#layout", row,
                ("Special warning \226\128\148 %s"):format(W.SOUND_TIER[tier].label))
            n = n + 1
        end
    end
    return n
end

-- The docked special sample: the fifth anchor is invisible until a special module is
-- both enabled and running, which means the one anchor a raider most needs to place is
-- the one they cannot see. This is a pad of the same size a docked special occupies,
-- installed through the same seam a module uses.
function T.EnsureSampleSpecial()
    if T.sampleSpecial then return T.sampleSpecial end
    if type(_G.CreateFrame) ~= "function" then return nil end
    local f = _G.CreateFrame("Frame", nil, _G.UIParent, "BackdropTemplate")
    f:SetSize(200, 76)                       -- BOTH dimensions at creation
    f:SetFrameStrata("MEDIUM")
    Addon:ApplyDarkBackdrop(f)
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("CENTER")
    f.label:SetJustifyH("CENTER")
    Addon:TrySetFont(f.label, "microLabel")
    Addon:StyleFont(f.label, "subText")
    f.label:SetText("Boss special (sample)")
    T.sampleSpecial = f
    return f
end

-- The upkeep tick. Re-populates what expired and RE-APPLIES every anchor, which is what
-- "refreshing as placement changes" means: a drag that moves the Major list moves the
-- sample bars in it on the next tick without the pass being restarted.
local function layoutTick()
    if not T.layoutOn then return end
    T.PopulateLayout()
    if Addon.Anchors then Addon.Anchors.ReapplyAll() end
    S():Schedule(T.LAYOUT_REFRESH, layoutTick, T)
end

function T.Layout(on)
    if on == nil then on = not T.layoutOn end
    if on then
        if Addon.Lifecycle and Addon.Lifecycle:AnyEngaged() then return false, "engaged" end
        T.Stop("layout")
        T.Begin("layout", nil)
        T.layoutOn = true
        local f = T.EnsureSampleSpecial()
        if f and Addon.Anchors then
            Addon.Anchors.EnsureSpecialsAnchor()
            Addon.Anchors.Install("#layout:special", f, {
                label = "Boss special (sample)",
                dock  = Addon.Anchors.ANCHOR_SPECIALS,
            })
            f:Show()
        end
        T.PopulateLayout()
        if Addon.ShowHudAnchors then Addon:ShowHudAnchors() end
        S():Schedule(T.LAYOUT_REFRESH, layoutTick, T)
        return true
    end
    T.Stop("layout off")
    return false
end

-- ══════════════════════════════════════════════════════════════════════════════
--  FEATURE 7 — PREVIEW (the Placement section's button, owner rework 2026-08-10)
-- ══════════════════════════════════════════════════════════════════════════════
-- One press, all four buckets at once: a bar on each list, a line on each warning
-- tier, everything through the real dispatch with layout mode's own transient-route
-- trick — and nothing more. No pull timer, no sample special, no upkeep tick: this
-- is the one-shot the Placement section fires so a drag happens against real
-- visuals, and Stop (Lock all / leaving the page / a real pull) sweeps it whole.
-- The warning samples hold with LAYOUT_WARN_HOLD for the same reason layout mode's
-- do: a line that fades in 1.5 s is not a thing you can place an anchor against.
T.PREVIEW_BAR = 35            -- sample bar length, seconds — long enough to drag against

function T.Preview()
    if Addon.Lifecycle and Addon.Lifecycle:AnyEngaged() then return nil, "engaged" end
    T.Stop("restart")
    T.Begin("preview", nil)
    local n = 0
    -- One bar per LIST, routed by the transient table exactly as layout mode routes
    -- its samples — a class-1 bar is Major by severity, so the transient is what
    -- makes "one on each list" a fact rather than a coincidence.
    local specs = {
        { bucket = "major", color = 1, text = "Add wave (sample)" },
        { bucket = "minor", color = 2, text = "Ground effect (sample)" },
    }
    for i, spec in ipairs(specs) do
        local optionKey = "#preview:" .. spec.bucket
        Addon.Route.SetTransient(optionKey, spec.bucket)
        T.layoutKeys[#T.layoutKeys + 1] = optionKey
        local t = syntheticTimer("preview:" .. spec.bucket, {
            key = "preview" .. spec.bucket, encId = "#preview", kind = "cd",
            text = spec.text, color = spec.color,
        })
        if t then t:Start(T.PREVIEW_BAR - i); n = n + 1 end   -- descending: sort visible
    end
    -- One line on each warning tier, through `Warn.Emit` — the router is the thing
    -- the Placement section places the output of, so the surfaces are never driven
    -- behind its back.
    local Wn = Addon.Warnings
    if Wn then
        local ann = { key = "previewann",  tier = "announce", color = 2,
                      duration = T.LAYOUT_WARN_HOLD }
        local spc = { key = "previewspec", tier = "special",  sound = 2,
                      duration = T.LAYOUT_WARN_HOLD }
        local ka, ks = Wn.OptionKey("#preview", ann), Wn.OptionKey("#preview", spc)
        Addon.Route.SetTransient(ka, "minor"); T.layoutKeys[#T.layoutKeys + 1] = ka
        Addon.Route.SetTransient(ks, "major"); T.layoutKeys[#T.layoutKeys + 1] = ks
        Wn.Emit("#preview", ann, "Announcement (sample)")
        Wn.Emit("#preview", spc, "Special warning (sample)")
        n = n + 2
    end
    return n
end

-- ══════════════════════════════════════════════════════════════════════════════
--  FEATURE 4 — COMPRESSED PLAYBACK
-- ══════════════════════════════════════════════════════════════════════════════
-- THE CLOCK, and the whole reason this is safe.
--
-- The scheduler's heap is keyed on ABSOLUTE time, so the only way to accelerate it
-- without touching a single scheduling call site is to accelerate the clock it reads.
-- Two properties make the swap invisible:
--
--   CONTINUOUS IN.   scaled(t0) == real(t0). The scaled clock is anchored at the value
--                    the real clock had the instant it was installed, so nothing already
--                    queued jumps: a task due in 20 s is still due in 20 scaled seconds
--                    (4 real ones at 5x), never immediately.
--   REBASED OUT.     the scaled clock has run AHEAD by the time it comes out, so simply
--                    restoring the real one would move every surviving task's due time.
--                    `Sched:Rebase(realNow - scaledNow)` shifts the whole heap by that
--                    constant, preserving every remaining DELAY exactly. A constant
--                    shift cannot reorder a strict min, so the heap is untouched.
--
-- The live clock function itself is CAPTURED AND RESTORED VERBATIM — including a
-- harness-injected one — so the live path is never rewritten, only wrapped for the
-- duration of a run that refuses to start while a real fight is up.
function T.BeginScaledClock(speed)
    if T._realClock then return false end
    speed = tonumber(speed) or T.PLAYBACK_SPEED
    if speed < T.PLAYBACK_MIN then speed = T.PLAYBACK_MIN end
    if speed > T.PLAYBACK_MAX then speed = T.PLAYBACK_MAX end
    local sched = S()
    T._realClock = sched.clock
    T._raw0 = T._realClock()
    T._t0   = T._raw0
    T.speed = speed
    sched:SetClock(function()
        return T._t0 + (T._realClock() - T._raw0) * T.speed
    end)
    return speed
end

function T.EndScaledClock()
    if not T._realClock then return false end
    local sched = S()
    local scaledNow = sched:Now()
    sched:SetClock(T._realClock)
    local delta = sched:Now() - scaledNow
    sched:Rebase(delta)
    T._realClock, T._raw0, T._t0, T.speed = nil, nil, nil, nil
    return true, delta
end

-- Resolve what the user typed. An encounter id wins outright; then a boss id; then a
-- case-insensitive substring of the encounter's name, which is how "heigan" finds
-- "Heigan the Unclean". Deterministic: the registry is walked in registration order and
-- the FIRST match wins, never a pairs() race.
function T.ResolveEncounter(ref)
    if type(ref) ~= "string" or ref == "" then return nil end
    local direct = Addon:GetEncounter(ref)
    if direct then return direct end
    local want = ref:lower()
    for _, enc in ipairs(Addon:GetEncounters()) do
        local lg = enc.legacy or {}
        if lg.bossId and lg.bossId:lower() == want then return enc end
    end
    for _, enc in ipairs(Addon:GetEncounters()) do
        if enc.name and enc.name:lower():find(want, 1, true) then return enc end
    end
    return nil
end

-- A module's published running order (modules.lua, the playback seam), scheduled on the
-- scaled clock and spoken through the real warning dispatch. This is how Gothik's
-- eighteen waves are playable at all: that schedule rides C_Timer inside the module,
-- which does not read the engine clock and therefore cannot be accelerated.
local function scriptStep(encId, label)
    if not T.active then return end
    Addon:EmitAnnounce(encId, { key = "__test_script", tier = "announce", color = 1 }, label)
end

function T.ScheduleModuleScripts(enc)
    local lg = enc.legacy or {}
    local n = 0
    for _, def in ipairs(Addon:GetBossModules(lg.raidId, lg.bossId)) do
        if type(def.playbackScript) == "function" then
            local okc, steps = pcall(def.playbackScript, def)
            if okc and type(steps) == "table" then
                for _, st in ipairs(steps) do
                    if type(st) == "table" and tonumber(st.at) then
                        S():Schedule(tonumber(st.at), scriptStep, T, enc.id,
                                     tostring(st.label or "?"))
                        n = n + 1
                    end
                end
            end
        end
    end
    return n
end

local function playbackHorizon() return T.Stop("playback complete") end

function T.Playback(ref, speed)
    local enc = (type(ref) == "table") and ref or T.ResolveEncounter(ref)
    if not enc then return nil, "unknown_encounter" end
    if Addon.Lifecycle and Addon.Lifecycle:AnyEngaged() then return nil, "engaged" end
    T.Stop("restart")
    T.Begin("playback", enc.id)

    -- The clock goes in BEFORE anything is scheduled, so every due time below is
    -- computed in the scaled base and the run is accelerated from its first tick.
    local used = T.BeginScaledClock(speed)

    local rt = T.RuntimeFor(enc.id)
    if not rt then T.Stop("no_runtime"); return nil, "no_runtime" end

    -- THE ENCOUNTER'S OWN SCHEDULED SCRIPT, through the shipping code. This is what
    -- reproduces Heigan's alternating dance clock and Noth's alternating teleport tail:
    -- `StartPullSchedules` walks the `gaps` tables, arms the pre-warnings and routes
    -- every tick, and it does all of it on the scheduler it always did.
    rt:StartPullSchedules()
    local scripted = T.ScheduleModuleScripts(enc)

    S():Schedule(T.PLAYBACK_HORIZON, playbackHorizon, T)
    return enc.id, used, scripted
end

-- ══════════════════════════════════════════════════════════════════════════════
--  FEATURE 6 — /drm validate
-- ══════════════════════════════════════════════════════════════════════════════
-- A sweep of the WHOLE registry against the LIVE client. Patch-day insurance: a spell
-- id Blizzard renumbers is a row that silently never fires again, and the only place
-- that is cheap to find out is in the game, before the raid.
--
-- Every client call goes through `T.env` for the same reason the lifecycle's does: so
-- the harness can drive the shipping sweep over a fixture registry with a known-bad id
-- and assert that it is named, rather than asserting against a re-implementation.
T.env = {
    SpellName = function(id)
        local f = _G.GetSpellInfo
        if type(f) ~= "function" then return nil end
        local okc, name = pcall(f, id)
        return okc and name or nil
    end,
    SpellTexture = function(id)
        local f = _G.GetSpellTexture
        if type(f) ~= "function" then return nil end
        local okc, tex = pcall(f, id)
        return okc and tex or nil
    end,
}

function T.SetEnv(t)
    if type(t) ~= "table" then return end
    for k, v in pairs(t) do T.env[k] = v end
end

-- Every spell id a row can fire on: its own, plus every id on every trigger it carries.
-- Deduplicated and returned in first-seen order, so a report reads the same twice.
local TRIGGER_FIELDS = {
    "start", "restart", "stop", "trigger", "inc", "dec", "reset",
    "add", "remove", "clear", "on",
}
local TRIGGER_LISTS = {
    "starts", "restarts", "stops", "triggers", "incs", "resets",
    "adds", "removes", "clears", "variants", "transitions", "cancels",
}

local function collectIds(row, out, seen)
    local function take(v)
        if type(v) == "number" then
            if not seen[v] then seen[v] = true; out[#out + 1] = v end
        elseif type(v) == "table" then
            for _, n in ipairs(v) do take(n) end
        end
    end
    take(row.spellId)
    for _, f in ipairs(TRIGGER_FIELDS) do
        local tr = row[f]
        if type(tr) == "table" then take(tr.spellId) end
    end
    for _, f in ipairs(TRIGGER_LISTS) do
        local list = row[f]
        if type(list) == "table" then
            for _, tr in ipairs(list) do
                if type(tr) == "table" then take(tr.spellId) end
            end
        end
    end
    return out
end
T.CollectIds = function(row) return collectIds(row, {}, {}) end

-- Every row of an encounter, in a fixed order, each tagged with the list it came from.
local ROW_LISTS = { "timers", "warnings", "schedule", "counters", "states",
                    "rosters", "restyles", "scans", "icons" }

function T.EachRow(enc, fn)
    for _, listName in ipairs(ROW_LISTS) do
        for _, row in ipairs(enc[listName] or {}) do
            if row.key then fn(row, listName) end
        end
    end
end

T.VERDICT_OK      = "ok"
T.VERDICT_SUSPECT = "SUSPECT ID"
T.VERDICT_ICON    = "ICON UNRESOLVED"
T.VERDICT_MARK    = "MARK OUT OF RANGE"
T.VERDICT_SOUND   = "SOUND MISSING"
T.VERDICT_VOICE   = "VOICE MISSING"

-- `icon` MEANS TWO DIFFERENT THINGS in the grammar, and a sweep that did not know it
-- would flag every raid-marker row in the addon. On an ordinary row it is a texture
-- path; on an `icons` row (ENGINE SPEC's raid-target markers — Kel'Thuzad's Mana Bomb,
-- C'Thun's eye beam, Onyxia's fireball) it is a RAID TARGET INDEX, 1..8. Both are
-- checked, each by its own rule.
T.MARK_MIN, T.MARK_MAX = 1, 8

-- Returns { lines = {…}, checked = , suspects = , problems = { {enc=,row=,kind=,detail=} } }.
-- Grouped by encounter, in registry order, and only encounters WITH a problem produce a
-- group — a clean sweep of 65 encounters should read as one line, not sixty-five.
function T.Validate()
    local report = { lines = {}, problems = {}, checked = 0, spells = 0,
                     suspects = 0, encounters = 0 }
    local function line(s) report.lines[#report.lines + 1] = s end
    local function problem(enc, row, kind, detail)
        report.problems[#report.problems + 1] =
            { enc = enc.id, encName = enc.name, row = row.key, kind = kind, detail = detail }
        if kind == T.VERDICT_SUSPECT then report.suspects = report.suspects + 1 end
    end

    for _, enc in ipairs(Addon:GetEncounters()) do
        report.encounters = report.encounters + 1
        local before = #report.problems
        T.EachRow(enc, function(row, listName)
            report.checked = report.checked + 1

            -- 1. SPELL IDS. nil from GetSpellInfo means the client does not know this
            -- id — the row can never fire, and nothing else in the addon would say so.
            local ids = collectIds(row, {}, {})
            for _, id in ipairs(ids) do
                report.spells = report.spells + 1
                if not T.env.SpellName(id) then
                    problem(enc, row, T.VERDICT_SUSPECT, tostring(id))
                end
            end

            -- 2. ICONS. A row that declares one must declare a usable path; a row that
            -- declares none inherits its spell's, so it is only unresolved when the
            -- spell has no texture either. (There is no client call that answers "does
            -- this texture path exist", so a declared path is checked for SHAPE and
            -- said to be checked for shape — an honest partial beats a false green.)
            if listName == "icons" then
                -- A raid-marker row: `icon` and `base` are marker INDICES, not paths.
                for _, f in ipairs({ "icon", "base" }) do
                    local v = row[f]
                    if v ~= nil then
                        local n = tonumber(v)
                        if not n or n < T.MARK_MIN or n > T.MARK_MAX then
                            problem(enc, row, T.VERDICT_MARK, f .. "=" .. tostring(v))
                        end
                    end
                end
            elseif row.icon ~= nil then
                if type(row.icon) ~= "string" or row.icon == "" then
                    problem(enc, row, T.VERDICT_ICON, "declared icon is not a path")
                end
            elseif #ids > 0 and (row.kind or row.tier) then
                if not T.env.SpellTexture(ids[1]) then
                    problem(enc, row, T.VERDICT_ICON, "spell " .. ids[1] .. " has no texture")
                end
            end

            -- 3. SOUNDS. The row's own configured sound key must resolve in the bucket.
            local db = Addon.db
            local o  = (db and type(db.mechanics) == "table")
                       and db.mechanics[API().OptionKey(enc.id, row.key)] or nil
            local key = o and o.sound
            if key and key ~= "none" and not Addon:GetSoundByKey(key) then
                problem(enc, row, T.VERDICT_SOUND, tostring(key))
            end

            -- 4. VOICE CUES, in the pack that is actually selected.
            if row.voice and not Addon:GetVoiceLine(row.voice) then
                problem(enc, row, T.VERDICT_VOICE, tostring(row.voice))
            end
        end)

        if #report.problems > before then
            line(("%s (%s)"):format(enc.name or enc.id, enc.id))
            for i = before + 1, #report.problems do
                local p = report.problems[i]
                line(("    %-14s %s  \226\134\146  %s"):format(p.kind, p.row, p.detail))
            end
        end
    end
    return report
end

function T.ValidateText(report)
    report = report or T.Validate()
    local out = {}
    out[#out + 1] = ("-- Daseeki Raid Mechanics data validation (build %s) --")
        :format((Addon.Telemetry and Addon.Telemetry.BUILD) or "?")
    out[#out + 1] = ("%d encounters, %d rows, %d spell ids checked.")
        :format(report.encounters, report.checked, report.spells)
    if #report.problems == 0 then
        out[#out + 1] = "No problems found."
    else
        out[#out + 1] = ("%d problem(s), %d of them SUSPECT IDs:")
            :format(#report.problems, report.suspects)
        out[#out + 1] = ""
        for _, l in ipairs(report.lines) do out[#out + 1] = l end
    end
    return table.concat(out, "\n")
end

-- Printed AND written to the debug log, because the log is the thing Drew can paste
-- into a report a week later when the raid has moved on.
function T.RunValidate()
    local report = T.Validate()
    local text = T.ValidateText(report)
    if Addon.DLog then
        for l in (text .. "\n"):gmatch("([^\n]*)\n") do
            if l ~= "" then Addon.DLog("%s", l) end
        end
    end
    local DS = _G.DaseekiSuite
    if DS and DS.ShowTextDialog then
        DS.ShowTextDialog("DRM Data Validation", text, true)
    elseif type(print) == "function" then
        for l in (text .. "\n"):gmatch("([^\n]*)\n") do
            if l ~= "" then print(Addon:Tag("[DRM]") .. " " .. l) end
        end
    end
    return report
end

-- ══════════════════════════════════════════════════════════════════════════════
--  BOOT
-- ══════════════════════════════════════════════════════════════════════════════
function T.Init()
    if T._inited then return false end
    T._inited = true
    -- QUARANTINE RULE 4, second net. `Life:StartCombat` already tears the suite down
    -- before the real runtime exists — that is the one that matters, because it is the
    -- one with the right ORDERING. This catches any future start path that reaches an
    -- engage without going through there. `Stop` is idempotent, so the pair is free.
    Addon:RegisterEngineCallback("ENGINE_ENGAGE", function()
        if T.active then T.Stop("real engage") end
    end, T)
    return true
end

return T
