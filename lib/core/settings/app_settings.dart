import 'package:flutter/foundation.dart';

/// User-selectable theme brightness behavior.
enum AppThemeMode {
  /// Follow the platform light/dark setting.
  system,

  /// Always light.
  light,

  /// Always dark.
  dark,
}

/// User-selectable motion behavior.
enum AppMotionMode {
  /// Playful M3 Expressive springs (overshoot/bounce). Default.
  expressive,

  /// Standard, minimal-bounce springs (reduced motion).
  standard,
}

/// Immutable bundle of user preferences persisted via `shared_preferences`.
///
/// Phase 1 covered theme, motion, and dynamic color; Phase 8 adds the default
/// reminder time and week start without breaking stored keys.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.motionMode = AppMotionMode.expressive,
    this.dynamicColor = true,
    this.defaultReminderMinutes,
    this.weekStartsOnMonday = true,
    this.localeCode,
    this.syncEnabled = false,
    this.syncFolderHandle,
    this.onboardingComplete = false,
  });

  final AppThemeMode themeMode;
  final AppMotionMode motionMode;

  /// Whether to derive the palette from the OS (Material You) when available.
  final bool dynamicColor;

  /// Default reminder time-of-day for new habits/tasks, as minutes since
  /// midnight (e.g. 540 = 09:00). Null = no default reminder.
  final int? defaultReminderMinutes;

  /// Whether weeks start on Monday (ISO). The streak engine and stats always
  /// use Monday-start weeks; this preference is surfaced for the user and
  /// will drive calendar-style views.
  final bool weekStartsOnMonday;

  /// Explicit UI language override (e.g. 'en', 'es'). Null = follow system.
  final String? localeCode;

  /// Whether file-based sync is on (v0.3.0). Off by default; requires a
  /// chosen folder.
  final bool syncEnabled;

  /// Persisted sync-folder handle: a filesystem path (desktop) or SAF tree
  /// URI (Android). Null = no folder chosen.
  final String? syncFolderHandle;

  /// Whether the first-run intro has been dismissed (v0.5.0). Stored locally
  /// per device — importing a backup never skips it on a fresh install.
  final bool onboardingComplete;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppMotionMode? motionMode,
    bool? dynamicColor,
    int? defaultReminderMinutes,
    bool? weekStartsOnMonday,
    String? localeCode,
    bool? syncEnabled,
    String? syncFolderHandle,
    bool? onboardingComplete,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      motionMode: motionMode ?? this.motionMode,
      dynamicColor: dynamicColor ?? this.dynamicColor,
      defaultReminderMinutes:
          defaultReminderMinutes ?? this.defaultReminderMinutes,
      weekStartsOnMonday: weekStartsOnMonday ?? this.weekStartsOnMonday,
      localeCode: localeCode ?? this.localeCode,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      syncFolderHandle: syncFolderHandle ?? this.syncFolderHandle,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    );
  }

  /// Returns a copy with the default reminder cleared (copyWith cannot null
  /// a nullable field).
  AppSettings clearDefaultReminder() {
    return AppSettings(
      themeMode: themeMode,
      motionMode: motionMode,
      dynamicColor: dynamicColor,
      defaultReminderMinutes: null,
      weekStartsOnMonday: weekStartsOnMonday,
      localeCode: localeCode,
      syncEnabled: syncEnabled,
      syncFolderHandle: syncFolderHandle,
      onboardingComplete: onboardingComplete,
    );
  }

  /// Returns a copy with the locale override cleared (follow system).
  AppSettings clearLocale() {
    return AppSettings(
      themeMode: themeMode,
      motionMode: motionMode,
      dynamicColor: dynamicColor,
      defaultReminderMinutes: defaultReminderMinutes,
      weekStartsOnMonday: weekStartsOnMonday,
      localeCode: null,
      syncEnabled: syncEnabled,
      syncFolderHandle: syncFolderHandle,
      onboardingComplete: onboardingComplete,
    );
  }

  /// Returns a copy with the sync folder cleared (and sync disabled).
  AppSettings clearSyncFolder() {
    return AppSettings(
      themeMode: themeMode,
      motionMode: motionMode,
      dynamicColor: dynamicColor,
      defaultReminderMinutes: defaultReminderMinutes,
      weekStartsOnMonday: weekStartsOnMonday,
      localeCode: localeCode,
      syncEnabled: false,
      syncFolderHandle: null,
      onboardingComplete: onboardingComplete,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppSettings &&
        other.themeMode == themeMode &&
        other.motionMode == motionMode &&
        other.dynamicColor == dynamicColor &&
        other.defaultReminderMinutes == defaultReminderMinutes &&
        other.weekStartsOnMonday == weekStartsOnMonday &&
        other.localeCode == localeCode &&
        other.syncEnabled == syncEnabled &&
        other.syncFolderHandle == syncFolderHandle &&
        other.onboardingComplete == onboardingComplete;
  }

  @override
  int get hashCode => Object.hash(
    themeMode,
    motionMode,
    dynamicColor,
    defaultReminderMinutes,
    weekStartsOnMonday,
    localeCode,
    syncEnabled,
    syncFolderHandle,
    onboardingComplete,
  );
}
