# Changelog

## Unreleased

### Thaddius: "Polarity CHANGED" is its own alert now

- **The notification that fires only when your charge actually swaps is a row of its
  own.** It always existed — it reads your debuff icon and stays quiet on a refresh,
  which is exactly the behaviour you want — but it lived as a "Polarity Change Alert"
  sub-section that only appeared once you clicked the *Polarity Shift* row, directly
  above a near-identical row called *Polarity Shift (cast)*. It is now
  **Polarity CHANGED (your debuff)** in Thaddius's ability list, sitting with the
  other polarity rows, with the rule printed on its own page: *fires only when your
  charge actually FLIPS (+ ↔ −), never on a refresh.*
- Being a row means it gets everything a row gets: a **Placement** control that
  really works (Major, Minor, Custom or Hidden — it used to share one saved position
  with the Polarity Shift timer bar, so it could not be moved on its own at all),
  the **Sound** switch and the per-mechanic **sound picker**, and **Play** / **Cue**,
  where Play shows you a simulated flip rather than a mock-up of one.
- **Your existing settings come with it.** Whatever you had set — on or off, text on
  or off, sound on or off, and which sound — lands on the new row unchanged the first
  time you log in. Text turned off becomes *Hidden*, which is the same thing said in
  the new vocabulary: nothing drawn, sound still plays. The old values are left in
  place, untouched, and the Polarity Shift bar's own settings are not affected.

### Your engine log is a log again

- **Fixed: other addons' chat traffic was filling the engine log and pushing your own
  raid's records out of it.** Raid Mechanics listens on the addon channel, and the
  game hands it every addon message in your session — including the constant stream a
  world-buff addon sends. Every one of those was written down as a separate entry, so
  after one raid night the 250-entry log was 250 lines of "that wasn't for us" and the
  timer, encounter and diagnostic records the night actually produced had all been
  evicted. Ambient traffic like this is now **counted, not transcribed**: one line per
  source, carrying a running total, with the count also printed at the top of
  `/drm telemetry raw`. A malformed message on *our own* channel is still recorded in
  full every time — that one is real evidence.

### Sync hardening

- **Our own broadcasts can come back to us inside the send call**, on this client, and
  are now recognised as our own echo at the front door — before any counter, before the
  inbound event goes out to the rest of the engine, and before any handler runs. The
  echo suppression that stops a received sync being re-broadcast now covers the whole
  of inbound handling rather than being switched on one call later, and a depth fuse
  refuses an unforeseen re-entry (with a record) instead of letting it run away. Nothing
  changes on screen; the traffic counters just stop counting our own messages as
  somebody else's.

## 2.1.0 — 2026-08-10

**The settings rework: placement you can find, categories that lead, and a sound
picker on every warning.** Three things you told us after 2.0.0 shipped — "I don't
see a way to place major or minor bars", "I don't understand the custom timer
section", and "there's no way to choose sounds for a given mechanic" — and this
release is those three answers. Your settings are kept; nothing changes shape.

### Placement, front and centre

- **A new Placement section leads the General page.** All five on-screen surfaces —
  Minor bars, Major bars, Announcements, Special warnings, and the boss-specials
  pad — each with three controls: **Place** (picks up that one labelled handle and
  starts dragging it immediately; click drops it, Esc or the button settles it),
  **Reset placement**, and the **Attach to** frame control. These are the same
  handles `/drm unlock`, demo and layout mode have always dressed — one placement
  state, now with a front door.
- **Preview all** fires sample content into every surface at once — a bar on each
  list, an announcement, and a special warning — so you place things against the
  real visuals, not empty boxes. It runs inside the testing suite's quarantine
  (no stats, no sync, no timer telemetry) and cleans up completely when you press
  **Lock all**, leave the page, or pull a boss.
- The old **Attachment** section is absorbed into Placement — attaching a surface
  to your target frame or the minimap is part of placing it, not a separate page.
  The buttons formerly called "Show anchors" now say **Unlock handles**, which is
  what they do.

### Every ability leads with where it goes

- Each ability's page now opens with one control labelled **Placement** — Major /
  Minor / Custom / Hidden — with the follow rule stated right there: Major and
  Minor follow the two bucket anchors in Placement, a Minor bar is promoted into
  the Major list as its time runs out, Custom places itself, and Hidden draws
  nothing while its sound still plays.
- **Custom explains itself.** Picking Custom opens a block that says what it is —
  this one ability owns its own spot — before showing its controls: Place (the
  ability's own handle, unlocked alone), Reset placement, frame attachment, and
  size. Same controls as before, no more mystery.

### Choose the sound per mechanic

- Beside each warning's Default / On / Off switch there is now a **Sound:** button
  that opens the sound picker for that one ability. Your pick beats the built-in
  default whenever the row is allowed to make noise at all; **Off still silences
  everything**, exactly as before. Picking **None** clears your choice and returns
  the row to Default.
- The hint under the switch now tells you exactly what the **Cue** button will
  play this second — your pick, the tier default, or nothing — so you can always
  check the answer before the fight does.

### Counted timer bars now say which one is coming

- **The number is in the bar's label now** — "Spore 3", "Inevitable Doom 2",
  "Mark 5" — and it names the occurrence the bar is running **toward**, so you can
  read straight off the timer which spore is about to spawn or which mark is about
  to go out. When the cast lands, the announcement ("Spore 3") confirms the exact
  number the bar was showing, and the restarted bar moves on to the next one.
- This applies to every counted timer in every raid — Loatheb's spores and dooms,
  the Four Horsemen's marks, Viscidus's poison volleys — including through Loatheb's
  late-fight doom speed-up, where the numbering carries straight across the cadence
  change.
- The little count badge in the bar's corner is retired: the same number printed
  twice on one bar was clutter, and the label is where your eyes already are.
- Timer bars whose ability declares only a display name now label with that name
  ("Spore", not a lowercase internal key) — the fix that makes "Spore 3" read as
  "Spore 3". And the rehearsal's play button always shows a counted bar as its
  first occurrence instead of whatever number the last real fight left behind.

Nothing here moves your existing setup: routes, sound modes, positions, attachments,
sizes, statistics and every 2.0.0 setting load unchanged, and that is verified by a
dedicated migration test that pushes a real 2.0.0 profile through the new panel.

## 2.0.0 — 2026-08-08

**Raid Mechanics has been rebuilt from the ground up, and it now covers every raid in
Classic Era — all eight zones, all 65 boss fights.**

The old version knew three raids and watched for a fight starting in exactly one way.
This one knows Molten Core, Onyxia's Lair, Blackwing Lair, Zul'Gurub, both Ahn'Qiraj
raids, Naxxramas and all six world bosses, and it finds the pull five different ways so
a fight that starts oddly still arms your timers.

### What's new

- **Every raid, every boss.** 65 encounters with their timers, warnings, phase changes
  and enrages. Molten Core through Naxxramas, plus Azuregos, Lord Kazzak and the four
  Dragons of Nightmare out in the world.
- **Timer bars.** Countdown bars for every tracked ability, in two lists — a normal
  stack and a larger one for the things that matter — with spell icons, colour by school,
  and bars that recolour or rename themselves mid-fight when the fight demands it
  (Chromaggus changes his breath every pull; the bar changes with him).
- **You decide where everything goes.** Every timer and every warning has one control on
  its boss page: **Major**, **Minor**, **Hidden** or **Custom**.
  - **Major** is the big list and the big centred warning — where adds, interrupts and
    the pull timer go by default. A Major bar starts large and stays there.
  - **Minor** is the normal stack and the ordinary announcement line. A Minor bar is
    promoted into the Major list as its time runs out, and you choose when: "promote at
    N seconds" and "pulse under N seconds" are now sliders instead of fixed numbers.
  - **Hidden** takes something off your screen without silencing it. The sound and the
    spoken countdown still play — useful for the cue you want to hear but not see.
  - **Custom** gives that one ability its own spot: drag it wherever you like, at
    whatever size you like, outside both lists. It never joins a stack, never migrates,
    and still grows and pulses where you put it.

  Nothing is switched off by this. Every ability starts in the bucket its own severity
  implies, so a fresh install is already sorted the way you would have sorted it.
- **Anchors can ride your unit frames.** Any anchor — either bar list, either warning
  tier, the new boss-specials anchor, and every Custom ability — can be attached to your
  **target frame**, your **player frame**, the **minimap**, or any frame you can name,
  with a drag-adjustable offset. If that frame is hidden or does not exist — your target
  dies, or the addon that owns it is not loaded — the content falls straight back to its
  own position on screen. **Nothing ever vanishes because the thing it was attached to
  went away**, and a frame that appears later is picked up automatically without a
  reload.
- **Honest uncertainty.** Some abilities genuinely do not have a fixed cooldown. Instead
  of inventing a number, those bars show the real WINDOW as a shaded band — "somewhere
  between 26 and 29 seconds" — and the countdown voice speaks at the earliest end of it.
  Where even a window would be dishonest, there is deliberately no bar at all.
- **Warnings in tiers.** Ordinary announcements stack quietly; the things that kill you
  get big centred text with a screen flash and a sound. Both are separately placeable and
  separately silenceable.
- **Quiet by default — loud where it matters.** Sixty-five bosses' worth of alerts is a
  lot of noise if every one of them beeps, so by default **most abilities are seen and
  not heard**. What still makes a sound is the short list you would have written
  yourself: every big centred special warning, every critical raid-wide call (Disrupting
  Shout, a tank swap, a lethal debuff landing on someone), every interrupt call, and
  every hard enrage. Everything else draws its line and says nothing.

  **Any ability is one click from loud.** Each ability's page now has a **Sound** switch
  beside its placement control with three settings — **Default**, **On** and **Off** —
  and the line underneath it tells you which way Default falls for that specific
  ability and why. Turn one alert on, turn one off, and everything you never touched
  keeps behaving sensibly. The **Cue** button next to it plays exactly what that ability
  will play in the fight, so what you hear when you press it is the truth, including
  when the truth is silence.

  Countdown voices, pull and break sounds and the sounds you attach to a timer yourself
  are **not affected** — this is about ability warnings only.
- **It knows what you are.** Tank-only, healer-only, "you can dispel this" and
  class-specific alerts ship switched on for the people they are for and off for
  everyone else — worked out from your talents, your stance or form, and your raid
  assignment, and re-worked out when you respec or get promoted mid-raid. If your
  talents are not readable yet at login it waits and asks again rather than guessing —
  a Protection paladin is never filed as a healer because the client was slow.
- **Raid sync.** Pull timers and break timers are shared with everyone else running
  Raid Mechanics, and a kill or a wipe is confirmed by several people before it counts,
  so one person's disconnect does not end the fight for the raid.
- **Reload recovery.** Reload or disconnect mid-fight and your bars come back — the raid
  tells your client what is still running, most-urgent first. It waits for your raid
  roster to actually arrive before it asks, and asks again if it has not, so a reload
  during a pull recovers instead of quietly finding nobody to ask.
- **DBM pull timers still work.** If someone in your raid pulls with DBM, you get the
  countdown. Raid Mechanics listens to DBM but never transmits on DBM's channel.
- **Self-auditing timers.** When an ability comes back sooner than the addon expected,
  that observation is written down instead of being announced to your raid. `/drm
  telemetry` shows which timers have been wrong and by how much — after a few raid
  nights it is a list of exactly what needs correcting.
- **The five Naxxramas specials are intact — and now they are placeable like everything
  else.** The Four Horsemen rotation caller and mark tracker, the Gothik wave counter,
  the Loatheb healer rotation, the Razuvious understudy tracker and the Thaddius polarity
  watcher all came across with their own config panels. The five that draw a widget now
  dock to a single **Boss specials** anchor, so you place them once and every boss's
  tracker turns up in the same corner — and any of them can be detached to its own spot,
  or attached to a unit frame, from its own page. (The Razuvious tracker is the exception
  and always was: its icons sit on the understudies' nameplates, which the game places,
  not us.)
- **Sound packs, made pickable.** The DBM and NovaWorldBuffs sound packs ship inside the
  addon, so they work whether or not you have those addons installed, and anything
  registered with LibSharedMedia is picked up too. Pick a default pack and the sound
  picker opens filtered to it, instead of dropping you into a thousand-entry list.
- **You can rehearse any fight, out of combat.** Every boss page has a **Test this
  boss** button, and every ability on it has **Play** and **Cue** buttons of its own.
  - **Play** fires that one ability exactly the way the fight will — its real duration,
    its real uncertainty window, in the place you routed it to, with the sound you
    chose. Press it again and it restarts. **Cue** plays just the sound, and plays it
    honestly: whatever that ability resolves to right now, which is nothing at all when
    it is set to be silent.
  - **Test this boss** is the whole rehearsal: the engage banner, every enabled timer
    started at its real value all at once (so you see the screen you will actually
    have), the warnings walked out about a second apart so you can read them, the
    phases stepped, and the boss's own special tracker switched on. **Stop** clears all
    of it.
  - **None of it can reach your raid.** A test never sends anything on the addon
    channel, never touches your kill and wipe record, and never feeds the timer
    self-audit. And if a real pull starts while you are testing, the test is dropped
    instantly in favour of the fight.
- **`/drm layout`** is a placement workbench. It fills every list and both warning
  tiers with one of everything — every colour, both buckets, a variance window, a count
  bar, a pull countdown and a sample boss tracker — and **keeps them there** while you
  drag, following your changes as you make them. `/drm demo` is still the one-shot
  quick version; this is the one you leave running.
- **`/drm playback <boss>`** replays a scripted fight at five times speed (or any speed
  you name). Heigan's dance clock, Noth's teleport cycle and Gothik's eighteen add
  waves all run in accelerated real order, so a five-minute sequence takes one minute
  to watch and you can check the whole thing before the raid instead of during it.
- **`/drm validate`** checks all 65 encounters against your actual game client in one
  pass: every spell ID, every icon, every sound file and every voice line. Anything the
  client no longer recognises is listed by boss and by ability. Worth running after
  every patch — a renumbered spell ID is an alert that silently stops firing, and this
  is the only cheap way to find out before it matters.
- **`/drm demo`** draws the whole display out of combat — one bar of every kind, one
  line of every warning tier, and labelled draggable anchors — so you can place
  everything without needing a boss.

### If you already use Raid Mechanics

**Your settings are kept.** Every mechanic toggle is stored under the same key it used
before, so a mechanic you switched off is still switched off, a sound you chose is still
chosen, and your alert placements are where you left them. Your kill and wipe statistics
and your saved debug logs are untouched. The settings file is upgraded in place — nothing
is ever wiped to make room for a new version.

Three things to know:

- **Timer values changed** where the rebuild's reference data disagreed with the old
  numbers. Every disagreement was checked against real combat logs first and the more
  reliable source won; the per-wave notes below record each one.
- **Some alerts you never had now exist**, and a few of them ship switched ON because
  they are load-bearing (a poison cloud when Kri dies; the Twin Emperors' heal). The
  chatty ones — cleaves, thrashes, knockdowns — ship switched OFF, as before.
- **Add and interrupt bars now start in the big list.** With Major/Minor placement, the
  bars that name adds or an interruptible cast begin on the Major anchor instead of
  waiting to be promoted with 11 seconds left. If you preferred them in the normal
  stack, set that ability's placement to Minor — the control is on its own page, and it
  is remembered per ability.
- **A lot of alerts got quieter.** Ordinary announcements no longer make a sound unless
  you ask them to — the big centred warnings, the critical calls, the interrupt calls
  and the hard enrages still do. If there is one you want back, its **Sound** switch is
  on its own page, next to its placement control, and it is one click.
- **Everyone in the raid should be on 2.0.0** for pull-timer sharing and kill
  confirmation to work between you. Mixed versions degrade quietly rather than erroring,
  and Raid Mechanics will never disable itself for being out of date.

**Going back to 1.3.0 is not supported.** Your settings file is not damaged by the
attempt — 2.0.0 stamps a version on it, and any older build that reads a file stamped
newer than itself leaves it completely alone rather than converting or clearing it — but
1.3.0 has no idea what the 2.0 settings mean, so it would run on its own defaults for
everything the rebuild added. If you want to go back, keep a copy of your
`DaseekiRaidMechanicsDB` saved-variables file first.

### Also in 2.0.0

- New options pages for the timer bars (size, spacing, growth direction, sort order per
  list, promote-at and pulse-under), the warning tiers, attachment, sound packs and the
  timer telemetry.
- The two bar lists are now labelled **Minor** and **Major** everywhere — on the options
  page and on the drag handles — instead of "small" and "large". They are the same two
  lists in the same two places; only the names changed, so your saved positions are
  exactly where you left them.
- `/drm telemetry`, `/drm telemetry raw` and `/drm telemetry clear`.
- Requires Daseeki Core 2.0.0 or newer for the options window; everything else works
  standalone.

## Internal build history — the 2.0.0 rebuild, wave by wave

These entries are the engineering record of how 2.0.0 was built. They were
never shipped as releases; everything they describe is folded into the 2.0.0
block above. Kept because each wave documents why a value is what it is.

### 2.0.0 data-honesty pass, Brief N (cold reads at the login seam — internal)
Three findings from the suite data-honesty audit, all of them the same shape: the
code read a client fact on the one frame the client cannot answer it, and could not
tell "not answered" apart from "answered nothing".
- **RM-2 — reload recovery read the raid roster too early (the headline).** The
  cascade correctly deferred its whispers to +7/10/13 s, and then snapshotted the
  list of people to whisper *synchronously on the `PLAYER_ENTERING_WORLD` frame* —
  the one thing the client has not populated yet. After a mid-raid `/reload`
  `IsInGroup()` is already true while `GetNumGroupMembers()` still answers 0, so the
  snapshot was empty, the code concluded "nobody to ask", dropped its flag and
  returned. Nothing retried, and the player rejoined the next pull with no bars at
  all, silently — for a feature that exists solely for that scenario. The snapshot
  moved to the ask: each rung now reads the LIVE roster when it fires, so the
  7/10/13 s ladder is three real attempts instead of three copies of one stale
  answer. On top of that the engine now records `GROUP_ROSTER_UPDATE` as a populate
  witness and refuses to conclude anything from an unanswered roster, with one
  bounded re-ask at +18 s if it is still dark — and if it never populates, the
  suppression flag is handed straight back rather than blinding pull detection for
  nothing.
- **RM-3 — "rank the raid by version" could never work, and now does.** The peer
  table is empty after a reload, the version hello went out on the same frame, and
  replies land three seconds later — so every candidate carried revision -1 and the
  documented version ranking collapsed permanently onto alphabetical order. Recovery
  could whisper a twenty-two-revisions-old client while current ones went unasked.
  Ranking at the ask fixes it for free.
- **RM-1 — "no talent points spent" and "talents not loaded" were the same answer.**
  Both resolved to talent tab 1, which for a paladin is Holy: a Protection paladin
  whose talents read cold at login booted classified as a **healer**, and the options
  tree froze that into every role-gated default for the session. Unreadable talents
  now answer *unknown*: no role is derived from them, no signature is stamped, no
  projection is treated as final, and a re-check against a dark tree refuses instead
  of clearing a tank latch it cannot re-earn. The already-registered
  `PLAYER_ENTERING_WORLD` is routed to the throttled re-check, backed by a bounded
  three-rung ladder, so the answer is earned when the talents warm — including for a
  player who logs in solo and never groups. Zero points spent still resolves to tab 1;
  that rule is unchanged, it just requires the tree to have answered first.
- **The simulator was unkinded first, because that is why none of this was visible.**
  The harness hardcoded `GetNumTalentTabs()` to 3 and had no cold-roster world at all.
  Both are now profiles — a talent tree that is absent, then present-but-unfilled,
  then readable; a roster that is dark at entering-world and populates a beat later —
  and every fix is proved by a RED CONTROL that reproduces the old code's shape on the
  same fixture and fails. One new gate, `BRIEF-N`, 77 assertions — 39 gates and
  2762 assertions in total, all green.

### 2.0.0 rebuild, wave 5 (polish, options, scaffold retirement, release prep — internal)
- **The scaffolding is gone.** `core_boot.lua` existed through waves 1-4 as the place
  homeless things lived after the old engine was demolished; it is now purely the
  composition root, with nothing in it labelled transitional. The raid/boss/npc readers
  and the 1.x `RegisterRaid` refusal moved into `core_api.lua` beside the projection
  that fills them; the combat-log capture, auto-debug policy, Debug-Only indicator and
  kill-statistics text moved into a new `core_diag.lua`.
- **Five determinism findings from the suite async audit (Brief G) fixed.** A Main Tank
  promotion mid-raid now re-derives the role instead of leaving a session latch frozen
  until `/reload`, and re-resolves the role-gated alert defaults with it. The
  timer-restore whispers a reloading raider receives are sorted most-urgent-first —
  they pass through a rate bucket that TRUNCATES, so the old `pairs()` walk decided
  which timers arrived at all, differently every attempt. State-variable restores are
  sorted (the contract the code's own comment already claimed). Multi-creature boss
  health reads walk the encounter's declared creature order. And a sweep that matches
  several bosses at once picks its winner by rule — the mob you are targeting, else the
  lowest creature id — instead of by table-iteration accident.
- **The options surface consumes the whole projected tree**: eight raids in progression
  order, every boss, every row as a toggle honouring its ship-off default, with the five
  specials' own config panels intact.
- **New options pages** for the timer bars, the warning tiers, sound packs and the timer
  telemetry, plus a pack filter in the sound picker.
- **§7.7 (Era world-buff yell broadcasting) was assessed and SKIPPED**, deliberately.
  See RAID_MECHANICS_REBUILD_DESIGN.md for the reasoning: it needs a guild channel
  scope, a BattleNet transport and six invented yell patterns that this addon has no
  precedent for, and it duplicates a surface Daseeki Nexus already owns.

### 2.0.0 rebuild, wave 4a (Molten Core + Onyxia + world bosses — internal)
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

### 2.0.0 rebuild, Ahn'Qiraj data arbitrations (internal)
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

### 2.0.0 rebuild, Naxxramas data arbitrations (internal)
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
### 2.0.0 rebuild, wave 4b (Blackwing Lair + Zul'Gurub — internal)
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

### 2.0.0 rebuild, wave 4c (Ruins + Temple of Ahn'Qiraj — internal)
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

### 2.0.0 rebuild, wave 4d (Naxxramas + the Naxx specials — internal)
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

### 2.0.0 rebuild, wave 3 (raid sync, recovery, interop — internal)
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

### 2.0.0 rebuild, wave 1 (engine core, internal)
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

### 2.0.0 rebuild, wave 2 (timer bars, warnings, Era services)
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

### Suite theming pass (internal)
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
