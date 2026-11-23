# Changelog

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
