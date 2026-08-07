--[[
    Daseeki Raid Mechanics 2.0 — NAXXRAMAS (zone 533), encounter data
    (wave 4d: the owner's raid-priority zone)

    SOURCE OF TRUTH: DBM_ERA_ENCOUNTERS_BEHAVIOR_SPEC.md §8, the fifteen Naxxramas
    encounters plus the zone-wide trash module. Every timer value, warning tier,
    audience gate, ship-off default, phase rule, emote trigger and target scan in
    that section is a row below. Room-1 material only: this file was written from the
    behavioural spec, never from third-party source.

    ────────────────────────────────────────────────────────────────────────────────
    OWNER ARBITRATIONS, 2026-08-07 (from the W4d cross-check) — DO NOT UNDO
    ────────────────────────────────────────────────────────────────────────────────
    Two explicit owner decisions overlay the spec in this file. Both are commented in
    place at every site AND pinned by the NAXX / NAXX-DRIVE gates, so "cleaning them
    up" reddens the harness rather than quietly reverting a decision.

      1. DUAL-ID TRIGGERS where our own Anniversary field logs (2026-07-26) disagreed
         with the spec about a spell id. Neither side is retired: the row fires on
         EITHER id set, and the early-refresh tripwire (§4.3) reports which one this
         server actually uses. Three sites: Faerlina's Enrage (28798 / 28131),
         Sapphiron's Blizzard GTFO (28547 / 28560) and Noth's Blink (all four).
      2. THE DROPPED 1.x ROWS ARE BACK — thirteen of them, each under the option key
         its 1.x row used, so a player's existing SavedVariables choice survives.
         Tank-swap rows announce loudly to the tank audience; the poison-class rows
         ship DEFAULT-OFF, which is the honest middle between "DBM's authors judged
         this class too noisy to carry" and "the owner wants the toggle to exist".
         Every restoration site carries a RESTORED note naming the owner and the date
         (grep the file for it; the gate counts them).

    THE TWO KEY SCHEMES COINCIDE, DELIBERATELY. An encounter is `naxxramas:<boss>` and
    a row key is a mechanic id, so
          API.OptionKey(encId, rowKey) == Addon:MechKey("naxxramas", boss, rowKey)
    and the option a player ticks in the raid section is the same SavedVariables entry
    the engine reads. It is also why the shipped specials keep working untouched:
    thaddius.lua's polarity panel lives under `naxxramas:thaddius:polarity`, and the
    Four Horsemen tracker reads the Mark count from `naxxramas:fourhorsemen:markcd`.
    Both of those keys are rows in this file.

    ────────────────────────────────────────────────────────────────────────────────
    DIVISION OF LABOUR WITH THE FIVE SHIPPED SPECIALS
    ────────────────────────────────────────────────────────────────────────────────
    The specials are play-tested, owner-tuned surfaces. Where one of them already
    renders a behaviour the grammar could now also express, THE SPECIAL SHIPS IT and
    this file deliberately does not declare the row — two renderings of the same
    mechanic is worse than either alone. Each such omission is commented at its
    encounter. The attach point is the `legacy = { raidId, bossId }` seam: engaging
    the encounter starts that boss's enabled modules and populates `Addon.active`.

      gothik_waves          — the whole 18-wave surface (widget, "wave N incoming"
                              3 s banner, "wave N: composition", the 270 s phase-2
                              banner). This file declares NO wave schedule.
      fourhorsemen_tracker  — per-horse health/target/mark stacks, the Meteor /
                              Void Zone / Holy Wrath cooldown radials, and the
                              "4+ marks on you" alarm. This file declares the Mark
                              CADENCE (markcd, which the tracker reads) and the
                              announces, not those three radials.
      fourhorsemen_rotation — the personal corner-rotation bar. No overlap.
      loatheb_healers       — the healer-window frame. No overlap.
      razuvious_understudy  — the understudy nameplate icons. This file declares the
                              understudy TIMERS (taunt / shield wall / mind
                              exhaustion), which are bars, not nameplate icons.
      thaddius (minihealth  — Stalagg/Feugen health frame, and the polarity-FLIP
       + polarity watcher)    alert. This file declares the polarity SHIFT bar and
                              its cast/pre warnings, and owns the option key the
                              watcher's sub-panel hangs from.
--]]

local _, Addon = ...

local ICON = "Interface\\Icons\\"

Addon:RegisterZone({
    id = "naxxramas", name = "Naxxramas", order = 70,
    mapID = 533, size = 40, icon = ICON .. "Spell_Shadow_RaiseDead",
})

-- ══════════════════════════════════════════════════════════════════════════════
--  ARACHNID QUARTER
-- ══════════════════════════════════════════════════════════════════════════════

-- §8.1 Anub'Rekhan. Era quirk: the post-swarm cooldown (69.2 s measured from swarm
-- END) is far more consistent than the pull window, so the bar switches from a
-- variance to a fixed value after the first swarm — which is exactly what `pull` +
-- `duration` mean. Swarm removal is matched on the spell alone: there is no reliable
-- discriminator on the destination. Crypt Guard timers are NOT implemented (spec).
Addon:RegisterEncounter({
    id = "naxxramas:anubrekhan", name = "Anub'Rekhan", zone = 533,
    creatureId = { 15956 }, encounterId = { 1107 },
    legacy = { raidId = "naxxramas", bossId = "anubrekhan" },
    detect = { mode = "combat_yell", yell = {
        "Yes, run! It makes the blood pump faster!",
        "Just a little taste...",
        "There is no way out.",
    } },
    timers = {
        { key = "locust", name = "Locust Swarm", kind = "cd", spellId = 28785, color = 2,
          icon = ICON .. "Spell_Nature_InsectSwarm",
          pull = "v77.3-109.3", duration = 69.2,
          start   = { on = "pull" },
          -- spec: swarm removal is matched on a HOSTILE destination (there is no
          -- reliable spell-id discriminator between the boss's aura and a player's)
          restart = { on = "SPELL_AURA_REMOVED", spellId = 28785,
                      where = { destIsPlayer = false } },
          stop    = { on = "SPELL_CAST_START",   spellId = 28785 } },
        { key = "locustactive", name = "Locust Swarm (active)", kind = "active", spellId = 28785,
          duration = 23, color = 6, icon = ICON .. "Spell_Nature_InsectSwarm",
          start = { on = "SPELL_CAST_START", spellId = 28785 } },
    },
    warnings = {
        { key = "locustsoon", name = "Locust Swarm soon", tier = "announce", color = 2,
          text = "Locust Swarm soon", triggers = {
            { on = "pull", delay = 75 },
            { on = "SPELL_AURA_REMOVED", spellId = 28785, delay = 54.2 },
          } },
        { key = "locustfaded", name = "Locust Swarm faded", tier = "announce", color = 1,
          text = "Locust Swarm faded",
          trigger = { on = "SPELL_AURA_REMOVED", spellId = 28785 } },
        -- Emitted by the scan below with the victim folded in (svc_scan's `warning`
        -- seam), which is why this row carries no trigger of its own.
        { key = "impale", name = "Impale", tier = "announce", color = 3, text = "Impale on %s",
          yell = "Impale on me!", icon = ICON .. "Ability_Rogue_Eviscerate" },
        { key = "locustspecial", name = "Locust Swarm (special)", tier = "special",
          sound = 2, voice = "aesoon", text = "Locust Swarm",
          trigger = { on = "SPELL_CAST_START", spellId = 28785 } },
    },
    scans = {
        -- §1.6 boss target scanner: 0.1 s x 6 after the cast starts.
        { key = "impalescan", type = "poll", interval = 0.1, tries = 6,
          filter = "playersOnly", warning = "impale", creatureId = 15956,
          on = { on = "SPELL_CAST_START", spellId = 28783 } },
    },
})

-- §8.2 Grand Widow Faerlina. The enrage bar STOPS when Widow's Embrace lands and is
-- only restarted if she was actually enraged — hence the `enraged` state gate on the
-- restart. The defensive special keys off whether YOU are tanking, not off a role.
Addon:RegisterEncounter({
    id = "naxxramas:faerlina", name = "Grand Widow Faerlina", zone = 533,
    creatureId = { 15953 }, encounterId = { 1110 },
    legacy = { raidId = "naxxramas", bossId = "faerlina" },
    detect = { mode = "combat_yell", yell = {
        "Kneel before me, worm!",
        "You cannot hide from me!",
        "Slay them in the master's name!",
        "Run while you still can!",
    } },
    timers = {
        { key = "enrage", name = "Enrage", kind = "cd", spellId = 28131, color = 2,
          icon = ICON .. "Ability_Druid_Berserk",
          pull = 56, duration = "v56-76",
          start = { on = "pull" },
          -- restarted only if she was actually enraged before the Embrace landed
          restart = { on = "SPELL_AURA_REMOVED", spellId = 28732,
                      states = { enraged = "yes" } },
          stop  = { on = "SPELL_AURA_APPLIED", spellId = 28732 } },
        { key = "embrace", name = "Widow's Embrace", kind = "active", spellId = 28732,
          duration = 30, color = 6, icon = ICON .. "Spell_Shadow_NightOfTheDead",
          start = { on = "SPELL_AURA_APPLIED", spellId = 28732, antispam = 5 } },
    },
    -- ARBITRATION — owner 2026-08-07: dual-ID; field logs 2026-07-26 vs spec —
    -- tripwire telemetry arbitrates. The spec (and DBM) key the Enrage off 28798; our
    -- own Anniversary logs recorded 28798 never appearing and 28131 firing 12-15x per
    -- pull instead. Neither side is retired: every Enrage rule below fires on
    -- 28798 AND our observed 28131, and the early-refresh tripwire (§4.3) tells us
    -- which one this server actually uses. DO NOT "clean this up" to a single id.
    states = {
        { key = "enraged", initial = "no", transitions = {
            -- the gate the enrage bar's post-Embrace restart reads: it has to answer
            -- "yes" whichever id the server sent, or the bar never comes back
            { on = "SPELL_AURA_APPLIED", spellId = { 28798, 28131 }, to = "yes" },
        } },
    },
    warnings = {
        { key = "embraceactive", name = "Widow's Embrace active", tier = "announce", color = 1,
          text = "Widow's Embrace active",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 28732, antispam = 5 } },
        { key = "embraceends", name = "Widow's Embrace ends in 5s", tier = "announce", color = 2,
          text = "Widow's Embrace ends in 5 seconds",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 28732, delay = 25 },
          -- cancelled if the boss dies or the Embrace ends early
          cancels = { { on = "UNIT_DIED", creatureId = 15953 },
                      { on = "SPELL_AURA_REMOVED", spellId = 28732 } } },
        { key = "embracefaded", name = "Widow's Embrace faded", tier = "announce", color = 3,
          text = "Widow's Embrace faded",
          trigger = { on = "SPELL_AURA_REMOVED", spellId = 28732 } },
        -- dual-ID (see the ARBITRATION note above): spec 28798 OR field-log 28131
        { key = "frenzy", name = "Enrage!", tier = "announce", color = 4, text = "Enrage",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = { 28798, 28131 } } },
        { key = "defensive", name = "Use a defensive", tier = "special", sound = 3,
          voice = "defensive", text = "Enrage — use a defensive",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = { 28798, 28131 },
                      condition = "playerIsBossTarget", creatureId = 15953 } },
        -- RESTORED — owner 2026-08-07: the 1.x row the W4d port dropped, back as an
        -- encounter row under its 1.x option key (`poisonbolt`), spell id from the
        -- parked data_naxxramas.lua. POISON-CLASS ROWS SHIP DEFAULT-OFF: DBM's Era
        -- authors judged this class too noisy to carry at all, the owner restored it
        -- knowingly, and off-by-default is the honest middle — the toggle exists.
        { key = "poisonbolt", name = "Poison Bolt Volley", tier = "announce", color = 2,
          default = false, text = "Poison Bolt Volley",
          icon = ICON .. "Spell_Nature_CorrosiveBreath",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 28796, creatureId = 15953 } },
        { key = "rainoffire", name = "Rain of Fire (GTFO)", tier = "special", sound = 1,
          voice = "watchfeet", soundClass = 8, text = "Move out of the fire",
          triggers = { { on = "SPELL_AURA_APPLIED",   spellId = 28794, dest = "player" },
                       { on = "SPELL_DAMAGE",         spellId = 28794, dest = "player" },
                       { on = "SPELL_PERIODIC_DAMAGE", spellId = 28794, dest = "player" } },
          antispam = 2.5 },
    },
})

-- §8.3 Maexxna. Spiderling spawns are tied to the Web Spray cycle rather than being
-- an independent timer. The "switch targets" special is scheduled 0.5 s out and
-- cancelled if it turns out YOU are the wrapped player — you yell instead.
Addon:RegisterEncounter({
    id = "naxxramas:maexxna", name = "Maexxna", zone = 533,
    creatureId = { 15952 }, encounterId = { 1116 },
    legacy = { raidId = "naxxramas", bossId = "maexxna" },
    detect = { mode = "combat" },
    timers = {
        { key = "webspray", name = "Web Spray", kind = "next", spellId = 29484, color = 2,
          icon = ICON .. "Ability_Ensnare", duration = 40.5, countdown = { depth = 5 },
          start = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 29484 } },
        { key = "webwrap", name = "Web Wrap", kind = "cd", spellId = 28622, color = 3,
          icon = ICON .. "Spell_Nature_StrangleVines",
          pull = "v18.2-20.1", duration = "v39.6-40.9",
          start = { on = "pull" },
          restart = { on = "SPELL_AURA_APPLIED", spellId = 28622 } },
        { key = "spiderlings", name = "Spiderlings", kind = "adds", spellId = 29434, color = 1,
          icon = ICON .. "Spell_Nature_InsectSwarm", duration = 30.7,
          start = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 29484 } },
    },
    warnings = {
        { key = "websprayNow", name = "Web Spray", tier = "announce", color = 4, text = "Web Spray",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 29484 } },
        { key = "webspraySoon", name = "Web Spray soon", tier = "announce", color = 3,
          text = "Web Spray soon", triggers = {
            { on = "pull", delay = 35.5 },
            { on = "SPELL_CAST_SUCCESS", spellId = 29484, delay = 35.5 } } },
        { key = "spiderlingsNow", name = "Spiderlings", tier = "announce", color = 4,
          text = "Spiderlings", trigger = { on = "unitCast", spellId = 29434, sync = true } },
        { key = "spiderlingsSoon", name = "Spiderlings soon", tier = "announce", color = 2,
          text = "Spiderlings soon", triggers = {
            { on = "pull", delay = 25.7 },
            { on = "SPELL_CAST_SUCCESS", spellId = 29484, delay = 25.7 } } },
        { key = "webwrapon", name = "Web Wrap on <name>", tier = "announce", color = 2,
          text = "Web Wrap on %s", combine = 0.5, role = "RangedDps|Healer", generic = true,
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 28622 } },
        { key = "frenzy", name = "Enrage", tier = "announce", color = 4, text = "Enrage",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 28747 } },
        { key = "enragesoon", name = "Enrage soon (35%)", tier = "announce", color = 2,
          text = "Enrage soon", trigger = { on = "health", pct = 35, sync = true } },
        { key = "switchtarget", name = "Switch to the wrapped player", tier = "special",
          sound = 1, voice = "targetchange", role = "RangedDps|Healer",
          text = "Switch targets — %s is wrapped",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 28622, delay = 0.5 },
          -- …cancelled if it turns out YOU are the wrapped player
          cancel = { on = "SPELL_AURA_APPLIED", spellId = 28622, dest = "player" } },
        { key = "killspiderlings", name = "Kill the spiderlings", tier = "special",
          sound = 2, voice = "killmob", role = "Dps", text = "Kill the spiderlings",
          trigger = { on = "unitCast", spellId = 29434, sync = true } },
        -- RESTORED — owner 2026-08-07: the 1.x row the W4d port dropped, back under its
        -- 1.x option key (`necrotic`), spell id from the parked data_naxxramas.lua.
        -- POISON-CLASS ROWS SHIP DEFAULT-OFF (see Faerlina's poisonbolt).
        { key = "necrotic", name = "Necrotic Poison", tier = "announce", color = 2,
          default = false, text = "Necrotic Poison",
          icon = ICON .. "Ability_Creature_Poison_03",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 28776, creatureId = 15952 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  PLAGUE QUARTER
-- ══════════════════════════════════════════════════════════════════════════════

-- §8.4 Noth the Plaguebringer. ERA QUIRK, load-bearing: the balcony/return emotes
-- later clients provide DO NOT EXIST on Era, so the entire teleport cycle is a
-- schedule seeded at pull. Odd ticks are teleports TO the balcony, even ticks are
-- returns to the room — which is what `index = { odd = }` / `{ even = }` select. The
-- gap list carries the spec's cycle verbatim and then alternates 35/55 forever
-- (`repeatFrom`). The Cripple cast that accompanies each teleport was evaluated as a
-- correction trigger and left disabled (spec).
Addon:RegisterEncounter({
    id = "naxxramas:noth", name = "Noth the Plaguebringer", zone = 533,
    creatureId = { 15954 }, encounterId = { 1117 },
    legacy = { raidId = "naxxramas", bossId = "noth" },
    detect = { mode = "combat_yell", yell = {
        "Die, trespasser!", "Glory to the master!", "Your life is forfeit!",
    } },
    schedule = {
        --        1st tp  bal   room   bal  room   bal  room  bal  room  bal
        { key = "teleport", name = "Teleport cycle",
          gaps = { 90.8, 75, 109, 97, 173, 126, 93, 55, 35, 55, repeatFrom = 9 },
          pre = 20 },
    },
    counters = {
        -- "which teleport cycle are we in" and "how many curses / add waves have
        -- landed since the last return" — the two facts the spec's per-slot
        -- exceptions are keyed on.
        { key = "telecycle", scope = "global",
          inc = { on = "schedule", fromKey = "teleport", index = { even = true },
                  where = { pre = false } } },
        { key = "cursecycle", scope = "global",
          inc = { on = "SPELL_CAST_SUCCESS", spellId = 29213 },
          reset = { on = "schedule", fromKey = "teleport", index = { even = true },
                    where = { pre = false } } },
        { key = "addcycle", scope = "global",
          inc = { on = "yell", textFind = "Rise, my soldiers" },
          reset = { on = "schedule", fromKey = "teleport", index = { even = true },
                    where = { pre = false } } },
    },
    timers = {
        { key = "curse", name = "Curse of the Plaguebringer", kind = "cd", spellId = 29213,
          color = 2, icon = ICON .. "Spell_Shadow_PlagueCloud",
          pull = "v6.5-25.9", duration = "v51.8-66.8",
          starts = {
            { on = "pull" },
            -- 10 s after each return to the room…
            { on = "schedule", fromKey = "teleport", index = { even = true },
              where = { pre = false }, duration = 10 },
            -- …except 17 s after the 4th return…
            { on = "schedule", fromKey = "teleport", index = 8, where = { pre = false },
              duration = 17 },
            -- …and 67 s for the 3rd teleport's first curse.
            { on = "schedule", fromKey = "teleport", index = 6, where = { pre = false },
              duration = 67 },
          },
          restarts = {
            { on = "SPELL_CAST_SUCCESS", spellId = 29213 },
            -- the other 67 s slot: the 2nd teleport cycle's SECOND curse
            { on = "SPELL_CAST_SUCCESS", spellId = 29213, duration = 67,
              counter = { { key = "telecycle", eq = 2 }, { key = "cursecycle", eq = 0 } } },
          } },
        { key = "cursefades", name = "Curse fades", kind = "fades", spellId = 29213,
          duration = 10, color = 5, role = "RemoveCurse",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 29213 } },
        { key = "adds", name = "Adds", kind = "adds", spellId = 29252, color = 1,
          icon = ICON .. "Spell_Shadow_RaiseDead",
          pull = "v8.1-22.7", duration = "v25.9-37.2",
          starts = {
            { on = "pull" },
            { on = "schedule", fromKey = "teleport", index = { odd = true },
              where = { pre = false }, duration = 5 },
            { on = "schedule", fromKey = "teleport", index = 2, where = { pre = false }, duration = 3 },
            { on = "schedule", fromKey = "teleport", index = 4, where = { pre = false }, duration = 17 },
          },
          restarts = {
            { on = "yell", textFind = "Rise, my soldiers" },
            -- teleport cycle 1: 33.9, then 30
            { on = "yell", textFind = "Rise, my soldiers", duration = 33.9,
              counter = { { key = "telecycle", eq = 1 }, { key = "addcycle", eq = 0 } } },
            { on = "yell", textFind = "Rise, my soldiers", duration = 30,
              counter = { { key = "telecycle", eq = 1 }, { key = "addcycle", eq = 1 } } },
            -- teleport cycle 2: 30, 32, 32, 30
            { on = "yell", textFind = "Rise, my soldiers", duration = 30,
              counter = { { key = "telecycle", eq = 2 }, { key = "addcycle", eq = 0 } } },
            { on = "yell", textFind = "Rise, my soldiers", duration = 32,
              counter = { { key = "telecycle", eq = 2 }, { key = "addcycle", eq = 1 } } },
            { on = "yell", textFind = "Rise, my soldiers", duration = 32,
              counter = { { key = "telecycle", eq = 2 }, { key = "addcycle", eq = 2 } } },
            { on = "yell", textFind = "Rise, my soldiers", duration = 30,
              counter = { { key = "telecycle", eq = 2 }, { key = "addcycle", eq = 3 } } },
          } },
    },
    warnings = {
        { key = "teleported", name = "Teleported", tier = "announce", color = 3, text = "Teleported",
          trigger = { on = "schedule", fromKey = "teleport", where = { pre = false } } },
        { key = "teleportsoon", name = "Teleport in 20 seconds", tier = "announce", color = 1,
          text = "Teleport in 20 seconds",
          trigger = { on = "schedule", fromKey = "teleport", where = { pre = true } } },
        { key = "cursewarn", name = "Curse of the Plaguebringer", tier = "announce", color = 2,
          text = "Curse of the Plaguebringer",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 29213 } },
        -- ARBITRATION — owner 2026-08-07: dual-ID; field logs 2026-07-26 vs spec —
        -- tripwire telemetry arbitrates. The spec carried ONE blink id; our Anniversary
        -- logs recorded the boss using all four. The row fires on
        -- 29208/29209/29210/29211 — every observed id, not the spec's single one.
        -- DO NOT "clean this up" back to one id.
        { key = "blink", name = "Blink", tier = "announce", color = 3, text = "Blink",
          trigger = { on = "SPELL_CAST_SUCCESS",
                      spellId = { 29208, 29209, 29210, 29211 } } },
        { key = "dispelcurse", name = "Dispel the curse", tier = "special", sound = 1,
          voice = "dispelnow", role = "RemoveCurse", text = "Dispel the curse on %s",
          combine = 0.5, antispam = 3,
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 29213 } },
        { key = "killadds", name = "Kill the adds", tier = "special", sound = 1,
          voice = "killmob", role = "-Healer", text = "Kill the adds",
          trigger = { on = "yell", textFind = "Rise, my soldiers", sync = true } },
    },
})

-- §8.5 Heigan the Unclean. The PHASE surface has zero combat-log triggers: a pure
-- two-state scheduled loop. Ticks alternate room->dance and dance->room, and the
-- pre-warning lead alternates with them (15 s before a room phase ends, 10 s before a
-- dance ends), which is what a cycling `pre` list is for. The two ability announces
-- below are the owner's 2026-08-07 restoration and are the only combat-log rows here.
Addon:RegisterEncounter({
    id = "naxxramas:heigan", name = "Heigan the Unclean", zone = 533,
    creatureId = { 15936 }, encounterId = { 1112 },
    legacy = { raidId = "naxxramas", bossId = "heigan" },
    detect = { mode = "combat_yell", yell = {
        "You are mine now.", "I see you...", "You... are next.",
    } },
    schedule = {
        { key = "dance", name = "Dance cycle",
          gaps = { 90, 47, 88, repeatFrom = 2 }, pre = { 15, 10 } },
    },
    timers = {
        { key = "teleportdance", name = "Teleport (to the platform)", kind = "stage", color = 6,
          icon = ICON .. "Spell_Fire_Volcano", duration = 88,
          starts = { { on = "pull", duration = 90 },
                     { on = "schedule", fromKey = "dance", index = { even = true },
                       where = { pre = false }, duration = 88 } } },
        { key = "teleportroom", name = "Teleport (back to the room)", kind = "stage", color = 6,
          icon = ICON .. "Spell_Arcane_Blink", duration = 47,
          start = { on = "schedule", fromKey = "dance", index = { odd = true },
                    where = { pre = false } } },
    },
    warnings = {
        { key = "teleported", name = "Teleported", tier = "announce", color = 2, text = "Teleported",
          trigger = { on = "schedule", fromKey = "dance", where = { pre = false } } },
        { key = "teleportsoon", name = "Teleport soon", tier = "announce", color = 2,
          text = "Teleport soon",
          trigger = { on = "schedule", fromKey = "dance", where = { pre = true } } },
        -- RESTORED — owner 2026-08-07: the two 1.x rows the W4d port dropped, back under
        -- their 1.x option keys (`fever`, `disrupt`), spell ids from the parked
        -- data_naxxramas.lua. Neither is poison-class, so both keep the 1.x
        -- default (ON); the audience is the whole raid, as it was in 1.x.
        { key = "fever", name = "Decrepit Fever", tier = "announce", color = 2,
          text = "Decrepit Fever", icon = ICON .. "Spell_Nature_NullifyDisease",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 29998, creatureId = 15936 } },
        { key = "disrupt", name = "Spell Disruption", tier = "announce", color = 2,
          text = "Spell Disruption", icon = ICON .. "Spell_Shadow_MindRot",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 29310, creatureId = 15936 } },
    },
})

-- §8.6 Loatheb. The Era mechanic is the CORRUPTED MIND pair (a 2-minute aura that
-- turns your next heal into a silence), not the Wrath-style Necrotic Aura. The healer
-- window frame is mod_loatheb_healers and is NOT re-declared here. The doom cadence
-- alternates 29.1/32.4 and then changes shape entirely at the 7th doom — `sequence`
-- plus `sequenceFrom`.
Addon:RegisterEncounter({
    id = "naxxramas:loatheb", name = "Loatheb", zone = 533,
    creatureId = { 16011 }, encounterId = { 1115 },
    legacy = { raidId = "naxxramas", bossId = "loatheb" },
    detect = { mode = "combat" },
    timers = {
        { key = "spore", name = "Spore", kind = "next", spellId = 29234, color = 1, count = true,
          icon = ICON .. "Spell_Nature_LivingBomb", pull = 11.3, duration = 12.9,
          start = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 29234 } },
        { key = "doom", name = "Inevitable Doom", kind = "next", spellId = 29204, color = 2,
          count = true, icon = ICON .. "Spell_Shadow_CurseOfAchimonde",
          pull = 121.3, sequence = { 29.1, 32.4 },
          sequenceFrom = { [7] = { 9.7 }, [8] = { 19.4, 11.3 } },
          start = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 29204 } },
        { key = "necroticaura", name = "Remove Curse (heal window)", kind = "cd", spellId = 30281,
          color = 5, icon = ICON .. "Spell_Shadow_AntiShadow", classDefault = "WARLOCK",
          pull = "v0.5-8.2", duration = 30.7,
          start = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 30281 } },
    },
    warnings = {
        { key = "sporeN", name = "Spore N", tier = "announce", color = 1, role = "Dps",
          count = true, text = "Spore %d",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 29234 } },
        { key = "sporesoon", name = "Spore soon", tier = "announce", color = 1, role = "Dps",
          text = "Spore soon", triggers = {
            { on = "pull", delay = 6.3 },
            { on = "SPELL_CAST_SUCCESS", spellId = 29234, delay = 7.9 } },
          -- failsafe against pull mis-detection when the raid chain-pulls the gauntlet
          cancel = { on = "UNIT_DIED", creatureId = 16011 } },
        { key = "doomN", name = "Inevitable Doom N", tier = "announce", color = 3, count = true,
          text = "Doom %d", trigger = { on = "SPELL_CAST_SUCCESS", spellId = 29204 } },
        { key = "removecurse", name = "Loatheb removes a curse", tier = "announce", color = 3,
          classDefault = "WARLOCK", text = "Loatheb removes a curse",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 30281 } },
        { key = "healpossible", name = "Healing possible in 3 seconds", tier = "announce",
          color = 4, role = "Healer", text = "Healing possible in 3 seconds",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = { 29184, 29195, 29197, 29199 },
                      dest = "player", delay = 55 } },
        { key = "healnow", name = "Heal now", tier = "announce", color = 1, role = "Healer",
          default = false, text = "Heal now",
          trigger = { on = "SPELL_AURA_REMOVED", spellId = { 29184, 29195, 29197, 29199 },
                      dest = "player" } },
        -- RESTORED — owner 2026-08-07: the 1.x row the W4d port dropped, back under its
        -- 1.x option key (`deathbloom`, kept verbatim so an existing SavedVariables
        -- choice survives), spell id from the parked data_naxxramas.lua. 29865 is
        -- "Poison Aura" on this server, applied to the ENTIRE raid every ~14.5 s
        -- (field-verified 2026-07-26) — POISON-CLASS ROWS SHIP DEFAULT-OFF, and 1.x
        -- shipped this one off for the same reason.
        { key = "deathbloom", name = "Poison Aura", tier = "announce", color = 2,
          default = false, text = "Poison Aura",
          icon = ICON .. "Spell_Nature_NatureTouchDecay",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 29865, dest = "player" } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  MILITARY QUARTER
-- ══════════════════════════════════════════════════════════════════════════════

-- §8.7 Instructor Razuvious. Taunt and Shield Wall are matched on a PET SOURCE — a
-- mind-controlled understudy counts as a pet — which is why the combat-log pet flag
-- had to become a normalised field. The nameplate ICONS are the shipped special; the
-- bars below are this file's. Both default on for Priests only.
Addon:RegisterEncounter({
    id = "naxxramas:razuvious", name = "Instructor Razuvious", zone = 533,
    creatureId = { 16061 }, encounterId = { 1113 },
    legacy = { raidId = "naxxramas", bossId = "razuvious" },
    detect = { mode = "combat_yell", yell = {
        "Show them no mercy!",
        "The time for practice is over! Show me what you have learned!",
        "Do as I taught you!",
        "Sweep the leg... Do you have a problem with that?",
    } },
    timers = {
        { key = "shout", name = "Disrupting Shout", kind = "cd", spellId = 29107, color = 2,
          icon = ICON .. "Spell_Shadow_Teleport", duration = 25.9, countdown = { depth = 5 },
          start = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 29107 } },
        { key = "taunt", name = "Understudy Taunt", kind = "cd", spellId = 29060, color = 5,
          icon = ICON .. "Spell_Nature_Reincarnation", duration = 60, perTarget = true,
          classDefault = "PRIEST",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 29060, source = "pet" } },
        { key = "shieldwall", name = "Shield Wall (understudy)", kind = "active", spellId = 29061,
          color = 6, icon = ICON .. "Ability_Warrior_ShieldWall", duration = 20, perTarget = true,
          start = { on = "SPELL_AURA_APPLIED", spellId = 29061, source = "pet" } },
        { key = "mindexhaust", name = "Mind Exhaustion", kind = "cd", spellId = 29051, color = 5,
          icon = ICON .. "Spell_Shadow_Teleport", duration = 60, nameplate = true,
          classDefault = "PRIEST",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 29051 } },
    },
    warnings = {
        { key = "shoutnow", name = "Disrupting Shout", tier = "announce", color = 4,
          text = "Disrupting Shout",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 29107 } },
        { key = "shoutsoon", name = "Disrupting Shout soon", tier = "announce", color = 3,
          role = "ManaUser", text = "Disrupting Shout soon", triggers = {
            { on = "pull", delay = 19.5 },
            { on = "SPELL_CAST_SUCCESS", spellId = 29107, delay = 19.5 } } },
        { key = "shieldwallwarn", name = "Shield Wall ending", tier = "announce", color = 2,
          role = "Dps", text = "Shield Wall on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 29061, source = "pet", delay = 15 } },
        -- RESTORED — owner 2026-08-07: the 1.x row the W4d port dropped, back under its
        -- 1.x option key (`unbalancing`). Spell id 26613 is field-verified (147 casts
        -- logged 2026-07-26; the old 28491 never appeared once). THIS IS A TANK-SWAP
        -- CALL, so it announces LOUDLY — top announce colour — to the tank-relevant
        -- audience. It is deliberately NOT default-off: the poison-class rule does not
        -- reach a tank-swap.
        { key = "unbalancing", name = "Unbalancing Strike (tank swap)", tier = "announce",
          color = 4, role = "Tank|Healer", text = "Unbalancing Strike — tank swap",
          icon = ICON .. "Ability_Warrior_Disarm",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 26613, creatureId = 16061 } },
    },
})

-- §8.8 Gothik the Harvester.
-- WAVE SURFACE OWNED BY mod_gothik_waves: the 18-wave schedule, both wave banners
-- and the 270 s phase-2 banner are its shipping behaviour and are NOT declared here
-- (the module's wave clock is the spec's gap table, cumulatively identical). This
-- encounter owns the teleport bars, the death announces and the phase register.
-- The live/undead census frame is not shipped (see the wave report).
Addon:RegisterEncounter({
    id = "naxxramas:gothik", name = "Gothik the Harvester", zone = 533,
    creatureId = { 16060 }, encounterId = { 1109 },
    legacy = { raidId = "naxxramas", bossId = "gothik" },
    detect = { mode = "combat" },
    timers = {
        -- The two bars alternate: each teleport arms the other side's.
        { key = "telelive", name = "Teleport (live side)", kind = "cd", spellId = 28025,
          color = 6, icon = ICON .. "Spell_Arcane_Blink", duration = "v19.4-21",
          start = { on = "unitCast", spellId = 28026 },
          stop  = { on = "health", pct = 30 } },
        { key = "teledead", name = "Teleport (dead side)", kind = "cd", spellId = 28026,
          color = 6, icon = ICON .. "Spell_Arcane_Blink", duration = "v19.4-21",
          start = { on = "unitCast", spellId = 28025 },
          stop  = { on = "health", pct = 30 } },
    },
    phases = {
        -- the FIRST live-side teleport is what promotes the fight to phase 2
        { stage = 2, on = "unitCast", spellId = 28025, whenStage = 1 },
    },
    warnings = {
        { key = "telelivenow", name = "Teleport (live side)", tier = "announce", color = 3,
          text = "Teleport — live side",
          trigger = { on = "unitCast", spellId = 28025, sync = true } },
        { key = "teledeadnow", name = "Teleport (dead side)", tier = "announce", color = 3,
          text = "Teleport — dead side",
          trigger = { on = "unitCast", spellId = 28026, sync = true } },
        { key = "telelivesoon", name = "Teleport (live side) soon", tier = "announce", color = 2,
          text = "Teleport soon — live side",
          trigger = { on = "unitCast", spellId = 28026, delay = 14.5 },
          cancels = { { on = "unitCast", spellId = 28025 }, { on = "health", pct = 30 } } },
        { key = "teledeadsoon", name = "Teleport (dead side) soon", tier = "announce", color = 2,
          text = "Teleport soon — dead side",
          trigger = { on = "unitCast", spellId = 28025, delay = 14.5 },
          cancels = { { on = "unitCast", spellId = 28026 }, { on = "health", pct = 30 } } },
        { key = "riderdown", name = "Rider down", tier = "announce", color = 4, text = "Rider down",
          trigger = { on = "UNIT_DIED", creatureId = 16126, dedupe = "destGUID" } },
        { key = "knightdown", name = "Knight down", tier = "announce", color = 2,
          text = "Knight down",
          trigger = { on = "UNIT_DIED", creatureId = 16125, dedupe = "destGUID" } },
        -- RESTORED — owner 2026-08-07: the two 1.x rows the W4d port dropped, back under
        -- their 1.x option keys (`shadowbolt`, `harvest`), spell ids from the parked
        -- data_naxxramas.lua. 29317 is field-verified (the old 27831 never logged).
        -- Shadow Bolt ships OFF exactly as 1.x shipped it: 184 casts at 1.5-1.7 s
        -- intervals were logged 2026-07-26 — a fast repeated P2 nuke, not a volley.
        -- SHAPE GUARD: 1.x rendered it as a self-replacing BAR; an announce row fires
        -- once per event, so the restoration carries a 5 s anti-spam window. Without it
        -- a player who ticks the box gets ~35 warnings a minute.
        { key = "shadowbolt", name = "Shadow Bolt", tier = "announce", color = 2,
          default = false, text = "Shadow Bolt", antispam = 5,
          icon = ICON .. "Spell_Shadow_ShadowBolt",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 29317, creatureId = 16060 } },
        { key = "harvest", name = "Harvest Soul", tier = "announce", color = 3,
          text = "Harvest Soul", icon = ICON .. "Spell_Shadow_SoulGem",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 28679, creatureId = 16060 } },
    },
})

-- §8.9 The Four Horsemen. Boss HP display uses the highest of the four.
-- THE TRACKER OWNS: the four health rows, each horse's current target and mark
-- stacks, the Meteor / Void Zone / Holy Wrath cooldown radials, and the "4+ marks on
-- YOU" alarm. This file owns the shared Mark cadence — which the tracker READS from
-- `Addon._mechCount["naxxramas:fourhorsemen:markcd"]` — and the announces.
Addon:RegisterEncounter({
    id = "naxxramas:fourhorsemen", name = "The Four Horsemen", zone = 533,
    creatureId = { 16062, 16063, 16064, 16065 }, encounterId = { 1121 },
    legacy = { raidId = "naxxramas", bossId = "fourhorsemen" },
    detect = { mode = "combat" },
    combat = { highestHealth = true },
    timers = {
        { key = "markcd", name = "Mark", kind = "cd", color = 3, count = true,
          spellId = { 28832, 28833, 28834, 28835 },
          icon = ICON .. "Spell_Shadow_AntiMagicShell",
          pull = 21, duration = 12.9,
          start = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = { 28832, 28833, 28834, 28835 },
                      antispam = 10 } },
        { key = "bonebarrier", name = "Bone Barrier", kind = "target", spellId = 29061,
          color = 3, duration = 20, perTarget = true,
          start = { on = "SPELL_AURA_APPLIED", spellId = 29061 } },
    },
    counters = {
        { key = "horsemen", scope = "census", from = 4, step = 1,
          dec = { on = "UNIT_DIED", creatureId = { 16062, 16063, 16064, 16065 },
                  dedupe = "destGUID" },
          announce = "Horseman down — %d remaining", announceAt = { 3, 2, 1, 0 } },
    },
    warnings = {
        { key = "marksoon", name = "Mark in 3 seconds", tier = "announce", color = 1,
          default = false, count = true, text = "Mark in 3 seconds", triggers = {
            { on = "pull", delay = 16 },
            { on = "SPELL_CAST_SUCCESS", spellId = { 28832, 28833, 28834, 28835 },
              antispam = 10, delay = 9.9 } } },
        { key = "meteor", name = "Meteor", tier = "announce", color = 4, text = "Meteor",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 28884 } },
        { key = "voidzone", name = "Void Zone on <name>", tier = "announce", color = 3,
          text = "Void Zone on %s",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 28863 } },
        { key = "holywrath", name = "Holy Wrath on <name>", tier = "announce", color = 3,
          default = false, text = "Holy Wrath on %s",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 28883 } },
        { key = "bonebarrierwarn", name = "Bone Barrier on <name>", tier = "announce", color = 2,
          role = "Dps", text = "Bone Barrier on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 29061 } },
        { key = "voidzoneyou", name = "Void Zone on YOU", tier = "special", sound = 1,
          voice = "targetyou", text = "Void Zone on YOU", yell = "Void Zone on me!",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 28863, dest = "player" } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  CONSTRUCT QUARTER
-- ══════════════════════════════════════════════════════════════════════════════

-- §8.10 Patchwerk. Deliberately thin: no hateful-strike tracking, no tank-stack logic.
Addon:RegisterEncounter({
    id = "naxxramas:patchwerk", name = "Patchwerk", zone = 533,
    creatureId = { 16028 }, encounterId = { 1118 },
    legacy = { raidId = "naxxramas", bossId = "patchwerk" },
    detect = { mode = "combat_yell", yell = {
        "Patchwerk want to play!", "Kel'thuzad make Patchwerk his avatar of war!",
    } },
    timers = {
        { key = "berserk", name = "Berserk", kind = "berserk", duration = 420, color = 6,
          icon = ICON .. "Spell_Shadow_UnholyFrenzy", start = { on = "pull" } },
    },
    warnings = {
        { key = "frenzy", name = "Enrage", tier = "announce", color = 4, text = "Enrage",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 28131 } },
        { key = "enragesoon", name = "Enrage soon (10%)", tier = "announce", color = 2,
          text = "Enrage soon", trigger = { on = "health", pct = 10, sync = true } },
        { key = "slimebolt", name = "Slime Bolt", tier = "announce", color = 4, text = "Slime Bolt",
          trigger = { on = "SPELL_CAST_START", spellId = 28311 } },
    },
})

-- §8.11 Grobbulus. Injection targets are iconed 1->4 by insertion order and RE-PACKED
-- when one drops off, so the survivors always hold the lowest icons. Icons ship off.
Addon:RegisterEncounter({
    id = "naxxramas:grobbulus", name = "Grobbulus", zone = 533,
    creatureId = { 15931 }, encounterId = { 1111 },
    legacy = { raidId = "naxxramas", bossId = "grobbulus" },
    detect = { mode = "combat" },
    timers = {
        { key = "berserk", name = "Berserk", kind = "berserk", duration = 720, color = 6,
          icon = ICON .. "Spell_Shadow_UnholyFrenzy", start = { on = "pull" } },
        { key = "injection", name = "Mutating Injection", kind = "target", spellId = 28169,
          color = 3, duration = 10, perTarget = true,
          icon = ICON .. "Spell_Nature_NullifyPoison",
          start = { on = "SPELL_AURA_APPLIED", spellId = 28169 },
          -- stopped if the debuff is dispelled early (an early dispel arrives as an
          -- AURA_REMOVED like any other, which is the Era-reliable signal)
          stop = { on = "SPELL_AURA_REMOVED", spellId = 28169 } },
        { key = "cloud", name = "Poison Cloud", kind = "cd", spellId = 28240, color = 2,
          icon = ICON .. "Spell_Nature_Acid_01", duration = "v14.5-16.6",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 28240 } },
    },
    warnings = {
        { key = "injectionon", name = "Injection on <name>", tier = "announce", color = 2,
          text = "Mutating Injection on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 28169 } },
        { key = "cloudwarn", name = "Poison Cloud", tier = "announce", color = 2,
          text = "Poison Cloud", trigger = { on = "SPELL_CAST_SUCCESS", spellId = 28240 } },
        { key = "runout", name = "Injection on YOU — run out", tier = "special", sound = 1,
          voice = "runout", text = "Injection on YOU — run out",
          yell = "Injection on me!", yellDefault = false,
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 28169, dest = "player" } },
        -- RESTORED — owner 2026-08-07: the 1.x row the W4d port dropped, back under its
        -- 1.x option key (`slimespray`), spell id from the parked data_naxxramas.lua.
        -- POISON-CLASS ROWS SHIP DEFAULT-OFF, which is also the default 1.x shipped.
        { key = "slimespray", name = "Slime Spray", tier = "announce", color = 2,
          default = false, text = "Slime Spray",
          icon = ICON .. "Ability_Creature_Poison_02",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 28157, creatureId = 15931 } },
    },
    icons = {
        { key = "injectionicons", name = "Injection raid icons", default = false,
          mode = "repack", from = 1, to = 4, clearOnEnd = true,
          on = { on = "SPELL_AURA_APPLIED", spellId = 28169 } },
    },
})

-- §8.12 Gluth. ERA QUIRK: there is no cast event for Decimate — it is detected from
-- the DAMAGE it deals, matched on name as well as id, with a 20 s throttle. No
-- Decimate timer is implemented (the real cycle is ~105 s; noted as desired but
-- unbuilt in the spec, and we do not invent one).
Addon:RegisterEncounter({
    id = "naxxramas:gluth", name = "Gluth", zone = 533,
    creatureId = { 15932 }, encounterId = { 1108 },
    legacy = { raidId = "naxxramas", bossId = "gluth" },
    detect = { mode = "combat" },
    timers = {
        { key = "berserk", name = "Berserk", kind = "berserk", duration = 420, color = 6,
          icon = ICON .. "Spell_Shadow_UnholyFrenzy", start = { on = "pull" } },
        { key = "frenzy", name = "Frenzy", kind = "cd", spellId = 28371, color = 2,
          icon = ICON .. "Ability_Druid_Berserk",
          pull = "v9.6-11.3", duration = "v8.1-11.4",
          start = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 28371 } },
        { key = "frenzyactive", name = "Frenzy (active)", kind = "active", spellId = 28371,
          duration = 8, color = 6,
          start = { on = "SPELL_AURA_APPLIED", spellId = 28371 } },
        { key = "roar", name = "Terrifying Roar", kind = "cd", spellId = 29685, color = 2,
          icon = ICON .. "Spell_Shadow_DeathScream", duration = "v17.8-24.2",
          start = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 29685 } },
    },
    warnings = {
        { key = "frenzywarn", name = "Frenzy", tier = "announce", color = 3,
          role = "Tank|RemoveEnrage|Healer", text = "Frenzy",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 28371 } },
        { key = "roarwarn", name = "Terrifying Roar", tier = "announce", color = 2,
          text = "Terrifying Roar",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 29685 } },
        { key = "decimate", name = "Decimate", tier = "announce", color = 3, text = "Decimate",
          antispam = 20, triggers = {
            { on = "SPELL_DAMAGE", spellId = { 28374, 28375 } },
            { on = "SPELL_DAMAGE", spellName = "Decimate" } } },
        { key = "dispelfrenzy", name = "Dispel Frenzy", tier = "special", sound = 1,
          voice = "enrage", soundClass = 6, role = "RemoveEnrage", text = "Dispel the Frenzy",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 28371 } },
        -- RESTORED — owner 2026-08-07: the 1.x row the W4d port dropped, back under its
        -- 1.x option key (`mortalwound`). Spell id 25646 is field-verified (39 casts
        -- logged 2026-07-26; the old 28467 never appeared) and is the SAME debuff id the
        -- suite already carries on Ossirian (§6.1) and Anubisath (§7) — so this ships in
        -- the suite's Mortal Wound SHAPE, announcing the carrier and the live STACK,
        -- which is the tank-relevant fact. Tank audience, not default-off: the
        -- poison-class rule does not reach a tank-stack row.
        { key = "mortalwound", name = "Mortal Wound on <name>", tier = "announce", color = 3,
          role = "Tank", stacks = true, text = "Mortal Wound %s (%d)",
          icon = ICON .. "Ability_Criticalstrike",
          triggers = { { on = "SPELL_AURA_APPLIED",      spellId = 25646 },
                       { on = "SPELL_AURA_APPLIED_DOSE", spellId = 25646 } } },
    },
})

-- §8.13 Thaddius. Detection is the ADDS-phase yell: the encounter begins at Stalagg
-- and Feugen. The adds are tracked through their emotes (synced), and phase 1.5
-- begins when BOTH are simultaneously dead — a compound state test, not a counter.
-- THE POLARITY FLIP ALERT IS thaddius.lua's (it reads the debuff ICONS, 135768 /
-- 135769, which is the only Era-correct way to know your charge); this file owns the
-- shift bar, the cast bar, the pre-warning, and the option key that sub-panel hangs
-- from. The Stalagg/Feugen health frame is the same file's module.
Addon:RegisterEncounter({
    id = "naxxramas:thaddius", name = "Thaddius", zone = 533,
    creatureId = { 15928, 15929, 15930 }, encounterId = { 1120 },
    killCreatureIds = { 15928 },
    legacy = { raidId = "naxxramas", bossId = "thaddius" },
    detect = { mode = "combat_yell", yell = { "Feed you to master!", "Stalagg crush you!" } },
    timers = {
        { key = "magneticpull", name = "Magnetic Pull (Throw)", kind = "cd", color = 3,
          spellId = { 28338, 28339 }, icon = ICON .. "Spell_Nature_EarthBind",
          duration = 21,
          start = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = { 28338, 28339 } },
          -- phase 1.5 (both adds down) stops the throw bar
          stop = { on = "stage", stage = 1.5 } },
        { key = "intermission", name = "Intermission", kind = "intermission", color = 6,
          duration = "v12.8-16",
          start = { on = "stage", stage = 1.5 } },
        { key = "berserk", name = "Berserk", kind = "berserk", duration = 300, color = 6,
          icon = ICON .. "Spell_Shadow_UnholyFrenzy",
          start = { on = "stage", stage = 2 } },
        { key = "polarity", name = "Polarity Shift", kind = "cd", spellId = 28089, color = 4,
          icon = ICON .. "Spell_Nature_Lightning",
          pull = 11.3, phaseDuration = { [2] = "v25.9-35.7" },
          options = { polarityWatch = true },   -- reaches thaddius.lua's flip sub-panel
          start = { on = "stage", stage = 2 },
          restart = { on = "SPELL_CAST_START", spellId = 28089 } },
        { key = "polaritycast", name = "Polarity Shift (cast)", kind = "cast", spellId = 28089,
          duration = 3, color = 4,
          start = { on = "SPELL_CAST_START", spellId = 28089 } },
        -- RESTORED — owner 2026-08-07: the 1.x row the W4d port dropped, back under its
        -- 1.x option key (`chainlightning`), spell id and cadence from the parked
        -- data_naxxramas.lua. This is the ONE restored row 1.x shipped as a COOLDOWN
        -- RADIAL rather than a plain alert, so it comes back as a timer, not a warning:
        -- 90 casts at ~8.5 s average were logged 2026-07-26. Quiet healer info —
        -- no window warning, no sound, and OFF by default exactly as 1.x had it.
        { key = "chainlightning", name = "Chain Lightning", kind = "cd", spellId = 28167,
          color = 2, default = false, duration = 8.5,
          icon = ICON .. "Spell_Nature_ChainLightning",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 28167, creatureId = 15928 } },
    },
    states = {
        -- emote-driven, synced, keyed on the add named in the emote
        { key = "stalagg", initial = "alive", transitions = {
            { on = "emote", textPattern = "Stalagg.*dies",   to = "dead" },
            { on = "emote", textPattern = "Stalagg.*jolted", to = "alive" } } },
        { key = "feugen", initial = "alive", transitions = {
            { on = "emote", textPattern = "Feugen.*dies",   to = "dead" },
            { on = "emote", textPattern = "Feugen.*jolted", to = "alive" } } },
    },
    phases = {
        -- both adds simultaneously dead -> phase 1.5 (pre-phase, intermission bar)
        { stage = 1.5, on = "state", states = { stalagg = "dead", feugen = "dead" },
          whenStage = 1 },
        { stage = 2, on = "yell",
          text = { "Eat... your... bones...", "Break... you!!", "Kill..." } },
    },
    warnings = {
        { key = "thrownow", name = "Throw", tier = "announce", color = 3, text = "Throw",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = { 28338, 28339 } } },
        { key = "throwsoon", name = "Throw soon", tier = "announce", color = 2, text = "Throw soon",
          triggers = { { on = "pull", delay = 16 },
                       { on = "SPELL_CAST_SUCCESS", spellId = { 28338, 28339 }, delay = 16 } },
          cancel = { on = "stage", stage = 1.5 } },
        { key = "phase2soon", name = "Phase 2 soon", tier = "announce", color = 2,
          text = "Phase 2 soon", trigger = { on = "stage", stage = 1.5 } },
        { key = "phase2", name = "Phase 2", tier = "announce", color = 2, text = "Phase 2",
          trigger = { on = "stage", stage = 2 } },
        { key = "polaritycasting", name = "Polarity Shift casting", tier = "announce", color = 4,
          text = "Polarity Shift — casting",
          trigger = { on = "SPELL_CAST_START", spellId = 28089 } },
        { key = "polaritysoon", name = "Polarity Shift soon", tier = "announce", color = 3,
          text = "Polarity Shift soon",
          trigger = { on = "SPELL_CAST_START", spellId = 28089, delay = 20 } },
        -- RESTORED — owner 2026-08-07: two more 1.x rows the W4d port dropped, back under
        -- their 1.x option keys (`powersurge`, `balllightning`), spell ids from the
        -- parked data_naxxramas.lua. Both field-verified 2026-07-26: Power Surge 28134
        -- (16 casts, ~27.5 s apart, Stalagg's damage buff during the adds phase) and
        -- Ball Lightning 28299 (the old 28338 is Stalagg's Magnetic Pull on this
        -- server, an entirely different spell). Neither is poison-class → both keep
        -- the 1.x default (ON). SHAPE GUARD, as on Gothik's Shadow Bolt: Ball Lightning
        -- was a 1.x BAR and is a repeated P2 nuke, so the announce carries a 3 s
        -- anti-spam window.
        { key = "powersurge", name = "Power Surge", tier = "announce", color = 3,
          text = "Power Surge — Stalagg damage up",
          icon = ICON .. "Spell_Lightning_LightningBolt01",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 28134 } },
        { key = "balllightning", name = "Ball Lightning", tier = "announce", color = 2,
          text = "Ball Lightning", antispam = 3,
          icon = ICON .. "Spell_Nature_LightningShield",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 28299, creatureId = 15928 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  FROSTWYRM LAIR
-- ══════════════════════════════════════════════════════════════════════════════

-- §8.14 Sapphiron. ERA QUIRK, the notable one: THERE IS NO AIR-PHASE EVENT. The mod
-- samples the boss continuously and watches whether he has a TARGET OF HIS OWN; more
-- than 0.5 s target-less while in combat means he has lifted off. That is a repeated
-- scanner whose LOSS is the signal (`reportLoss`), a 0.5 s deferred transition, and a
-- 60 s force-clear safety net. Landing is then a schedule seeded by Frost Breath.
Addon:RegisterEncounter({
    id = "naxxramas:sapphiron", name = "Sapphiron", zone = 533,
    creatureId = { 15989 }, encounterId = { 1119 },
    legacy = { raidId = "naxxramas", bossId = "sapphiron" },
    detect = { mode = "combat" },
    timers = {
        { key = "berserk", name = "Berserk", kind = "berserk", duration = 900, color = 6,
          icon = ICON .. "Spell_Shadow_UnholyFrenzy", start = { on = "pull" } },
        { key = "airphase", name = "Air Phase", kind = "stage", color = 6,
          icon = ICON .. "Spell_Frost_Wisp",
          pull = "v31.2-45.9", duration = "v54.3-70.8",
          starts = { { on = "pull" },
                     -- re-armed when he lands: 12.2 s after Frost Breath starts
                     { on = "SPELL_CAST_START", spellId = 28524, delay = 12.2 } },
          stop = { on = "health", pct = 10 } },
        { key = "landing", name = "Landing", kind = "stage", color = 6,
          icon = ICON .. "Spell_Frost_FrostBolt02", duration = 28.5,
          starts = { { on = "state", fromKey = "flight", where = { to = "air" } },
                     -- corrected once Frost Breath actually starts
                     { on = "SPELL_CAST_START", spellId = 28524, duration = "v16.3-28.5" } } },
        { key = "frostbreath", name = "Frost Breath", kind = "cast", spellId = 28524,
          duration = 7, color = 4, countdown = { depth = 5 },
          start = { on = "SPELL_CAST_START", spellId = 28524 } },
        { key = "lifedrain", name = "Life Drain", kind = "cd", spellId = 28542, color = 2,
          icon = ICON .. "Spell_Shadow_LifeDrain", duration = "v21.1-27.5",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 28542 },
          stop  = { on = "state", fromKey = "flight", where = { to = "air" } } },
    },
    scans = {
        { key = "airscan", type = "repeated", interval = 0.2, creatureId = 15989,
          reportLoss = true, on = { on = "pull" } },
    },
    states = {
        { key = "flight", initial = "ground", transitions = {
            -- >0.5 s target-less = he has lifted off; any re-acquired target cancels it
            { on = "targetChanged", fromKey = "airscan", where = { lost = true },
              delay = 0.5, to = "air" },
            -- landing, and the 60 s safety net that force-clears the flying flag
            { on = "SPELL_CAST_START", spellId = 28524, delay = 12.2, to = "ground",
              actions = { { resetCounter = "iceblock" } } },
            { on = "state", where = { to = "air" }, delay = 60, to = "ground" },
          },
          cancel = { on = "targetChanged", fromKey = "airscan", where = { lost = false } } },
    },
    counters = {
        { key = "iceblock", scope = "global",
          inc = { on = "SPELL_AURA_APPLIED", spellId = 28522 } },
    },
    warnings = {
        { key = "lifedrainnow", name = "Life Drain", tier = "announce", color = 3,
          text = "Life Drain", trigger = { on = "SPELL_CAST_SUCCESS", spellId = 28542 } },
        { key = "lifedrainsoon", name = "Life Drain soon", tier = "announce", color = 2,
          role = "RemoveCurse", text = "Life Drain soon",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 28542, delay = 18.5 },
          cancel = { on = "state", fromKey = "flight", where = { to = "air" } } },
        { key = "iceblockon", name = "Ice Block on <name>", tier = "announce", color = 2,
          count = true, text = "Ice Block on %s", yell = "Ice Block on me!",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 28522 } },
        { key = "airphasesoon", name = "Air phase soon", tier = "announce", color = 3,
          text = "Air phase soon", triggers = {
            { on = "pull", delay = 26.2 },
            { on = "SPELL_CAST_START", spellId = 28524, delay = 61.5 } },
          cancel = { on = "health", pct = 10 } },
        { key = "airphasenow", name = "Air phase", tier = "announce", color = 4, text = "Air phase",
          trigger = { on = "state", fromKey = "flight", where = { to = "air" } } },
        { key = "landed", name = "Sapphiron landed", tier = "announce", color = 4,
          text = "Sapphiron landed",
          trigger = { on = "state", fromKey = "flight", where = { to = "ground" } } },
        -- ARBITRATION — owner 2026-08-07: dual-ID; field logs 2026-07-26 vs spec —
        -- tripwire telemetry arbitrates. The spec (and DBM) key the Blizzard off 28547;
        -- our own Anniversary logs recorded 59 casts of 28560 ("Summon Blizzard") and
        -- zero of 28547. The GTFO fires on
        -- 28547 AND our observed 28560 (Summon Blizzard) — every arm of it, on either
        -- id. DO NOT "clean this up" to a single id.
        { key = "blizzard", name = "Blizzard (GTFO)", tier = "special", sound = 1,
          voice = "watchfeet", soundClass = 8, text = "Move out of the Blizzard",
          antispam = 2.5,
          triggers = { { on = "SPELL_AURA_APPLIED",    spellId = { 28547, 28560 }, dest = "player" },
                       { on = "SPELL_DAMAGE",          spellId = { 28547, 28560 }, dest = "player" },
                       { on = "SPELL_PERIODIC_DAMAGE", spellId = { 28547, 28560 }, dest = "player" } } },
        { key = "findshelter", name = "Find shelter", tier = "special", sound = 3,
          voice = "findshelter", text = "Find shelter",
          trigger = { on = "SPELL_CAST_START", spellId = 28524 } },
    },
})

-- §8.15 Kel'Thuzad. ERA QUIRK: phase-2 entry (KT becoming attackable) has no reliable
-- trigger — it is detected by HIS NAMEPLATE APPEARING while still in phase 1, synced,
-- so the phase-1 duration is a wide variance bar measured across Era logs. Every P2
-- ability has a different FIRST value at phase-2 entry than its recurring cooldown,
-- which is exactly a per-trigger duration on the stage start. All three icon options
-- ship OFF.
Addon:RegisterEncounter({
    id = "naxxramas:kelthuzad", name = "Kel'Thuzad", zone = 533,
    creatureId = { 15990 }, encounterId = { 1114 },
    legacy = { raidId = "naxxramas", bossId = "kelthuzad" },
    detect = { mode = "combat_yell", yell = {
        "Minions, servants, soldiers of the cold dark! Obey the call of Kel'Thuzad!",
    } },
    combat = { minCombatTime = 60, wipeWindow = 15 },
    timers = {
        { key = "phase2", name = "Phase 2", kind = "stage", color = 6,
          icon = ICON .. "Spell_Frost_Wisp", duration = "v229.2-245.8",
          start = { on = "pull" },
          stop  = { on = "stage", stage = 2 } },
        { key = "frostboltcast", name = "Frostbolt (cast)", kind = "cast", spellId = 28478,
          duration = 2, color = 4, nameplate = true,
          start = { on = "SPELL_CAST_START", spellId = 28478 },
          stop  = { on = "SPELL_INTERRUPT", spellId = 28478 } },
        { key = "frostbolt", name = "Frostbolt", kind = "cd", spellId = 28479, color = 2,
          default = false, icon = ICON .. "Spell_Frost_FrostBolt",
          duration = "v15.7-63.1",
          starts = { { on = "stage", stage = 2, duration = "v15.3-85.9" } },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 28479 } },
        { key = "fissure", name = "Shadow Fissure", kind = "cd", spellId = 27810, color = 2,
          default = false, icon = ICON .. "Spell_Shadow_ShadowfuryUnused",
          duration = "v10.9-42.1",
          starts = { { on = "stage", stage = 2, duration = "v10.4-38.4" } },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 27810 } },
        { key = "detonate", name = "Mana Bomb", kind = "cd", spellId = 27819, color = 2,
          icon = ICON .. "Spell_Arcane_ManaTap", duration = "v20.2-50.9",
          starts = { { on = "stage", stage = 2, duration = "v20.2-46.5" } },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 27819 } },
        { key = "frostblast", name = "Frost Blast", kind = "cd", spellId = 27808, color = 2,
          icon = ICON .. "Spell_Frost_Glacier", duration = "v33.5-75.3",
          starts = { { on = "stage", stage = 2, duration = "v30.3-92.7" } },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 27808 } },
        { key = "frostblastfades", name = "Frost Blast fades", kind = "fades", spellId = 27808,
          duration = 5, color = 3,
          start = { on = "SPELL_AURA_APPLIED", spellId = 27808, delay = 0.5 } },
        { key = "chains", name = "Chains of Kel'Thuzad", kind = "cd", spellId = 28410, color = 3,
          icon = ICON .. "Spell_Shadow_DeathCoil", duration = "v63.1-145.4",
          starts = { { on = "stage", stage = 2, duration = "v21.8-103.4" } },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 28408 } },
    },
    phases = {
        -- Era: his nameplate appearing IS the phase-2 signal
        { stage = 2, on = "nameplate", creatureId = 15990, whenStage = 1 },
        -- the guardian-summon point
        { stage = 3, on = "health", pct = 48, whenStage = 2, sync = true, pre = true },
    },
    warnings = {
        { key = "phase2warn", name = "Phase 2", tier = "announce", color = 2, voice = "ptwo",
          text = "Phase 2", trigger = { on = "stage", stage = 2 } },
        { key = "phase3warn", name = "Phase 3", tier = "announce", color = 2, voice = "pthree",
          text = "Phase 3", trigger = { on = "stage", stage = 3 } },
        { key = "phase2soon", name = "Phase 2 soon", tier = "announce", color = 2,
          text = "Phase 2 soon", trigger = { on = "pull", delay = 220 },
          cancel = { on = "stage", stage = 2 } },
        { key = "phase3soon", name = "Phase 3 soon", tier = "announce", color = 2,
          text = "Phase 3 soon",
          trigger = { on = "health", pct = 48, stage = 2, sync = true } },
        { key = "frostblastwarn", name = "Frost Blast on <names>", tier = "announce", color = 2,
          text = "Frost Blast on %s", combine = 0.5,
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 27808 } },
        { key = "fissurewarn", name = "Shadow Fissure on <name>", tier = "announce", color = 4,
          text = "Shadow Fissure on %s",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 27810 } },
        { key = "manabombwarn", name = "Mana Bomb on <name>", tier = "announce", color = 2,
          text = "Mana Bomb on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 27819 } },
        { key = "chainswarn", name = "Chains on <names>", tier = "announce", color = 4,
          text = "Chains on %s", combine = 1.0, antispam = 5,
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 28410 } },
        { key = "healfrostblast", name = "Heal the Frost Blast targets", tier = "special",
          sound = 1, voice = "healall", role = "Healer", combine = 0.5,
          text = "Heal the Frost Blast targets — %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 27808 } },
        { key = "fissureyou", name = "Shadow Fissure on YOU", tier = "special", sound = 3,
          voice = "targetyou", text = "Shadow Fissure on YOU", yell = "Fissure on me!",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 27810, dest = "player" } },
        { key = "manabombyou", name = "Mana Bomb on YOU", tier = "special", sound = 1,
          voice = "scatter", role = "ManaUser", text = "Mana Bomb on YOU — run out",
          yell = "Mana Bomb on me!",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 27819, dest = "player" } },
        { key = "interruptfrostbolt", name = "Interrupt Frostbolt", tier = "special", sound = 1,
          voice = "kickcast", role = "HasInterrupt", filter = "interrupt",
          text = "Interrupt Frostbolt",
          trigger = { on = "SPELL_CAST_START", spellId = 28478 } },
    },
    icons = {
        { key = "chainsicons", name = "Chains raid icons", default = false,
          mode = "groupParity", up = { 1, 2, 3, 4, 5 }, down = { 5, 4, 3, 2, 1 },
          resetOn = "apply", on = { on = "SPELL_AURA_APPLIED", spellId = 28410 } },
        { key = "manabombicon", name = "Mana Bomb raid icon", default = false,
          icon = 8, duration = 5.5,
          on = { on = "SPELL_AURA_APPLIED", spellId = 27819 } },
        { key = "frostblasticons", name = "Frost Blast raid icons", default = false,
          mode = "reverse", base = 8, duration = 4.5,
          on = { on = "SPELL_AURA_APPLIED", spellId = 27808 } },
    },
})

-- §8.16 Naxxramas trash (zone-wide). A zone module: armed for the whole instance and
-- live DURING boss fights too, which is why it is a separate registration rather than
-- rows on a boss. The lightning-totem special deliberately carries NO anti-spam —
-- two packs can summon back to back and the second totem is the one that kills you.
Addon:RegisterEncounter({
    id = "naxxramas:trash", name = "Naxxramas trash", zone = 533,
    legacy = { raidId = "naxxramas", bossId = "trash" },
    detect = { mode = "zone" },
    warnings = {
        { key = "intimidatingshout", name = "Intimidating Shout", tier = "announce", color = 2,
          text = "Intimidating Shout", antispam = 3,
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19134 } },
        { key = "fear", name = "Fear", tier = "announce", color = 2, text = "Fear", antispam = 5,
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 27990 } },
        { key = "poisoncharge", name = "Poison Charge", tier = "announce", color = 2,
          text = "Poison Charge", antispam = 3,
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 28431 } },
        { key = "veilofshadow", name = "Veil of Shadow", tier = "announce", color = 2,
          text = "Veil of Shadow", antispam = 6, role = "RemoveCurse|Healer",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 28440 } },
        { key = "lightningtotem", name = "Kill the lightning totem", tier = "special",
          sound = 3, voice = "attacktotem", role = "Dps", text = "Kill the lightning totem",
          trigger = { on = "SPELL_SUMMON", spellId = 28294 } },
    },
})
