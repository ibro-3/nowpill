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
/// Phase 1 covers theme, motion, and dynamic color. Later phases extend this
/// with reminder defaults and week-start without breaking stored keys.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.motionMode = AppMotionMode.expressive,
    this.dynamicColor = true,
  });

  final AppThemeMode themeMode;
  final AppMotionMode motionMode;

  /// Whether to derive the palette from the OS (Material You) when available.
  final bool dynamicColor;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppMotionMode? motionMode,
    bool? dynamicColor,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      motionMode: motionMode ?? this.motionMode,
      dynamicColor: dynamicColor ?? this.dynamicColor,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppSettings &&
        other.themeMode == themeMode &&
        other.motionMode == motionMode &&
        other.dynamicColor == dynamicColor;
  }

  @override
  int get hashCode => Object.hash(themeMode, motionMode, dynamicColor);
}
