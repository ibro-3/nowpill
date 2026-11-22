# NowPill

A playful **Material 3 Expressive** habit tracker & to-do list. Local-first,
offline, with streaks, freeze tokens, recurring tasks, reminders, and stats.

> Status: early development (v0.1.0 in progress).
> Implementation plan: `~/.opencode/plan/nowpill-plan.md`.

## Platforms

Android · iOS · Web · Linux desktop

## Requirements

- Flutter 3.50+ / Dart 3.14+ (uses the standalone `material_ui` package)
- Android SDK for Android builds; Xcode/macOS for iOS builds
- Linux: clang, cmake, ninja, GTK3 headers
- A Chromium-based browser for web runs. On this machine we use
  [Helium](https://helium.computer): `export CHROME_EXECUTABLE=/usr/bin/helium-browser`

## Run

```bash
flutter pub get

# Linux desktop
flutter run -d linux

# Web (Chromium-based browser)
CHROME_EXECUTABLE=/usr/bin/helium-browser flutter run -d chrome

# Android (device or emulator connected)
flutter run -d android
```

## Test & quality gates

```bash
flutter analyze
dart format .
flutter test
```

Generated code (`*.g.dart`, `*.freezed.dart`, `*.drift.dart`) is gitignored;
regenerate with:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Build

```bash
flutter build apk --release
flutter build web --release
flutter build linux --release
# iOS: flutter build ipa  (requires macOS + signing)
```

## Notes

- App ID `com.example.nowpill` is a **placeholder** — change before any store release.
- Reminders work on Android/iOS/Linux; web reminders are deferred.
- Data is stored locally (Drift/SQLite) with JSON export/import; cloud sync is planned for a later release.
