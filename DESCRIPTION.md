# CurseForge Description — Daseeki Raid Mechanics

<!-- Canonical CurseForge project description. Update here first, then paste to
     https://www.curseforge.com/wow/addons/daseeki-raid-mechanics (project 1592413).
     Last synced: never — this addon has never been publicly released. 2.0.0 is the
     first release the project page would carry, so the whole description below is
     new copy rather than a diff against something live. -->

Daseeki Raid Mechanics is the Daseeki suite's boss-mechanic alert addon for WoW Classic Era. Timer bars, centre-screen warnings and sounds for all eight raid zones — 65 encounters, Molten Core through Naxxramas plus the six world bosses.

## Features
- **Every raid, every boss**: Molten Core, Onyxia's Lair, Blackwing Lair, Zul'Gurub, both Ahn'Qiraj raids, Naxxramas, and the world bosses — Azuregos, Lord Kazzak and the four Dragons of Nightmare. Timers, warnings, phase changes and enrages, each one a toggle you can switch off
- **Timer bars in two lists**: a Minor stack and a Major one for the things that matter, each separately placeable, with spell icons, school colouring, and bars that recolour and rename themselves mid-fight when the fight demands it
- **You decide where each ability goes**: one control per timer and per warning — **Major**, **Minor**, **Hidden** (off your screen but still audible) or **Custom** (its own spot, its own size, outside both lists). Defaults come from the ability's own severity, so a fresh install is already sorted. Promote-at and pulse-under are sliders, not fixed numbers
- **Anchors can ride your unit frames**: attach either bar list, either warning tier, the boss-specials anchor or any Custom ability to your target frame, player frame, minimap or any frame you name. If that frame hides or does not exist, the content falls back to its own screen position — nothing vanishes when your target dies
- **Honest uncertainty**: abilities with no fixed cooldown show their real range as a shaded band — "between 26 and 29 seconds" — instead of an invented exact number, and the countdown speaks at the earliest end of it. Where even a window would be dishonest, no bar ships at all
- **Warnings in tiers**: ordinary announcements stack quietly; the things that kill you get big centred text with a screen flash and a sound. Both are separately placeable and separately silenceable
- **It knows what you are**: tank-only, healer-only, "you can dispel this" and class-specific alerts ship switched on for the people they are for — worked out from your talents, your stance or form and your raid assignment, and re-worked out when you respec or get promoted mid-raid
- **Raid sync**: pull timers and break timers shared with everyone else running Raid Mechanics, with kills and wipes confirmed by several people before they count, so one disconnect does not end the fight for the raid
- **Reload recovery**: reload or disconnect mid-fight and your bars come back — the raid tells your client what is still running, most-urgent first
- **DBM pull timers still work** if someone in your raid pulls with DBM. Raid Mechanics listens to DBM and never transmits on DBM's channel
- **Self-auditing timers**: when an ability comes back sooner than expected, the observation is written down rather than announced to your raid. `/drm telemetry` shows which timers have been wrong and by how much
- **Five bespoke Naxxramas modules**: the Four Horsemen rotation caller and mark tracker, the Gothik wave counter, the Loatheb healer rotation, the Razuvious understudy tracker and the Thaddius polarity watcher, each with its own config panel. The ones that draw a widget dock to a single Boss specials anchor — place it once, every boss's tracker turns up there — and any of them can be detached to its own spot
- **Sound packs included**: the DBM and NovaWorldBuffs sound packs ship inside the addon, so they work whether or not you have those addons installed, and anything registered with LibSharedMedia is picked up too. Pick a default pack and the picker opens filtered to it
- **`/drm demo`** draws the whole display out of combat — one bar of every kind, one line of every warning tier, and labelled draggable anchors — so you can place everything without needing a boss

## Chat Commands
- `/drm` — open the Raid Mechanics section in the Daseeki hub
- `/drm demo` / `/drm demo off` — draw the whole display out of combat
- `/drm anchors` / `/drm lock` — show or hide the draggable HUD anchors
- `/drm pull <sec>` / `/drm pull cancel` — start or cancel a raid pull timer
- `/drm telemetry` — the timer observation report
- `/drm stats` — kill and wipe statistics
- `/drm debug`, `/drm debugonly`, `/drm log` — combat-log capture for measuring real timings

## Requires
- **Daseeki Core 2.0.0+** — the suite's shared UI foundation, which supplies the options window. Everything else works standalone
- Optional: **DBM-Core** — its pull timers are mirrored if present

Sound packs bundled under `Sounds/` originate from the Deadly Boss Mods and NovaWorldBuffs projects and retain their original licensing; the addon code is MIT.

DISCLAIMER: I originally developed these addons for my own personal use, and am listing them on CurseForge to allow some friends to test/report bugs. The 'Daseeki' suite of addons is still very much a WIP, so please keep that in mind when downloading.
