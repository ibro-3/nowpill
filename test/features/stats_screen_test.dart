import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/data/repositories/tag_repository.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/features/stats/stats_screen.dart';
import 'package:nowpill/features/stats/widgets/streak_leaderboard.dart';
import 'package:nowpill/features/stats/widgets/tag_donut.dart';
import 'package:nowpill/features/stats/widgets/trend_chart.dart';
import 'package:nowpill/features/stats/widgets/weekly_bars.dart';
import 'package:nowpill/features/today/widgets/floating_pills.dart';

import '../data/test_database.dart';
import '../helpers/test_localizations.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: M3ETheme(data: M3EThemeData.light(), child: child),
      ),
    );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(const StatsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Let the staggered spring entrances run.
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  }

  /// Backdates a habit's creation so check-ins from earlier days count toward
  /// its streak (check-ins before the creation day are legitimately excluded).
  Future<void> backdateHabit(int id, DateTime createdAt) async {
    final habit = await HabitRepository(db).getById(id);
    await HabitRepository(db)
        .update(habit!.copyWith(createdAt: createdAt.toUtc()));
  }

  testWidgets('empty state shows when there is no data', (tester) async {
    await pumpScreen(tester);
    expect(find.byType(FloatingPills), findsOneWidget);
    expect(find.byType(TrendChart), findsNothing);
    await cleanup(tester);
  });

  testWidgets('seeded data renders all four sections', (tester) async {
    final tasks = TaskRepository(db);
    final habits = HabitRepository(db);
    final tags = TagRepository(db);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // A habit with a 3-day streak (today + previous two days).
    final habitId = await habits.create(name: 'Meditate', color: 0xFF2DD4A8);
    await backdateHabit(habitId, today.subtract(const Duration(days: 10)));
    for (var i = 0; i < 3; i++) {
      await habits.checkIn(
        habitId,
        formatDate(today.subtract(Duration(days: i))),
      );
    }
    await habits.create(name: 'Read', color: 0xFF5B8DEF);

    // A completed task tagged "work".
    final tagId = await tags.create(name: 'work', color: 0xFFFFB454);
    final taskId = await tasks.create(title: 'Ship report', dueAt: today);
    await tasks.setTags(taskId, [tagId]);
    await tasks.complete(taskId);

    await pumpScreen(tester);

    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('Weekly summary'), findsOneWidget);
    expect(find.text('Streak leaderboard'), findsOneWidget);
    expect(find.text('Tasks by tag'), findsOneWidget);
    expect(find.byType(TrendChart), findsOneWidget);
    expect(find.byType(WeeklyBars), findsOneWidget);
    expect(find.byType(StreakLeaderboard), findsOneWidget);
    expect(find.byType(TagDonut), findsOneWidget);
    expect(find.byType(FloatingPills), findsNothing);

    // Leaderboard: Meditate (streak 3) ranks above Read (streak 0).
    expect(find.text('Meditate'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('best 3d'), findsOneWidget);

    // Tag donut legend shows the tag and its count.
    expect(find.text('work'), findsOneWidget);

    // Summary tiles: 3 check-ins, 1 task done, best streak 3.
    expect(find.text('check-ins'), findsOneWidget);
    expect(find.text('tasks done'), findsOneWidget);
    expect(find.text('best streak'), findsOneWidget);

    // Regression: every entrance card must actually become visible (the
    // stagger once left the last card stuck at opacity 0). Check the Opacity
    // inside each keyed entrance, not M3E-internal ones.
    for (var i = 0; i < 4; i++) {
      final opacity = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byKey(ValueKey('stats-entrance-$i')),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(
        opacity.opacity,
        greaterThan(0.99),
        reason: 'entrance $i should be fully visible',
      );
    }
    await cleanup(tester);
  });

  testWidgets('leaderboard ranks by current streak', (tester) async {
    final habits = HabitRepository(db);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final gym = await habits.create(name: 'Gym', color: 0xFFFF6B5E);
    final read = await habits.create(name: 'Read', color: 0xFF5B8DEF);
    await backdateHabit(gym, today.subtract(const Duration(days: 10)));
    await backdateHabit(read, today.subtract(const Duration(days: 10)));
    // Read: 5-day streak; Gym: 1-day streak.
    for (var i = 0; i < 5; i++) {
      await habits.checkIn(read, formatDate(today.subtract(Duration(days: i))));
    }
    await habits.checkIn(gym, formatDate(today));

    await pumpScreen(tester);

    final rows = tester
        .widgetList<StreakLeaderboard>(find.byType(StreakLeaderboard))
        .single
        .entries;
    expect(rows.first.name, 'Read');
    expect(rows.first.currentStreak, 5);
    expect(rows[1].name, 'Gym');
    expect(rows[1].currentStreak, 1);
    await cleanup(tester);
  });

  testWidgets('weekly-target habit shows week units on leaderboard', (
    tester,
  ) async {
    final habits = HabitRepository(db);
    await habits.create(
      name: 'Journal',
      color: 0xFF9B6DFF,
      scheduleType: HabitScheduleType.weeklyTarget,
      targetPerWeek: 3,
    );

    await pumpScreen(tester);
    expect(find.text('Journal'), findsOneWidget);
    // Weekly habits render "wk" units, not "d".
    expect(find.text('wk'), findsWidgets);
    await cleanup(tester);
  });
}
