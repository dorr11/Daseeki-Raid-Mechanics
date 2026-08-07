--[[
    Daseeki Raid Mechanics 2.0 — RUINS OF AHN'QIRAJ / AQ20 (zone 509), encounter data
    (wave 4c, first half)

    SOURCE OF TRUTH: DBM_ERA_ENCOUNTERS_BEHAVIOR_SPEC.md §6 — the six AQ20 encounters
    plus the zone-wide trash module. Every timer value, warning tier, audience gate,
    ship-off default, phase rule, emote trigger and scan in that section is a row
    below. Room-1 material only: written from the behavioural spec, never from
    third-party source.

    NO 1.x PREDECESSOR. Unlike AQ40, AQ20 was never in the shipped data set — there is
    no data_aq20.lua and therefore no SavedVariables continuity to preserve. Keys here
    are chosen fresh, in the same house style as enc_naxxramas.lua.

    THE TWO KEY SCHEMES COINCIDE (see enc_naxxramas.lua's header): an encounter is
    `aq20:<boss>` and a row key is a mechanic id, so
          API.OptionKey(encId, rowKey) == Addon:MechKey("aq20", boss, rowKey)
    and the option a player ticks is the SavedVariables entry the engine reads.

    ────────────────────────────────────────────────────────────────────────────────
    THE VANILLA TANK-SWAP BRANCH, ONCE, AS DATA
    ────────────────────────────────────────────────────────────────────────────────
    §6.1 names it and §6.4 / §7.4 / §7.6 repeat it: a stacking tank debuff produces
    THREE different alerts off one application —

        on YOU at N+           -> personal special, stack-high voice
        on SOMEONE ELSE at N+  -> "taunt" special, but only if you are clean and alive
        on anyone, any stack   -> the plain tank announce

    Arm two is three separate facts, so it is three separate predicates (W4c grammar
    extension 15) over a ROSTER (extension 12) the encounter keeps of everyone
    currently carrying the debuff. Every fight that has this shape uses the same
    three rows and the same roster; none of them has bespoke code.
--]]

local _, Addon = ...

local ICON = "Interface\\Icons\\"

Addon:RegisterZone({
    id = "aq20", name = "Ruins of Ahn'Qiraj", order = 50,
    mapID = 509, size = 20, icon = ICON .. "INV_Misc_AhnQirajTrinket_02",
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §6.1 KURINNAXX
-- ══════════════════════════════════════════════════════════════════════════════
-- The Sand Trap bar is keyed off the TRAP OBJECT being created, not off a cast that
-- resolves: the spec gives the pair (25656 cast / 25648 created object) and the
-- object is what the raid can actually see. Both paths restart the same bar.
Addon:RegisterEncounter({
    id = "aq20:kurinnaxx", name = "Kurinnaxx", zone = 509,
    creatureId = { 15348 }, encounterId = { 718 },
    legacy = { raidId = "aq20", bossId = "kurinnaxx" },
    detect = { mode = "combat" },
    timers = {
        { key = "sandtrap", name = "Sand Trap", kind = "cd", spellId = 25656, color = 2,
          icon = ICON .. "Spell_Nature_EarthBind", duration = 8,
          start = { on = "pull" },
          restarts = {
            { on = "SPELL_SUMMON",       spellId = 25648 },
            { on = "SPELL_CAST_SUCCESS", spellId = 25656 },
          } },
        { key = "mortalwound", name = "Mortal Wound", kind = "target", spellId = 25646,
          color = 3, duration = 15, perTarget = true,
          icon = ICON .. "Ability_Criticalstrike",
          starts = { { on = "SPELL_AURA_APPLIED", spellId = 25646 },
                     { on = "SPELL_AURA_REFRESH", spellId = 25646 },
                     { on = "SPELL_AURA_APPLIED_DOSE", spellId = 25646 } },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 25646 } },
    },
    -- Who is carrying Mortal Wound right now, and at what stack. The taunt branch
    -- asks this roster "am I clean?" rather than re-reading the debuff bar.
    rosters = {
        { key = "wounded", name = "Mortal Wound carriers", aura = 25646,
          adds = { { on = "SPELL_AURA_APPLIED",      spellId = 25646 },
                   { on = "SPELL_AURA_APPLIED_DOSE", spellId = 25646 },
                   { on = "SPELL_AURA_REFRESH",      spellId = 25646 } },
          remove = { on = "SPELL_AURA_REMOVED", spellId = 25646 } },
    },
    warnings = {
        { key = "sandtrapon", name = "Sand Trap under <name>", tier = "announce", color = 3,
          text = "Sand Trap under %s", noFilter = true,
          icon = ICON .. "Spell_Nature_EarthBind",
          triggers = { { on = "SPELL_SUMMON",       spellId = 25648 },
                       { on = "SPELL_CAST_SUCCESS", spellId = 25656 } } },
        { key = "mortalwoundon", name = "Mortal Wound on <name>", tier = "announce",
          color = 2, role = "Tank", stacks = true, text = "Mortal Wound %s (%d)",
          triggers = { { on = "SPELL_AURA_APPLIED",      spellId = 25646 },
                       { on = "SPELL_AURA_APPLIED_DOSE", spellId = 25646 } } },
        { key = "enrage", name = "Enrage", tier = "announce", color = 3, text = "Enrage",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 26527 } },
        { key = "sandtrapyou", name = "Sand Trap on YOU", tier = "special", sound = 1,
          voice = "targetyou", text = "Sand Trap on YOU", yell = "Sand Trap on me!",
          triggers = { { on = "SPELL_SUMMON",       spellId = 25648, dest = "player" },
                       { on = "SPELL_CAST_SUCCESS", spellId = 25656, dest = "player" } } },
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
--  §6.2 GENERAL RAJAXX
-- ══════════════════════════════════════════════════════════════════════════════
-- Events are armed OUTSIDE combat: the boss himself may not engage until his eight
-- waves are done, so the encounter starts on the Andorov RP yell, not on a mob. Every
-- wave yell is matched by SUBSTRING (the spec notes some contain line breaks) and is
-- synced, with the engine's own "reject a sync from outside the zone" rule doing the
-- work the spec describes.
--
-- JUDGEMENT CALL (reported): the spec's single "Wave N" row is shipped as SEVEN rows,
-- one per distinct yell, because a warning row carries one text and the wave number is
-- the whole content of the alert. Seven checkboxes beats one checkbox that cannot say
-- which wave. Waves 1 and 2 share a yell in the spec and therefore share a row.
Addon:RegisterEncounter({
    id = "aq20:rajaxx", name = "General Rajaxx", zone = 509,
    creatureId = { 15341 }, encounterId = { 719 },
    legacy = { raidId = "aq20", bossId = "rajaxx" },
    detect = { mode = "combat_yellfind", yellFind = {
        "when I said I'd kill you last",
        "They come now. Try not to get yourself killed",
    } },
    timers = {
        -- 31 s until the wave starts moving, ~31.8 until it is in the room.
        { key = "pullwave", name = "First wave incoming", kind = "adds", color = 1,
          icon = ICON .. "Ability_Warrior_BattleShout", duration = 31.8,
          start = { on = "yell", textFind = "when I said I'd kill you last" } },
        { key = "order", name = "Order (Command Aura)", kind = "target", spellId = 25471,
          color = 3, duration = 10, perTarget = true,
          icon = ICON .. "Spell_Holy_AuraOfLight",
          start = { on = "SPELL_AURA_APPLIED", spellId = 25471 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 25471 } },
        { key = "thundercrashcloud", name = "Thundercrash cloud", kind = "active",
          spellId = 26550, color = 6, duration = 15,
          icon = ICON .. "Spell_Nature_Lightning",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 26550 } },
    },
    warnings = {
        { key = "wave12", name = "Waves 1 and 2", tier = "announce", color = 2,
          text = "Waves 1 and 2 incoming", sync = true,
          trigger = { on = "yell", textFind = "They come now. Try not to get yourself killed" } },
        { key = "wave3", name = "Wave 3", tier = "announce", color = 2,
          text = "Wave 3 incoming", sync = true,
          trigger = { on = "yell", textFind = "The time of our retribution is at hand" } },
        { key = "wave4", name = "Wave 4", tier = "announce", color = 2,
          text = "Wave 4 incoming", sync = true,
          trigger = { on = "yell", textFind = "No longer will we wait behind barred doors" } },
        { key = "wave5", name = "Wave 5", tier = "announce", color = 2,
          text = "Wave 5 incoming", sync = true,
          trigger = { on = "yell", textFind = "Fear is for the enemy! Fear and death!" } },
        { key = "wave6", name = "Wave 6", tier = "announce", color = 2,
          text = "Wave 6 incoming", sync = true,
          trigger = { on = "yell", textFind = "Staghelm will whimper and beg for his life" } },
        { key = "wave7", name = "Wave 7", tier = "announce", color = 2,
          text = "Wave 7 incoming", sync = true,
          trigger = { on = "yell", textFind = "Fandral! Your time has come!" } },
        { key = "wave8", name = "Wave 8 — Rajaxx engages", tier = "announce", color = 2,
          text = "Wave 8 — Rajaxx engages", sync = true,
          trigger = { on = "yell", textFind = "Impudent fool! I will kill you myself!" } },
        { key = "orderon", name = "Order on <name>", tier = "announce", color = 2,
          text = "Order on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 25471 } },
        { key = "cloud", name = "Thundercrash cloud", tier = "announce", color = 2,
          text = "Thundercrash cloud",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 26550 } },
        { key = "thundercrash", name = "Thundercrash", tier = "announce", color = 2,
          text = "Thundercrash",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 25599 } },
        { key = "orderyou", name = "Order on YOU", tier = "special", sound = 1,
          voice = "targetyou", text = "Order on YOU", yell = "Order on me!",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 25471, dest = "player" } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §6.3 MOAM
-- ══════════════════════════════════════════════════════════════════════════════
-- Deliberately thin. The mana drain and Arcane Eruption (25672) are NOT implemented:
-- the spec records a single observed data point at 325.8 s and marks it unverified,
-- and we do not ship a bar we cannot stand behind. No mana-fiend summon tracking.
Addon:RegisterEncounter({
    id = "aq20:moam", name = "Moam", zone = 509,
    creatureId = { 15340 }, encounterId = { 720 },
    legacy = { raidId = "aq20", bossId = "moam" },
    detect = { mode = "combat" },
    timers = {
        { key = "stoneform", name = "Stoneform", kind = "next", spellId = 25685, color = 2,
          icon = ICON .. "Spell_Nature_Stoneskintotem", duration = 90,
          starts  = { { on = "pull" } },
          restart = { on = "SPELL_AURA_REMOVED", spellId = 25685 } },
        { key = "stoneformactive", name = "Stoneform (active)", kind = "active",
          spellId = 25685, color = 6, duration = 90,
          icon = ICON .. "Spell_Nature_Stoneskintotem",
          start = { on = "SPELL_AURA_APPLIED", spellId = 25685 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 25685 } },
    },
    warnings = {
        { key = "stoneformwarn", name = "Stoneform", tier = "announce", color = 3,
          text = "Stoneform",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 25685 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §6.4 BURU THE GORGER
-- ══════════════════════════════════════════════════════════════════════════════
-- ERA QUIRK, load-bearing: Buru's pursuit has NO SPELL ID in the Era data set. The
-- only trigger that exists is the monster emote "<Buru> sets eyes on <player>!", so
-- the warning carries a custom text instead of an auto-localised spell name, and
-- "the emote names YOU" is answered by the `namesPlayer` predicate reading the emote
-- text — there is no aura to test.
Addon:RegisterEncounter({
    id = "aq20:buru", name = "Buru the Gorger", zone = 509,
    creatureId = { 15370 }, encounterId = { 721 },
    legacy = { raidId = "aq20", bossId = "buru" },
    detect = { mode = "combat" },
    timers = {
        { key = "dismember", name = "Dismember", kind = "target", spellId = 96, color = 3,
          duration = 10, perTarget = true, icon = ICON .. "Ability_Rogue_Eviscerate",
          starts = { { on = "SPELL_AURA_APPLIED", spellId = 96 },
                     { on = "SPELL_AURA_APPLIED_DOSE", spellId = 96 } },
          stop   = { on = "SPELL_AURA_REMOVED", spellId = 96 } },
    },
    rosters = {
        { key = "dismembered", name = "Dismember carriers", aura = 96,
          adds = { { on = "SPELL_AURA_APPLIED",      spellId = 96 },
                   { on = "SPELL_AURA_APPLIED_DOSE", spellId = 96 } },
          remove = { on = "SPELL_AURA_REMOVED", spellId = 96 } },
    },
    warnings = {
        { key = "pursue", name = "Pursue on <name>", tier = "announce", color = 3,
          text = "Buru is chasing %s", icon = ICON .. "Ability_Rogue_Sprint",
          trigger = { on = "emote", textFind = "sets eyes on" } },
        { key = "dismemberon", name = "Dismember on <name>", tier = "announce", color = 3,
          role = "Tank", stacks = true, text = "Dismember %s (%d)",
          triggers = { { on = "SPELL_AURA_APPLIED",      spellId = 96 },
                       { on = "SPELL_AURA_APPLIED_DOSE", spellId = 96 } } },
        { key = "pursueyou", name = "Buru is chasing YOU", tier = "special", sound = 4,
          voice = "justrun", text = "Buru is chasing YOU — RUN",
          trigger = { on = "emote", textFind = "sets eyes on", condition = "namesPlayer" } },
        { key = "dismemberstack", name = "Dismember 5+ on YOU", tier = "special", sound = 1,
          soundClass = 6, voice = "stackhigh", text = "Dismember stacks are high",
          triggers = { { on = "SPELL_AURA_APPLIED_DOSE", spellId = 96,
                         dest = "player", stacks = 5 },
                       { on = "SPELL_AURA_APPLIED", spellId = 96,
                         dest = "player", stacks = 5 } } },
        { key = "dismembertaunt", name = "Taunt — <name> is at 5+", tier = "special",
          sound = 1, voice = "tauntboss", role = "Tank",
          text = "Taunt — %s is at 5 stacks",
          triggers = { { on = "SPELL_AURA_APPLIED_DOSE", spellId = 96, dest = "other",
                         stacks = 5, roster = "dismembered",
                         condition = { "playerAlive", "playerNotInRoster" } },
                       { on = "SPELL_AURA_APPLIED", spellId = 96, dest = "other",
                         stacks = 5, roster = "dismembered",
                         condition = { "playerAlive", "playerNotInRoster" } } } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §6.5 AYAMISS THE HUNTER
-- ══════════════════════════════════════════════════════════════════════════════
-- Phase transitions are PURE HEALTH POLLING: 75 % is "phase 2 soon", 70 % is the
-- landing. No timers for the Lash/swarm mechanics and no stinger tracking (spec).
Addon:RegisterEncounter({
    id = "aq20:ayamiss", name = "Ayamiss the Hunter", zone = 509,
    creatureId = { 15369 }, encounterId = { 722 },
    legacy = { raidId = "aq20", bossId = "ayamiss" },
    detect = { mode = "combat" },
    timers = {
        { key = "paralyze", name = "Paralyze", kind = "target", spellId = 25725, color = 3,
          duration = 10, perTarget = true, icon = ICON .. "Spell_Nature_Sleep",
          start = { on = "SPELL_AURA_APPLIED", spellId = 25725 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 25725 } },
    },
    phases = {
        { stage = 2, on = "health", pct = 70, whenStage = 1, sync = true },
    },
    warnings = {
        { key = "paralyzeon", name = "Paralyze on <name>", tier = "announce", color = 3,
          text = "Paralyze on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 25725 } },
        { key = "phase1", name = "Phase 1", tier = "announce", color = 2, text = "Phase 1",
          trigger = { on = "pull" } },
        { key = "phase2", name = "Phase 2", tier = "announce", color = 2, text = "Phase 2",
          trigger = { on = "stage", stage = 2 } },
        { key = "phase2soon", name = "Phase 2 soon (75%)", tier = "announce", color = 2,
          text = "Phase 2 soon",
          trigger = { on = "health", pct = 75, stage = 1, sync = true } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §6.6 OSSIRIAN THE UNSCARRED
-- ══════════════════════════════════════════════════════════════════════════════
-- The five weakness auras each get their own 45 s bar and their own tier-1 caster
-- announce — five rows each, not one row with five spell ids, because the whole
-- point of the alert is WHICH school is open. No crystal-spawn tracking and no
-- specials (spec).
Addon:RegisterEncounter({
    id = "aq20:ossirian", name = "Ossirian the Unscarred", zone = 509,
    creatureId = { 15339 }, encounterId = { 723 },
    legacy = { raidId = "aq20", bossId = "ossirian" },
    detect = { mode = "combat" },
    timers = {
        { key = "tongues", name = "Curse of Tongues", kind = "cd", spellId = 25195,
          color = 2, icon = ICON .. "Spell_Shadow_CurseOfTounges",
          pull = "v17.8-50.2", duration = "v21-43.7",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 25195 } },
        { key = "cyclone", name = "Cyclone", kind = "target", spellId = 25189, color = 3,
          duration = 10, perTarget = true, icon = ICON .. "Spell_Nature_Cyclone",
          start = { on = "SPELL_AURA_APPLIED", spellId = 25189 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 25189 } },
        { key = "fireweakness", name = "Fire Weakness", kind = "active", spellId = 25177,
          color = 6, duration = 45, icon = ICON .. "Spell_Fire_Fire",
          start = { on = "SPELL_AURA_APPLIED", spellId = 25177 } },
        { key = "frostweakness", name = "Frost Weakness", kind = "active", spellId = 25178,
          color = 6, duration = 45, icon = ICON .. "Spell_Frost_FrostBolt02",
          start = { on = "SPELL_AURA_APPLIED", spellId = 25178 } },
        { key = "natureweakness", name = "Nature Weakness", kind = "active", spellId = 25180,
          color = 6, duration = 45, icon = ICON .. "Spell_Nature_Lightning",
          start = { on = "SPELL_AURA_APPLIED", spellId = 25180 } },
        { key = "arcaneweakness", name = "Arcane Weakness", kind = "active", spellId = 25181,
          color = 6, duration = 45, icon = ICON .. "Spell_Nature_WispSplode",
          start = { on = "SPELL_AURA_APPLIED", spellId = 25181 } },
        { key = "shadowweakness", name = "Shadow Weakness", kind = "active", spellId = 25183,
          color = 6, duration = 45, icon = ICON .. "Spell_Shadow_ShadowBolt",
          start = { on = "SPELL_AURA_APPLIED", spellId = 25183 } },
    },
    warnings = {
        { key = "supreme", name = "Supreme Mode", tier = "announce", color = 3,
          text = "Supreme Mode",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 25176 } },
        { key = "cycloneon", name = "Cyclone on <name>", tier = "announce", color = 4,
          text = "Cyclone on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 25189 } },
        { key = "firewarn", name = "Fire Weakness", tier = "announce", color = 1,
          role = "CasterDps", text = "Fire Weakness",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 25177 } },
        { key = "frostwarn", name = "Frost Weakness", tier = "announce", color = 1,
          role = "CasterDps", text = "Frost Weakness",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 25178 } },
        { key = "naturewarn", name = "Nature Weakness", tier = "announce", color = 1,
          role = "CasterDps", text = "Nature Weakness",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 25180 } },
        { key = "arcanewarn", name = "Arcane Weakness", tier = "announce", color = 1,
          role = "CasterDps", text = "Arcane Weakness",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 25181 } },
        { key = "shadowwarn", name = "Shadow Weakness", tier = "announce", color = 1,
          role = "CasterDps", text = "Shadow Weakness",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 25183 } },
        { key = "tongueswarn", name = "Curse of Tongues", tier = "announce", color = 2,
          role = "SpellCaster", text = "Curse of Tongues",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 25195 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §6.7 AQ20 TRASH (zone-wide, live DURING boss fights too)
-- ══════════════════════════════════════════════════════════════════════════════
-- Shares the Anubisath ability set with AQ40 trash (§7.10); this module carries the
-- AQ20-specific rows plus the two reflect alerts, which are identical in both zones.
--
-- REFLECTS ARE READ FROM THE MISS TYPE, NOT FROM A BUFF. The spec is explicit that
-- the Anubisath reflect buffs are not reliably visible, so the evidence is
-- REFLECT / DEFLECT on YOUR OWN spell plus the school bitmask of what bounced.
Addon:RegisterEncounter({
    id = "aq20:trash", name = "Ruins of Ahn'Qiraj trash", zone = 509,
    legacy = { raidId = "aq20", bossId = "trash" },
    detect = { mode = "zone" },
    timers = {
        -- One 6 s cast bar per exploding mob, cancelled when that mob dies.
        { key = "explodebar", name = "Explode (cast)", kind = "cast", spellId = 25698,
          color = 4, duration = 6, nameplate = true,
          icon = ICON .. "Spell_Fire_SelfDestruct",
          start = { on = "SPELL_AURA_APPLIED", spellId = 25698 },
          stop  = { on = "UNIT_DIED", creatureId = 15355 } },
        { key = "insanitytimer", name = "Cause Insanity", kind = "target", spellId = 26079,
          color = 3, duration = 10, perTarget = true,
          icon = ICON .. "Spell_Shadow_MindSteal",
          start = { on = "SPELL_AURA_APPLIED", spellId = 26079 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 26079 } },
    },
    warnings = {
        { key = "plagueon", name = "Plague on <name>", tier = "announce", color = 3,
          text = "Plague on %s", noFilter = true,
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 22997, dest = "other" } },
        { key = "plagueyou", name = "Plague on YOU — run away", tier = "special", sound = 4,
          voice = "runaway", text = "Plague on YOU — run away", yell = "Plague on me!",
          -- "you OR YOUR PET": Era's combat log gives a pet bit but no "is it MINE"
          -- bit, and Plague is only ever cast by an Anubisath onto the raid, so a
          -- plagued pet inside this instance is a raid pet.
          triggers = { { on = "SPELL_AURA_APPLIED", spellId = 22997, dest = "player" },
                       { on = "SPELL_AURA_APPLIED", spellId = 22997,
                         where = { destIsPet = true } } } },
        { key = "explode", name = "Explode — run", tier = "special", sound = 4,
          voice = "justrun", text = "Explode — run",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 25698 } },
        { key = "insanity", name = "Cause Insanity on <name>", tier = "announce", color = 3,
          text = "Cause Insanity on %s", noFilter = true, combine = 0.75,
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 26079 } },
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
    icons = {
        -- A hostile-nameplate marker on whatever just thunderclapped. One per MOB per
        -- second, which is what `antispamBy` exists for: a pull of four Anubisaths
        -- must not collapse into one marker.
        { key = "thunderclapicon", name = "Thunderclap nameplate icon", mode = "nameplate",
          on = { on = "SPELL_DAMAGE", spellId = { 8732, 26554 },
                 antispam = 1, antispamBy = "sourceGUID" } },
    },
})
