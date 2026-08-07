--[[
    Daseeki Raid Mechanics 2.0 — ERA SERVICES (engine services, wave 2)

    ENGINE SPEC §6.1 the item-range ladder and the 43-yard clamp, §6.3 map
    restrictions, §6.4 the distance filters, §8.6 boss health on Era, §5.4 the
    interrupt / dispel / crowd-control gates and the tank + healer role tests, and
    the Era gates in §10.2 / §10.4 / §10.23 that shape all of it.

    THIS IS THE "WHAT CAN THIS CLIENT ACTUALLY ANSWER" LAYER. Every function here
    exists because a modern API a boss mod would reach for does not exist on Classic
    Era, and the replacement is a measurement rather than a query:

      RANGE      There is no distance function inside Era instances (§6.3), so range
                 is a LADDER of items whose usable range is known, probed with
                 IsItemInRange. Six rungs plus a binary 43-yard test, and a request
                 above 43 is silently clamped rather than failing.
      HEALTH     Boss unit tokens do not populate (§10.2), so boss health is resolved
                 by sweep — cached token, then target, then every group member's
                 target, then nameplate1..20 — and a unit that reports 0 health while
                 not actually dead is a real client quirk, so the LAST NON-ZERO value
                 is retained rather than believed.
      GATES      There is no specialization API (§10.23), so "am I a tank" is a
                 talent-tab count crossed with a stance/form check, and "can I
                 interrupt this" is a spellbook-and-cooldown question over a fixed
                 Era spell set, cached for 0.1 s so a burst of simultaneous debuff
                 applications does not re-derive it forty times.

    IT ALSO FILLS THE TWO WAVE-1 STUBS. core_api.lua declares
    `Addon.RoleResolver` / `Addon.ClassResolver` as nil with the comment "W2 supplies
    the live role/class resolvers"; API.RowDefault calls them to decide whether a
    role-gated or class-gated row ships on. They are installed at the bottom of this
    file, which is why role and class filtering is genuinely resolved ENGINE-SIDE
    before any warning reaches the presentation layer.

    HEADLESS DISCIPLINE: one injectable `Era.env`, one injectable clock (the engine
    scheduler), no globals read directly. Every gate is a pure decision over that
    environment, so the whole matrix is assertable row by row.
--]]

local _, Addon = ...

local Era = {}
Addon.Era = Era

local function S() return Addon.Sched end

-- ══════════════════════════════════════════════════════════════════════════════
--  §6.1 THE ERA ITEM-RANGE LADDER
-- ══════════════════════════════════════════════════════════════════════════════
-- "Era's usable item ladder (Classic-safe items only)." The yard values are the
-- EMPIRICALLY CORRECTED ranges, not the tooltip ranges — §6.1 is explicit that a
-- "6-yard" item does not report false until ~8 yards, so it is filed as 8.
Era.RANGE_LADDER = {
    { yards = 8,  item = 8149  },   -- Voodoo Charm
    { yards = 13, item = 17626 },   -- Sparrowhawk Net   (§10.12: 32321 elsewhere)
    { yards = 18, item = 6450  },   -- Silk Bandage
    { yards = 23, item = 21519 },   -- Mistletoe
    { yards = 28, item = 13289 },   -- Egan's Blaster
    { yards = 33, item = 1180  },   -- Scroll of Stamina
}
-- "43 yd — UnitInRange (boolean only — no item)". This is the ceiling of what Era
-- can measure at all: the 48 / 60 / 80 / 100 yard rungs need TBC+ items.
Era.BINARY_RANGE = 43
-- §6.1: "the range picker in the UI offers only 8/13/18/23/33 on Era (the 6 and 43
-- entries are non-Era)." 28 is a real rung but is not offered in the picker.
Era.PICKER_RUNGS = { 8, 13, 18, 23, 33 }
Era.NEARBY_TOLERANCE = 0.5      -- §6.4 "the latter with a +0.5 yd tolerance"
Era.TANK_CACHE_TTL   = 2        -- §12 "distance filter cache: 2 s (tank distance)"
Era.GATE_CACHE_TTL   = 0.1      -- §12 "0.1 s (dispel/CC)"

-- Resolve a requested distance to the rung that actually answers it. Returns
-- (yards, itemId) — a nil itemId means the binary 43-yard UnitInRange test.
--
-- §6.1: "A module asking for a range ABOVE 43 on Era is SILENTLY CLAMPED to 43."
-- Silently is the operative word: erroring would take a working warning off the
-- screen because a data file was written against a client that has an 80-yard item.
function Era.RungFor(yards)
    yards = tonumber(yards) or Era.BINARY_RANGE
    if yards > Era.BINARY_RANGE then return Era.BINARY_RANGE, nil end
    for i = 1, #Era.RANGE_LADDER do
        local r = Era.RANGE_LADDER[i]
        if yards <= r.yards then return r.yards, r.item end
    end
    return Era.BINARY_RANGE, nil
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §5.4 THE ERA SPELL SETS
-- ══════════════════════════════════════════════════════════════════════════════
-- "the Era-relevant spell set is Shield Bash 72 / 1671 / 1672, Kick 1766 / 1767 /
-- 1768 / 1769, Counterspell 2139, Pummel 6552 / 6554, Silence 15487, Spell Lock
-- 19244 / 19647, Earth Shock 8042, Feral Charge 16979."
Era.INTERRUPTS = { 72, 1671, 1672, 1766, 1767, 1768, 1769, 2139,
                   6552, 6554, 15487, 19244, 19647, 8042, 16979 }

-- §5.4 dispels. The spell IDs are verbatim; the TYPE assignment is a plain game
-- fact about what each spell removes on Era (the spec names the spells, not their
-- schools). Note 527 is the priest dispel the reference options tree calls "Purify";
-- the ID is what matters and the ID is what is reproduced.
Era.DISPELS = {
    { id = 2782, class = "DRUID",   types = { curse = true } },
    { id = 475,  class = "MAGE",    types = { curse = true } },
    { id = 527,  class = "PRIEST",  types = { magic = true } },
    -- "Cleanse 4987 (paladin, MAGIC ONLY — poison/disease gated behind healer role).
    --  Cleanse and Nature's Cure are additionally REJECTED WHEN THE PLAYER IS NOT A
    --  HEALER."  Both rules are encoded, not merged: the spell is healer-only, and
    --  two of its three types are healer-only on top of that.
    { id = 4987, class = "PALADIN", types = { magic = true, poison = true, disease = true },
      healerOnly = true, healerOnlyTypes = { poison = true, disease = true } },
    -- Beyond §5.4's list, and marked as such: the enrage-removal role gate
    -- (API.ROLE_GATES.RemoveEnrage) is otherwise unanswerable on Era. Tranquilizing
    -- Shot is the only Era answer and is a game fact, not a reproduced decision.
    { id = 19801, class = "HUNTER", types = { enrage = true } },
}

-- §5.4: "Crowd-control filter. Same shape as dispel, keyed by CC CATEGORY
-- (disrupt/stun/knock/disorient/incapacitate/root/slow/sleep), same 0.1 s cache.
-- LARGELY EMPTY OF ERA SPELLS." The categories ship declared and empty so encounter
-- data can key on them and the gate answers honestly (false) until W4 fills one in.
Era.CC_CATEGORIES = {
    disrupt = {}, stun = {}, knock = {}, disorient = {},
    incapacitate = {}, root = {}, slow = {}, sleep = {},
}

-- §5.4: "'Move out of bad' warnings are suppressed for a priest in SPIRIT OF
-- REDEMPTION (27827), who can neither move nor take damage."
Era.SPIRIT_OF_REDEMPTION = 27827
-- §5.4 the Era tank test: "currently in Defensive Stance (FORM ID 18) or Bear/Dire
-- Bear Form (5487 / 9634)".
Era.DEFENSIVE_STANCE_FORM = 18
Era.BEAR_FORMS = { 5487, 9634 }
-- §5.4: "Content is 'trivial' when the player's level is >= 15 ABOVE the instance's
-- reference level (10 above on retail)."
Era.TRIVIAL_LEVEL_GAP = 15

-- ══════════════════════════════════════════════════════════════════════════════
--  INJECTABLE ENVIRONMENT
-- ══════════════════════════════════════════════════════════════════════════════
local function g(name)
    return function(...)
        local f = _G[name]
        if type(f) == "function" then return f(...) end
        return nil
    end
end

Era.env = {
    UnitExists        = g("UnitExists"),
    UnitGUID          = g("UnitGUID"),
    UnitName          = g("UnitName"),
    UnitClass         = g("UnitClass"),
    UnitLevel         = g("UnitLevel"),
    UnitHealth        = g("UnitHealth"),
    UnitHealthMax     = g("UnitHealthMax"),
    UnitIsDeadOrGhost = g("UnitIsDeadOrGhost"),
    UnitIsUnit        = g("UnitIsUnit"),
    UnitIsFriend      = g("UnitIsFriend"),
    UnitInRange       = g("UnitInRange"),
    UnitPosition      = g("UnitPosition"),
    UnitDistanceSquared = g("UnitDistanceSquared"),
    UnitDetailedThreatSituation = g("UnitDetailedThreatSituation"),
    IsItemInRange     = g("IsItemInRange"),
    IsSpellKnown      = g("IsSpellKnown"),
    GetSpellInfo      = g("GetSpellInfo"),
    GetSpellCooldown  = g("GetSpellCooldown"),
    GetShapeshiftFormID = g("GetShapeshiftFormID"),
    GetNumTalentTabs  = g("GetNumTalentTabs"),
    GetTalentTabInfo  = g("GetTalentTabInfo"),
    GetPartyAssignment = g("GetPartyAssignment"),
    IsInRaid          = g("IsInRaid"),
    GetNumGroupMembers = g("GetNumGroupMembers"),
}

-- Does the player currently have this aura? Era has no C_UnitAuras, so this walks
-- UnitBuff by index; injectable so the harness can answer directly.
function Era.env.PlayerHasAura(spellId)
    local f = _G.UnitBuff
    if type(f) ~= "function" then return false end
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, id = f("player", i)
        if not name then return false end
        if id == spellId then return true end
    end
    return false
end

function Era.env.ForEachGroupMember(fn)
    local L = Addon.Lifecycle
    if L and L.env and L.env.ForEachGroupMember then return L.env.ForEachGroupMember(fn) end
    return false
end

function Era:SetEnv(t)
    if type(t) ~= "table" then return end
    for k, v in pairs(t) do Era.env[k] = v end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  THE 0.1 s RESULT CACHE (§5.4 / §12)
-- ══════════════════════════════════════════════════════════════════════════════
-- "Results are cached for 0.1 s TO SURVIVE A BURST OF SIMULTANEOUS DEBUFF
-- APPLICATIONS." Twenty raiders getting the same debuff on the same frame must cost
-- one spellbook sweep, not twenty.
Era.cache = {}

function Era.Cached(key, ttl, produce)
    local now = S():Now()
    local e = Era.cache[key]
    if e and (now - e.at) < ttl then return e.v, true end
    local v = produce()
    Era.cache[key] = { at = now, v = v }
    return v, false
end

function Era.ClearCache()
    for k in pairs(Era.cache) do Era.cache[k] = nil end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  SPELLBOOK + COOLDOWN
-- ══════════════════════════════════════════════════════════════════════════════
function Era.Knows(spellId)
    local f = Era.env.IsSpellKnown
    if type(f) == "function" then
        local v = f(spellId)
        if v ~= nil then return v and true or false end
    end
    local name = Era.env.GetSpellInfo(spellId)
    return name ~= nil
end

-- "off cooldown": a duration at or under the global cooldown is not a real cooldown.
function Era.OffCooldown(spellId)
    local f = Era.env.GetSpellCooldown
    if type(f) ~= "function" then return true end
    local start, duration = f(spellId)
    if start == nil then return true end
    if start == 0 or duration == nil or duration <= 1.5 then return true end
    return (start + duration) <= S():Now()
end

function Era.KnowsReady(spellId)
    return Era.Knows(spellId) and Era.OffCooldown(spellId)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §10.23 ROLE DERIVATION (no specialization API on Era)
-- ══════════════════════════════════════════════════════════════════════════════
-- "With no specialization API, the 'spec' is the TALENT TAB WITH THE MOST POINTS
-- SPENT, identified as CLASS..tabIndex. ZERO POINTS SPENT falls back to tab 1."
Era.roleState = { tankLatched = false }

function Era.Class()
    local _, class = Era.env.UnitClass("player")
    return class
end

function Era.SpecTab()
    local n = Era.env.GetNumTalentTabs() or 0
    local best, bestPoints = 1, -1
    for i = 1, n do
        local _, _, _, _, points = Era.env.GetTalentTabInfo(i)
        points = points or 0
        if points > bestPoints then best, bestPoints = i, points end
    end
    if bestPoints <= 0 then return 1, 0 end
    return best, bestPoints
end

function Era.Spec()
    local class = Era.Class()
    if not class then return nil end
    return class .. tostring((Era.SpecTab()))
end

-- Which CLASS..tab combinations are the tank tree and the healer tree on Era.
-- Talent tab ORDER is a client fact, and getting it wrong is silent: these are
--   WARRIOR 1 Arms   2 Protection 3 Fury          PALADIN 1 Holy    2 Protection 3 Retribution
--   DRUID   1 Balance 2 Feral     3 Restoration   PRIEST  1 Discipline 2 Holy   3 Shadow
--   SHAMAN  1 Elemental 2 Enhancement 3 Restoration
Era.TANK_SPECS   = { WARRIOR2 = true, DRUID2 = true, PALADIN2 = true }
Era.HEALER_SPECS = { PRIEST1 = true, PRIEST2 = true, PALADIN1 = true,
                     DRUID3 = true, SHAMAN3 = true }
Era.MELEE_CLASSES = { WARRIOR = true, ROGUE = true, PALADIN = true,
                      DRUID = true, SHAMAN = true }
Era.MANA_CLASSES  = { PALADIN = true, PRIEST = true, SHAMAN = true, MAGE = true,
                      WARLOCK = true, DRUID = true, HUNTER = true }
Era.CASTER_CLASSES = { MAGE = true, WARLOCK = true, PRIEST = true,
                       DRUID = true, SHAMAN = true }
Era.RANGED_CLASSES = { HUNTER = true, MAGE = true, WARLOCK = true,
                       PRIEST = true, DRUID = true, SHAMAN = true }

function Era.InBearForm()
    for _, id in ipairs(Era.BEAR_FORMS) do
        if Era.env.PlayerHasAura(id) then return true end
    end
    return false
end

function Era.IsMainTankFlagged()
    local f = Era.env.GetPartyAssignment
    if type(f) ~= "function" then return false end
    return f("MAINTANK", "player") and true or false
end

-- §5.4: "On Era, 'am I a tank' is evaluated as: talent-tree role says tank AND
-- (currently in Defensive Stance (form ID 18) or Bear/Dire Bear Form (5487 / 9634)
-- or flagged Main Tank in the raid UI). ONCE TRUE IT LATCHES FOR THE SESSION."
--
-- The latch is what makes it usable: a warrior who taunts and then swaps to Battle
-- Stance for a burst window must not stop receiving tank warnings mid-fight.
function Era.IsTank()
    if Era.roleState.tankLatched then return true end
    if not Era.TANK_SPECS[Era.Spec() or ""] then return false end
    local form = Era.env.GetShapeshiftFormID()
    local stanced = (form == Era.DEFENSIVE_STANCE_FORM) or Era.InBearForm()
    if stanced or Era.IsMainTankFlagged() then
        Era.roleState.tankLatched = true
        return true
    end
    return false
end

-- §5.4: "'Am I a healer' on Era additionally requires a DRUID TO BE *OUT* OF FORM."
function Era.IsHealer()
    if not Era.HEALER_SPECS[Era.Spec() or ""] then return false end
    if Era.Class() == "DRUID" then
        local form = Era.env.GetShapeshiftFormID()
        if (form and form ~= 0) or Era.InBearForm() then return false end
    end
    return true
end

-- §10.23: "Re-derivation is THROTTLED: CHARACTER_POINTS_CHANGED schedules the check
-- 2 s out, CANCELLING ANY PENDING ONE, so a full respec doesn't fire it forty times."
Era.RESPEC_THROTTLE = 2

local function rederive()
    Era.roleState.tankLatched = false     -- a respec invalidates the session latch
    Era.ClearCache()
    Addon:FireEngineEvent("ROLE_CHANGED", Era.Spec(), Era.IsTank(), Era.IsHealer())
end
Era._rederive = rederive

function Era.OnTalentsChanged()
    S():DelayedCall(Era.RESPEC_THROTTLE, rederive, Era)
    return true
end

-- ── AUDIT RM-1 (SUITE_ASYNC_AUDIT Brief G, lesson Class 7) ────────────────────
-- A respec is not the only thing that changes the answer to "am I a tank". Being
-- PROMOTED TO MAIN TANK mid-raid changes it too — `IsMainTankFlagged` would now
-- answer true — but the event set above listened only for CHARACTER_POINTS_CHANGED,
-- so nothing ever asked again. Worse, `roleState.tankLatched` latches FOR THE
-- SESSION (§5.4, deliberately) and only `rederive` clears it: a warrior who tanked
-- one pull and was then DEMOTED stayed "tank" until /reload.
--
-- The fix is not to weaken the latch — the latch is the spec — it is to make the
-- latch RE-EARNED on roster churn instead of frozen. Clear it, ask again, and if
-- the player is still stanced/flagged it re-latches within the same call and
-- nothing was disturbed.
--
-- Roster events are BURSTY (a 40-man invite wave fires dozens), so this is
-- throttled like the respec path, and — unlike the respec path — it stays SILENT
-- when the derived answer did not actually move. A respec is always news; a raider
-- joining the group usually is not, and re-projecting the whole options tree on
-- every GROUP_ROSTER_UPDATE would be a boot-cost tax paid forty times a night.
Era.ROLE_RECHECK_THROTTLE = 1
Era.ROSTER_EVENTS = { "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED" }
Era.ROSTER_EVENT_SET = {}
for _, e in ipairs(Era.ROSTER_EVENTS) do Era.ROSTER_EVENT_SET[e] = true end

-- The derived role tuple, read THROUGH the latch as it currently stands.
local function roleSignature()
    return tostring(Era.Spec()) .. "/" .. tostring(Era.IsTank()) .. "/" .. tostring(Era.IsHealer())
end
Era._roleSignature = roleSignature

local function recheckRole()
    local before = roleSignature()          -- the answer the addon is currently giving
    Era.roleState.tankLatched = false       -- the latch must be re-EARNED, not frozen
    Era.ClearCache()
    local after = roleSignature()           -- re-latches inside this call if still true
    if after == before then return false end
    Addon:FireEngineEvent("ROLE_CHANGED", Era.Spec(), Era.IsTank(), Era.IsHealer())
    return true
end
Era._recheckRole = recheckRole

function Era.OnRosterChanged()
    S():DelayedCall(Era.ROLE_RECHECK_THROTTLE, recheckRole, Era)
    return true
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §5.4 THE INTERRUPT FILTER — four independent gates
-- ══════════════════════════════════════════════════════════════════════════════
function Era.Settings()
    local db = Addon.db
    if type(db) ~= "table" or type(db.settings) ~= "table" then return {} end
    local e = db.settings.era
    if type(e) ~= "table" then
        e = { interruptHealerFilterBoss = true, interruptHealerFilterTrash = true,
              filterFarWarnings = true }
        db.settings.era = e
    end
    return e
end

function Era.KnowsAnyInterrupt()
    return Era.Cached("interrupt:known", Era.GATE_CACHE_TTL, function()
        for _, id in ipairs(Era.INTERRUPTS) do if Era.Knows(id) then return true end end
        return false
    end)
end

-- Gate (ii): "drop unless the player KNOWS AND HAS OFF COOLDOWN at least one
-- interrupt". Cached like every other gate, because an AoE silence lands on twenty
-- casters in one frame.
function Era.HasReadyInterrupt()
    return Era.Cached("interrupt:ready", Era.GATE_CACHE_TTL, function()
        for _, id in ipairs(Era.INTERRUPTS) do if Era.KnowsReady(id) then return true end end
        return false
    end)
end

-- Returns allowed, reason. `ctx` = { casterUnit, trash, ignoreTargeting }.
function Era.InterruptFilter(ctx)
    ctx = ctx or {}
    local s = Era.Settings()
    -- (i) "drop if the player is a HEALER and the healer filter is on (SEPARATE
    --      OPTIONS FOR BOSS VS TRASH)"
    -- Written as an if, not `cond and a or b`: `a` here is a BOOLEAN OPTION that is
    -- legitimately false, and that idiom would silently fall through to `b`.
    local healerFilter
    if ctx.trash then healerFilter = s.interruptHealerFilterTrash
    else healerFilter = s.interruptHealerFilterBoss end
    if healerFilter and Era.IsHealer() then return false, "healer" end
    -- (ii) knows and has off cooldown at least one interrupt
    if not Era.HasReadyInterrupt() then return false, "no_interrupt" end
    -- (iv) "a caller may request 'IGNORE TARGETING' for raid-wide interrupts" —
    --      checked before (iii), because that is what ignoring means.
    if ctx.ignoreTargeting then return true end
    -- (iii) "drop unless the caster is the player's CURRENT TARGET (NO FOCUS UNIT
    --       EXISTS ON ERA, so the focus branch is skipped)"
    if ctx.casterUnit then
        local f = Era.env.UnitIsUnit
        if type(f) == "function" and not f("target", ctx.casterUnit) then
            return false, "not_targeted"
        end
    end
    return true
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §5.4 THE DISPEL FILTER
-- ══════════════════════════════════════════════════════════════════════════════
-- "Drops the warning unless the player KNOWS AND HAS OFF COOLDOWN a dispel of the
-- requested type." Returns allowed, spellId.
function Era.DispelFilterUncached(dispelType)
    local healer = Era.IsHealer()
    for _, d in ipairs(Era.DISPELS) do
        if d.types[dispelType] then
            local blocked = (d.healerOnly and not healer)
                         or (d.healerOnlyTypes and d.healerOnlyTypes[dispelType] and not healer)
            if not blocked and Era.KnowsReady(d.id) then return true, d.id end
        end
    end
    return false, nil
end

function Era.DispelFilter(dispelType)
    local v = Era.Cached("dispel:" .. tostring(dispelType), Era.GATE_CACHE_TTL, function()
        local ok, id = Era.DispelFilterUncached(dispelType)
        return { ok = ok, id = id }
    end)
    return v.ok, v.id
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §5.4 THE CROWD-CONTROL FILTER — same shape, same cache
-- ══════════════════════════════════════════════════════════════════════════════
function Era.CCFilterUncached(category)
    local set = Era.CC_CATEGORIES[category]
    if not set then return false, nil end
    for _, id in ipairs(set) do
        if Era.KnowsReady(id) then return true, id end
    end
    return false, nil
end

function Era.CCFilter(category)
    local v = Era.Cached("cc:" .. tostring(category), Era.GATE_CACHE_TTL, function()
        local ok, id = Era.CCFilterUncached(category)
        return { ok = ok, id = id }
    end)
    return v.ok, v.id
end

-- §5.4: taunt-type warnings are HARD-DROPPED for non-tanks, ALWAYS, NO OPTION.
function Era.TauntFilter()
    return Era.IsTank()
end

-- §5.4 Spirit of Redemption: a priest who can neither move nor take damage does not
-- need to be told to move out of anything.
function Era.MoveOutFilter()
    if Era.Class() == "PRIEST" and Era.env.PlayerHasAura(Era.SPIRIT_OF_REDEMPTION) then
        return false, "spirit_of_redemption"
    end
    return true
end

-- §5.4 trivial content. `refLevel` is the instance's reference level; with no
-- reference level available nothing is trivial, which is the safe answer.
function Era.IsTrivial(refLevel)
    if not refLevel then return false end
    local lvl = Era.env.UnitLevel("player") or 0
    return (lvl - refLevel) >= Era.TRIVIAL_LEVEL_GAP
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §6.3 MAP RESTRICTIONS / §6.4 DISTANCE FILTERS
-- ══════════════════════════════════════════════════════════════════════════════
-- §6.3: the engine derives ONE boolean — "world position is unavailable" — by
-- testing whether UnitPosition("player") returns coordinates, and re-evaluates it on
-- every zone change. When restricted, ALL distance queries degrade to the binary
-- 43-yard test. "A rebuild MUST derive this dynamically and MUST NOT ASSUME precise
-- distances are available inside Era instances."
Era.worldPositionAvailable = nil

function Era.EvaluateWorldPosition()
    local x, y = Era.env.UnitPosition("player")
    Era.worldPositionAvailable = (x ~= nil and y ~= nil) and true or false
    return Era.worldPositionAvailable
end

function Era.WorldPositionAvailable()
    if Era.worldPositionAvailable == nil then return Era.EvaluateWorldPosition() end
    return Era.worldPositionAvailable
end

-- Is `unit` within `yards`? Returns true / false / nil (unanswerable).
function Era.CheckRange(unit, yards)
    if not Era.env.UnitExists(unit) then return nil end
    local rung, item = Era.RungFor(yards)
    if not item then
        local v = Era.env.UnitInRange(unit)
        if v == nil then return nil end
        return v and true or false, rung
    end
    -- §6.4: "the item API only works on hostiles" is stated for the boss-distance
    -- filter; for friendly units IsItemInRange still answers on Era, and when it
    -- does not it returns nil, which is propagated rather than guessed at.
    local v = Era.env.IsItemInRange(item, unit)
    if v == nil then return nil, rung end
    return (v and v ~= 0) and true or false, rung
end

-- §6.1: "The engine has TWO distance mechanisms: UnitDistanceSquared — exact, but
-- ONLY USABLE WHERE THE CLIENT EXPOSES WORLD POSITION — and item-range probing."
-- So the exact path is tried first and is gated on §6.3's world-position boolean.
function Era.ExactDistance(unit)
    if not Era.WorldPositionAvailable() then return nil end
    local d2 = Era.env.UnitDistanceSquared(unit)
    if type(d2) ~= "number" then return nil end
    return math.sqrt(d2)
end

-- §6.4 "is player X within N yards", with the stated +0.5 yd tolerance.
--
-- The tolerance is only MEANINGFUL on the exact path: the item ladder's rungs are
-- five or more yards apart, so half a yard cannot change which rung answers, and
-- adding it before picking a rung would silently promote a 13-yard question to the
-- 18-yard item. So it is applied where it means something and skipped where it
-- would do harm. The second return value says which mechanism answered.
function Era.IsPlayerWithin(unit, yards)
    yards = tonumber(yards) or 0
    local exact = Era.ExactDistance(unit)
    if exact then return exact <= (yards + Era.NEARBY_TOLERANCE), "exact" end
    return Era.CheckRange(unit, yards)
end

-- §6.4 "is anyone within N yards of me" (via the all-members distance sweep).
function Era.AnyoneWithin(yards, excludeSelf)
    local count = 0
    Era.env.ForEachGroupMember(function(u)
        if excludeSelf ~= false and Era.env.UnitIsUnit and Era.env.UnitIsUnit("player", u) then
            return false
        end
        if Era.env.UnitIsDeadOrGhost(u) then return false end
        if Era.CheckRange(u, yards) then count = count + 1 end
        return false
    end)
    return count
end

-- §6.4 tank distance: "finds who is actually tanking the mob by walking group
-- members and testing UnitDetailedThreatSituation(member, mob) for `tanking` or
-- status 3; falls back to whoever the mob is looking at. If that resolves to the
-- PLAYER, pass. If it resolves to an NPC, use UnitInRange (43 yd). Results cached
-- for 2 s per mob. The DEFAULT ON TOTAL FAILURE IS 'ALLOW THE WARNING'."
function Era.TankDistance(mobUnit)
    if not mobUnit then return true, "no_mob" end
    local v = Era.Cached("tankdist:" .. tostring(mobUnit), Era.TANK_CACHE_TTL, function()
        local tankUnit
        Era.env.ForEachGroupMember(function(u)
            local isTanking, status = Era.env.UnitDetailedThreatSituation(u, mobUnit)
            if isTanking or status == 3 then tankUnit = u; return true end
            return false
        end)
        if not tankUnit then
            local t = mobUnit .. "target"
            if Era.env.UnitExists(t) then tankUnit = t end
        end
        if not tankUnit then return { ok = true, why = "unresolved" } end
        if Era.env.UnitIsUnit and Era.env.UnitIsUnit("player", tankUnit) then
            return { ok = true, why = "player_is_tank" }
        end
        local inRange = Era.env.UnitInRange(tankUnit)
        if inRange == nil then return { ok = true, why = "no_answer" } end
        return { ok = inRange and true or false, why = "unit_in_range" }
    end)
    return v.ok, v.why
end

-- §6.4 boss-distance filter: "probes IsItemInRange with a caller-supplied item
-- (default 32698, A NON-ERA ITEM — so on Era this call *fails* and falls through).
-- On failure, or when the unit is friendly, it falls back to a TANK-DISTANCE check."
--
-- The default item being non-Era is not an oversight to correct: it is the reason
-- the tank-distance fallback is the path that actually runs on this client, and a
-- rebuild that "fixed" the default would quietly change which rule applies.
Era.NON_ERA_DEFAULT_ITEM = 32698

function Era.BossDistanceFilter(mobUnit, itemId)
    if not Era.Settings().filterFarWarnings then return true, "filter_off" end
    itemId = itemId or Era.NON_ERA_DEFAULT_ITEM
    if mobUnit and Era.env.UnitExists(mobUnit) and not Era.env.UnitIsFriend("player", mobUnit) then
        local v = Era.env.IsItemInRange(itemId, mobUnit)
        if v ~= nil then return (v and v ~= 0) and true or false, "item" end
    end
    return Era.TankDistance(mobUnit)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  §8.6 BOSS HEALTH ON ERA — nameplate fallback + last-non-zero retention
-- ══════════════════════════════════════════════════════════════════════════════
-- Resolution order, verbatim from §8.6 with the Era skips applied: cached unit token
-- for that creature ID -> target -> (focus branch skipped) -> (boss1-10 branch
-- skipped) -> every group member's target -> nameplate1..20. The successful token is
-- cached per creature ID.
Era.NAMEPLATE_SWEEP = 20
Era.healthCache = {}       -- creatureId -> { pct = lowest/highest seen, last = last NON-ZERO }
Era.healthToken = {}       -- creatureId -> unit token

function Era.UnitHealthPct(unit)
    local hp, mx = Era.env.UnitHealth(unit), Era.env.UnitHealthMax(unit)
    if not hp or not mx or mx == 0 then return nil end
    return hp / mx * 100
end

local function creatureIdOf(unit)
    local L = Addon.Lifecycle
    if not L then return nil end
    return L.CreatureIdFromGUID(Era.env.UnitGUID(unit))
end

-- Read one unit as a candidate for `want`. Returns the pct to use, or nil.
--
-- THE QUIRK: §8.6 — the cache "RETURNS THE LAST NON-ZERO VALUE WHEN THE UNIT REPORTS
-- 0 HEALTH BUT IS NOT ACTUALLY DEAD — a real Classic API quirk." Believing the zero
-- would report a boss at 0 % mid-fight and, worse, hand the wipe report a lie.
local function probe(unit, want)
    if not Era.env.UnitExists(unit) then return nil end
    local cid = creatureIdOf(unit)
    if not cid or not want[cid] then return nil end
    local pct = Era.UnitHealthPct(unit)
    if pct and pct > 0 then
        Era.healthToken[cid] = unit
        local e = Era.healthCache[cid]
        if not e then e = {}; Era.healthCache[cid] = e end
        e.last = pct
        return pct, cid
    end
    if pct == 0 and not Era.env.UnitIsDeadOrGhost(unit) then
        local e = Era.healthCache[cid]
        if e and e.last then return e.last, cid end
    end
    return nil
end

function Era.BossHealthPct(creatureIds, opts)
    opts = opts or {}
    -- AUDIT RME-1 (Brief G, lesson Class 8). `want` is a SET — membership only —
    -- and the cached-token pass used to walk it with pairs(). On a multi-creature
    -- encounter with several ids cached and alive (Four Horsemen is the case that
    -- proves it), *which* boss's health got reported and RECORDED changed from call
    -- to call. `order` keeps the caller's DECLARED sequence, which is the encounter
    -- definition's creatureIds array, so "the first creature the encounter names
    -- that is cached and alive" is a stated rule rather than a hash accident.
    local want, order = {}, {}
    if type(creatureIds) == "table" then
        for _, cid in ipairs(creatureIds) do
            if want[cid] == nil then want[cid] = true; order[#order + 1] = cid end
        end
    elseif creatureIds then
        want[creatureIds] = true; order[1] = creatureIds
    end

    -- 1. the cached token for each wanted creature id, re-validated first, in the
    --    encounter's declared order (AUDIT RME-1)
    for _, cid in ipairs(order) do
        local tok = Era.healthToken[cid]
        if tok then
            local pct = probe(tok, want)
            if pct then return Era.Record(cid, pct, opts), cid, tok end
            Era.healthToken[cid] = nil
        end
    end
    -- 2. target
    local pct, cid = probe("target", want)
    if pct then return Era.Record(cid, pct, opts), cid, "target" end
    -- 3. every group member's target
    local found, foundCid, foundTok
    Era.env.ForEachGroupMember(function(u)
        local p, c = probe(u .. "target", want)
        if p then found, foundCid, foundTok = p, c, u .. "target"; return true end
        return false
    end)
    if found then return Era.Record(foundCid, found, opts), foundCid, foundTok end
    -- 4. nameplate1..20 — the sweep NO OTHER CLIENT VERSION PERFORMS (§10.2)
    for i = 1, Era.NAMEPLATE_SWEEP do
        local u = "nameplate" .. i
        local p, c = probe(u, want)
        if p then return Era.Record(c, p, opts), c, u end
    end
    return nil
end

-- §8.6: "The cache keeps the LOWEST value seen (or the HIGHEST, if the module
-- declared 'report the highest-health boss', used for COUNCIL FIGHTS)."
function Era.Record(cid, pct, opts)
    if not cid then return pct end
    local e = Era.healthCache[cid]
    if not e then e = {}; Era.healthCache[cid] = e end
    e.last = pct
    if e.pct == nil then e.pct = pct
    elseif opts and opts.highest then if pct > e.pct then e.pct = pct end
    elseif pct < e.pct then e.pct = pct end
    return e.pct
end

function Era.LastNonZero(cid)
    local e = Era.healthCache[cid]
    return e and e.last or nil
end

function Era.ResetHealth()
    for k in pairs(Era.healthCache) do Era.healthCache[k] = nil end
    for k in pairs(Era.healthToken) do Era.healthToken[k] = nil end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  THE WAVE-1 RESOLVER STUBS, FILLED
-- ══════════════════════════════════════════════════════════════════════════════
-- core_api.lua: "Addon.RoleResolver = nil -- function(gateString) -> boolean" and
-- "Addon.ClassResolver = nil -- function() -> 'WARLOCK' etc." with the note "W2
-- supplies the live role/class resolvers". API.RowDefault calls these to decide
-- whether a role-gated or class-gated row SHIPS ON, which is what makes role
-- filtering an engine decision rather than a presentation one.
--
-- Compound gates use `|` as OR, per API.ROLE_GATES, and a leading `-` is a negation
-- ("-Melee", "-Healer").
local GATE = {}

GATE.Tank   = function() return Era.IsTank() end
GATE.Healer = function() return Era.IsHealer() end
GATE.Dps    = function() return not Era.IsTank() and not Era.IsHealer() end
GATE.Melee  = function()
    if Era.IsHealer() then return false end
    return Era.MELEE_CLASSES[Era.Class() or ""] and true or false
end
GATE.RangedDps = function()
    if Era.IsTank() or Era.IsHealer() then return false end
    return Era.RANGED_CLASSES[Era.Class() or ""] and true or false
end
GATE.CasterDps = function()
    if Era.IsTank() or Era.IsHealer() then return false end
    return Era.CASTER_CLASSES[Era.Class() or ""] and true or false
end
GATE.SpellCaster = function() return Era.CASTER_CLASSES[Era.Class() or ""] and true or false end
GATE.ManaUser    = function() return Era.MANA_CLASSES[Era.Class() or ""] and true or false end
GATE.HasInterrupt = function() return Era.KnowsAnyInterrupt() and true or false end
GATE.RemoveCurse   = function() return (Era.DispelFilter("curse")) and true or false end
GATE.RemoveMagic   = function() return (Era.DispelFilter("magic")) and true or false end
GATE.RemovePoison  = function() return (Era.DispelFilter("poison")) and true or false end
GATE.RemoveEnrage  = function() return (Era.DispelFilter("enrage")) and true or false end
GATE.MagicDispeller = GATE.RemoveMagic
GATE["-Melee"]  = function() return not GATE.Melee() end
GATE["-Healer"] = function() return not Era.IsHealer() end

Era.GATE = GATE

function Era.ResolveRole(gateString)
    if type(gateString) ~= "string" then return true end
    for tok in gateString:gmatch("[^|]+") do
        tok = tok:gsub("^%s+", ""):gsub("%s+$", "")
        local f = GATE[tok]
        if f and f() then return true end
    end
    return false
end

function Era.Init()
    if Era._inited then return end
    Era._inited = true
    Addon.RoleResolver  = Era.ResolveRole
    Addon.ClassResolver = Era.Class
    Era.EvaluateWorldPosition()

    if type(_G.CreateFrame) == "function" then
        local f = _G.CreateFrame("Frame")
        f:RegisterEvent("CHARACTER_POINTS_CHANGED")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        -- AUDIT RM-1: the two events that can change the Main-Tank answer without
        -- touching a talent point. PLAYER_ROLES_ASSIGNED does not exist on Era —
        -- registering it is a no-op there and correct on any client that has it —
        -- so GROUP_ROSTER_UPDATE is the one that actually carries the signal for us.
        for _, e in ipairs(Era.ROSTER_EVENTS) do pcall(f.RegisterEvent, f, e) end
        f:SetScript("OnEvent", function(_, event)
            if event == "CHARACTER_POINTS_CHANGED" then
                Era.OnTalentsChanged()
            elseif Era.ROSTER_EVENT_SET[event] then
                Era.OnRosterChanged()
            else
                -- §6.3: re-evaluated on every zone change and every loading screen.
                Era.EvaluateWorldPosition()
            end
        end)
        Era.frame = f
    end
    -- Health is fight-scoped: a cached boss token from the last pull is a lie.
    Addon:RegisterEngineCallback("ENGINE_END", function() Era.ResetHealth() end, Era)
    return true
end

return Era
