import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/features/habits/habit_detail_screen.dart';
import 'package:nowpill/features/habits/widgets/habit_insights_card.dart';

import '../data/test_database.dart';
import '../helpers/test_localizations.dart';

/// v0.9: per-habit completion insights on the detail screen.
void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: M3ETheme(data: M3EThemeData.light(), child: child),
      ),
    );
  }

  Future<void> pumpScreen(WidgetTester tester, int habitId) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(HabitDetailScreen(habitId: habitId)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  }

  String day(int offset) {
    final now = DateTime.now();
    return formatDate(DateTime(now.year, now.month, now.day - offset));
  }

  testWidgets('shows completion rate, numerator, and best day', (tester) async {
    final repo = HabitRepository(db);
    final now = DateTime.now();
    final id = await repo.create(
      name: 'Meditate',
      color: 0xFF2DD4A8,
      createdAt: DateTime(now.year, now.month, now.day - 9).toUtc(),
    );
    for (var i = 0; i < 4; i++) {
      await repo.checkIn(id, day(i));
    }

    await pumpScreen(tester, id);
    expect(find.byType(HabitInsightsCard), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('4 of 10 days'), findsOneWidget);
    expect(find.textContaining('Best day:'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('range toggle switches between 30 and 90 days', (tester) async {
    final repo = HabitRepository(db);
    final now = DateTime.now();
    final id = await repo.create(
      name: 'Read',
      color: 0xFF5B8DEF,
      createdAt: DateTime(now.year, now.month, now.day - 59).toUtc(),
    );
    // Two check-ins inside 30 days, three more in days 31–60.
    for (var i in [0, 1, 35, 40, 55]) {
      await repo.checkIn(id, day(i));
    }

    await pumpScreen(tester, id);
    expect(find.text('2 of 30 days'), findsOneWidget);

    await tester.tap(find.text('90 days'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('5 of 60 days'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('quit habits show clean days and relapses', (tester) async {
    final repo = HabitRepository(db);
    final now = DateTime.now();
    final id = await repo.create(
      name: 'No smoking',
      color: 0xFFFFB454,
      kind: HabitKind.quit,
      createdAt: DateTime(now.year, now.month, now.day - 4).toUtc(),
    );
    await repo.logRelapse(id, day(1));

    await pumpScreen(tester, id);
    expect(find.textContaining('clean days'), findsOneWidget);
    expect(find.text('Relapses: 1'), findsOneWidget);
    expect(find.textContaining('Best day:'), findsNothing);
    await cleanup(tester);
  });
}
