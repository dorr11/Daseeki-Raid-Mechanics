--[[
    Daseeki Raid Mechanics — Naxxramas (40-man, vanilla / Classic Era) encounter data.

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

    NOTE: spellIDs/timers are the best-known vanilla 40-man values and should be
    confirmed in-game via /drm debug (they differ from WotLK Naxxramas).
--]]

local _, Addon = ...

local RED    = { 0.90, 0.20, 0.20 }
local ORANGE = { 0.95, 0.55, 0.15 }
local PURPLE = { 0.65, 0.35, 0.90 }
local GREEN  = { 0.30, 0.80, 0.35 }
local BLUE   = { 0.30, 0.55, 0.95 }
local YELLOW = { 0.95, 0.85, 0.25 }

Addon:RegisterRaid({
    id    = "naxxramas",
    name  = "Naxxramas",
    order = 70,
    mapID = 533,
    size  = 40,
    icon  = "Interface\\Icons\\Spell_Shadow_RaiseDead",
    bosses = {
        -- ── Arachnid Quarter ──────────────────────────────────────────────────
        { id = "anubrekhan", name = "Anub'Rekhan", npcIDs = { 15956 }, mechanics = {
            { id = "impale", name = "Impale", icon = "Interface\\Icons\\Ability_Rogue_Eviscerate",
              trigger = { type = "cast", spellID = 28783, npcID = 15956 }, barColor = ORANGE },
            { id = "locust", name = "Locust Swarm", icon = "Interface\\Icons\\Spell_Nature_InsectSwarm",
              trigger = { type = "cast", spellID = 28785, npcID = 15956 }, barColor = GREEN,
              mode = "cooldown", style = "icon", cooldown = 77, winWarning = true, winSound = true, -- DBM 77.3 consistently (2026-07-26; was 81)
              warningText = "Locust Swarm soon!", sound = "raidwarning" },
        }},
        { id = "faerlina", name = "Grand Widow Faerlina", npcIDs = { 15953 }, mechanics = {
            -- Rain of Fire never combat-logs as a boss CAST on this server — it only shows up as
            -- SPELL_AURA_APPLIED on players (+ periodic damage). Personal get-out alert instead.
            -- log-verified 2026-07-26.
            { id = "rainoffire", name = "Rain of Fire", icon = "Interface\\Icons\\Spell_Shadow_RainOfFire",
              trigger = { type = "aura", spellID = 28794, onPlayer = true }, barColor = ORANGE,
              style = "flash", warningText = "Rain of Fire on YOU — move!", sound = "raidwarning" },
            { id = "poisonbolt", name = "Poison Bolt Volley", icon = "Interface\\Icons\\Spell_Nature_CorrosiveBreath",
              trigger = { type = "cast", spellID = 28796, npcID = 15953 }, barColor = GREEN },
            { id = "frenzy", name = "Enrage", icon = "Interface\\Icons\\Ability_Druid_Berserk",
              trigger = { type = "aura", spellID = 28131 }, barColor = RED, -- log-verified 2026-07-26: Enrage 28131 (CAST + AURA_APPLIED, 12-15x); old aura 28798 never appears
              warning = true, warningText = "Faerlina Enrage — sacrifice!", sound = "raidwarning" },
            -- Cast by a Naxxramas Worshipper add (no npcID gate). 30s window during which her
            -- Enrage is suppressed. -- DBM 30.0s effect
            { id = "embrace", name = "Widow's Embrace", icon = "Interface\\Icons\\Spell_Shadow_NightOfTheDead",
              trigger = { type = "cast", spellID = 28732 }, barColor = PURPLE,
              style = "bar", barDuration = 30, default = true,
              warningText = "Widow's Embrace — Enrage delayed!", sound = "ding" },
        }},
        { id = "maexxna", name = "Maexxna", npcIDs = { 15952 }, mechanics = {
            -- Web Spray = a cooldown radial counting to the next spray (DBM 40.5s, predicted
            -- from pull via firstCast).
            { id = "webspray", name = "Web Spray", icon = "Interface\\Icons\\Ability_Ensnare",
              trigger = { type = "cast", spellID = 29484, npcID = 15952 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 40, firstCast = 40, glowThreshold = 5,
              winWarning = true, winSound = true, warningText = "Web Spray soon!", sound = "raidwarning",
              countdownVoice = true },  -- pre-heal/position before the AoE stun (40s cycle)
            -- Web Wrap = cooldown radial (DBM v39.6-40.9). Its `reminder` is the optional
            -- SNOWBALL warning — a separate radial that fires `leadTime`s before each wrap,
            -- with its own icon/scale/opacity/glow/sound/position (configured in Web Wrap's
            -- settings, not Web Spray's).
            { id = "webwrap", name = "Web Wrap", icon = "Interface\\Icons\\Spell_Nature_StrangleVines",
              trigger = { type = "cast", spellID = 28622, npcID = 15952 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 40, firstCast = 18, -- DBM first 18.2, then 39.6
              reminder = { name = "Snowball", icon = "Interface\\Icons\\Spell_Frost_FrostBolt02",
                           style = "icon", leadTime = 5, barDuration = 5, glowThreshold = 5,
                           sound = "raidwarning", barColor = BLUE, default = false } },
            { id = "necrotic", name = "Necrotic Poison", icon = "Interface\\Icons\\Ability_Creature_Poison_03",
              trigger = { type = "cast", spellID = 28776, npcID = 15952 }, barColor = GREEN },
            -- Was a blind 30% HP trigger; now fires on the actual Enrage cast.
            -- log-verified 2026-07-26: 10 casts of "Enrage" 28747.
            { id = "frenzy", name = "Enrage (30%)", icon = "Interface\\Icons\\Ability_Druid_Berserk",
              trigger = { type = "cast", spellID = 28747, npcID = 15952 }, barColor = RED,
              warning = true, warningText = "Maexxna Frenzy!", sound = "raidwarning" },
            -- Spiderling wave cadence. The summon may not combat-log on this server, so the
            -- cycle free-runs from firstCast (that's fine).
            { id = "spiderlings", name = "Spiderlings", icon = "Interface\\Icons\\Spell_Nature_InsectSwarm",
              trigger = { type = "cast", spellID = 29434, npcID = 15952 }, barColor = ORANGE,
              mode = "cooldown", style = "icon", cooldown = 30.7, firstCast = 31, -- DBM 30.7 recurring
              winWarning = true, warningText = "Spiderlings soon!", sound = "ding" },
        }},

        -- ── Plague Quarter ────────────────────────────────────────────────────
        { id = "noth", name = "Noth the Plaguebringer", npcIDs = { 15954 }, mechanics = {
            { id = "curse", name = "Curse of the Plaguebringer", icon = "Interface\\Icons\\Spell_Shadow_PlagueCloud",
              trigger = { type = "cast", spellID = 29213, npcID = 15954 }, barColor = GREEN,
              mode = "cooldown", style = "icon", cooldown = 52, firstCast = 6, winWarning = true, winSound = true, -- DBM v6.4 then v51.8-118.9
              warningText = "Plaguebringer Curse soon — decurse!", sound = "raidwarning" },
            { id = "adds", name = "Adds (Blink phase)", icon = "Interface\\Icons\\Spell_Shadow_RaiseDead",
              trigger = { type = "yell", text = "Rise, my soldiers" }, barColor = RED,
              style = "flash", warningText = "Adds spawning — kill them!", sound = "raidwarning" },
            { id = "cripple", name = "Cripple", icon = "Interface\\Icons\\Spell_Shadow_Cripple",
              trigger = { type = "cast", spellID = 29212, npcID = 15954 }, barColor = PURPLE },
            { id = "blink", name = "Blink (Teleport)", icon = "Interface\\Icons\\Spell_Arcane_Blink",
              trigger = { type = "cast", spellIDs = { 29208, 29209, 29210, 29211 }, npcID = 15954 }, barColor = BLUE }, -- log-verified 2026-07-26: boss uses all four blink IDs
            -- First teleport DBM-verified at ~90.8s from pull; full ground+balcony cycle length
            -- UNVERIFIED (interval=160 is an estimate) — off by default until tuned in-game.
            { id = "teleport", name = "Teleport (balcony)", icon = "Interface\\Icons\\Spell_Arcane_Blink",
              trigger = { type = "timer", delay = 90, interval = 160 }, barColor = BLUE,
              warning = true, warningText = "Noth teleports — adds!", sound = "raidwarning", default = false },
        }},
        { id = "heigan", name = "Heigan the Unclean", npcIDs = { 15936 }, mechanics = {
            { id = "fever", name = "Decrepit Fever", icon = "Interface\\Icons\\Spell_Nature_NullifyDisease",
              trigger = { type = "cast", spellID = 29998, npcID = 15936 }, barColor = GREEN },
            { id = "disrupt", name = "Spell Disruption", icon = "Interface\\Icons\\Spell_Shadow_MindRot",
              trigger = { type = "cast", spellID = 29310, npcID = 15936 }, barColor = PURPLE },
            -- DBM: 90s from pull to the first teleport-to-dance, then dance(47s)/room(88s)
            -- => teleport-to-dance recurs every 135s. Fires when the dance phase begins.
            { id = "dance", name = "Dance Phase", icon = "Interface\\Icons\\Spell_Fire_Volcano",
              trigger = { type = "timer", delay = 90, interval = 135 }, barColor = ORANGE,
              warning = true, warningText = "Heigan Dance!", sound = "raidwarning", default = false },
        }},
        { id = "loatheb", name = "Loatheb", npcIDs = { 16011 }, mechanics = {
            -- Anniversary-server mechanics: Corrupted Mind (curse 29201, every ~11.3s) blocks
            -- heals; Loatheb's own "Remove Curse" cast (30281) every ~30.7s is the decurse/heal
            -- window. Old aura 29232 is actually "Fungal Bloom" (Spore add buff, npc 16286) on
            -- this server — wrong source entirely. Cooldown radial resyncs on each Remove Curse.
            -- log-verified 2026-07-26: 44 casts of 30281, intervals 30.3-32.3; DBM "Remove Curse" 0.5 then 30.7.
            { id = "necroticaura", name = "Heal Window (Remove Curse)", icon = "Interface\\Icons\\Spell_Shadow_AntiShadow",
              trigger = { type = "cast", spellID = 30281, npcID = 16011 }, barColor = GREEN,
              mode = "cooldown", style = "icon", cooldown = 30.7, firstCast = 31, glowThreshold = 3,
              winWarning = true, winSound = true, warningText = "Heal window — decurse!", sound = "raidwarning",
              countdownVoice = true },  -- healers pre-cast into the window (30.7s cycle)
            -- showCount + a "%d" placeholder in castText/reminder.warningText is
            -- substituted with the live spore count (1, 2, 3...) by FormatCountText
            -- in alerts.lua: "Spore N Soon - Move" ~5s before each spawn (reminder,
            -- defaulted ON), then "Spore N" the moment it casts (on-cast, defaulted ON).
            { id = "spore", name = "Spore", icon = "Interface\\Icons\\Spell_Nature_LivingBomb",
              trigger = { type = "cast", spellID = 29234, npcID = 16011 }, barColor = ORANGE,
              mode = "cooldown", style = "icon", cooldown = 12.9, firstCast = 11, showCount = true, -- DBM 11.3 then 12.9 w/ count
              winWarning = true, winSound = true, warningText = "Spore!", sound = "ding",
              castText = "Spore %d", onCastDefault = true,
              reminder = { name = "Spore Soon", style = "text", leadTime = 5, barDuration = 5,
                           sound = "raidwarning", barColor = ORANGE, default = true,
                           warningText = "Spore %d Soon - Move" } },
            -- 29865 is "Poison Aura" on this server — applied to the ENTIRE raid every ~14.5s,
            -- so a personal-aura alert fires constantly. Off by default to avoid spam.
            -- log-verified 2026-07-26.
            { id = "deathbloom", name = "Poison Aura", icon = "Interface\\Icons\\Spell_Nature_NatureTouchDecay",
              trigger = { type = "aura", spellID = 29865, onPlayer = true }, barColor = PURPLE, default = false },
            -- Cast on a random raid member; deals raid-wide damage if it expires. DBM's
            -- recast interval alternates ~29.1/32.4s (using the low bound here, consistent
            -- with how other variable DBM timers in this file are handled).
            { id = "doom", name = "Impending Doom", icon = "Interface\\Icons\\Spell_Shadow_CurseOfAchimonde",
              trigger = { type = "cast", spellID = 29204, npcID = 16011 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 29, firstCast = 121, showCount = true, -- DBM first ~121.3s, then v29.1-32.4
              winWarning = true, winSound = true, warningText = "Impending Doom!", sound = "raidwarning" },
        }},

        -- ── Construct Quarter ─────────────────────────────────────────────────
        { id = "patchwerk", name = "Patchwerk", npcIDs = { 16028 }, mechanics = {
            { id = "hateful", name = "Hateful Strike", icon = "Interface\\Icons\\Ability_Warrior_DecisiveStrike",
              trigger = { type = "cast", spellID = 28308, npcID = 16028 }, barColor = RED, barDuration = 1.2 }, -- UNVERIFIED on Anniversary: no trace in 485-pull log review 2026-07-26; confirm in-game
            { id = "berserk", name = "Enrage (5%)", icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",
              trigger = { type = "health", pct = 5 }, barColor = RED,
              warning = true, warningText = "Patchwerk Enrage — burn!", sound = "raidwarning" },
            -- Hard-enrage countdown from pull (one-shot bar, modeled like KT phase2).
            { id = "hardberserk", name = "Berserk (7 min)", icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",
              trigger = { type = "timer" }, barColor = RED,
              mode = "cooldown", style = "bar", cooldown = 420, firstCast = 420, noLoop = true, -- DBM 420
              winWarning = true, winSound = true, warningText = "Patchwerk Berserk!", sound = "raidwarning" },
        }},
        { id = "grobbulus", name = "Grobbulus", npcIDs = { 15931 }, mechanics = {
            -- Personal 10s run-out countdown when YOU get the injection (DBM target timer 10s).
            { id = "injection", name = "Mutating Injection (on you)", icon = "Interface\\Icons\\Spell_Nature_NullifyPoison",
              trigger = { type = "aura", spellID = 28169, onPlayer = true }, barColor = GREEN,
              style = "icon", barDuration = 10,
              warningText = "Mutating Injection on YOU — move out!", sound = "raidwarning",
              special = true },  -- personal: walk out NOW or drop a cloud in melee — act-now tier
            { id = "cloud", name = "Poison Cloud", icon = "Interface\\Icons\\Spell_Nature_Acid_01",
              trigger = { type = "cast", spellID = 28240, npcID = 15931 }, barColor = GREEN,
              mode = "cooldown", style = "icon", cooldown = 14.5 }, -- DBM 14.5 consistently
            { id = "slimespray", name = "Slime Spray", icon = "Interface\\Icons\\Ability_Creature_Poison_02",
              trigger = { type = "cast", spellID = 28157, npcID = 15931 }, barColor = GREEN, default = false },
            -- Hard-enrage countdown from pull (one-shot bar, modeled like KT phase2).
            { id = "berserk", name = "Berserk (12 min)", icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",
              trigger = { type = "timer" }, barColor = RED,
              mode = "cooldown", style = "bar", cooldown = 720, firstCast = 720, noLoop = true, -- DBM 720
              winWarning = true, winSound = true, warningText = "Grobbulus Berserk!", sound = "raidwarning" },
        }},
        { id = "gluth", name = "Gluth", npcIDs = { 15932 }, mechanics = {
            { id = "decimate", name = "Decimate", icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
              trigger = { type = "cast", spellID = 28375, npcID = 15932 }, barColor = RED, -- UNVERIFIED on Anniversary: no trace in 485-pull log review 2026-07-26; confirm in-game
              warning = true, warningText = "Decimate!", sound = "raidwarning" },
            { id = "mortalwound", name = "Mortal Wound", icon = "Interface\\Icons\\Ability_Criticalstrike",
              trigger = { type = "cast", spellID = 25646, npcID = 15932 }, barColor = ORANGE }, -- log-verified 2026-07-26: 39 casts of 25646, zero of old 28467
            { id = "frenzy", name = "Frenzy", icon = "Interface\\Icons\\Ability_Druid_Berserk",
              trigger = { type = "cast", spellID = 28371, npcID = 15932 }, barColor = RED,
              mode = "cooldown", style = "icon", cooldown = 8, -- DBM v8.1-11.4 (tranq target)
              warningText = "Gluth Frenzy — tranq!", sound = "raidwarning" },
            { id = "roar", name = "Terrifying Roar", icon = "Interface\\Icons\\Spell_Shadow_DeathScream",
              trigger = { type = "cast", spellID = 29685, npcID = 15932 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 18, winWarning = true, winSound = true, -- DBM v17.8-24.2
              warningText = "Terrifying Roar (Fear) soon!", sound = "raidwarning" },
            -- Hard-enrage countdown from pull (one-shot bar, modeled like KT phase2).
            { id = "berserk", name = "Berserk (7 min)", icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",
              trigger = { type = "timer" }, barColor = RED,
              mode = "cooldown", style = "bar", cooldown = 420, firstCast = 420, noLoop = true, -- DBM 420
              winWarning = true, winSound = true, warningText = "Gluth Berserk!", sound = "raidwarning" },
        }},
        -- npcIDs include Stalagg (15929) + Feugen (15930) so the fight engages during the
        -- add phase (the Mini-Boss Health module + Thaddius timers come online then).
        { id = "thaddius", name = "Thaddius", npcIDs = { 15928, 15929, 15930 }, mechanics = {
            -- polarityWatch enables the "Polarity change" sub-alert (see thaddius.lua).
            { id = "polarity", name = "Polarity Shift", icon = "Interface\\Icons\\Spell_Nature_Lightning",
              trigger = { type = "aura", spellID = 28089, onPlayer = true }, barColor = YELLOW,
              style = "flash", warningText = "Polarity Shift — check your charge!", sound = "raidwarning",
              special = true,  -- wipe mechanic: wrong charge kills the raid — act-now tier
              polarityWatch = true },
            { id = "balllightning", name = "Ball Lightning", icon = "Interface\\Icons\\Spell_Nature_LightningShield",
              trigger = { type = "cast", spellID = 28299, npcID = 15928 }, barColor = BLUE }, -- log-verified 2026-07-26: 28299; old 28338 is actually Stalagg's Magnetic Pull on this server
            -- Add-phase tank-swap pull (Stalagg 28338 / Feugen 28339, no npcID gate so either
            -- variant resyncs). log-verified 2026-07-26: 34 casts, interval 21.0-21.1s.
            { id = "magneticpull", name = "Magnetic Pull", icon = "Interface\\Icons\\Spell_Nature_EarthBind",
              trigger = { type = "cast", spellIDs = { 28338, 28339 } }, barColor = YELLOW,
              mode = "cooldown", style = "icon", cooldown = 21, glowThreshold = 3,
              winWarning = true, warningText = "Magnetic Pull!", sound = "ding" },
            -- Stalagg damage buff during the add phase. log-verified 2026-07-26: 16 casts, ~27.5s apart.
            { id = "powersurge", name = "Power Surge", icon = "Interface\\Icons\\Spell_Lightning_LightningBolt01",
              trigger = { type = "cast", spellID = 28134 }, barColor = RED,
              warning = true, warningText = "Power Surge — Stalagg damage up!", sound = "ding" },
            -- Quiet healer-info radial (no window warning/sound); off by default — casts too
            -- often to alert on. log-verified 2026-07-26: 90 casts, ~8.5s avg.
            { id = "chainlightning", name = "Chain Lightning", icon = "Interface\\Icons\\Spell_Nature_ChainLightning",
              trigger = { type = "cast", spellID = 28167, npcID = 15928 }, barColor = BLUE,
              mode = "cooldown", style = "icon", cooldown = 8.5, default = false },
            -- Hard-enrage countdown from pull (one-shot bar, modeled like KT phase2).
            { id = "berserk", name = "Berserk (5 min)", icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",
              trigger = { type = "timer" }, barColor = RED,
              mode = "cooldown", style = "bar", cooldown = 300, firstCast = 300, noLoop = true, -- DBM 300
              winWarning = true, winSound = true, warningText = "Thaddius Berserk!", sound = "raidwarning" },
        }},

        -- ── Military Quarter ──────────────────────────────────────────────────
        { id = "razuvious", name = "Instructor Razuvious", npcIDs = { 16061 }, mechanics = {
            { id = "unbalancing", name = "Unbalancing Strike", icon = "Interface\\Icons\\Ability_Warrior_Disarm",
              trigger = { type = "cast", spellID = 26613, npcID = 16061 }, barColor = ORANGE, -- log-verified 2026-07-26: 147 casts of 26613, zero of old 28491
              warning = true, warningText = "Unbalancing Strike — tank swap!", sound = "raidwarning" },
            { id = "shout", name = "Disrupting Shout", icon = "Interface\\Icons\\Spell_Shadow_Teleport",
              trigger = { type = "cast", spellID = 29107, npcID = 16061 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 26, firstCast = 26 }, -- DBM CD 25.9 from pull
            -- Understudy mind-control taunt (cast 29060 by a controlled Understudy). Cooldown
            -- mechanic so the FIRST taunt registers in-engine (the old module missed the
            -- engaging event). No npcID gate: matches the pet/MC source.
            { id = "taunt", name = "Understudy Taunt", icon = "Interface\\Icons\\Spell_Nature_Reincarnation",
              trigger = { type = "cast", spellID = 29060 }, barColor = ORANGE,
              mode = "cooldown", style = "icon", cooldown = 60, glowThreshold = 5,
              winWarning = true, winSound = true, warningText = "Taunt ready — swap MC!", sound = "raidwarning",
              countdownVoice = true },  -- MC swap timing is exact (60s cycle)
        }},
        { id = "gothik", name = "Gothik the Harvester", npcIDs = { 16060 }, mechanics = {
            -- log-verified 2026-07-26: 29317 (old 27831 never logged); 184 casts at ~1.5-1.7s
            -- intervals — a fast repeated P2 nuke on this server, not an occasional volley.
            -- Off by default: casts every ~1.7s in P2 and would spam bars.
            { id = "shadowbolt", name = "Shadow Bolt", icon = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
              trigger = { type = "cast", spellID = 29317, npcID = 16060 }, barColor = PURPLE, default = false },
            { id = "harvest", name = "Harvest Soul", icon = "Interface\\Icons\\Spell_Shadow_SoulGem",
              trigger = { type = "cast", spellID = 28679, npcID = 16060 }, barColor = PURPLE },
        }},
        { id = "fourhorsemen", name = "The Four Horsemen",
          npcIDs = { 16062, 16063, 16064, 16065 }, mechanics = {
            -- Per-horse abilities (Meteor / Void Zone / Holy Wrath) and the per-player
            -- Mark stacks now live INSIDE the "* Horsemen Tracker" module (inline cooldowns
            -- + live target/stacks). Only the global Mark cadence remains as a mechanic here.
            { id = "markcd", name = "Mark CD", icon = "Interface\\Icons\\Spell_Shadow_AntiMagicShell",
              trigger = { type = "cast", spellIDs = { 28832, 28833, 28834, 28835 } }, barColor = ORANGE,
              mode = "cooldown", style = "icon", cooldown = 13, firstCast = 21, showCount = true }, -- DBM 21 then 12.9-13
        }},

        -- ── Frostwyrm Lair ────────────────────────────────────────────────────
        { id = "sapphiron", name = "Sapphiron", npcIDs = { 15989 }, mechanics = {
            { id = "lifedrain", name = "Life Drain", icon = "Interface\\Icons\\Spell_Shadow_LifeDrain",
              trigger = { type = "cast", spellID = 28542, npcID = 15989 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 21 }, -- DBM v21.1-27.5
            -- Normal boss-cast mechanic (Ability Tracker + On Cast Notification). The "Personal
            -- Damage Warning" sub-section fires separately when the blizzard actually deals damage to YOU.
            { id = "blizzard", name = "Blizzard", icon = "Interface\\Icons\\Spell_Frost_IceStorm",
              trigger = { type = "cast", spellID = 28560, npcID = 15989 }, barColor = BLUE }, -- log-verified 2026-07-26: 59 casts of 28560 ("Summon Blizzard"), zero of old 28547
            -- Icebolt 28522 only ever appears as SPELL_AURA_APPLIED on players, never as a boss
            -- cast (aura source matching differs) — log-verified 2026-07-26. First Icebolt =
            -- air phase active; the bar counts down to Sapphiron landing. -- DBM "Landing" 28.5
            { id = "iceblock", name = "Air Phase / Ice Bolt", icon = "Interface\\Icons\\Spell_Frost_FrostBolt02",
              trigger = { type = "aura", spellID = 28522 }, barColor = BLUE, barDuration = 28.5,
              warning = true, warningText = "Ice Bolt — get behind a block!", sound = "raidwarning",
              special = true },  -- air phase: get behind a block or die — act-now tier
            -- Countdown to the NEXT air phase; resyncs on the first Icebolt of each air phase.
            -- DBM ground phase 54.3s; first liftoff ~55s (Icebolts observed ~53s from pull).
            { id = "airphase", name = "Air Phase (next)", icon = "Interface\\Icons\\Spell_Frost_Wisp",
              trigger = { type = "aura", spellID = 28522 }, barColor = BLUE,
              mode = "cooldown", style = "icon", cooldown = 54.3, firstCast = 55, glowThreshold = 5,
              winWarning = true, winSound = true, warningText = "Air phase soon!", sound = "raidwarning",
              countdownVoice = true },  -- pre-spread before liftoff (54.3s cycle)
            -- 7s cast that ends the air phase -> show it as a cast bar (no CD reset after).
            { id = "frostbreath", name = "Frost Breath", icon = "Interface\\Icons\\Spell_Frost_FrostNova",
              trigger = { type = "cast", spellID = 28524, npcID = 15989, onStart = true }, barColor = BLUE,
              style = "castbar", castTime = 7, warningText = "Frost Breath — air phase ending!", sound = "raidwarning" },
            -- Hard-enrage countdown from pull (one-shot bar, modeled like KT phase2).
            { id = "berserk", name = "Berserk (15 min)", icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",
              trigger = { type = "timer" }, barColor = RED,
              mode = "cooldown", style = "bar", cooldown = 900, firstCast = 900, noLoop = true, -- DBM 900
              winWarning = true, winSound = true, warningText = "Sapphiron Berserk!", sound = "raidwarning" },
        }},
        -- Kel'Thuzad: the abilities are COOLDOWN-mode icons. Each shows a radial countdown
        -- to when its window opens; at zero the icon border glows; when KT actually casts it
        -- (combat-log detect) the cycle resets and counts down again. cooldowns are
        -- PLACEHOLDER vanilla estimates — tune via /drm debug or the per-mechanic editor.
        { id = "kelthuzad", name = "Kel'Thuzad", npcIDs = { 15990 }, mechanics = {
            -- Phase 1 -> Phase 2 countdown: a one-shot bar from pull to when KT becomes
            -- active (~230s; DBM v229.2-242.8). noLoop = fires the warning once at 0 and clears.
            -- Its trigger never matches in P1, so it just counts the firstCast down.
            { id = "phase2", name = "Phase 2 (KT active)", icon = "Interface\\Icons\\Spell_Frost_Wisp",
              trigger = { type = "timer" }, barColor = BLUE,
              mode = "cooldown", style = "bar", cooldown = 230, firstCast = 230, noLoop = true,
              winWarning = true, winSound = true, warningText = "Kel'Thuzad is active — Phase 2!", sound = "raidwarning" },
            -- Cooldowns are the MINIMUM recast (low end of DBM's NewVarTimer range),
            -- i.e. the earliest the ability can go again -> "0 = castable now".
            { id = "frostblast", name = "Frost Blast", icon = "Interface\\Icons\\Spell_Frost_Glacier",
              trigger = { type = "cast", spellID = 27808, npcID = 15990 }, barColor = BLUE,
              mode = "cooldown", style = "icon", cooldown = 34, firstCast = 30, winWarning = true, winSound = true, -- DBM first 30.3, then 33.5-75.3
              warningText = "Frost Blast window!", sound = "raidwarning" },
            { id = "fissure", name = "Shadow Fissure", icon = "Interface\\Icons\\Spell_Shadow_ShadowfuryUnused",
              trigger = { type = "cast", spellID = 27810, npcID = 15990 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 11, winWarning = true, -- DBM v10.9-42.1
              warningText = "Shadow Fissure window!", sound = "ding" },
            { id = "detonate", name = "Detonate Mana", icon = "Interface\\Icons\\Spell_Arcane_ManaTap",
              trigger = { type = "cast", spellID = 27819, npcID = 15990 }, barColor = BLUE,
              mode = "cooldown", style = "icon", cooldown = 20 }, -- DBM v20.2-50.9
            -- Log shows KT casting 28408 for Chains while DBM's timer keys off 28410 —
            -- accept both so either resyncs the cycle. log-verified 2026-07-26.
            { id = "chains", name = "Chains of Kel'Thuzad", icon = "Interface\\Icons\\Spell_Shadow_DeathCoil",
              trigger = { type = "cast", spellIDs = { 28408, 28410 }, npcID = 15990 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 63, firstCast = 22, winWarning = true, winSound = true, -- DBM first 21.8 after P2, then 63.1-145.4
              warningText = "Mind Control window!", sound = "raidwarning" },
            -- KT's constant P2 nuke — quiet radial, no window warning/sound.
            { id = "frostbolt", name = "Frostbolt", icon = "Interface\\Icons\\Spell_Frost_FrostBolt",
              trigger = { type = "cast", spellID = 28479, npcID = 15990 }, barColor = BLUE,
              mode = "cooldown", style = "icon", cooldown = 15.5, default = true }, -- DBM 15.3/15.7; log 56 casts 2026-07-26
            { id = "guardians", name = "Guardians (Phase 2)", icon = "Interface\\Icons\\Spell_Shadow_SummonImp",
              trigger = { type = "yell", text = "Minions, servants" }, barColor = RED,
              style = "flash", warningText = "Guardians incoming!", sound = "raidwarning" },
        }},
    },
})
