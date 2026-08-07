--[[
    Daseeki Raid Mechanics 2.0 — ONYXIA'S LAIR (zone 249), encounter data
    (wave 4a, second third)

    SOURCE OF TRUTH: DBM_ERA_ENCOUNTERS_BEHAVIOR_SPEC.md §3 — one encounter, three
    phases, no trash module. Room-1 material only.

    NO PARKED 1.x DATA. Onyxia's Lair never had a data file, so there is nothing to
    diff and no SavedVariables continuity to preserve (see enc_moltencore.lua's header
    for the full statement).

    ────────────────────────────────────────────────────────────────────────────────
    THE THREE THINGS WORTH READING BEFORE THE DATA
    ────────────────────────────────────────────────────────────────────────────────
    1. DEEP BREATH IS EIGHT SPELLS. The Era client emits a different breath id
       depending on which of the lair's perches Onyxia flew to, so the alert matches a
       LIST of eight ids on cast start with an 8 s anti-spam key. The spec is explicit
       that the emote-based detection used on later clients is deliberately avoided
       here, because a hunter pet breaks it — so there is no emote arm, on purpose.

    2. THE PHASES ARE YELLS; THE PRE-WARNINGS ARE HALF-STAGES. P1 -> P2 and P2 -> P3
       are boss yells (synced). The two "phase N soon" warnings come from the health
       poll and the spec models them as FRACTIONAL stages 1.5 and 2.5, with the
       explicit rule that a half-stage emits no stage-change announce — only the
       pre-warning. The stage register takes fractions natively (§8.5), and every
       announce row below carries an exact `stage` filter, so that rule falls out of
       the data rather than needing a suppression pass.

    3. THE JOKE SOUND PACK IS NOT SHIPPED, and this is a judgement call, reported.
       §3.1 describes a bundled pack of quotes from a well-known Vanilla raid
       recording, on by default, with clip schedules at pull, at each phase entry, on
       Tail Sweep hitting you, and on any raid death. Those clips are somebody else's
       audio assets; a clean-room rebuild cannot ship them, and a schedule with no
       clips is a set of checkboxes that do nothing. The one behaviour it uniquely
       depended on — Tail Sweep (15847), which the spec notes is matched BY NAME AS
       WELL AS BY ID on Era — therefore has no row here either, because outside the
       joke pack §3.1 gives it none.
--]]

local _, Addon = ...

local ICON = "Interface\\Icons\\"

Addon:RegisterZone({
    id = "onyxia", name = "Onyxia's Lair", order = 20,
    mapID = 249, size = 40, icon = ICON .. "INV_Misc_Head_Dragon_01",
})

-- §3.1's eight breath ids. One mechanic, eight spells, and NOT a guess: the spec
-- lists all eight and says why there are eight.
local DEEP_BREATH = { 17086, 18351, 18564, 18576, 18584, 18596, 18609, 18617 }

Addon:RegisterEncounter({
    id = "onyxia:onyxia", name = "Onyxia", zone = 249,
    creatureId = { 10184 }, encounterId = { 1084 },
    legacy = { raidId = "onyxia", bossId = "onyxia" },
    -- Combat by yell (§1.1): she is not reliably combat-detectable at the pull.
    detect = { mode = "combat_yellfind", yellFind = {
        "How fortuitous",
        "I must leave my lair in order to feed",
    } },
    timers = {
        -- Both ground-phase bars STOP on phase 2 — she is airborne and casts neither.
        { key = "flamebreath", name = "Flame Breath", kind = "cd", spellId = 18435, color = 2,
          icon = ICON .. "Spell_Fire_Fire",
          pull = "v11.3-28.5", duration = "v9.7-35.6",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_START", spellId = 18435 },
          stop    = { on = "stage", stage = 2 } },
        { key = "wingbuffet", name = "Wing Buffet", kind = "cd", spellId = 18500, color = 2,
          icon = ICON .. "Spell_Nature_Cyclone",
          pull = "v11.3-24.5", duration = "v17.8-32.4",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_START", spellId = 18500 },
          stop    = { on = "stage", stage = 2 } },
        -- A very wide window, and shipped anyway: §9.1's "if the maximum is more than
        -- double the minimum, a bar at the minimum misleads" heuristic is recorded
        -- there as the author's rule for WORLD BOSSES, and §3.1 ships this bar
        -- regardless. The spec wins over the heuristic where the two disagree.
        { key = "bellowingroar", name = "Bellowing Roar (Fear)", kind = "cd", spellId = 18431,
          color = 2, icon = ICON .. "Spell_Shadow_DeathScream", duration = "v9.7-58.3",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_START", spellId = 18431 } },
        { key = "deepbreathcast", name = "Deep Breath (cast)", kind = "cast", color = 4,
          duration = 5, icon = ICON .. "Spell_Fire_Incinerate",
          start = { on = "SPELL_CAST_START", spellId = DEEP_BREATH } },
    },
    scans = {
        -- §1.6 boss target scanner, 0.3 s x 6. Fireball has no target in the combat
        -- log at cast start, so her current target IS the answer.
        { key = "fireballscan", name = "Fireball target scan", type = "poll",
          interval = 0.3, tries = 6, filter = "playersOnly", creatureId = 10184,
          warning = "fireballon",
          on = { on = "SPELL_CAST_START", spellId = 18392 } },
    },
    phases = {
        -- NO `whenStage` GATE on the two yells, and that is deliberate rather than an
        -- omission: by the time she says "…from above" the register may already be at
        -- the FRACTIONAL 1.5, and a `whenStage = 1` filter is an equality test, so it
        -- would refuse the real phase change on every pull where the 70 % pre-warning
        -- had already fired. The yells happen once per pull and name their own phase,
        -- which is gate enough.
        { stage = 2, on = "yell", textFind = "I'll incinerate you all from above",
          sync = true },
        { stage = 3, on = "yell", textFind = "you'll need another lesson, mortals",
          sync = true },
        -- The two fractional pre-stages. They move the register and say nothing; the
        -- two `phaseNsoon` rows below are what the raid actually hears.
        { stage = 1.5, on = "health", pct = 70, whenStage = 1, sync = true, pre = true },
        { stage = 2.5, on = "health", pct = 45, whenStage = 2, sync = true, pre = true },
    },
    warnings = {
        { key = "phase1", name = "Phase 1", tier = "announce", color = 2, text = "Phase 1",
          trigger = { on = "pull" } },
        { key = "phase2", name = "Phase 2", tier = "announce", color = 2, voice = "ptwo",
          text = "Phase 2 — Onyxia takes off", icon = ICON .. "INV_Misc_Head_Dragon_01",
          trigger = { on = "stage", stage = 2 } },
        { key = "phase3", name = "Phase 3", tier = "announce", color = 2, voice = "pthree",
          text = "Phase 3 — Onyxia lands", icon = ICON .. "INV_Misc_Head_Dragon_01",
          trigger = { on = "stage", stage = 3 } },
        -- Hung off the HALF-stages, which is what makes "a half-stage announces
        -- nothing of its own" true without a second mechanism.
        { key = "phase2soon", name = "Phase 2 soon (70%)", tier = "announce", color = 2,
          text = "Phase 2 soon", trigger = { on = "stage", stage = 1.5 } },
        { key = "phase3soon", name = "Phase 3 soon (45%)", tier = "announce", color = 2,
          text = "Phase 3 soon", trigger = { on = "stage", stage = 2.5 } },
        -- SHIPS OFF (spec). Fed by the scan above as well as by its own trigger; the
        -- yell is the "it is you" half of the same row.
        { key = "fireballon", name = "Fireball on <name>", tier = "announce", color = 2,
          default = false, noFilter = true, text = "Fireball on %s",
          yell = "FIREBALL on me!", icon = ICON .. "Spell_Fire_FlameBolt",
          trigger = { on = "SPELL_CAST_START", spellId = 18392 } },
        { key = "wingbuffetwarn", name = "Wing Buffet", tier = "announce", color = 2,
          role = "Tank", text = "Wing Buffet — threat drop",
          icon = ICON .. "Spell_Nature_Cyclone",
          trigger = { on = "SPELL_CAST_START", spellId = 18500 } },
        -- SHIPS OFF (spec).
        { key = "knockaway", name = "Knock Away on <name>", tier = "announce", color = 2,
          default = false, noFilter = true, text = "Knock Away on %s",
          icon = ICON .. "INV_Gauntlets_05",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19633 } },
        -- THE HEADLINE ALERT. Eight ids, one mechanic, 8 s anti-spam.
        { key = "deepbreath", name = "Deep Breath", tier = "special", sound = 3,
          voice = "breathsoon", text = "DEEP BREATH",
          trigger = { on = "SPELL_CAST_START", spellId = DEEP_BREATH, antispam = 8 } },
        { key = "bellowingroarwarn", name = "Bellowing Roar (Fear)", tier = "special",
          sound = 2, voice = "fearsoon", text = "FEAR incoming",
          trigger = { on = "SPELL_CAST_START", spellId = 18431, antispam = 3 } },
    },
    icons = {
        -- ON by default (spec): skull on the Fireball target, for three seconds.
        { key = "fireballicon", name = "Fireball raid icon", default = true,
          mode = "fixed", icon = 8, hold = 3,
          on = { on = "SPELL_CAST_START", spellId = 18392 } },
    },
})

-- ERA GAPS recorded from §3.1 and §11, and deliberately NOT scaffolded:
--   * no whelp-wave timer and no Onyxian Warder tracking. The reference ships both as
--     disabled scaffolding; a checkbox that can never fire is worse than no checkbox.
--   * no trash module. §3 describes none, and the lair has one pull.
