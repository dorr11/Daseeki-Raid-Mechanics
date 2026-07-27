--[[
    Daseeki Raid Mechanics — Blackwing Lair (40-man, vanilla / Classic Era) encounter data.

    Format: identical to data_naxxramas.lua — see its header for the full mechanic shape
    and how defaults merge with DB overrides (core.lua GetMechanicConfig).

    Provenance tags used below:
      -- log-verified 2026-07-26: ...   measured from ~17 MB of captured server combat logs
      -- DBM <val>                      DBM's own timer bars logged verbatim (ground truth for CDs)
      -- DBM-source (unverified live)   lifted from installed DBM-Raids-Vanilla files, not yet seen live

    NOTE: values are Anniversary-realm measurements where tagged; confirm the rest
    in-game via /drm debug.
--]]

local _, Addon = ...

local RED    = { 0.90, 0.20, 0.20 }
local ORANGE = { 0.95, 0.55, 0.15 }
local PURPLE = { 0.65, 0.35, 0.90 }
local GREEN  = { 0.30, 0.80, 0.35 }
local BLUE   = { 0.30, 0.55, 0.95 }
local YELLOW = { 0.95, 0.85, 0.25 }

Addon:RegisterRaid({
    id    = "bwl",
    name  = "Blackwing Lair",
    order = 30,
    mapID = 469,
    size  = 40,
    icon  = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    bosses = {
        -- ── Razorgore the Untamed ─────────────────────────────────────────────
        { id = "razorgore", name = "Razorgore the Untamed", npcIDs = { 12435 }, mechanics = {
            -- Egg-phase add waves. DBM-source starts a single 47s "Adds spawning" bar at pull;
            -- measured DBM bars showed the 47.0 cadence recurring through the egg phase, so this
            -- free-runs on that interval. Limitation: timer triggers can't stop at Phase 2, so the
            -- bar keeps cycling after the eggs are done — toggle off in P2 or ignore. -- DBM 47.0
            { id = "adds", name = "Adds Incoming", icon = "Interface\\Icons\\Ability_Warrior_Charge",
              trigger = { type = "timer", delay = 47, interval = 47 }, barColor = RED,
              warning = true, warningText = "Adds incoming!", sound = "raidwarning" },
            -- Orb-controller egg counter, Loatheb-Spore style: quiet on-cast text with the live
            -- count substituted for %d (FormatCountText in alerts.lua). 30 eggs total.
            -- log-verified 2026-07-26: 60 casts of 19873, intervals 10.1-18.2 (too variable for
            -- a cooldown radial — alert mode with a count instead).
            { id = "destroyegg", name = "Destroy Egg", icon = "Interface\\Icons\\INV_Egg_05",
              trigger = { type = "cast", spellID = 19873, npcID = 12435 }, barColor = YELLOW,
              showCount = true, castText = "Egg %d", onCastDefault = true, sound = "none",
              default = true },
            -- Disorient on the tank/nearby players; logs only as SPELL_AURA_APPLIED on players
            -- (DBM-source keys the same event). log-verified 2026-07-26: intervals ~16.1s.
            { id = "conflagration", name = "Conflagration", icon = "Interface\\Icons\\Spell_Fire_Incinerate",
              trigger = { type = "aura", spellID = 23023 }, barColor = ORANGE,
              warning = true, warningText = "Conflagration!", sound = "raidwarning" },
            -- Phase 2 ranged AoE nuke (cast alert; DBM-source keys SPELL_CAST_START + LOS warning).
            { id = "fireballvolley", name = "Fireball Volley", icon = "Interface\\Icons\\Spell_Fire_FlameBolt",
              trigger = { type = "cast", spellID = 22425, npcID = 12435 }, barColor = ORANGE,
              warning = true, warningText = "Fireball Volley — break line of sight!", sound = "raidwarning" },
            { id = "warstomp", name = "War Stomp", icon = "Interface\\Icons\\Ability_WarStomp",
              trigger = { type = "cast", spellID = 24375, npcID = 12435 }, barColor = ORANGE, default = false },
            { id = "cleave", name = "Cleave", icon = "Interface\\Icons\\Ability_Warrior_Cleave",
              trigger = { type = "cast", spellID = 19632, npcID = 12435 }, barColor = ORANGE, default = false },
        }},

        -- ── Vaelastrasz the Corrupt ───────────────────────────────────────────
        -- GAP: DBM shows a 43.5s "Combat starts" countdown off the pre-combat RP yell
        -- ("Too late, friends!"). Our engine starts mechanics on Engage, so that RP
        -- countdown is intentionally omitted rather than modeled wrong. -- DBM 43.5
        { id = "vaelastrasz", name = "Vaelastrasz the Corrupt", npcIDs = { 13020 }, mechanics = {
            -- Cooldown radial to the NEXT Burning Adrenaline pick (DBM starts the CD at pull
            -- and restarts on each cast). -- DBM v16.1-17.8 (low bound)
            { id = "adrenalinecd", name = "Burning Adrenaline CD", icon = "Interface\\Icons\\Spell_Fire_Immolation",
              trigger = { type = "cast", spellID = 18173, npcID = 13020 }, barColor = RED,
              mode = "cooldown", style = "icon", cooldown = 16.1, firstCast = 16 },
            -- PERSONAL: you have 20 seconds to live — burn mana, get out of the raid.
            -- -- DBM 20.0 target bar
            { id = "adrenaline", name = "Burning Adrenaline (on you)", icon = "Interface\\Icons\\Spell_Fire_Immolation",
              trigger = { type = "aura", spellID = 18173, onPlayer = true }, barColor = RED,
              style = "flash", barDuration = 20, default = true,
              warningText = "BURNING ADRENALINE — burn your mana, move out before death!", sound = "raidwarning",
              special = true },  -- personal death timer: 20s to live — act-now tier
            -- Informational: the infinite-resource buff Vael grants the raid at pull. Not in
            -- DBM-source at all; spellID 23513 from classic DB — unverified live. Quiet, off
            -- by default (it's a pull-time constant, not a decision point).
            { id = "essence", name = "Essence of the Red", icon = "Interface\\Icons\\Spell_Nature_BloodLust",
              trigger = { type = "aura", spellID = 23513, onPlayer = true }, barColor = YELLOW,
              sound = "none", default = false },
            -- Frontal cone on the tank, near-constant. log-verified 2026-07-26: intervals 6.0-8.1.
            { id = "flamebreath", name = "Flame Breath", icon = "Interface\\Icons\\Spell_Fire_Fire",
              trigger = { type = "cast", spellID = 23461, npcID = 13020 }, barColor = ORANGE, default = false },
            -- Constant PBAoE pulse — pure spam. log-verified 2026-07-26: intervals 3.2-4.9.
            { id = "firenova", name = "Fire Nova", icon = "Interface\\Icons\\Spell_Fire_SealOfFire",
              trigger = { type = "cast", spellID = 23462, npcID = 13020 }, barColor = ORANGE, default = false },
            -- Not in DBM-source; spellIDs from classic DB — unverified live. Minor melee noise.
            { id = "cleave", name = "Cleave", icon = "Interface\\Icons\\Ability_Warrior_Cleave",
              trigger = { type = "cast", spellID = 19983, npcID = 13020 }, barColor = ORANGE, default = false },
            { id = "tailsweep", name = "Tail Sweep", icon = "Interface\\Icons\\Ability_Whirlwind",
              trigger = { type = "cast", spellID = 15847, npcID = 13020 }, barColor = ORANGE, default = false },
        }},

        -- ── Broodlord Lashlayer ───────────────────────────────────────────────
        { id = "broodlord", name = "Broodlord Lashlayer", npcIDs = { 12017 }, mechanics = {
            -- Tank debuff (-50% healing). DBM-source has NO recast timer for this, only a 5s
            -- target-debuff bar; measured intervals 11.3-29.1 are too variable for a cooldown
            -- radial, so this alerts on the aura landing. -- DBM-source 5.0 target bar
            { id = "mortalstrike", name = "Mortal Strike", icon = "Interface\\Icons\\Ability_Warrior_SavageBlow",
              trigger = { type = "aura", spellID = 24573 }, barColor = ORANGE, barDuration = 5,
              warning = true, warningText = "Mortal Strike on tank — healing cut!", sound = "raidwarning" },
            -- log-verified 2026-07-26: intervals ~17.8s. Quiet melee-info radial.
            { id = "blastwave", name = "Blast Wave", icon = "Interface\\Icons\\Spell_Holy_Excorcism_02",
              trigger = { type = "cast", spellID = 23331, npcID = 12017 }, barColor = ORANGE,
              mode = "cooldown", style = "icon", cooldown = 17.8 },
            -- Threat drop + knockback. log-verified 2026-07-26: intervals 17.8-25.8.
            { id = "knockaway", name = "Knock Away", icon = "Interface\\Icons\\INV_Gauntlets_05",
              trigger = { type = "cast", spellID = 18670, npcID = 12017 }, barColor = ORANGE,
              warning = true, warningText = "Knock Away — threat drop!", sound = "raidwarning" },
            { id = "cleave", name = "Cleave", icon = "Interface\\Icons\\Ability_Warrior_Cleave",
              trigger = { type = "cast", spellID = 15754, npcID = 12017 }, barColor = ORANGE, default = false },
        }},

        -- ── Firemaw ───────────────────────────────────────────────────────────
        { id = "firemaw", name = "Firemaw", npcIDs = { 11983 }, mechanics = {
            -- The stacking fire debuff you drop by breaking line of sight. Applies to everyone
            -- in LOS every 1.3-8.1s (log-verified 2026-07-26) and our trigger shape has no
            -- stack-count support (DBM warns per-stack via SPELL_AURA_APPLIED_DOSE), so a
            -- personal-aura alert would fire near-constantly. Quiet + off by default.
            { id = "flamebuffet", name = "Flame Buffet", icon = "Interface\\Icons\\Spell_Fire_Fireball02",
              trigger = { type = "aura", spellID = 23341, onPlayer = true }, barColor = ORANGE,
              sound = "none", default = false },
            -- Onyxia Scale Cloak check. -- DBM v11.3-13.0 (low bound)
            { id = "shadowflame", name = "Shadow Flame", icon = "Interface\\Icons\\Spell_Fire_Incinerate",
              trigger = { type = "cast", spellID = 22539, npcID = 11983 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 11.3, winWarning = true,
              warningText = "Shadow Flame — cloak up!", sound = "raidwarning" },
            -- Knockback + ~50% threat wipe on those hit. -- DBM v30.6-31.6 (low bound)
            { id = "wingbuffet", name = "Wing Buffet", icon = "Interface\\Icons\\Spell_Nature_Cyclone",
              trigger = { type = "cast", spellID = 23339, npcID = 11983 }, barColor = ORANGE,
              mode = "cooldown", style = "icon", cooldown = 30.6, winWarning = true, winSound = true,
              warningText = "Wing Buffet — threat drop!", sound = "raidwarning" },
            -- Thrash 3391 (generic drake melee) intentionally omitted.
        }},

        -- ── Ebonroc ───────────────────────────────────────────────────────────
        { id = "ebonroc", name = "Ebonroc", npcIDs = { 14601 }, mechanics = {
            -- Tank debuff: Ebonroc HEALS off the target — swap/taunt. log-verified 2026-07-26:
            -- intervals 8.1-13.0. -- DBM 8.0 target bar
            { id = "shadowofebonroc", name = "Shadow of Ebonroc", icon = "Interface\\Icons\\Spell_Shadow_GatherShadows",
              trigger = { type = "aura", spellID = 23340 }, barColor = PURPLE, barDuration = 8,
              warning = true, warningText = "Shadow of Ebonroc on tank — heals heal HIM!", sound = "raidwarning" },
            -- Onyxia Scale Cloak check. -- DBM v11.3-12.9 (low bound)
            { id = "shadowflame", name = "Shadow Flame", icon = "Interface\\Icons\\Spell_Fire_Incinerate",
              trigger = { type = "cast", spellID = 22539, npcID = 14601 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 11.3, winWarning = true,
              warningText = "Shadow Flame — cloak up!", sound = "raidwarning" },
            -- -- DBM v30.2-31.1 (low bound)
            { id = "wingbuffet", name = "Wing Buffet", icon = "Interface\\Icons\\Spell_Nature_Cyclone",
              trigger = { type = "cast", spellID = 23339, npcID = 14601 }, barColor = ORANGE,
              mode = "cooldown", style = "icon", cooldown = 30.2, winWarning = true, winSound = true,
              warningText = "Wing Buffet — threat drop!", sound = "raidwarning" },
        }},

        -- ── Flamegor ──────────────────────────────────────────────────────────
        { id = "flamegor", name = "Flamegor", npcIDs = { 11981 }, mechanics = {
            -- Tranq-shot rotation target. -- DBM CD v8.3 (low bound); "Frenzy ends" 10.0
            { id = "frenzy", name = "Frenzy", icon = "Interface\\Icons\\Ability_Druid_Berserk",
              trigger = { type = "cast", spellID = 23342, npcID = 11981 }, barColor = RED,
              mode = "cooldown", style = "icon", cooldown = 8.3,
              warningText = "Frenzy — tranq!", sound = "raidwarning" },
            -- Onyxia Scale Cloak check. -- DBM v11.2-12.9 (low bound)
            { id = "shadowflame", name = "Shadow Flame", icon = "Interface\\Icons\\Spell_Fire_Incinerate",
              trigger = { type = "cast", spellID = 22539, npcID = 11981 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 11.2, winWarning = true,
              warningText = "Shadow Flame — cloak up!", sound = "raidwarning" },
            -- -- DBM v30.3-31.1 (low bound)
            { id = "wingbuffet", name = "Wing Buffet", icon = "Interface\\Icons\\Spell_Nature_Cyclone",
              trigger = { type = "cast", spellID = 23339, npcID = 11981 }, barColor = ORANGE,
              mode = "cooldown", style = "icon", cooldown = 30.3, winWarning = true, winSound = true,
              warningText = "Wing Buffet — threat drop!", sound = "raidwarning" },
        }},

        -- ── Chromaggus ────────────────────────────────────────────────────────
        -- The two breaths are RANDOM per lockout out of 5 possible spells (Incinerate 23309,
        -- Corrosive Acid 23313, Frost Burn 23187, Ignite Flesh 23316, Time Lapse 23310), so
        -- both slots key the same spell set and can't be told apart by trigger — modeled as
        -- two free-running timer slots instead. DBM-source slot starts: Breath 1 v27-37.2,
        -- Breath 2 v57.3-68.1 (low bounds used); each recasts on a 61.5 cycle
        -- (log-verified 2026-07-26: Incinerate 23309 / Ignite Flesh 23316 intervals 61.5).
        { id = "chromaggus", name = "Chromaggus", npcIDs = { 14020 }, mechanics = {
            { id = "breath1", name = "Breath 1", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
              trigger = { type = "timer", delay = 27, interval = 61.5 }, barColor = ORANGE, -- DBM 27.0 then 61.5
              warning = true, warningText = "Breath incoming — hide!", sound = "raidwarning" },
            { id = "breath2", name = "Breath 2", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
              trigger = { type = "timer", delay = 57.3, interval = 61.5 }, barColor = ORANGE, -- DBM 57.3 then 61.5
              warning = true, warningText = "Breath incoming — hide!", sound = "raidwarning" },
            -- Tranq-shot rotation target. -- DBM v12.5-16.1 (low bound)
            { id = "frenzy", name = "Frenzy", icon = "Interface\\Icons\\Ability_Druid_Berserk",
              trigger = { type = "cast", spellID = 23128, npcID = 14020 }, barColor = RED,
              mode = "cooldown", style = "icon", cooldown = 12.5, firstCast = 12.5,
              warningText = "Frenzy — tranq!", sound = "raidwarning" },
            -- LIMITATION: DBM detects the ACTIVE vulnerability school by scanning the boss's
            -- buffs (22277/22278/22279/22280/22281) off the "flinches as its skin shimmers"
            -- emote — our engine has no such scan, so this is just a blind recurring radial
            -- for "the school may have rotated". Off by default. -- DBM v16.2-25.9 (low bound)
            { id = "vulnshift", name = "Vulnerability Shift", icon = "Interface\\Icons\\Spell_Nature_WispSplode",
              trigger = { type = "timer" }, barColor = YELLOW,
              mode = "cooldown", style = "icon", cooldown = 16.2, firstCast = 16.2, default = false },
            -- 20% soft enrage (DBM-source syncs a "soon" at 25% then announces the 23537 aura;
            -- we key the health threshold directly).
            { id = "enrage", name = "Enrage (20%)", icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",
              trigger = { type = "health", pct = 20 }, barColor = RED,
              warning = true, warningText = "Chromaggus 20% — Enrage!", sound = "raidwarning" },
        }},

        -- ── Nefarian ──────────────────────────────────────────────────────────
        -- npcIDs include the Phase 1 drakonid adds (Red/Blue/Green/Bronze/Black/Chromatic)
        -- so the encounter engages during the add phase and the yell-triggered class calls
        -- register from pull (same pattern as Thaddius' Stalagg/Feugen). Side effect: the
        -- Shadow Flame / Bellowing Roar radials free-run through P1 and only become
        -- meaningful after they resync on Nefarian's first P2 casts.
        { id = "nefarian", name = "Nefarian",
          npcIDs = { 11583, 14261, 14262, 14263, 14264, 14265, 14302 }, mechanics = {
            -- Onyxia Scale Cloak check (P2). -- DBM v8.1-37.2 (low bound)
            { id = "shadowflame", name = "Shadow Flame", icon = "Interface\\Icons\\Spell_Fire_Incinerate",
              trigger = { type = "cast", spellID = 22539, npcID = 11583 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 8.1, winWarning = true,
              warningText = "Shadow Flame — cloak up!", sound = "raidwarning" },
            -- AoE fear. -- DBM v27-90.1 (low bound)
            { id = "bellowingroar", name = "Bellowing Roar", icon = "Interface\\Icons\\Spell_Shadow_DeathScream",
              trigger = { type = "cast", spellID = 22686, npcID = 11583 }, barColor = RED,
              mode = "cooldown", style = "icon", cooldown = 27, winWarning = true, winSound = true,
              warningText = "AoE Fear soon — tremor/berserker rage!", sound = "raidwarning",
              countdownVoice = true },  -- precast tremor/berserker rage (27s cycle)
            -- -75% healing curse on the tank. log-verified 2026-07-26: intervals 16.1-53.4
            -- (too variable for a radial — alert on the aura landing).
            { id = "veilofshadow", name = "Veil of Shadow", icon = "Interface\\Icons\\Spell_Shadow_GatherShadows",
              trigger = { type = "aura", spellID = 22687 }, barColor = PURPLE,
              warning = true, warningText = "Veil of Shadow — healing cut, decurse!", sound = "raidwarning" },
            { id = "taillash", name = "Tail Lash", icon = "Interface\\Icons\\Ability_Whirlwind",
              trigger = { type = "cast", spellID = 23364, npcID = 11583 }, barColor = ORANGE, default = false },
            -- Mind control. -- DBM 15.0 target bar
            { id = "shadowcommand", name = "Shadow Command", icon = "Interface\\Icons\\Spell_Shadow_ShadowWordDominate",
              trigger = { type = "aura", spellID = 22667 }, barColor = PURPLE, barDuration = 15,
              warning = true, warningText = "Shadow Command — MC!", sound = "raidwarning" },

            -- Class calls: one mechanic per vanilla class (the trigger shape supports a single
            -- yell text each). Yell substrings + the 30s call duration lifted from DBM-source
            -- (unverified live). All nine default ON — each fires once-in-a-while and everyone
            -- needs to know which class just got hit. -- DBM-source 30.0 "call ends" bar
            { id = "classcall_druid", name = "Class Call: Druid", icon = "Interface\\Icons\\ClassIcon_Druid",
              trigger = { type = "yell", text = "silly shapeshifting" }, barColor = ORANGE,
              style = "flash", barDuration = 30, warningText = "Class Call — Druids!", sound = "raidwarning" },
            { id = "classcall_hunter", name = "Class Call: Hunter", icon = "Interface\\Icons\\ClassIcon_Hunter",
              trigger = { type = "yell", text = "Hunters and your annoying" }, barColor = GREEN,
              style = "flash", barDuration = 30, warningText = "Class Call — Hunters!", sound = "raidwarning" },
            { id = "classcall_mage", name = "Class Call: Mage", icon = "Interface\\Icons\\ClassIcon_Mage",
              trigger = { type = "yell", text = "more careful when you play with magic" }, barColor = BLUE,
              style = "flash", barDuration = 30, warningText = "Class Call — Mages!", sound = "raidwarning" },
            { id = "classcall_paladin", name = "Class Call: Paladin", icon = "Interface\\Icons\\ClassIcon_Paladin",
              trigger = { type = "yell", text = "I've heard you have many lives" }, barColor = YELLOW,
              style = "flash", barDuration = 30, warningText = "Class Call — Paladins!", sound = "raidwarning" },
            { id = "classcall_priest", name = "Class Call: Priest", icon = "Interface\\Icons\\ClassIcon_Priest",
              trigger = { type = "yell", text = "keep healing like that" }, barColor = YELLOW,
              style = "flash", barDuration = 30, warningText = "Class Call — Priests! Heals now HURT!", sound = "raidwarning" },
            { id = "classcall_rogue", name = "Class Call: Rogue", icon = "Interface\\Icons\\ClassIcon_Rogue",
              trigger = { type = "yell", text = "Stop hiding and face me" }, barColor = ORANGE,
              style = "flash", barDuration = 30, warningText = "Class Call — Rogues teleported!", sound = "raidwarning" },
            { id = "classcall_shaman", name = "Class Call: Shaman", icon = "Interface\\Icons\\ClassIcon_Shaman",
              trigger = { type = "yell", text = "show me what your totems can do" }, barColor = BLUE,
              style = "flash", barDuration = 30, warningText = "Class Call — Shamans! Kill the totems!", sound = "raidwarning" },
            { id = "classcall_warlock", name = "Class Call: Warlock", icon = "Interface\\Icons\\ClassIcon_Warlock",
              trigger = { type = "yell", text = "magic you don't understand" }, barColor = PURPLE,
              style = "flash", barDuration = 30, warningText = "Class Call — Warlocks! Kill the infernals!", sound = "raidwarning" },
            { id = "classcall_warrior", name = "Class Call: Warrior", icon = "Interface\\Icons\\ClassIcon_Warrior",
              trigger = { type = "yell", text = "I know you can hit harder" }, barColor = ORANGE,
              style = "flash", barDuration = 30, warningText = "Class Call — Warriors forced into Berserker!", sound = "raidwarning" },

            -- Phase 2: Nefarian lands once ~42 adds are down. DBM-source has NO landing yell
            -- (its P2 detect polls IsEncounterInProgress); classic landing yell used instead —
            -- unverified live, confirm via /drm debug.
            { id = "landing", name = "Phase 2 (Landing)", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Black",
              trigger = { type = "yell", text = "BURN! You wretches" }, barColor = RED,
              style = "flash", warningText = "Nefarian landing!", sound = "raidwarning",
              special = true },  -- phase 2: reposition everything — act-now tier
            -- Phase 3 at 20%: the P1 Drakonid corpses rise as Bone Constructs.
            -- Yell substring from DBM-source (unverified live).
            { id = "phase3", name = "Phase 3 (Bone Constructs)", icon = "Interface\\Icons\\Spell_Shadow_RaiseDead",
              trigger = { type = "yell", text = "Rise my minions" }, barColor = RED,
              style = "flash", warningText = "Phase 3 — Bone Constructs!", sound = "raidwarning" },
        }},
    },
})
