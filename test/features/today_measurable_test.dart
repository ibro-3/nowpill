import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/features/today/today_screen.dart';

import '../data/test_database.dart';
import '../helpers/test_localizations.dart';

/// Measurable habits on the Today dashboard: the stepper logs partial amounts
/// (UI-only progress) and only 100% of the goal counts as done.
void main() {
  late AppDatabase db;
  late HabitRepository habits;

  setUp(() {
    db = createTestDatabase();
    habits = HabitRepository(db);
  });

  Widget wrap() {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: M3ETheme(data: M3EThemeData.light(), child: const TodayScreen()),
      ),
    );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  }

  testWidgets('stepper logs partial progress without completing the day', (
    tester,
  ) async {
    final id = await habits.create(
      name: 'Water',
      color: 0xFF00B4D8,
      targetAmount: 8,
    );
    await pumpScreen(tester);

    expect(find.text('0 / 8'), findsOneWidget);

    // Log 3 units via the + stepper.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(ValueKey('amount-plus-$id')));
      await settle(tester);
    }
    expect(find.text('3 / 8'), findsOneWidget);
    // Partial: the day is NOT done (no strikethrough / goal pill unchecked).
    final checkins = await habits.getCheckins(id);
    expect(checkins.single.amount, 3);

    // Minus removes one.
    await tester.tap(find.byKey(ValueKey('amount-minus-$id')));
    await settle(tester);
    expect(find.text('2 / 8'), findsOneWidget);

    await cleanup(tester);
  });

  testWidgets('reaching the goal completes the day; goal pill toggles', (
    tester,
  ) async {
    final id = await habits.create(
      name: 'Water',
      color: 0xFF00B4D8,
      targetAmount: 3,
    );
    await pumpScreen(tester);

    // Complete via the goal pill (sets the full amount).
    await tester.tap(find.bySemanticsLabel('Complete the goal for Water'));
    await settle(tester);
    expect(find.text('3 / 3'), findsOneWidget);
    expect((await habits.getCheckins(id)).single.amount, 3);

    // The pill now clears the goal.
    await tester.tap(find.bySemanticsLabel('Clear the goal for Water'));
    await settle(tester);
    expect(await habits.getCheckins(id), isEmpty);

    await cleanup(tester);
  });

  testWidgets('minus to zero clears the check-in', (tester) async {
    final id = await habits.create(
      name: 'Water',
      color: 0xFF00B4D8,
      targetAmount: 8,
    );
    await habits.checkIn(id, formatDate(DateTime.now()), amount: 1);
    await pumpScreen(tester);
    expect(find.text('1 / 8'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('amount-minus-$id')));
    await settle(tester);
    expect(await habits.getCheckins(id), isEmpty);

    await cleanup(tester);
  });
}
