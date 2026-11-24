# Changelog

## v0.7.0 — 2026-11-24

Routines and scoped vacation. The streak engine is unchanged: only *which*
habits a period pauses is resolved differently. Still local-first.

### Features
- **Routines** — named habit groups (Morning, Evening, …) with colors and
  ordering. The Habits tab gains routine filter chips and section headers;
  an ungrouped "Unrouted" bucket keeps every habit visible. Deleting a routine
  only ungroups its habits.
- **Scoped vacation** — a vacation can pause all habits (the v6 default) or
  just selected routines/habits. Paused days stay neutral, never notify, and
  appear under a collapsed "Paused for vacation" disclosure on Today. A
  routine-scoped vacation follows habits added to that routine later.
- **Stats** — fully paused weeks are skipped in the weekly review comparison;
  paused habits are never "at risk".

### Under the hood
- Schema v7: `Routines`, `VacationScopes`, habit routine links, and an explicit
  `VacationPeriods.allHabits` flag so deleting the last scoped routine can
  never widen a vacation. Guarded v6→v7 migration; v6 backups import as
  all-habits vacations.
- Export envelope v7 carries routines and scopes; folder sync merges them with
  routine-name dedupe, polymorphic target orphan cleanup, natural-key scope
  dedupe, and tombstones.
- Pure `resolvePausedDates` resolves one habit's paused days per habit; the
  streak engine, reminders, widget snapshot, and stats all consume it.
- 490 unit/widget tests plus Linux e2e.

## v0.6.1 — 2026-11-24

Vacation correctness patch. No schema or backup-format change (both stay v6).

- A weekly-target habit now loses a week only when **every active day** of that
  week was paused. Previously a Monday-only vacation excused the whole week.
- Habit reminders skip planned vacation days; adding or removing a vacation
  re-plans them immediately.
- Habits on vacation are no longer listed as "at risk" in the weekly review.

## v0.6.0 — 2026-11-24

Habit depth: quitting and planned time off. Still local-first — no account, no server, no tracking.

### Features
- **Quit habits** — a second habit kind whose streak is the number of clean days
  since the quit date. No daily check-ins: every day is clean until you log a
  relapse (one per day, with an optional note). Relapses reset the current
  streak but keep the best; freeze tokens don't apply. The habit editor lets you
  backdate the quit date, and the kind locks once the habit has history.
- **Upcoming: routines** — v0.7 will group habits into routines and let a
  vacation pause selected routines/habits. v0.6's engine already resolves
  pauses per habit so that extension needs no streak-engine change.
- **Planned vacation** — add inclusive date ranges in Settings. Paused days are
  neutral: not due, not missed, no token spent, no streak gain; a real check-in
  on a paused day still counts. Today shows a vacation banner and drops paused
  habits, and the heatmap marks those days as paused.
- **Replay intro** — Settings → About replays the first-run walkthrough without
  re-seeding starter habits.

### Under the hood
- Schema v6: `HabitRelapses`, `VacationPeriods`, and `Habits.kind`, with a
  guarded v5→v6 migration. Export envelope v6 imports v1–v5 payloads (old habits
  become build habits). Folder sync carries relapses and vacations with LWW,
  natural-key relapse dedupe, parent-orphan cleanup, and tombstones.
- Pure domain: `replayStreak` gains an opt-in quit branch and a `pausedDates`
  set; `expandPausedDates` resolves ranges to local day keys; heatmaps gain
  `relapsed` and `paused` states with screen-reader labels.
- 460 unit/widget tests plus Linux e2e; new coverage for the v6 migration,
  quit replay, vacation replay/range expansion, merge rules, and the relapse /
  vacation UI.

## v0.5.0 — 2026-11-24

First run, project organization, and a quieter accessibility pass. Still
local-first — no account, no server, no tracking.

### Features
- **First-run onboarding** — a three-step intro (what the app is, optional
  starter habits, ready to go) shown once per device. Pick from Drink water,
  Move for 10 minutes, and Read a few pages; skip seeds nothing. The flag is
  local, so restoring a backup on a fresh device still shows the intro.
- **Task lists** — group tasks into named, colored lists and filter by them
  from the Tasks tab. Create and rename inline; deleting a list moves its tasks
  to Inbox instead of deleting them. Recurring tasks stay in their list.
- **Weekly review** — a new Stats card recapping the last complete week
  (check-ins, tasks, delta vs. the week before), best streak, habits whose
  streak is at risk today, and open tasks due in the next seven days.

### Under the hood
- Schema v5 (`TaskLists` + `Tasks.listId/listUuid`) with a guarded v4→v5
  migration; export envelope v5 imports v1–v4 backups (old tasks land in the
  inbox). Folder sync carries lists with LWW merge, name dedupe, and soft
  references — a missing list never drops its tasks.
- Accessibility: screen-reader labels for month/year heatmap days, the progress
  ring, streak odometer, token wallet, and all three stats charts; decorative
  confetti excluded from semantics; large-text sizing for the progress ring,
  filter strips, and bottom navigation.
- 429 unit/widget tests plus Linux e2e; new coverage for the v5 migration,
  list soft-delete/export/merge, onboarding seeding, the weekly-review engine,
  and tap-target/2× text-scale guidelines.

## v0.4.0 — 2026-11-23

Daily-driver delight: ask in plain language, find anything, see the whole year,
check off from the launcher, and sync through a folder on the web too.
Still local-first — no account, no server, no tracking.

### Features
- **Natural-language quick-add** — type “tomorrow at 5pm pay bills #finance
  !high” and watch live preview chips for date, time, recurrence, tags, and
  priority before submitting. Pure EN/ES parser, no AI or network; plain input
  keeps the pre-v0.4 behavior (due today 23:59).
- **Global search** — one reactive screen across task titles/notes/subtasks,
  habit names/notes, and tags. Case- and accent-insensitive; tap a result to
  jump straight to it. Available from every tab.
- **Year heatmap** — a 53×7 GitHub-style grid alongside the month grid on habit
  detail, with the same shared day-state rules, month labels, and ≤30-day tap
  backfill. One fade-in instead of hundreds of individual springs.
- **Interactive home-screen widgets** — the summary widget now offers a Check
  pill for the next undone habit, and a new “Today's habits” list widget shows
  every due habit with a per-habit check pill. Taps write through the same
  repository (sync-safe): a live engine while the app is open, a short-lived
  headless engine when it is closed. iOS AppIntents sources ship (build needs
  macOS).
- **Web folder sync** — Chromium browsers can pick a folder via the File System
  Access API; the handle is kept in IndexedDB so sync resumes after a reload,
  with permission re-request on manual sync. Same per-device envelope files and
  merge as Android/desktop — two tabs with different device ids converge.

### Quality
- 415 unit/widget tests plus Linux e2e; emulator-verified widget check-ins on
  both code paths and browser-verified two-tab folder sync (Chromium 158).

## v0.3.0 — 2026-11-23

Sync & daily-driver core: your data follows you across devices, backs itself
up, and reminders act without opening the app.

### Features
- **Folder sync (optional, off by default)** — keep devices in step through a
  folder you choose (Syncthing, Dropbox, iCloud Drive, a shared drive…). No
  account, no server: each device writes its own envelope file and a pure
  last-writer-wins merge (with tombstones for deletes/undos) converges them.
  Android uses the system folder picker with a persisted permission; desktop
  uses the native directory picker. Reactive cycles on every change, plus
  poll / app-resume / manual "Sync now". Live status in Settings. Web folder
  sync is planned for v0.4.
- **Automatic backups** — a daily snapshot on first launch of the day, last 7
  kept, listed in Settings with an explicit confirm-to-restore. Nothing is ever
  restored automatically.
- **Measurable habits** — optional numeric daily goal (e.g. 8 glasses). A Today
  stepper logs partial progress (shown, but only 100% counts toward the
  streak); the heatmap shades partial days; backfill completes the whole goal.
  Existing habits are unchanged.
- **Notification actions** — Done / Snooze (10 min / 1 hour) right on the
  reminder. Android handles them in a background isolate even when the app is
  closed (writes go through the same database, so sync picks them up); iOS
  category sources ship (build needs macOS).

### Under the hood
- Schema v3 (cross-device identity: per-row uuid + updatedAt, tombstones) and
  v4 (measurable amounts), both with guarded migrations; export envelope v4
  still imports v1–v3 backups.
- 314 unit/widget tests + Linux e2e; emulator-verified two-device merge,
  reactive tombstone propagation, and background Done action.
- CI actions bumped to current majors (checkout v7, setup-java v6, cache v6,
  upload-artifact v7) — clears the Node-20 deprecation annotations.

### Store prep
- Signed release AAB, phone screenshots (1080×2400), privacy policy + Play
  data-safety copy in `store/`.

## v0.2.0 — 2026-11-23

Six feature drops on top of v0.1.0, plus store-release preparation.

### Features
- **Manual freeze mode** — per-habit Auto/Manual toggle in the habit editor.
  In manual mode you decide when to spend a token: tapping a missed heatmap day
  opens a Backfill / Freeze ❄ choice (when a token is available), and tapping a
  frozen day removes the freeze (refund). Existing habits stay in auto mode.
  Schema v2 (`Habits.freezeMode` + `HabitFreezes`) with a v1→v2 migration;
  export envelope v2 carries freezes and still imports v1 backups.
- **Web reminders** — in-tab reminder timers with a browser permission flow and
  a test-fire button in Settings (the web plugin only fires immediate
  notifications via its own service worker, so scheduled occurrences use
  in-page timers while the tab is open).
- **Translations** — full English + Spanish catalogs (~180 keys) covering every
  screen, dialog, and semantics label; a Language picker in Settings
  (System / English / Español) with live switching.
- **Home-screen widgets** — a today-summary widget showing done/total progress,
  a progress bar, and your top habit streak; tap opens the app. Android uses a
  RemoteViews AppWidget fed by a reactive snapshot controller (every check-in,
  completion, CRUD, and import refreshes it); iOS ships WidgetKit Swift sources
  + App Group integration steps (compiling requires macOS).
- **Store-release prep** — application ID `app.nowpill` across Android, iOS, and
  Linux; a two-tone pill launcher icon (legacy + adaptive Android, full iOS
  icon set); release signing via a local upload keystore with a debug-signing
  fallback so CI keeps building; store listing copy in `store/listing.md`.

### Quality
- New e2e journey: backup export → mutate → import through the real Settings UI
  with real file bytes (the platform dialog is the only substituted layer),
  plus an invalid-backup rejection path.
- Motion re-audit: the new surfaces (freeze choice dialog, language picker,
  widgets) add no ad-hoc animation — see `doc/motion_audit.md`.
- Dark-mode + light-mode visual pass with screenshots in `doc/screenshots/`.
- 235 unit/widget tests + 5 Linux e2e journeys, analyze/format clean.

## v0.1.0 — 2026-11-23

First feature-complete release. Local-first habit tracker + to-do list with a
Material 3 Expressive design system and spring-driven motion.

### Features
- **Today dashboard** — greeting/date header, spring progress ring, overdue →
  habits → tasks-due → done sections, quick-add bar, all-done celebration
  (ring overshoot, shape burst, confetti), floating-pill empty states.
- **Tasks** — subtasks, tags, priorities, due dates, recurring tasks
  (complete → spawn next occurrence anchored to the cadence), swipe-to-complete,
  Today/Upcoming/All/Done filters, full editor sheet.
- **Habits** — daily / weekdays / weekly-target schedules, curated icons and
  brand colors, notes, monthly heatmap with ≤30-day tap-backfill, streak
  odometer, freeze tokens (auto-earned every 7 streak days / 4 weeks, cap 3,
  auto-consumed to bridge a missed day, refunded on backfill), archive & delete.
- **Stats** — 30-day trend chart, weekly summary bars with delta, streak
  leaderboard (day/week units), tag donut, staggered entrance.
- **Reminders** — next-N weekday-aware occurrences per habit + one-shot task
  reminders; exact alarms on Android with graceful inexact fallback and a
  settings-intent Allow flow; iOS priming screen; Linux in-app fallback;
  web no-op with UI hint; boot receiver restores schedules after reboot;
  reschedule on CRUD/check-in/import/app-resume.
- **Settings** — theme mode, motion scheme (expressive/standard, honors OS
  reduce-motion), Material You dynamic color, default reminder time, week start,
  notification status + test notification.
- **Backup** — versioned JSON export (save dialog / share / web download) and
  replace-all import behind a confirm dialog.

### Quality
- Pure, unit-tested domain engines: streak replay, recurrence, schedules,
  reminder planner, stats.
- 194 unit/widget tests; 5 integration tests on Linux + Android emulator
  (check-in → streak, recurring spawn, backfill → freeze refund, plus frame
  budgets for the celebration and heatmap).
- GitHub Actions CI: analyze → format → build_runner → tests → web + APK
  builds + headless Linux e2e.
- Motion audit: every animation reads central spring tokens, retargets safely
  on scheme change, and honors reduce-motion (`doc/motion_audit.md`).

### Known limitations
- iOS builds require macOS + signing (platform files included).
- App ID `com.example.nowpill` is a placeholder — change before store release.
- Cloud sync deferred to a later release; data is local with JSON backup.
