import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/core/settings/app_settings.dart';
import 'package:nowpill/core/settings/app_settings_provider.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/test_database.dart';

/// Regression: the Settings theme picker must drive the M3E theme, not just
/// the ambient Material theme. Previously the expressive host hardcoded
/// `autoTheming: true`, so M3E components always followed the OS brightness
/// and Light/Dark selections appeared to do nothing.
void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  Widget app({required Brightness platform}) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MediaQuery(
        data: MediaQueryData(platformBrightness: platform),
        child: const NowPillApp(),
      ),
    );
  }

  Future<void> boot(WidgetTester tester, {required Brightness platform}) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(platform: platform));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  }

  /// The brightness every M3E component resolves, and the Material theme they
  /// are projected onto — both must agree with the effective mode. The
  /// scaffold background is asserted explicitly: it is a *derived* ThemeData
  /// field, so it exposes any stale merge base (AnimatedTheme lag) that a
  /// colorScheme-only check would miss.
  void expectBrightness(WidgetTester tester, Brightness expected) {
    final context = tester.element(find.text('Today').first);
    final m3e = M3ETheme.of(context);
    final material = Theme.of(context);
    expect(m3e.brightness, expected);
    expect(material.brightness, expected);
    expect(m3e.colorScheme.surface, material.colorScheme.surface);
    expect(
      material.scaffoldBackgroundColor,
      m3e.colorScheme.toColorScheme().surface,
      reason: 'scaffold background must match the active scheme, not lag it',
    );
  }

  // The full matrix: user mode x OS brightness. Dynamic color is disabled so
  // no platform channels are involved and the mint seed scheme is used.
  for (final platform in Brightness.values) {
    for (final mode in AppThemeMode.values) {
      final expected = switch (mode) {
        AppThemeMode.system => platform,
        AppThemeMode.light => Brightness.light,
        AppThemeMode.dark => Brightness.dark,
      };
      testWidgets('mode=${mode.name} on ${platform.name} OS resolves '
          '${expected.name}', (tester) async {
        SharedPreferences.setMockInitialValues({
          'settings.themeMode': mode.name,
          'settings.dynamicColor': false,
        });
        await boot(tester, platform: platform);
        expectBrightness(tester, expected);
        await cleanup(tester);
      });
    }
  }

  testWidgets('changing the mode live re-themes M3E components', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'settings.themeMode': 'system',
      'settings.dynamicColor': false,
    });
    await boot(tester, platform: Brightness.light);
    expectBrightness(tester, Brightness.light);

    final container = ProviderScope.containerOf(
      tester.element(find.text('Today').first),
    );

    // Lock dark while the OS stays light.
    container
        .read(appSettingsProvider.notifier)
        .setThemeMode(AppThemeMode.dark);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expectBrightness(tester, Brightness.dark);

    // Back to system follows the (light) OS again.
    container
        .read(appSettingsProvider.notifier)
        .setThemeMode(AppThemeMode.system);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expectBrightness(tester, Brightness.light);

    await cleanup(tester);
  });

  testWidgets('locked mode survives an OS brightness flip', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.themeMode': 'dark',
      'settings.dynamicColor': false,
    });
    await boot(tester, platform: Brightness.light);
    expectBrightness(tester, Brightness.dark);

    // Simulate the OS switching to light->dark->light while locked to dark.
    await tester.pumpWidget(app(platform: Brightness.dark));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expectBrightness(tester, Brightness.dark);

    await tester.pumpWidget(app(platform: Brightness.light));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expectBrightness(tester, Brightness.dark);

    await cleanup(tester);
  });
}
