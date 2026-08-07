--[[
    Daseeki Raid Mechanics 2.0 — encounter-mod API + engine dispatch seam
    (engine core, wave 1)

    Design doc, target-architecture item 8: "Encounter-mod API: declarative tables
    (the ClassHUD displays-registry lesson: sources/conditions/presentation as data),
    with an escape hatch to registered special modules (the Naxx five)."

    TWO HALVES:

    A. THE OUTBOUND DISPATCH SEAM (`Addon:FireEngineEvent`). ENGINE SPEC §11.8 —
       the external callback surface is "more load-bearing than it looks". Every
       engine decision leaves through it. W2 hangs presentation off it, W3 hangs
       sync off it, the harness hangs a recorder off it. Callbacks run inside a
       pcall so a misbehaving consumer cannot break the engine.

    B. THE DECLARATIVE ENCOUNTER GRAMMAR (`Addon:RegisterEncounter`). Data in,
       engine services out. The grammar is sized against DBM_ERA_ENCOUNTERS_
       BEHAVIOR_SPEC.md so that NO encounter in that document is inexpressible:
         variance + pull-vs-cd + per-stage + alternating-sequence + hard-coded-cycle
         timer values;  phase machinery incl. half-stages, stage totality, health
         thresholds and the "encounter in progress" poll;  target-scan declarations
         in all three scanner shapes;  emote state machines;  stack / census /
         rate counters;  ship-off defaults, role gates and dynamic class defaults;
         and a REGISTERED-SPECIAL-MODULE ESCAPE HATCH for everything that refuses
         to be data.

    W4d GRAMMAR EXTENSIONS (Naxxramas wave). Porting the encounters spec's Naxx
    section found eleven behaviours the shipped grammar could not express. Each
    extension below is GENERAL — a primitive any zone can use — never a shape cut to
    fit one boss. They are listed here because a reader of an encounter file needs to
    know the vocabulary exists:

      1. DEFERRED ACTS.  `delay` on a trigger (or a row) schedules the act instead of
         running it, and `cancel` triggers unschedule a row's pending acts. This is
         the spec's ubiquitous "scheduled N s after X" pre-warning, and its equally
         ubiquitous "cancelled if the boss dies / the aura fades early".
      2. TRIGGER FILTERS.  `fromKey`, `index`, `where`, `states`, `counter`,
         `spellName`, `condition` / `conditionNot`, `dedupe`.
      3. PER-TRIGGER DURATION.  `duration` on a trigger overrides the row's resolved
         value for that path (one bar, many cadences: Noth's curse).
      4. LIST TRIGGER FORMS.  `starts` / `restarts` / `stops` on a timer row, because
         one bar routinely has more than three ways in.
      5. SCHEDULE ROWS grew `pre` (a pre-tick N s before each tick, cycling per tick),
         `count` (stop after N ticks) and `gaps.repeatFrom` (an alternating tail).
      6. SYNTHETIC ROUTING.  Stage and state transitions are now ROUTED as events
         (`on = "stage"` / `on = "state"`), which the vocabulary already promised.
      7. TARGET INTERPOLATION.  `%s` in a warning's text is filled with the event's
         target, and the target rides along to the batchers.
      8. LEGACY COUNT MIRROR.  Row counts are published into `Addon._mechCount` under
         the row's option key — the contract the shipped Four Horsemen tracker reads.
      9. OPTIONS PROJECTION.  `Addon:RegisterZone` + `API.PublishOptionsTree` build the
         raid / boss / mechanic tree options.lua consumes out of the ENCOUNTER
         REGISTRY, replacing the 1.x `RegisterRaid` data model (still refused).
     10. CONDITIONS REGISTRY.  `API.Conditions` — named predicates a trigger names,
         so "you are the boss's current tank" is data, not code.
     11. (core_lifecycle) the nameplate path, combat-log pet flags and zone-armed
         trash modules; (core_sched) `gaps.repeatFrom`; (svc_scan) `reportLoss`.

    W4C GRAMMAR EXTENSIONS (Ruins + Temple of Ahn'Qiraj wave). Seven more, same
    discipline: every one is a PRIMITIVE, not a boss-shaped hole.

     12. ROSTERS.  `rosters = { … }` — a live membership SET with a per-member stack
         count, driven by ordinary triggers (`add` / `remove` / `clear`). "Who
         currently carries debuff X, and at what stack" was code in every mod that
         needed it; here it is data. C'Thun's stomach list is the design case; the
         four Vanilla tank-swap fights (Kurinnaxx, Buru, Fankriss, Huhuran) use the
         same primitive to answer "is anyone ELSE at 5 stacks while I am clean".
         Membership changes are published (`ROSTER`) and re-enter as an ordinary
         `on = "roster"` trigger.
     13. ROSTER-RELAYED SCAN.  `scans[].type = "roster"` (serviced in svc_scan) —
         sample a creature you cannot see yourself THROUGH the targets of a roster's
         members, hold each GUID's health, and report it as an ordinary `on = "probe"`
         trigger. C'Thun's Flesh Tentacles are only visible to players inside the
         stomach; the general fact is "an ally's target is a unit token you do not
         otherwise have".
     14. RATE COUNTERS.  `rate = { window =, fallback = }` on a counter row. Wave 1's
         header promised rate counters and the field was inert; Viscidus (frost hits
         per second while thawed, melee hits per second while frozen) is what it was
         promised FOR, so it now computes. `rt:Rate(key)`.
     15. CONDITION LISTS.  `condition` / `conditionNot` accept a LIST of named
         predicates, all of which must pass. "Someone else is at 5 stacks AND you are
         clean AND you are alive" is three facts, not one, and inventing a fused
         predicate per boss is exactly the shape this registry exists to avoid.
         Five new general predicates ship with it (see API.Conditions).
     16. MISS TYPES.  `missType` on a trigger, normalised by core_lifecycle for the
         four *_MISSED sub-events. The Anubisath reflect buffs are not reliably
         visible on Era, so REFLECT / DEFLECT plus the spell school is the only
         evidence there is.
     17. PER-SOURCE ANTI-SPAM.  `antispamBy = "<event field>"` widens an anti-spam
         key with a value off the event, so "one alert per MOB per second" stops
         being "one alert per second across a whole pull of Anubisaths".
     18. STATE DWELL TIME.  `minStateAge` on a state transition — fire only once the
         machine has been in its current state for N seconds. Viscidus's failed
         shatter is inferred from him swinging at someone MORE THAN 5 s after he
         froze, and "more than 5 s after" is a property of the machine, not the swing.

    W4B GRAMMAR EXTENSIONS (Blackwing Lair + Zul'Gurub wave). Seven more. Chromaggus
    is the reason for four of them and Nefarian, Razorgore, Vaelastrasz and Hakkar for
    one each — but every one is written as a PRIMITIVE, because a "vulnerability
    system" that only Chromaggus can use is code wearing a data costume.

     19. RESTYLE ROWS.  `restyles = { … }` — one BAR, several identities, chosen by
         evidence. A restyle row names the `timer` whose running bar it re-labels and
         carries `variants`, each a trigger plus a `style = { text =, icon =, color = }`.
         W2 built `Bars.Restyle` for exactly this and nothing could reach it from data;
         this is the seam (`RESTYLE_REQUEST`). Chromaggus's vulnerability bar (five
         schools) and his breath bars (ten breath spells, two of them per lockout) are
         the design cases. Identity changes; elapsed time does not.
     20. IDENTITY BY EVENT FIELD.  `identBy = "<event field>"` on a timer row — one bar
         per distinct value of that field. `perTarget` (destName) and `nameplate`
         (sourceGUID) were the only two identities the engine had; Chromaggus needs one
         bar per BREATH SPELL, which is neither.
     21. THE ENCOUNTER-IN-PROGRESS POLL.  `scans[].type = "progress"` — sample
         Blizzard's own "is an encounter running" flag at a fixed rate and route each
         CHANGE as an ordinary `on = "progress"` trigger. Nefarian's P1 -> intermission
         -> P2 transition has no combat-log or yell trigger on Era at all; the flag is
         the only evidence that exists.
     22. THE UNIT-FACT SWEEP.  `scans[].type = "unit"` — resolve a creature through the
         Era token ladder and report facts ABOUT it: which of a declared aura set it is
         carrying (`on = "aura"`), and its maximum health (`on = "probe"`). Chromaggus's
         vulnerability is only in the combat log when somebody has Detect Magic up, so
         reading the boss's buffs is one of three independent evidence paths; Hakkar's
         hard mode has no difficulty flag and is inferred from his max health.
         LESSON CLASS 4/6, hard-wired: a sweep that finds NOTHING routes NOTHING. An
         empty read is not proof of absence, and this scanner may never clear state.
     23. NUMERIC FIELD TESTS.  `atLeast` / `atMost` on a trigger — `{ field = value }`
         maps. `where` answers equality; "his maximum health is at least 1,079,325"
         is not an equality question.
     24. KILL-STAGE GATE.  `combat.killMinStage` — the boss's death only counts as a
         KILL from stage N; before that it is a wipe. Razorgore dies in phase 1 every
         time somebody drops the orb, and Blizzard's ENCOUNTER_END lies about it.
     25. RP PULL COUNTDOWN.  `detect.pullCountdown = { seconds =, yellFind =, … }` — a
         chat line that precedes the pull by a known interval starts the engine's own
         pull timer (§11.4) without engaging anything. Vaelastrasz's forced dialogue is
         43.5 s of standing still with no bar unless something declares it.
     26. ROW SUPPRESSION.  `suppressedBy = "<row key>"` on a warning row — the row stays
         quiet while the named row is ENABLED. The spec writes this as "replaces the
         announce when enabled" and it appears seven times across BWL and ZG alone
         (Firemaw's buffet, Ebonroc's taunt, Flamegor's and Hakkar's tranq calls,
         Venoxis's and Mar'li's dispel calls). Two alerts for one fact is worse than
         either alone, and which one you get is a preference.
     27. (API.Conditions, not a new shape) `playerClassIs` — "…and the class this
         trigger names is YOUR class". Nefarian calls out one class at a time by yell;
         the mapping from yell to class is data, so the predicate reads `tr.class`
         instead of one warning row per class per arm.

    W4A GRAMMAR EXTENSIONS (Molten Core + Onyxia + the world bosses — the wave that
    closes W4). TWO, and both come out of Ragnaros. The grammar was mature enough that
    seven zones' worth of encounters needed nothing else; these two are recorded here
    because a reader should be able to see exactly what the last zone cost.

     28. COUNTER ROUTING.  `on = "counter"` finally FIRES. "A counter threshold" has
         been in the published trigger vocabulary since wave 1 and nothing ever routed
         one — the same dead-vocabulary situation W4d extension 6 found for `stage`
         and `state`. Every counter change on a DECLARED counter row is now routed as
         `{ on = "counter", key =, fromKey-matchable, value =, delta = }`, so
         "when the eighth Son of Flame dies, emerge NOW" is a rule rather than an
         accident of row-indexing order. Internal bookkeeping counters (`__warn:`,
         `__occ:`) are deliberately NOT routed: they are engine plumbing, not data.
     29. PULL COUNTDOWN FROM A DEATH.  `detect.pullCountdown` may name
         `creatureDeath = <creature id>` instead of a chat line. W4b extension 25
         established the surface ("an event that precedes the pull by a known interval
         starts the engine's own pull timer"); this only widens the admissible events,
         because Ragnaros's RP window is measured from MAJORDOMO DYING and there is no
         chat line for it in the spec.

    W4A DEFECT FIXES (not extensions — two published paths that nothing ever drove).
    Both predate this wave and both affect encounters shipped in W4d/W4c/W4b:

      A. UNIT_DIED never reached `Life:OnUnitDied`. The combat-log path routed the
         event to encounter rows and stopped there, so DEATH-BASED KILL DETECTION was
         reachable only through a corroborated sync or the harness. Razorgore
         (`noEncounterEndKill`) had no working kill path in-game at all. Wired in
         `Life:Deliver`.
      B. `unitCast` was never PRODUCED. UNIT_SPELLCAST_SUCCEEDED was not in the
         lifecycle's event set, so every `on = "unitCast"` row ever written was dead:
         Maexxna's spiderlings, Sapphiron's air phase, Viscidus, Venoxis, Arlokk — and
         now Ragnaros's submerge visual and Ysondre's Lightning Wave. Registered and
         normalised, gated so it costs nothing while nothing is engaged.

    THE ESCAPE HATCH IS THE CONTRACT WITH W4d. The five shipped Naxx specials
    (mod_loatheb_healers, mod_fourhorsemen_rotation, mod_fourhorsemen_tracker,
    mod_gothik_waves, mod_razuvious_understudy, thaddius) are NOT touched by this
    wave. They call exactly three engine-owned surfaces:
        Addon:RegisterModule{...}   -- modules.lua, unchanged
        Addon:RegisterCombatHook(fn) with signature
            fn(subevent, sourceGUID, sourceID, destGUID, destID, spellID, spellName)
        Addon.active = { raidId, bossId, boss, startTime }
    All three are preserved VERBATIM here. The ONLY seam W4d adds is a `legacy =
    { raidId=, bossId= }` field on the encounter definition, which tells the engine
    which legacy module bucket to Start/Stop on engage/end.
--]]

local _, Addon = ...

local API = {}
Addon.API = API

-- ══════════════════════════════════════════════════════════════════════════════
--  A. DISPATCH SEAM (ENGINE SPEC §11.8)
-- ══════════════════════════════════════════════════════════════════════════════

Addon._engineCallbacks = {}     -- event -> ordered { fn, owner }
Addon._eventLog        = nil    -- headless recorder, off unless enabled
Addon.EVENT_LOG_MAX    = 4000

-- The published event vocabulary. W2/W3 build against exactly this list.
API.EVENTS = {
    -- lifecycle
    "ENGINE_ENGAGE",        -- (encId, rt, delay, trigger)
    "ENGINE_END",           -- (encId, rt, wiped, duration, bossHpPct)
    "ENGINE_STAGE",         -- (encId, stage, totality)
    "ENGINE_WIPE_VERDICT",  -- (encId, verdict, confirming)
    "ENGINE_LOCKOUT",       -- (encId, reason, remaining)
    "ENGINE_LOGIN",         -- (isLogin, isReload)        -> W3 reload-recovery cascade (§9.1)
    -- timers
    "TIMER_START", "TIMER_UPDATE", "TIMER_STOP", "TIMER_PAUSE", "TIMER_RESUME",
    "TIMER_COUNTDOWN",      -- (barId, remainingCount, timer)
    -- warnings
    "WARN_ANNOUNCE",        -- (encId, row, text, ...)
    "WARN_SPECIAL",         -- (encId, row, text, ...)
    -- services other waves own
    "SCAN_REQUEST",         -- (encId, scanDecl, ctx)     -> W2 target scanners
    "ICON_REQUEST",         -- (encId, iconDecl, ctx)     -> W2 raid icons
    "RESTYLE_REQUEST",      -- (encId, restyleRow, style, ctx) -> W2 Bars.Restyle (W4b ext 19)
    "SYNC_SEND",            -- (subPrefix, ...)           -> W3 addon channel, outbound
    "SYNC_RECV",            -- (subPrefix, sender, ...)   -> W3 addon channel, inbound
    "ENGINE_PULL",          -- (seconds, source, target)  -> W3 pull timer (§11.4)
    "ENGINE_BREAK",         -- (seconds, source)          -> W3 break timer (§11.4)
    "COUNTER",              -- (encId, key, value, delta)
    "STATE",                -- (encId, key, from, to)
    "TELEMETRY",            -- (entry)
}

local KNOWN_EVENT = {}
for _, e in ipairs(API.EVENTS) do KNOWN_EVENT[e] = true end

function Addon:RegisterEngineCallback(event, fn, owner)
    if type(fn) ~= "function" then return false end
    local list = Addon._engineCallbacks[event]
    if not list then list = {}; Addon._engineCallbacks[event] = list end
    list[#list + 1] = { fn = fn, owner = owner }
    return true
end

function Addon:UnregisterEngineCallback(event, fn)
    local list = Addon._engineCallbacks[event]
    if not list then return 0 end
    local n = 0
    for i = #list, 1, -1 do
        if list[i].fn == fn then table.remove(list, i); n = n + 1 end
    end
    return n
end

-- Headless / diagnostic recorder. Bounded; the harness reads it to prove the
-- engine drove the right decisions without needing any UI.
function Addon:SetEventRecording(on)
    Addon._eventLog = on and (Addon._eventLog or {}) or nil
    return Addon._eventLog
end

function Addon:GetEventLog() return Addon._eventLog end

function Addon:ClearEventLog()
    local l = Addon._eventLog
    if l then for i = #l, 1, -1 do l[i] = nil end end
end

function Addon:FireEngineEvent(event, ...)
    local log = Addon._eventLog
    if log then
        if #log >= Addon.EVENT_LOG_MAX then table.remove(log, 1) end
        log[#log + 1] = { event = event, n = select("#", ...), ... }
    end
    local list = Addon._engineCallbacks[event]
    if not list then return 0 end
    local fired = 0
    for i = 1, #list do
        local cb = list[i]
        local okc, err = pcall(cb.fn, event, ...)   -- secure-call wrapper, §11.8
        if okc then
            fired = fired + 1
        elseif Addon.Telemetry then
            Addon.Telemetry.Write("api.validate", { reason = "callback error", key = event,
                                                    detail = tostring(err) })
        end
    end
    return fired
end

-- ── Alert dispatch seam ───────────────────────────────────────────────────────
-- RETIRED IN W2. This carried a wave-1 shim: an opportunistic pcall forward into
-- whatever alerts.lua happened to expose, so the engine had *some* visible output
-- before a real warning surface existed. ui_warnings.lua is that surface now — it
-- consumes WARN_ANNOUNCE / WARN_SPECIAL and renders the two tiers properly — so
-- the fallback is gone and these are pure dispatch again.
--
-- alerts.lua's Addon:ShowWarning / Addon:ShowSpecialWarning are UNTOUCHED and still
-- shipping: the five Naxx special modules call them directly with their own anchor
-- keys (thaddius.lua, mod_gothik_waves.lua), and the design doc's verdict on the
-- alert HUD is KEEP + EXTEND. W4d re-seats those callers onto engine rows.
-- W4d added the optional 4th argument `target`: the player the warning is ABOUT, so
-- the combine/precise batchers can list names. Three-argument callers are unchanged.
function Addon:EmitAnnounce(encId, row, text, target)
    Addon:FireEngineEvent("WARN_ANNOUNCE", encId, row, text, target)
    return text
end

function Addon:EmitSpecial(encId, row, text, target)
    Addon:FireEngineEvent("WARN_SPECIAL", encId, row, text, target)
    return text
end

-- ══════════════════════════════════════════════════════════════════════════════
--  B. THE DECLARATIVE ENCOUNTER GRAMMAR
-- ══════════════════════════════════════════════════════════════════════════════

-- Detection modes (ENCOUNTERS SPEC §1.1 + ENGINE SPEC §2.1). `combat` subscribes
-- to all generic paths; the message variants subscribe to chat triggers instead
-- of, or in addition to, the generic paths.
API.DETECT_MODES = {
    combat = true, yell = true, say = true, emote = true,
    yell_regex = true, say_regex = true, emote_regex = true,
    combat_yell = true, combat_say = true, combat_emote = true,
    combat_yellfind = true, combat_sayfind = true, combat_emotefind = true,
    zone = true,                    -- trash module: armed for a whole instance
}

-- Timer kinds. `cd/next/cast/active/fades/target/stage/intermission/adds/berserk`
-- cover every row in the encounters spec; `learning` is the self-teaching flavour
-- (ENGINE SPEC §4.6) and is exempt from the early-refresh tripwire.
API.TIMER_KINDS = {
    cd = "cd", next = "cd", cast = "cast", active = "cd", fades = "cd",
    target = "target", stage = "stage", intermission = "stage", adds = "cd",
    berserk = "berserk", combat = "cd", achievement = "cd", learning = "cd",
}

-- The simplified external categories every timer collapses into (§4.5), so
-- third-party consumers and our own bars agree.
API.SIMPLE_CATEGORIES = { cd = true, target = true, stage = true, cast = true,
                          ["break"] = true, pull = true, berserk = true,
                          cdnp = true, castnp = true }

-- Colour indices (§4.5): 1 add, 2 AoE, 3 targeted, 4 interrupt, 5 role, 6 stage, 7 user.
API.COLOR_MAX = 7

-- Trigger vocabulary. CLEU sub-events plus the engine's own synthetic sources.
API.TRIGGER_EVENTS = {
    -- combat log
    SPELL_CAST_START = true, SPELL_CAST_SUCCESS = true, SPELL_CAST_FAILED = true,
    SPELL_AURA_APPLIED = true, SPELL_AURA_REFRESH = true, SPELL_AURA_REMOVED = true,
    SPELL_AURA_APPLIED_DOSE = true, SPELL_AURA_REMOVED_DOSE = true,
    SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true, SPELL_MISSED = true,
    SPELL_PERIODIC_MISSED = true, SPELL_HEAL = true, SPELL_SUMMON = true,
    SPELL_INTERRUPT = true, SPELL_DISPEL = true, SWING_DAMAGE = true,
    RANGE_DAMAGE = true, UNIT_DIED = true, UNIT_DESTROYED = true,
    RANGE_MISSED = true, SWING_MISSED = true,   -- W4c: the reflect evidence path
    -- synthetic / non-CLEU
    pull = true, yell = true, say = true, emote = true, bossEmote = true,
    unitCast = true,        -- UNIT_SPELLCAST_SUCCEEDED channel (Gothik, Sapphiron, Ysondre)
    health = true,          -- boss-health threshold from the poll
    stage = true,           -- a stage transition
    schedule = true,        -- a pure schedule seeded at pull
    nameplate = true,       -- NAME_PLATE_UNIT_ADDED (KT phase 2, Razuvious understudies)
    targetChanged = true,   -- UNIT_TARGET
    unitDeath = true,       -- creature-id death (alias of UNIT_DIED with a creature filter)
    sync = true,            -- an incoming module sync (W3)
    state = true,           -- an emote state machine transition
    counter = true,         -- a counter threshold
    aura = true,            -- a unit-aura sweep result (Chromaggus/Thaddius icon reads)
    roster = true,          -- W4c: a roster membership change (C'Thun's stomach list)
    probe = true,           -- W4c: a roster-relayed unit sample (C'Thun's Flesh Tentacles)
                            --      W4b: also the unit-fact sweep's max-health report
    progress = true,        -- W4b: Blizzard's encounter-in-progress flag changed (Nefarian)
}

-- W4c extension 16. The four *_MISSED sub-events carry a miss TYPE that nothing
-- else does. Uppercase, matched verbatim ("REFLECT", "DEFLECT", "IMMUNE", …).
API.MISS_TYPES = {
    ABSORB = true, BLOCK = true, DEFLECT = true, DODGE = true, EVADE = true,
    IMMUNE = true, MISS = true, PARRY = true, REFLECT = true, RESIST = true,
}

-- Role gates (ENCOUNTERS SPEC §1.4). Compound gates use `|` as OR. The engine
-- stores them; W2's role resolver evaluates them.
API.ROLE_GATES = {
    Tank = true, Healer = true, Melee = true, ["-Melee"] = true, Dps = true,
    RangedDps = true, CasterDps = true, SpellCaster = true, ManaUser = true,
    ["-Healer"] = true, HasInterrupt = true, MagicDispeller = true,
    RemoveMagic = true, RemoveCurse = true, RemovePoison = true, RemoveEnrage = true,
}

-- W4c extension 13 adds the fourth shape: `roster`, which samples through OTHER
-- PLAYERS' targets rather than through the boss's.
-- W4b adds the two shapes that ask about a unit rather than about its target:
-- `progress` (Blizzard's encounter flag) and `unit` (that creature's own auras and
-- maximum health).
API.SCAN_TYPES  = { poll = true, event = true, repeated = true, roster = true,
                    progress = true, unit = true }
API.COUNTER_SCOPES = { global = true, self = true, boss = true, census = true, target = true }
API.WARN_TIERS  = { announce = true, special = true }

-- ── W4d: NAMED CONDITIONS (extension 10) ──────────────────────────────────────
-- A trigger names a predicate; the engine resolves it. Keeps encounter data free of
-- functions (it must stay serialisable and reviewable) while still expressing the
-- handful of spec rules that are genuinely a question about the live world. Every
-- entry is `fn(rt, ev, tr) -> boolean` and every one is overridable, which is how the
-- harness drives them deterministically.
API.Conditions = {}

-- "…and you are the boss's current tank" (Faerlina's defensive special). The spec is
-- explicit that this branch keys off whether YOU are tanking, not off a role flag.
API.Conditions.playerIsBossTarget = function(rt, ev, tr)
    local unit
    local Scan = Addon.Scan
    if Scan and Scan.ResolveUnit then
        local cid = (tr and tr.creatureId) or (ev and ev.sourceId) or (rt.def.creatureIds or {})[1]
        unit = Scan.ResolveUnit(cid, ev and ev.sourceGUID)
    end
    if not unit then return false end
    local f = _G.UnitIsUnit
    if type(f) ~= "function" then return false end
    return f("player", unit .. "target") and true or false
end

-- ── W4c: the taunt-branch predicates (extension 15) ───────────────────────────
-- The spec's three-way stack branch — "on you" / "you should taunt" / "plain
-- announce" — appears verbatim on Kurinnaxx, Buru, Fankriss and Huhuran. Its middle
-- arm is THREE separate facts: someone else is at N stacks (an ordinary trigger
-- filter), you do not carry the debuff, and you are alive. Each is its own predicate.

-- "…and you are alive" (not dead, not a ghost). Also the suppressor on C'Thun's
-- Dark Glare special, which the spec says is skipped while you are a ghost.
API.Conditions.playerAlive = function()
    local L = Addon.Lifecycle
    local f = (L and L.env and L.env.UnitIsDeadOrGhost) or _G.UnitIsDeadOrGhost
    if type(f) ~= "function" then return true end     -- unanswerable: do not suppress
    return not f("player")
end

-- "…and YOU do not have the debuff." Answered from the encounter's own roster
-- rather than from an aura scan: the engine has already watched every application
-- and removal go past in the combat log, so the membership set is both cheaper and
-- more Era-reliable than re-reading the player's debuff bar.
API.Conditions.playerNotInRoster = function(rt, ev, tr)
    local key = tr and (tr.roster or tr.rosterKey)
    if not key then return false end
    local r = rt.rosters and rt.rosters[key]
    if not r then return true end
    return r[API.PlayerName()] == nil
end

-- "…and this event is about YOU", where "about you" is either the destination name
-- or your name appearing inside the text. Buru's pursuit has no spell id at all on
-- Era — the emote naming you is the entire mechanic — and a boss-target scan
-- reports a NAME, not a unit flag, so both shapes need the same answer.
API.Conditions.namesPlayer = function(rt, ev)
    if not ev then return false end
    if ev.destIsPlayer then return true end
    local me = API.PlayerName()
    if not me then return false end
    if ev.destName == me or ev.targetName == me then return true end
    if type(ev.text) == "string" and ev.text:find(me, 1, true) then return true end
    return false
end

-- "…and the mob is close enough to matter." Sartura's whirlwind special is gated on
-- a can-you-actually-be-hit check; the Era answer is the range ladder, clamped.
API.Conditions.playerNearSource = function(rt, ev, tr)
    local Era = Addon.Era
    if not Era or type(Era.CheckRange) ~= "function" then return true end
    local unit
    local Scan = Addon.Scan
    if Scan and Scan.ResolveUnit then
        unit = Scan.ResolveUnit((tr and tr.creatureId) or (ev and ev.sourceId),
                                ev and ev.sourceGUID)
    end
    if not unit then return true end       -- cannot see it: do not swallow the alert
    return Era.CheckRange(unit, (tr and tr.range) or 10) and true or false
end

-- "…and the class this trigger names is YOUR class" (W4b extension 27). Nefarian's
-- twelve class calls are one mechanic with a per-class payload, and the payload is
-- carried by the trigger (`class = "DRUID"`), so the personal arm is ONE row with one
-- trigger per yell rather than one row per class. Reads the class resolver svc_era
-- installs, which is also what `classDefault` reads, so both answers agree.
API.Conditions.playerClassIs = function(rt, ev, tr)
    local want = tr and tr.class
    if not want then return false end
    local f = Addon.ClassResolver
    if type(f) ~= "function" then return false end   -- unanswerable: do not claim it is you
    return f() == want
end

-- ── W4a: two more predicates (still not new shapes) ───────────────────────────

-- "…and the player this event is ABOUT is the boss's current tank." The mirror of
-- `playerIsBossTarget`, which answers the same question about YOU. The Dragons of
-- Nightmare filter their Noxious Breath stack announce to the dragon's current tank
-- rather than to a role, so the subject of the test is the event's destination.
API.Conditions.destIsBossTarget = function(rt, ev, tr)
    local name = ev and (ev.destName or ev.targetName)
    if not name then return false end
    local unit
    local Scan = Addon.Scan
    if Scan and Scan.ResolveUnit then
        local cid = (tr and tr.creatureId) or (ev and ev.sourceId) or (rt.def.creatureIds or {})[1]
        unit = Scan.ResolveUnit(cid, ev and ev.sourceGUID)
    end
    if not unit then return false end
    local f = Addon.Lifecycle and Addon.Lifecycle.env and Addon.Lifecycle.env.UnitName
    if type(f) ~= "function" then f = _G.UnitName end
    if type(f) ~= "function" then return false end
    return f(unit .. "target") == name
end

-- "…and this pull is reliable enough to put a clock on it." Lord Kazzak's berserk bar
-- is the spec's one conditional timer: it starts only when the pull was yell-detected
-- or the fight is inside an instance, because a random outdoor aggro pull can happen
-- minutes before anybody notices and a berserk bar seeded from it is a lie. It is one
-- rule with an OR in it — the OR is the rule, not two rules — so it is one predicate.
API.Conditions.pullTimeable = function(rt)
    if rt and rt.trigger == "chat" then return true end
    local L = Addon.Lifecycle
    if L and type(L.InInstance) == "function" then
        local okc, inside = pcall(L.InInstance, L)
        if okc and inside then return true end
    end
    return false
end

-- "…and the mob that gained it is on a nameplate." The Twin Emperors' Explode Bug
-- only warns for a bug that is actually near you, and walking the nameplate units is
-- the only proximity answer Era gives for a mob you are not targeting.
API.Conditions.sourceOnNameplate = function(rt, ev)
    local guid = ev and (ev.sourceGUID or ev.destGUID)
    if not guid then return false end
    local L = Addon.Lifecycle
    if not L or type(L.env.ForEachNameplate) ~= "function" then return false end
    return L.env.ForEachNameplate(function(u)
        return L.env.UnitGUID(u) == guid
    end) and true or false
end

-- The player's own name, cached per session. Every predicate above needs it and
-- UnitName("player") is not free inside a combat-log hot path.
-- Read through the LIFECYCLE'S injected world first and only then off the global, so
-- the predicates above answer the same world every other engine decision answers
-- (and so the harness can drive them).
function API.PlayerName()
    if API._playerName then return API._playerName end
    local n
    local L = Addon.Lifecycle
    if L and type(L.env) == "table" and type(L.env.UnitName) == "function" then
        n = L.env.UnitName("player")
    end
    if n == nil and type(_G.UnitName) == "function" then n = _G.UnitName("player") end
    API._playerName = n
    return n
end
function API.ForgetPlayerName() API._playerName = nil end

-- Run a trigger's `condition` / `conditionNot` field, which may be one name or a
-- LIST of names (extension 15). An unknown name has already been refused by
-- validation, so a missing predicate here means the row was hand-built in a test.
local function conditionsPass(rt, ev, tr, field, wantTrue)
    local spec = tr[field]
    if spec == nil then return true end
    local list = type(spec) == "table" and spec or { spec }
    for _, name in ipairs(list) do
        local f = API.Conditions[name]
        local got = f and f(rt, ev, tr) and true or false
        if wantTrue and not got then return false end
        if (not wantTrue) and got then return false end
    end
    return true
end
API.ConditionsPass = conditionsPass

-- ── Registry ──────────────────────────────────────────────────────────────────
Addon.encounters        = {}    -- ordered array
Addon.encountersById    = {}    -- id -> def
Addon.encByCreature     = {}    -- creatureId -> { def, ... }
Addon.encByEncounterId  = {}    -- encounterId -> { def, ... }
Addon.encByZone         = {}    -- instanceId -> { def, ... }

local function listify(v)
    if v == nil then return nil end
    if type(v) == "table" then return v end
    return { v }
end

local function addTo(map, key, def)
    local l = map[key]
    if not l then l = {}; map[key] = l end
    l[#l + 1] = def
end

-- ── Validation ────────────────────────────────────────────────────────────────
-- Never throws in-game: returns an error list and writes to the telemetry ring.
-- The harness asserts the list is empty for real data (and non-empty for the
-- deliberate bad fixtures).
local validateDuration      -- forward: triggers may carry their own duration override

local function validateTrigger(errs, where, tr)
    if type(tr) ~= "table" then errs[#errs + 1] = where .. ": trigger must be a table"; return end
    if tr.on == nil then errs[#errs + 1] = where .. ": trigger has no `on`"; return end
    if not API.TRIGGER_EVENTS[tr.on] then
        errs[#errs + 1] = where .. ": unknown trigger event '" .. tostring(tr.on) .. "'"
    end
    -- W4d extensions carry their own validation, per the wave's mandate.
    if tr.delay ~= nil and (type(tr.delay) ~= "number" or tr.delay < 0) then
        errs[#errs + 1] = where .. ": `delay` must be a non-negative number"
    end
    -- W4c extension 15: one name or a list of them, every entry registered.
    for _, field in ipairs({ "condition", "conditionNot" }) do
        local spec = tr[field]
        if spec ~= nil then
            local list = type(spec) == "table" and spec or { spec }
            if type(spec) == "table" and #spec == 0 then
                errs[#errs + 1] = where .. ": `" .. field .. "` list is empty"
            end
            for _, name in ipairs(list) do
                if API.Conditions[name] == nil then
                    errs[#errs + 1] = where .. ": unknown condition '" .. tostring(name) .. "'"
                end
            end
        end
    end
    -- W4c extension 16: miss types are a closed set; a typo here is silent forever.
    if tr.missType ~= nil then
        local list = type(tr.missType) == "table" and tr.missType or { tr.missType }
        for _, m in ipairs(list) do
            if not API.MISS_TYPES[m] then
                errs[#errs + 1] = where .. ": unknown miss type '" .. tostring(m) .. "'"
            end
        end
    end
    -- W4c extension 17: the widening field must name an event field, and widening a
    -- key with no window to throttle is a data mistake worth catching.
    if tr.antispamBy ~= nil then
        if type(tr.antispamBy) ~= "string" then
            errs[#errs + 1] = where .. ": `antispamBy` must name an event field"
        elseif tr.antispam == nil then
            errs[#errs + 1] = where .. ": `antispamBy` without an `antispam` window"
        end
    end
    if tr.dest ~= nil and tr.dest ~= "player" and tr.dest ~= "other" then
        errs[#errs + 1] = where .. ": `dest` must be 'player' or 'other'"
    end
    if tr.source ~= nil and tr.source ~= "player" and tr.source ~= "pet"
       and tr.source ~= "other" then
        errs[#errs + 1] = where .. ": `source` must be 'player', 'pet' or 'other'"
    end
    if tr.minStateAge ~= nil and (type(tr.minStateAge) ~= "number" or tr.minStateAge < 0) then
        errs[#errs + 1] = where .. ": `minStateAge` must be a non-negative number"
    end
    if tr.index ~= nil and type(tr.index) ~= "number" and type(tr.index) ~= "table" then
        errs[#errs + 1] = where .. ": `index` must be a number or a table"
    end
    if tr.where ~= nil and type(tr.where) ~= "table" then
        errs[#errs + 1] = where .. ": `where` must be a table of event-field values"
    end
    if tr.states ~= nil and type(tr.states) ~= "table" then
        errs[#errs + 1] = where .. ": `states` must be a table of stateKey -> value"
    end
    if tr.counter ~= nil then
        local list = tr.counter[1] and tr.counter or { tr.counter }
        for _, c in ipairs(list) do
            if type(c) ~= "table" or type(c.key) ~= "string" then
                errs[#errs + 1] = where .. ": `counter` needs { key = <counter row key>, … }"
            elseif c.eq == nil and c.min == nil and c.max == nil then
                errs[#errs + 1] = where .. ": counter '" .. tostring(c.key) .. "' has no eq/min/max test"
            end
        end
    end
    if tr.dedupe ~= nil and type(tr.dedupe) ~= "string" then
        errs[#errs + 1] = where .. ": `dedupe` must name an event field"
    end
    -- W4b extension 23: numeric field tests. `where` answers equality and nothing else,
    -- so "his maximum health is at least N" had no expression at all.
    for _, field in ipairs({ "atLeast", "atMost" }) do
        local spec = tr[field]
        if spec ~= nil then
            if type(spec) ~= "table" then
                errs[#errs + 1] = where .. ": `" .. field .. "` must be { <event field> = number }"
            else
                local n = 0
                for k, v in pairs(spec) do
                    n = n + 1
                    if type(k) ~= "string" or type(v) ~= "number" then
                        errs[#errs + 1] = where .. ": `" .. field ..
                            "` maps an event field name to a number"
                    end
                end
                if n == 0 then errs[#errs + 1] = where .. ": `" .. field .. "` is empty" end
            end
        end
    end
    if tr.duration ~= nil then validateDuration(errs, where .. ".duration", tr.duration) end
end

local function validateRole(errs, where, role)
    if role == nil then return end
    if type(role) ~= "string" then errs[#errs + 1] = where .. ": role gate must be a string"; return end
    for tok in role:gmatch("[^|]+") do
        tok = tok:gsub("^%s+", ""):gsub("%s+$", "")
        if not API.ROLE_GATES[tok] then
            errs[#errs + 1] = where .. ": unknown role gate '" .. tok .. "'"
        end
    end
end

function validateDuration(errs, where, v)
    if v == nil then return end
    local T = Addon.Timers
    if not T then return end                 -- timers module loads after us in headless slices
    if type(v) == "table" then
        for k, sub in pairs(v) do validateDuration(errs, where .. "[" .. tostring(k) .. "]", sub) end
        return
    end
    if not T.ParseDuration(v) then
        errs[#errs + 1] = where .. ": unparseable duration '" .. tostring(v) .. "'"
    end
end

function API.Validate(def)
    local errs = {}
    if type(def) ~= "table" then return { "encounter definition must be a table" } end
    if type(def.id) ~= "string" or def.id == "" then errs[#errs + 1] = "encounter needs a string id" end
    local d = def.detect or {}
    if d.mode and not API.DETECT_MODES[d.mode] then
        errs[#errs + 1] = "unknown detect.mode '" .. tostring(d.mode) .. "'"
    end
    -- A ZONE (trash) module is armed by the instance, not started by a mob or a yell,
    -- so the "nothing can start it" rule is satisfied by declaring the zone instead.
    local isZone = (d.mode == "zone")
    if isZone and not def.zone then
        errs[#errs + 1] = tostring(def.id) .. ": a zone module must declare the instance it arms in"
    end
    if not isZone and not def.creatureId and not def.encounterId and not (d.yell or d.yellFind
        or d.yellPattern or d.emote or d.emoteFind or d.say) then
        errs[#errs + 1] = def.id .. ": no creatureId, encounterId or chat trigger — nothing can start it"
    end

    local seen = {}
    local function rowKey(kind, row, i)
        local k = row.key
        if type(k) ~= "string" or k == "" then
            errs[#errs + 1] = ("%s: %s row %d has no key"):format(tostring(def.id), kind, i)
            return nil
        end
        if seen[k] then
            errs[#errs + 1] = ("%s: duplicate row key '%s'"):format(tostring(def.id), k)
        end
        seen[k] = true
        return k
    end

    for i, row in ipairs(def.timers or {}) do
        local where = ("%s.timers[%s]"):format(tostring(def.id), tostring(row.key or i))
        rowKey("timer", row, i)
        if row.kind and not API.TIMER_KINDS[row.kind] then
            errs[#errs + 1] = where .. ": unknown timer kind '" .. tostring(row.kind) .. "'"
        end
        validateDuration(errs, where .. ".duration", row.duration)
        validateDuration(errs, where .. ".pull", row.pull)
        validateDuration(errs, where .. ".phaseDuration", row.phaseDuration)
        validateRole(errs, where, row.role)
        if row.start then validateTrigger(errs, where .. ".start", row.start) end
        if row.restart then validateTrigger(errs, where .. ".restart", row.restart) end
        if row.stop then validateTrigger(errs, where .. ".stop", row.stop) end
        -- W4d extension 4: the list forms. One bar, many ways in.
        for j, tr in ipairs(row.starts   or {}) do validateTrigger(errs, where .. ".starts["   .. j .. "]", tr) end
        for j, tr in ipairs(row.restarts or {}) do validateTrigger(errs, where .. ".restarts[" .. j .. "]", tr) end
        for j, tr in ipairs(row.stops    or {}) do validateTrigger(errs, where .. ".stops["    .. j .. "]", tr) end
        for j, tr in ipairs(row.cancels  or {}) do validateTrigger(errs, where .. ".cancels["  .. j .. "]", tr) end
        if row.cancel then validateTrigger(errs, where .. ".cancel", row.cancel) end
        if row.delay ~= nil and (type(row.delay) ~= "number" or row.delay < 0) then
            errs[#errs + 1] = where .. ": `delay` must be a non-negative number"
        end
        if row.color and (type(row.color) ~= "number" or row.color < 1 or row.color > API.COLOR_MAX) then
            errs[#errs + 1] = where .. ": colour index out of range 1.." .. API.COLOR_MAX
        end
        -- W4b extension 20. Three identities cannot be true of one bar at once, and a
        -- row that declared two would silently pick whichever the dispatcher tested first.
        if row.identBy ~= nil then
            if type(row.identBy) ~= "string" then
                errs[#errs + 1] = where .. ": `identBy` must name an event field"
            elseif row.perTarget or row.nameplate then
                errs[#errs + 1] = where .. ": `identBy` cannot combine with perTarget/nameplate"
            end
        end
    end

    for i, row in ipairs(def.warnings or {}) do
        local where = ("%s.warnings[%s]"):format(tostring(def.id), tostring(row.key or i))
        rowKey("warning", row, i)
        local tier = row.tier or "announce"
        if not API.WARN_TIERS[tier] then
            errs[#errs + 1] = where .. ": unknown warning tier '" .. tostring(tier) .. "'"
        end
        if tier == "announce" and row.color and (row.color < 1 or row.color > 4) then
            errs[#errs + 1] = where .. ": announce colour tier must be 1..4"
        end
        if tier == "special" and row.sound and (row.sound < 1 or row.sound > 5) then
            errs[#errs + 1] = where .. ": special sound tier must be 1..5"
        end
        validateRole(errs, where, row.role)
        if row.trigger then validateTrigger(errs, where .. ".trigger", row.trigger) end
        for j, tr in ipairs(row.triggers or {}) do
            validateTrigger(errs, where .. ".triggers[" .. j .. "]", tr)
        end
        if row.cancel then validateTrigger(errs, where .. ".cancel", row.cancel) end
        for j, tr in ipairs(row.cancels or {}) do
            validateTrigger(errs, where .. ".cancels[" .. j .. "]", tr)
        end
        if row.delay ~= nil and (type(row.delay) ~= "number" or row.delay < 0) then
            errs[#errs + 1] = where .. ": `delay` must be a non-negative number"
        end
        if row.stacks and row.count then
            errs[#errs + 1] = where .. ": a row fills `%d` from `stacks` OR `count`, not both"
        end
        -- W4b extension 26: a suppressor that names nothing suppresses nothing, forever
        -- and silently. (Resolved after the loop, once every row key is known.)
        if row.suppressedBy ~= nil and type(row.suppressedBy) ~= "string" then
            errs[#errs + 1] = where .. ": `suppressedBy` must name another row"
        end
    end
    do
        local warnKeys = {}
        for _, row in ipairs(def.warnings or {}) do if row.key then warnKeys[row.key] = true end end
        for i, row in ipairs(def.warnings or {}) do
            if type(row.suppressedBy) == "string" then
                if not warnKeys[row.suppressedBy] then
                    errs[#errs + 1] = ("%s.warnings[%s]: `suppressedBy` names no row ('%s')")
                        :format(tostring(def.id), tostring(row.key or i), row.suppressedBy)
                elseif row.suppressedBy == row.key then
                    errs[#errs + 1] = ("%s.warnings[%s]: a row cannot suppress itself")
                        :format(tostring(def.id), tostring(row.key or i))
                end
            end
        end
    end

    -- W4c: icon rows are addressable rows too (every one of them is a checkbox), and
    -- until now they were the only section whose triggers nothing validated.
    for i, row in ipairs(def.icons or {}) do
        local where = ("%s.icons[%s]"):format(tostring(def.id), tostring(row.key or i))
        rowKey("icon", row, i)
        if row.on then validateTrigger(errs, where .. ".on", row.on) end
    end

    -- W4d extension 5: schedule rows are user-addressable rows like any other, so
    -- they take part in the key-uniqueness rule and carry their own validation.
    for i, row in ipairs(def.schedule or {}) do
        local where = ("%s.schedule[%s]"):format(tostring(def.id), tostring(row.key or i))
        rowKey("schedule", row, i)
        if not row.gaps and not row.at then
            errs[#errs + 1] = where .. ": a schedule row needs `gaps` or `at`"
        end
        if row.gaps then
            if type(row.gaps) ~= "table" or #row.gaps == 0 then
                errs[#errs + 1] = where .. ": `gaps` must be a non-empty list"
            else
                local rf = row.gaps.repeatFrom
                if rf ~= nil and (type(rf) ~= "number" or rf < 1 or rf > #row.gaps) then
                    errs[#errs + 1] = where .. ": `gaps.repeatFrom` is outside the gap list"
                end
            end
        end
        if row.pre ~= nil and type(row.pre) ~= "number" and type(row.pre) ~= "table" then
            errs[#errs + 1] = where .. ": `pre` must be a number or a list of numbers"
        end
        if row.count ~= nil and (type(row.count) ~= "number" or row.count < 1) then
            errs[#errs + 1] = where .. ": `count` must be a positive number of ticks"
        end
    end

    for i, row in ipairs(def.scans or {}) do
        local where = ("%s.scans[%s]"):format(tostring(def.id), tostring(row.key or i))
        rowKey("scan", row, i)
        if not API.SCAN_TYPES[row.type or "poll"] then
            errs[#errs + 1] = where .. ": unknown scan type '" .. tostring(row.type) .. "'"
        end
        -- W4c extension 13: a roster-relayed scan is meaningless without the roster
        -- whose members' targets it borrows, and without the creature it is hunting.
        if row.type == "roster" then
            if type(row.roster) ~= "string" then
                errs[#errs + 1] = where .. ": a roster scan must name the `roster` it relays through"
            end
            if row.creatureId == nil then
                errs[#errs + 1] = where .. ": a roster scan must name the `creatureId` it is looking for"
            end
        end
        if row.on then validateTrigger(errs, where .. ".on", row.on) end
        if row.stop then validateTrigger(errs, where .. ".stop", row.stop) end
    end

    for i, row in ipairs(def.counters or {}) do
        local where = ("%s.counters[%s]"):format(tostring(def.id), tostring(row.key or i))
        rowKey("counter", row, i)
        if not API.COUNTER_SCOPES[row.scope or "global"] then
            errs[#errs + 1] = where .. ": unknown counter scope '" .. tostring(row.scope) .. "'"
        end
        if row.inc then validateTrigger(errs, where .. ".inc", row.inc) end
        if row.dec then validateTrigger(errs, where .. ".dec", row.dec) end
        for j, tr in ipairs(row.incs or {}) do validateTrigger(errs, where .. ".incs[" .. j .. "]", tr) end
        if row.reset then validateTrigger(errs, where .. ".reset", row.reset) end
        for j, tr in ipairs(row.resets or {}) do validateTrigger(errs, where .. ".resets[" .. j .. "]", tr) end
        -- W4c extension 14: the rate window. `fallback` is the WIDER sample set the
        -- rate falls back to when the narrow window has not filled yet, so a fallback
        -- smaller than the window would silently never be used.
        if row.rate ~= nil then
            if type(row.rate) ~= "table" then
                errs[#errs + 1] = where .. ": `rate` must be { window =, fallback = }"
            else
                local w, f = row.rate.window, row.rate.fallback
                if type(w) ~= "number" or w < 2 then
                    errs[#errs + 1] = where .. ": rate.window must be a number >= 2"
                end
                if f ~= nil and (type(f) ~= "number" or (type(w) == "number" and f < w)) then
                    errs[#errs + 1] = where .. ": rate.fallback must be >= rate.window"
                end
            end
        end
    end

    -- W4c extension 12: rosters. A membership set is a user-addressable row like any
    -- other (it is what an info frame hangs off), so it takes part in key uniqueness.
    for i, row in ipairs(def.rosters or {}) do
        local where = ("%s.rosters[%s]"):format(tostring(def.id), tostring(row.key or i))
        rowKey("roster", row, i)
        if not row.add and not row.adds then
            errs[#errs + 1] = where .. ": a roster needs an `add` trigger (nothing can join it)"
        end
        if row.add then validateTrigger(errs, where .. ".add", row.add) end
        for j, tr in ipairs(row.adds or {}) do validateTrigger(errs, where .. ".adds[" .. j .. "]", tr) end
        if row.remove then validateTrigger(errs, where .. ".remove", row.remove) end
        for j, tr in ipairs(row.removes or {}) do validateTrigger(errs, where .. ".removes[" .. j .. "]", tr) end
        if row.clear then validateTrigger(errs, where .. ".clear", row.clear) end
        for j, tr in ipairs(row.clears or {}) do validateTrigger(errs, where .. ".clears[" .. j .. "]", tr) end
        if row.hold ~= nil and (type(row.hold) ~= "number" or row.hold < 0) then
            errs[#errs + 1] = where .. ": `hold` must be a non-negative number of seconds"
        end
    end

    -- W4b extension 19: restyle rows. A row that names a timer that does not exist is
    -- a silent no-op forever, which is exactly the class of mistake validation is for.
    do
        local timerKeys = {}
        for _, row in ipairs(def.timers or {}) do if row.key then timerKeys[row.key] = true end end
        for i, row in ipairs(def.restyles or {}) do
            local where = ("%s.restyles[%s]"):format(tostring(def.id), tostring(row.key or i))
            rowKey("restyle", row, i)
            if type(row.timer) ~= "string" then
                errs[#errs + 1] = where .. ": a restyle row must name the `timer` it re-labels"
            elseif not timerKeys[row.timer] then
                errs[#errs + 1] = where .. ": `timer` names no timer row ('" .. row.timer .. "')"
            end
            if row.identBy ~= nil and type(row.identBy) ~= "string" then
                errs[#errs + 1] = where .. ": `identBy` must name an event field"
            end
            local variants = row.variants or {}
            if #variants == 0 then
                errs[#errs + 1] = where .. ": a restyle row needs at least one variant"
            end
            for j, v in ipairs(variants) do
                local vw = where .. ".variants[" .. j .. "]"
                if type(v) ~= "table" then
                    errs[#errs + 1] = vw .. ": variant must be a table"
                else
                    if type(v.style) ~= "table" then
                        errs[#errs + 1] = vw .. ": variant has no `style` table"
                    elseif v.style.text == nil and v.style.icon == nil and v.style.color == nil then
                        errs[#errs + 1] = vw .. ": `style` changes nothing (text/icon/colour)"
                    end
                    if type(v.style) == "table" and v.style.color ~= nil
                       and (type(v.style.color) ~= "number" or v.style.color < 1
                            or v.style.color > API.COLOR_MAX) then
                        errs[#errs + 1] = vw .. ": style colour out of range 1.." .. API.COLOR_MAX
                    end
                    if v.on == nil then
                        errs[#errs + 1] = vw .. ": variant has no trigger"
                    else
                        validateTrigger(errs, vw, v)
                    end
                end
            end
        end
    end

    for i, row in ipairs(def.phases or {}) do
        local where = ("%s.phases[%d]"):format(tostring(def.id), i)
        if row.stage == nil then errs[#errs + 1] = where .. ": phase row has no stage" end
        if row.on then validateTrigger(errs, where, row) end
    end

    for i, row in ipairs(def.states or {}) do
        local where = ("%s.states[%s]"):format(tostring(def.id), tostring(row.key or i))
        rowKey("state", row, i)
        for j, tr in ipairs(row.transitions or {}) do
            validateTrigger(errs, where .. ".transitions[" .. j .. "]", tr)
            if tr.to == nil then errs[#errs + 1] = where .. ".transitions[" .. j .. "]: no `to` state" end
        end
    end

    if def.special ~= nil and type(def.special) ~= "string" and type(def.special) ~= "table" then
        errs[#errs + 1] = tostring(def.id) .. ": `special` must be a module id or a list of them"
    end
    if def.legacy ~= nil then
        if type(def.legacy) ~= "table" or not def.legacy.raidId or not def.legacy.bossId then
            errs[#errs + 1] = tostring(def.id) .. ": `legacy` needs { raidId=, bossId= }"
        end
    end
    -- W4b extension 24.
    local kms = def.combat and def.combat.killMinStage
    if kms ~= nil and (type(kms) ~= "number" or kms < 1) then
        errs[#errs + 1] = tostring(def.id) .. ": `combat.killMinStage` must be a stage number >= 1"
    end
    -- W4b extension 25.
    local pc = d.pullCountdown
    if pc ~= nil then
        local pw = tostring(def.id) .. ".detect.pullCountdown"
        if type(pc) ~= "table" then
            errs[#errs + 1] = pw .. ": must be a table"
        else
            if type(pc.seconds) ~= "number" or pc.seconds <= 0 then
                errs[#errs + 1] = pw .. ": needs a positive `seconds`"
            end
            -- W4a extension 29: a creature DEATH is a legal source too. Ragnaros's RP
            -- window is measured from Majordomo dying and the spec gives no chat line
            -- for it, so "a chat line" is no longer the whole admissible set.
            if pc.creatureDeath ~= nil and type(pc.creatureDeath) ~= "number"
               and type(pc.creatureDeath) ~= "table" then
                errs[#errs + 1] = pw .. ": `creatureDeath` must be a creature id (or a list)"
            end
            if not (pc.yell or pc.yellFind or pc.emote or pc.emoteFind or pc.say
                    or pc.sayFind or pc.creatureDeath) then
                errs[#errs + 1] = pw .. ": needs a chat line or a creature death to start from"
            end
        end
    end
    return errs
end

-- ── Compilation ───────────────────────────────────────────────────────────────
-- Builds a trigger index so runtime dispatch is a table lookup, not a linear
-- sweep of every row in the encounter.
local function indexTrigger(enc, tr, consumer)
    if type(tr) ~= "table" or tr.on == nil then return end
    local bucket = enc.index[tr.on]
    if not bucket then bucket = {}; enc.index[tr.on] = bucket end
    bucket[#bucket + 1] = { trigger = tr, consumer = consumer }
end

-- W4d extension 1: a row's `cancel` / `cancels` triggers unschedule that row's
-- pending DEFERRED acts. Indexed for every row kind, because "cancel the pre-warning
-- if the boss dies" is not a warning-only rule.
local function indexCancels(enc, row)
    if row.cancel then indexTrigger(enc, row.cancel, { kind = "cancel", row = row }) end
    for _, tr in ipairs(row.cancels or {}) do
        indexTrigger(enc, tr, { kind = "cancel", row = row })
    end
end

local function compile(enc)
    enc.index    = {}
    enc.rowsByKey = {}
    for _, row in ipairs(enc.timers or {}) do
        enc.rowsByKey[row.key] = row
        indexTrigger(enc, row.start,   { kind = "timer", row = row, act = "start" })
        indexTrigger(enc, row.restart, { kind = "timer", row = row, act = "restart" })
        indexTrigger(enc, row.stop,    { kind = "timer", row = row, act = "stop" })
        for _, tr in ipairs(row.starts   or {}) do indexTrigger(enc, tr, { kind = "timer", row = row, act = "start" }) end
        for _, tr in ipairs(row.restarts or {}) do indexTrigger(enc, tr, { kind = "timer", row = row, act = "restart" }) end
        for _, tr in ipairs(row.stops    or {}) do indexTrigger(enc, tr, { kind = "timer", row = row, act = "stop" }) end
        indexCancels(enc, row)
    end
    for _, row in ipairs(enc.warnings or {}) do
        enc.rowsByKey[row.key] = row
        if row.trigger then indexTrigger(enc, row.trigger, { kind = "warning", row = row }) end
        for _, tr in ipairs(row.triggers or {}) do
            indexTrigger(enc, tr, { kind = "warning", row = row })
        end
        indexCancels(enc, row)
    end
    for _, row in ipairs(enc.schedule or {}) do
        if row.key then enc.rowsByKey[row.key] = row end
    end
    for _, row in ipairs(enc.scans or {}) do
        enc.rowsByKey[row.key] = row
        if row.on then indexTrigger(enc, row.on, { kind = "scan", row = row }) end
        if row.stop then indexTrigger(enc, row.stop, { kind = "scanstop", row = row }) end
    end
    for _, row in ipairs(enc.counters or {}) do
        enc.rowsByKey[row.key] = row
        indexCancels(enc, row)
        if row.inc then indexTrigger(enc, row.inc, { kind = "counter", row = row, act = "inc" }) end
        if row.dec then indexTrigger(enc, row.dec, { kind = "counter", row = row, act = "dec" }) end
        if row.reset then indexTrigger(enc, row.reset, { kind = "counter", row = row, act = "reset" }) end
        for _, tr in ipairs(row.incs   or {}) do indexTrigger(enc, tr, { kind = "counter", row = row, act = "inc" }) end
        for _, tr in ipairs(row.resets or {}) do indexTrigger(enc, tr, { kind = "counter", row = row, act = "reset" }) end
    end
    -- W4c extension 12: rosters index exactly like counters — three acts, ordinary
    -- triggers, and the row key is the option key its display hangs from.
    for _, row in ipairs(enc.rosters or {}) do
        enc.rowsByKey[row.key] = row
        indexCancels(enc, row)
        if row.add    then indexTrigger(enc, row.add,    { kind = "roster", row = row, act = "add" }) end
        if row.remove then indexTrigger(enc, row.remove, { kind = "roster", row = row, act = "remove" }) end
        if row.clear  then indexTrigger(enc, row.clear,  { kind = "roster", row = row, act = "clear" }) end
        for _, tr in ipairs(row.adds    or {}) do indexTrigger(enc, tr, { kind = "roster", row = row, act = "add" }) end
        for _, tr in ipairs(row.removes or {}) do indexTrigger(enc, tr, { kind = "roster", row = row, act = "remove" }) end
        for _, tr in ipairs(row.clears  or {}) do indexTrigger(enc, tr, { kind = "roster", row = row, act = "clear" }) end
    end
    -- A phase row IS its own trigger, except that its `stage` field is the stage to
    -- MOVE TO, never a stage filter. Copy the row into a synthetic trigger with
    -- `stage`/`pre` stripped; a phase that should only fire while already in a given
    -- stage declares `whenStage` ("phase 3 soon at <= 48 % IN PHASE 2").
    for i, row in ipairs(enc.phases or {}) do
        local tr = {}
        for k, v in pairs(row) do
            if k ~= "stage" and k ~= "pre" and k ~= "whenStage" then tr[k] = v end
        end
        if row.whenStage ~= nil then tr.stage = row.whenStage end
        indexTrigger(enc, tr, { kind = "phase", row = row, act = i })
    end
    for _, row in ipairs(enc.states or {}) do
        enc.rowsByKey[row.key] = row
        indexCancels(enc, row)
        for _, tr in ipairs(row.transitions or {}) do
            indexTrigger(enc, tr, { kind = "state", row = row, transition = tr })
        end
    end
    for _, row in ipairs(enc.icons or {}) do
        enc.rowsByKey[row.key] = row
        if row.on then indexTrigger(enc, row.on, { kind = "icon", row = row }) end
    end
    -- W4b extension 19. Each VARIANT is its own trigger carrying its own style, so the
    -- dispatcher never has to search the row for "which identity did this event mean".
    for _, row in ipairs(enc.restyles or {}) do
        enc.rowsByKey[row.key] = row
        indexCancels(enc, row)
        for _, v in ipairs(row.variants or {}) do
            indexTrigger(enc, v, { kind = "restyle", row = row, style = v.style })
        end
    end
    return enc
end

-- ── Registration ──────────────────────────────────────────────────────────────
function Addon:RegisterEncounter(def)
    local errs = API.Validate(def)
    if #errs > 0 then
        for _, e in ipairs(errs) do
            if Addon.Telemetry then
                Addon.Telemetry.Write("api.validate", { enc = def and def.id, reason = e })
            end
        end
        return nil, errs
    end

    def.detect  = def.detect  or {}
    def.combat  = def.combat  or {}
    def.timers  = def.timers  or {}
    def.warnings = def.warnings or {}
    def.scans   = def.scans   or {}
    def.phases  = def.phases  or {}
    def.counters = def.counters or {}
    def.states  = def.states  or {}
    def.icons   = def.icons   or {}
    def.schedule = def.schedule or {}
    def.rosters = def.rosters or {}
    def.restyles = def.restyles or {}
    def.creatureIds   = listify(def.creatureId) or {}
    def.encounterIds  = listify(def.encounterId) or {}
    def.zones         = listify(def.zone) or {}
    def.specials      = listify(def.special) or {}
    compile(def)

    if Addon.encountersById[def.id] then
        for i, e in ipairs(Addon.encounters) do
            if e.id == def.id then Addon.encounters[i] = def break end
        end
    else
        Addon.encounters[#Addon.encounters + 1] = def
    end
    Addon.encountersById[def.id] = def

    for _, cid in ipairs(def.creatureIds)  do addTo(Addon.encByCreature, cid, def) end
    for _, eid in ipairs(def.encounterIds) do addTo(Addon.encByEncounterId, eid, def) end
    for _, z   in ipairs(def.zones)        do addTo(Addon.encByZone, z, def) end
    return def, errs
end

function Addon:GetEncounter(id) return Addon.encountersById[id] end
function Addon:GetEncounters() return Addon.encounters end

-- Option key for a row. Everything user-facing (enable/disable, style, sound) is
-- addressed by this; W5's options surface and the SavedVariables overrides key on it.
function API.OptionKey(encId, rowKey) return tostring(encId) .. ":" .. tostring(rowKey) end

-- Ship-off defaults + role gate + dynamic class default (ENCOUNTERS SPEC §1.4).
-- The engine owns the DEFAULT decision; the resolvers answer "is this player a
-- tank / can this player dispel a curse / what class is this" on a client with no
-- specialization API.
--
-- W2 FILLED THESE. They were nil stubs in wave 1; svc_era.lua's Era.Init installs
-- Era.ResolveRole and Era.Class over them (ENGINE SPEC §5.4 tank/healer derivation,
-- §10.23 talent-tab spec). They remain overridable — the harness swaps in fixtures
-- to drive role-gated rows deterministically.
Addon.RoleResolver  = nil   -- function(gateString) -> boolean   (svc_era.lua)
Addon.ClassResolver = nil   -- function() -> "WARLOCK" etc.      (svc_era.lua)

function API.RowDefault(row)
    if row.default ~= nil then return row.default and true or false end
    if row.classDefault then
        local f = Addon.ClassResolver
        if type(f) ~= "function" then return false end
        return f() == row.classDefault
    end
    if row.role then
        local f = Addon.RoleResolver
        if type(f) ~= "function" then return true end   -- no resolver yet: show it
        return f(row.role) and true or false
    end
    return true
end

function API.IsRowEnabled(encId, row)
    local db = Addon.db
    local key = API.OptionKey(encId, row.key)
    if db and type(db.mechanics) == "table" then
        local o = db.mechanics[key]
        if o and o.masterEnabled ~= nil then return o.masterEnabled and true or false end
    end
    return API.RowDefault(row)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  C. ENCOUNTER RUNTIME (one per engagement) — stage register, counters, states,
--     anti-spam, timer instances, and the trigger router.
-- ══════════════════════════════════════════════════════════════════════════════

local Runtime = {}
Runtime.__index = Runtime
API.Runtime = Runtime

function API.NewRuntime(def, ctx)
    local rt = setmetatable({}, Runtime)
    rt.def       = def
    rt.id        = def.id
    rt.stage     = 1
    rt.totality  = 0
    rt.counters  = {}
    rt.states    = {}
    rt.antispam  = {}
    rt.timers    = {}
    rt.healthFired = {}
    rt.dedupe    = {}       -- W4d: per-trigger "fire once per distinct value" sets
    rt.rosters   = {}       -- W4c: rosterKey -> { [name] = { name=, stacks=, at= } }
    rt.rosterN   = {}       -- W4c: rosterKey -> live member count
    rt.rateLog   = {}       -- W4c: counterKey -> ring of increment timestamps
    rt.stateAt   = {}       -- W4c: stateKey -> when it entered its current value
    rt.engaged   = true
    rt.pullTime  = (ctx and ctx.pullTime) or (Addon.Sched and Addon.Sched:Now()) or 0
    rt.difficulty = ctx and ctx.difficulty
    rt.trigger   = ctx and ctx.trigger
    for _, row in ipairs(def.states) do
        rt.states[row.key] = row.initial or "initial"
        rt.stateAt[row.key] = rt.pullTime
    end
    for _, row in ipairs(def.counters) do rt.counters[row.key] = row.from or 0 end
    for _, row in ipairs(def.rosters or {}) do rt.rosters[row.key] = {}; rt.rosterN[row.key] = 0 end
    return rt
end

function Runtime:Now() return Addon.Sched:Now() end

-- ── Stage register (ENGINE SPEC §8.5) ─────────────────────────────────────────
-- Absolute number, or 0 to increment by one, or 0.5 to increment by a half.
-- A separate TOTALITY counter increments on every set. Setting a stage while not
-- engaged is silently ignored. Every set broadcasts.
function Runtime:SetStage(v)
    if not self.engaged then return false end
    if v == 0 then self.stage = self.stage + 1
    elseif v == 0.5 then self.stage = self.stage + 0.5
    else self.stage = v end
    self.totality = self.totality + 1
    Addon:FireEngineEvent("ENGINE_STAGE", self.id, self.stage, self.totality)
    -- W4d extension 6. `stage` has always been in the trigger vocabulary; nothing
    -- ever ROUTED one, so "start this bar when the phase changes" (Kel'Thuzad's whole
    -- phase-2 ability set, Thaddius's berserk) was declarable but dead. It fires now.
    self:RouteSynthetic({ on = "stage", stage = self.stage, totality = self.totality })
    return true
end

-- Synthetic events are engine-originated, so a badly-written state machine could
-- ping-pong. Depth-capped rather than forbidden: a transition that legitimately
-- drives a phase change is normal encounter shape.
Runtime.SYNTH_MAX_DEPTH = 4
function Runtime:RouteSynthetic(ev)
    local d = (self._synthDepth or 0)
    if d >= Runtime.SYNTH_MAX_DEPTH then
        if Addon.Telemetry then
            Addon.Telemetry.Write("api.validate",
                { enc = self.id, reason = "synthetic routing depth cap", key = tostring(ev.on) })
        end
        return 0
    end
    self._synthDepth = d + 1
    local okc, n = pcall(Runtime.Route, self, ev)
    self._synthDepth = d
    return okc and n or 0
end

function Runtime:GetStage() return self.stage, self.totality end

-- Query API: equality / less-than / greater-than / not-equal against stage or totality.
function Runtime:StageIs(op, value, useTotality)
    local s = useTotality and self.totality or self.stage
    if op == "==" or op == "eq" then return s == value end
    if op == "<"  or op == "lt" then return s <  value end
    if op == ">"  or op == "gt" then return s >  value end
    if op == "~=" or op == "ne" then return s ~= value end
    if op == "<=" then return s <= value end
    if op == ">=" then return s >= value end
    return false
end

-- ── Anti-spam (ENCOUNTERS SPEC §1.6) ──────────────────────────────────────────
-- Returns true when the caller may proceed (i.e. the key is NOT throttled).
function Runtime:AntiSpam(key, seconds)
    if not seconds or seconds <= 0 then return true end
    local now = self:Now()
    local last = self.antispam[key]
    if last and (now - last) < seconds then return false end
    self.antispam[key] = now
    return true
end

-- ── Counters ──────────────────────────────────────────────────────────────────
-- Counter values are mirrored into the legacy `Addon._mechCount` contract under the
-- row's option key (W4d extension 8): the shipped Four Horsemen tracker reads
-- `Addon._mechCount["naxxramas:fourhorsemen:markcd"]` for its header, and the port
-- must not touch that file.
local function mirrorCount(rt, key, value)
    Addon._mechCount = Addon._mechCount or {}
    Addon._mechCount[API.OptionKey(rt.id, key)] = value
end

-- W4c extension 14: the rate ring. Every increment of a rate-bearing counter stamps
-- the clock into a bounded ring; `Rate` reads hits-per-second off it.
local function rateStamp(rt, key, row)
    if not (row and row.rate) then return end
    local cap = row.rate.fallback or row.rate.window
    local ring = rt.rateLog[key]
    if not ring then ring = { n = 0 }; rt.rateLog[key] = ring end
    ring.n = ring.n + 1
    ring[((ring.n - 1) % cap) + 1] = rt:Now()
    ring.cap = cap
end

-- W4a extension 28. A counter change is an EVENT. `on = "counter"` has been in the
-- published vocabulary since wave 1 and nothing ever routed one, so "when this count
-- reaches N" could be declared and could never fire — the same hole W4d extension 6
-- closed for `stage` and `state`.
--
-- Only DECLARED counter rows are routed. `__warn:` and `__occ:` are engine
-- bookkeeping under the same table, and routing them would put a synthetic event on
-- every counting warning and every timer occurrence for no reader.
local function routeCounter(rt, key, value, delta)
    if not (rt.def.rowsByKey and rt.def.rowsByKey[key]) then return 0 end
    return rt:RouteSynthetic({ on = "counter", key = key, value = value, delta = delta })
end

function Runtime:Count(key, delta)
    local v = (self.counters[key] or 0) + (delta or 1)
    self.counters[key] = v
    mirrorCount(self, key, v)
    if (delta or 1) > 0 then
        rateStamp(self, key, self.def.rowsByKey and self.def.rowsByKey[key])
    end
    Addon:FireEngineEvent("COUNTER", self.id, key, v, delta or 1)
    routeCounter(self, key, v, delta or 1)
    return v
end

function Runtime:GetCount(key) return self.counters[key] or 0 end

function Runtime:ResetCount(key, to)
    local row = self.def.rowsByKey and self.def.rowsByKey[key]
    self.counters[key] = to or (row and row.from) or 0
    self.rateLog[key] = nil
    Addon:FireEngineEvent("COUNTER", self.id, key, self.counters[key], 0)
    routeCounter(self, key, self.counters[key], 0)
    return self.counters[key]
end

-- Hits per second over the last `window` increments, widening to `fallback`
-- increments while the narrow window has not filled yet. Returns nil — never zero —
-- when there is not enough evidence to answer (LESSON CLASS 5: a truthy zero here
-- would render "0.0 frost hits/sec" over a raid that is in fact hitting hard).
function Runtime:Rate(key)
    local row = self.def.rowsByKey and self.def.rowsByKey[key]
    if not (row and row.rate) then return nil end
    local ring = self.rateLog[key]
    if not ring or ring.n < 2 then return nil end
    local cap    = ring.cap or row.rate.window
    local have   = ring.n < cap and ring.n or cap
    local window = row.rate.window
    local use    = have >= window and window or have
    -- Walk back `use` stamps from the newest, oldest first.
    local newest = ((ring.n - 1) % cap) + 1
    local oldestIdx = ((newest - use) % cap) + 1
    local t1, t0 = ring[newest], ring[oldestIdx]
    if not (t1 and t0) or t1 <= t0 then return nil end
    return (use - 1) / (t1 - t0)
end

-- ── W4c extension 12: rosters ─────────────────────────────────────────────────
-- A membership set with a stack count per member. Add is idempotent on the NAME and
-- updates the stack, which is what makes an APPLIED / APPLIED_DOSE pair a single
-- "Bob is at 6" rather than two entries.
function Runtime:RosterAdd(key, name, stacks)
    if not name then return false end
    local r = self.rosters[key]
    if not r then r = {}; self.rosters[key] = r; self.rosterN[key] = 0 end
    local e = r[name]
    if not e then
        e = { name = name, at = self:Now() }
        r[name] = e
        self.rosterN[key] = (self.rosterN[key] or 0) + 1
    end
    e.stacks = stacks or e.stacks or 1
    e.seen = self:Now()
    Addon:FireEngineEvent("ROSTER", self.id, key, "add", name, e.stacks, self.rosterN[key])
    self:RouteSynthetic({ on = "roster", key = key, added = true, destName = name,
                          amount = e.stacks, count = self.rosterN[key] })
    return true
end

function Runtime:RosterRemove(key, name)
    local r = self.rosters[key]
    if not (r and name and r[name]) then return false end
    local stacks = r[name].stacks
    r[name] = nil
    self.rosterN[key] = math.max(0, (self.rosterN[key] or 1) - 1)
    Addon:FireEngineEvent("ROSTER", self.id, key, "remove", name, stacks, self.rosterN[key])
    self:RouteSynthetic({ on = "roster", key = key, added = false, destName = name,
                          amount = stacks, count = self.rosterN[key] })
    return true
end

function Runtime:RosterClear(key)
    local r = self.rosters[key]
    if not r then return false end
    for name in pairs(r) do r[name] = nil end
    self.rosterN[key] = 0
    Addon:FireEngineEvent("ROSTER", self.id, key, "clear", nil, nil, 0)
    self:RouteSynthetic({ on = "roster", key = key, cleared = true, count = 0 })
    return true
end

function Runtime:GetRoster(key) return self.rosters[key] end
function Runtime:RosterCount(key) return self.rosterN[key] or 0 end
function Runtime:RosterHas(key, name)
    local r = self.rosters[key]
    return (r and name and r[name]) and true or false
end

-- ── State machines ────────────────────────────────────────────────────────────
function Runtime:SetState(key, to)
    local from = self.states[key]
    if from == to then return false end
    self.states[key] = to
    -- W4c extension 18: dwell time. "Viscidus swung at someone MORE THAN 5 s after he
    -- froze" is a question about the machine, so the machine records when it arrived.
    self.stateAt[key] = self:Now()
    Addon:FireEngineEvent("STATE", self.id, key, from, to)
    -- W4d extension 6, the other half: a state transition is an event. This is what
    -- makes "when BOTH adds are dead" (Thaddius) a declared rule instead of code.
    self:RouteSynthetic({ on = "state", key = key, from = from, to = to })
    return true
end


function Runtime:GetState(key) return self.states[key] end

-- ── Timer instances ───────────────────────────────────────────────────────────
function Runtime:Timer(key)
    local t = self.timers[key]
    if t then return t end
    local row = self.def.rowsByKey and self.def.rowsByKey[key]
    if not row or not Addon.Timers then return nil end
    t = Addon.Timers.New({
        id       = API.OptionKey(self.id, key),
        key      = key,
        encId    = self.id,
        kind     = row.kind or "cd",
        duration = row.duration,
        spellId  = type(row.spellId) == "table" and row.spellId[1] or row.spellId,
        text     = row.text, icon = row.icon, color = row.color,
        count    = row.count, allowDouble = row.allowDouble,
        keep     = row.keep, fade = row.fade,
        nameplate = row.nameplate,
        perTarget = row.perTarget,
        requiresCombat = row.requiresCombat,
        countdown = row.countdown,
        owner    = self,
    })
    self.timers[key] = t
    return t
end

-- Resolve the duration for the Nth occurrence of a timer row. This is where the
-- encounter grammar's four value shapes collapse into one number/variance string:
--   pull            first occurrence differs from the recurring cd
--   phaseDuration   per-stage override (Thaddius P2, Kel'Thuzad P2)
--   sequence        alternating table (Loatheb doom 29.1/32.4)
--   sequenceFrom    the sequence CHANGES at the Nth occurrence (Loatheb's 7th doom)
--   schedule        a hard-coded cycle whose last entry repeats (Noth teleports)
function API.ResolveDuration(row, occurrence, stage)
    occurrence = occurrence or 1
    if row.schedule and #row.schedule > 0 then
        return row.schedule[occurrence] or row.schedule[#row.schedule]
    end
    if row.sequenceFrom then
        local bestAt, bestSeq
        for at, seq in pairs(row.sequenceFrom) do
            if occurrence >= at and (bestAt == nil or at > bestAt) then bestAt, bestSeq = at, seq end
        end
        if bestSeq then
            local i = ((occurrence - bestAt) % #bestSeq) + 1
            return bestSeq[i]
        end
    end
    if occurrence <= 1 and row.pull ~= nil then return row.pull end
    if row.phaseDuration and stage ~= nil and row.phaseDuration[stage] ~= nil then
        return row.phaseDuration[stage]
    end
    if row.sequence and #row.sequence > 0 then
        local i = ((occurrence - 2) % #row.sequence) + 1
        if i < 1 then i = 1 end
        return row.sequence[i]
    end
    return row.duration
end

-- ── Trigger routing ───────────────────────────────────────────────────────────
-- `ev` is the normalised event table the lifecycle layer hands us:
--   { on=, spellId=, sourceGUID=, sourceId=, destGUID=, destId=, destName=,
--     sourceName=, amount=, school=, text=, pct=, stage=, unit= }
-- W4d extension 2 helpers. Each is a pure predicate over (trigger spec, event).
local function inList(want, got)
    if type(want) == "table" then
        for _, v in ipairs(want) do if v == got then return true end end
        return false
    end
    return want == got
end

-- `index` selects ticks of a scheduled loop: an exact tick, a list of ticks, every
-- other tick (`odd` / `even` — the shape of every two-state scripted loop), or an
-- arbitrary stride.
local function indexMatches(spec, i)
    if i == nil then return false end
    if type(spec) == "number" then return spec == i end
    if type(spec) ~= "table" then return false end
    if spec.odd  then return (i % 2) == 1 end
    if spec.even then return (i % 2) == 0 end
    if spec.every then
        local off = spec.offset or 0
        return i >= off and ((i - off) % spec.every) == 0
    end
    return inList(spec, i)
end

local function counterMatches(rt, spec)
    local list = spec[1] and spec or { spec }
    for _, c in ipairs(list) do
        local v = rt.counters[c.key] or 0
        if c.eq  ~= nil and v ~= c.eq  then return false end
        if c.min ~= nil and v <  c.min then return false end
        if c.max ~= nil and v >  c.max then return false end
    end
    return true
end

local function triggerMatches(rt, tr, ev)
    if tr.spellId ~= nil then
        if type(tr.spellId) == "table" then
            local hit = false
            for _, id in ipairs(tr.spellId) do if id == ev.spellId then hit = true break end end
            if not hit then return false end
        elseif tr.spellId ~= ev.spellId then
            return false
        end
    end
    if tr.creatureId ~= nil then
        local want, got = tr.creatureId, ev.sourceId or ev.destId or ev.creatureId
        if type(want) == "table" then
            local hit = false
            for _, id in ipairs(want) do if id == got then hit = true break end end
            if not hit then return false end
        elseif want ~= got then
            return false
        end
    end
    if tr.dest == "player" and not ev.destIsPlayer then return false end
    -- W4c: the other arm of the same question. "Another player is at 5 stacks" is a
    -- different rule from "you are", and both ship on the same four bosses.
    if tr.dest == "other" and ev.destIsPlayer then return false end
    if tr.source == "player" and not ev.sourceIsPlayer then return false end
    if tr.source == "other" and ev.sourceIsPlayer then return false end
    if tr.source == "pet" and not ev.sourceIsPet then return false end
    -- W4c extension 16.
    if tr.missType ~= nil and not inList(tr.missType, ev.missType) then return false end
    if tr.school ~= nil then
        local s = ev.school or 0
        if s % (tr.school * 2) < tr.school then return false end   -- bitmask test, Lua-5.1 safe
    end
    if tr.stacks ~= nil and (ev.amount or 0) < tr.stacks then return false end
    if tr.stage ~= nil and rt.stage ~= tr.stage then return false end
    if tr.state ~= nil and rt.states[tr.stateKey or tr.key] ~= tr.state then return false end
    if tr.pct ~= nil and (ev.pct == nil or ev.pct > tr.pct) then return false end
    -- W4c: the LOWER edge of a health WINDOW. Skeram's split pre-warnings are windows
    -- (81-77, 56-52, 31-27), not thresholds — the spec's own words — so a threshold
    -- that stays armed all the way to 1 % would announce "split soon" during the
    -- execute. `pct` is the ceiling; `pctMin` is the floor.
    if tr.pctMin ~= nil and (ev.pct == nil or ev.pct < tr.pctMin) then return false end
    if tr.text ~= nil then
        local want, got = tr.text, ev.text or ""
        if type(want) == "table" then
            local hit = false
            for _, s in ipairs(want) do if s == got then hit = true break end end
            if not hit then return false end
        elseif want ~= got then
            return false
        end
    end
    if tr.textFind ~= nil then
        local got = ev.text or ""
        local want = type(tr.textFind) == "table" and tr.textFind or { tr.textFind }
        local hit = false
        for _, s in ipairs(want) do if got:find(s, 1, true) then hit = true break end end
        if not hit then return false end
    end
    if tr.textPattern ~= nil then
        local got = ev.text or ""
        local want = type(tr.textPattern) == "table" and tr.textPattern or { tr.textPattern }
        local hit = false
        for _, s in ipairs(want) do if got:match(s) then hit = true break end end
        if not hit then return false end
    end

    -- ── W4d extension 2: the new filters ──────────────────────────────────────
    -- `fromKey` scopes a synthetic event to the row that raised it: schedules, scan
    -- results and state changes all carry the originating row's key, and without this
    -- every `on = "schedule"` row in an encounter would answer every other row's tick.
    if tr.fromKey ~= nil and ev.key ~= tr.fromKey then return false end
    if tr.index ~= nil and not indexMatches(tr.index, ev.index) then return false end
    if tr.spellName ~= nil and not inList(tr.spellName, ev.spellName) then return false end
    if tr.where ~= nil then
        for field, want in pairs(tr.where) do
            local got = ev[field]
            if type(want) == "boolean" then
                if (got and true or false) ~= want then return false end
            elseif not inList(want, got) then
                return false
            end
        end
    end
    if tr.states ~= nil then
        for k, want in pairs(tr.states) do
            if rt.states[k] ~= want then return false end
        end
    end
    if tr.counter ~= nil and not counterMatches(rt, tr.counter) then return false end
    -- W4b extension 23. A MISSING field fails the test rather than passing it: an
    -- unanswerable "is his max health >= 1,079,325" must not read as "yes, hard mode".
    if tr.atLeast ~= nil then
        for field, want in pairs(tr.atLeast) do
            local got = ev[field]
            if type(got) ~= "number" or got < want then return false end
        end
    end
    if tr.atMost ~= nil then
        for field, want in pairs(tr.atMost) do
            local got = ev[field]
            if type(got) ~= "number" or got > want then return false end
        end
    end
    -- W4c extension 12: "…and this player is (not) already in the set".
    if tr.inRoster ~= nil and not rt:RosterHas(tr.inRoster, ev.destName) then return false end
    if tr.notInRoster ~= nil and rt:RosterHas(tr.notInRoster, ev.destName) then return false end
    -- W4c extension 18: how long the machine has been where it is.
    if tr.minStateAge ~= nil then
        local k = tr.stateKey or tr.fromKey or tr.key
        local at = k and rt.stateAt[k]
        if not at or (rt:Now() - at) < tr.minStateAge then return false end
    end
    -- W4c extension 15: one predicate or a list, all of which must agree.
    if not conditionsPass(rt, ev, tr, "condition", true) then return false end
    if not conditionsPass(rt, ev, tr, "conditionNot", false) then return false end
    -- `dedupe` is LAST because it is the only filter with a side effect: it records
    -- the value it just admitted. ("<horseman> died, de-duplicated by GUID".)
    if tr.dedupe ~= nil then
        local v = ev[tr.dedupe]
        if v ~= nil then
            local set = rt.dedupe[tr]
            if not set then set = {}; rt.dedupe[tr] = set end
            if set[v] then return false end
            set[v] = true
        end
    end
    return true
end
API.TriggerMatches = triggerMatches
API.IndexMatches   = indexMatches

-- Dispatch one normalised event into an engagement. Returns the number of rows
-- that acted, which is what the harness asserts against.
function Runtime:Route(ev)
    if not self.engaged then return 0 end
    local bucket = self.def.index[ev.on]
    if not bucket then return 0 end
    local acted = 0
    for i = 1, #bucket do
        local entry = bucket[i]
        if triggerMatches(self, entry.trigger, ev) then
            if self:Act(entry, ev) then acted = acted + 1 end
        end
    end
    return acted
end

local function fmtCount(text, n)
    if not text then return text end
    if text:find("%%d") then return (text:format(n)) end
    return text .. " " .. tostring(n)
end

-- W4d extension 1. A deferred act is an ordinary act that runs later, scheduled with
-- the RUNTIME as its owner (so combat end sweeps it) and the ROW KEY as its leading
-- argument (so §3.2's partial-match Unschedule can cancel a row's pending acts
-- without knowing which trigger raised them).
local function deferredAct(rowKey, entry, ev, rt)
    if not rt.engaged then return end
    return rt:Act(entry, ev, true)
end
API.DeferredAct = deferredAct

function Runtime:Act(entry, ev, deferred)
    local c, row = entry.consumer, entry.consumer.row
    local tr = entry.trigger

    if c.kind == "cancel" then
        -- Cancels never throttle and never defer: they exist to unmake a schedule.
        local n = Addon.Sched:Unschedule(deferredAct, self, row.key)
        return n > 0
    end

    if not deferred then
        -- W4c extension 17: `antispamBy` widens the throttle key with a value off the
        -- event, so a per-mob window is per-mob and not per-encounter.
        if tr.antispam then
            local akey = tostring(row.key) .. ":" .. tostring(tr.on)
            if tr.antispamBy then akey = akey .. ":" .. tostring(ev and ev[tr.antispamBy]) end
            if not self:AntiSpam(akey, tr.antispam) then return false end
        end
        if row.antispam and not self:AntiSpam(row.key, row.antispam) then return false end

        -- `row.delay` on a SCAN row already means something else (svc_scan's own
        -- pre-scan delay, §5.3), so only the trigger-level form applies there.
        local delay = tr.delay or (c.kind ~= "scan" and row.delay or nil)
        if delay and delay > 0 then
            Addon.Sched:Schedule(delay, deferredAct, self, row.key, entry, ev, self)
            return true
        end
    end

    if c.kind == "timer" then
        if not Addon.API.IsRowEnabled(self.id, row) then return false end
        local t = self:Timer(row.key)
        if not t then return false end
        -- BAR IDENTITY (§4.1) is timerId + arguments, so the identity argument must
        -- be supplied ONLY for timers that genuinely have one bar per subject.
        -- Passing a per-event value (a target name, a GUID) to a plain cooldown
        -- timer would mint a NEW bar every cast — which silently disables the
        -- early-refresh tripwire, because there would never be a bar to measure.
        -- W4b extension 20 generalises the two identities that already existed: a bar
        -- may be per-target (destName), per-mob (sourceGUID) or per ANY event field.
        local ident
        if row.perTarget then ident = ev.destName
        elseif row.nameplate then ident = ev.sourceGUID or ev.destGUID
        elseif row.identBy then ident = ev[row.identBy] end
        if c.act == "stop" then
            if ident ~= nil then t:Stop(ident) else t:Stop() end
            return true
        end
        local n = (self.counters["__occ:" .. row.key] or 0) + 1
        self.counters["__occ:" .. row.key] = n
        if row.count then mirrorCount(self, row.key, n) end
        -- W4d extension 3: a trigger may carry the duration for ITS path. One bar can
        -- then have several cadences (Noth's curse: a pull window, a recurring
        -- variance, and a fixed value on each return to the room).
        local dur = tr.duration or API.ResolveDuration(row, n, self.stage)
        if ident ~= nil then t:Start(dur, ident) else t:Start(dur) end
        return true
    end

    if c.kind == "warning" then
        if row.key and not Addon.API.IsRowEnabled(self.id, row) then return false end
        -- W4b extension 26. The spec's "replaces the announce when enabled": the plain
        -- row goes quiet while the sharper one is switched on, and comes back the
        -- moment the player switches that one off.
        if row.suppressedBy then
            local other = self.def.rowsByKey and self.def.rowsByKey[row.suppressedBy]
            if other and Addon.API.IsRowEnabled(self.id, other) then return false end
        end
        local text = row.text or row.key
        -- W4c: STACK interpolation, the sibling of W4d's target interpolation. The
        -- spec writes these alerts as "<name> (N)" where N is the debuff's stack, not
        -- the number of times the alert has fired — so `stacks = true` fills `%d` from
        -- the event and `count = true` (which fills it from the fire count) stays
        -- exactly what it was. A row declares one or the other, never both.
        if row.stacks and ev and ev.amount and text:find("%%d") then
            text = (text:gsub("%%d", tostring(ev.amount)))
        end
        if row.count then text = fmtCount(text, self:Count("__warn:" .. row.key)) end
        -- W4d extension 7: the event's target fills a `%s` in the text and rides along
        -- to the batchers, which is what makes "Void Zone on <name>" data.
        local target
        if row.target ~= false then target = ev and (ev.destName or ev.targetName) end
        if target and text:find("%%s") then text = (text:gsub("%%s", target)) end
        if (row.tier or "announce") == "special" then
            Addon:EmitSpecial(self.id, row, text, target)
        else
            Addon:EmitAnnounce(self.id, row, text, target)
        end
        return true
    end

    if c.kind == "counter" then
        if c.act == "reset" then self:ResetCount(row.key)
        elseif c.act == "dec" then self:Count(row.key, -(row.step or 1))
        else self:Count(row.key, row.step or 1) end
        local v = self:GetCount(row.key)
        if row.threshold and row.threshold.at and v >= row.threshold.at and row.threshold.warning then
            local w = self.def.rowsByKey[row.threshold.warning]
            if w and Addon.API.IsRowEnabled(self.id, w) then
                Addon:EmitSpecial(self.id, w, fmtCount(w.text or w.key, v))
            end
        end
        if row.announceAt then
            for _, mark in ipairs(row.announceAt) do
                if v == mark and row.announce then
                    Addon:EmitAnnounce(self.id, row, fmtCount(row.announce, v))
                end
            end
        end
        return true
    end

    if c.kind == "phase" then
        return self:SetStage(row.stage)
    end

    if c.kind == "state" then
        local changed = self:SetState(row.key, tr.to)
        if changed and tr.announce then Addon:EmitAnnounce(self.id, row, tr.announce) end
        if changed and tr.actions then
            for _, a in ipairs(tr.actions) do
                if a.stopTimer then local t = self:Timer(a.stopTimer); if t then t:Stop() end end
                if a.startTimer then
                    local t = self:Timer(a.startTimer)
                    local r = self.def.rowsByKey[a.startTimer]
                    if t then t:Start(r and API.ResolveDuration(r, 1, self.stage)) end
                end
                if a.resetCounter then self:ResetCount(a.resetCounter) end
                if a.resetCounters then
                    for _, k in ipairs(a.resetCounters) do self:ResetCount(k) end
                end
                if a.clearRoster then self:RosterClear(a.clearRoster) end
                if a.stage then self:SetStage(a.stage) end
            end
        end
        return changed
    end

    -- W4c extension 12. Rosters act on the same three verbs everywhere; the STACK
    -- comes off the event, so an APPLIED_DOSE simply overwrites the member's count.
    if c.kind == "roster" then
        if c.act == "clear"  then return self:RosterClear(row.key) end
        local name = ev and (ev.destName or ev.targetName)
        if c.act == "remove" then return self:RosterRemove(row.key, name) end
        return self:RosterAdd(row.key, name, ev and ev.amount)
    end

    if c.kind == "scan" then
        Addon:FireEngineEvent("SCAN_REQUEST", self.id, row, ev)
        return true
    end

    if c.kind == "scanstop" then
        Addon:FireEngineEvent("SCAN_STOP", self.id, row, ev)
        return true
    end

    if c.kind == "icon" then
        Addon:FireEngineEvent("ICON_REQUEST", self.id, row, ev)
        return true
    end

    -- W4b extension 19. The engine decides WHICH identity the evidence means and
    -- publishes it; ui_bars decides how a bar wears it. The announce half of the same
    -- fact is an ordinary warning row on the same trigger — a restyle never speaks.
    if c.kind == "restyle" then
        if not Addon.API.IsRowEnabled(self.id, row) then return false end
        local style = entry.consumer.style
        if not style then return false end
        -- Announce-on-CHANGE, the spec's rule for the vulnerability school: re-seeing
        -- the same school is not news, and re-styling the bar to what it already says
        -- would burn a TIMER_UPDATE every sample of the aura sweep.
        local sig = tostring(style.text) .. "\t" .. tostring(style.icon) .. "\t"
                    .. tostring(style.color)
        local ident = row.identBy and ev and ev[row.identBy] or nil
        local slot  = tostring(row.key) .. "\t" .. tostring(ident)
        self.restyled = self.restyled or {}
        if self.restyled[slot] == sig then return false end
        self.restyled[slot] = sig
        -- THE STATE MOVES FIRST, and the order is load-bearing. The current identity is
        -- state, so a warning row can be gated on it and a timer row can START on it —
        -- which Chromaggus's vulnerability bar does, because the school changing is the
        -- only thing that arms it. Restyling before the state moved would try to
        -- re-label a bar that does not exist yet.
        if row.state ~= false then self:SetState(row.key, style.text or sig) end
        Addon:FireEngineEvent("RESTYLE_REQUEST", self.id, row, style, ev, ident)
        return true
    end
    return false
end

-- Pull-seeded schedules (Noth's teleports, Heigan's dance, Gothik's waves,
-- Chromaggus's two breath pre-warnings, C'Thun's Dark Glare loop).
-- W4d extension 5: the pre-tick value for tick `i`. A number applies to every tick;
-- a list CYCLES, which is how a two-state loop carries a different lead time per
-- direction (Heigan: 15 s before the room ends, 10 s before the dance ends).
local function preAt(row, i)
    local p = row.pre
    if p == nil then return nil end
    if type(p) == "number" then return p end
    if #p == 0 then return nil end
    return p[((i - 1) % #p) + 1]
end

function Runtime:StartPullSchedules()
    local S = Addon.Sched
    for _, row in ipairs(self.def.schedule) do
        if Addon.API.IsRowEnabled(self.id, row) then
            if row.gaps then
                -- The pre-tick for tick `i` is scheduled from the PREVIOUS tick (and,
                -- for tick 1, from the pull), because only then is the gap it leads
                -- known. It routes the same event with `pre = true`, so a pre-warning
                -- is an ordinary row with `where = { pre = true }`.
                local function firePre(i)
                    self:Route({ on = "schedule", key = row.key, index = i, pre = true })
                    if row.preAnnounce then
                        Addon:EmitAnnounce(self.id, row, fmtCount(row.preAnnounce, i))
                    end
                end
                local function armPre(i)
                    local p = preAt(row, i)
                    if not p or (row.count and i > row.count) then return end
                    local gap = S.GapAt(row.gaps, i)
                    if gap and gap > p then S:Schedule(gap - p, firePre, self, i) end
                end
                local st
                st = S:LoopTable(row.gaps, function(_, i)
                    self:Route({ on = "schedule", key = row.key, index = i })
                    if row.announce then Addon:EmitAnnounce(self.id, row, fmtCount(row.announce, i)) end
                    if row.count and i >= row.count then S:CancelLoop(st) return end
                    armPre(i + 1)
                end, self, row.immediate)
                armPre(1)
            elseif row.at then
                local list = type(row.at) == "table" and row.at or { row.at }
                for _, t in ipairs(list) do
                    S:Schedule(t, function()
                        self:Route({ on = "schedule", key = row.key })
                        if row.announce then Addon:EmitAnnounce(self.id, row, row.announce) end
                    end, self)
                end
            end
        end
    end
    -- Timers whose start trigger is the pull itself.
    self:Route({ on = "pull" })
end

function Runtime:Teardown()
    self.engaged = false
    for _, t in pairs(self.timers) do t:Stop() end
    Addon.Sched:CancelOwner(self)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  D. THE ESCAPE HATCH — registered special modules (design item 8)
-- ══════════════════════════════════════════════════════════════════════════════
--  modules.lua is UNCHANGED and remains the registration surface for the five
--  shipped Naxx specials. This section preserves the two engine-owned surfaces
--  those modules reach for, with byte-identical signatures, and wires them to the
--  new lifecycle.

Addon._combatHooks = Addon._combatHooks or {}
-- fn(subevent, sourceGUID, sourceID, destGUID, destID, spellID, spellName)
-- ^ VERBATIM the signature the retired engine used. mod_fourhorsemen_tracker.lua
--   registers against exactly this and must keep working untouched.
function Addon:RegisterCombatHook(fn)
    if type(fn) == "function" then Addon._combatHooks[#Addon._combatHooks + 1] = fn end
end

function Addon:FireCombatHooks(subevent, sourceGUID, sourceID, destGUID, destID, spellID, spellName)
    if Addon.IsDebugOnly and Addon:IsDebugOnly() then return 0 end
    local hooks = Addon._combatHooks
    for i = 1, #hooks do
        pcall(hooks[i], subevent, sourceGUID, sourceID, destGUID, destID, spellID, spellName)
    end
    return #hooks
end

-- `Addon.active` is the legacy widget contract: { raidId, bossId, boss, startTime }.
-- The five specials, alerts.lua and options.lua all read it. The new lifecycle
-- keeps it populated so W4d's port is a data change, not a code change.
function API.SetLegacyActive(enc, rt)
    if enc and enc.legacy then
        Addon.active = {
            raidId    = enc.legacy.raidId,
            bossId    = enc.legacy.bossId,
            boss      = enc.legacy.boss or { id = enc.legacy.bossId, name = enc.name },
            startTime = rt and rt.pullTime or (Addon.Sched and Addon.Sched:Now()),
            encId     = enc.id,
        }
    else
        Addon.active = nil
    end
    return Addon.active
end

function API.StartSpecials(enc, rt)
    local started = 0
    if enc.legacy and type(Addon.StartBossModules) == "function" then
        local okc = pcall(Addon.StartBossModules, Addon, enc.legacy.raidId, enc.legacy.bossId)
        if okc then started = started + 1 end
    end
    for _, id in ipairs(enc.specials or {}) do
        for _, def in ipairs(Addon.modules or {}) do
            if def.id == id and type(Addon.StartModule) == "function" then
                pcall(Addon.StartModule, Addon, def)
                started = started + 1
            end
        end
    end
    if type(enc.OnEngage) == "function" then
        pcall(enc.OnEngage, enc, rt, rt and rt.delay or 0,
              rt and rt.trigger == "chat", rt and rt.trigger == "encounter")
    end
    return started
end

function API.StopSpecials(enc, rt, wiped)
    if type(Addon.StopAllModules) == "function" then pcall(Addon.StopAllModules, Addon) end
    if type(enc.OnEnd) == "function" then pcall(enc.OnEnd, enc, rt, wiped) end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  E. THE OPTIONS PROJECTION (W4d extension 9)
-- ══════════════════════════════════════════════════════════════════════════════
--  options.lua reads a raid -> boss -> mechanic tree: `Addon:GetRaids()`, then
--  `raid.bosses[i].mechanics[j]`, and addresses every checkbox by
--  `Addon:MechKey(raidId, bossId, mechId)`. The 1.x data files built that tree by
--  hand; `Addon:RegisterRaid` (core_boot.lua) still REFUSES them, and stays refusing.
--
--  This is the replacement: the tree is PROJECTED from the encounter registry, and
--  the projection is exact rather than approximate because the two key schemes were
--  designed to coincide —
--        API.OptionKey(encId, rowKey)  ==  Addon:MechKey(raidId, bossId, rowKey)
--  when the encounter id is "<raidId>:<bossId>". So a checkbox options.lua writes is
--  the same SavedVariables entry `API.IsRowEnabled` reads, with no adapter between
--  them, and the shipped specials that hard-code a mechanic key (thaddius.lua's
--  "naxxramas:thaddius:polarity", the Four Horsemen tracker's
--  "naxxramas:fourhorsemen:markcd") keep working untouched.
Addon.zones     = Addon.zones or {}      -- ordered array of zone descriptors
Addon.zonesById = Addon.zonesById or {}

-- THE PROJECTED TREE AND ITS FOUR READERS.
--
-- W5 SCAFFOLD RETIREMENT: these lived in core_boot.lua from the wave-1 demolition
-- until now, under a heading that called them "retirement shims". They never were
-- shims — they are the READ SIDE of the projection defined thirty lines below, and
-- W4d already replaced the thing that fills them. Leaving the readers in a file
-- named "boot", labelled transitional, meant every reader of this codebase had to
-- discover that the label was stale. They are here, next to the writer, because
-- this is where they belong: `PublishOptionsTree` assigns these three tables and
-- these four functions are how everything else asks about them.
--
-- Consumers: options.lua (the whole raid/boss drill-down), alerts.lua, svc_scan.lua
-- and the special modules' `bossId` lookups.
Addon.raids     = Addon.raids     or {}
Addon.raidsById = Addon.raidsById or {}
Addon.npcIndex  = Addon.npcIndex  or {}

function Addon:GetRaids()  return Addon.raids end
function Addon:GetRaid(id) return Addon.raidsById[id] end
function Addon:GetBoss(raidId, bossId)
    local r = Addon.raidsById[raidId]
    if not r then return nil end
    for _, b in ipairs(r.bosses or {}) do if b.id == bossId then return b end end
    return nil
end
function Addon:GetBossByNpcID(npcID) return Addon.npcIndex[npcID] end

-- THE 1.x REGISTRATION REFUSAL. Not a shim either — a permanent guard, and it is
-- deliberately a HARD STOP rather than a silent no-op.
--
-- All three 1.x data files (data_naxxramas / data_aq40 / data_bwl) were consumed
-- and deleted across W4b-d, and Molten Core, Onyxia and the world bosses never had
-- one; the RETIRE gate asserts they stay deleted. So there is no caller left inside
-- the addon. It stays because the reasons outlive the files: a third-party or
-- hand-written plugin may still call `Addon:RegisterRaid`, and a silent no-op would
-- be strictly worse than the function not existing — the plugin author would see
-- their raid simply not appear, with nothing to read. A refusal that writes to the
-- telemetry ring is the traceable answer, and it names the successor.
function Addon:RegisterRaid(def)
    if Addon.Telemetry then
        Addon.Telemetry.Write("api.validate", {
            reason = "legacy RegisterRaid refused (the 1.x encounter-data format was retired in 2.0)",
            enc = def and def.id,
        })
    end
    return nil, "the 1.x encounter-data format was retired in 2.0; use Addon:RegisterZone + Addon:RegisterEncounter"
end

-- { id = "naxxramas", name = "Naxxramas", order = 70, mapID = 533, size = 40, icon = }
function Addon:RegisterZone(def)
    if type(def) ~= "table" or type(def.id) ~= "string" then
        return nil, "a zone needs a string id"
    end
    if Addon.zonesById[def.id] then
        for i, z in ipairs(Addon.zones) do if z.id == def.id then Addon.zones[i] = def break end end
    else
        Addon.zones[#Addon.zones + 1] = def
    end
    Addon.zonesById[def.id] = def
    return def
end

-- One row of the encounter grammar becomes one row of the options tree. `row.options`
-- is a verbatim passthrough for the legacy mechDef fields the detail editor reads
-- (icon/style/sound/colour, and `polarityWatch`, which is how thaddius.lua's
-- polarity sub-panel is reached).
local function projectRow(row, kind)
    local m = {
        id      = row.key,
        name    = row.name or row.text or row.key,
        icon    = row.icon,
        default = API.RowDefault(row),
        _rowKind = kind,
    }
    if type(row.options) == "table" then
        for k, v in pairs(row.options) do m[k] = v end
    end
    return m
end

function API.PublishOptionsTree()
    local raids, byId, npc = {}, {}, {}
    for _, z in ipairs(Addon.zones) do
        local raid = { id = z.id, name = z.name or z.id, order = z.order,
                       mapID = z.mapID, size = z.size, icon = z.icon, bosses = {} }
        raids[#raids + 1] = raid
        byId[z.id] = raid
    end
    for _, enc in ipairs(Addon.encounters) do
        local lg = enc.legacy
        local raid = lg and byId[lg.raidId]
        if raid then
            local boss = { id = lg.bossId, name = enc.name or lg.bossId,
                           npcIDs = enc.creatureIds, encId = enc.id, mechanics = {} }
            for _, row in ipairs(enc.timers)   do boss.mechanics[#boss.mechanics + 1] = projectRow(row, "timer") end
            for _, row in ipairs(enc.warnings) do boss.mechanics[#boss.mechanics + 1] = projectRow(row, "warning") end
            for _, row in ipairs(enc.schedule) do
                if row.key then boss.mechanics[#boss.mechanics + 1] = projectRow(row, "schedule") end
            end
            -- W4c: a roster IS a user-facing surface (it is what an info frame draws),
            -- so it gets a checkbox like every other row.
            for _, row in ipairs(enc.rosters or {}) do
                boss.mechanics[#boss.mechanics + 1] = projectRow(row, "roster")
            end
            -- W4b: "should the bar follow the school" is a preference like any other.
            for _, row in ipairs(enc.restyles or {}) do
                boss.mechanics[#boss.mechanics + 1] = projectRow(row, "restyle")
            end
            raid.bosses[#raid.bosses + 1] = boss
            for _, cid in ipairs(enc.creatureIds) do npc[cid] = boss end
        end
    end
    table.sort(raids, function(a, b) return (a.order or 999) < (b.order or 999) end)
    Addon.raids, Addon.raidsById, Addon.npcIndex = raids, byId, npc
    Addon._optionsTreeRevision = (Addon._optionsTreeRevision or 0) + 1
    return raids
end

-- AUDIT RM-1, second half (Brief G, lesson Class 7). `projectRow` FREEZES the
-- resolved answer: `default = API.RowDefault(row)` calls the role resolver ONCE, at
-- boot. The engine itself is fine — `API.IsRowEnabled` re-resolves live on every
-- fire — but everything that reads the PROJECTED tree (the options checkboxes,
-- alerts.lua's Addon:GetMechanicConfig fallbacks) kept answering with the role the
-- player had at login. Promoted to Main Tank at 20:05, tank rows still reading
-- "off" at 23:00.
--
-- Re-projecting is cheap (it is a walk of already-built tables, no validation) and
-- ROLE_CHANGED is rare by construction — svc_era only fires it on a respec or on a
-- roster change that MOVED the answer. Registered once, from InitEngine, after the
-- first projection exists.
function API.WatchRoleChanges()
    if API._roleWatchInstalled then return false end
    API._roleWatchInstalled = true
    Addon:RegisterEngineCallback("ROLE_CHANGED", function()
        API.PublishOptionsTree()
        -- Repaint any options section currently on screen; a no-op headless and a
        -- no-op when the hub was never opened.
        if Addon.RefreshAllRaidSections then Addon:RefreshAllRaidSections() end
    end)
    return true
end

return API
