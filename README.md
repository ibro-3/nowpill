# NowPill

[![CI](https://github.com/ibro-3/nowpill/actions/workflows/ci.yml/badge.svg)](https://github.com/ibro-3/nowpill/actions/workflows/ci.yml)

A playful **Material 3 Expressive** habit tracker & to-do list. Local-first and
offline, with strict streaks, freeze tokens, recurring tasks, reminders, heatmaps,
and stats — wrapped in smooth, spring-driven motion.

Current release: **v0.2.0** (see `CHANGELOG.md`).

<p align="center">
  <img src="doc/screenshots/today-light.png" width="45%" alt="Today dashboard (light)" />
  <img src="doc/screenshots/stats-dark.png" width="45%" alt="Stats (dark)" />
</p>

## Features

- **Today dashboard** — greeting + spring progress ring; overdue → habits due →
  tasks due → done-today; one-line quick-add; an all-done celebration (ring
  overshoot, shape burst, confetti).
- **Tasks** — subtasks, tags, priorities, due dates, recurring tasks
  (complete → spawn next occurrence), swipe-to-complete, filterable list.
- **Habits** — daily / weekdays / weekly-target schedules, curated icons & brand
  colors, monthly heatmap with tap-backfill (≤30 days), streak odometer, freeze
  tokens (earned automatically, auto-consumed to bridge a missed day, refunded on
  backfill), **manual freeze mode** (opt-in per habit: choose when to spend a
  token), archive & delete.
- **Stats** — 30-day trend, weekly summary, streak leaderboard, tag donut.
- **Reminders** — exact alarms on Android (graceful inexact fallback), iOS, and
  Linux (in-app); **web reminders fire in-tab** with a permission + test-fire
  flow. Survive reboot via a boot receiver.
- **Home-screen widget** — today's progress + top streak on the launcher
  (Android AppWidget; iOS WidgetKit sources included, build needs macOS).
- **Backup** — versioned JSON export/import (schema v2, imports v1) with a
  confirm-replace-all flow.
- **Languages** — English and Spanish, switchable live in Settings.
- **Design** — Material 3 Expressive (`material_3_expressive` + `motor` +
  `material_new_shapes`), Nunito emphasized type scale, Material You dynamic
  color, and a reduce-motion mode (honors the OS accessibility setting).

## Platforms

Android · iOS · Web · Linux desktop

## Requirements

- Flutter 3.50+ / Dart 3.14+ (uses the standalone `material_ui` package)
- Android SDK for Android builds; Xcode/macOS for iOS builds
- Linux: clang, cmake, ninja, GTK3 headers
- A Chromium-based browser for web runs, e.g.
  `export CHROME_EXECUTABLE=/usr/bin/helium-browser`

## Run

```bash
flutter pub get
dart run build_runner build   # generated code is gitignored
flutter gen-l10n              # l10n classes are gitignored (pub get also runs it)

flutter run -d linux          # Linux desktop
flutter run -d chrome         # Web (Chromium-based browser)
flutter run -d android        # Android device or emulator
```

## Test & quality gates

```bash
flutter analyze
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
flutter test                              # unit + widget tests
flutter test integration_test -d linux    # end-to-end flows + frame budgets

# Android emulator (perf suite needs --no-dds):
flutter drive --no-dds --driver=test_driver/integration_test.dart \
  --target=integration_test/perf_test.dart -d <emulator-id>
```

CI (`.github/workflows/ci.yml`) runs analyze → format → build_runner → tests,
then builds web + APK and runs the Linux integration tests headless.

Generated code (`*.g.dart`, `*.freezed.dart`, `*.drift.dart`) is gitignored;
regenerate with `dart run build_runner build`.

## Build

```bash
flutter build apk --release
flutter build web --release
flutter build linux --release
# iOS: flutter build ipa  (requires macOS + signing)
```

**Android release signing:** copy `android/key.properties.example` to
`android/key.properties` and point it at your upload keystore (both are
gitignored). Without it, release builds fall back to debug signing so CI and
`flutter run --release` keep working.

## Architecture

```
lib/
  core/       theme (M3E tokens, Nunito, dynamic color), motion (AppMotion,
              MotionScope), router (go_router StatefulShellRoute), settings
  domain/     pure Dart engines: streak replay, recurrence, schedules,
              reminder planner, stats — all unit-tested, no Flutter imports
  data/       Drift/SQLite db + DAOs, repositories, export/backup, notifications,
              widget (today-summary snapshot bridge for home-screen widgets)
  features/   today / tasks / habits / stats / settings / shell
```

Local-first: all data lives in Drift/SQLite. Streaks and freeze tokens are
*derived* by replaying check-in history (no mutable counters), so backfilling a
past day automatically refunds any freeze it would have consumed.

## Notes

- App ID is `app.nowpill` (Android, iOS, Linux).
- Data is stored locally with JSON export/import; cloud sync is planned for a later release.
- The iOS home-screen widget ships as WidgetKit sources + integration steps in
  `ios/NowPillWidget/` — adding the extension target requires Xcode on macOS.
- See `doc/m3e_spike_decision.md` (design-system adoption), `doc/motion_audit.md`
  (motion polish pass), and `doc/screenshots/` (visual pass).
