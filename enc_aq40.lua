--[[
    Daseeki Raid Mechanics 2.0 — TEMPLE OF AHN'QIRAJ / AQ40 (zone 531), encounter data
    (wave 4c, second half)

    SOURCE OF TRUTH: DBM_ERA_ENCOUNTERS_BEHAVIOR_SPEC.md §7 — the nine AQ40 encounters
    plus the zone-wide trash module. Room-1 material only: written from the
    behavioural spec, never from third-party source.

    REPLACES data_aq40.lua. That file was the 1.x flat mechanic model; it was diffed
    against the spec row by row before deletion, the spec won every disagreement, and
    every disagreement is in the wave report and the CHANGELOG.

    SAVEDVARIABLES CONTINUITY. The 1.x file registered raid `aq40` with boss ids
    skeram / bugtrio / sartura / fankriss / viscidus / huhuran / twinemps / ouro /
    cthun, and `Addon:MechKey(raidId, bossId, mechId)` is exactly the option key this
    grammar produces for `aq40:<boss>` + `<rowKey>`. So the boss ids are preserved
    verbatim, and where a spec row is recognisably the same mechanic as a 1.x row the
    ROW KEY is preserved too — a player who turned a mechanic off in 1.x finds it
    still off. Two keys are deliberately kept over their names:

      huhuran:noxious   — the 1.x "Noxious Poison" and the spec's "Poison Bolt" are
                          both spell 26053. The key is the saved setting; the name is
                          just a label, so the key stays and the label follows the spec.
      cthun:eyebeam     — 1.x shipped Eye Beam as a (default-off) cast announce. The
                          spec's Eye Beam is a boss-target SCAN. Same mechanic, same
                          key, different machinery.

    ────────────────────────────────────────────────────────────────────────────────
    WHAT THIS WAVE DOES NOT SHIP (deliberate, reported)
    ────────────────────────────────────────────────────────────────────────────────
    Three of §7's surfaces are INFO FRAMES — live tables, not alerts. Their MODELS are
    built here (the C'Thun stomach roster and its relayed tentacle probe, the Viscidus
    hit counters and their rates, the bug-trio census) and published on the engine's
    broadcast seam; the frames that draw them are a presentation job, on the same
    precedent by which W4d shipped Gothik's wave model without Gothik's census frame.
    The AQ40 trash Anubisath ability DOSSIER (the aura-scan half of §7.10) is not
    built at all this wave — its ALERTS are all here; its per-mob ability table is not.
--]]

local _, Addon = ...

local ICON = "Interface\\Icons\\"

Addon:RegisterZone({
    id = "aq40", name = "Temple of Ahn'Qiraj", order = 60,
    mapID = 531, size = 40, icon = ICON .. "INV_Misc_QirajiCrystal_05",
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §7.1 THE PROPHET SKERAM
-- ══════════════════════════════════════════════════════════════════════════════
-- Boss-death kill detection is DISABLED: the images die too, and a dying image is
-- indistinguishable from the boss on Era. The split pre-warnings are health WINDOWS
-- rather than thresholds (81-77, 56-52, 31-27), which is why each carries a floor as
-- well as a ceiling — a bare "<= 81 %" threshold would re-announce during the execute.
Addon:RegisterEncounter({
    id = "aq40:skeram", name = "The Prophet Skeram", zone = 531,
    creatureId = { 15263 }, encounterId = { 709 },
    legacy = { raidId = "aq40", bossId = "skeram" },
    detect = { mode = "combat" },
    combat = { noBossKill = true },
    timers = {
        { key = "fulfillment", name = "True Fulfillment (Mind Control)", kind = "target",
          spellId = 785, color = 3, duration = 20, perTarget = true,
          icon = ICON .. "Spell_Shadow_ShadowWordDominate",
          start = { on = "SPELL_AURA_APPLIED", spellId = 785 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 785 } },
    },
    warnings = {
        { key = "fulfillmenton", name = "Mind control on <name>", tier = "announce",
          color = 4, noFilter = true, combine = 0.3, text = "Mind control on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 785 } },
        { key = "teleport", name = "Blink / Teleport", tier = "announce", color = 3,
          text = "Teleport", icon = ICON .. "Spell_Arcane_Blink",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = { 20449, 4801, 8195 },
                      antispam = 3 } },
        { key = "images", name = "Summon Images (split)", tier = "announce", color = 3,
          text = "Skeram splits", icon = ICON .. "Spell_Magic_LesserInvisibilty",
          trigger = { on = "SPELL_SUMMON", spellId = 747, antispam = 3 } },
        { key = "splitsoon", name = "Split soon", tier = "announce", color = 2,
          text = "Split soon", triggers = {
            { on = "health", pct = 81, pctMin = 77, sync = true },
            { on = "health", pct = 56, pctMin = 52, sync = true },
            { on = "health", pct = 31, pctMin = 27, sync = true } } },
        { key = "arcaneexplosion", name = "Interrupt Arcane Explosion", tier = "special",
          sound = 1, voice = "kickcast", role = "HasInterrupt", filter = "interrupt",
          text = "Interrupt Arcane Explosion",
          trigger = { on = "SPELL_CAST_START", spellId = 26192, antispam = 3 } },
    },
    icons = {
        -- 8 -> 7 -> 6 -> 5 -> 4 as victims land, and the counter goes back to 8 after
        -- 3 s of quiet, so the next split's crop starts from the top again.
        { key = "mcicons", name = "Mind control raid icons", default = true,
          mode = "descend", from = 8, to = 4, resetAfter = 3, clearOnEnd = true,
          on = { on = "SPELL_AURA_APPLIED", spellId = 785 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §7.2 SILITHID ROYALTY  (Vem / Lord Kri / Princess Yauj)
-- ══════════════════════════════════════════════════════════════════════════════
-- Each bar belongs to a specific bug and STOPS WHEN THAT BUG DIES — Fear is Yauj's,
-- Toxic Volley is Kri's. That is the whole reason both rows carry a `stop`.
--
-- ERA QUIRK the spec calls out and we cannot fully honour yet: the poison cloud
-- persists AFTER the encounter ends, so the reference keeps its ground-damage
-- listeners alive for 60 s past combat end. Our lifecycle tears a runtime down at
-- combat end and has no linger; the row below is correct DURING the fight and is
-- reported as a known gap rather than faked. The ground events are matched on spell
-- NAME as well as id, which the spec requires and which we do honour.
Addon:RegisterEncounter({
    id = "aq40:bugtrio", name = "Silithid Royalty", zone = 531,
    creatureId = { 15544, 15511, 15543 }, encounterId = { 710 },
    legacy = { raidId = "aq40", bossId = "bugtrio" },
    detect = { mode = "combat" },
    combat = { highestHealth = true },
    timers = {
        { key = "fear", name = "Fear", kind = "cd", spellId = 26580, color = 2,
          icon = ICON .. "Spell_Shadow_Psychicscream",
          pull = "v10.6-18.4", duration = "v20.3-29.4",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 26580 },
          stop    = { on = "UNIT_DIED", creatureId = 15543 } },
        { key = "toxicvolley", name = "Toxic Volley", kind = "cd", spellId = 25812,
          color = 2, icon = ICON .. "Spell_Nature_CorrosiveBreath",
          pull = "v8.1-42.6", duration = "v8.1-35.1",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 25812 },
          stop    = { on = "UNIT_DIED", creatureId = 15511 } },
    },
    counters = {
        -- The model behind "all three bugs' health": how many are left, announced as
        -- each one dies, de-duplicated by GUID.
        { key = "bugs", name = "Bugs remaining", scope = "census", from = 3, step = 1,
          dec = { on = "UNIT_DIED", creatureId = { 15544, 15511, 15543 },
                  dedupe = "destGUID" },
          announce = "Bug down — %d remaining", announceAt = { 2, 1, 0 } },
    },
    warnings = {
        { key = "fearwarn", name = "Fear", tier = "announce", color = 2, text = "Fear",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 26580, antispam = 3 } },
        { key = "toxicvolleywarn", name = "Toxic Volley", tier = "announce", color = 2,
          role = "RemovePoison", text = "Toxic Volley",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 25812 } },
        { key = "heal", name = "Great Heal", tier = "announce", color = 3,
          role = "HasInterrupt", text = "Great Heal — interrupt",
          trigger = { on = "SPELL_CAST_START", spellId = 25807 } },
        { key = "interruptheal", name = "Interrupt Great Heal", tier = "special", sound = 1,
          voice = "kickcast", role = "HasInterrupt", filter = "interrupt",
          text = "Interrupt Great Heal",
          trigger = { on = "SPELL_CAST_START", spellId = 25807 } },
        { key = "gtfo", name = "Poison cloud (GTFO)", tier = "special", sound = 1,
          soundClass = 8, voice = "watchfeet", text = "Move out of the poison",
          antispam = 2.5, triggers = {
            { on = "SPELL_AURA_APPLIED",    spellId = { 25786, 25989 }, dest = "player" },
            { on = "SPELL_PERIODIC_DAMAGE", spellId = { 25786, 25989 }, dest = "player" },
            { on = "SPELL_DAMAGE",          spellId = { 25786, 25989 }, dest = "player" },
            -- matched on NAME as well as id (spec), because the persisting cloud does
            -- not always carry the id we know it by
            { on = "SPELL_PERIODIC_DAMAGE", spellName = { "Poison Cloud", "Toxin" },
              dest = "player" } } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §7.3 BATTLEGUARD SARTURA
-- ══════════════════════════════════════════════════════════════════════════════
-- NO COOLDOWN TIMERS: the spec records that Whirlwind's interval was never
-- characterised, and we do not invent one. The whirlwind special is gated on a
-- "can you actually be hit" check, which on Era is the range ladder.
Addon:RegisterEncounter({
    id = "aq40:sartura", name = "Battleguard Sartura", zone = 531,
    creatureId = { 15516 }, encounterId = { 711 },
    legacy = { raidId = "aq40", bossId = "sartura" },
    detect = { mode = "combat" },
    counters = {
        { key = "guards", name = "Royal Guards remaining", scope = "census", from = 3,
          step = 1,
          dec = { on = "UNIT_DIED", creatureId = 15984, dedupe = "destGUID" },
          announce = "Royal Guard down — %d remaining", announceAt = { 2, 1, 0 } },
    },
    warnings = {
        { key = "whirlwind", name = "Whirlwind", tier = "announce", color = 3,
          text = "Whirlwind", icon = ICON .. "Ability_Whirlwind",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 26083, antispam = 4 } },
        { key = "enrage", name = "Enrage", tier = "announce", color = 4, text = "Enrage",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 8269 } },
        { key = "enragesoon", name = "Enrage soon (35%)", tier = "announce", color = 2,
          text = "Enrage soon", trigger = { on = "health", pct = 35, sync = true } },
        { key = "whirlwindrun", name = "Whirlwind — run", tier = "special", sound = 4,
          voice = "justrun", text = "Whirlwind — run",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 26083, antispam = 4,
                      condition = "playerNearSource", range = 13, creatureId = 15516 } },
        { key = "gtfo", name = "Sundering Cleave (GTFO)", tier = "special", sound = 1,
          soundClass = 8, voice = "watchfeet", text = "Move out of it", antispam = 2.5,
          -- damage only: 26084 applies no aura, which is why there is no aura trigger
          triggers = { { on = "SPELL_DAMAGE",          spellId = 26084, dest = "player" },
                       { on = "SPELL_PERIODIC_DAMAGE", spellId = 26084, dest = "player" } } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §7.4 FANKRISS THE UNYIELDING
-- ══════════════════════════════════════════════════════════════════════════════
-- ERA QUIRK: the three Entangle ids are the three teleport LOCATIONS, so all three
-- feed one bar. The Spawn of Fankriss summon has NO combat-log event at all — it is
-- caught on the unit-cast channel and synced, exactly like Maexxna's spiderlings.
Addon:RegisterEncounter({
    id = "aq40:fankriss", name = "Fankriss the Unyielding", zone = 531,
    creatureId = { 15510 }, encounterId = { 712 },
    legacy = { raidId = "aq40", bossId = "fankriss" },
    detect = { mode = "combat" },
    timers = {
        { key = "mortalwound", name = "Mortal Wound", kind = "target", spellId = 25646,
          color = 3, duration = 20, perTarget = true,
          icon = ICON .. "Ability_Criticalstrike",
          starts = { { on = "SPELL_AURA_APPLIED", spellId = 25646 },
                     { on = "SPELL_AURA_APPLIED_DOSE", spellId = 25646 } },
          stop   = { on = "SPELL_AURA_REMOVED", spellId = 25646 } },
        { key = "entangle", name = "Entangle", kind = "target", spellId = 720, color = 3,
          duration = 8, perTarget = true, icon = ICON .. "Spell_Nature_StrangleVines",
          start = { on = "SPELL_AURA_APPLIED", spellId = { 720, 731, 1121 } },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = { 720, 731, 1121 } } },
    },
    rosters = {
        { key = "wounded", name = "Mortal Wound carriers", aura = 25646,
          adds = { { on = "SPELL_AURA_APPLIED",      spellId = 25646 },
                   { on = "SPELL_AURA_APPLIED_DOSE", spellId = 25646 } },
          remove = { on = "SPELL_AURA_REMOVED", spellId = 25646 } },
    },
    warnings = {
        { key = "entangleon", name = "Entangle on <name>", tier = "announce", color = 2,
          noFilter = true, text = "Entangle on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = { 720, 731, 1121 } } },
        { key = "mortalwoundon", name = "Mortal Wound on <name>", tier = "announce",
          color = 3, role = "Tank", stacks = true, text = "Mortal Wound %s (%d)",
          triggers = { { on = "SPELL_AURA_APPLIED",      spellId = 25646 },
                       { on = "SPELL_AURA_APPLIED_DOSE", spellId = 25646 } } },
        { key = "worms", name = "Summon Worm", tier = "announce", color = 3,
          text = "Worm summoned", icon = ICON .. "Spell_Nature_InsectSwarm",
          trigger = { on = "SPELL_SUMMON", spellId = { 518, 25831, 25832 }, antispam = 3 } },
        { key = "spawnwarn", name = "Spawn of Fankriss", tier = "announce", color = 3,
          text = "Spawn of Fankriss",
          trigger = { on = "unitCast", spellId = { 26630, 26631, 26632 }, sync = true } },
        { key = "killspawns", name = "Kill the spawns", tier = "special", sound = 2,
          voice = "killmob", role = "Dps", text = "Kill the spawns",
          trigger = { on = "unitCast", spellId = { 26630, 26631, 26632 }, sync = true } },
        { key = "woundstack", name = "Mortal Wound 5+ on YOU", tier = "special", sound = 1,
          soundClass = 6, voice = "stackhigh", text = "Mortal Wound stacks are high",
          triggers = { { on = "SPELL_AURA_APPLIED_DOSE", spellId = 25646,
                         dest = "player", stacks = 5 },
                       { on = "SPELL_AURA_APPLIED", spellId = 25646,
                         dest = "player", stacks = 5 } } },
        { key = "woundtaunt", name = "Taunt — <name> is at 5+", tier = "special", sound = 1,
          voice = "tauntboss", role = "Tank", text = "Taunt — %s is at 5 stacks",
          triggers = { { on = "SPELL_AURA_APPLIED_DOSE", spellId = 25646, dest = "other",
                         stacks = 5, roster = "wounded",
                         condition = { "playerAlive", "playerNotInRoster" } },
                       { on = "SPELL_AURA_APPLIED", spellId = 25646, dest = "other",
                         stacks = 5, roster = "wounded",
                         condition = { "playerAlive", "playerNotInRoster" } } } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §7.5 VISCIDUS  — the emote state machine and the hit-rate counters
-- ══════════════════════════════════════════════════════════════════════════════
-- The whole fight is a five-step emote machine with two ways out of "frozen":
--
--     normal -- "begins to slow"        --> freeze1
--            -- "is freezing up"        --> freeze2
--            -- "is frozen solid"       --> frozen      (stop the volley bar, zero the counters)
--     frozen -- "begins to crack"       --> shatter1
--            -- "looks ready to shatter"--> shatter2    (start the 16.5 s rejoin bar)
--            -- HE SWINGS AT SOMEONE    --> normal      (a FAILED shatter — see below)
--   shatter2 -- the globs recombine     --> normal
--
-- THE FAILED SHATTER is the interesting one. There is no "he unfroze" event on Era at
-- all; the only tell is that a frozen boss cannot melee, so a swing landing MORE THAN
-- 5 s after he froze means he is not frozen any more. "More than 5 s after he froze"
-- is a property of the MACHINE, not of the swing, which is what `minStateAge` is
-- (W4c grammar extension 18). The 5 s floor is what keeps the swing that was already
-- in flight when he froze from immediately unfreezing him.
--
-- THE HIT COUNTERS are the mod's most unusual feature and the design case for rate
-- counters (extension 14): while thawed the raid needs frost hits per second against
-- a 200-hit goal; while frozen it needs melee hits per second. Frost is matched on the
-- school BITMASK, not on a spell list, because every frost effect in the game counts.
-- Every path out of a freeze zeroes both counters.
--
-- ERA NOTES: a sixth phase emote referenced by older mods does not exist in Classic
-- and is deliberately not implemented. Two "Viscidus Frost Weakness" spells (25926,
-- 1215736) are observed on the unit-cast channel with unresolved meaning; they are
-- logged for research and are NOT rows.
Addon:RegisterEncounter({
    id = "aq40:viscidus", name = "Viscidus", zone = 531,
    creatureId = { 15299 }, encounterId = { 713 },
    legacy = { raidId = "aq40", bossId = "viscidus" },
    detect = { mode = "combat" },
    timers = {
        { key = "poisonvolley", name = "Poison Bolt Volley", kind = "cd", spellId = 25991,
          color = 2, count = true, icon = ICON .. "Spell_Nature_CorrosiveBreath",
          pull = "v11.3-12.9", duration = 11.3,
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 25991 },
          stop    = { on = "state", fromKey = "phase", where = { to = "frozen" } } },
        { key = "rejoin", name = "Rejoin (globs recombine)", kind = "next", spellId = 25896,
          color = 1, duration = 16.5, icon = ICON .. "INV_Misc_Slime_01",
          start = { on = "state", fromKey = "phase", where = { to = "shatter2" } } },
    },
    states = {
        { key = "phase", name = "Freeze / shatter", initial = "normal", transitions = {
            { on = "emote", textFind = "begins to slow",        to = "freeze1" },
            { on = "emote", textFind = "is freezing up",        to = "freeze2" },
            { on = "emote", textFind = "is frozen solid",       to = "frozen",
              actions = { { stopTimer = "poisonvolley" },
                          { resetCounters = { "frosthits", "meleehits" } } } },
            { on = "emote", textFind = "begins to crack",       to = "shatter1" },
            { on = "emote", textFind = "looks ready to shatter", to = "shatter2" },
            -- FAILED SHATTER: he swings, and he has been frozen for more than 5 s.
            { on = "SWING_DAMAGE", creatureId = 15299, stateKey = "phase", state = "frozen",
              minStateAge = 5, to = "normal",
              actions = { { resetCounters = { "frosthits", "meleehits" } } } },
            -- The globs recombining. Every surviving glob casts it; only the first is
            -- honoured, which is what the 8 s anti-spam is for.
            { on = "SPELL_CAST_SUCCESS", spellId = 25896, antispam = 8, to = "normal",
              actions = { { resetCounters = { "frosthits", "meleehits" } } } },
        } },
    },
    counters = {
        { key = "frosthits", name = "Frost hits", scope = "boss", goal = 200,
          rate = { window = 7, fallback = 15 },
          incs = { { on = "SPELL_DAMAGE",          school = 16, where = { destId = 15299 } },
                   { on = "SPELL_PERIODIC_DAMAGE", school = 16, where = { destId = 15299 } },
                   { on = "RANGE_DAMAGE",          school = 16, where = { destId = 15299 } } },
          resets = { { on = "state", fromKey = "phase", where = { to = "frozen" } },
                     { on = "state", fromKey = "phase", where = { to = "normal" } } } },
        { key = "meleehits", name = "Melee hits (frozen)", scope = "boss",
          rate = { window = 10, fallback = 20 },
          inc = { on = "SWING_DAMAGE", where = { destId = 15299 } },
          resets = { { on = "state", fromKey = "phase", where = { to = "frozen" } },
                     { on = "state", fromKey = "phase", where = { to = "normal" } } } },
    },
    warnings = {
        { key = "poisonvolleyN", name = "Poison Bolt Volley N", tier = "announce", color = 3,
          count = true, text = "Poison Bolt Volley %d",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 25991 } },
        { key = "slow", name = "Freeze 1/3", tier = "announce", color = 2, sync = true,
          text = "Freeze 1/3 — keep the frost coming",
          trigger = { on = "state", fromKey = "phase", where = { to = "freeze1" } } },
        { key = "freezing", name = "Freeze 2/3", tier = "announce", color = 2, sync = true,
          text = "Freeze 2/3 — keep the frost coming",
          trigger = { on = "state", fromKey = "phase", where = { to = "freeze2" } } },
        { key = "frozen", name = "Freeze 3/3 — frozen", tier = "announce", color = 2,
          sync = true, text = "Freeze 3/3 — FROZEN, melee now",
          trigger = { on = "state", fromKey = "phase", where = { to = "frozen" } } },
        { key = "crack", name = "Shatter 1/2", tier = "announce", color = 2, sync = true,
          text = "Shatter 1/2",
          trigger = { on = "state", fromKey = "phase", where = { to = "shatter1" } } },
        { key = "shatter", name = "Shatter 2/2", tier = "announce", color = 2, sync = true,
          text = "Shatter 2/2 — ready to shatter",
          trigger = { on = "state", fromKey = "phase", where = { to = "shatter2" } } },
        { key = "gtfo", name = "Poison cloud (GTFO)", tier = "special", sound = 1,
          soundClass = 8, voice = "watchfeet", text = "Move out of the poison",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 25989, dest = "player",
                      antispam = 3 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §7.6 PRINCESS HUHURAN
-- ══════════════════════════════════════════════════════════════════════════════
-- Berserk stops THREE bars at once (Sting, Frenzy, Poison Bolt) — after 30 % the
-- cadences stop meaning anything and a bar that keeps counting is a lie.
--
-- The Sting announce is the spec's one "collect targets for a second, then announce
-- the list" pattern: the bar restarts 1 s after the targets are collected, which is
-- an anti-spam of 1 s on the way in plus a 1 s deferral on the way out.
Addon:RegisterEncounter({
    id = "aq40:huhuran", name = "Princess Huhuran", zone = 531,
    creatureId = { 15509 }, encounterId = { 714 },
    legacy = { raidId = "aq40", bossId = "huhuran" },
    detect = { mode = "combat" },
    timers = {
        { key = "sting", name = "Wyvern Sting", kind = "cd", spellId = 26180, color = 2,
          icon = ICON .. "INV_Spear_02",
          pull = "v6.8-43.7", duration = "v25.9-59.2",
          start   = { on = "pull" },
          restart = { on = "SPELL_AURA_APPLIED", spellId = 26180, antispam = 1, delay = 1 },
          stop    = { on = "SPELL_AURA_APPLIED", spellId = 26068 } },
        { key = "stingfades", name = "Wyvern Sting fades", kind = "fades", spellId = 26180,
          color = 5, duration = 12,
          start = { on = "SPELL_AURA_APPLIED", spellId = 26180, dest = "player" } },
        -- 1.x key `noxious` preserved: same spell (26053), spec name (Poison Bolt).
        { key = "noxious", name = "Poison Bolt", kind = "cd", spellId = 26053, color = 2,
          icon = ICON .. "Ability_Creature_Poison_03",
          pull = "v11.3-38.8", duration = "v11.3-37.6",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 26053 },
          stop    = { on = "SPELL_AURA_APPLIED", spellId = 26068 } },
        { key = "poisonboltfades", name = "Poison Bolt fades", kind = "fades", spellId = 26053,
          color = 5, duration = 8,
          start = { on = "SPELL_AURA_APPLIED", spellId = 26053, dest = "player" } },
        { key = "frenzy", name = "Frenzy", kind = "cd", spellId = 26051, color = 2,
          icon = ICON .. "Ability_Druid_Berserk",
          pull = "v6.5-25.9", duration = "v11.3-25.9",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 26051 },
          stop    = { on = "SPELL_AURA_APPLIED", spellId = 26068 } },
        { key = "frenzyactive", name = "Frenzy (active)", kind = "active", spellId = 26051,
          color = 6, duration = 8,
          start = { on = "SPELL_AURA_APPLIED", spellId = 26051 } },
        { key = "acidspit", name = "Acid Spit", kind = "target", spellId = 26050, color = 3,
          duration = 30, perTarget = true, icon = ICON .. "Spell_Nature_Acid_01",
          starts = { { on = "SPELL_AURA_APPLIED", spellId = 26050 },
                     { on = "SPELL_AURA_APPLIED_DOSE", spellId = 26050 } },
          stop   = { on = "SPELL_AURA_REMOVED", spellId = 26050 } },
    },
    rosters = {
        { key = "acid", name = "Acid Spit carriers", aura = 26050,
          adds = { { on = "SPELL_AURA_APPLIED",      spellId = 26050 },
                   { on = "SPELL_AURA_APPLIED_DOSE", spellId = 26050 } },
          remove = { on = "SPELL_AURA_REMOVED", spellId = 26050 } },
    },
    warnings = {
        { key = "stingon", name = "Wyvern Sting on <names>", tier = "announce", color = 2,
          combine = 1.0, text = "Wyvern Sting on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 26180 } },
        { key = "acidspiton", name = "Acid Spit on <name>", tier = "announce", color = 3,
          role = "Tank", stacks = true, text = "Acid Spit %s (%d)",
          triggers = { { on = "SPELL_AURA_APPLIED",      spellId = 26050 },
                       { on = "SPELL_AURA_APPLIED_DOSE", spellId = 26050 } } },
        { key = "poisonboltwarn", name = "Poison Bolt", tier = "announce", color = 3,
          text = "Poison Bolt",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 26053 } },
        { key = "frenzywarn", name = "Frenzy", tier = "announce", color = 3,
          role = "Tank|RemoveEnrage|Healer", text = "Frenzy",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 26051 } },
        { key = "berserk", name = "Berserk", tier = "announce", color = 3, text = "Berserk",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 26068 } },
        { key = "berserksoon", name = "Berserk soon (35%)", tier = "announce", color = 2,
          text = "Berserk soon", trigger = { on = "health", pct = 35, sync = true } },
        { key = "dispelfrenzy", name = "Dispel the Frenzy", tier = "special", sound = 1,
          soundClass = 6, voice = "trannow", role = "RemoveEnrage",
          text = "Tranquilise the Frenzy",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 26051 } },
        { key = "acidstack", name = "Acid Spit 10+ on YOU", tier = "special", sound = 1,
          soundClass = 6, voice = "stackhigh", text = "Acid Spit stacks are high",
          triggers = { { on = "SPELL_AURA_APPLIED_DOSE", spellId = 26050,
                         dest = "player", stacks = 10 },
                       { on = "SPELL_AURA_APPLIED", spellId = 26050,
                         dest = "player", stacks = 10 } } },
        { key = "acidtaunt", name = "Taunt — <name> is at 10+", tier = "special", sound = 1,
          voice = "tauntboss", role = "Tank", text = "Taunt — %s is at 10 stacks",
          triggers = { { on = "SPELL_AURA_APPLIED_DOSE", spellId = 26050, dest = "other",
                         stacks = 10, roster = "acid",
                         condition = { "playerAlive", "playerNotInRoster" } },
                       { on = "SPELL_AURA_APPLIED", spellId = 26050, dest = "other",
                         stacks = 10, roster = "acid",
                         condition = { "playerAlive", "playerNotInRoster" } } } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §7.7 TWIN EMPERORS  (Vek'lor / Vek'nilash)
-- ══════════════════════════════════════════════════════════════════════════════
-- The teleport bar is driven by the teleport AURA rather than a cast, and carries a
-- 4 s spoken countdown because the swap is a positioning call the whole raid makes
-- together. Explode Bug only warns for a bug that is actually NEAR YOU — the only
-- proximity answer Era gives for a mob you are not targeting is whether it has a
-- nameplate, which is what the `sourceOnNameplate` predicate walks.
Addon:RegisterEncounter({
    id = "aq40:twinemps", name = "Twin Emperors", zone = 531,
    creatureId = { 15276, 15275 }, encounterId = { 715 },
    legacy = { raidId = "aq40", bossId = "twinemps" },
    detect = { mode = "combat" },
    combat = { highestHealth = true },
    timers = {
        { key = "berserk", name = "Berserk", kind = "berserk", color = 6, duration = 900,
          icon = ICON .. "Spell_Shadow_UnholyFrenzy", start = { on = "pull" } },
        { key = "teleport", name = "Twin Teleport", kind = "cd", spellId = 800, color = 6,
          icon = ICON .. "Spell_Arcane_Blink", countdown = { depth = 4 },
          pull = 30.8, duration = "v29.1-40.5",
          start   = { on = "pull" },
          restart = { on = "SPELL_AURA_APPLIED", spellId = { 799, 800 }, antispam = 5 } },
        { key = "unbalancing", name = "Unbalancing Strike", kind = "cd", spellId = 26613,
          color = 2, icon = ICON .. "Ability_Warrior_Disarm",
          pull = "v11.2-43.8", duration = "v9.7-37.3",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 26613 } },
        { key = "explodebug", name = "Explode Bug", kind = "cd", spellId = 804, color = 1,
          default = false, icon = ICON .. "Spell_Fire_SelfDestruct",
          duration = "v4.5-32.3",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 804 } },
        { key = "mutatebug", name = "Mutate Bug", kind = "cd", spellId = 802, color = 1,
          default = false, icon = ICON .. "INV_Misc_MonsterSpiderCarapace_01",
          duration = "v10.9-27.1",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 802 } },
    },
    warnings = {
        { key = "teleportwarn", name = "Teleport", tier = "announce", color = 3,
          text = "Teleport — swap sides",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = { 799, 800 }, antispam = 5 } },
        { key = "unbalancingon", name = "Unbalancing Strike on <name>", tier = "announce",
          color = 3, role = "Tank|Healer", text = "Unbalancing Strike on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 26613 } },
        { key = "mutatebugwarn", name = "Mutate Bug", tier = "announce", color = 2,
          default = false, text = "Mutate Bug",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 802 } },
        { key = "defensive", name = "Unbalancing Strike on YOU", tier = "special", sound = 1,
          voice = "defensive", role = "Tank", text = "Unbalancing Strike — use a defensive",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 26613, dest = "player" } },
        { key = "runawaybug", name = "Run away from the bug", tier = "special", sound = 1,
          voice = "runaway", text = "Run away from the bug",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 804,
                      condition = "sourceOnNameplate" } },
        { key = "gtfo", name = "Ground effect (GTFO)", tier = "special", sound = 1,
          soundClass = 8, voice = "watchfeet", text = "Move out of it", antispam = 2.5,
          triggers = { { on = "SPELL_AURA_APPLIED",    spellId = 26607, dest = "player" },
                       { on = "SPELL_DAMAGE",          spellId = 26607, dest = "player" },
                       { on = "SPELL_PERIODIC_DAMAGE", spellId = 26607, dest = "player" } } },
    },
    icons = {
        { key = "mutateicons", name = "Mutated bug nameplate icon", default = true,
          mode = "nameplate", clearOn = "remove",
          on = { on = "SPELL_AURA_APPLIED", spellId = 802 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §7.8 OURO
-- ══════════════════════════════════════════════════════════════════════════════
-- ERA QUIRK: EMERGE IS A SCHEDULE, NOT AN EVENT. Submerging stops the Blast, Sweep
-- and Submerge bars; 30 s later all three restart FROM THEIR PULL VALUES, which is
-- exactly a deferred start carrying its own duration (W4d extension 3 + extension 1
-- in combination). Once he berserks he never submerges again, so the submerge bar
-- stops for good and the Blast cooldown restarts from zero.
Addon:RegisterEncounter({
    id = "aq40:ouro", name = "Ouro", zone = 531,
    creatureId = { 15517 }, encounterId = { 716 },
    legacy = { raidId = "aq40", bossId = "ouro" },
    detect = { mode = "combat" },
    timers = {
        { key = "sandblast", name = "Sand Blast", kind = "cd", spellId = 26102, color = 2,
          icon = ICON .. "Spell_Nature_Cyclone",
          pull = "v20.1-26.3", duration = "v22.1-26.8",
          starts = { { on = "pull" },
                     -- emerge: 30 s after the submerge cast, back on the pull window
                     { on = "SPELL_CAST_SUCCESS", spellId = 26058, delay = 30,
                       duration = "v20.1-26.3" },
                     -- berserk: he stops submerging, so the cooldown restarts from zero
                     { on = "SPELL_AURA_APPLIED", spellId = 26615, duration = "v20.1-26.3" } },
          restart = { on = "SPELL_CAST_START", spellId = 26102 },
          stop    = { on = "SPELL_CAST_SUCCESS", spellId = 26058 } },
        { key = "sweep", name = "Sweep", kind = "cd", spellId = 26103, color = 2,
          icon = ICON .. "INV_Misc_MonsterTail_03",
          pull = "v22.6-25.9", duration = "v20.6-22.6",
          starts = { { on = "pull" },
                     { on = "SPELL_CAST_SUCCESS", spellId = 26058, delay = 30,
                       duration = "v22.6-25.9" } },
          restart = { on = "SPELL_CAST_START", spellId = 26103 },
          stop    = { on = "SPELL_CAST_SUCCESS", spellId = 26058 } },
        { key = "submerge", name = "Submerge", kind = "stage", color = 6, duration = 184,
          icon = ICON .. "Spell_Nature_Earthquake",
          starts = { { on = "pull" },
                     { on = "SPELL_CAST_SUCCESS", spellId = 26058, delay = 30,
                       duration = 184 } },
          stops = { { on = "SPELL_CAST_SUCCESS", spellId = 26058 },
                    { on = "SPELL_AURA_APPLIED", spellId = 26615 } } },
        { key = "emerge", name = "Emerge", kind = "stage", color = 6, duration = 30,
          icon = ICON .. "Spell_Nature_EarthBind",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 26058 },
          stop  = { on = "SPELL_AURA_APPLIED", spellId = 26615 } },
    },
    states = {
        { key = "berserked", initial = "no", transitions = {
            { on = "SPELL_AURA_APPLIED", spellId = 26615, to = "yes" },
        } },
    },
    warnings = {
        { key = "mounds", name = "Submerge", tier = "announce", color = 3,
          text = "Ouro submerging — mounds up",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 26058, antispam = 3,
                      states = { berserked = "no" } } },
        { key = "emergewarn", name = "Emerge", tier = "announce", color = 3,
          text = "Ouro emerging",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 26058, delay = 30,
                      states = { berserked = "no" } },
          cancel = { on = "SPELL_AURA_APPLIED", spellId = 26615 } },
        { key = "sweepwarn", name = "Sweep", tier = "announce", color = 2, role = "Tank",
          text = "Sweep",
          trigger = { on = "SPELL_CAST_START", spellId = 26103 } },
        { key = "berserk", name = "Berserk", tier = "announce", color = 3, text = "Berserk",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 26615 } },
        { key = "berserksoon", name = "Berserk soon (25%)", tier = "announce", color = 2,
          text = "Berserk soon", trigger = { on = "health", pct = 25, sync = true } },
        { key = "sandblastwarn", name = "Sand Blast incoming", tier = "special", sound = 2,
          voice = "stunsoon", text = "Sand Blast incoming",
          trigger = { on = "SPELL_CAST_START", spellId = 26102 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §7.9 C'THUN  — the crown of the zone
-- ══════════════════════════════════════════════════════════════════════════════
-- FOUR SPAWN TIMERS, THREE VALUE SETS. Every tentacle bar has a phase-1 cadence, a
-- one-off value at the moment phase 2 begins, and a different one-off value after a
-- Weakened. Those are three different mechanisms in the grammar and it is worth being
-- explicit about which is which:
--
--   phase-1 cadence     `pull` + `duration`     (the ordinary shape)
--   phase-2 cadence     `phaseDuration[2]`      (Eye Tentacles only: 45 -> 30)
--   the one-off values  a per-trigger `duration` on the `stage` / `emote` start
--
-- PHASE 2 IS THE EYE'S DEATH (CID 15589). It stops Dark Glare and the Claw Tentacles
-- permanently and re-seeds the other three bars. THE WEAKENED EMOTE re-seeds the same
-- three bars again and clears the stomach list.
--
-- THE STOMACH is the standout feature and needed two new engine primitives, both
-- general (see core_api.lua, W4c extensions 12 and 13):
--   * a ROSTER of everyone carrying the stomach debuff (26476) with their acid stack;
--   * a ROSTER-RELAYED SCAN, because the Flesh Tentacles (CID 15802) are inside the
--     stomach and literally cannot be seen from outside it. The only unit tokens that
--     resolve to them are `<stomached player>target`, so the scan borrows the eyes of
--     the people who were eaten. Dead tentacles are HELD in the dossier for 30 s
--     rather than vanishing (a sample that comes back empty is not proof of death),
--     and a Weakened tears the whole thing down.
--
-- ERA QUIRK: the eye beam's target can CHANGE after the cast begins, so the target
-- scan is deliberately delayed 0.1 s before it starts polling.
Addon:RegisterEncounter({
    id = "aq40:cthun", name = "C'Thun", zone = 531,
    creatureId = { 15589, 15727 }, encounterId = { 717 },
    killCreatureIds = { 15727 },
    legacy = { raidId = "aq40", bossId = "cthun" },
    detect = { mode = "combat" },
    combat = { wipeWindow = 25 },
    schedule = {
        -- Dark Glare's loop is a schedule, not a cast chain: 48 s from the pull, then
        -- every 86 s. It keeps ticking after phase 2 (a schedule cannot be cancelled
        -- by an event); everything that consumes it is gated on `stage = 1`, which is
        -- the same answer with none of the machinery.
        { key = "glareloop", name = "Dark Glare loop", gaps = { 48, 86, repeatFrom = 2 } },
    },
    timers = {
        { key = "darkglarecd", name = "Dark Glare", kind = "next", spellId = 26029,
          color = 4, icon = ICON .. "Spell_Shadow_Charm",
          pull = 48, duration = 86, countdown = { depth = 5 },
          starts = { { on = "pull" } },
          restarts = { { on = "schedule", fromKey = "glareloop", stage = 1 },
                       { on = "SPELL_CAST_START", spellId = 26029, stage = 1 } },
          stop = { on = "stage", stage = 2 } },
        { key = "darkglare", name = "Dark Glare (rotating)", kind = "active", spellId = 26029,
          color = 4, duration = 39, icon = ICON .. "Spell_Shadow_Charm",
          starts = { { on = "schedule", fromKey = "glareloop", stage = 1 },
                     { on = "SPELL_CAST_START", spellId = 26029, stage = 1 } },
          stop = { on = "stage", stage = 2 } },
        -- the BAR ships on; it is the ANNOUNCE the spec marks off by default
        { key = "clawtentacle", name = "Claw Tentacle", kind = "adds", color = 1,
          icon = ICON .. "INV_Misc_MonsterClaw_04",
          pull = 9, duration = 8,
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 26586, creatureId = 15725,
                      antispam = 5, antispamBy = "sourceId" },
          stop    = { on = "stage", stage = 2 } },
        { key = "eyetentacles", name = "Eye Tentacles", kind = "adds", color = 1,
          icon = ICON .. "INV_Misc_Eye_01",
          pull = 45, duration = 45, phaseDuration = { [2] = 30 },
          starts = { { on = "pull" },
                     { on = "stage", stage = 2, duration = 40.5 },
                     { on = "emote", textFind = "weakened", duration = 83 } },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 26586, creatureId = 15726,
                      antispam = 5, antispamBy = "sourceId" } },
        { key = "giantclaw", name = "Giant Claw Tentacle", kind = "adds", color = 1,
          icon = ICON .. "INV_Misc_MonsterClaw_04", duration = 60,
          starts = { { on = "stage", stage = 2, duration = 10.5 },
                     { on = "emote", textFind = "weakened", duration = 53 } },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 26586, creatureId = 15728,
                      antispam = 5, antispamBy = "sourceId" } },
        { key = "gianteye", name = "Giant Eye Tentacle", kind = "adds", color = 1,
          icon = ICON .. "INV_Misc_Eye_01", duration = 60,
          starts = { { on = "stage", stage = 2, duration = 41.3 },
                     { on = "emote", textFind = "weakened", duration = 83.7 } },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 26586, creatureId = 15334,
                      antispam = 5, antispamBy = "sourceId" } },
        { key = "weaken", name = "Weakened ends", kind = "stage", color = 6, duration = 45,
          icon = ICON .. "Spell_Shadow_Cripple",
          start = { on = "emote", textFind = "weakened" } },
    },
    phases = {
        -- the eye's death, and nothing else, is phase 2
        { stage = 2, on = "UNIT_DIED", creatureId = 15589, whenStage = 1, sync = true },
    },
    rosters = {
        -- Everyone the stomach has eaten, with their Digestive Acid stack. A Weakened
        -- empties it; so does climbing back out.
        { key = "stomach", name = "Stomach list", aura = 26476,
          adds = { { on = "SPELL_AURA_APPLIED",      spellId = 26476 },
                   { on = "SPELL_AURA_APPLIED_DOSE", spellId = 26476 } },
          remove = { on = "SPELL_AURA_REMOVED", spellId = 26476 },
          clear  = { on = "emote", textFind = "weakened" } },
    },
    scans = {
        -- 1.x key `eyebeam` preserved. §1.6 boss target scanner, deliberately delayed
        -- 0.1 s because the beam's target can change after the cast starts.
        { key = "eyebeam", name = "Eye Beam target scan", type = "poll",
          interval = 0.1, tries = 3, delay = 0.1, filter = "playersOnly",
          creatureId = 15589, warning = "eyebeamon",
          on = { on = "SPELL_CAST_START", spellId = 26134 } },
        -- The Flesh Tentacles, read through the eyes of the eaten.
        { key = "fleshtentacles", name = "Flesh Tentacle health (stomach)", type = "roster",
          roster = "stomach", creatureId = 15802, interval = 1, hold = 30,
          on   = { on = "roster", fromKey = "stomach", where = { added = true } },
          stop = { on = "emote", textFind = "weakened" } },
    },
    warnings = {
        { key = "eyetentacleswarn", name = "Eye Tentacle", tier = "announce", color = 2,
          text = "Eye Tentacle",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 26586, creatureId = 15726,
                      antispam = 5, antispamBy = "sourceId" } },
        { key = "clawtentaclewarn", name = "Claw Tentacle", tier = "announce", color = 2,
          default = false, text = "Claw Tentacle",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 26586, creatureId = 15725,
                      antispam = 5, antispamBy = "sourceId" } },
        { key = "gianteyewarn", name = "Giant Eye Tentacle", tier = "announce", color = 3,
          text = "Giant Eye Tentacle",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 26586, creatureId = 15334,
                      antispam = 5, antispamBy = "sourceId" } },
        { key = "giantclawwarn", name = "Giant Claw Tentacle", tier = "announce", color = 3,
          text = "Giant Claw Tentacle",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 26586, creatureId = 15728,
                      antispam = 5, antispamBy = "sourceId" } },
        { key = "phase1", name = "Phase 1", tier = "announce", color = 2, text = "Phase 1",
          trigger = { on = "pull" } },
        { key = "phase2", name = "Phase 2", tier = "announce", color = 2, text = "Phase 2",
          trigger = { on = "stage", stage = 2 } },
        -- Emitted by the scan above with the victim folded in (svc_scan's `warning`
        -- seam), which is why this row carries no trigger of its own.
        { key = "eyebeamon", name = "Eye Beam on <name>", tier = "announce", color = 3,
          text = "Eye Beam on %s", icon = ICON .. "INV_Misc_Eye_01" },
        { key = "darkglarerun", name = "Run from Dark Glare", tier = "special", sound = 3,
          voice = "laserrun", text = "Dark Glare — run",
          -- suppressed while you are dead or a ghost (spec)
          trigger = { on = "schedule", fromKey = "glareloop", stage = 1,
                      condition = "playerAlive" } },
        { key = "weakened", name = "C'Thun is weakened!", tier = "special", sound = 2,
          voice = "targetchange", sync = true, text = "C'Thun is WEAKENED — burn",
          trigger = { on = "emote", textFind = "weakened" } },
        { key = "eyebeamyou", name = "Eye Beam on YOU", tier = "special", sound = 1,
          voice = "targetyou", text = "Eye Beam on YOU", yell = "Eye Beam on me!",
          trigger = { on = "targetChanged", fromKey = "eyebeam", condition = "namesPlayer" } },
    },
    icons = {
        { key = "eyebeamicon", name = "Eye Beam raid icon", default = true,
          icon = 1, duration = 3,
          on = { on = "targetChanged", fromKey = "eyebeam" } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §7.10 AQ40 TRASH (zone-wide, live DURING boss fights too)
-- ══════════════════════════════════════════════════════════════════════════════
-- The Anubisath ALERTS, in full. The per-mob ability DOSSIER (the aura-scan half of
-- §7.10 — target/nameplate/1 Hz/Detect-Magic scans building a live ability table per
-- mob) is NOT shipped this wave and is reported as such; the alerts below are what
-- actually fire mid-pull and none of them depend on the dossier.
--
-- Reflects are read from the MISS TYPE plus the school (extension 16): the reflect
-- buffs are not reliably visible on Era, and Detect Magic — the one scan that could
-- read them — gets reflected itself for the Fire/Arcane flavour.
Addon:RegisterEncounter({
    id = "aq40:trash", name = "Temple of Ahn'Qiraj trash", zone = 531,
    legacy = { raidId = "aq40", bossId = "trash" },
    detect = { mode = "zone" },
    timers = {
        { key = "explodebar", name = "Explode (cast)", kind = "cast", spellId = 25698,
          color = 4, duration = 6, nameplate = true,
          icon = ICON .. "Spell_Fire_SelfDestruct",
          start = { on = "SPELL_AURA_APPLIED", spellId = 25698 },
          stop  = { on = "UNIT_DIED", creatureId = 15277 } },
        { key = "insanitytimer", name = "Cause Insanity", kind = "target", spellId = 26079,
          color = 3, duration = 10, perTarget = true,
          icon = ICON .. "Spell_Shadow_MindSteal",
          start = { on = "SPELL_AURA_APPLIED", spellId = 26079 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 26079 } },
        -- One nameplate bar per thunderclapping mob, re-armed on each clap, one per
        -- MOB per second — which is what `antispamBy` is for.
        { key = "thunderclap", name = "Thunderclap", kind = "cd", spellId = 26554,
          color = 2, duration = 7, nameplate = true,
          icon = ICON .. "Spell_Nature_Thunderclap",
          start = { on = "SPELL_DAMAGE", spellId = { 8732, 26554 },
                    antispam = 1, antispamBy = "sourceGUID" } },
    },
    warnings = {
        { key = "shadowstorm", name = "Move out of Shadow Storm", tier = "special", sound = 1,
          voice = "findshelter", text = "Move out of Shadow Storm",
          triggers = { { on = "SPELL_DAMAGE", spellId = { 26555, 26546 }, dest = "player",
                         antispam = 3 },
                       { on = "SPELL_PERIODIC_DAMAGE", spellId = { 26555, 26546 },
                         dest = "player", antispam = 3 } } },
        { key = "plagueyou", name = "Plague on YOU — run away", tier = "special", sound = 4,
          voice = "runaway", text = "Plague on YOU — run away", yell = "Plague on me!",
          triggers = { { on = "SPELL_AURA_APPLIED", spellId = 26556, dest = "player" },
                       { on = "SPELL_AURA_APPLIED", spellId = 26556,
                         where = { destIsPet = true } } } },
        { key = "plagueon", name = "Plague on <name>", tier = "announce", color = 3,
          noFilter = true, text = "Plague on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 26556, dest = "other" } },
        { key = "explode", name = "Explode — run", tier = "special", sound = 4,
          voice = "justrun", text = "Explode — run",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 25698 } },
        { key = "insanity", name = "Cause Insanity on <name>", tier = "announce", color = 3,
          noFilter = true, combine = 0.75, text = "Cause Insanity on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 26079 } },
        { key = "intimidatingshout", name = "Intimidating Shout", tier = "announce", color = 2,
          text = "Intimidating Shout",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19134, antispam = 3 } },
        { key = "summonadds", name = "Summon adds", tier = "announce", color = 2,
          role = "Dps", text = "Adds summoned",
          triggers = { { on = "SPELL_SUMMON", spellId = 17430 },
                       { on = "SPELL_SUMMON", spellId = 17431 } } },
        { key = "reflectshadowfrost", name = "Shadow/Frost reflect — stop attacking",
          tier = "special", sound = 1, voice = "stopattack",
          text = "Shadow/Frost reflect — stop casting",
          triggers = { { on = "SPELL_MISSED", source = "player",
                         missType = { "REFLECT", "DEFLECT" }, school = 32 },
                       { on = "SPELL_MISSED", source = "player",
                         missType = { "REFLECT", "DEFLECT" }, school = 16 } } },
        { key = "reflectfirearcane", name = "Fire/Arcane reflect — stop attacking",
          tier = "special", sound = 1, voice = "stopattack",
          text = "Fire/Arcane reflect — stop casting",
          triggers = { { on = "SPELL_MISSED", source = "player",
                         missType = { "REFLECT", "DEFLECT" }, school = 4 },
                       { on = "SPELL_MISSED", source = "player",
                         missType = { "REFLECT", "DEFLECT" }, school = 64 } } },
    },
})
