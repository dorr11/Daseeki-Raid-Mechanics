--[[
    Daseeki Raid Mechanics 2.0 — PUBLIC CALLBACK SURFACE (wave 2)

    ===========================================================================
                 P U B L I C   C O N T R A C T  —  read this first
    ===========================================================================
    Everything in this file is a PROMISE TO THIRD-PARTY ADDONS. WeakAuras strings,
    nameplate addons and personal HUDs bind to it. Field names, field ORDER and
    event names are frozen once shipped: add at the end, never renumber, never
    rename. Breaking it silently breaks displays their authors cannot see failing.

    ENGINE SPEC §11.8 is blunt about why this exists: the callback surface "is the
    INTEGRATION CONTRACT with WeakAuras and nameplate addons and is more load-bearing
    than it looks — A REBUILD THAT OMITS IT BREAKS A LARGE ECOSYSTEM."

    ---------------------------------------------------------------------------
    HOW TO CONSUME IT
    ---------------------------------------------------------------------------
        local DRM = DaseekiRaidMechanics
        if DRM and DRM.Callbacks then
            DRM.Callbacks:Register("DRM_TimerStart", function(event, payload)
                -- payload.text, payload.remaining, payload.category, ...
                -- the same 18 fields also arrive positionally after `payload`
            end)
        end
        DRM.Callbacks:Unregister("DRM_TimerStart", myHandler)

    Handlers run inside a secure-call wrapper: a consumer that errors is dropped for
    that call and recorded in the engine telemetry ring; it can never break a raid.

    ---------------------------------------------------------------------------
    THE 18-FIELD TIMER PAYLOAD (ENGINE SPEC §4.5), IN ORDER
    ---------------------------------------------------------------------------
      1  barId          unique id of this bar (timer id + its identity arguments)
      2  text           formatted display text, count already substituted
      3  remaining      seconds left to the MINIMUM end of a variance window.
                        NOT the rendered end — audio, sorting and every callback
                        consumer are fed the minimum, so a consumer never tells a
                        raider to relax during a window in which the cast can land.
      4  icon           icon path / file id, or nil
      5  category       simplified category: cd | target | stage | cast |
                        break | pull | berserk, with nameplate-only timers
                        mapping to cdnp / castnp
      6  spellKey       the option/row key this timer was declared under
      7  color          colour index 1..7 (1 add, 2 AoE, 3 targeted, 4 interrupt,
                        5 role, 6 stage, 7 user)
      8  modId          owning module / encounter id
      9  keep           keep-on-screen flag
     10  fade           fade flag
     11  spellName      spell name when known
     12  guid           mob GUID when one could be parsed out of the identity
                        arguments, else nil
     13  count          numeric count for count timers, else nil
     14  priority       high-priority flag
     15  timerType      the FULL, unsimplified timer type (cd/next/cast/active/
                        fades/target/stage/intermission/adds/berserk/learning)
     16  hasVariance    true when this timer carries a variance window
     17  variancePeak   seconds left to the MAXIMUM end of that window (field 3 is
                        the minimum; these two are the window)
     18  enabled        whether the BAR IS BEING DRAWN for this user

    ---------------------------------------------------------------------------
    THE RULE THAT MAKES FIELD 18 MATTER
    ---------------------------------------------------------------------------
    §4.5: "The broadcast fires EVEN WHEN THE USER HAS THE OPTION DISABLED (with the
    enabled flag false), so third-party consumers see everything; the bar itself is
    only created when enabled."

    So the display option is OURS to suppress and THEIRS to observe. A raider who
    hides our bars because their WeakAura already shows the same cooldown must not
    also silence the WeakAura. Consumers that want to mirror the user's choice read
    field 18; consumers that want everything ignore it.

    A PARALLEL BROADCAST fires for nameplate-attached timers (§4.5), on the
    DRM_NameplateTimer* events, carrying the identical payload — nameplate addons
    subscribe to those alone rather than filtering every timer in the fight.
--]]

local _, Addon = ...

local Public = {}
Addon.Callbacks = Public
Public.__index = Public

-- The published event vocabulary (§11.8). Anything not on this list is internal.
Public.EVENTS = {
    "DRM_TimerStart", "DRM_TimerUpdate", "DRM_TimerStop",
    "DRM_TimerPause", "DRM_TimerResume",
    "DRM_NameplateTimerStart", "DRM_NameplateTimerUpdate", "DRM_NameplateTimerStop",
    "DRM_Announce", "DRM_SpecialWarning",
    "DRM_SetStage", "DRM_Pull", "DRM_Kill", "DRM_Wipe", "DRM_ZoneChanged",
}

-- Field order is the contract. Consumers may index the payload by name OR read the
-- positional arguments; this table is what guarantees the two agree forever.
Public.TIMER_FIELDS = {
    "barId", "text", "remaining", "icon", "category", "spellKey", "color", "modId",
    "keep", "fade", "spellName", "guid", "count", "priority", "timerType",
    "hasVariance", "variancePeak", "enabled",
}
Public.TIMER_FIELD_COUNT = 18

local KNOWN = {}
for _, e in ipairs(Public.EVENTS) do KNOWN[e] = true end

Public.registry = {}          -- event -> ordered { fn = , owner = }

function Public:Register(event, fn, owner)
    if type(fn) ~= "function" then return false, "handler must be a function" end
    if not KNOWN[event] then return false, "unknown event '" .. tostring(event) .. "'" end
    local list = Public.registry[event]
    if not list then list = {}; Public.registry[event] = list end
    for i = 1, #list do if list[i].fn == fn then return true end end   -- idempotent
    list[#list + 1] = { fn = fn, owner = owner }
    return true
end

function Public:Unregister(event, fn)
    local list = Public.registry[event]
    if not list then return 0 end
    local n = 0
    for i = #list, 1, -1 do
        if list[i].fn == fn then table.remove(list, i); n = n + 1 end
    end
    return n
end

function Public:IsRegistered(event, fn)
    for _, e in ipairs(Public.registry[event] or {}) do if e.fn == fn then return true end end
    return false
end

-- §11.8: "Callbacks are invoked through a SECURE-CALL WRAPPER so a misbehaving
-- consumer cannot break the engine."
function Public.Fire(event, ...)
    local list = Public.registry[event]
    if not list then return 0 end
    local fired = 0
    for i = 1, #list do
        local okc, err = pcall(list[i].fn, event, ...)
        if okc then
            fired = fired + 1
        elseif Addon.Telemetry then
            Addon.Telemetry.Write("api.validate",
                { reason = "public callback error", key = event, detail = tostring(err) })
        end
    end
    return fired
end

-- ══════════════════════════════════════════════════════════════════════════════
--  PAYLOAD CONSTRUCTION
-- ══════════════════════════════════════════════════════════════════════════════
-- §4.5 GUID association: "if any start argument parses as a NON-PLAYER GUID it
-- becomes the bar's mob GUID." Identity arguments are tab-joined into the bar id,
-- so that is where they are recovered from.
function Public.GuidFromBarId(barId)
    if type(barId) ~= "string" then return nil end
    for part in barId:gmatch("[^\t]+") do
        local kind = part:match("^(%a+)%-")
        if kind == "Creature" or kind == "Vehicle" or kind == "Pet" then return part end
    end
    return nil
end

local function remainingMin(bar, now)
    if bar.paused then return bar.minEndsAt - bar.pausedAt end
    return bar.minEndsAt - now
end

local function remainingMax(bar, now)
    if bar.paused then return bar.endsAt - bar.pausedAt end
    return bar.endsAt - now
end

-- Build the payload. Returns the named table AND the 18 positional values, so both
-- documented consumption styles come from one place and cannot drift apart.
function Public.TimerPayload(bar, now)
    now = now or (Addon.Sched and Addon.Sched:Now()) or 0
    local objs = Addon.Timers and Addon.Timers.objects
    local timer = objs and objs[bar.timerId]
    local Model = Addon.Bars and Addon.Bars.Model

    local count    = Model and Model.CountOf(bar) or nil
    local row      = Model and Model.rows and Model.rows[bar.id]
    local text     = row and Model.DisplayText(row) or (bar.text or bar.key or bar.timerId)
    -- Field 18 is the DISPLAY decision, and only the display decision. Written out
    -- rather than as `Model and X or true`, because that idiom collapses a genuine
    -- `false` back to `true` — which is exactly the value this field exists to carry.
    local enabled = true
    if Model then enabled = Model.IsDisplayEnabled(bar) end

    local p = {
        barId        = bar.id,
        text         = text,
        remaining    = remainingMin(bar, now),
        icon         = bar.icon,
        category     = bar.category,
        spellKey     = bar.key,
        color        = bar.color or (Model and Model.ClassOf(bar)) or nil,
        modId        = bar.encId or (timer and timer.owner and timer.owner.id) or nil,
        keep         = bar.keep and true or false,
        fade         = bar.fade and true or false,
        spellName    = bar.spellName or (timer and timer.spellName) or nil,
        guid         = Public.GuidFromBarId(bar.id),
        count        = count,
        priority     = bar.priority and true or false,
        timerType    = timer and timer.kind or nil,
        hasVariance  = bar.hasVariance and true or false,
        variancePeak = remainingMax(bar, now),
        enabled      = enabled and true or false,
    }
    return p, p.barId, p.text, p.remaining, p.icon, p.category, p.spellKey, p.color,
           p.modId, p.keep, p.fade, p.spellName, p.guid, p.count, p.priority,
           p.timerType, p.hasVariance, p.variancePeak, p.enabled
end

-- ══════════════════════════════════════════════════════════════════════════════
--  ENGINE SEAM — every broadcast originates here and nowhere else
-- ══════════════════════════════════════════════════════════════════════════════
local NAMEPLATE_EVENT = {
    DRM_TimerStart  = "DRM_NameplateTimerStart",
    DRM_TimerUpdate = "DRM_NameplateTimerUpdate",
    DRM_TimerStop   = "DRM_NameplateTimerStop",
}

local function broadcastTimer(event, bar)
    local p, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10,
          a11, a12, a13, a14, a15, a16, a17, a18 = Public.TimerPayload(bar)
    Public.Fire(event, p, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10,
                a11, a12, a13, a14, a15, a16, a17, a18)
    -- §4.5: "A PARALLEL BROADCAST fires for nameplate-attached timers."
    local np = NAMEPLATE_EVENT[event]
    if np and bar.nameplate then
        Public.Fire(np, p, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10,
                    a11, a12, a13, a14, a15, a16, a17, a18)
    end
    return p
end
Public.BroadcastTimer = broadcastTimer

function Public.Init()
    if Public._inited then return end
    Public._inited = true

    Addon:RegisterEngineCallback("TIMER_START",  function(_, bar) broadcastTimer("DRM_TimerStart",  bar) end, Public)
    Addon:RegisterEngineCallback("TIMER_UPDATE", function(_, bar) broadcastTimer("DRM_TimerUpdate", bar) end, Public)
    Addon:RegisterEngineCallback("TIMER_PAUSE",  function(_, bar) broadcastTimer("DRM_TimerPause",  bar) end, Public)
    Addon:RegisterEngineCallback("TIMER_RESUME", function(_, bar) broadcastTimer("DRM_TimerResume", bar) end, Public)

    -- A stop carries no live bar, so it broadcasts the identity only. Consumers key
    -- their displays on barId, which is exactly what they get back.
    Addon:RegisterEngineCallback("TIMER_STOP", function(_, barId, timerId, reason)
        Public.Fire("DRM_TimerStop", { barId = barId, timerId = timerId, reason = reason },
                    barId, timerId, reason)
        Public.Fire("DRM_NameplateTimerStop", { barId = barId, timerId = timerId, reason = reason },
                    barId, timerId, reason)
    end, Public)

    Addon:RegisterEngineCallback("WARN_ANNOUNCE", function(_, encId, row, text)
        row = row or {}
        Public.Fire("DRM_Announce",
            { text = text, modId = encId, spellKey = row.key, color = row.color,
              spellId = row.spellId, count = row.count, special = false },
            text, row.color, row.spellId, encId, false, row.count)
    end, Public)

    Addon:RegisterEngineCallback("WARN_SPECIAL", function(_, encId, row, text)
        row = row or {}
        Public.Fire("DRM_SpecialWarning",
            { text = text, modId = encId, spellKey = row.key, sound = row.sound,
              spellId = row.spellId, count = row.count, special = true },
            text, row.sound, row.spellId, encId, true, row.count)
    end, Public)

    -- §11.8's lifecycle half of the surface: stage changed, pull / kill / wipe,
    -- zone updated. These are what a WeakAura keys "show only in phase 2" on.
    Addon:RegisterEngineCallback("ENGINE_STAGE", function(_, encId, stage, totality)
        Public.Fire("DRM_SetStage", { modId = encId, stage = stage, totality = totality },
                    encId, stage, totality)
    end, Public)

    Addon:RegisterEngineCallback("ENGINE_ENGAGE", function(_, encId, rt, delay, trigger)
        Public.Fire("DRM_Pull", { modId = encId, delay = delay, trigger = trigger,
                                  startHp = rt and rt.engagedAtPct },
                    encId, delay, trigger, rt and rt.engagedAtPct)
    end, Public)

    Addon:RegisterEngineCallback("ENGINE_END", function(_, encId, rt, wiped, duration, hp)
        local ev = wiped and "DRM_Wipe" or "DRM_Kill"
        Public.Fire(ev, { modId = encId, duration = duration, bossHp = hp, wiped = wiped },
                    encId, duration, hp)
    end, Public)

    Addon:RegisterEngineCallback("ENGINE_ZONE", function()
        Public.Fire("DRM_ZoneChanged", {})
    end, Public)

    return true
end

return Public
