# Daseeki Raid Mechanics

Boss-mechanic alerts for WoW Classic Era (1.14.x): timer bars, centre-screen warnings
and sounds for all eight raid zones — 65 encounters, Molten Core through Naxxramas plus
the six world bosses.

Part of the [Daseeki suite](../). Registers as the `raidmechanics` section in the shared
Daseeki Core options hub.

## What it does

- **Timer bars** for every tracked ability, in two placeable lists (normal / important),
  with spell icons, school colouring and mid-fight recolour+rename where a fight needs it.
- **Variance windows.** Abilities with no fixed cooldown render their real range as a
  shaded band rather than a made-up exact number. Where even a window would be
  dishonest, no bar ships at all.
- **Warning tiers** — quiet announcements and big centred special warnings with a screen
  flash — separately placeable and separately silenceable.
- **Role- and class-aware defaults**: tank-only, healer-only, dispeller-only and
  class-specific rows ship on for the people they are for, derived from talents, stance
  or form, and raid assignment, and re-derived on respec or promotion.
- **Raid sync** on its own addon prefix: pull and break timers, corroborated kill and
  wipe detection, and mid-fight reload recovery (most-urgent timers first).
- **DBM interop, receive-only.** DBM pull timers are ingested; nothing is ever sent on
  DBM's prefix.
- **Self-auditing timers.** Bars that restart earlier than their declared window write
  the observation to a bounded ring instead of announcing it. `/drm telemetry` reports
  which timers have been wrong and by how much.
- **Five bespoke Naxxramas modules**: Four Horsemen rotation + mark tracker, Gothik wave
  counter, Loatheb healer rotation, Razuvious understudy tracker, Thaddius polarity.

## Commands

| Command | Does |
|---|---|
| `/drm` | Open the options hub |
| `/drm demo` / `/drm demo off` | Draw the whole display out of combat |
| `/drm anchors` / `/drm lock` | Show / hide the draggable HUD anchors |
| `/drm pull <sec>` / `/drm pull cancel` | Start or cancel a raid pull timer |
| `/drm telemetry` | Timer observation report (the arbitration table) |
| `/drm telemetry raw` / `/drm telemetry clear` | Raw engine log / clear the ring |
| `/drm stats` | Kill and wipe statistics |
| `/drm debug`, `/drm debugonly`, `/drm log` | Combat-log capture for measuring timings |

## Layout

| | |
|---|---|
| `core.lua` | SavedVariables, migration chain, mechanic config resolution |
| `core_heap` → `core_sched` → `core_timers` | Min-heap absolute-time scheduler and timer semantics |
| `core_api.lua` | The declarative encounter grammar, the runtime, the options projection |
| `core_lifecycle.lua` | Five engage paths, the wipe poll/confirm model, re-engage lockouts |
| `core_telemetry.lua` | The bounded observation ring (the early-refresh tripwire) |
| `core_diag.lua` | Combat-log capture, auto-debug, Debug-Only indicator, stats text |
| `core_boot.lua` | The composition root |
| `core_sync.lua`, `dbm_bridge.lua` | Own-prefix raid sync; receive-only DBM ingest |
| `svc_era.lua`, `svc_scan.lua` | Era range/health/role/dispel services; the three target scanners |
| `ui_bars.lua`, `ui_warnings.lua`, `alerts.lua` | Presentation |
| `enc_*.lua` | Encounter data, one file per zone |
| `mod_*.lua`, `thaddius.lua` | The five Naxxramas special modules |
| `options.lua`, `slash.lua`, `soundpicker.lua` | Configuration surfaces |
| `harness/` | Headless self-tests — run `harness/run-selftests.cmd` |

## Requires

- WoW Classic Era 1.14.x (Interface 11507–11509).
- Optional: **Daseeki Core 2.0.0+** — supplies the options window. Everything else
  works standalone.
- Optional: **DBM-Core** — its pull timers are mirrored if present.

## Licensing

Code is MIT licensed (see `LICENSE`). The bundled sound packs under `Sounds/` originate
from the Deadly Boss Mods and NovaWorldBuffs projects and retain their original
licensing — they are not covered by the MIT license above.
