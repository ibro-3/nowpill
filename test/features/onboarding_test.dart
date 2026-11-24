import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/test_database.dart';

/// First-run gate: fresh installs see the intro, starters can be seeded, and
/// dismissing it (or skipping) lands on Today exactly once.
void main() {
  Future<void> boot(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> cleanup(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  }

  testWidgets('fresh install seeds selected starter habits and enters Today', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = createTestDatabase();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const NowPillApp(),
      ),
    );
    await boot(tester);

    expect(find.text('Make today count'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await boot(tester);
    expect(find.text('Start with a few habits'), findsOneWidget);

    // Water and Read start selected; add Move too.
    await tester.tap(find.byKey(const ValueKey('starter-move')));
    await boot(tester);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await boot(tester);

    expect(find.text('Today'), findsWidgets);
    final habits = await db.select(db.habits).get();
    expect(habits, hasLength(3));

    await cleanup(tester, db);
  });

  testWidgets('skip enters Today without seeding anything', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = createTestDatabase();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const NowPillApp(),
      ),
    );
    await boot(tester);

    await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
    await boot(tester);

    expect(find.text('Today'), findsWidgets);
    expect(await db.select(db.habits).get(), isEmpty);

    await cleanup(tester, db);
  });
}
