import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

part 'app_settings_provider.g.dart';

const _kThemeMode = 'settings.themeMode';
const _kMotionMode = 'settings.motionMode';
const _kDynamicColor = 'settings.dynamicColor';
const _kDefaultReminderMinutes = 'settings.defaultReminderMinutes';
const _kWeekStartsOnMonday = 'settings.weekStartsOnMonday';
const _kLocaleCode = 'settings.localeCode';

/// Loads and persists [AppSettings].
///
/// Exposes an [AsyncValue] so the UI can show a splash while preferences load,
/// then mutate settings synchronously afterwards. Mutations update state
/// optimistically and persist in the background.
@Riverpod(keepAlive: true)
class AppSettingsNotifier extends _$AppSettingsNotifier {
  SharedPreferences? _prefs;

  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    return AppSettings(
      themeMode: _decodeTheme(prefs.getString(_kThemeMode)),
      motionMode: _decodeMotion(prefs.getString(_kMotionMode)),
      dynamicColor: prefs.getBool(_kDynamicColor) ?? true,
      defaultReminderMinutes: prefs.getInt(_kDefaultReminderMinutes),
      weekStartsOnMonday: prefs.getBool(_kWeekStartsOnMonday) ?? true,
      localeCode: prefs.getString(_kLocaleCode),
    );
  }

  void setThemeMode(AppThemeMode mode) => _update(
    (s) => s.copyWith(themeMode: mode),
    (p, s) => p.setString(_kThemeMode, s.themeMode.name),
  );

  void setMotionMode(AppMotionMode mode) => _update(
    (s) => s.copyWith(motionMode: mode),
    (p, s) => p.setString(_kMotionMode, s.motionMode.name),
  );

  void setDynamicColor(bool enabled) => _update(
    (s) => s.copyWith(dynamicColor: enabled),
    (p, s) => p.setBool(_kDynamicColor, s.dynamicColor),
  );

  void setDefaultReminderMinutes(int? minutes) => _update(
    (s) => minutes == null
        ? s.clearDefaultReminder()
        : s.copyWith(defaultReminderMinutes: minutes),
    (p, s) => s.defaultReminderMinutes == null
        ? p.remove(_kDefaultReminderMinutes)
        : p.setInt(_kDefaultReminderMinutes, s.defaultReminderMinutes!),
  );

  void setWeekStartsOnMonday(bool monday) => _update(
    (s) => s.copyWith(weekStartsOnMonday: monday),
    (p, s) => p.setBool(_kWeekStartsOnMonday, s.weekStartsOnMonday),
  );

  /// Sets the UI language override; null clears it (follow system).
  void setLocaleCode(String? code) => _update(
    (s) => code == null ? s.clearLocale() : s.copyWith(localeCode: code),
    (p, s) => s.localeCode == null
        ? p.remove(_kLocaleCode)
        : p.setString(_kLocaleCode, s.localeCode!),
  );

  void _update(
    AppSettings Function(AppSettings) transform,
    Future<bool> Function(SharedPreferences, AppSettings) persist,
  ) {
    final current = state.value;
    final prefs = _prefs;
    if (current == null || prefs == null) return;
    final next = transform(current);
    if (next == current) return;
    state = AsyncData(next);
    persist(prefs, next);
  }

  static AppThemeMode _decodeTheme(String? name) {
    return AppThemeMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => AppThemeMode.system,
    );
  }

  static AppMotionMode _decodeMotion(String? name) {
    return AppMotionMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => AppMotionMode.expressive,
    );
  }
}

/// Convenience accessor: current settings, or defaults while loading.
@Riverpod(keepAlive: true)
AppSettings currentSettings(Ref ref) {
  return ref.watch(appSettingsProvider).value ?? const AppSettings();
}
