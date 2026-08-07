# Changelog

## Unreleased — 2.0.0 rebuild, wave 4a (Molten Core + Onyxia + world bosses — internal)
- **The last three zones are in, and that finishes every raid.** Molten Core's ten
  bosses plus a zone-wide trash module, Onyxia, and all six world bosses — Azuregos,
  Lord Kazzak and the four Dragons of Nightmare. With this wave the addon covers all
  **65 encounters** across eight zones, which is every fight in the reference set.
- **Ragnaros has his whole submerge cycle.** The submerge is spotted two ways — his
  "COME FORTH, MY SERVANTS" yell and the submerge animation itself — and either one
  stops his Wrath bar and starts the 90-second emerge clock. The eight Sons of Flame are
  counted as they die (a corpse can't be counted twice), and killing the last one brings
  him back up **immediately** rather than waiting out the clock. His post-emerge Wrath
  timing is genuinely different from his opening timing, and the bar now says so.
- **The Ragnaros walk-in has a countdown.** Majordomo dying starts a 73-second bar so
  the raid knows exactly when Ragnaros becomes attackable, instead of standing there
  guessing.
- **Onyxia's Deep Breath is called every time.** This client fires a different Deep
  Breath spell depending on which perch she flew to, so the alert listens for all eight
  of them and still only shouts once. Her three phases come off her own yells, and you
  get "phase 2 soon" at 70% and "phase 3 soon" at 45% — the pre-warning only, without a
  false phase-change announce in front of it.
- **Molten Core trash gets eleven per-mob bars.** A Molten Giant's Knock Away, a
  Firelord's Lava Spawn, a Flameguard's Cone of Fire and eight more, each one attached
  to *that* mob's nameplate — so two giants are two bars, and a giant dying takes only
  its own bar with it. A pack of six identical mobs still produces one warning, not six.
- **World bosses behave like world bosses.** Dying at one is not a wipe, the addon waits
  15 seconds before calling one, and an open-world pull starts everybody's timers
  together. Kazzak's berserk bar only starts when the pull was actually heard — a random
  outdoor aggro pull can happen minutes before anyone notices, and a bar seeded from
  that moment would be worse than none. Azuregos deliberately has **no** bars at all:
  every one of his abilities was measured and every window was too wide to show
  honestly.
- **Three long-standing bugs fixed along the way.** Deaths in the combat log were never
  reaching kill detection, which meant Razorgore (the one fight that has to work this
  out for itself) could never register a kill. A whole class of boss cast — the ones
  this client leaves out of the combat log entirely — was never being listened for, so
  Maexxna's spiderlings, Sapphiron's air phase, Viscidus, Venoxis and Arlokk were all
  quietly missing a trigger. And the pull countdown was capped at 60 seconds, which is
  shorter than Ragnaros's own walk-in.
- Golemagg still has exactly one alert and Onyxia still has no whelp timer, because
  that is genuinely all the reference has for them. Nothing has been invented to fill a
  gap.

## Unreleased — 2.0.0 rebuild, Ahn'Qiraj data arbitrations (internal)
- **Two Temple bars are back that the rebuild had no numbers for.** Battleguard
  Sartura's Whirlwind now has a cooldown bar again: the reference data says nobody ever
  timed it, but our own logs did — 26 to 29 seconds — so the bar shows that range rather
  than a made-up exact number. Fankriss gets a "next Mortal Wound" bar on its measured 6
  to 10 second cadence, alongside (not instead of) the 20-second bar showing how long
  the debuff on the tank has left.
- **Thirteen Temple alerts the rebuild had dropped are back.** Skeram's Earth Shock;
  the Bug Trio's Cleave, Thrash, Ravage, Knock Away, Knockdown and Berserker Charge,
  plus the two that matter most — the poison cloud when Kri dies and the Vengeance
  enrage when Vem does; Sartura's Sundering Cleave; Viscidus's Poison Shock; and the
  Twin Emperors' Arcane Burst and Heal Brother. Each one is a toggle under its boss,
  stored under **exactly the key it used before the rebuild**, so if you had one of
  these switched off it is still switched off.
- The two "a bug just died and the fight changed" alerts come back LOUD. The melee
  chatter — cleaves, thrashes, knockdowns and the Twins' positioning spam — comes back
  switched OFF, the same way it shipped before: it fires often enough that the reference
  authors dropped it entirely, so having the toggle there and unticked is the honest
  middle. Turn any of them on and it works. The ones that repeat several times a second
  are throttled rather than repeated once per cast.
- Vem's three restored bars stop the moment Vem dies, like the trio's other bars.
  Sartura's new bar ignores her Royal Guards' whirlwinds and the whirlwind's own damage
  ticks, and Fankriss's ignores every other boss that shares the Mortal Wound spell — so
  none of them can be restarted by the wrong thing.

## Unreleased — 2.0.0 rebuild, Naxxramas data arbitrations (internal)
- **Three Naxx alerts now fire on either spell id.** When the rebuild was cross-checked
  against our own Anniversary combat logs, three mechanics turned out to use a different
  spell id here than the reference data says. Rather than pick a side, all three now
  listen for both: Faerlina's Enrage (the raid warning AND the "use a defensive" call to
  whoever is tanking her), Sapphiron's "get out of the Blizzard", and Noth's Blink, which
  on this server uses four different ids where the reference had one. If the server ever
  changes its mind, the alerts keep working either way.
- **Thirteen alerts that the rebuild had dropped are back.** Razuvious's Unbalancing
  Strike tank-swap call and Gluth's Mortal Wound stack count, Thaddius's Power Surge,
  Ball Lightning and Chain Lightning, Gothik's Shadow Bolt and Harvest Soul, Heigan's
  Decrepit Fever and Spell Disruption, Maexxna's Necrotic Poison, Faerlina's Poison Bolt
  Volley, Grobbulus's Slime Spray and Loatheb's Poison Aura. Each one is a toggle under
  its boss, stored under **exactly the key it used before the rebuild**, so if you had
  one of these switched off it is still switched off.
- The tank-swap calls come back LOUD, to tanks and healers. The poison-type alerts come
  back switched OFF: they fire often enough that the reference authors dropped them
  entirely, so having the toggle there and unticked is the honest middle — turn any of
  them on and it works. Two of the restored alerts (Gothik's Shadow Bolt and Thaddius's
  Ball Lightning) fire several times a second in the real fight, so they are throttled
  rather than repeated once per cast.
## Unreleased — 2.0.0 rebuild, wave 4b (Blackwing Lair + Zul'Gurub — internal)
- **Blackwing Lair and Zul'Gurub are in.** All eight BWL bosses plus a zone-wide trash
  module, and all ten Zul'Gurub bosses. Zul'Gurub had never shipped at all; Blackwing
  Lair had a handful of bars per boss and now carries the full set — every timer, every
  warning, the audience each one defaults on for, the phase rules, and the Era-specific
  detection each fight needs.
- **Chromaggus finally knows which school he is vulnerable to.** The bar changes colour,
  icon and NAME to the current school the moment anything proves what it is, without
  restarting — so the time left on it stays honest. It reads that from three completely
  independent places, because on this client the vulnerability is only in the combat log
  while somebody is holding Detect Magic on him: the combat-log event, a direct read of
  his own buffs (which works with nobody dispelling anything), and the "skin shimmers"
  emote, which proves the school just changed even when nothing can say to what. And the
  rule that matters most: **not being able to see a school never clears one.** A read
  that comes back empty changes nothing at all.
- The rest of Chromaggus is complete too. Both pull breath bars are labelled separately
  and each is closed by hand when its breath actually lands, instead of counting into a
  window forever. Each breath then gets its OWN 61.5-second bar, named for itself, so two
  breaths mean two clocks. "Breath soon" is called before every one of them. Your own
  brood afflictions are counted up AND back down, and you are told the moment you are
  carrying three of the five.
- **Nefarian's phases work with nothing to work with.** There is no combat-log event and
  no yell for phase 1 ending on this client, so the mod watches whether the game itself
  still thinks an encounter is running: it stops while the drakonid waves finish, and
  starts again as he lands. The drakonid counter runs 42 down to 0, de-duplicated so a
  corpse cannot be counted twice. All nine class calls announce to the raid, shout at you
  personally if it is your class, and put a 30-second bar up named for the class that was
  called — and the Shaman call shouts at everybody, because the totems are everybody's
  problem.
- Razorgore's egg count is announced for every single egg, and **the fight now knows the
  difference between a kill and a wipe.** Dying in phase 1 means somebody dropped the orb;
  only dying in phase 2 counts as a kill, and the game's own (wrong) verdict is ignored.
- Vaelastrasz counts you in: hearing "Too late, friends!" starts a 43.5-second pull
  countdown so the raid knows exactly how long the speech has left. Burning Adrenaline
  puts a bar on each victim, shouts at you when it is you, and calls you out five seconds
  before it kills you — and that call is cancelled the instant the debuff comes off.
- Ebonroc, Flamegor, Firemaw, Broodlord and the BWL trash all behave: Wing Buffet and
  Shadow Flame cooldowns with correct first-cast windows, Flame Buffet counted from four
  stacks upward, per-Seether Flamestrike bars, and a "get out of the fire" alert.
- **Hakkar's hard mode is detected.** There is no difficulty setting for it anywhere — the
  only difference is that he has more health — so the mod reads his maximum health off
  whoever can see him, and above 1,079,325 it arms all five Aspect timers. A fight it
  cannot prove is hard runs as a normal fight, which is the safe way to be wrong.
- Mandokir's gaze is read from his **yell**, not the combat log, because the yell arrives
  a full two seconds earlier — and two seconds is the whole mechanic. Arlokk's vanish has
  no event at all on this client, so her return is worked out from the first time she
  swings at somebody. Venoxis, Jeklik, Mar'li, Thekal, Jin'do and Gahz'ranka are all in,
  with resurrection windows, interrupt calls, dispel calls and totem-switch calls.
- **The Edge of Madness bosses ship switched off, on purpose.** Their spell IDs are flagged
  as unverified in the source material we built from, and an alert keyed to an ID nobody
  has confirmed is worse than no alert: it teaches a raid to trust a bar that may never
  fire. Every row is there and every row is off, ready to be switched on by anyone helping
  verify them.
- Both new options sections are real: every bar and every warning is its own toggle under
  its boss. **Blackwing Lair settings carry over** — where the old data and the new spec
  agree on a mechanic, the setting is stored under the same key it always was.
- Internal: the encounter grammar gained seven more general primitives — dynamic bar
  identity (restyle rows), per-event-field bar identity, the encounter-in-progress poll,
  a unit-fact sweep for auras and maximum health, numeric field tests, a kill-stage gate,
  and RP-driven pull countdowns — plus row suppression and a "this call is for your class"
  predicate. `data_bwl.lua`, the last parked 1.x data file, was diffed against the spec
  and then deleted; the spec won every disagreement, one log-verified mechanic the spec
  lacks entirely was carried over switched off, and everything is listed in the wave
  report.

## Unreleased — 2.0.0 rebuild, wave 4c (Ruins + Temple of Ahn'Qiraj — internal)
- **Both Ahn'Qiraj raids are in.** All six Ruins bosses and all nine Temple bosses now
  run on the new engine, plus a zone-wide trash module for each instance. The Ruins had
  never shipped at all; the Temple had a handful of bars per boss and now carries the
  full set — every timer, every warning, the audience each one defaults on for, the
  phase rules and the Era-specific detection each fight needs.
- **C'Thun is complete.** Both phases, all four tentacle spawn timers, and the fact that
  each of them counts differently in phase 1, at the moment phase 2 begins, and again
  after a Weakened. The eye's death flips the phase, stops Dark Glare and the Claw
  Tentacles for good, and re-seeds the rest; the Weakened emote re-seeds them again and
  calls the burn. Eye Beam runs the boss-target scan, marks the victim with a raid icon,
  and shouts at you personally when it is you.
- The C'Thun **stomach list** is built: everyone the stomach has eaten, with their acid
  stacks, and — the part nothing else can do — each Flesh Tentacle's health, read
  through the eyes of the players who were swallowed, because the tentacles cannot be
  seen from outside the stomach at all. A dead tentacle is held on the list for half a
  minute rather than silently vanishing, and a Weakened clears the whole thing.
- **Viscidus's freeze and shatter cycle is tracked properly**, including the part that
  has no event behind it. All five emotes advance the ladder, the poison-volley bar
  stops the moment he freezes, and a FAILED shatter is caught by noticing that a frozen
  boss has started swinging at people again. Frost hits and melee hits are counted with
  live per-second rates, and every way out of a freeze zeroes them.
- Ouro's submerge cycle behaves: submerging stops the Blast, Sweep and Submerge bars,
  thirty seconds later all three come back from their pull values, and once he berserks
  he never submerges again — so that bar stops for good and the Blast cooldown restarts
  from zero.
- The Twin Emperors' teleport bar counts you in for the swap, and "run away from the
  bug" only fires for a bug that is actually near you.
- The Vanilla tank-swap fights (Kurinnaxx, Buru, Fankriss, Huhuran) get the full
  three-way call: your own stacks, the taunt call when somebody ELSE is stacked and you
  are clean, and the plain tank announce. The taunt call goes quiet the instant you are
  carrying the debuff yourself.
- Anubisath trash alerts are armed for the whole instance in both zones — plague, the
  explode countdown per mob, cause insanity, thunderclap, and the two "stop casting,
  it's reflecting" alarms, which are detected from what bounced off it rather than from
  a buff you cannot see.
- The Ahn'Qiraj options sections are real: every bar and every warning is its own toggle
  under its boss. **Temple settings carry over** — where the old data and the new spec
  agree on a mechanic, the setting is stored under the same key it always was, so
  anything you had switched off in AQ40 stays off.
- Internal: the encounter grammar gained seven more general primitives — membership
  rosters with stack counts, a scan that reads a unit through other players' targets,
  rate counters, condition lists, combat-log miss types, per-source anti-spam windows,
  and state dwell time. The old `data_aq40.lua` was diffed against the spec first and
  then deleted; where the two disagreed the spec won, and the differences are listed in
  the wave report.

## Unreleased — 2.0.0 rebuild, wave 4d (Naxxramas + the Naxx specials — internal)
- **Naxxramas is back, rebuilt.** All fifteen bosses and the zone-wide trash alerts now
  run on the new engine, rewritten from the behavioural spec rather than carried over:
  every timer, every warning, the audiences they default on for, the phase rules and
  the Era-specific detection each fight needs. Where the old data had a handful of bars
  per boss, each fight now carries the full set — including the ones that only exist on
  Era, like Noth's fully scripted teleport clock and Heigan's silent dance loop.
- Timer bars know the difference between "the first one" and "every one after". Anub'-
  Rekhan's first Locust Swarm is a wide window and every one after it is a flat 69.2
  seconds; Loatheb's dooms alternate and then change shape entirely at the seventh;
  Kel'Thuzad's whole phase-2 ability set arms on different numbers the moment he
  becomes attackable than it uses for the rest of the fight.
- Pre-warnings arrive on time and, just as importantly, GO AWAY when they should.
  "Widow's Embrace ends in 5 seconds" is cancelled if the Embrace ends early or the
  boss dies; "switch to the wrapped player" on Maexxna is cancelled if the wrapped
  player turns out to be you; Gothik's teleport pre-warnings all stop for good once he
  is under 30% and stops teleporting.
- The fights with no events to work with are handled the way Era demands. Sapphiron's
  air phase is detected by watching whether he still has a target of his own, held for
  half a second before it counts, with a 60-second safety net. Kel'Thuzad's phase 2 is
  detected by his nameplate appearing. Thaddius's intermission starts when both adds
  are down at the same time, tracked off their emotes. None of these have a real event
  on this client, and all of them now start your bars anyway.
- **Your five Naxx widgets are untouched and now start themselves.** The Four Horsemen
  tracker and rotation bar, the Gothik wave tracker, the Loatheb healer window, the
  Razuvious understudy icons and the Thaddius add-health frame all come up on the right
  pull and go away at the end, driven by the encounter data instead of the old engine.
  Not one line of those files changed. Where a widget already shows something the new
  data could also show — Gothik's waves, the Horsemen's per-horse cooldowns, the
  polarity flip alert — the WIDGET still ships it and the encounter deliberately stays
  quiet, so nothing is drawn twice.
- The Naxxramas options section is real again: every bar and every warning is its own
  toggle under its boss, and they are stored under exactly the keys your existing
  settings already use, so anything you had turned off in Naxxramas stays off.
- Naxxramas trash alerts (fear, poison charge, veil of shadow, and "kill the lightning
  totem") are armed the whole time you are in the instance, including during boss
  fights, and disarm themselves when you leave.
- Internal: the encounter grammar gained eleven general primitives the Naxx section
  needed — deferred and cancellable alerts, counter- and state-gated triggers,
  per-trigger durations, alternating scheduled loops with per-tick pre-warnings, routed
  phase/state transitions, the nameplate and pet-flag paths, zone-armed trash modules,
  and the projection that builds the options tree from the encounter registry. The old
  `data_naxxramas.lua` was diffed against the spec first and then deleted; where the two
  disagreed the spec won, and the differences are listed in the wave report.

## Unreleased — 2.0.0 rebuild, wave 3 (raid sync, recovery, interop — internal)
- Raid Mechanics now talks to other people running it. Pull timers, break timers and
  "the fight has started / the fight is over" all travel across the raid on Daseeki's
  own channel, so one person starting a pull countdown starts everyone's.
- A pull only counts once three different people's clients agree it happened, so a
  stray message can never start your timers in the middle of a trash pack. The one
  exception is a fight ENDING, which only needs one report — on Classic the game gives
  everyone too little to work with otherwise, and a fight that ends late is worse than
  one that ends on somebody else's word.
- Reloading mid-fight no longer costs you the fight. On coming back, Raid Mechanics
  quietly asks up to three raiders — highest version first — where the fight is up to,
  and rebuilds it: how long you have been pulled for, which phase you are in, and every
  bar that was running, restored to the right position. Ability WINDOWS survive the
  rebuild too, so a "40-60 seconds" bar comes back as a window and not a fake exact
  time. It asks at 7, 10 and 13 seconds and stops the moment somebody answers, and
  while it is working it will not mistake the recovery for a fresh pull.
- Break timers survive a reload or a disconnect, and are recovered from other raiders
  if you log back in during one. They announce at 10, 5, 2 and 1 minutes and tell you
  what time the break is over.
- If people around you are running a newer version, you are told once — quietly, in
  chat, with a reminder next time you log in. **Raid Mechanics will never turn itself
  off** because of what somebody else's client reports. Boss mods traditionally can and
  do; that is not a thing that is going to happen to you in the middle of a raid night.
- DBM users' pull and break timers now show up on YOUR bars, attributed to whoever
  started them, without you needing DBM installed. This is strictly one-way: Raid
  Mechanics listens on DBM's channel and is structurally incapable of transmitting on
  it — the send path physically refuses that prefix in two separate places, and the
  test suite proves both.
- Internal: the pull timer moved out of the wave-1 scaffolding into the real sync layer
  and picked up the rules it was missing (a pull under 3 seconds is now refused instead
  of silently stretched to 3, a pull is refused mid-fight and in battlegrounds, and
  engaging a boss cancels a running one). `/drm pull` is unchanged.

## Unreleased — 2.0.0 rebuild, wave 1 (engine core, internal)
- Raid Mechanics has a new engine underneath it. The old one could only watch for a
  boss the moment you personally entered combat with it, kept its timings on the
  game's own tick, and had no idea when a pull had actually gone wrong. The new one
  watches for a pull five different ways (the game's encounter event, three staggered
  sweeps of what everyone in the raid is targeting, boss yells and emotes, and a
  guarded boss-health check), so a fight starts on time whether you pulled it, someone
  else did, or you ran in late.
- Wipes are now recognised properly. The engine checks every three seconds and then
  waits to be sure before calling it, so feigning, vanishing, a spirit release, a boss
  briefly phasing out or a long roleplay pause no longer end your timers early — and a
  real wipe still closes the fight cleanly. World bosses get a longer grace period, and
  a fight that needs even longer can say so.
- Re-pulling is protected: after a kill the fight will not restart for two minutes,
  after a wipe for twenty seconds, and zoning out and back in clears both immediately.
  No more double-started timers when the raid resets and pulls again.
- Every timer now runs on one shared clock built for the job. Bars no longer drift over
  a long fight, a laggy frame delays a warning instead of quietly desynchronising
  everything after it, and outside combat the engine does no work at all.
- Timer bars understand ability windows. A cast that lands somewhere between 40 and 60
  seconds now shows the whole window rather than pretending to be exact — the bar runs
  to the latest time with the window shaded, while the countdown voice, the sorting and
  the "this is about to happen" enlargement all use the EARLIEST time, so you are never
  told to relax during the part of the window where it can actually happen.
- New: the engine now checks its own timer data. Every time a bar restarts, it measures
  the one it replaced, and anything that fired outside its declared window is written to
  a small, capped record inside your saved settings — never to chat. After a few raid
  nights that record says, with numbers, exactly which of our timings are wrong. Nobody
  gets nagged and nothing is sent anywhere.
- Internal, no user-visible change yet: encounters are now described as data rather than
  code, so the remaining zones can be added quickly and consistently. The Naxxramas
  widgets you already use (Four Horsemen, Gothik, Loatheb, Razuvious, Thaddius) are
  untouched and will re-seat on the new engine unchanged.
- Encounter data for Naxxramas, Blackwing Lair and Ahn'Qiraj is temporarily not loaded
  while it is regenerated in the new format. This build is an internal engine milestone,
  not a raid-night build.

## Unreleased — 2.0.0 rebuild, wave 2 (timer bars, warnings, Era services)
- Raid Mechanics has timer bars again, and this time they are part of the same
  styled HUD as the rest of the addon rather than a separate look. Bars carry the
  ability icon, its name, a running count where one applies, and the time left, on
  two lists you place separately: a small list for everything that is coming, and a
  large list that a bar promotes itself into as it gets close.
- Bars understand ability WINDOWS properly on screen. A cast that lands somewhere
  between 40 and 60 seconds draws to the 60, with the uncertain part of the bar
  shaded so you can see the window rather than guess at it — while the sorting, the
  "this is about to happen" enlargement and the spoken countdown all work off the
  40. You are never told to relax during the part of the window where it can happen.
- Bars can change their mind mid-fight. When a fight only tells you which ability
  you got partway through (Chromaggus picking two breaths out of five), the running
  bar is renamed and recoloured in place — it does not restart, so the time left
  stays honest and the timer-accuracy record is not polluted with a false alarm.
- The pull countdown is visible at last. It was already a real timer underneath;
  now it draws with everything else, in its own colour, on the large list, with the
  spoken count.
- Warnings are now two clearly different things instead of one. Ordinary
  announcements are three stacked lines that scroll; the important ones are a much
  larger, outlined headline at their own spot with a screen flash, a sound picked
  from four urgency levels, and a spoken line where one exists. You can move each of
  the four HUD spots independently and they are labelled while you drag them.
- Warnings that name people read better: names are class-coloured, carry the raid
  marker if the person has one, and drop the realm suffix. When a mechanic hits
  several people at once they arrive as one line ("Sting on A, B, C and 2 others")
  instead of five lines fighting for the same slot.
- Everything can be turned off individually: all bars, all warnings, just the big
  warnings' text, just their flash, just their sound, just the controller rumble.
  Turning off all three parts of the big warnings costs nothing at all — the addon
  stops doing the work rather than doing it and hiding the result.
- New under the hood, and it is what the encounter data will lean on: the addon can
  now work out who a boss is about to hit (three different ways, depending on how
  much time there is), how far away someone is on a client that has no distance
  function inside raids, how much health a boss has when nobody is targeting it, and
  whether YOU personally can interrupt or dispel the thing being warned about. That
  last one is why you will stop seeing interrupt warnings you cannot act on.
- New: a public hook for WeakAuras and nameplate addons. Every timer we start is
  published with eighteen pieces of information about it, and it is published even
  when you have chosen to hide our own bars — so hiding our display never silences
  the aura you built on top of it.
- `/drm demo` puts the whole thing on screen out of combat, and `/drm anchors` shows
  just the four labelled drag handles, so you can place everything without a boss.
- Internal: 712 assertions now run headless against the real code, including every
  bar layout rule, both warning tiers, all three target scanners, the range ladder,
  the boss-health fallback and every interrupt/dispel gate.

## Unreleased (internal)
- The alert HUD now matches the rest of the Daseeki suite. Timer bars, the centre
  warnings, the Gothik / Four Horsemen / Loatheb / Mini-Boss widgets and the sound
  picker all had their own fixed dark palette and the game's stock font, so they were
  the one part of your UI that ignored both the theme and the font you picked in
  Daseeki Core. They now follow both, and change with them. Countdowns and health
  percentages use the suite's numeral face so they line up as you read them. The
  centre warnings keep their large size and outline — only the typeface changed.
  If you left a mechanic's alert font on "Default" it now means your picked suite
  font; explicitly choosing Arial Narrow, Skurri, Morpheus or a shared-media font
  still gives you exactly that. Positions, sizes and spacing are untouched, and with
  Daseeki Core not installed everything looks exactly as it did.

## 1.3.0
- Settings rebuilt on the new Daseeki Core 2.0 interface (requires Daseeki Core 2.0.0+).
  The boss / mechanic / detail drill-down is preserved; detail editor groups now stack
  and collapse cleanly with no overlap.

## 1.2.1
- Curated special-warning and voice-countdown flag assignments across encounters.

## 1.2.0
- Naxxramas encounter data verified against captured combat logs (DBM-parity pass):
  corrected spell IDs, Loatheb heal-window redesign, Faerlina/Sapphiron trigger fixes,
  Berserk timers, Thaddius add-phase, and more.
- Added Blackwing Lair and Temple of Ahn'Qiraj encounter data.
- Phase E: special warnings, voice countdowns, pull timer, and kill stats.
- Debug-only banner fade and debug-log hygiene improvements.
## 1.1.0
- Added a combat-log debug/timing harness for verifying real boss mechanic timings:
  casts (with the interval since a spell last fired), auras, damage taken, and deaths
  are captured to a persisted, per-sitting debug log (viewable in-game and clearable).
- Added a "Debug Only" mode — a blanket kill-switch that silences ALL mechanic output
  (Ability Tracker, On Cast / Personal Damage notifications, custom widgets, boss-death
  sound) while combat-log data keeps being captured, so real fights can be used to
  gather accurate timings without the addon's current guesses firing alongside.
- Added a persistent login reminder and an on-screen indicator while Debug Only is on,
  so alerts are never left silently disabled.
- Added an optional DBM cross-log bridge: when DBM-Core is installed, DBM's own timers,
  announces, stage changes, and pull detection are logged alongside our raw capture for
  side-by-side comparison. Fully optional and degrades cleanly when DBM is absent.
- Added hard caps on debug-log SavedVariables growth (live-log line cap with oldest-line
  trimming, plus a capped ring-buffer of saved sessions) to prevent logout/reload lag.
- Added a "Clear Saved Sessions" button to the options panel, and `/drm` debug commands
  (debug, debugonly, log, savelog, clearlog, clearsessions).

## 1.0.0
- Initial CurseForge release.
