import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/core/settings/app_settings_provider.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/test_database.dart';

/// i18n (Phase 14): the UI language follows the persisted locale override and
/// switching it rebuilds labels live. English is the default; Spanish is the
/// first additional locale.
void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const NowPillApp(),
      ),
    );
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

  testWidgets('defaults to English', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await boot(tester);
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Habits'), findsWidgets);
    await cleanup(tester);
  });

  testWidgets('persisted Spanish locale renders Spanish labels', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'settings.localeCode': 'es'});
    await boot(tester);
    expect(find.text('Hoy'), findsWidgets);
    expect(find.text('Hábitos'), findsWidgets);
    expect(find.text('Today'), findsNothing);
    await cleanup(tester);
  });

  testWidgets('switching the locale live rebuilds labels', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await boot(tester);
    expect(find.text('Today'), findsWidgets);

    final container = ProviderScope.containerOf(
      tester.element(find.text('Today').first),
    );
    container.read(appSettingsProvider.notifier).setLocaleCode('es');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Hoy'), findsWidgets);
    expect(find.text('Today'), findsNothing);

    // Back to system (English default in the test environment).
    container.read(appSettingsProvider.notifier).setLocaleCode(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Today'), findsWidgets);
    await cleanup(tester);
  });
}
