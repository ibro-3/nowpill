import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/features/habits/habit_detail_screen.dart';
import 'package:nowpill/features/habits/widgets/year_heatmap.dart';

import '../data/test_database.dart';
import '../helpers/test_localizations.dart';

/// Year heatmap: month/year toggle on the detail screen, 53-week grid, and
/// tap-backfill through the same flow as the month grid.
void main() {
  late AppDatabase db;
  late HabitRepository habits;
  late int habitId;

  setUp(() async {
    db = createTestDatabase();
    habits = HabitRepository(db);
    habitId = await habits.create(name: 'Read', color: 0xFF5B8DEF);
    // Backdate creation so recent days are within the habit's lifetime
    // (backfill requires day >= createdAt day).
    final created = DateTime.now().subtract(const Duration(days: 400));
    await habits.update(
      (await habits.getById(habitId))!.copyWith(createdAt: created.toUtc()),
    );
  });

  Widget wrap() {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: M3ETheme(
          data: M3EThemeData.light(),
          child: HabitDetailScreen(habitId: habitId),
        ),
      ),
    );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  }

  testWidgets('toggle switches between month and year grids', (tester) async {
    await pumpScreen(tester);
    expect(find.byType(YearHeatmap), findsNothing);
    expect(find.text('Last 12 months'), findsNothing);

    await tester.tap(find.text('Year').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(YearHeatmap), findsOneWidget);
    expect(find.text('Last 12 months'), findsOneWidget);

    await tester.tap(find.text('Month').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(YearHeatmap), findsNothing);
    await cleanup(tester);
  });

  testWidgets('year grid backfills a recent day on tap', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Year').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final key = formatDate(yesterday);
    final cell = find.byKey(ValueKey('year-heatmap-$key'));
    expect(cell, findsOneWidget);
    await tester.tap(cell);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final checkins = await habits.getCheckins(habitId);
    expect(checkins.map((c) => c.date), contains(key));
    await cleanup(tester);
  });

  testWidgets('old days are not backfillable (>30 days)', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Year').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final old = DateTime.now().subtract(const Duration(days: 60));
    expect(
      find.byKey(ValueKey('year-heatmap-${formatDate(old)}')),
      findsNothing, // rendered, but without the tappable key
    );
    await cleanup(tester);
  });
}
