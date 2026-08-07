--[[
    Daseeki Raid Mechanics 2.0 — MOLTEN CORE (zone 409), encounter data
    (wave 4a, first third — the wave that closes W4)

    SOURCE OF TRUTH: DBM_ERA_ENCOUNTERS_BEHAVIOR_SPEC.md §2 — the ten Molten Core
    encounters plus the zone-wide trash module. Every timer value, warning tier,
    audience gate, ship-off default, phase rule, emote/yell trigger and scan in that
    section is a row below. Room-1 material only: written from the behavioural spec,
    never from third-party source.

    THERE IS NO PARKED 1.x DATA FOR THIS ZONE. data_naxxramas.lua, data_aq40.lua and
    data_bwl.lua were the only three 1.x data files that ever existed, and W4d/W4c/W4b
    consumed all three. Molten Core, Onyxia's Lair and the world bosses never had one,
    so unlike every earlier W4 wave there is NOTHING to diff, nothing to restore and
    no SavedVariables continuity to preserve: the spec is the sole source, and every
    row key below is new ground chosen for legibility.

    ────────────────────────────────────────────────────────────────────────────────
    WHY THIS ZONE IS MOSTLY THIN, AND WHY THAT IS THE POINT
    ────────────────────────────────────────────────────────────────────────────────
    §2 is the least mechanically ambitious section of the whole document and the spec
    says so out loud: Garr is "thin mod", Golemagg is "the thinnest raid-boss mod in
    the package — a single announce", Sulfuron has no pull timers at all. The
    temptation on a wave like this is to fill the gaps with plausible mechanics. We
    ship the spec's row set and nothing else; §11's "conspicuously absent" table is
    the record of what is missing and why, and inventing a Magma Splash stack tracker
    for Golemagg would put data in this file that no evidence stands behind.

    RAGNAROS is the one genuinely complex fight here (§2.10) and it is the reason for
    both of this wave's grammar extensions — see core_api.lua items 28 and 29, and the
    long comment over his registration below.
--]]

local _, Addon = ...

local ICON = "Interface\\Icons\\"

Addon:RegisterZone({
    id = "mc", name = "Molten Core", order = 10,
    mapID = 409, size = 40, icon = ICON .. "Spell_Fire_SelfDestruct",
})

-- §2 "Speed-clear stopwatch starts on the first Molten Giant engage and closes on
-- Ragnaros's death." NOT IMPLEMENTED, and not scaffolded: the engine has no per-raid
-- stopwatch surface and no personal-best store, so there is nothing for a declaration
-- to hang off. Reported as a W5 item; the same sentence appears verbatim for BWL,
-- AQ40 and Naxxramas, so it is one feature, not four.

-- ══════════════════════════════════════════════════════════════════════════════
--  §2.1 LUCIFRON
-- ══════════════════════════════════════════════════════════════════════════════
-- The mind-control victim is known TWICE: the Era client emits a cast-start for
-- Dominate Mind, so a boss-target scan names the victim ~0.2 s before the aura
-- lands, and the aura itself is the fallback. Both paths feed the SAME announce row,
-- which therefore carries a 1.5 s anti-spam key so the raid hears it once.
--
-- ERA QUIRK (spec): Impending Doom and its curse also carry alternate Season ids
-- 460931 / 460932 that NEVER fire on Era. They are not shipped — a trigger that can
-- never match is a maintenance liability, not a safety net.
Addon:RegisterEncounter({
    id = "mc:lucifron", name = "Lucifron", zone = 409,
    creatureId = { 12118 }, encounterId = { 663 },
    legacy = { raidId = "mc", bossId = "lucifron" },
    detect = { mode = "combat" },
    timers = {
        { key = "impendingdoom", name = "Impending Doom", kind = "cd", spellId = 19702,
          color = 2, icon = ICON .. "Spell_Shadow_AntiShadow",
          pull = "v5.7-11.8", duration = "v21-27",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19702 } },
        { key = "curseofdoom", name = "Curse of Impending Doom", kind = "cd", spellId = 19703,
          color = 3, icon = ICON .. "Spell_Shadow_AuraOfDarkness",
          pull = "v11.2-16.3", duration = "v21-25.9",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19703 } },
        -- SHIPS OFF (spec: "Off by default. Mind-control duration bar.")
        { key = "dominatemind", name = "Dominate Mind on <name>", kind = "target",
          spellId = 20604, color = 3, duration = 15, perTarget = true, default = false,
          icon = ICON .. "Spell_Shadow_ShadowWordDominate",
          start = { on = "SPELL_AURA_APPLIED", spellId = 20604 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 20604 } },
    },
    scans = {
        -- §1.6 boss target scanner: 0.2 s x 5 after the cast starts, with pet and
        -- non-raid results discarded.
        { key = "mindcontrolscan", name = "Dominate Mind target scan", type = "poll",
          interval = 0.2, tries = 5, filter = "playersOnly", creatureId = 12118,
          warning = "mindcontrol",
          on = { on = "SPELL_CAST_START", spellId = 20604 } },
    },
    warnings = {
        { key = "impendingdoomwarn", name = "Impending Doom", tier = "announce", color = 2,
          text = "Impending Doom", icon = ICON .. "Spell_Shadow_AntiShadow",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19702 } },
        { key = "curseofdoomwarn", name = "Curse of Impending Doom", tier = "announce",
          color = 3, role = "RemoveCurse|Healer", text = "Curse of Impending Doom",
          icon = ICON .. "Spell_Shadow_AuraOfDarkness",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19703 } },
        -- ONE ROW, TWO EVIDENCE PATHS. The scan (above) routes into this key; the aura
        -- is the fallback. The 1.5 s anti-spam is what de-duplicates them.
        { key = "mindcontrol", name = "Mind control on <name>", tier = "announce", color = 4,
          noFilter = true, combine = 0.3, text = "Mind control on %s",
          icon = ICON .. "Spell_Shadow_ShadowWordDominate",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 20604, antispam = 1.5 } },
        { key = "mindcontrolyou", name = "Mind control on YOU", tier = "special", sound = 1,
          voice = "targetyou", yell = "MIND CONTROL on me!",
          text = "MIND CONTROL on YOU",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 20604, dest = "player" } },
    },
    icons = {
        -- ON by default (spec). Cycles 1 -> 2 -> 3 -> 4 and clears on aura removal;
        -- on Era only icons 1 and 2 are ever reached, because Era Lucifron never has
        -- more than two victims at once.
        { key = "mindcontrolicons", name = "Mind-control raid icons", default = true,
          mode = "ascend", from = 1, to = 4, wrap = true, clearOn = "remove",
          on = { on = "SPELL_AURA_APPLIED", spellId = 20604 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §2.2 MAGMADAR
-- ══════════════════════════════════════════════════════════════════════════════
-- ERA QUIRK (spec): the Core Hound summons are NOT in the combat log at all. The
-- reference listens on the unit-cast channel, syncs it, and additionally snoops a
-- competing boss-mod addon's sync channel for the same event. WE SHIP NEITHER, and
-- deliberately:
--   * §2.2's warning table lists three rows — Panic, Frenzy and the dispel call. The
--     hound summon is described in the Era-quirk prose and has NO row and NO spell id
--     anywhere in the document, so there is nothing to declare.
--   * the spec is explicit that no hound timer is provided ("commented out as
--     unverified"), which is §11's position too.
-- Our dbm_bridge.lua is already a receive-only ingest of a foreign sync channel, so
-- the cross-addon half has a home the day an id turns up. Reported.
Addon:RegisterEncounter({
    id = "mc:magmadar", name = "Magmadar", zone = 409,
    creatureId = { 11982 }, encounterId = { 664 },
    legacy = { raidId = "mc", bossId = "magmadar" },
    detect = { mode = "combat" },
    timers = {
        { key = "panic", name = "Panic", kind = "cd", spellId = 19408, color = 2,
          icon = ICON .. "Spell_Shadow_DeathScream",
          pull = "v6.2-11.3", duration = "v37.3-66.4",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19408 } },
        { key = "frenzy", name = "Frenzy", kind = "cd", spellId = 19451, color = 2,
          icon = ICON .. "Ability_Druid_Berserk",
          pull = "v6.4-11.3", duration = "v16.1-21.1",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19451 } },
        { key = "frenzyactive", name = "Frenzy (active)", kind = "active", spellId = 19451,
          color = 6, duration = 8, icon = ICON .. "Ability_Druid_Berserk",
          start = { on = "SPELL_AURA_APPLIED", spellId = 19451, dest = "other" },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 19451, dest = "other" } },
    },
    warnings = {
        { key = "panicwarn", name = "Panic", tier = "announce", color = 2, text = "Panic",
          icon = ICON .. "Spell_Shadow_DeathScream",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19408 } },
        -- "The dispel special and the plain announce are mutually exclusive — enabling
        -- the dispel special replaces the announce." (W4b extension 26.)
        { key = "frenzywarn", name = "Frenzy", tier = "announce", color = 3,
          role = "Tank|RemoveEnrage|Healer", text = "Frenzy — tranq",
          suppressedBy = "frenzydispel", icon = ICON .. "Ability_Druid_Berserk",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 19451, dest = "other" } },
        { key = "frenzydispel", name = "Dispel Frenzy", tier = "special", sound = 1,
          voice = "enrage", role = "RemoveEnrage", text = "Tranquilizing Shot NOW",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 19451, dest = "other" } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §2.3 GEHENNAS
-- ══════════════════════════════════════════════════════════════════════════════
-- ERA QUIRK (spec): Rain of Fire's ground damage is matched by SPELL NAME AS WELL AS
-- SPELL ID, because the Era client's combat log is inconsistent about which id the
-- periodic damage carries. `spellName` on a trigger is an AND filter, not an OR, so
-- "name OR id" is two triggers on the same row — which is exactly what the GTFO row
-- below is: three id-matched arms and three name-matched arms.
--
-- The spec also notes the GTFO listener is high-frequency and is registered only on
-- pull. Our engine never subscribes per-row — every row hangs off one normalised
-- combat-log stream that is already only routed while something is engaged — so the
-- teardown half of that rule is structural here rather than declared.
Addon:RegisterEncounter({
    id = "mc:gehennas", name = "Gehennas", zone = 409,
    creatureId = { 12259 }, encounterId = { 665 },
    legacy = { raidId = "mc", bossId = "gehennas" },
    detect = { mode = "combat" },
    timers = {
        { key = "gehennascurse", name = "Gehennas' Curse", kind = "cd", spellId = 19716,
          color = 3, icon = ICON .. "Spell_Shadow_AntiShadow",
          pull = "v6.4-14.5", duration = "v25.9-35.6",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19716 } },
        -- A FIXED 4.8 s cadence, not a window: the spec gives one number.
        { key = "rainoffire", name = "Rain of Fire", kind = "cd", spellId = 19717, color = 2,
          icon = ICON .. "Spell_Fire_SelfDestruct", duration = 4.8,
          start = { on = "SPELL_CAST_SUCCESS", spellId = 19717 } },
    },
    warnings = {
        { key = "gehennascursewarn", name = "Gehennas' Curse", tier = "announce", color = 3,
          role = "RemoveCurse|Healer", text = "Gehennas' Curse",
          icon = ICON .. "Spell_Shadow_AntiShadow",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19716 } },
        -- SHIPS OFF (spec): it lands every five seconds.
        { key = "rainoffirewarn", name = "Rain of Fire", tier = "announce", color = 2,
          default = false, text = "Rain of Fire", icon = ICON .. "Spell_Fire_SelfDestruct",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19717 } },
        -- SHIPS OFF (spec).
        { key = "fistofragnaros", name = "Fist of Ragnaros on <name>", tier = "announce",
          color = 2, default = false, combine = 0.3, text = "Fist of Ragnaros on %s",
          icon = ICON .. "Spell_Fire_Fireball",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 20277 } },
        -- §1.6 GTFO block: aura-applied, direct damage and periodic damage, ~2.5 s
        -- throttle, sound tier 1, voice `watchfeet`. Six arms because the Era log
        -- cannot be trusted to use the same id twice (see the header).
        { key = "gtfo", name = "Move out of the fire", tier = "special", sound = 1,
          voice = "watchfeet", soundClass = 8, antispam = 2.5,
          text = "Move out of the fire", triggers = {
            { on = "SPELL_AURA_APPLIED",    spellId = 19717, dest = "player" },
            { on = "SPELL_DAMAGE",          spellId = 19717, dest = "player" },
            { on = "SPELL_PERIODIC_DAMAGE", spellId = 19717, dest = "player" },
            { on = "SPELL_AURA_APPLIED",    spellName = "Rain of Fire", dest = "player" },
            { on = "SPELL_DAMAGE",          spellName = "Rain of Fire", dest = "player" },
            { on = "SPELL_PERIODIC_DAMAGE", spellName = "Rain of Fire", dest = "player" },
          } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §2.4 GARR
-- ══════════════════════════════════════════════════════════════════════════════
-- "No specials, no phase logic. Thin mod." — the spec's own words, and the whole
-- encounter. The Firesworn adds exist only as the source of the Immolate announce.
Addon:RegisterEncounter({
    id = "mc:garr", name = "Garr", zone = 409,
    creatureId = { 12057 }, encounterId = { 666 },
    legacy = { raidId = "mc", bossId = "garr" },
    detect = { mode = "combat" },
    timers = {
        { key = "antimagicpulse", name = "Antimagic Pulse", kind = "cd", spellId = 19492,
          color = 2, icon = ICON .. "Spell_Nature_AbolishMagic",
          pull = "v11.2-16.2", duration = "v16.2-21.1",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19492 } },
        { key = "magmashackles", name = "Magma Shackles", kind = "cd", spellId = 19496,
          color = 2, icon = ICON .. "Spell_Fire_Immolation",
          pull = "v5.9-11.3", duration = "v11.3-16.2",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19496 } },
    },
    warnings = {
        { key = "antimagicpulsewarn", name = "Antimagic Pulse", tier = "announce", color = 2,
          text = "Antimagic Pulse", icon = ICON .. "Spell_Nature_AbolishMagic",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19492 } },
        { key = "magmashackleswarn", name = "Magma Shackles", tier = "announce", color = 2,
          text = "Magma Shackles", icon = ICON .. "Spell_Fire_Immolation",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19496 } },
        -- SHIPS OFF (spec): eight Firesworn each applying it is eight alerts.
        { key = "immolate", name = "Immolate on <name>", tier = "announce", color = 2,
          default = false, combine = 1.0, text = "Immolate on %s",
          icon = ICON .. "Spell_Fire_Immolation",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 15732 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §2.5 BARON GEDDON
-- ══════════════════════════════════════════════════════════════════════════════
-- ARMAGEDDON'S BAR OUTLIVES THE ENCOUNTER on purpose (`keep`): it is an 8 s cast that
-- resolves after the raid is already dead, and a bar that vanishes at combat end
-- would hide the one number anybody still cares about.
--
-- INFERNO'S GROUND DAMAGE is wired through the shared GTFO block on TWO ids — the
-- damage (19698) and the aura (364838) are different spells on Era — and the spec
-- says it is SUPPRESSED FOR TANKS. There is no `-Tank` role gate (§1.4's gate list
-- has `-Melee` and `-Healer` and nothing else), so "everyone except tanks" is written
-- as the positive union of the other two role classes. Same answer, expressible today.
--
-- KNOWN GAP, reported: §2.5 also says that if combat ends while you still carry the
-- bomb, the "bomb on you" warning and its yell FIRE AGAIN on combat end. The grammar
-- has no `on = "end"` trigger and the runtime is torn down at end, so there is
-- nowhere for that rule to live. It is a last-breath alert during a wipe; it is not
-- worth a third grammar extension in this wave.
Addon:RegisterEncounter({
    id = "mc:geddon", name = "Baron Geddon", zone = 409,
    creatureId = { 12056 }, encounterId = { 668 },
    legacy = { raidId = "mc", bossId = "geddon" },
    detect = { mode = "combat" },
    timers = {
        { key = "ignitemana", name = "Ignite Mana", kind = "cd", spellId = 19659, color = 2,
          icon = ICON .. "Spell_Fire_SealOfFire",
          pull = "v6.3-27.5", duration = "v25.9-44",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19659 } },
        { key = "inferno", name = "Inferno", kind = "cd", spellId = 19695, color = 2,
          icon = ICON .. "Spell_Fire_Fire",
          pull = "v11.3-33.4", duration = "v21-37.2",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19695 } },
        { key = "infernoactive", name = "Inferno (active)", kind = "active", spellId = 19695,
          color = 6, duration = 8, icon = ICON .. "Spell_Fire_Fire",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 19695 } },
        { key = "livingbomb", name = "Living Bomb", kind = "cd", spellId = 20475, color = 2,
          icon = ICON .. "Spell_Fire_SelfDestruct",
          pull = "v11.3-30.7", duration = "v11.3-30.1",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 20475 } },
        { key = "livingbombtarget", name = "Living Bomb on <name>", kind = "target",
          spellId = 20475, color = 4, duration = 8, perTarget = true,
          countdown = { depth = 5 }, icon = ICON .. "Spell_Fire_SelfDestruct",
          start = { on = "SPELL_AURA_APPLIED", spellId = 20475 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 20475 } },
        -- `keep` — the bar deliberately survives the encounter-end transition.
        { key = "armageddon", name = "Armageddon", kind = "cast", spellId = 20478, color = 4,
          duration = 8, keep = true, icon = ICON .. "Spell_Fire_Volcano",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 20478 } },
    },
    warnings = {
        { key = "ignitemanawarn", name = "Ignite Mana", tier = "announce", color = 3,
          role = "ManaUser", text = "Ignite Mana", icon = ICON .. "Spell_Fire_SealOfFire",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19659 } },
        { key = "infernowarn", name = "Inferno", tier = "announce", color = 3,
          text = "Inferno", icon = ICON .. "Spell_Fire_Fire",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19695 } },
        { key = "livingbombon", name = "Living Bomb on <name>", tier = "announce", color = 4,
          noFilter = true, combine = 0.1, text = "Living Bomb on %s",
          icon = ICON .. "Spell_Fire_SelfDestruct",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 20475 } },
        { key = "infernorunout", name = "Run out (Inferno)", tier = "special", sound = 4,
          voice = "aesoon", role = "Melee", text = "INFERNO — run out",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19695 } },
        { key = "ignitemanadispel", name = "Dispel Ignite Mana on <name>", tier = "special",
          sound = 1, voice = "helpdispel", role = "MagicDispeller", combine = 0.3,
          text = "Dispel Ignite Mana on %s",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 19659 } },
        { key = "livingbombyou", name = "Living Bomb on YOU", tier = "special", sound = 3,
          voice = "bombyou", yell = "LIVING BOMB on me!",
          text = "LIVING BOMB — run out",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 20475, dest = "player" } },
        { key = "armageddonwarn", name = "Armageddon", tier = "special",
          text = "ARMAGEDDON",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 20478 } },
        -- The shared ground-effect block. Two ids because the damage and the aura are
        -- different spells on Era; "everyone except tanks" per the header note.
        { key = "gtfo", name = "Move out of the Inferno", tier = "special", sound = 1,
          voice = "watchfeet", soundClass = 8, antispam = 2.5, role = "Dps|Healer",
          text = "Move out of the Inferno", triggers = {
            { on = "SPELL_AURA_APPLIED",    spellId = { 19698, 364838 }, dest = "player" },
            { on = "SPELL_DAMAGE",          spellId = { 19698, 364838 }, dest = "player" },
            { on = "SPELL_PERIODIC_DAMAGE", spellId = { 19698, 364838 }, dest = "player" },
          } },
    },
    icons = {
        -- SHIPS OFF (spec). Icon set {8,7,6}, and the index resets to 8 on every
        -- Living Bomb CAST SUCCESS — i.e. once per volley, not once per victim.
        { key = "livingbombicons", name = "Living Bomb raid icons", default = false,
          mode = "descend", from = 8, to = 6, wrap = true, clearOn = "remove",
          resetOn = { on = "SPELL_CAST_SUCCESS", spellId = 20475 },
          on = { on = "SPELL_AURA_APPLIED", spellId = 20475 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §2.6 SHAZZRAH
-- ══════════════════════════════════════════════════════════════════════════════
-- The Gate teleport (23138) wipes aggro, which is why a TAUNT call exists on a spell
-- that does no damage: the bar is not the point, the reaction is.
Addon:RegisterEncounter({
    id = "mc:shazzrah", name = "Shazzrah", zone = 409,
    creatureId = { 12264 }, encounterId = { 667 },
    legacy = { raidId = "mc", bossId = "shazzrah" },
    detect = { mode = "combat" },
    timers = {
        { key = "shazzrahcurse", name = "Shazzrah's Curse", kind = "cd", spellId = 19713,
          color = 3, icon = ICON .. "Spell_Shadow_AntiShadow",
          pull = "v6.1-13", duration = "v21-26.4",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19713 } },
        { key = "counterspell", name = "Counterspell", kind = "cd", spellId = 19715, color = 4,
          icon = ICON .. "Spell_Frost_IceShock",
          pull = "v8.1-14.5", duration = "v15.7-21.1",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19715 } },
        { key = "deadenmagic", name = "Deaden Magic (active)", kind = "active", spellId = 19714,
          color = 6, duration = 30, icon = ICON .. "Spell_Nature_AbolishMagic",
          start = { on = "SPELL_AURA_APPLIED", spellId = 19714, dest = "other" },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 19714, dest = "other" } },
        { key = "gate", name = "Gate of Shazzrah", kind = "cd", spellId = 23138, color = 2,
          icon = ICON .. "Spell_Arcane_Blink",
          pull = "v30.3-34.1", duration = "v42.1-48.6",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 23138 } },
    },
    warnings = {
        { key = "shazzrahcursewarn", name = "Shazzrah's Curse", tier = "announce", color = 3,
          role = "RemoveCurse|Healer", text = "Shazzrah's Curse",
          icon = ICON .. "Spell_Shadow_AntiShadow",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19713 } },
        { key = "deadenmagicwarn", name = "Deaden Magic on boss", tier = "announce", color = 2,
          role = "CasterDps", noFilter = true, suppressedBy = "deadenmagicdispel",
          text = "Deaden Magic on Shazzrah", icon = ICON .. "Spell_Nature_AbolishMagic",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 19714, dest = "other" } },
        { key = "counterspellwarn", name = "Counterspell", tier = "announce", color = 3,
          role = "SpellCaster", text = "Counterspell", icon = ICON .. "Spell_Frost_IceShock",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19715 } },
        { key = "deadenmagicdispel", name = "Dispel Deaden Magic", tier = "special", sound = 1,
          voice = "dispelboss", role = "MagicDispeller", text = "Dispel Deaden Magic",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 19714, dest = "other" } },
        { key = "gatetaunt", name = "Taunt — Shazzrah blinked", tier = "special", sound = 1,
          voice = "tauntboss", role = "Tank", filter = "tank", text = "Blink — TAUNT",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 23138 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §2.7 SULFURON HARBINGER
-- ══════════════════════════════════════════════════════════════════════════════
-- NO PULL TIMERS — every alert here is reactive, and three of the four target
-- announces ship OFF because the spec records the authors judging the adds' debuff
-- spam too noisy. That is a preference, so the rows exist and are switched off.
--
-- The Heal cast bar is PER CASTER GUID and attached to that caster's nameplate: four
-- Flamewaker Priests are four bars, and each ends when its own cast is interrupted.
Addon:RegisterEncounter({
    id = "mc:sulfuron", name = "Sulfuron Harbinger", zone = 409,
    creatureId = { 12098 }, encounterId = { 669 },
    legacy = { raidId = "mc", bossId = "sulfuron" },
    detect = { mode = "combat" },
    timers = {
        -- The spec says the bar is "cancelled on interrupt". Era's SPELL_INTERRUPT
        -- names the INTERRUPTER'S spell in the id slot and the interrupted spell only
        -- in the extra-spell slot the normaliser does not carry, and its source GUID
        -- is the interrupter — so an interrupt arm would attach to the wrong bar. The
        -- completed cast closes the bar instead; a kicked bar therefore lingers for at
        -- most the 2 s it had left. Reported.
        { key = "healcast", name = "Heal (cast)", kind = "cast", spellId = 19775, color = 4,
          duration = 2, nameplate = true, icon = ICON .. "Spell_Holy_Heal",
          start = { on = "SPELL_CAST_START", spellId = 19775 },
          stop  = { on = "SPELL_CAST_SUCCESS", spellId = 19775 } },
        { key = "inspire", name = "Inspire on <name>", kind = "target", spellId = 19779,
          color = 3, duration = 10, perTarget = true, icon = ICON .. "Spell_Holy_PrayerOfHealing",
          start = { on = "SPELL_AURA_APPLIED", spellId = 19779 },
          stop  = { on = "SPELL_AURA_REMOVED", spellId = 19779 } },
    },
    warnings = {
        -- SHIPS OFF (spec).
        { key = "shadowwordpain", name = "Shadow Word: Pain on <name>", tier = "announce",
          color = 2, default = false, combine = 0.3, text = "Shadow Word: Pain on %s",
          icon = ICON .. "Spell_Shadow_ShadowWordPain",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 19776 } },
        { key = "inspireon", name = "Inspire on <name>", tier = "announce", color = 2,
          role = "Tank|Healer", noFilter = true, text = "Inspire on %s",
          icon = ICON .. "Spell_Holy_PrayerOfHealing",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 19779 } },
        -- SHIPS OFF (spec).
        { key = "handofragnaros", name = "Hand of Ragnaros on <name>", tier = "announce",
          color = 2, default = false, combine = 0.3, text = "Hand of Ragnaros on %s",
          icon = ICON .. "Spell_Fire_Fireball",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 19780 } },
        -- SHIPS OFF (spec).
        { key = "immolate", name = "Immolate on <name>", tier = "announce", color = 2,
          default = false, combine = 0.3, text = "Immolate on %s",
          icon = ICON .. "Spell_Fire_Immolation",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 20294 } },
        -- "filtered to casts you can actually reach": the interrupt gate answers WHO,
        -- and the Era range ladder answers WHETHER. 33 is the ladder's nearest rung to
        -- a caster interrupt's 30 yd, and the predicate fails OPEN (an unresolvable
        -- unit does not swallow the alert).
        { key = "healinterrupt", name = "Interrupt Heal on <caster>", tier = "special",
          sound = 1, voice = "kickcast", role = "HasInterrupt",
          text = "INTERRUPT the Heal",
          trigger = { on = "SPELL_CAST_START", spellId = 19775,
                      condition = "playerNearSource", range = 33 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §2.8 GOLEMAGG THE INCINERATOR
-- ══════════════════════════════════════════════════════════════════════════════
-- ONE ANNOUNCE. That is the entire mod, and the spec calls it "the thinnest raid-boss
-- mod in the package". §11 lists what is missing (Magma Splash stacks, Core Rager
-- timers, phase awareness) and none of it has values anywhere in the document, so
-- none of it is invented here. This registration is short because the fight's
-- coverage is short, not because it was rushed.
Addon:RegisterEncounter({
    id = "mc:golemagg", name = "Golemagg the Incinerator", zone = 409,
    creatureId = { 11988 }, encounterId = { 670 },
    legacy = { raidId = "mc", bossId = "golemagg" },
    detect = { mode = "combat" },
    warnings = {
        { key = "earthquake", name = "Earthquake", tier = "announce", color = 2,
          role = "Melee", text = "Earthquake", icon = ICON .. "Spell_Nature_EarthQuake",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19798 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §2.9 MAJORDOMO EXECUTUS
-- ══════════════════════════════════════════════════════════════════════════════
-- THE ADDS ARE THE ENCOUNTER. Three creature ids — Majordomo (12018), the Flamewaker
-- Healers (11663) and the Flamewaker Elites (11664) — are one fight, and the fight is
-- won by killing the eight adds while Majordomo himself is untouchable. So:
--   * all three ids start combat, which is what makes an add pull engage the mod;
--   * `severalCreatureIdsOneBoss` REFUSES to end the fight on any death, because the
--     adds die constantly and Majordomo never dies at all (he submits). Blizzard's
--     ENCOUNTER_END is the kill path here and it is the correct one.
--
-- THE "NEXT SHIELD" BAR is one timer for two mutually-exclusive abilities, which the
-- spec flags as a design note worth carrying forward: the raid only needs to know
-- that *a* shield is coming, and two half-informative bars are worse than one.
--
-- JUDGEMENT CALL, reported: §2.9 says the Damage Shield special "downgrades itself to
-- a plain announce when the encounter is trivial for the group". The engine has no
-- trivial-content notion (Era has no level scaling and no trivial flag in §10), so
-- both rows ship and `suppressedBy` makes them mutually exclusive by preference
-- instead of by group level. Magic Reflection has no such downgrade in the spec
-- either way, because it is always lethal to casters.
Addon:RegisterEncounter({
    id = "mc:majordomo", name = "Majordomo Executus", zone = 409,
    creatureId = { 12018, 11663, 11664 }, encounterId = { 671 },
    legacy = { raidId = "mc", bossId = "majordomo" },
    detect = { mode = "combat" },
    combat = { severalCreatureIdsOneBoss = true },
    timers = {
        { key = "teleport", name = "Teleport", kind = "cd", spellId = 20534, color = 2,
          icon = ICON .. "Spell_Arcane_Blink",
          pull = "v15.8-21.1", duration = "v25.9-30.8",
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 20534 } },
        { key = "magicreflection", name = "Magic Reflection (active)", kind = "active",
          spellId = 20619, color = 6, duration = 10, icon = ICON .. "Spell_Nature_WispSplode",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 20619 } },
        { key = "damageshield", name = "Damage Shield (active)", kind = "active",
          spellId = 21075, color = 6, duration = 10, icon = ICON .. "Spell_Holy_PowerWordShield",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 21075 } },
        -- ONE BAR, TWO ABILITIES. Either cast restarts it.
        { key = "nextshield", name = "Next shield", kind = "cd", color = 3,
          icon = ICON .. "Spell_Holy_PowerWordShield",
          pull = "v25.6-30.7", duration = 30.7,
          start    = { on = "pull" },
          restarts = { { on = "SPELL_CAST_SUCCESS", spellId = 20619 },
                       { on = "SPELL_CAST_SUCCESS", spellId = 21075 } } },
    },
    warnings = {
        { key = "teleporton", name = "Teleport on <name>", tier = "announce", color = 2,
          noFilter = true, text = "Teleport on %s", icon = ICON .. "Spell_Arcane_Blink",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 20534 } },
        { key = "damageshieldwarn", name = "Damage Shield", tier = "announce", color = 2,
          role = "Melee", text = "Damage Shield", suppressedBy = "damageshieldstop",
          icon = ICON .. "Spell_Holy_PowerWordShield",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 21075 } },
        { key = "magicreflectionstop", name = "Stop casting (Magic Reflection)",
          tier = "special", sound = 1, voice = "stopattack", role = "-Melee",
          text = "MAGIC REFLECTION — stop casting",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 20619 } },
        { key = "damageshieldstop", name = "Stop attacking (Damage Shield)", tier = "special",
          sound = 1, voice = "stopattack", role = "Melee",
          text = "DAMAGE SHIELD — stop attacking",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 21075 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §2.10 RAGNAROS — the crown of this zone, and the reason for two extensions
-- ══════════════════════════════════════════════════════════════════════════════
-- THE SUBMERGE CYCLE IS A STATE MACHINE, NOT A PAIR OF PHASE ROWS, and the reason is
-- exact: `SetStage` is not idempotent. The emerge has TWO ways in — a 90 s schedule
-- and "the eighth Son of Flame just died" — and whichever loses the race must be a
-- no-op. A state machine gives that for free (`SetState` refuses a transition to the
-- state it is already in, so the loser's `actions` never run), where two phase rows
-- would both fire, both bump the stage register, and both re-seed the Wrath bar.
-- The stage register still moves, driven from the machine's `actions`, so every
-- ordinary row below can be written against stages 1 and 2 exactly as the spec
-- describes them (stage 1 = emerged, stage 2 = submerged).
--
-- SUBMERGE IS DETECTED TWICE AND SYNCED (spec): the boss yell, and the submerge
-- visual 20567 on the unit-cast channel. Both arms land on the same transition, so
-- whichever arrives first wins and the other is a no-op.
--
-- EMERGE IS A SCHEDULE, NOT AN EVENT (spec's Era quirk): there is no emerge event in
-- the Era combat log at all. The 90 s deferred transition is that schedule.
--
-- THE SONS COUNTER IS SILENT ON PURPOSE. §2.10 describes the counter as the mechanism
-- behind the early emerge and lists no announce for it, so it counts and says
-- nothing. It is de-duplicated by GUID (a corpse that logs twice cannot double-count)
-- and reset on every submerge, so the second cycle starts at eight again.
--
-- ─── GRAMMAR EXTENSION 28 (core_api.lua): `on = "counter"` FINALLY FIRES ──────────
-- "A counter threshold" has been in the published trigger vocabulary since wave 1 and
-- nothing ever ROUTED one, exactly as `stage` and `state` were dead until W4d
-- extension 6. Ragnaros's "the scheduled emerge is cancelled and emerge fires
-- immediately when the counter hits 0" is the case that needed it. The alternative
-- was a `counter = { key = "sons", eq = 1 }` filter on the eighth death — which works
-- only because counter rows happen to be indexed before state rows, i.e. it would
-- have been correct by accident.
--
-- ─── GRAMMAR EXTENSION 29 (core_api.lua): PULL COUNTDOWN FROM A DEATH ─────────────
-- §2.10's combat-start row is "83 s initial estimate, corrected to 73 s remaining
-- when Majordomo dies", sourced from "the Summon-Ragnaros cast or the pull yell".
-- The spec gives NO id for that cast and NO text for that yell, so the 83 s arm has
-- no expressible trigger and is not shipped. The CORRECTION does have a trigger, it
-- is the more accurate of the two, and it needed one new pull-countdown source:
-- a creature death. W4b extension 25 already established that "an event that precedes
-- the pull by a known interval starts the engine's own pull timer"; this only widens
-- the admissible events from chat-only to chat-or-death.
Addon:RegisterEncounter({
    id = "mc:ragnaros", name = "Ragnaros", zone = 409,
    creatureId = { 11502 }, encounterId = { 672 },
    legacy = { raidId = "mc", bossId = "ragnaros" },
    detect = { mode = "combat",
               -- 73 s of RP between Majordomo's death and Ragnaros being attackable.
               pullCountdown = { seconds = 73, creatureDeath = 12018 } },
    timers = {
        -- The post-emerge window is genuinely different from the ordinary one, so the
        -- emerge path carries its own duration (W4d extension 3).
        { key = "wrath", name = "Wrath of Ragnaros", kind = "cd", spellId = 20566, color = 3,
          icon = ICON .. "Spell_Fire_SelfDestruct",
          pull = "v25.9-33.8", duration = "v25.9-34.7",
          starts   = { { on = "pull" },
                       { on = "stage", stage = 1, duration = "v25.5-31.9" } },
          restart  = { on = "SPELL_CAST_SUCCESS", spellId = 20566 },
          stop     = { on = "stage", stage = 2 } },
        -- 180 s from the pull, and 180 s after each emerge.
        { key = "submerge", name = "Submerge", kind = "stage", color = 6, duration = 180,
          icon = ICON .. "Spell_Fire_MoltenBlood",
          starts = { { on = "pull" }, { on = "stage", stage = 1 } },
          stop   = { on = "stage", stage = 2 } },
        -- 90 s, closed early the instant the eighth Son dies.
        { key = "emerge", name = "Emerge", kind = "stage", color = 6, duration = 90,
          icon = ICON .. "Spell_Fire_LavaSpawn",
          start = { on = "stage", stage = 2 },
          stops = { { on = "stage", stage = 1 },
                    { on = "counter", fromKey = "sons", where = { value = 0 } } } },
    },
    counters = {
        -- Eight Sons of Flame, counted DOWN by GUID and reset on every submerge.
        { key = "sons", name = "Sons of Flame remaining", scope = "census", from = 8, step = 1,
          dec   = { on = "UNIT_DIED", creatureId = 12143, dedupe = "destGUID" },
          reset = { on = "stage", stage = 2 } },
    },
    states = {
        { key = "ragphase", initial = "emerged", transitions = {
            -- Both submerge witnesses, on the same transition.
            { on = "yell", textFind = "COME FORTH, MY SERVANTS", sync = true,
              to = "submerged", actions = { { stage = 2 } } },
            { on = "unitCast", spellId = 20567, sync = true,
              to = "submerged", actions = { { stage = 2 } } },
            -- The 90 s schedule. Deferred, and unmade by the row's own cancel below
            -- when the Sons die first; even if it survived, SetState would refuse it.
            { on = "state", fromKey = "ragphase", where = { to = "submerged" }, delay = 90,
              to = "emerged", actions = { { stage = 1 } } },
            -- …and the race's other runner.
            { on = "counter", fromKey = "sons", where = { value = 0 },
              to = "emerged", actions = { { stage = 1 } } },
          },
          cancel = { on = "counter", fromKey = "sons", where = { value = 0 } } },
    },
    warnings = {
        { key = "wrathwarn", name = "Wrath of Ragnaros", tier = "announce", color = 3,
          text = "Wrath of Ragnaros", icon = ICON .. "Spell_Fire_SelfDestruct",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 20566 } },
        { key = "submergewarn", name = "Submerge", tier = "announce", color = 2,
          text = "Ragnaros submerges — Sons of Flame", icon = ICON .. "Spell_Fire_MoltenBlood",
          trigger = { on = "stage", stage = 2 } },
        { key = "emergewarn", name = "Emerge", tier = "announce", color = 2,
          text = "Ragnaros emerges", icon = ICON .. "Spell_Fire_LavaSpawn",
          trigger = { on = "stage", stage = 1 } },
    },
})
-- ERA QUIRK, recorded and deliberately not modelled: Ragnaros's model preview is
-- disabled on Classic clients because it renders wrong. We ship no model previews at
-- all, so there is nothing to disable.

-- ══════════════════════════════════════════════════════════════════════════════
--  §2.11 MOLTEN CORE TRASH (zone-wide)
-- ══════════════════════════════════════════════════════════════════════════════
-- ELEVEN PER-MOB-GUID NAMEPLATE COOLDOWNS, each stopping when THAT mob dies, plus two
-- mob-agnostic dispel announces. Every announce carries the spec's 3 s anti-spam key
-- so a pack of six identical Firewalkers produces one warning.
--
-- THE ENGAGE VALUES, AND THE JUDGEMENT CALL BEHIND THEM (reported). §2.11 gives each
-- ability an ENGAGE time as well as a recurring window, and the engine has no "this
-- mob just engaged" event — nothing in Era's combat log announces it. The nearest
-- honest witness is the mob's FIRST SWING, which is what these rows start on, deduped
-- per source GUID so it happens at most once per mob. Two consequences, both
-- deliberate:
--   * a mob you merely walk past never starts a bar (which a nameplate-added trigger
--     would have done, and which would have been worse than no bar);
--   * the occurrence counter is per ROW rather than per mob, so on a pack pulled one
--     at a time only the first mob's bar uses the engage window. For a pack pulled
--     together — which is how Molten Core trash is pulled — the first is the right
--     one, and every subsequent bar comes off an observed cast anyway.
--
-- Knockdown's recurring value is written "7.2+" in the spec — a floor with no
-- measured ceiling — so it ships as a flat 7.2 rather than as an invented window.
Addon:RegisterEncounter({
    id = "mc:trash", name = "Molten Core trash", zone = 409,
    legacy = { raidId = "mc", bossId = "trash" },
    detect = { mode = "zone" },
    timers = {
        -- Molten Giant (11658)
        { key = "smash", name = "Smash", kind = "cd", spellId = 18944, color = 2,
          nameplate = true, icon = ICON .. "Ability_Warrior_DecisiveStrike",
          pull = 3.3, duration = "v7.2-9.9",
          start   = { on = "SWING_DAMAGE", creatureId = 11658, dedupe = "sourceGUID" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 18944 },
          stop    = { on = "UNIT_DIED", creatureId = 11658 } },
        { key = "knockaway", name = "Knock Away", kind = "cd", spellId = 18945, color = 2,
          nameplate = true, icon = ICON .. "INV_Gauntlets_05",
          pull = "v5.3-10.5", duration = "v10.7-14.8",
          start   = { on = "SWING_DAMAGE", creatureId = 11658, dedupe = "sourceGUID" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 18945 },
          stop    = { on = "UNIT_DIED", creatureId = 11658 } },
        -- Molten Destroyer (11659)
        { key = "knockdown", name = "Knockdown", kind = "cd", spellId = 20276, color = 2,
          nameplate = true, icon = ICON .. "Ability_Warrior_Charge",
          pull = 3.9, duration = 7.2,
          start   = { on = "SWING_DAMAGE", creatureId = 11659, dedupe = "sourceGUID" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 20276 },
          stop    = { on = "UNIT_DIED", creatureId = 11659 } },
        { key = "massivetremor", name = "Massive Tremor", kind = "cd", spellId = 19129,
          color = 2, nameplate = true, icon = ICON .. "Spell_Nature_EarthQuake",
          pull = 6.9, duration = "v13.3-17",
          start   = { on = "SWING_DAMAGE", creatureId = 11659, dedupe = "sourceGUID" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19129 },
          stop    = { on = "UNIT_DIED", creatureId = 11659 } },
        -- Firelord (11668)
        { key = "lavaspawn", name = "Summon Lava Spawn", kind = "adds", spellId = 19392,
          color = 1, nameplate = true, icon = ICON .. "Spell_Fire_LavaSpawn",
          pull = "v10-14", duration = "v16.8-19.5",
          start   = { on = "SWING_DAMAGE", creatureId = 11668, dedupe = "sourceGUID" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19392 },
          stop    = { on = "UNIT_DIED", creatureId = 11668 } },
        -- Lava Surger (12101). The spec gives NO engage value ("near-instant on ranged
        -- pulls"), so this bar starts only on an observed Surge.
        { key = "surge", name = "Surge", kind = "cd", spellId = 19196, color = 2,
          nameplate = true, icon = ICON .. "Ability_Warrior_Charge",
          duration = "v7.1-14.5",
          start = { on = "SPELL_CAST_SUCCESS", spellId = 19196 },
          stop  = { on = "UNIT_DIED", creatureId = 12101 } },
        -- Ancient Core Hound (11673)
        { key = "lavabreath", name = "Lava Breath", kind = "cd", spellId = 19272, color = 2,
          nameplate = true, icon = ICON .. "Spell_Fire_Incinerate",
          pull = "v3.8-24.3", duration = "v10.9-19.4",
          start   = { on = "SWING_DAMAGE", creatureId = 11673, dedupe = "sourceGUID" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19272 },
          stop    = { on = "UNIT_DIED", creatureId = 11673 } },
        -- Lava Elemental (12076)
        { key = "pyroclast", name = "Pyroclast Barrage", kind = "cd", spellId = 19641,
          color = 2, nameplate = true, icon = ICON .. "Spell_Fire_FlameBolt",
          pull = "v6.5-13.5", duration = "v8.3-20.7",
          start   = { on = "SWING_DAMAGE", creatureId = 12076, dedupe = "sourceGUID" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19641 },
          stop    = { on = "UNIT_DIED", creatureId = 12076 } },
        -- Firewalker (11666)
        { key = "inciteflames", name = "Incite Flames", kind = "cd", spellId = 19635,
          color = 2, nameplate = true, icon = ICON .. "Spell_Fire_Fire",
          pull = "v5-12.4", duration = "v12.1-18.2",
          start   = { on = "SWING_DAMAGE", creatureId = 11666, dedupe = "sourceGUID" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19635 },
          stop    = { on = "UNIT_DIED", creatureId = 11666 } },
        { key = "fireblossom", name = "Fire Blossom", kind = "cd", spellId = 19636, color = 2,
          nameplate = true, icon = ICON .. "Spell_Fire_FlameBolt",
          pull = "v6.4-17.4", duration = "v11.1-19.6",
          start   = { on = "SWING_DAMAGE", creatureId = 11666, dedupe = "sourceGUID" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19636 },
          stop    = { on = "UNIT_DIED", creatureId = 11666 } },
        -- Flameguard (11667)
        { key = "coneoffire", name = "Cone of Fire", kind = "cd", spellId = 19630, color = 2,
          nameplate = true, icon = ICON .. "Spell_Fire_SoulBurn",
          pull = "v7-13", duration = "v13.5-15.9",
          start   = { on = "SWING_DAMAGE", creatureId = 11667, dedupe = "sourceGUID" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = 19630 },
          stop    = { on = "UNIT_DIED", creatureId = 11667 } },
    },
    warnings = {
        -- SHIPS OFF (spec).
        { key = "smashwarn", name = "Smash", tier = "announce", color = 2, default = false,
          text = "Smash", icon = ICON .. "Ability_Warrior_DecisiveStrike",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 18944, antispam = 3 } },
        { key = "knockawaywarn", name = "Knock Away", tier = "announce", color = 2,
          role = "Tank", text = "Knock Away", icon = ICON .. "INV_Gauntlets_05",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 18945, antispam = 3 } },
        { key = "knockdownwarn", name = "Knockdown", tier = "announce", color = 2,
          role = "Tank", text = "Knockdown", icon = ICON .. "Ability_Warrior_Charge",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 20276, antispam = 3 } },
        -- SHIPS OFF (spec).
        { key = "massivetremorwarn", name = "Massive Tremor", tier = "announce", color = 3,
          default = false, text = "Massive Tremor", icon = ICON .. "Spell_Nature_EarthQuake",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19129, antispam = 3 } },
        { key = "lavaspawnwarn", name = "Summon Lava Spawn", tier = "announce", color = 3,
          text = "Lava Spawn incoming", icon = ICON .. "Spell_Fire_LavaSpawn",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19392, antispam = 3 } },
        { key = "surgewarn", name = "Surge", tier = "announce", color = 2,
          role = "Tank|Healer", text = "Surge", icon = ICON .. "Ability_Warrior_Charge",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19196, antispam = 3 } },
        -- SHIPS OFF (spec).
        { key = "lavabreathwarn", name = "Lava Breath", tier = "announce", color = 2,
          default = false, text = "Lava Breath", icon = ICON .. "Spell_Fire_Incinerate",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19272, antispam = 3 } },
        { key = "pyroclastwarn", name = "Pyroclast Barrage", tier = "announce", color = 2,
          text = "Pyroclast Barrage", icon = ICON .. "Spell_Fire_FlameBolt",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19641, antispam = 3 } },
        { key = "inciteflameswarn", name = "Incite Flames", tier = "announce", color = 2,
          role = "MagicDispeller", text = "Incite Flames", icon = ICON .. "Spell_Fire_Fire",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19635, antispam = 3 } },
        { key = "fireblossomwarn", name = "Fire Blossom", tier = "announce", color = 2,
          text = "Fire Blossom", icon = ICON .. "Spell_Fire_FlameBolt",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19636, antispam = 3 } },
        { key = "coneoffirewarn", name = "Cone of Fire", tier = "announce", color = 3,
          role = "Healer", text = "Cone of Fire", icon = ICON .. "Spell_Fire_SoulBurn",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 19630, antispam = 3 } },
        -- The two mob-agnostic rows: §2.11 lists neither a caster nor a cooldown for
        -- these, only the dispel audience.
        { key = "ancientdread", name = "Ancient Dread", tier = "announce", color = 3,
          role = "MagicDispeller", text = "Ancient Dread",
          icon = ICON .. "Spell_Shadow_Possession",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 19365, antispam = 3 } },
        { key = "soulburn", name = "Soul Burn on <name>", tier = "announce", color = 3,
          role = "MagicDispeller", noFilter = true, text = "Soul Burn on %s",
          icon = ICON .. "Spell_Fire_SoulBurn",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 19393, antispam = 3 } },
    },
})
