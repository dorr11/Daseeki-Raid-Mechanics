--[[
    Daseeki Raid Mechanics 2.0 — ZUL'GURUB (zone 309), encounter data
    (wave 4b, second half)

    SOURCE OF TRUTH: DBM_ERA_ENCOUNTERS_BEHAVIOR_SPEC.md §5 — the ten Zul'Gurub
    encounters. Room-1 material only: written from the behavioural spec, never from
    third-party source.

    NO 1.x PREDECESSOR. Zul'Gurub was never in the shipped data set — there is no
    data_zg.lua and therefore no SavedVariables continuity to preserve. Keys here are
    chosen fresh, in the same house style as enc_naxxramas.lua and enc_aq20.lua.

    THE TWO KEY SCHEMES COINCIDE (see enc_naxxramas.lua's header): an encounter is
    `zg:<boss>` and a row key is a mechanic id, so
          API.OptionKey(encId, rowKey) == Addon:MechKey("zg", boss, rowKey)
    and the option a player ticks is the SavedVariables entry the engine reads.

    ────────────────────────────────────────────────────────────────────────────────
    THREE THINGS THIS ZONE DOES THAT NOWHERE ELSE DOES
    ────────────────────────────────────────────────────────────────────────────────
    1. MANDOKIR'S GAZE IS READ FROM THE YELL, NOT THE COMBAT LOG. §5.4 is explicit that
       the yell arrives 1.5-2 s BEFORE the aura does, and 1.5 seconds is the difference
       between stopping and dying. So the yell is the primary trigger and the combat log
       is the fallback and the bar. The anti-spam key is scoped PER TARGET NAME.
    2. ARLOKK'S RETURN IS INFERRED FROM A SWING. Vanish has no combat-log event at all;
       it is caught on the unit-cast channel and synced, and she is known to be BACK
       because she hit somebody. A melee swing — hit OR miss — is the only witness.
    3. HAKKAR'S HARD MODE IS A HEALTH READING. There is no difficulty flag anywhere.
       The un-nerfed "all priests alive" fight is identified by his MAXIMUM HEALTH being
       at least 1,079,325, sampled off whatever unit token can see him. That is what the
       W4b unit-fact sweep (extension 22) and the numeric field test (extension 23) are
       for, and it is the reason the five Aspect timers below arm from a probe rather
       than from the pull.

    EDGE OF MADNESS SHIPS DEFAULT-OFF, ALL OF IT. §5.5 flags its own spell ids as
    wrong/duplicate and says in as many words: "Treat every ID here as unverified."
    Every row in that encounter therefore carries `default = false` and an in-data note.
    They are listed in the wave report for the owner to arbitrate; nothing here is
    deleted, because an unverified id is still the only id there is.
--]]

local _, Addon = ...

local ICON = "Interface\\Icons\\"

Addon:RegisterZone({
    id = "zg", name = "Zul'Gurub", order = 40,
    mapID = 309, size = 20, icon = ICON .. "INV_Misc_Idol_03",
})

-- §5.10: the un-nerfed Hakkar's maximum health. No difficulty flag exists; this number
-- IS the difficulty flag.
local HAKKAR_HARDMODE_HP = 1079325

-- ══════════════════════════════════════════════════════════════════════════════
--  §5.1 HIGH PRIEST VENOXIS
-- ══════════════════════════════════════════════════════════════════════════════
-- Half-stage 1.5 at 55 % emits "phase 2 soon"; the actual transformation is the
-- transform spell arriving on the UNIT-CAST channel while in that half-stage — which
-- is why the phase row is gated on `whenStage = 1.5` rather than on health alone.
Addon:RegisterEncounter({
    id = "zg:venoxis", name = "High Priest Venoxis", zone = 309,
    creatureId = { 14507 }, encounterId = { 784 },
    legacy = { raidId = "zg", bossId = "venoxis" },
    detect = { mode = "combat" },
    timers = {
        { key = "poisoncloud", name = "Poison cloud", kind = "active", spellId = 23861,
          color = 6, duration = 10, icon = ICON .. "Spell_Nature_CorrosiveBreath",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 23861 } },
        { key = "renew", name = "Renew on Venoxis", kind = "active", spellId = 23895,
          color = 4, duration = 15, icon = ICON .. "Spell_Holy_Renew",
          start = { on = "SPELL_AURA_APPLIED", spellId = 23895 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 23895 } },
        { key = "venoxisfire", name = "Venoxis' Fire on <name>", kind = "target",
          spellId = 23860, color = 3, duration = 8, perTarget = true,
          icon = ICON .. "Spell_Fire_Fire",
          start = { on = "SPELL_AURA_APPLIED", spellId = 23860 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 23860 } },
    },
    phases = {
        -- Half-stage: 55 % health is "nearly", not "now".
        { stage = 1.5, on = "health", pct = 55, whenStage = 1, sync = true },
        { stage = 2, on = "unitCast", spellId = 23849, whenStage = 1.5, sync = true },
    },
    warnings = {
        { key = "cloudwarn", name = "Poison cloud", tier = "announce", color = 2,
          text = "Poison cloud",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 23861 } },
        { key = "renewon", name = "Renew on Venoxis", tier = "announce", color = 3,
          role = "MagicDispeller", noFilter = true, text = "Renew on Venoxis",
          suppressedBy = "renewdispel",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 23895 } },
        { key = "fireon", name = "Venoxis' Fire on <name>", tier = "announce", color = 2,
          role = "MagicDispeller|Healer", noFilter = true, text = "Venoxis' Fire on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 23860 } },
        { key = "snakeson", name = "Summon Snakes on <name>", tier = "announce", color = 2,
          noFilter = true, text = "Summon Snakes on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 23865 } },
        { key = "phase1", name = "Phase 1", tier = "announce", color = 2, text = "Phase 1",
          trigger = { on = "pull" } },
        { key = "phase2", name = "Phase 2 — the serpent", tier = "announce", color = 2,
          voice = "ptwo", text = "Phase 2 — the serpent",
          trigger = { on = "stage", stage = 2 } },
        { key = "phase2soon", name = "Phase 2 soon (55%)", tier = "announce", color = 2,
          text = "Phase 2 soon",
          trigger = { on = "stage", stage = 1.5 } },
        { key = "renewdispel", name = "Dispel Renew", tier = "special", sound = 1,
          voice = "dispelboss", role = "MagicDispeller", text = "Dispel Renew NOW",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 23895 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §5.2 HIGH PRIESTESS JEKLIK
-- ══════════════════════════════════════════════════════════════════════════════
-- No bat-phase or dive tracking (spec). The interrupt call is filtered to casts you
-- could actually reach, which is what the warning layer's `interrupt` filter is.
Addon:RegisterEncounter({
    id = "zg:jeklik", name = "High Priestess Jeklik", zone = 309,
    creatureId = { 14517 }, encounterId = { 785 },
    legacy = { raidId = "zg", bossId = "jeklik" },
    detect = { mode = "combat" },
    timers = {
        { key = "greatheal", name = "Great Heal", kind = "next", spellId = 23954, color = 4,
          duration = 20, icon = ICON .. "Spell_Holy_GreaterHeal",
          start = { on = "SPELL_CAST_START", spellId = 23954 } },
        { key = "sonicburst", name = "Sonic Burst fades", kind = "fades", spellId = 23918,
          color = 2, duration = 10, icon = ICON .. "Spell_Shadow_Teleport",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 23918 } },
        { key = "scream", name = "Psychic Scream fades", kind = "fades", spellId = 22884,
          color = 2, duration = 4, icon = ICON .. "Spell_Shadow_Psychicscream",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 22884 } },
        { key = "swp", name = "Shadow Word: Pain on <name>", kind = "target", spellId = 23952,
          color = 3, duration = 18, perTarget = true,
          icon = ICON .. "Spell_Shadow_ShadowWordPain",
          start = { on = "SPELL_AURA_APPLIED", spellId = 23952 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 23952 } },
    },
    warnings = {
        { key = "sonicburstwarn", name = "Sonic Burst", tier = "announce", color = 3,
          text = "Sonic Burst",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 23918 } },
        { key = "screamwarn", name = "Psychic Scream", tier = "announce", color = 3,
          text = "Psychic Scream",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 22884 } },
        { key = "swpon", name = "Shadow Word: Pain on <name>", tier = "announce", color = 2,
          role = "MagicDispeller", noFilter = true, text = "Shadow Word: Pain on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 23952 } },
        { key = "healkick", name = "Interrupt Great Heal", tier = "special", sound = 1,
          voice = "kickcast", role = "HasInterrupt", filter = "interrupt",
          text = "Interrupt Great Heal",
          trigger = { on = "SPELL_CAST_START", spellId = 23954 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §5.3 HIGH PRIESTESS MAR'LI
-- ══════════════════════════════════════════════════════════════════════════════
-- No cooldown timers (spec) — everything here is a duration or an announce.
Addon:RegisterEncounter({
    id = "zg:marli", name = "High Priestess Mar'li", zone = 309,
    creatureId = { 14510 }, encounterId = { 786 },
    legacy = { raidId = "zg", bossId = "marli" },
    detect = { mode = "combat" },
    timers = {
        { key = "drainlife", name = "Drain Life on <name>", kind = "target", spellId = 24300,
          color = 3, duration = 7, perTarget = true, icon = ICON .. "Spell_Shadow_LifeDrain",
          start = { on = "SPELL_AURA_APPLIED", spellId = 24300 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 24300 } },
        { key = "corrosive", name = "Corrosive Poison on <name>", kind = "target",
          spellId = 24111, color = 3, duration = 30, perTarget = true,
          icon = ICON .. "Spell_Nature_CorrosiveBreath",
          start = { on = "SPELL_AURA_APPLIED", spellId = 24111 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 24111 } },
    },
    warnings = {
        { key = "spider", name = "Spawn Spider", tier = "announce", color = 2,
          text = "Spider spawned", icon = ICON .. "Ability_Hunter_Pet_Spider",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 24083 } },
        { key = "poisonvolley", name = "Poison Volley", tier = "announce", color = 2,
          role = "RemovePoison", text = "Poison Volley",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 24099 } },
        { key = "drainlifeon", name = "Drain Life on <name>", tier = "announce", color = 2,
          role = "MagicDispeller|Healer", noFilter = true, text = "Drain Life on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24300 } },
        { key = "corrosiveon", name = "Corrosive Poison on <name>", tier = "announce",
          color = 2, role = "RemovePoison", noFilter = true,
          text = "Corrosive Poison on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24111 } },
        { key = "enlargeon", name = "Enlarge on <name>", tier = "announce", color = 3,
          noFilter = true, text = "Enlarge on %s", suppressedBy = "enlargedispel",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24109 } },
        { key = "enlargedispel", name = "Dispel Enlarge", tier = "special", sound = 1,
          voice = "dispelboss", role = "MagicDispeller", text = "Dispel Enlarge NOW",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24109 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §5.4 BLOODLORD MANDOKIR
-- ══════════════════════════════════════════════════════════════════════════════
-- THE YELL IS THE MECHANIC. §5.4's Era quirk is load-bearing: the combat-log aura is
-- 1.5-2 s LATE, and that is exactly the window in which you are supposed to stop what
-- you are doing. So the raid announce and the personal special both trigger on the
-- YELL, and the aura only starts the duration bar.
--
-- The 3 s anti-spam is scoped PER TARGET NAME (extension 17), because two players
-- gazed within three seconds of each other is two facts, not one.
Addon:RegisterEncounter({
    id = "zg:mandokir", name = "Bloodlord Mandokir", zone = 309,
    creatureId = { 11382, 14988 }, encounterId = { 787 },
    legacy = { raidId = "zg", bossId = "mandokir" },
    detect = { mode = "combat" },
    timers = {
        { key = "gaze", name = "Watch (Gaze) on <name>", kind = "target", spellId = 24314,
          color = 4, duration = 6, perTarget = true, icon = ICON .. "Spell_Shadow_EvilEye",
          start = { on = "SPELL_AURA_APPLIED", spellId = 24314 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 24314 } },
        { key = "mortalstrike", name = "Mortal Strike on <name>", kind = "target",
          spellId = 16856, color = 3, duration = 5, perTarget = true,
          icon = ICON .. "Ability_Warrior_SavageBlow",
          start = { on = "SPELL_AURA_APPLIED", spellId = 16856 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 16856 } },
    },
    warnings = {
        { key = "enrage", name = "Enrage", tier = "announce", color = 3,
          role = "Tank|Healer", text = "Enrage",
          icon = ICON .. "Spell_Shadow_UnholyFrenzy",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24318 } },
        -- Yell FIRST (primary), combat log SECOND (fallback). Both throttled per name.
        { key = "gazeon", name = "Gaze on <name>", tier = "announce", color = 4,
          noFilter = true, text = "MANDOKIR IS WATCHING %s",
          icon = ICON .. "Spell_Shadow_EvilEye", triggers = {
            { on = "yell", textFind = "I'm watching you", antispam = 3,
              antispamBy = "destName" },
            { on = "SPELL_AURA_APPLIED", spellId = 24314, antispam = 3,
              antispamBy = "destName" },
          } },
        { key = "mortalstrikeon", name = "Mortal Strike on <name>", tier = "announce",
          color = 2, role = "Tank|Healer", noFilter = true, text = "Mortal Strike on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 16856 } },
        { key = "gazeyou", name = "Gaze on YOU — stop", tier = "special", sound = 3,
          voice = "stopcast", text = "MANDOKIR IS WATCHING YOU — STOP", triggers = {
            { on = "yell", textFind = "I'm watching you", condition = "namesPlayer",
              antispam = 3 },
            { on = "SPELL_AURA_APPLIED", spellId = 24314, dest = "player", antispam = 3 },
          } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §5.5 EDGE OF MADNESS  (Gri'lek / Hazza'rah / Renataki / Wushoolay)
-- ══════════════════════════════════════════════════════════════════════════════
-- ⚠ EVERY ROW HERE SHIPS OFF, DELIBERATELY. §5.5 ends with the sentence "This mod is
-- explicitly flagged internally as low-confidence (wrong/duplicate spell IDs
-- suspected, needs log review). Treat every ID here as unverified." — the SPEC AUTHORS
-- FLAG THESE IDS UNVERIFIED, and shipping an alert keyed to an id nobody has confirmed
-- is worse than shipping nothing: it teaches a raid to trust a bar that may never fire
-- or may fire on the wrong thing.
--
-- So the rows exist, keyed exactly as the spec writes them, with `default = false` on
-- every single one. A player who wants to help verify them can switch them on; nobody
-- gets them by accident. Listed in full in the wave report for the owner.
Addon:RegisterEncounter({
    id = "zg:edgeofmadness", name = "Edge of Madness", zone = 309,
    creatureId = { 15083 }, encounterId = { 788 },
    legacy = { raidId = "zg", bossId = "edgeofmadness" },
    detect = { mode = "combat" },
    timers = {
        -- spec authors flag these ids unverified
        { key = "sleep", name = "Sleep", kind = "active", spellId = 24664, color = 6,
          duration = 6, default = false, icon = ICON .. "Spell_Nature_Sleep",
          start = { on = "SPELL_AURA_APPLIED", spellId = 24664, antispam = 3 } },
        -- spec authors flag these ids unverified
        { key = "poisoncloud", name = "Poison cloud", kind = "active", spellId = 24683,
          color = 6, duration = 15, default = false,
          icon = ICON .. "Spell_Nature_CorrosiveBreath",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 24683 } },
        -- spec authors flag these ids unverified
        { key = "grilekkite", name = "Gri'lek kiting debuff", kind = "active", spellId = 24646,
          color = 6, duration = 15, default = false, icon = ICON .. "Ability_Rogue_Sprint",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 24646 } },
    },
    warnings = {
        -- spec authors flag these ids unverified
        { key = "illusions", name = "Summon Illusions", tier = "announce", color = 2,
          default = false, text = "Summon Illusions",
          trigger = { on = "SPELL_SUMMON", spellId = 24728 } },
        -- spec authors flag these ids unverified
        { key = "sleepwarn", name = "Sleep on <name>", tier = "announce", color = 2,
          default = false, text = "Sleep on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24664 } },
        -- spec authors flag these ids unverified
        { key = "chainburn", name = "Chain Burn", tier = "announce", color = 2,
          default = false, text = "Chain Burn",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 24684 } },
        -- spec authors flag these ids unverified
        { key = "frenzy", name = "Frenzy", tier = "announce", color = 2, default = false,
          text = "Frenzy", icon = ICON .. "Ability_Druid_Berserk",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 8269 } },
        -- spec authors flag these ids unverified
        { key = "vanish", name = "Vanish", tier = "announce", color = 2, default = false,
          text = "Vanish", icon = ICON .. "Ability_Vanish",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 24699 } },
        -- spec authors flag these ids unverified
        { key = "cloudwarn", name = "Poison cloud", tier = "announce", color = 2,
          default = false, text = "Poison cloud",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 24683 } },
        -- spec authors flag these ids unverified
        { key = "grilekmove", name = "Keep moving (Gri'lek)", tier = "special", sound = 1,
          voice = "keepmove", default = false, text = "KEEP MOVING",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 24646 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §5.6 HIGH PRIEST THEKAL
-- ══════════════════════════════════════════════════════════════════════════════
-- Three linked units, and the boss health display takes the HIGHEST of them so a
-- dead-but-resurrecting add cannot make the fight look nearly over.
--
-- The resurrection window opens on the "%s dies." EMOTE for the first of the three,
-- synced with a 20 s anti-spam so the second and third deaths do not restart it, and
-- it is closed by the phase-2 yell.
Addon:RegisterEncounter({
    id = "zg:thekal", name = "High Priest Thekal", zone = 309,
    creatureId = { 14509, 11348, 11347 }, encounterId = { 789 },
    legacy = { raidId = "zg", bossId = "thekal" },
    detect = { mode = "combat" },
    combat = { highestHealth = true, severalCreatureIdsOneBoss = true },
    timers = {
        { key = "resurrect", name = "Resurrection", kind = "stage", color = 6, duration = 15,
          icon = ICON .. "Spell_Holy_Resurrection",
          start = { on = "emote", textFind = " dies.", antispam = 20, sync = true },
          stop  = { on = "yell", textFind = "fill me with your RAGE" } },
        { key = "blind", name = "Blind on <name>", kind = "target", spellId = 21060,
          color = 3, duration = 10, perTarget = true, icon = ICON .. "Spell_Shadow_MindSteal",
          start = { on = "SPELL_AURA_APPLIED", spellId = 21060 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 21060 } },
        { key = "gouge", name = "Gouge on <name>", kind = "target", spellId = 12540,
          color = 3, duration = 4, perTarget = true, icon = ICON .. "Ability_Gouge",
          start = { on = "SPELL_AURA_APPLIED", spellId = 12540 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 12540 } },
    },
    phases = {
        { stage = 2, on = "yell", textFind = "fill me with your RAGE", whenStage = 1 },
    },
    warnings = {
        { key = "firstdown", name = "First add down — resurrection", tier = "announce",
          color = 1, text = "One down — resurrection in 15",
          trigger = { on = "emote", textFind = " dies.", antispam = 20, sync = true } },
        { key = "blindon", name = "Blind on <name>", tier = "announce", color = 2,
          text = "Blind on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 21060 } },
        { key = "gougeon", name = "Gouge on <name>", tier = "announce", color = 2,
          text = "Gouge on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 12540 } },
        { key = "zealots", name = "Summon Zealots", tier = "announce", color = 3,
          text = "Zealots summoned",
          trigger = { on = "SPELL_SUMMON", spellId = 24183, antispam = 3 } },
        { key = "phase1", name = "Phase 1", tier = "announce", color = 2, text = "Phase 1",
          trigger = { on = "pull" } },
        { key = "phase2", name = "Phase 2", tier = "announce", color = 2, voice = "ptwo",
          text = "Phase 2 — Thekal enrages",
          trigger = { on = "stage", stage = 2 } },
        { key = "healkick", name = "Interrupt Great Heal", tier = "special", sound = 1,
          voice = "kickcast", role = "HasInterrupt", filter = "interrupt",
          text = "Interrupt Great Heal",
          trigger = { on = "SPELL_CAST_START", spellId = 24208 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §5.7 GAHZ'RANKA
-- ══════════════════════════════════════════════════════════════════════════════
-- The thinnest mod in the zone, and deliberately so: two cast announces, no timers, no
-- specials, no target tracking. Anything more would be invented.
Addon:RegisterEncounter({
    id = "zg:gahzranka", name = "Gahz'ranka", zone = 309,
    creatureId = { 15114 }, encounterId = { 790 },
    legacy = { raidId = "zg", bossId = "gahzranka" },
    detect = { mode = "combat" },
    warnings = {
        { key = "frostbreath", name = "Frost Breath", tier = "announce", color = 3,
          text = "Frost Breath", icon = ICON .. "Spell_Frost_FrostBolt02",
          trigger = { on = "SPELL_CAST_START", spellId = 16099 } },
        { key = "geyser", name = "Massive Geyser", tier = "announce", color = 3,
          text = "Massive Geyser", icon = ICON .. "Spell_Frost_SummonWaterElemental",
          trigger = { on = "SPELL_CAST_START", spellId = 22421 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §5.8 HIGH PRIESTESS ARLOKK
-- ══════════════════════════════════════════════════════════════════════════════
-- ERA QUIRK, and the reason there is a SWING trigger in this file: Vanish produces no
-- combat-log event whatsoever. It is caught on the unit-cast channel and synced, and
-- her RETURN is inferred from her first melee swing afterwards — hit or miss, which is
-- why both SWING_DAMAGE and SWING_MISSED restart the cooldown. A missed swing is still
-- proof she is standing there.
Addon:RegisterEncounter({
    id = "zg:arlokk", name = "High Priestess Arlokk", zone = 309,
    creatureId = { 14515 }, encounterId = { 791 },
    legacy = { raidId = "zg", bossId = "arlokk" },
    detect = { mode = "combat" },
    timers = {
        { key = "vanishcd", name = "Vanish", kind = "cd", spellId = 24223, color = 2,
          icon = ICON .. "Ability_Vanish",
          pull = "v33.7-34.4", duration = "v65-70",
          starts = { { on = "pull" },
                     -- she is back: the first swing after the vanish
                     { on = "SWING_DAMAGE", creatureId = 14515 },
                     { on = "SWING_MISSED", creatureId = 14515 } },
          stop = { on = "unitCast", spellId = 24223 } },
        { key = "vanishactive", name = "Vanish (active)", kind = "active", spellId = 24223,
          color = 6, duration = "v43.7-61.5", icon = ICON .. "Ability_Vanish",
          start = { on = "unitCast", spellId = 24223 },
          stops = { { on = "SWING_DAMAGE", creatureId = 14515 },
                    { on = "SWING_MISSED", creatureId = 14515 } } },
        { key = "swp", name = "Shadow Word: Pain on <name>", kind = "target", spellId = 24212,
          color = 3, duration = 18, perTarget = true,
          icon = ICON .. "Spell_Shadow_ShadowWordPain",
          start = { on = "SPELL_AURA_APPLIED", spellId = 24212 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 24212 } },
    },
    warnings = {
        { key = "markon", name = "Mark of Arlokk on <name>", tier = "announce", color = 3,
          noFilter = true, text = "Mark of Arlokk on %s",
          icon = ICON .. "Ability_Hunter_MarkedForDeath",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24210 } },
        { key = "swpon", name = "Shadow Word: Pain on <name>", tier = "announce", color = 2,
          role = "MagicDispeller", noFilter = true, text = "Shadow Word: Pain on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24212 } },
        { key = "vanishwarn", name = "Vanish", tier = "announce", color = 2, sync = true,
          text = "Arlokk vanished",
          trigger = { on = "unitCast", spellId = 24223 } },
        { key = "markyou", name = "Mark of Arlokk on YOU", tier = "special", sound = 1,
          voice = "targetyou", text = "Mark of Arlokk on YOU",
          yell = "Mark of Arlokk on me!",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24210, dest = "player" } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §5.9 JIN'DO THE HEXXER
-- ══════════════════════════════════════════════════════════════════════════════
-- Two "attack that thing instead" calls and one "your target has changed" call, all
-- three of which are the same instruction wearing different hats — and all three are
-- exactly what the `attacktotem` / `targetchange` voice classes exist for.
Addon:RegisterEncounter({
    id = "zg:jindo", name = "Jin'do the Hexxer", zone = 309,
    creatureId = { 11380 }, encounterId = { 792 },
    legacy = { raidId = "zg", bossId = "jindo" },
    detect = { mode = "combat" },
    timers = {
        { key = "hex", name = "Powerful Hex on <name>", kind = "target", spellId = 17172,
          color = 3, duration = 5, perTarget = true, icon = ICON .. "Spell_Shadow_Charm",
          start = { on = "SPELL_AURA_APPLIED", spellId = 17172 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 17172 } },
        { key = "delusions", name = "Delusions on <name>", kind = "target", spellId = 24306,
          color = 3, duration = 20, perTarget = true,
          icon = ICON .. "Spell_Shadow_MindSteal",
          start = { on = "SPELL_AURA_APPLIED", spellId = 24306 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 24306 } },
        { key = "brainwashcd", name = "Brain Wash Totem", kind = "cd", spellId = 24262,
          color = 2, icon = ICON .. "Spell_Nature_Purge",
          pull = "v11.3-30.9", duration = "v11.3-26.2",
          start   = { on = "pull" },
          restart = { on = "SPELL_SUMMON", spellId = 24262 } },
    },
    warnings = {
        { key = "delusionson", name = "Delusions on <name>", tier = "announce", color = 2,
          role = "RemoveCurse", noFilter = true, text = "Delusions on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24306 } },
        { key = "hexon", name = "Hex on <name>", tier = "announce", color = 2,
          role = "MagicDispeller", noFilter = true, text = "Hex on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 17172 } },
        { key = "brainwashon", name = "Brain Wash on <name>", tier = "announce", color = 4,
          noFilter = true, text = "BRAIN WASH on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24261 } },
        { key = "banishon", name = "Banish on <name>", tier = "announce", color = 2,
          noFilter = true, text = "Banish on %s",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 24466 } },
        { key = "healingward", name = "Kill the Healing Ward", tier = "special", sound = 1,
          voice = "attacktotem", role = "Dps", text = "KILL THE HEALING WARD",
          trigger = { on = "SPELL_SUMMON", spellId = 24309 } },
        { key = "brainwashtotem", name = "Kill the Brain Wash Totem", tier = "special",
          sound = 1, voice = "attacktotem", role = "Dps",
          text = "KILL THE BRAIN WASH TOTEM",
          trigger = { on = "SPELL_SUMMON", spellId = 24262 } },
        { key = "delusionsyou", name = "Attack the Ghosts (Delusions on YOU)",
          tier = "special", sound = 1, voice = "targetchange",
          text = "YOUR TARGET CHANGED — attack the Ghosts",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24306, dest = "player" } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §5.10 HAKKAR THE SOULFLAYER
-- ══════════════════════════════════════════════════════════════════════════════
-- HARD MODE IS A HEALTH READING, and that is the whole design of this encounter.
-- There is NO difficulty flag on Era: the only difference between the nerfed fight and
-- the "all five priests still alive" fight is that Hakkar has more health, so the mod
-- walks the raid looking for anyone whose target IS him and reads his MAXIMUM health.
-- At >= 1,079,325 the five Aspect timer sets arm.
--
-- Expressed with two W4b primitives and no bespoke code: a unit-fact sweep (22) that
-- reports his max health as an ordinary `probe` event, and a numeric field test (23)
-- on the trigger. The five Aspect bars therefore start from the PROBE, not from the
-- pull — which also means they start correctly on a fight we joined late, and never
-- start at all on a nerfed one.
--
-- LESSON CLASS 5 lives in the scanner: a maximum health of zero or nil is a COLD read,
-- not a small boss, and is never routed. A fight whose hard mode we cannot prove runs
-- as a normal fight, which is the safe direction to be wrong in.
Addon:RegisterEncounter({
    id = "zg:hakkar", name = "Hakkar the Soulflayer", zone = 309,
    creatureId = { 14834 }, encounterId = { 793 },
    legacy = { raidId = "zg", bossId = "hakkar" },
    detect = { mode = "combat" },
    scans = {
        { key = "hardmode", type = "unit", creatureId = 14834, interval = 2,
          maxHealth = true, on = { on = "pull" } },
    },
    timers = {
        { key = "berserk", name = "Berserk", kind = "berserk", duration = 585, color = 6,
          icon = ICON .. "Spell_Shadow_UnholyFrenzy", start = { on = "pull" } },
        { key = "siphon", name = "Blood Siphon", kind = "next", spellId = 24324, color = 2,
          duration = 90, icon = ICON .. "Spell_Shadow_LifeDrain",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 24324 } },
        { key = "insanitycd", name = "Cause Insanity", kind = "cd", spellId = 24327,
          color = 2, icon = ICON .. "Spell_Shadow_MindSteal",
          pull = "v20.7-22.7", duration = 21,
          start   = { on = "pull" },
          restart = { on = "SPELL_AURA_APPLIED", spellId = 24327 } },
        { key = "insanityon", name = "Cause Insanity on <name>", kind = "target",
          spellId = 24327, color = 3, duration = 10, perTarget = true,
          icon = ICON .. "Spell_Shadow_MindSteal",
          start = { on = "SPELL_AURA_APPLIED", spellId = 24327 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 24327 } },
        -- ── HARD MODE ONLY ────────────────────────────────────────────────────
        -- Each arms off the max-health probe and then runs on its own cast cycle. The
        -- probe repeats every 2 s, and re-arming a bar that is already running would be
        -- an early refresh — so each carries a `dedupe` on the boss GUID, which admits
        -- the first proof and refuses every later one.
        { key = "aspectmarli", name = "Aspect of Mar'li", kind = "cd", spellId = 24686,
          color = 2, icon = ICON .. "Ability_Hunter_Pet_Spider",
          pull = 10, duration = "v16-20",
          start   = { on = "probe", fromKey = "hardmode",
                      atLeast = { maxHealth = HAKKAR_HARDMODE_HP }, dedupe = "sourceGUID" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 24686 } },
        { key = "aspectthekal", name = "Aspect of Thekal", kind = "cd", spellId = 24689,
          color = 2, icon = ICON .. "Ability_Druid_Berserk",
          pull = 10, duration = 15.8,
          start   = { on = "probe", fromKey = "hardmode",
                      atLeast = { maxHealth = HAKKAR_HARDMODE_HP }, dedupe = "sourceGUID" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 24689 } },
        { key = "aspectvenoxis", name = "Aspect of Venoxis", kind = "cd", spellId = 24688,
          color = 2, icon = ICON .. "Spell_Nature_CorrosiveBreath",
          pull = 14, duration = "v16.2-18.3",
          start   = { on = "probe", fromKey = "hardmode",
                      atLeast = { maxHealth = HAKKAR_HARDMODE_HP }, dedupe = "sourceGUID" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 24688 } },
        { key = "aspectjeklik", name = "Aspect of Jeklik", kind = "cd", spellId = 24687,
          color = 2, icon = ICON .. "Spell_Shadow_Teleport",
          pull = 21, duration = "v23-24",
          start   = { on = "probe", fromKey = "hardmode",
                      atLeast = { maxHealth = HAKKAR_HARDMODE_HP }, dedupe = "sourceGUID" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 24687 } },
        { key = "aspectarlokk", name = "Aspect of Arlokk", kind = "next", spellId = 24690,
          color = 2, icon = ICON .. "Ability_Hunter_MarkedForDeath", duration = 30,
          start   = { on = "probe", fromKey = "hardmode",
                      atLeast = { maxHealth = HAKKAR_HARDMODE_HP }, dedupe = "sourceGUID" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 24690 } },
        { key = "marlion", name = "Aspect of Mar'li on <name>", kind = "target",
          spellId = 24686, color = 3, duration = 6, perTarget = true,
          icon = ICON .. "Ability_Hunter_Pet_Spider",
          start = { on = "SPELL_AURA_APPLIED", spellId = 24686 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 24686 } },
        -- OFF by default (spec): one bar per silenced player is genuinely spammy, and
        -- the spec's own note says an info frame is the right answer and is unbuilt.
        { key = "jeklikon", name = "Aspect of Jeklik on <name>", kind = "target",
          spellId = 24687, color = 3, duration = 5, perTarget = true, default = false,
          icon = ICON .. "Spell_Shadow_Teleport",
          start = { on = "SPELL_AURA_APPLIED", spellId = 24687 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 24687 } },
        { key = "thekalactive", name = "Aspect of Thekal (active)", kind = "active",
          spellId = 24689, color = 6, duration = 8, icon = ICON .. "Ability_Druid_Berserk",
          start = { on = "SPELL_AURA_APPLIED", spellId = 24689, dest = "other" },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 24689, dest = "other" } },
        { key = "arlokkon", name = "Aspect of Arlokk on <name>", kind = "target",
          spellId = 24690, color = 3, duration = 2, perTarget = true,
          icon = ICON .. "Ability_Hunter_MarkedForDeath",
          start = { on = "SPELL_AURA_APPLIED", spellId = 24690 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 24690 } },
    },
    warnings = {
        { key = "hardmodewarn", name = "Hard mode detected", tier = "announce", color = 2,
          text = "HARD MODE — all Aspects are live",
          trigger = { on = "probe", fromKey = "hardmode",
                      atLeast = { maxHealth = HAKKAR_HARDMODE_HP }, dedupe = "sourceGUID" } },
        -- Scheduled 80 s after the pull and 80 s after every Siphon, i.e. 10 s of lead.
        { key = "siphonsoon", name = "Blood Siphon soon", tier = "announce", color = 3,
          text = "Blood Siphon soon", triggers = {
            { on = "pull", delay = 80 },
            { on = "SPELL_CAST_SUCCESS", spellId = 24324, delay = 80 },
          } },
        { key = "insanitywarn", name = "Cause Insanity on <name>", tier = "announce",
          color = 4, noFilter = true, text = "Cause Insanity on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24327 } },
        -- FILTERED, not no-filter (spec): this one genuinely can be spammy.
        { key = "bloodon", name = "Blood of the Corruptor on <name>", tier = "announce",
          color = 2, text = "Blood of the Corruptor on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24328 } },
        { key = "marliwarn", name = "Aspect of Mar'li on <name>", tier = "announce",
          color = 2, noFilter = true, text = "Aspect of Mar'li on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24686 } },
        { key = "thekalwarn", name = "Aspect of Thekal", tier = "announce", color = 3,
          role = "Tank|RemoveEnrage|Healer", text = "Aspect of Thekal — tranq",
          suppressedBy = "thekaldispel",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24689, dest = "other" } },
        { key = "arlokkwarn", name = "Aspect of Arlokk on <name>", tier = "announce",
          color = 3, noFilter = true, text = "Aspect of Arlokk on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24690 } },
        { key = "thekaldispel", name = "Dispel Aspect of Thekal", tier = "special",
          sound = 1, voice = "enrage", role = "RemoveEnrage",
          text = "Tranquilizing Shot NOW",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24689, dest = "other" } },
    },
})
