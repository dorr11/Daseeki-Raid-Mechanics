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
              mode = "cooldown", style = "icon", cooldown = 81, winWarning = true, winSound = true, -- DBM v81.3-104.5
              warningText = "Locust Swarm soon!", sound = "raidwarning" },
        }},
        { id = "faerlina", name = "Grand Widow Faerlina", npcIDs = { 15953 }, mechanics = {
            -- Normal boss-cast mechanic (Ability Tracker + On Cast Notification, like any other).
            -- The "Personal Damage Warning" sub-section (independent of this trigger type) fires
            -- separately whenever the same spellID actually deals damage to YOU — i.e. you're
            -- standing in the resulting ground effect.
            { id = "rainoffire", name = "Rain of Fire", icon = "Interface\\Icons\\Spell_Shadow_RainOfFire",
              trigger = { type = "cast", spellID = 28794, npcID = 15953 }, barColor = ORANGE },
            { id = "poisonbolt", name = "Poison Bolt Volley", icon = "Interface\\Icons\\Spell_Nature_CorrosiveBreath",
              trigger = { type = "cast", spellID = 28796, npcID = 15953 }, barColor = GREEN },
            { id = "frenzy", name = "Frenzy", icon = "Interface\\Icons\\Ability_Druid_Berserk",
              trigger = { type = "aura", spellID = 28798 }, barColor = RED,
              warning = true, warningText = "Faerlina Frenzy — sacrifice!", sound = "raidwarning" },
        }},
        { id = "maexxna", name = "Maexxna", npcIDs = { 15952 }, mechanics = {
            -- Web Spray = a cooldown radial counting to the next spray (DBM 40.5s, predicted
            -- from pull via firstCast).
            { id = "webspray", name = "Web Spray", icon = "Interface\\Icons\\Ability_Ensnare",
              trigger = { type = "cast", spellID = 29484, npcID = 15952 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 40, firstCast = 40, glowThreshold = 5,
              winWarning = true, winSound = true, warningText = "Web Spray soon!", sound = "raidwarning" },
            -- Web Wrap = cooldown radial (DBM v39.6-40.9). Its `reminder` is the optional
            -- SNOWBALL warning — a separate radial that fires `leadTime`s before each wrap,
            -- with its own icon/scale/opacity/glow/sound/position (configured in Web Wrap's
            -- settings, not Web Spray's).
            { id = "webwrap", name = "Web Wrap", icon = "Interface\\Icons\\Spell_Nature_StrangleVines",
              trigger = { type = "cast", spellID = 28622, npcID = 15952 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 40,
              reminder = { name = "Snowball", icon = "Interface\\Icons\\Spell_Frost_FrostBolt02",
                           style = "icon", leadTime = 5, barDuration = 5, glowThreshold = 5,
                           sound = "raidwarning", barColor = BLUE, default = false } },
            { id = "necrotic", name = "Necrotic Poison", icon = "Interface\\Icons\\Ability_Creature_Poison_03",
              trigger = { type = "cast", spellID = 28776, npcID = 15952 }, barColor = GREEN },
            { id = "frenzy", name = "Frenzy (30%)", icon = "Interface\\Icons\\Ability_Druid_Berserk",
              trigger = { type = "health", pct = 30 }, barColor = RED,
              warning = true, warningText = "Maexxna Frenzy!", sound = "raidwarning" },
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
              trigger = { type = "cast", spellID = 29208, npcID = 15954 }, barColor = BLUE },
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
            { id = "necroticaura", name = "Necrotic Aura (heal window)", icon = "Interface\\Icons\\Spell_Shadow_AntiShadow",
              trigger = { type = "aura", spellID = 29232, onRemove = true }, barColor = GREEN,
              barDuration = 3, warning = true, warningText = "Heal window OPEN!", sound = "raidwarning" },
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
            { id = "deathbloom", name = "Deathbloom", icon = "Interface\\Icons\\Spell_Nature_NatureTouchDecay",
              trigger = { type = "aura", spellID = 29865, onPlayer = true }, barColor = PURPLE },
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
              trigger = { type = "cast", spellID = 28308, npcID = 16028 }, barColor = RED, barDuration = 1.2 },
            { id = "berserk", name = "Enrage (5%)", icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",
              trigger = { type = "health", pct = 5 }, barColor = RED,
              warning = true, warningText = "Patchwerk Enrage — burn!", sound = "raidwarning" },
        }},
        { id = "grobbulus", name = "Grobbulus", npcIDs = { 15931 }, mechanics = {
            -- Personal 10s run-out countdown when YOU get the injection (DBM target timer 10s).
            { id = "injection", name = "Mutating Injection (on you)", icon = "Interface\\Icons\\Spell_Nature_NullifyPoison",
              trigger = { type = "aura", spellID = 28169, onPlayer = true }, barColor = GREEN,
              style = "icon", barDuration = 10,
              warningText = "Mutating Injection on YOU — move out!", sound = "raidwarning" },
            { id = "cloud", name = "Poison Cloud", icon = "Interface\\Icons\\Spell_Nature_Acid_01",
              trigger = { type = "cast", spellID = 28240, npcID = 15931 }, barColor = GREEN,
              mode = "cooldown", style = "icon", cooldown = 14 }, -- DBM v14.5-16.6
            { id = "slimespray", name = "Slime Spray", icon = "Interface\\Icons\\Ability_Creature_Poison_02",
              trigger = { type = "cast", spellID = 28157, npcID = 15931 }, barColor = GREEN, default = false },
        }},
        { id = "gluth", name = "Gluth", npcIDs = { 15932 }, mechanics = {
            { id = "decimate", name = "Decimate", icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
              trigger = { type = "cast", spellID = 28375, npcID = 15932 }, barColor = RED,
              warning = true, warningText = "Decimate!", sound = "raidwarning" },
            { id = "mortalwound", name = "Mortal Wound", icon = "Interface\\Icons\\Ability_Criticalstrike",
              trigger = { type = "cast", spellID = 28467, npcID = 15932 }, barColor = ORANGE },
            { id = "frenzy", name = "Frenzy", icon = "Interface\\Icons\\Ability_Druid_Berserk",
              trigger = { type = "cast", spellID = 28371, npcID = 15932 }, barColor = RED,
              mode = "cooldown", style = "icon", cooldown = 8, -- DBM v8.1-11.4 (tranq target)
              warningText = "Gluth Frenzy — tranq!", sound = "raidwarning" },
            { id = "roar", name = "Terrifying Roar", icon = "Interface\\Icons\\Spell_Shadow_DeathScream",
              trigger = { type = "cast", spellID = 29685, npcID = 15932 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 18, winWarning = true, winSound = true, -- DBM v17.8-24.2
              warningText = "Terrifying Roar (Fear) soon!", sound = "raidwarning" },
        }},
        -- npcIDs include Stalagg (15929) + Feugen (15930) so the fight engages during the
        -- add phase (the Mini-Boss Health module + Thaddius timers come online then).
        { id = "thaddius", name = "Thaddius", npcIDs = { 15928, 15929, 15930 }, mechanics = {
            -- polarityWatch enables the "Polarity change" sub-alert (see thaddius.lua).
            { id = "polarity", name = "Polarity Shift", icon = "Interface\\Icons\\Spell_Nature_Lightning",
              trigger = { type = "aura", spellID = 28089, onPlayer = true }, barColor = YELLOW,
              style = "flash", warningText = "Polarity Shift — check your charge!", sound = "raidwarning",
              polarityWatch = true },
            { id = "balllightning", name = "Ball Lightning", icon = "Interface\\Icons\\Spell_Nature_LightningShield",
              trigger = { type = "cast", spellID = 28338, npcID = 15928 }, barColor = BLUE }, -- DBM "Throw" timer id 28338
        }},

        -- ── Military Quarter ──────────────────────────────────────────────────
        { id = "razuvious", name = "Instructor Razuvious", npcIDs = { 16061 }, mechanics = {
            { id = "unbalancing", name = "Unbalancing Strike", icon = "Interface\\Icons\\Ability_Warrior_Disarm",
              trigger = { type = "cast", spellID = 28491, npcID = 16061 }, barColor = ORANGE,
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
              winWarning = true, winSound = true, warningText = "Taunt ready — swap MC!", sound = "raidwarning" },
        }},
        { id = "gothik", name = "Gothik the Harvester", npcIDs = { 16060 }, mechanics = {
            { id = "shadowbolt", name = "Shadow Bolt Volley", icon = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
              trigger = { type = "cast", spellID = 27831, npcID = 16060 }, barColor = PURPLE },
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
            -- Damage Warning" sub-section fires separately when 28547 actually deals damage to YOU.
            { id = "blizzard", name = "Blizzard", icon = "Interface\\Icons\\Spell_Frost_IceStorm",
              trigger = { type = "cast", spellID = 28547, npcID = 15989 }, barColor = BLUE },
            { id = "iceblock", name = "Air Phase / Ice Bolt", icon = "Interface\\Icons\\Spell_Frost_FrostBolt02",
              trigger = { type = "cast", spellID = 28522, npcID = 15989 }, barColor = BLUE,
              warning = true, warningText = "Ice Bolt — get behind a block!", sound = "raidwarning" },
            -- 7s cast that ends the air phase -> show it as a cast bar (no CD reset after).
            { id = "frostbreath", name = "Frost Breath", icon = "Interface\\Icons\\Spell_Frost_FrostNova",
              trigger = { type = "cast", spellID = 28524, npcID = 15989, onStart = true }, barColor = BLUE,
              style = "castbar", castTime = 7, warningText = "Frost Breath — air phase ending!", sound = "raidwarning" },
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
              mode = "cooldown", style = "icon", cooldown = 34, winWarning = true, winSound = true, -- DBM v33.5-75.3
              warningText = "Frost Blast window!", sound = "raidwarning" },
            { id = "fissure", name = "Shadow Fissure", icon = "Interface\\Icons\\Spell_Shadow_ShadowfuryUnused",
              trigger = { type = "cast", spellID = 27810, npcID = 15990 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 11, winWarning = true, -- DBM v10.9-42.1
              warningText = "Shadow Fissure window!", sound = "ding" },
            { id = "detonate", name = "Detonate Mana", icon = "Interface\\Icons\\Spell_Arcane_ManaTap",
              trigger = { type = "cast", spellID = 27819, npcID = 15990 }, barColor = BLUE,
              mode = "cooldown", style = "icon", cooldown = 20 }, -- DBM v20.2-50.9
            { id = "chains", name = "Chains of Kel'Thuzad", icon = "Interface\\Icons\\Spell_Shadow_DeathCoil",
              trigger = { type = "cast", spellID = 28410, npcID = 15990 }, barColor = PURPLE,
              mode = "cooldown", style = "icon", cooldown = 63, winWarning = true, winSound = true, -- DBM v63.1-145.4
              warningText = "Mind Control window!", sound = "raidwarning" },
            { id = "guardians", name = "Guardians (Phase 2)", icon = "Interface\\Icons\\Spell_Shadow_SummonImp",
              trigger = { type = "yell", text = "Minions, servants" }, barColor = RED,
              style = "flash", warningText = "Guardians incoming!", sound = "raidwarning" },
        }},
    },
})
