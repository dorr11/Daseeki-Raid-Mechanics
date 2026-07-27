--[[
    Daseeki Raid Mechanics — Temple of Ahn'Qiraj (40-man, vanilla / Classic Era) encounter data.

    Mechanic shape (see core.lua GetMechanicConfig for how defaults merge with DB overrides):
      {
        id, name, icon,
        trigger = { type = "cast"|"aura"|"yell"|"emote"|"health"|"death"|"timer",
                    spellID=, spellName=, npcID=, text=, pct=, onPlayer=, onRemove=,
                    delay=, interval= },
        mode  = "alert" (default) | "cooldown",   -- cooldown = recurring window cycle
        style = "bar"|"castbar"|"icon"|"nameplate"|"number"|"text"|"flash"|"pulse" (default "bar"),
        scale = 1.0,  opacity = 1.0,              -- per-mechanic defaults (user-overridable)
        barDuration = secs,  barColor = {r,g,b},
        warningText = "...",  warningColor = {r,g,b},   -- used by text/flash + window warnings
        sound = <bucket key: "raidwarning"|"ding"|"bell"|"none"|...> (see media.lua),
        cooldown = secs,  window = secs,          -- cooldown mode only
        winSound = false,  winWarning = false,    -- fire sound/text when the window opens
        default = true|false (mechanic enabled by default),
        customWidget = nil,   -- reserved hook for deferred bespoke visualizations
      }

    Most values are just DEFAULTS — the per-mechanic options editor lets the player change
    style / scale / opacity / sound / cooldown / window behavior and position per mechanic.

    Sources: ~17 MB captured Anniversary-server combat logs + DBM's own timers logged
    verbatim (2026-07-26), backfilled from installed DBM-Raids-Vanilla source for thin
    samples / phase structure. Provenance is tagged per value:
      "log-verified 2026-07-26"     = measured server casts
      "DBM <val>"                   = DBM's own timer duration captured live
      "DBM-source (unverified live)" = lifted from DBM-Raids-Vanilla files, not yet seen in logs
--]]

local _, Addon = ...

local RED    = { 0.90, 0.20, 0.20 }
local ORANGE = { 0.95, 0.55, 0.15 }
local PURPLE = { 0.65, 0.35, 0.90 }
local GREEN  = { 0.30, 0.80, 0.35 }
local BLUE   = { 0.30, 0.55, 0.95 }
local YELLOW = { 0.95, 0.85, 0.25 }

Addon:RegisterRaid({
    id    = "aq40",
    name  = "Temple of Ahn'Qiraj",
    order = 60,
    mapID = 531,
    size  = 40,
    icon  = "Interface\\Icons\\INV_Misc_QirajiCrystal_05",
    bosses = {
        -- ── The Prophet Skeram ────────────────────────────────────────────────
        -- Thin log sample (3/3/2/1 casts); structure backfilled from DBM source.
        { id = "skeram", name = "The Prophet Skeram", npcIDs = { 15263 }, mechanics = {
            -- Interruptible ranged-silence nuke. log-verified 2026-07-26: 3 casts of 26194.
            { id = "earthshock", name = "Earth Shock", icon = "Interface\\Icons\\Spell_Nature_EarthShock",
              trigger = { type = "cast", spellID = 26194, npcID = 15263 }, barColor = ORANGE },
            -- The 75/50/25% split. DBM-source prewarns via HP brackets (78/53/28) which our
            -- engine can't multi-trigger — the on-cast flash is the actionable moment anyway.
            -- log-verified 2026-07-26: 3 casts of 747, iv ~19.4 (HP-gated, not a timer).
            { id = "images", name = "Summon Images (split)", icon = "Interface\\Icons\\Spell_Magic_LesserInvisibilty",
              trigger = { type = "cast", spellID = 747, npcID = 15263 }, barColor = BLUE,
              style = "flash", warningText = "Skeram splits — find the real one!", sound = "raidwarning" },
            -- Mind control. Bar = DBM's 20.0s target timer; fires on the aura landing on anyone.
            -- log-verified 2026-07-26: 2 casts, iv ~32.4; DBM target bar 20.0.
            { id = "fulfillment", name = "True Fulfillment (MC)", icon = "Interface\\Icons\\Spell_Shadow_ShadowWordDominate",
              trigger = { type = "aura", spellID = 785 }, barColor = PURPLE, barDuration = 20,
              warning = true, warningText = "Mind Control — CC them!", sound = "raidwarning" },
            -- log-verified 2026-07-26: 1 cast of 8195. Tank reposition alert.
            { id = "teleport", name = "Teleport", icon = "Interface\\Icons\\Spell_Arcane_Blink",
              trigger = { type = "cast", spellID = 8195, npcID = 15263 }, barColor = BLUE },
        }},

        -- ── Bug Trio (Silithid Royalty) ───────────────────────────────────────
        -- Kri 15511 / Yauj 15543 / Vem 15544. Modest defaults — kill-order-dependent fight.
        { id = "bugtrio", name = "Bug Trio", npcIDs = { 15511, 15543, 15544 }, mechanics = {
            -- Kri. Raid-wide poison — cure it. Cooldown = low bound of DBM v8.1-35.1.
            { id = "toxicvolley", name = "Toxic Volley", icon = "Interface\\Icons\\Spell_Nature_CorrosiveBreath",
              trigger = { type = "cast", spellID = 25812, npcID = 15511 }, barColor = GREEN,
              mode = "cooldown", style = "icon", cooldown = 8.1, -- DBM 8.1 (low bound of v8.1-35.1)
              warningText = "Toxic Volley — cure poison!", sound = "ding" },
            { id = "cleave", name = "Cleave (Kri)", icon = "Interface\\Icons\\Ability_Warrior_Cleave",
              trigger = { type = "cast", spellID = 15584, npcID = 15511 }, barColor = ORANGE, default = false }, -- log-verified 2026-07-26: ~20s apart
            -- Fires when Kri dies (his death drops a lethal poison cloud on his corpse).
            -- log-verified 2026-07-26: cast 26590 on Kri death.
            { id = "poisoncloud", name = "Poison Cloud (Kri death)", icon = "Interface\\Icons\\Spell_Nature_Acid_01",
              trigger = { type = "cast", spellID = 26590 }, barColor = GREEN,
              style = "flash", warningText = "Kri died — move from the poison cloud!", sound = "raidwarning" },
            { id = "thrash", name = "Thrash (Kri)", icon = "Interface\\Icons\\INV_Misc_MonsterClaw_02",
              trigger = { type = "cast", spellID = 3391, npcID = 15511 }, barColor = ORANGE, default = false }, -- log-verified 2026-07-26
            -- Yauj. AoE fear — tremor/berserker rage. Cooldown = low bound (DBM 10.6-20.3).
            { id = "fear", name = "Fear (Yauj)", icon = "Interface\\Icons\\Spell_Shadow_Psychicscream",
              trigger = { type = "cast", spellID = 26580, npcID = 15543 }, barColor = RED,
              mode = "cooldown", style = "icon", cooldown = 10.5, glowThreshold = 3, -- DBM 10.6-20.3
              winWarning = true, winSound = true, warningText = "Fear soon — tremor!", sound = "raidwarning" },
            { id = "ravage", name = "Ravage (Yauj)", icon = "Interface\\Icons\\Ability_Druid_Ravage",
              trigger = { type = "cast", spellID = 3242, npcID = 15543 }, barColor = ORANGE, default = false }, -- log-verified 2026-07-26: ~12.2s apart
            -- Yauj's Great Heal 25807 (SPELL_CAST_START in DBM) — the trio's interrupt check.
            -- DBM-source (unverified live): interrupt special warning on cast start.
            { id = "heal", name = "Great Heal (Yauj)", icon = "Interface\\Icons\\Spell_Holy_GreaterHeal",
              trigger = { type = "cast", spellID = 25807, npcID = 15543, onStart = true }, barColor = YELLOW,
              style = "flash", warningText = "Yauj healing — interrupt!", sound = "raidwarning" },
            -- Vem. Quiet tank-info radials, off by default (order-dependent fight).
            { id = "knockaway", name = "Knock Away (Vem)", icon = "Interface\\Icons\\INV_Gauntlets_05",
              trigger = { type = "cast", spellID = 18670, npcID = 15544 }, barColor = ORANGE,
              mode = "cooldown", style = "icon", cooldown = 10.8, default = false }, -- log-verified 2026-07-26: iv 10.8-20.0
            { id = "knockdown", name = "Knockdown (Vem)", icon = "Interface\\Icons\\Spell_Frost_Stun",
              trigger = { type = "cast", spellID = 19128, npcID = 15544 }, barColor = ORANGE,
              mode = "cooldown", style = "icon", cooldown = 10.9, default = false }, -- log-verified 2026-07-26: iv 10.9-21.0
            { id = "charge", name = "Berserker Charge (Vem)", icon = "Interface\\Icons\\Ability_Warrior_Charge",
              trigger = { type = "cast", spellID = 26561, npcID = 15544 }, barColor = RED,
              mode = "cooldown", style = "icon", cooldown = 17.7, default = false }, -- log-verified 2026-07-26: iv 17.7-24.2
            -- Fires when Vem dies — remaining bugs enrage. log-verified 2026-07-26: 25790 on Vem death.
            { id = "vengeance", name = "Vengeance (Vem death)", icon = "Interface\\Icons\\Ability_Racial_Avatar",
              trigger = { type = "aura", spellID = 25790 }, barColor = RED,
              style = "flash", warningText = "Vem died — Vengeance! Bosses enraged!", sound = "raidwarning" },
        }},

        -- ── Battleguard Sartura ───────────────────────────────────────────────
        { id = "sartura", name = "Battleguard Sartura", npcIDs = { 15516 }, mechanics = {
            -- NOTE: 26084 is the whirlwind TICK (76 casts logged) — do NOT trigger on it.
            -- log-verified 2026-07-26: 26083 iv 25.9-29.1.
            { id = "whirlwind", name = "Whirlwind", icon = "Interface\\Icons\\Ability_Whirlwind",
              trigger = { type = "cast", spellID = 26083, npcID = 15516 }, barColor = ORANGE,
              mode = "cooldown", style = "icon", cooldown = 26, glowThreshold = 3,
              winWarning = true, winSound = true, warningText = "Whirlwind soon — move out!", sound = "raidwarning" },
            { id = "cleave", name = "Sundering Cleave", icon = "Interface\\Icons\\Ability_Warrior_Sunder",
              trigger = { type = "cast", spellID = 25174, npcID = 15516 }, barColor = ORANGE, default = false },
            -- 20% enrage (DBM-source prewarns at 35% HP via sync; we fire on the actual cast).
            { id = "enrage", name = "Enrage", icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",
              trigger = { type = "cast", spellID = 8269, npcID = 15516 }, barColor = RED,
              warning = true, warningText = "Sartura Enrage!", sound = "raidwarning" },
        }},

        -- ── Fankriss the Unyielding ───────────────────────────────────────────
        { id = "fankriss", name = "Fankriss the Unyielding", npcIDs = { 15510 }, mechanics = {
            -- Tank swap driver. npcID gate matters: Gluth shares spellID 25646.
            -- log-verified 2026-07-26: iv 6.5-9.7; bar = DBM 20.0s debuff duration.
            { id = "mortalwound", name = "Mortal Wound", icon = "Interface\\Icons\\Ability_Criticalstrike",
              trigger = { type = "cast", spellID = 25646, npcID = 15510 }, barColor = ORANGE,
              style = "bar", barDuration = 20,
              warning = true, warningText = "Mortal Wound — tank swap at high stacks!", sound = "ding" },
            -- Roots a random player near a worm spawn. Bar = DBM's 8.0s target timer.
            -- DBM-source also matches rank variants 731/1121 — add if 720 misses live.
            { id = "entangle", name = "Entangle", icon = "Interface\\Icons\\Spell_Nature_StrangleVines",
              trigger = { type = "aura", spellID = 720 }, barColor = GREEN, barDuration = 8, -- DBM target bar 8.0
              warning = true, warningText = "Entangle — free them!", sound = "raidwarning" },
            -- log-verified 2026-07-26: summon uses all three IDs.
            { id = "worms", name = "Summon Worm", icon = "Interface\\Icons\\Spell_Nature_InsectSwarm",
              trigger = { type = "cast", spellIDs = { 518, 25831, 25832 } }, barColor = PURPLE,
              style = "flash", warningText = "Worm spawned — kill it!", sound = "raidwarning" },
        }},

        -- ── Viscidus ──────────────────────────────────────────────────────────
        -- Freeze/shatter cycle is emote-driven; emote texts lifted from DBM source
        -- (engine matches substring on CHAT_MSG_MONSTER_EMOTE).
        { id = "viscidus", name = "Viscidus", npcIDs = { 15299 }, mechanics = {
            -- Counted like Loatheb's Spore: "Poison Bolt N" on each cast.
            { id = "poisonvolley", name = "Poison Bolt Volley", icon = "Interface\\Icons\\Spell_Nature_CorrosiveBreath",
              trigger = { type = "cast", spellID = 25991, npcID = 15299 }, barColor = GREEN,
              mode = "cooldown", style = "icon", cooldown = 11.3, showCount = true, -- DBM 11.3 w/ count 1-9
              castText = "Poison Bolt %d", onCastDefault = true, sound = "ding" },
            { id = "poisonshock", name = "Poison Shock", icon = "Interface\\Icons\\Spell_Nature_Acid_01",
              trigger = { type = "cast", spellID = 25993, npcID = 15299 }, barColor = GREEN, default = false }, -- log-verified 2026-07-26: iv 8.1-34
            -- Progress emote before the full freeze — quiet info, off by default.
            -- DBM-source (unverified live): emotes run "begins to slow" -> "is freezing up" -> "is frozen solid".
            { id = "freezing", name = "Freezing (progress)", icon = "Interface\\Icons\\Spell_Frost_FrostArmor02",
              trigger = { type = "emote", text = "is freezing up" }, barColor = BLUE,
              style = "text", warningText = "Viscidus freezing — keep frost hits coming!", sound = "ding", default = false },
            -- Fully frozen: melee burn window. DBM-source (unverified live) emote text.
            { id = "frozen", name = "Frozen (melee!)", icon = "Interface\\Icons\\Spell_Frost_Glacier",
              trigger = { type = "emote", text = "is frozen solid" }, barColor = BLUE,
              style = "flash", warningText = "Viscidus FROZEN — melee burn!", sound = "raidwarning" },
            -- "looks ready to shatter" = final crack emote ("begins to crack" precedes it).
            -- DBM-source (unverified live).
            { id = "shatter", name = "Shatter", icon = "Interface\\Icons\\Spell_Frost_FrostShock",
              trigger = { type = "emote", text = "looks ready to shatter" }, barColor = BLUE,
              style = "flash", warningText = "SHATTER!", sound = "raidwarning",
              special = true },  -- everyone must burst NOW — act-now tier
            -- Globs crawl back together after a shatter — kill window ends when this lands.
            { id = "rejoin", name = "Rejoin (reform)", icon = "Interface\\Icons\\INV_Misc_Slime_01",
              trigger = { type = "cast", spellID = 25896 }, barColor = GREEN, barDuration = 16.5, -- DBM bar 16.5
              warning = true, warningText = "Viscidus reforming — kill globs!", sound = "ding" },
        }},

        -- ── Princess Huhuran ──────────────────────────────────────────────────
        { id = "huhuran", name = "Princess Huhuran", npcIDs = { 15509 }, mechanics = {
            -- Hunter tranq target. Cooldown = low bound; DBM "Frenzy ends" 8.0.
            { id = "frenzy", name = "Frenzy", icon = "Interface\\Icons\\Ability_Druid_Berserk",
              trigger = { type = "cast", spellID = 26051, npcID = 15509 }, barColor = RED,
              mode = "cooldown", style = "icon", cooldown = 6.5, -- DBM 6.5-11.3
              warningText = "Frenzy — tranq!", sound = "raidwarning" },
            -- Tank stacking nature debuff; bar = DBM's 30.0s target timer.
            { id = "acidspit", name = "Acid Spit", icon = "Interface\\Icons\\Spell_Nature_Acid_01",
              trigger = { type = "aura", spellID = 26050 }, barColor = GREEN, barDuration = 30 }, -- DBM target bar 30.0
            -- Melee-group poison — cleanse it.
            { id = "noxious", name = "Noxious Poison", icon = "Interface\\Icons\\Ability_Creature_Poison_03",
              trigger = { type = "cast", spellID = 26053, npcID = 15509 }, barColor = GREEN,
              mode = "cooldown", style = "icon", cooldown = 11.3 }, -- DBM 11.3
            -- Sleep poison on random players (damages on dispel — careful).
            -- Bar = DBM-source 12s fade timer (unverified live).
            { id = "sting", name = "Wyvern Sting", icon = "Interface\\Icons\\INV_Spear_02",
              trigger = { type = "aura", spellID = 26180 }, barColor = GREEN, barDuration = 12, -- DBM 6.8-25.9 recast
              warning = true, warningText = "Wyvern Sting — careful dispel!", sound = "ding" },
            -- DBM-source detects the 30% berserk via SPELL_AURA_APPLIED 26068 (not yell/HP);
            -- mirrored with our aura trigger. Prewarn below fires off raw HP.
            { id = "berserksoon", name = "Berserk Soon (35%)", icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",
              trigger = { type = "health", pct = 35 }, barColor = RED,
              warning = true, warningText = "Huhuran Berserk soon — spread!", sound = "raidwarning" }, -- DBM-source prewarn at 35%
            { id = "berserk", name = "Berserk (30%)", icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",
              trigger = { type = "aura", spellID = 26068 }, barColor = RED,
              style = "flash", warningText = "Berserk — max ranged spread!", sound = "raidwarning",
              special = true },  -- P2 spread check: grouped ranged die — act-now tier
        }},

        -- ── Twin Emperors ─────────────────────────────────────────────────────
        -- Vek'nilash 15275 (melee-immune to magic) / Vek'lor 15276 (immune to melee).
        { id = "twinemps", name = "Twin Emperors", npcIDs = { 15275, 15276 }, mechanics = {
            -- THE fight mechanic: emperors swap positions; tanks/warlocks reposition.
            -- log-verified 2026-07-26: DBM CD 29.1-30.8. DBM-source also watches aura 799.
            { id = "teleport", name = "Twin Teleport", icon = "Interface\\Icons\\Spell_Arcane_Blink",
              trigger = { type = "cast", spellID = 800 }, barColor = BLUE,
              mode = "cooldown", style = "icon", cooldown = 29, firstCast = 31, glowThreshold = 5, -- DBM 29.1-30.8; first ~30.8 from pull
              winWarning = true, winSound = true, warningText = "Teleport soon — swap sides!", sound = "raidwarning",
              countdownVoice = true },  -- side-swap positioning (29s cycle)
            -- Vek'nilash tank debuff. log-verified 2026-07-26: iv 8.1-43.7; DBM 9.7-11.2.
            { id = "unbalancing", name = "Unbalancing Strike", icon = "Interface\\Icons\\Ability_Warrior_Disarm",
              trigger = { type = "cast", spellID = 26613, npcID = 15275 }, barColor = ORANGE,
              warning = true, warningText = "Unbalancing Strike — tank cooldowns!", sound = "ding" },
            { id = "mutatebug", name = "Mutate Bug (Vek'lor)", icon = "Interface\\Icons\\INV_Misc_MonsterSpiderCarapace_01",
              trigger = { type = "cast", spellID = 802, npcID = 15276 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 10.9, default = false }, -- DBM 10.9
            -- Spammy (DBM 4.5) — off by default.
            { id = "explodebug", name = "Explode Bug", icon = "Interface\\Icons\\Spell_Fire_SelfDestruct",
              trigger = { type = "cast", spellID = 804 }, barColor = ORANGE,
              mode = "cooldown", style = "icon", cooldown = 4.5, default = false }, -- DBM 4.5
            -- Vek'lor punishes melee range — positioning info, off by default.
            { id = "arcaneburst", name = "Arcane Burst (Vek'lor)", icon = "Interface\\Icons\\Spell_Nature_WispSplode",
              trigger = { type = "cast", spellID = 568, npcID = 15276 }, barColor = BLUE, default = false },
            { id = "healbrother", name = "Heal Brother", icon = "Interface\\Icons\\Spell_Holy_GreaterHeal",
              trigger = { type = "cast", spellID = 7393 }, barColor = YELLOW, default = false },
            -- Hard-enrage countdown from pull (one-shot bar, modeled on the Naxx berserk entries).
            { id = "berserk", name = "Berserk (15 min)", icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",
              trigger = { type = "timer" }, barColor = RED,
              mode = "cooldown", style = "bar", cooldown = 900, firstCast = 900, noLoop = true, -- DBM 900
              winWarning = true, winSound = true, warningText = "Twin Emperors Berserk!", sound = "raidwarning" },
        }},

        -- ── Ouro ──────────────────────────────────────────────────────────────
        { id = "ouro", name = "Ouro", npcIDs = { 15517 }, mechanics = {
            -- Knocks the target back and wipes threat unless eaten by the tank in front.
            { id = "sandblast", name = "Sand Blast", icon = "Interface\\Icons\\Spell_Nature_Cyclone",
              trigger = { type = "cast", spellID = 26102, npcID = 15517 }, barColor = YELLOW,
              mode = "cooldown", style = "icon", cooldown = 22.1, glowThreshold = 3, -- DBM 22.1
              winWarning = true, winSound = true, warningText = "Sand Blast soon!", sound = "raidwarning" },
            { id = "sweep", name = "Sweep", icon = "Interface\\Icons\\INV_Misc_MonsterTail_03",
              trigger = { type = "cast", spellID = 26103, npcID = 15517 }, barColor = ORANGE,
              mode = "cooldown", style = "icon", cooldown = 21 }, -- DBM 20.6-24.1
            -- Surface cycle: DBM one-shot bar 184.0s per surface phase + 30s submerged
            -- => 214s submerge-to-submerge. Resyncs on the Summon Ouro Mounds cast (26058
            -- fires at the moment he submerges); free-runs from pull until then.
            -- DBM-source (unverified live): emerge is scheduled 30s after submerge, not event-detected.
            { id = "submerge", name = "Submerge (next)", icon = "Interface\\Icons\\Spell_Nature_Earthquake",
              trigger = { type = "cast", spellID = 26058, npcID = 15517 }, barColor = YELLOW,
              mode = "cooldown", style = "bar", cooldown = 214, firstCast = 184, -- DBM 184.0 surface + 30 submerged
              winWarning = true, winSound = true, warningText = "Ouro submerging — spread!", sound = "raidwarning" },
            -- P2 / 20%: no more submerges, boss enrages. DBM-source detects via aura 26615.
            { id = "berserk", name = "Berserk (20%)", icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",
              trigger = { type = "aura", spellID = 26615 }, barColor = RED,
              style = "flash", warningText = "Ouro Berserk — burn!", sound = "raidwarning" },
            -- Spawn/emerge info alerts — quiet defaults.
            { id = "mounds", name = "Ouro Mounds", icon = "Interface\\Icons\\INV_Misc_Dust_02",
              trigger = { type = "cast", spellID = 26058, npcID = 15517 }, barColor = ORANGE,
              style = "text", warningText = "Mounds up — scarabs incoming!", sound = "ding", default = false },
            -- Birth 26586 marks the emerge; source npc unverified on this server (the Dirt
            -- Mound transforms back into Ouro), so no npcID gate. DBM-source (unverified live).
            { id = "emerge", name = "Emerge", icon = "Interface\\Icons\\Spell_Nature_Earthquake",
              trigger = { type = "cast", spellID = 26586 }, barColor = GREEN,
              style = "text", warningText = "Ouro emerging!", sound = "ding", default = false },
        }},

        -- ── C'Thun ────────────────────────────────────────────────────────────
        -- Eye of C'Thun 15589 (P1) / C'Thun 15727 (P2). Ignore spells 364340/364341
        -- ("Survivor") — Anniversary achievement trackers, not mechanics.
        { id = "cthun", name = "C'Thun", npcIDs = { 15727, 15589 }, mechanics = {
            -- Countdown to the next glare. DBM: first 48.0 from pull, then 86.0 cast-to-cast
            -- (39s glare + ~47s gap). Resyncs on the actual cast when it logs.
            { id = "darkglarecd", name = "Dark Glare (next)", icon = "Interface\\Icons\\Spell_Shadow_Charm",
              trigger = { type = "cast", spellID = 26029, npcID = 15589 }, barColor = RED,
              mode = "cooldown", style = "icon", cooldown = 86, firstCast = 48, glowThreshold = 5, -- DBM 48 first, 86 cycle
              winWarning = true, winSound = true, warningText = "Dark Glare soon — position!", sound = "raidwarning",
              countdownVoice = true },  -- pre-rotate out of the beam path (86s cycle)
            -- The 39s rotating-beam window itself (DBM "Dark Glare ends" 39.0).
            { id = "darkglare", name = "Dark Glare (rotating)", icon = "Interface\\Icons\\Spell_Shadow_Charm",
              trigger = { type = "cast", spellID = 26029, npcID = 15589 }, barColor = RED,
              style = "bar", barDuration = 39, -- DBM 39.0
              warning = true, warningText = "Glare rotating — move!", sound = "raidwarning" },
            -- Green chain-beam, near-constant in P1 — off by default.
            -- log-verified 2026-07-26: iv 3.2-46.9.
            { id = "eyebeam", name = "Eye Beam", icon = "Interface\\Icons\\INV_Misc_Eye_01",
              trigger = { type = "cast", spellID = 26134, npcID = 15589 }, barColor = GREEN, default = false },
            -- Tentacle waves resync on the spawn's Birth cast (26586), npc-gated per tentacle
            -- type. DBM-source P1 cycle is 45s (first at 45); P2 tightens to 30 — cooldown uses
            -- the P2 value so the window never opens late (glows a little early in P1).
            { id = "eyetentacles", name = "Eye Tentacles", icon = "Interface\\Icons\\INV_Misc_Eye_01",
              trigger = { type = "cast", spellID = 26586, npcID = 15726 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 30, firstCast = 45, glowThreshold = 5, -- DBM 30.0-83.7; DBM-source P1 45s
              winWarning = true, winSound = true, warningText = "Eye Tentacles soon!", sound = "raidwarning" },
            -- P2-only spawns (radial free-runs in P1, resyncs once they start).
            -- DBM-source: Giant Claw first 10.5 after P2, then 60s cycle (53 after weaken).
            { id = "giantclaw", name = "Giant Claw Tentacle", icon = "Interface\\Icons\\INV_Misc_MonsterClaw_04",
              trigger = { type = "cast", spellID = 26586, npcID = 15728 }, barColor = ORANGE,
              mode = "cooldown", style = "icon", cooldown = 60 }, -- DBM 10.5-60; DBM-source 60s P2 cycle
            -- DBM-source: Giant Eye first 41.3 after P2, then 60s cycle (83.7 after weaken).
            { id = "gianteye", name = "Giant Eye Tentacle", icon = "Interface\\Icons\\INV_Misc_Eye_01",
              trigger = { type = "cast", spellID = 26586, npcID = 15334 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 60 }, -- DBM 41.3-83.7; DBM-source 60s P2 cycle
            -- P2 burn window after both Flesh Tentacles die. Detection is emote-driven —
            -- DBM-source matches substring "weaken" on CHAT_MSG_MONSTER_EMOTE; bar = DBM
            -- "Weaken ends" 45.0.
            { id = "weaken", name = "Weakened (burn!)", icon = "Interface\\Icons\\Spell_Shadow_Cripple",
              trigger = { type = "emote", text = "weaken" }, barColor = YELLOW, barDuration = 45, -- DBM 45.0
              warning = true, warningText = "C'Thun WEAKENED — body vulnerable, BURN!", sound = "raidwarning",
              special = true },  -- burn window: the whole fight hinges on it — act-now tier
        }},
    },
})
