# Changelog

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
