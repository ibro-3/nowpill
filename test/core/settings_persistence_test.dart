import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/core/settings/app_settings.dart';
import 'package:nowpill/core/settings/app_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> loadContainer() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Wait for the async prefs load to complete.
    await container.read(appSettingsProvider.future);
    return container;
  }

  test('defaults: no reminder, Monday week start', () async {
    final container = await loadContainer();
    final settings = container.read(currentSettingsProvider);
    expect(settings.defaultReminderMinutes, isNull);
    expect(settings.weekStartsOnMonday, isTrue);
    expect(settings.motionMode, AppMotionMode.expressive);
  });

  test(
    'onboarding starts incomplete and the dismissed flag persists',
    () async {
      final container = await loadContainer();
      expect(
        container.read(currentSettingsProvider).onboardingComplete,
        isFalse,
      );

      container.read(appSettingsProvider.notifier).setOnboardingComplete(true);
      expect(
        container.read(currentSettingsProvider).onboardingComplete,
        isTrue,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings.onboardingComplete'), isTrue);

      final reloaded = ProviderContainer();
      addTearDown(reloaded.dispose);
      await reloaded.read(appSettingsProvider.future);
      expect(reloaded.read(currentSettingsProvider).onboardingComplete, isTrue);
    },
  );

  test('default reminder persists and reloads', () async {
    final container = await loadContainer();
    container.read(appSettingsProvider.notifier).setDefaultReminderMinutes(540);
    expect(container.read(currentSettingsProvider).defaultReminderMinutes, 540);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('settings.defaultReminderMinutes'), 540);

    // A fresh container reads the persisted value.
    final reloaded = ProviderContainer();
    addTearDown(reloaded.dispose);
    await reloaded.read(appSettingsProvider.future);
    expect(reloaded.read(currentSettingsProvider).defaultReminderMinutes, 540);
  });

  test('clearing the default reminder removes the key', () async {
    final container = await loadContainer();
    final notifier = container.read(appSettingsProvider.notifier);
    notifier.setDefaultReminderMinutes(540);
    notifier.setDefaultReminderMinutes(null);
    expect(
      container.read(currentSettingsProvider).defaultReminderMinutes,
      isNull,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('settings.defaultReminderMinutes'), isFalse);
  });

  test('week start persists and reloads', () async {
    final container = await loadContainer();
    container.read(appSettingsProvider.notifier).setWeekStartsOnMonday(false);
    expect(container.read(currentSettingsProvider).weekStartsOnMonday, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('settings.weekStartsOnMonday'), isFalse);

    final reloaded = ProviderContainer();
    addTearDown(reloaded.dispose);
    await reloaded.read(appSettingsProvider.future);
    expect(reloaded.read(currentSettingsProvider).weekStartsOnMonday, isFalse);
  });

  test(
    'copyWith preserves nullable reminder; clearDefaultReminder nulls it',
    () {
      const s = AppSettings(defaultReminderMinutes: 480);
      expect(
        s.copyWith(themeMode: AppThemeMode.dark).defaultReminderMinutes,
        480,
      );
      expect(s.clearDefaultReminder().defaultReminderMinutes, isNull);
      expect(s.clearDefaultReminder().themeMode, AppThemeMode.system);
    },
  );
}
