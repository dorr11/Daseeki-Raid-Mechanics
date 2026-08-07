--[[
    Daseeki Raid Mechanics 2.0 — THE VANILLA WORLD BOSSES, encounter data
    (wave 4a, final third — this file closes W4)

    SOURCE OF TRUTH: DBM_ERA_ENCOUNTERS_BEHAVIOR_SPEC.md §9 — Azuregos, Lord Kazzak
    and the four Dragons of Nightmare. Room-1 material only.

    NO PARKED 1.x DATA. The world bosses never had a data file (see
    enc_moltencore.lua's header for the full statement).

    ────────────────────────────────────────────────────────────────────────────────
    WHAT MAKES A WORLD BOSS DIFFERENT, AND WHY ALMOST NONE OF IT IS IN THIS FILE
    ────────────────────────────────────────────────────────────────────────────────
    The engine already implements every world-boss rule §9 and ENGINE SPEC §10.10
    describe, keyed off difficulty index 0:
        * wipe confirmation is 15 s rather than 5 s          (Life.WIPE_WINDOW_WORLDBOSS)
        * dying at a world boss is NOT a wipe                (ClassifyWipe row 3)
        * engaging below 98 % disqualifies the kill record   (WORLD_BOSS_RECORD_PCT)
        * engage/defeat broadcasts, de-duplicated on 30 s    (core_sync)
        * outdoors, a boss YELL triggers a delay-0 target sweep rather than engaging
          outright, so a yell heard across Azshara does not start your timers
                                                             (Life:OnChat + §2.1(d))
    So this file DECLARES rather than rebuilds. `combat.wipeWindow = 15` on all six is
    the one declaration worth making twice: it is a no-op while the client reports
    difficulty 0 (`WipeWindow` takes the larger of the two), and it is the safety net
    for the case where an outdoor client reports something else — which is exactly the
    case where a 5 s window would call a wipe on a raid that is still fighting.

    §9's own headline — "all six use outdoor engage syncing so everyone's timers start
    together on an open-world pull" — is likewise the engine's `C` sync (§7.3), which
    every engagement already broadcasts. There is nothing per-encounter to add.

    ────────────────────────────────────────────────────────────────────────────────
    THE HEURISTIC THIS SECTION IS WORTH REMEMBERING FOR
    ────────────────────────────────────────────────────────────────────────────────
    §9.1 records the author rejecting three measured windows on Azuregos — Frost
    Breath 10-40, Arcane Vacuum 16-35, Reflection 15.7-33 — on the rule:

        "if the maximum is more than double the minimum, a bar at the minimum is more
         misleading than helpful"

    and the spec adds "that heuristic is worth adopting wholesale". It is why Azuregos
    ships ZERO timers and why Kazzak's "5-40 s random" abilities have none either.
    Both are deliberate absences, not omissions, and both are asserted as absences in
    the harness so a future wave cannot quietly fill them in.
--]]

local _, Addon = ...

local ICON = "Interface\\Icons\\"

-- No mapID: these are outdoor encounters and the options tree groups them by name,
-- not by instance. Ordered last, after the seven raid zones.
Addon:RegisterZone({
    id = "world", name = "World Bosses", order = 80,
    size = 40, icon = ICON .. "INV_Misc_Head_Dragon_Green",
})

-- The engine derives 15 s from difficulty 0; this is the declaration that survives a
-- client that reports otherwise. One factory rather than one shared table, so six
-- registrations cannot end up sharing one mutable object.
local function worldBossCombat() return { wipeWindow = 15 } end

-- ══════════════════════════════════════════════════════════════════════════════
--  §9.1 AZUREGOS  (Azshara)
-- ══════════════════════════════════════════════════════════════════════════════
-- NO TIMERS, BY EXPLICIT DESIGN DECISION. See the header: three windows were measured
-- and all three were rejected. Everything here is reactive.
Addon:RegisterEncounter({
    id = "world:azuregos", name = "Azuregos",
    creatureId = { 6109 },
    legacy = { raidId = "world", bossId = "azuregos" },
    detect = { mode = "combat_yellfind", yellFind = {
        "This place is under my protection",
        "The mysteries of the arcane shall remain inviolate",
    } },
    combat = worldBossCombat(),
    warnings = {
        { key = "frostbreath", name = "Frost Breath", tier = "announce", color = 3,
          text = "Frost Breath", icon = ICON .. "Spell_Frost_FrostShock",
          trigger = { on = "SPELL_CAST_START", spellId = 21099, antispam = 3 } },
        { key = "arcanevacuum", name = "Arcane Vacuum — you will be teleported",
          tier = "special", sound = 2, voice = "teleyou",
          text = "TELEPORT — Arcane Vacuum",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 21147, antispam = 5 } },
        { key = "markoffrost", name = "Reflection — still dangerous", tier = "special",
          sound = 1, voice = "stilldanger", role = "CasterDps",
          text = "Reflection up — STILL DANGEROUS",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 22067 } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §9.2 LORD KAZZAK  (Blasted Lands)
-- ══════════════════════════════════════════════════════════════════════════════
-- THE ONE CONDITIONAL TIMER IN THE WHOLE DOCUMENT. The 180 s berserk starts only if
-- the pull was yell-detected or the fight is in an instance: a random outdoor aggro
-- pull can happen minutes before anybody notices, and a berserk bar seeded from that
-- moment is worse than none. That is ONE rule with an OR inside it, so it is one
-- named predicate (`pullTimeable`, core_api.lua) rather than two start paths — two
-- paths would both fire on a yell pull and restart the bar on top of itself.
--
-- DELIBERATE OMISSION (spec): NO RAID YELL on the Mark. Outdoor chat restrictions
-- make it unreliable and spammy, so the Mark rows carry the sync instead — Mark
-- targets are broadcast so raiders outside combat-log range still see who has it.
Addon:RegisterEncounter({
    id = "world:kazzak", name = "Lord Kazzak",
    creatureId = { 12397 },
    legacy = { raidId = "world", bossId = "kazzak" },
    detect = { mode = "combat_yellfind", yellFind = { "For the Legion! For Kil'Jaeden!" } },
    combat = worldBossCombat(),
    timers = {
        { key = "berserk", name = "Berserk", kind = "berserk", color = 4, duration = 180,
          icon = ICON .. "Spell_Shadow_UnholyFrenzy", countdown = { depth = 5 },
          start = { on = "pull", condition = "pullTimeable" } },
    },
    warnings = {
        { key = "shadowboltvolley", name = "Shadow Bolt Volley", tier = "announce", color = 2,
          text = "Shadow Bolt Volley", icon = ICON .. "Spell_Shadow_ShadowBolt",
          trigger = { on = "SPELL_CAST_SUCCESS", spellId = 21341 } },
        { key = "markon", name = "Mark of Kazzak on <name>", tier = "announce", color = 4,
          noFilter = true, text = "Mark of Kazzak on %s",
          icon = ICON .. "Spell_Shadow_AntiMagicShell",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 21056, antispam = 5,
                      sync = true } },
        -- No `yell` field here, and its absence is the spec's instruction.
        { key = "markyou", name = "Mark of Kazzak on YOU", tier = "special", sound = 1,
          voice = "targetyou", text = "MARK OF KAZZAK on YOU",
          trigger = { on = "SPELL_AURA_APPLIED", spellId = 21056, dest = "player" } },
    },
})

-- ══════════════════════════════════════════════════════════════════════════════
--  §9.3-9.6 THE DRAGONS OF NIGHTMARE
-- ══════════════════════════════════════════════════════════════════════════════
-- FOUR ENCOUNTERS, ONE MOD. The spec says so outright ("all four share a near-
-- identical mod"), and the only per-dragon facts are the creature id, the pull yell,
-- two Sleeping Fog numbers, and whether Lightning Wave exists (Ysondre only).
--
-- So the shared rows are written ONCE and stamped out by an ordinary Lua loop over a
-- four-row table. That is deliberately NOT a grammar extension: the grammar is a
-- description of one encounter, and four encounters that happen to be alike are a
-- fact about this file, not about the engine. A reader who wants to know what
-- Emeriss does reads DRAGONS below and the builder underneath it, and there is
-- exactly one place to fix a mistake.
--
-- THE FOG SPECIAL IS THROTTLED TO ONCE PER PULL (a 600 s anti-spam key), and that is
-- the spec's own design note: the fog is active more often than not, so a "dodge it"
-- call on every cast would be continuous noise. The COOLDOWN BAR keeps running
-- underneath it, which is where the recurring information lives.
--
-- NOXIOUS BREATH IS FILTERED TO THE DRAGON'S CURRENT TANK, not to a role — the stack
-- announce is only meaningful for whoever is actually eating it. That is the
-- `destIsBossTarget` predicate (core_api.lua, W4a), the mirror of the one Faerlina
-- already uses about the player.
--
-- ERA GAPS (§9.3-9.6 and §11): Bellowing Roar, Lethon's Shadow Bolt Whirl, Emeriss's
-- Volatile Infection and Taerar's shade split are all present in the reference as
-- DISABLED scaffolding because their Era spell ids were never confirmed. None of them
-- is shipped here — there is no id to ship. Noxious Breath's cooldown IS measured
-- (~18.3-19.4) and the spec records it as shipped-but-disabled, so it ships, OFF.
local DRAGONS = {
    { id = "ysondre", name = "Ysondre",  cid = 14887, order = 1,
      yell = "The strands of LIFE have been severed",
      fogPull = 18.4, fogCd = 16.0, lightningWave = true },
    { id = "lethon",  name = "Lethon",   cid = 14888, order = 2,
      yell = "I can sense the SHADOW on your hearts",
      fogPull = 18.4, fogCd = 16.8 },
    { id = "emeriss", name = "Emeriss",  cid = 14889, order = 3,
      yell = "Hope is a DISEASE of the soul",
      fogPull = 18.4, fogCd = 15.8 },
    { id = "taerar",  name = "Taerar",   cid = 14890, order = 4,
      yell = "Peace is but a fleeting dream",
      fogPull = 21.5, fogCd = 21.9 },
}

-- Sleeping Fog carries two ids on Era (24814 / 24813); both start the cast, both
-- restart the cooldown, and neither is trusted over the other.
local SLEEPING_FOG = { 24814, 24813 }

for _, d in ipairs(DRAGONS) do
    local timers = {
        { key = "sleepingfog", name = "Sleeping Fog", kind = "cd", spellId = SLEEPING_FOG[1],
          color = 2, icon = ICON .. "Spell_Nature_Sleep",
          pull = d.fogPull, duration = d.fogCd,
          start   = { on = "pull" },
          restart = { on = "SPELL_CAST_SUCCESS", spellId = SLEEPING_FOG } },
        -- SHIPS OFF (spec: measured, but recorded as "iffy" and shipped disabled).
        { key = "noxiousbreathcd", name = "Noxious Breath", kind = "cd", spellId = 24818,
          color = 2, default = false, icon = ICON .. "Spell_Nature_CorrosiveBreath",
          duration = "v18.3-19.4",
          start   = { on = "pull" },
          restart = { on = "SPELL_AURA_APPLIED", spellId = 24818 } },
    }
    local warnings = {
        -- "<name> (N)": the target fills `%s`, the debuff's own stack fills `%d`.
        { key = "noxiousbreath", name = "Noxious Breath on the tank", tier = "announce",
          color = 2, role = "Tank", stacks = true, text = "Noxious Breath %s (%d)",
          icon = ICON .. "Spell_Nature_CorrosiveBreath", triggers = {
            { on = "SPELL_AURA_APPLIED",      spellId = 24818,
              condition = "destIsBossTarget", creatureId = d.cid },
            { on = "SPELL_AURA_APPLIED_DOSE", spellId = 24818,
              condition = "destIsBossTarget", creatureId = d.cid },
          } },
        -- 600 s: once per pull, by construction.
        { key = "sleepingfogdodge", name = "Dodge the Sleeping Fog", tier = "special",
          sound = 2, voice = "watchstep", text = "SLEEPING FOG — move out",
          triggers = {
            { on = "SPELL_CAST_SUCCESS", spellId = SLEEPING_FOG, antispam = 600 },
          } },
    }
    if d.lightningWave then
        -- §9.3: Ysondre alone. The combat log does not carry it on Era, so the
        -- unit-cast channel is the witness (see core_lifecycle.lua, W4a defect fix B).
        timers[#timers + 1] =
            { key = "lightningwave", name = "Lightning Wave", kind = "cd", spellId = 24819,
              color = 2, icon = ICON .. "Spell_Nature_Lightning", duration = 13.4,
              start   = { on = "pull" },
              restart = { on = "unitCast", spellId = 24819 } }
        warnings[#warnings + 1] =
            { key = "lightningwavewarn", name = "Lightning Wave", tier = "announce", color = 3,
              text = "Lightning Wave", icon = ICON .. "Spell_Nature_Lightning",
              trigger = { on = "unitCast", spellId = 24819, antispam = 5 } }
    end

    Addon:RegisterEncounter({
        id = "world:" .. d.id, name = d.name,
        creatureId = { d.cid },
        legacy = { raidId = "world", bossId = d.id },
        detect = { mode = "combat_yellfind", yellFind = { d.yell } },
        combat = worldBossCombat(),
        timers = timers,
        warnings = warnings,
    })
end
