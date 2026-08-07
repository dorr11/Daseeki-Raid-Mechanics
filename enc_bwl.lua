--[[
    Daseeki Raid Mechanics 2.0 — BLACKWING LAIR (zone 469), encounter data
    (wave 4b, first half)

    SOURCE OF TRUTH: DBM_ERA_ENCOUNTERS_BEHAVIOR_SPEC.md §4 — the eight Blackwing Lair
    encounters plus the zone-wide trash module. Every timer value, warning tier,
    audience gate, ship-off default, phase rule, emote trigger and scan in that section
    is a row below. Room-1 material only: written from the behavioural spec, never from
    third-party source.

    REPLACES data_bwl.lua. That file was the 1.x flat mechanic model; it was diffed
    against the spec row by row before deletion, the spec won every disagreement, and
    every disagreement is in the wave report and the CHANGELOG.

    SAVEDVARIABLES CONTINUITY. The 1.x file registered raid `bwl` with boss ids
    razorgore / vaelastrasz / broodlord / firemaw / ebonroc / flamegor / chromaggus /
    nefarian, and `Addon:MechKey(raidId, bossId, mechId)` is exactly the option key this
    grammar produces for `bwl:<boss>` + `<rowKey>`. So the boss ids are preserved
    verbatim, and where a spec row is recognisably the same mechanic as a 1.x row the
    ROW KEY is preserved too. Three keys are deliberately kept over their names:

      vaelastrasz:adrenaline  — 1.x shipped ONE row that was both a 20 s personal bar
                                and the "you are about to die" alert. The grammar splits
                                those. The key follows the LOUD half (the special),
                                because a player who switched that row off wanted the
                                shouting to stop; the bar is `adrenalinebar`.
      chromaggus:vulnshift    — 1.x shipped a blind recurring radial with a comment
                                saying it could not read the school. The spec's real
                                vulnerability bar takes the key.
      nefarian:landing        — 1.x detected phase 2 from a yell the spec says does not
                                exist. The key stays on the phase-2 announce; the
                                detection underneath it is now the progress poll.

    ────────────────────────────────────────────────────────────────────────────────
    CHROMAGGUS, AND WHY FOUR NEW PRIMITIVES EXIST
    ────────────────────────────────────────────────────────────────────────────────
    §4.7 is the most mechanically complex fight in this zone and the spec names it as
    one of the two that should drive the architecture. Four W4b grammar extensions come
    straight out of it, and every one of them is written as a primitive:

      restyles (19)  one bar, five identities — the vulnerability bar is recoloured,
                     re-iconed and renamed to the current school WITHOUT restarting,
                     because restarting would lie about the remaining time and would
                     trip the early-refresh tripwire with a false positive. W2 built
                     `Bars.Restyle` for exactly this and nothing could reach it.
      identBy  (20)  one bar per BREATH SPELL. He picks two of five breaths per
                     lockout and each recurs on its own 61.5 s clock; neither
                     `perTarget` nor `nameplate` is the identity of a breath.
      unit scan(22)  THE EVIDENCE PROBLEM. His vulnerability auras are only in the
                     combat log while somebody in the raid has Detect Magic on him, so
                     there are three independent evidence paths and no single one of
                     them is trustworthy: the combat-log aura, a sweep of his own buffs,
                     and the shimmer emote (which proves a change happened but not to
                     WHAT). LESSON CLASS 4/6 is wired into the scanner itself — a sweep
                     that finds nothing routes nothing, and NO path in this file can
                     clear the school. Absence of evidence is not absence.
      suppressedBy(26) the spec's "replaces the announce when enabled", which BWL uses
                     three times before Zul'Gurub uses it four more.

    The two pull breath bars are a separate labelled pair that must be MANUALLY
    STOPPED when their breath lands (a variance bar otherwise keeps counting into its
    window forever). That is what `stop` on `breath1` / `breath2` is doing, and the
    second one is gated on the breath COUNTER so the first breath cannot close it.
--]]

local _, Addon = ...

local ICON = "Interface\\Icons\\"

Addon:RegisterZone({
    id = "bwl", name = "Blackwing Lair", order = 30,
    mapID = 469, size = 40, icon = ICON .. "INV_Misc_Head_Dragon_01",
})

-- The five breath spells the spec lists ten ids for. Only five of them are NAMED
-- anywhere we can stand behind: the parked 1.x data named these five off Drew's own
-- 2026-07-26 combat logs (Incinerate 23309 and Ignite Flesh 23316 with measured 61.5 s
-- intervals; the other three from the same table). The remaining five ids are in every
-- TRIGGER set below — they announce, they start the cast bar, they restart the
-- cooldown — but they carry no NAME mapping, so a breath we cannot name simply keeps
-- the generic bar rather than being labelled with a guess.
local BREATHS = { 23308, 23309, 23310, 23312, 23313, 23314, 23315, 23316, 23187, 23189 }

-- The five vulnerability schools (§4.7). No Holy.
local VULN_FIRE, VULN_NATURE, VULN_FROST = 22277, 22280, 22278
local VULN_SHADOW, VULN_ARCANE           = 22279, 22281
local VULN_ALL = { VULN_FIRE, VULN_NATURE, VULN_FROST, VULN_SHADOW, VULN_ARCANE }

-- The five Brood Afflictions (§4.7). The mutation counter counts these on YOU.
local BROOD_RED, BROOD_GREEN, BROOD_BLUE = 23155, 23169, 23153
local BROOD_BLACK, BROOD_BRONZE          = 23154, 23170

-- ══════════════════════════════════════════════════════════════════════════════
--  §4.1 RAZORGORE THE UNTAMED
-- ══════════════════════════════════════════════════════════════════════════════
-- KILL DETECTION IS SPECIAL-CASED, and this is the fight the kill-stage gate (W4b
-- extension 24) exists for. Blizzard's ENCOUNTER_END is wrong here, so it is refused;
-- Razorgore dying in phase 1 (somebody dropped the orb) is a WIPE and dying in phase 2
-- is a kill. The spec describes the reference doing this by registering a decoy second
-- creature id so the "all dead" test can never pass; we express the rule itself
-- instead, so a reader can see WHY a death did not count.
--
-- The pull yell contains an embedded line break, so it is matched by SUBSTRING on
-- each side of the break.
Addon:RegisterEncounter({
    id = "bwl:razorgore", name = "Razorgore the Untamed", zone = 469,
    creatureId = { 12435 }, encounterId = { 610 },
    legacy = { raidId = "bwl", bossId = "razorgore" },
    detect = { mode = "combat_yellfind", yellFind = {
        "Intruders have breached the hatchery",
        "Protect the eggs at all costs",
    } },
    combat = { wipeWindow = 180, noEncounterEndKill = true, killMinStage = 2 },
    timers = {
        -- FIRST WAVE ONLY. The 1.x file free-ran this on a 47 s interval and said so in
        -- its own comment ("the bar keeps cycling after the eggs are done"); the spec is
        -- explicit that there is no recurring add timer.
        { key = "adds", name = "Adds spawning", kind = "adds", color = 1,
          icon = ICON .. "Ability_Warrior_Charge", duration = 47,
          start = { on = "pull" } },
    },
    phases = {
        -- Phase 2 begins when Razorgore's own mind-control link breaks.
        { stage = 2, on = "SPELL_CAST_SUCCESS", spellId = 23040 },
    },
    warnings = {
        { key = "phase1", name = "Phase 1", tier = "announce", color = 2, text = "Phase 1",
          trigger = { on = "pull" } },
        { key = "phase2", name = "Phase 2", tier = "announce", color = 2, text = "Phase 2",
          voice = "ptwo", trigger = { on = "stage", stage = 2 } },
        { key = "fireballvolley", name = "Fireball Volley", tier = "announce", color = 3,
          text = "Fireball Volley", icon = ICON .. "Spell_Fire_FlameBolt",
          suppressedBy = "losvolley",
          trigger = { on = "SPELL_CAST_START", spellId = 22425 } },
        { key = "conflagration", name = "Conflagration on <name>", tier = "announce",
          color = 2, text = "Conflagration on %s", combine = 0.3,
          icon = ICON .. "Spell_Fire_Incinerate",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 23023 } },
        -- §4.1: on Era EVERY egg is announced (retail throttles to every third), and
        -- the count is the whole content of the alert.
        { key = "destroyegg", name = "Eggs destroyed", tier = "announce", color = 1,
          count = true, text = "Eggs destroyed %d/30", icon = ICON .. "INV_Egg_05",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19873 } },
        -- SHIPS OFF (spec). With it off, the plain cast announce above carries the
        -- mechanic; with it on, the announce steps aside.
        { key = "losvolley", name = "Break line of sight (Fireball Volley)",
          tier = "special", sound = 2, voice = "findshelter", default = false,
          text = "Fireball Volley — break line of sight",
          trigger = { on = "SPELL_CAST_START", spellId = 22425 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §4.2 VAELASTRASZ THE CORRUPT
-- ══════════════════════════════════════════════════════════════════════════════
-- The 43.5 s forced-dialogue window is a PULL COUNTDOWN, not an encounter timer:
-- nothing is engaged yet when "Too late, friends!" is heard, so there is no runtime
-- for a trigger to route into. W4b extension 25 hangs it off the engine's own §11.4
-- pull timer, which is the surface that already knows how to count a raid in.
--
-- The run-out special is SCHEDULED 15 s after the debuff lands — five seconds before
-- it kills you — and everything the debuff owns (that schedule, the fade countdown and
-- the target bar) is CANCELLED if it is removed early.
Addon:RegisterEncounter({
    id = "bwl:vaelastrasz", name = "Vaelastrasz the Corrupt", zone = 469,
    creatureId = { 13020 }, encounterId = { 611 },
    legacy = { raidId = "bwl", bossId = "vaelastrasz" },
    detect = { mode = "combat", pullCountdown = {
        seconds = 43.5, source = "encounter", yellFind = { "Too late, friends" } } },
    timers = {
        { key = "adrenalinecd", name = "Burning Adrenaline", kind = "cd", spellId = 18173,
          color = 2, icon = ICON .. "Spell_Fire_Immolation", duration = "v16.1-17.8",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 18173 } },
        -- One bar per victim, 20 s, with the voice countdown over the last five —
        -- which is as close as the engine gets to the spec's "fades yell" (see the
        -- wave report: the CHAT yell half has no surface yet).
        { key = "adrenalinebar", name = "Burning Adrenaline on <name>", kind = "target",
          spellId = 18173, color = 3, duration = 20, perTarget = true,
          countdown = { depth = 5 }, icon = ICON .. "Spell_Fire_Immolation",
          start = { on = "SPELL_AURA_APPLIED", spellId = 18173 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 18173 } },
    },
    warnings = {
        { key = "flamebreath", name = "Flame Breath", tier = "announce", color = 2,
          role = "Tank", text = "Flame Breath", icon = ICON .. "Spell_Fire_Fire",
          trigger = { on = "SPELL_CAST_START", spellId = 23461 } },
        { key = "adrenalineon", name = "Burning Adrenaline on <name>", tier = "announce",
          color = 2, noFilter = true, text = "Burning Adrenaline on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 18173, dest = "other" } },
        { key = "adrenaline", name = "Burning Adrenaline on YOU", tier = "special",
          sound = 4, voice = "targetyou", yell = "BURNING ADRENALINE on me!",
          text = "BURNING ADRENALINE — burn your mana and get out",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 18173, dest = "player" } },
        { key = "adrenalinerunout", name = "Run out (Burning Adrenaline)", tier = "special",
          sound = 1, voice = "runout", text = "RUN OUT — you are about to explode",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 18173, dest = "player",
                      delay = 15 },
          cancel  = { on = "SPELL_AURA_REMOVED", spellId = 18173, dest = "player" } },
        -- ADDITIVE, AND FLAGGED FOR ARBITRATION. Fire Nova is NOT in §4.2 at all, but
        -- the parked 1.x file carried it as `-- log-verified 2026-07-26: intervals
        -- 3.2-4.9` off Drew's own captured logs, shipped OFF, and the standing rule is
        -- that a log-verified fact the spec merely lacks is preserved rather than
        -- dropped. It stays OFF and it stays under its 1.x key, so nothing changes for
        -- anybody unless they ask for it. Listed in the wave report.
        { key = "firenova", name = "Fire Nova", tier = "announce", color = 1,
          default = false, text = "Fire Nova", icon = ICON .. "Spell_Fire_SealOfFire",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 23462, antispam = 3 } },
    },
    icons = {
        -- 8 -> 7 -> 6 and back to 8. Option ON by default (spec).
        { key = "adrenalineicons", name = "Burning Adrenaline raid icons", default = true,
          mode = "descend", from = 8, to = 6, wrap = true, clearOnEnd = true,
          on = { on = "SPELL_AURA_APPLIED", spellId = 18173 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §4.3 BROODLORD LASHLAYER
-- ══════════════════════════════════════════════════════════════════════════════
-- "No cooldown timers, no specials. Thin mod." — the spec's own words. The 1.x file
-- shipped a 17.8 s Blast Wave cooldown radial off Drew's logs; the spec says the
-- reference has no such bar, and the spec wins. Reported.
Addon:RegisterEncounter({
    id = "bwl:broodlord", name = "Broodlord Lashlayer", zone = 469,
    creatureId = { 12017 }, encounterId = { 612 },
    legacy = { raidId = "bwl", bossId = "broodlord" },
    detect = { mode = "combat_yellfind", yellFind = {
        "None of your kind should be here",
        "You've doomed only yourselves",
    } },
    timers = {
        { key = "mortalstrike", name = "Mortal Strike on <name>", kind = "target",
          spellId = 24573, color = 3, duration = 5, perTarget = true,
          icon = ICON .. "Ability_Warrior_SavageBlow",
          start = { on = "SPELL_AURA_APPLIED", spellId = 24573 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 24573 } },
    },
    warnings = {
        { key = "blastwave", name = "Blast Wave", tier = "announce", color = 2,
          text = "Blast Wave", icon = ICON .. "Spell_Holy_Excorcism_02",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 23331 } },
        { key = "knockaway", name = "Knock Away", tier = "announce", color = 3,
          role = "Melee", text = "Knock Away — threat drop",
          icon = ICON .. "INV_Gauntlets_05",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 18670 } },
        { key = "mortalstrikeon", name = "Mortal Strike on <name>", tier = "announce",
          color = 2, role = "Tank|Healer", noFilter = true, text = "Mortal Strike on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 24573 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §4.4 FIREMAW
-- ══════════════════════════════════════════════════════════════════════════════
-- Flame Buffet is announced from stack FOUR upward and only on EVEN stacks, which is
-- an equality question about the stack count, not a threshold — so it is a list of
-- exact values on `where`, not a `stacks` floor.
Addon:RegisterEncounter({
    id = "bwl:firemaw", name = "Firemaw", zone = 469,
    creatureId = { 11983 }, encounterId = { 613 },
    legacy = { raidId = "bwl", bossId = "firemaw" },
    detect = { mode = "combat" },
    timers = {
        { key = "wingbuffet", name = "Wing Buffet", kind = "cd", spellId = 23339, color = 2,
          icon = ICON .. "Spell_Nature_Cyclone",
          pull = "v30.6-40.4", duration = "v31.6-42.1",
          start = { on = "pull" },
          restart = { on = "SPELL_CAST_START", spellId = 23339 } },
        -- OFF by default (spec): the window is far too wide to be worth a bar unless
        -- the player asks for one.
        { key = "shadowflame", name = "Shadow Flame", kind = "cd", spellId = 22539,
          color = 2, default = false, icon = ICON .. "Spell_Fire_Incinerate",
          pull = "v11.3-24.3", duration = "v13-25.9",
          start = { on = "pull" },
          restart = { on = "SPELL_CAST_START", spellId = 22539 } },
    },
    warnings = {
        { key = "wingbuffetcast", name = "Wing Buffet", tier = "announce", color = 2,
          role = "Tank", text = "Wing Buffet — threat drop",
          suppressedBy = "wingbuffetspecial",
          trigger = { on = "SPELL_CAST_START", spellId = 23339 } },
        { key = "shadowflamecast", name = "Shadow Flame", tier = "announce", color = 2,
          role = "Tank|Healer", text = "Shadow Flame — cloak up",
          trigger = { on = "SPELL_CAST_START", spellId = 22539 } },
        { key = "flamebuffet", name = "Flame Buffet stacks", tier = "announce", color = 3,
          stacks = true, text = "Flame Buffet (%d)",
          icon = ICON .. "Spell_Fire_Fireball02",
          triggers = {
            { on = "SPELL_AURA_APPLIED_DOSE", spellId = 23341, dest = "player",
              where = { amount = { 4, 6, 8, 10, 12, 14, 16, 18, 20 } } },
            { on = "SPELL_AURA_APPLIED", spellId = 23341, dest = "player",
              where = { amount = { 4, 6, 8, 10, 12, 14, 16, 18, 20 } } },
          } },
        { key = "wingbuffetspecial", name = "Wing Buffet (special)", tier = "special",
          sound = 1, role = "Tank", text = "Wing Buffet",
          trigger = { on = "SPELL_CAST_START", spellId = 23339 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §4.5 EBONROC
-- ══════════════════════════════════════════════════════════════════════════════
-- The taunt call REPLACES the plain announce when it is enabled, and it respects the
-- global tank filter: it is a tank's call, so it carries both the role default and the
-- warning layer's tank filter.
Addon:RegisterEncounter({
    id = "bwl:ebonroc", name = "Ebonroc", zone = 469,
    creatureId = { 14601 }, encounterId = { 614 },
    legacy = { raidId = "bwl", bossId = "ebonroc" },
    detect = { mode = "combat" },
    timers = {
        { key = "wingbuffet", name = "Wing Buffet", kind = "cd", spellId = 23339, color = 2,
          icon = ICON .. "Spell_Nature_Cyclone",
          pull = "v30.2-35.6", duration = "v31.1-36",
          start = { on = "pull" },
          restart = { on = "SPELL_CAST_START", spellId = 23339 } },
        { key = "shadowflame", name = "Shadow Flame", kind = "cd", spellId = 22539,
          color = 2, default = false, icon = ICON .. "Spell_Fire_Incinerate",
          pull = "v11.3-21.1", duration = "v12.9-23.4",
          start = { on = "pull" },
          restart = { on = "SPELL_CAST_START", spellId = 22539 } },
        { key = "shadowofebonroc", name = "Shadow of Ebonroc on <name>", kind = "target",
          spellId = 23340, color = 3, duration = 8, perTarget = true,
          icon = ICON .. "Spell_Shadow_GatherShadows",
          start = { on = "SPELL_AURA_APPLIED", spellId = 23340 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 23340 } },
    },
    warnings = {
        { key = "wingbuffetcast", name = "Wing Buffet", tier = "announce", color = 2,
          role = "Tank", text = "Wing Buffet — threat drop",
          trigger = { on = "SPELL_CAST_START", spellId = 23339 } },
        { key = "shadowflamecast", name = "Shadow Flame", tier = "announce", color = 2,
          role = "Tank|Healer", text = "Shadow Flame — cloak up",
          trigger = { on = "SPELL_CAST_START", spellId = 22539 } },
        { key = "shadowon", name = "Shadow of Ebonroc on <name>", tier = "announce",
          color = 4, role = "Tank|Healer", noFilter = true, suppressedBy = "shadowtaunt",
          text = "Shadow of Ebonroc on %s — heals heal HIM",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 23340, dest = "other" } },
        { key = "shadowyou", name = "Shadow of Ebonroc on YOU", tier = "special",
          sound = 1, voice = "targetyou", role = "Tank",
          text = "Shadow of Ebonroc on YOU",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 23340, dest = "player" } },
        { key = "shadowtaunt", name = "Taunt — <name> has the Shadow", tier = "special",
          sound = 3, voice = "tauntboss", role = "Tank", filter = "tank",
          text = "Taunt — %s has the Shadow",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 23340, dest = "other" } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §4.6 FLAMEGOR
-- ══════════════════════════════════════════════════════════════════════════════
Addon:RegisterEncounter({
    id = "bwl:flamegor", name = "Flamegor", zone = 469,
    creatureId = { 11981 }, encounterId = { 615 },
    legacy = { raidId = "bwl", bossId = "flamegor" },
    detect = { mode = "combat" },
    timers = {
        { key = "wingbuffet", name = "Wing Buffet", kind = "cd", spellId = 23339, color = 2,
          icon = ICON .. "Spell_Nature_Cyclone",
          pull = "v30.3-35.4", duration = "v31.1-36.1",
          start = { on = "pull" },
          restart = { on = "SPELL_CAST_START", spellId = 23339 } },
        { key = "shadowflame", name = "Shadow Flame", kind = "cd", spellId = 22539,
          color = 2, default = false, icon = ICON .. "Spell_Fire_Incinerate",
          pull = "v11.2-21.1", duration = "v12.9-23",
          start = { on = "pull" },
          restart = { on = "SPELL_CAST_START", spellId = 22539 } },
        { key = "frenzy", name = "Frenzy", kind = "cd", spellId = 23342, color = 2,
          icon = ICON .. "Ability_Druid_Berserk", duration = "v8.3-11.3",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 23342 } },
        { key = "frenzyactive", name = "Frenzy (active)", kind = "active", spellId = 23342,
          color = 6, duration = 10, icon = ICON .. "Ability_Druid_Berserk",
          start = { on = "SPELL_AURA_APPLIED", spellId = 23342 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 23342 } },
    },
    warnings = {
        { key = "wingbuffetcast", name = "Wing Buffet", tier = "announce", color = 2,
          role = "Tank", text = "Wing Buffet — threat drop",
          trigger = { on = "SPELL_CAST_START", spellId = 23339 } },
        { key = "shadowflamecast", name = "Shadow Flame", tier = "announce", color = 2,
          role = "Tank|Healer", text = "Shadow Flame — cloak up",
          trigger = { on = "SPELL_CAST_START", spellId = 22539 } },
        { key = "frenzywarn", name = "Frenzy", tier = "announce", color = 3,
          role = "Tank|RemoveEnrage|Healer", text = "Frenzy — tranq",
          suppressedBy = "frenzydispel",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 23342 } },
        { key = "frenzydispel", name = "Dispel Frenzy", tier = "special", sound = 1,
          voice = "enrage", role = "RemoveEnrage", text = "Tranquilizing Shot NOW",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 23342 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §4.7 CHROMAGGUS — the crown of this wave
-- ══════════════════════════════════════════════════════════════════════════════
-- Detection is combat (CID) with a 20 s WIPE TIMEOUT, because ENCOUNTER_START fires
-- on the lever pull before the raid is actually in combat and a 5 s window would call
-- a wipe on the walk in.
--
-- THE EVIDENCE MODEL (spec's Era quirk, and the reason this fight is not a table of
-- spell ids). The vulnerability auras reach the combat log ONLY while somebody in the
-- raid is holding Detect Magic on him. So:
--    path 1  the combat-log aura            — exact school, only sometimes present
--    path 2  a sweep of HIS OWN buffs       — exact school, needs him resolvable
--    path 3  the shimmer emote (synced)     — proves a CHANGE, names no school
-- Paths 1 and 2 both feed the SAME restyle row, so whichever arrives first identifies
-- the school and the other is a no-op. Path 3 starts the bar with the school unknown.
-- Nothing here can ever CLEAR the school: an empty buff sweep is indistinguishable
-- from "we cannot see him", and the scanner refuses to route an absence at all.
Addon:RegisterEncounter({
    id = "bwl:chromaggus", name = "Chromaggus", zone = 469,
    creatureId = { 14020 }, encounterId = { 616 },
    legacy = { raidId = "bwl", bossId = "chromaggus" },
    detect = { mode = "combat" },
    combat = { wipeWindow = 20 },
    timers = {
        -- THE TWO PULL BREATH BARS. Separately labelled, and each MANUALLY STOPPED
        -- when its breath lands — a variance bar left alone counts into its window and
        -- sits there. `breath1` closes on the first breath of the fight; `breath2` is
        -- gated on the breath counter having already seen one, so the same cast cannot
        -- close both.
        { key = "breath1", name = "First Breath", kind = "cd", color = 4,
          icon = ICON .. "INV_Misc_Head_Dragon_01", duration = "v27-37.2",
          start = { on = "pull" },
          stop  = { on = "SPELL_CAST_START", spellId = BREATHS } },
        { key = "breath2", name = "Second Breath", kind = "cd", color = 4,
          icon = ICON .. "INV_Misc_Head_Dragon_01", duration = "v57.3-68.1",
          start = { on = "pull" },
          stop  = { on = "SPELL_CAST_START", spellId = BREATHS,
                    counter = { key = "breaths", min = 1 } } },
        -- ONE BAR PER BREATH SPELL (extension 20). He picks two of five per lockout and
        -- each recurs on its own 61.5 s clock, so a single shared bar would show only
        -- whichever breathed last.
        { key = "breathcd", name = "Breath", kind = "cd", color = 4, identBy = "spellId",
          icon = ICON .. "INV_Misc_Head_Dragon_01", duration = 61.5,
          start = { on = "SPELL_CAST_START", spellId = BREATHS } },
        { key = "breathcast", name = "Breath (cast)", kind = "cast", color = 4,
          icon = ICON .. "INV_Misc_Head_Dragon_01", duration = 2,
          start = { on = "SPELL_CAST_START", spellId = BREATHS } },
        { key = "frenzy", name = "Frenzy", kind = "cd", spellId = 23128, color = 2,
          icon = ICON .. "Ability_Druid_Berserk",
          pull = "v12.5-22.5", duration = "v16.1-17.8",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 23128 } },
        { key = "frenzyactive", name = "Frenzy (active)", kind = "active", spellId = 23128,
          color = 6, duration = 8, icon = ICON .. "Ability_Druid_Berserk",
          start = { on = "SPELL_AURA_APPLIED", spellId = 23128, dest = "other" },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 23128, dest = "other" } },
        -- THE VULNERABILITY BAR. Started by a school CHANGE (whichever evidence path
        -- proved it) or by the shimmer emote, which proves a change happened without
        -- saying to what. It is never started by the raw buff sweep, which re-reports
        -- the same school every second.
        { key = "vulnshift", name = "Vulnerability", kind = "cd", color = 7,
          icon = ICON .. "Spell_Nature_WispSplode", duration = "v16.2-25.9",
          starts = {
            { on = "state", fromKey = "vulnstyle" },
            { on = "emote", textFind = "flinches as its skin shimmers", sync = true },
          } },
    },
    -- W4b extension 19. One bar, five identities. The bar is recoloured, re-iconed and
    -- RENAMED without restarting — identity changes, elapsed time does not.
    --
    -- JUDGEMENT CALL (reported): our bar palette is seven semantic COLOUR CLASSES, not
    -- spell-school colours, so "recoloured to the school's colour" is honoured as "five
    -- schools get five visibly different classes". The school's real identity is in the
    -- icon and the name, which ARE exact.
    restyles = {
        { key = "vulnstyle", name = "Vulnerability bar follows the school",
          timer = "vulnshift", default = true, variants = {
            { on = "SPELL_AURA_APPLIED", spellId = VULN_FIRE,
              style = { text = "Fire Vulnerability",   color = 1, icon = ICON .. "Spell_Fire_Fire" } },
            { on = "aura", fromKey = "vulnscan", spellId = VULN_FIRE,
              style = { text = "Fire Vulnerability",   color = 1, icon = ICON .. "Spell_Fire_Fire" } },
            { on = "SPELL_AURA_APPLIED", spellId = VULN_NATURE,
              style = { text = "Nature Vulnerability", color = 2, icon = ICON .. "Spell_Nature_Lightning" } },
            { on = "aura", fromKey = "vulnscan", spellId = VULN_NATURE,
              style = { text = "Nature Vulnerability", color = 2, icon = ICON .. "Spell_Nature_Lightning" } },
            { on = "SPELL_AURA_APPLIED", spellId = VULN_FROST,
              style = { text = "Frost Vulnerability",  color = 3, icon = ICON .. "Spell_Frost_FrostBolt02" } },
            { on = "aura", fromKey = "vulnscan", spellId = VULN_FROST,
              style = { text = "Frost Vulnerability",  color = 3, icon = ICON .. "Spell_Frost_FrostBolt02" } },
            { on = "SPELL_AURA_APPLIED", spellId = VULN_SHADOW,
              style = { text = "Shadow Vulnerability", color = 5, icon = ICON .. "Spell_Shadow_ShadowBolt" } },
            { on = "aura", fromKey = "vulnscan", spellId = VULN_SHADOW,
              style = { text = "Shadow Vulnerability", color = 5, icon = ICON .. "Spell_Shadow_ShadowBolt" } },
            { on = "SPELL_AURA_APPLIED", spellId = VULN_ARCANE,
              style = { text = "Arcane Vulnerability", color = 7, icon = ICON .. "Spell_Nature_WispSplode" } },
            { on = "aura", fromKey = "vulnscan", spellId = VULN_ARCANE,
              style = { text = "Arcane Vulnerability", color = 7, icon = ICON .. "Spell_Nature_WispSplode" } },
          } },
        -- The recurring breath bar takes the breath's own name and icon. Five of the
        -- ten ids are named (see BREATHS above); the other five keep the generic label
        -- rather than being labelled with a guess.
        { key = "breathstyle", name = "Breath bars are named", timer = "breathcd",
          identBy = "spellId", default = true, variants = {
            { on = "SPELL_CAST_START", spellId = 23309,
              style = { text = "Incinerate",    icon = ICON .. "Spell_Fire_Incinerate" } },
            { on = "SPELL_CAST_START", spellId = 23310,
              style = { text = "Time Lapse",    icon = ICON .. "Spell_Nature_TimeStop" } },
            { on = "SPELL_CAST_START", spellId = 23313,
              style = { text = "Corrosive Acid", icon = ICON .. "Spell_Nature_Acid_01" } },
            { on = "SPELL_CAST_START", spellId = 23316,
              style = { text = "Ignite Flesh",  icon = ICON .. "Spell_Fire_SoulBurn" } },
            { on = "SPELL_CAST_START", spellId = 23187,
              style = { text = "Frost Burn",    icon = ICON .. "Spell_Frost_FrostShock" } },
          } },
    },
    scans = {
        -- EVIDENCE PATH 2 (extension 22). His own buffs, sampled once a second through
        -- the Era token ladder — which finds him through anybody's target, not only
        -- yours. Routes only what it FINDS; an empty sweep says nothing at all.
        { key = "vulnscan", type = "unit", creatureId = 14020, interval = 1,
          auras = VULN_ALL, on = { on = "pull" } },
    },
    counters = {
        -- How many breaths have landed, so the second pull bar can tell "the first one"
        -- from "the second one" without a bespoke flag.
        { key = "breaths", name = "Breaths cast", scope = "boss", step = 1,
          inc = { on = "SPELL_CAST_START", spellId = BREATHS } },
        -- MUTATION. The spec tracks the player's own brood-affliction count UP AND DOWN
        -- and warns at 3 of 5. `scope = "self"` is the whole point: this is a question
        -- about you, not about the raid.
        { key = "mutation", name = "Mutation (your brood afflictions)", scope = "self",
          step = 1, announce = "MUTATION %d/5", announceAt = { 3, 4, 5 },
          incs = {
            { on = "SPELL_AURA_APPLIED", spellId = BROOD_RED,    dest = "player" },
            { on = "SPELL_AURA_APPLIED", spellId = BROOD_GREEN,  dest = "player" },
            { on = "SPELL_AURA_APPLIED", spellId = BROOD_BLUE,   dest = "player" },
            { on = "SPELL_AURA_APPLIED", spellId = BROOD_BLACK,  dest = "player" },
            { on = "SPELL_AURA_APPLIED", spellId = BROOD_BRONZE, dest = "player" },
          },
          dec = { on = "SPELL_AURA_REMOVED",
                  spellId = { BROOD_RED, BROOD_GREEN, BROOD_BLUE, BROOD_BLACK, BROOD_BRONZE },
                  dest = "player" } },
    },
    warnings = {
        { key = "breathwarn", name = "Breath", tier = "announce", color = 2,
          text = "BREATH — get behind cover", icon = ICON .. "INV_Misc_Head_Dragon_01",
          trigger = { on = "SPELL_CAST_START", spellId = BREATHS } },
        -- SHIPS OFF (spec): Red is the one nobody dispels.
        { key = "broodred", name = "Brood Affliction: Red on <name>", tier = "announce",
          color = 2, default = false, text = "Brood Affliction: Red on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = BROOD_RED, antispam = 3 } },
        { key = "broodgreen", name = "Brood Affliction: Green on <name>", tier = "announce",
          color = 2, role = "RemovePoison", text = "Brood Affliction: Green on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = BROOD_GREEN } },
        { key = "broodblue", name = "Brood Affliction: Blue on <name>", tier = "announce",
          color = 2, role = "MagicDispeller", text = "Brood Affliction: Blue on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = BROOD_BLUE } },
        { key = "broodblack", name = "Brood Affliction: Black on <name>", tier = "announce",
          color = 2, role = "RemoveCurse", text = "Brood Affliction: Black on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = BROOD_BLACK } },
        { key = "frenzywarn", name = "Frenzy", tier = "announce", color = 3,
          role = "Tank|RemoveEnrage|Healer", text = "Frenzy — tranq",
          suppressedBy = "frenzydispel",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 23128, dest = "other" } },
        -- 1.x key `enrage` kept on the ENRAGE itself; the 20 % health rule it used is
        -- replaced by the spec's 25 % pre-warning below.
        { key = "enrage", name = "Enrage", tier = "announce", color = 4, text = "ENRAGE",
          icon = ICON .. "Spell_Shadow_UnholyFrenzy",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 23537, dest = "other" } },
        { key = "enragesoon", name = "Enrage soon (25%)", tier = "announce", color = 2,
          text = "Enrage soon", trigger = { on = "health", pct = 25, sync = true } },
        -- THE ANNOUNCE FIRES ONLY ON AN ACTUAL CHANGE. It is hung off the restyle row's
        -- state transition rather than off the aura, because the buff sweep re-reports
        -- the same school every single second and re-announcing it would be noise.
        { key = "vulnfire", name = "Fire Vulnerability", tier = "announce", color = 1,
          role = "CasterDps", text = "Fire Vulnerability",
          trigger = { on = "state", fromKey = "vulnstyle", where = { to = "Fire Vulnerability" } } },
        { key = "vulnnature", name = "Nature Vulnerability", tier = "announce", color = 1,
          role = "CasterDps", text = "Nature Vulnerability",
          trigger = { on = "state", fromKey = "vulnstyle", where = { to = "Nature Vulnerability" } } },
        { key = "vulnfrost", name = "Frost Vulnerability", tier = "announce", color = 1,
          role = "CasterDps", text = "Frost Vulnerability",
          trigger = { on = "state", fromKey = "vulnstyle", where = { to = "Frost Vulnerability" } } },
        { key = "vulnshadow", name = "Shadow Vulnerability", tier = "announce", color = 1,
          role = "CasterDps", text = "Shadow Vulnerability",
          trigger = { on = "state", fromKey = "vulnstyle", where = { to = "Shadow Vulnerability" } } },
        { key = "vulnarcane", name = "Arcane Vulnerability", tier = "announce", color = 1,
          role = "CasterDps", text = "Arcane Vulnerability",
          trigger = { on = "state", fromKey = "vulnstyle", where = { to = "Arcane Vulnerability" } } },
        { key = "broodbronze", name = "Brood Affliction: Bronze on YOU", tier = "special",
          sound = 1, voice = "useitem", text = "Bronze on YOU — use your trinket",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = BROOD_BRONZE, dest = "player" } },
        { key = "frenzydispel", name = "Dispel Frenzy", tier = "special", sound = 1,
          voice = "enrage", role = "RemoveEnrage", text = "Tranquilizing Shot NOW",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 23128, dest = "other" } },
        -- SCHEDULED, not derived: 27 s and 57 s from the pull, then 57 s after every
        -- regular breath (the 61.5 s cycle minus the lead).
        { key = "breathsoon", name = "Breath soon", tier = "special", sound = 3,
          voice = "breathsoon", text = "Breath soon", triggers = {
            { on = "pull", delay = 27 },
            { on = "pull", delay = 57 },
            { on = "SPELL_CAST_START", spellId = BREATHS, delay = 57 },
          } },
    },
    icons = {
        -- The school pinned to his nameplate, ON by default (spec). Driven by the same
        -- state transition the announces are, so it can never disagree with the bar.
        { key = "vulnnameplate", name = "Vulnerability nameplate icon", mode = "nameplate",
          default = true, on = { on = "state", fromKey = "vulnstyle" } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §4.8 NEFARIAN
-- ══════════════════════════════════════════════════════════════════════════════
-- THE PHASE MACHINE IS A POLL, and it is a poll because there is nothing else. The
-- spec is explicit: the phase 1 -> intermission -> phase 2 transition has no usable
-- combat-log event and no yell on Era, and the only witness is Blizzard's own
-- "an encounter is in progress" flag going false while the drakonid waves finish and
-- true again as he lands. W4b extension 21 samples it five times a second and routes
-- each CHANGE; the state machine below turns those changes into stages and then TEARS
-- THE POLLER DOWN, because a 0.2 s loop nobody reads is a tax on the rest of the fight.
--
-- The intermission arm requires `changed = true`: the very first sample is a change
-- from "unknown", and a pull that begins with the flag already false must not be read
-- as an intermission that already happened.
Addon:RegisterEncounter({
    id = "bwl:nefarian", name = "Nefarian", zone = 469,
    creatureId = { 11583 }, encounterId = { 617 },
    legacy = { raidId = "bwl", bossId = "nefarian" },
    detect = { mode = "combat_yellfind", yellFind = { "Let the games begin" } },
    combat = { wipeWindow = 50 },
    timers = {
        { key = "intermission", name = "Nefarian lands", kind = "intermission", color = 6,
          icon = ICON .. "INV_Misc_Head_Dragon_Black", duration = "v12.9-14.9",
          start = { on = "state", fromKey = "nefphase", where = { to = "intermission" } } },
        -- One 30 s bar for the call that is running, renamed and re-iconed to the class
        -- that was called (extension 19). Only one call is ever live at a time.
        { key = "classcall", name = "Class call", kind = "cd", color = 3, duration = 30,
          icon = ICON .. "Spell_Shadow_DeathScream",
          starts = {
            { on = "yell", textFind = "show me what your totems can do" },
            { on = "yell", textFind = "I've heard you have many lives" },
            { on = "yell", textFind = "silly shapeshifting" },
            { on = "yell", textFind = "keep healing like that" },
            { on = "yell", textFind = "I know you can hit harder" },
            { on = "yell", textFind = "Stop hiding and face me" },
            { on = "yell", textFind = "magic you don't understand" },
            { on = "yell", textFind = "Hunters and your annoying" },
            { on = "yell", textFind = "more careful when you play with magic" },
          } },
        -- 1.x key `bellowingroar` preserved: the fear bar is what a player toggled.
        { key = "bellowingroar", name = "Bellowing Roar (Fear)", kind = "cd", spellId = 22686,
          color = 2, icon = ICON .. "Spell_Shadow_DeathScream", duration = "v27-90.1",
          starts = { { on = "stage", stage = 2 } },
          restart = { on = "SPELL_CAST_START", spellId = 22686 } },
        { key = "shadowflame", name = "Shadow Flame", kind = "cd", spellId = 22539,
          color = 2, default = false, icon = ICON .. "Spell_Fire_Incinerate",
          duration = "v8.1-37.2",
          starts = { { on = "stage", stage = 2 } },
          restart = { on = "SPELL_CAST_START", spellId = 22539 } },
        { key = "shadowcommand", name = "Shadow Command on <name>", kind = "target",
          spellId = 22667, color = 3, duration = 15, perTarget = true,
          icon = ICON .. "Spell_Shadow_ShadowWordDominate",
          start = { on = "SPELL_AURA_APPLIED", spellId = 22667 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 22667 } },
    },
    restyles = {
        { key = "classcallstyle", name = "Class-call bar is named", timer = "classcall",
          default = true, variants = {
            { on = "yell", textFind = "show me what your totems can do",
              style = { text = "Shaman call",  icon = ICON .. "ClassIcon_Shaman" } },
            { on = "yell", textFind = "I've heard you have many lives",
              style = { text = "Paladin call", icon = ICON .. "ClassIcon_Paladin" } },
            { on = "yell", textFind = "silly shapeshifting",
              style = { text = "Druid call",   icon = ICON .. "ClassIcon_Druid" } },
            { on = "yell", textFind = "keep healing like that",
              style = { text = "Priest call",  icon = ICON .. "ClassIcon_Priest" } },
            { on = "yell", textFind = "I know you can hit harder",
              style = { text = "Warrior call", icon = ICON .. "ClassIcon_Warrior" } },
            { on = "yell", textFind = "Stop hiding and face me",
              style = { text = "Rogue call",   icon = ICON .. "ClassIcon_Rogue" } },
            { on = "yell", textFind = "magic you don't understand",
              style = { text = "Warlock call", icon = ICON .. "ClassIcon_Warlock" } },
            { on = "yell", textFind = "Hunters and your annoying",
              style = { text = "Hunter call",  icon = ICON .. "ClassIcon_Hunter" } },
            { on = "yell", textFind = "more careful when you play with magic",
              style = { text = "Mage call",    icon = ICON .. "ClassIcon_Mage" } },
          } },
    },
    scans = {
        { key = "phasepoll", type = "progress", interval = 0.2,
          on   = { on = "pull" },
          stop = { on = "state", fromKey = "nefphase", where = { to = "landed" } } },
    },
    states = {
        { key = "nefphase", initial = "waves", transitions = {
            { on = "progress", fromKey = "phasepoll",
              where = { inProgress = false, changed = true },
              states = { nefphase = "waves" }, to = "intermission" },
            { on = "progress", fromKey = "phasepoll", where = { inProgress = true },
              states = { nefphase = "intermission" }, to = "landed" },
          } },
    },
    phases = {
        { stage = 2, on = "state", fromKey = "nefphase", where = { to = "landed" } },
        { stage = 3, on = "yell", textFind = "Rise my minions" },
    },
    counters = {
        -- 42 drakonids, de-duplicated by GUID so a corpse that logs twice cannot
        -- double-count, announced only at the marks the spec lists.
        { key = "drakonids", name = "Drakonids remaining", scope = "census", from = 42,
          step = 1, announce = "%d drakonids left",
          announceAt = { 40, 35, 30, 25, 20, 15, 12, 9, 6, 3, 1 },
          dec = { on = "UNIT_DIED",
                  creatureId = { 14261, 14262, 14263, 14264, 14265, 14302 },
                  dedupe = "destGUID" } },
    },
    warnings = {
        { key = "phase1", name = "Phase 1", tier = "announce", color = 2, text = "Phase 1",
          trigger = { on = "pull" } },
        -- 1.x key `landing` preserved on the phase-2 announce.
        { key = "landing", name = "Phase 2 — Nefarian lands", tier = "announce", color = 2,
          voice = "ptwo", text = "Phase 2 — Nefarian lands",
          icon = ICON .. "INV_Misc_Head_Dragon_Black",
          trigger = { on = "stage", stage = 2 } },
        { key = "phase3", name = "Phase 3 — Bone Constructs", tier = "announce", color = 2,
          voice = "pthree", text = "Phase 3 — Bone Constructs",
          icon = ICON .. "Spell_Shadow_RaiseDead",
          trigger = { on = "stage", stage = 3 } },
        { key = "phase2soon", name = "Phase 2 soon", tier = "announce", color = 2,
          text = "Phase 2 soon — Nefarian is coming down",
          trigger = { on = "state", fromKey = "nefphase", where = { to = "intermission" } } },
        { key = "phase3soon", name = "Phase 3 soon (25%)", tier = "announce", color = 2,
          text = "Phase 3 soon",
          trigger = { on = "health", pct = 25, stage = 2, sync = true } },
        { key = "shadowflamecast", name = "Shadow Flame", tier = "announce", color = 2,
          role = "Tank|Healer", text = "Shadow Flame — cloak up",
          trigger = { on = "SPELL_CAST_START", spellId = 22539 } },
        { key = "fearcast", name = "Bellowing Roar (Fear)", tier = "announce", color = 2,
          text = "Bellowing Roar — Fear",
          trigger = { on = "SPELL_CAST_START", spellId = 22686 } },
        -- THE NINE CLASS CALLS THAT EXIST ON ERA. The spec lists eleven; Death Knight
        -- and Demon Hunter are marked "never fires on Era" and are not shipped, because
        -- a checkbox that can never do anything is worse than no checkbox.
        { key = "classcall_shaman", name = "Class call: Shaman", tier = "announce",
          color = 3, text = "Class call — SHAMANS", icon = ICON .. "ClassIcon_Shaman",
          trigger = { on = "yell", textFind = "show me what your totems can do" } },
        { key = "classcall_paladin", name = "Class call: Paladin", tier = "announce",
          color = 3, text = "Class call — PALADINS", icon = ICON .. "ClassIcon_Paladin",
          trigger = { on = "yell", textFind = "I've heard you have many lives" } },
        { key = "classcall_druid", name = "Class call: Druid", tier = "announce",
          color = 3, text = "Class call — DRUIDS", icon = ICON .. "ClassIcon_Druid",
          trigger = { on = "yell", textFind = "silly shapeshifting" } },
        { key = "classcall_priest", name = "Class call: Priest", tier = "announce",
          color = 3, text = "Class call — PRIESTS", icon = ICON .. "ClassIcon_Priest",
          trigger = { on = "yell", textFind = "keep healing like that" } },
        { key = "classcall_warrior", name = "Class call: Warrior", tier = "announce",
          color = 3, text = "Class call — WARRIORS", icon = ICON .. "ClassIcon_Warrior",
          trigger = { on = "yell", textFind = "I know you can hit harder" } },
        { key = "classcall_rogue", name = "Class call: Rogue", tier = "announce",
          color = 3, text = "Class call — ROGUES", icon = ICON .. "ClassIcon_Rogue",
          trigger = { on = "yell", textFind = "Stop hiding and face me" } },
        { key = "classcall_warlock", name = "Class call: Warlock", tier = "announce",
          color = 3, text = "Class call — WARLOCKS", icon = ICON .. "ClassIcon_Warlock",
          trigger = { on = "yell", textFind = "magic you don't understand" } },
        { key = "classcall_hunter", name = "Class call: Hunter", tier = "announce",
          color = 3, text = "Class call — HUNTERS", icon = ICON .. "ClassIcon_Hunter",
          trigger = { on = "yell", textFind = "Hunters and your annoying" } },
        { key = "classcall_mage", name = "Class call: Mage", tier = "announce",
          color = 3, text = "Class call — MAGES", icon = ICON .. "ClassIcon_Mage",
          trigger = { on = "yell", textFind = "more careful when you play with magic" } },
        -- THE PERSONAL ARM, once. `playerClassIs` (extension 27) carries the class on
        -- the TRIGGER, so nine yells share one row instead of needing nine more rows.
        { key = "classcallyou", name = "Class call on YOU", tier = "special", sound = 1,
          voice = "targetyou", text = "YOUR CLASS IS CALLED", triggers = {
            { on = "yell", textFind = "show me what your totems can do",
              condition = "playerClassIs", class = "SHAMAN" },
            { on = "yell", textFind = "I've heard you have many lives",
              condition = "playerClassIs", class = "PALADIN" },
            { on = "yell", textFind = "silly shapeshifting",
              condition = "playerClassIs", class = "DRUID" },
            { on = "yell", textFind = "keep healing like that",
              condition = "playerClassIs", class = "PRIEST" },
            { on = "yell", textFind = "I know you can hit harder",
              condition = "playerClassIs", class = "WARRIOR" },
            { on = "yell", textFind = "Stop hiding and face me",
              condition = "playerClassIs", class = "ROGUE" },
            { on = "yell", textFind = "magic you don't understand",
              condition = "playerClassIs", class = "WARLOCK" },
            { on = "yell", textFind = "Hunters and your annoying",
              condition = "playerClassIs", class = "HUNTER" },
            { on = "yell", textFind = "more careful when you play with magic",
              condition = "playerClassIs", class = "MAGE" },
          } },
        -- The Shaman call is the one call that is EVERYBODY'S problem: the totems have
        -- to die and no single class can do it. Raid-wide, unconditionally.
        { key = "shamantotems", name = "Kill the totems (Shaman call)", tier = "special",
          sound = 1, voice = "attacktotem", text = "KILL THE TOTEMS",
          trigger = { on = "yell", textFind = "show me what your totems can do" } },
        { key = "shadowcommandmc", name = "Mind control on <name>", tier = "special",
          sound = 1, voice = "findmc", text = "Mind control on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 22667 } },
        -- 1.x key `veilofshadow` preserved on the decurse call, which is what that row
        -- actually was.
        { key = "veilofshadow", name = "Dispel Veil of Shadow", tier = "special", sound = 1,
          voice = "dispelnow", role = "RemoveCurse", text = "Decurse Veil of Shadow",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 22687 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §4.9 BLACKWING LAIR TRASH (zone-wide, live DURING boss fights too)
-- ══════════════════════════════════════════════════════════════════════════════
-- The Death Talon drakonids carry the SAME five-school vulnerability system as
-- Chromaggus, with the same Detect Magic problem behind it — so the announce ships
-- OFF (it is a caster's optimisation, not a survival alert) and the nameplate icon
-- ships ON. Unlike Chromaggus there is no buff-sweep path here: a unit scan needs one
-- creature to hunt and a pull is four or five different drakonids at once, so the
-- combat-log aura is the only evidence and its absence is reported, not faked.
--
-- Demon Portal (22372) on the Blackwing warlocks is NOT implemented. The spec records
-- one observed interval (32.7 s) and marks it insufficient, and we do not ship a bar
-- we cannot stand behind.
Addon:RegisterEncounter({
    id = "bwl:trash", name = "Blackwing Lair trash", zone = 469,
    legacy = { raidId = "bwl", bossId = "trash" },
    detect = { mode = "zone" },
    timers = {
        -- One bar per Seether GUID; the spec's window is 8.1-10.9 and very often
        -- exactly 10.9 repeating.
        { key = "flamestrike", name = "Flamestrike", kind = "cd", spellId = 22275,
          color = 2, nameplate = true, duration = "v8.1-10.9",
          icon = ICON .. "Spell_Fire_SelfDestruct",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 22275 },
          stop  = { on = "UNIT_DIED", creatureId = 12468 } },
        { key = "broodpower", name = "Brood Power: Bronze on <name>", kind = "target",
          spellId = 22291, color = 3, duration = 5, perTarget = true,
          icon = ICON .. "Spell_Holy_SealOfWrath",
          start = { on = "SPELL_AURA_APPLIED", spellId = 22291 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 22291 } },
    },
    warnings = {
        { key = "flamestrikewarn", name = "Flamestrike", tier = "announce", color = 2,
          text = "Flamestrike",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 22275 } },
        -- No timer: the spec's observed window is 9.7-24.3, too wide to be a bar.
        { key = "rainoffire", name = "Rain of Fire", tier = "announce", color = 2,
          text = "Rain of Fire",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19717 } },
        { key = "trashenrage", name = "Enrage on <name>", tier = "announce", color = 3,
          role = "Tank|RemoveEnrage|Healer", noFilter = true, text = "Enrage on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 22428 } },
        { key = "broodpoweron", name = "Brood Power: Bronze on <name>", tier = "announce",
          color = 3, role = "Melee", noFilter = true, text = "Brood Power: Bronze on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 22291 } },
        -- SHIPS OFF (spec). One row, five ids: unlike Chromaggus there is no bar to
        -- rename here, so the school does not need five separate rows to be legible.
        { key = "trashvuln", name = "Drakonid vulnerability changed", tier = "announce",
          color = 1, role = "CasterDps", default = false, text = "Drakonid vulnerability",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = VULN_ALL,
                      antispam = 2, antispamBy = "destGUID" } },
        { key = "gtfo", name = "Move out of the fire", tier = "special", sound = 1,
          voice = "watchfeet", soundClass = 8, antispam = 2.5,
          text = "Move out of the fire", triggers = {
            { on = "SPELL_AURA_APPLIED",    spellId = 19717, dest = "player" },
            { on = "SPELL_DAMAGE",          spellId = 19717, dest = "player" },
            { on = "SPELL_PERIODIC_DAMAGE", spellId = 19717, dest = "player" },
            { on = "SPELL_AURA_APPLIED",    spellId = 22275, dest = "player" },
            { on = "SPELL_DAMAGE",          spellId = 22275, dest = "player" },
            { on = "SPELL_PERIODIC_DAMAGE", spellId = 22275, dest = "player" },
          } },
    },
    icons = {
        -- ON by default (spec). State is per MOB, which is what the widened anti-spam
        -- key is for, and it is cleared when that mob dies.
        { key = "trashvulnicon", name = "Drakonid vulnerability nameplate icon",
          mode = "nameplate", default = true,
          on = { on = "SPELL_AURA_APPLIED", spellId = VULN_ALL,
                 antispam = 1, antispamBy = "destGUID" } },
    },
})
