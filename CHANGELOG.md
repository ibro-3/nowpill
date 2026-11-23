# Changelog

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
