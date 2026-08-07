# Changelog

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
