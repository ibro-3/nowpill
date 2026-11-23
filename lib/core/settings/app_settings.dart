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

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppMotionMode? motionMode,
    bool? dynamicColor,
    int? defaultReminderMinutes,
    bool? weekStartsOnMonday,
    String? localeCode,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      motionMode: motionMode ?? this.motionMode,
      dynamicColor: dynamicColor ?? this.dynamicColor,
      defaultReminderMinutes:
          defaultReminderMinutes ?? this.defaultReminderMinutes,
      weekStartsOnMonday: weekStartsOnMonday ?? this.weekStartsOnMonday,
      localeCode: localeCode ?? this.localeCode,
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
        other.localeCode == localeCode;
  }

  @override
  int get hashCode => Object.hash(
    themeMode,
    motionMode,
    dynamicColor,
    defaultReminderMinutes,
    weekStartsOnMonday,
    localeCode,
  );
}
