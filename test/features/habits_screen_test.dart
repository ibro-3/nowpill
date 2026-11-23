import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/habit_schedule.dart';
import 'package:nowpill/domain/streak_engine.dart';
import 'package:nowpill/features/habits/habit_detail_screen.dart';
import 'package:nowpill/features/habits/habits_screen.dart';
import 'package:nowpill/features/habits/widgets/habit_heatmap.dart';

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

  Future<void> pumpScreen(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(child));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  }

  testWidgets('empty state shows when no habits', (tester) async {
    await pumpScreen(tester, const HabitsScreen());
    expect(
      find.text('No habits yet. Tap + to build your first streak.'),
      findsOneWidget,
    );
    await cleanup(tester);
  });

  testWidgets('habit appears with name and zero streak', (tester) async {
    final repo = HabitRepository(db);
    await repo.create(name: 'Meditate', color: 0xFF2DD4A8);

    await pumpScreen(tester, const HabitsScreen());
    expect(find.text('Meditate'), findsOneWidget);
    expect(find.text('Every day'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('check-in updates streak to 1', (tester) async {
    final repo = HabitRepository(db);
    final id = await repo.create(name: 'Read', color: 0xFF5B8DEF);

    await pumpScreen(tester, const HabitsScreen());
    await tester.tap(find.bySemanticsLabel('Check in Read'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final checkins = await repo.getCheckins(id);
    expect(checkins.length, 1);
    expect(checkins.single.date, formatDate(DateTime.now()));
    await cleanup(tester);
  });

  testWidgets('check-in is reversible', (tester) async {
    final repo = HabitRepository(db);
    final id = await repo.create(name: 'Walk', color: 0xFF4CB944);
    await repo.checkIn(id, formatDate(DateTime.now()));

    await pumpScreen(tester, const HabitsScreen());
    await tester.tap(find.bySemanticsLabel('Undo check-in for Walk'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final checkins = await repo.getCheckins(id);
    expect(checkins, isEmpty);
    await cleanup(tester);
  });

  testWidgets('detail screen shows heatmap and stats', (tester) async {
    final repo = HabitRepository(db);
    final id = await repo.create(name: 'Hydrate', color: 0xFF00B4D8);
    await repo.checkIn(id, formatDate(DateTime.now()));

    await pumpScreen(tester, HabitDetailScreen(habitId: id));
    expect(find.text('Current streak'), findsOneWidget);
    expect(find.text('Best streak'), findsOneWidget);
    expect(find.text('Freeze tokens'), findsOneWidget);
    expect(find.byType(HabitHeatmap), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('backfill adds a check-in for a past day', (tester) async {
    final repo = HabitRepository(db);
    final now = DateTime.now();
    // Create the habit 10 days ago so backfill days are within its lifetime.
    final id = await repo.create(name: 'Journal', color: 0xFF9B6DFF);
    await db
        .update(db.habits)
        .replace(
          (await repo.getById(id))!.copyWith(
            createdAt: now.subtract(const Duration(days: 10)).toUtc(),
          ),
        );

    await pumpScreen(tester, HabitDetailScreen(habitId: id));
    await tester.pump(const Duration(milliseconds: 400));

    // Tap yesterday's heatmap cell to backfill.
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final cellKey = ValueKey('heatmap-${formatDate(yesterday)}');
    await tester.ensureVisible(find.byKey(cellKey));
    await tester.pump();
    await tester.tap(find.byKey(cellKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final checkins = await repo.getCheckins(id);
    expect(checkins.any((c) => c.date == formatDate(yesterday)), isTrue);

    // Tapping again removes it (toggle).
    await tester.tap(find.byKey(cellKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final after = await repo.getCheckins(id);
    expect(after.any((c) => c.date == formatDate(yesterday)), isFalse);
    await cleanup(tester);
  });

  testWidgets('freeze token renders in heatmap after a missed day', (
    tester,
  ) async {
    final repo = HabitRepository(db);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Build a 7-day streak ending 2 days ago, miss yesterday (earns a token on
    // day 7, then freezes yesterday). Create habit 12 days ago.
    final id = await repo.create(name: 'Stretch', color: 0xFFEF5DA8);
    await db
        .update(db.habits)
        .replace(
          (await repo.getById(id))!.copyWith(
            createdAt: today.subtract(const Duration(days: 12)).toUtc(),
          ),
        );
    for (var i = 8; i >= 2; i--) {
      await repo.checkIn(id, formatDate(today.subtract(Duration(days: i))));
    }
    // yesterday (i=1) intentionally missed -> should be frozen.

    await pumpScreen(tester, HabitDetailScreen(habitId: id));
    await tester.pump(const Duration(milliseconds: 400));

    // The streak engine should have frozen yesterday.
    final checkins = await repo.getCheckins(id);
    expect(checkins.length, 7);
    // Verify the heatmap shows a frozen cell (ac_unit icon).
    expect(find.byIcon(M3EIcons.ac_unit), findsWidgets);
    await cleanup(tester);
  });

  testWidgets('weekly-target heatmap never marks individual days missed', (
    tester,
  ) async {
    final repo = HabitRepository(db);
    final id = await repo.create(
      name: 'Journal',
      color: 0xFF9B6DFF,
      scheduleType: HabitScheduleType.weeklyTarget,
      targetPerWeek: 3,
    );
    await db
        .update(db.habits)
        .replace(
          (await repo.getById(id))!.copyWith(
            createdAt: DateTime.now()
                .subtract(const Duration(days: 14))
                .toUtc(),
          ),
        );

    await pumpScreen(tester, HabitDetailScreen(habitId: id));
    await tester.pump(const Duration(milliseconds: 400));

    // Only the 3 wallet slots carry the snowflake icon — no day cell is
    // frozen, and no unchecked day shows the missed-day cross.
    expect(find.byIcon(M3EIcons.ac_unit), findsNWidgets(3));
    expect(find.byIcon(M3EIcons.close), findsNothing);
    await cleanup(tester);
  });

  testWidgets('weekly freeze renders on the frozen week’s days', (
    tester,
  ) async {
    final repo = HabitRepository(db);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = startOfWeek(today);
    final id = await repo.create(
      name: 'Review',
      color: 0xFF00B4D8,
      scheduleType: HabitScheduleType.weeklyTarget,
      targetPerWeek: 1,
    );
    await db
        .update(db.habits)
        .replace(
          (await repo.getById(id))!.copyWith(
            createdAt: thisMonday.subtract(const Duration(days: 42)).toUtc(),
          ),
        );
    // Four completed weeks earn a token; the fifth week is missed and frozen.
    for (var w = 5; w >= 2; w--) {
      await repo.checkIn(
        id,
        formatDate(thisMonday.subtract(Duration(days: 7 * w))),
      );
    }

    await pumpScreen(tester, HabitDetailScreen(habitId: id));
    await tester.pump(const Duration(milliseconds: 400));

    // The engine must have frozen last week (token earned over weeks 1-4).
    final streak = replayStreak(
      schedule: const HabitSchedule.weeklyTarget(1),
      checkins: (await repo.getCheckins(id)).map((c) => c.date).toSet(),
      today: today,
      startDate: thisMonday.subtract(const Duration(days: 42)),
    );
    expect(streak.tokens, 0);
    expect(streak.frozenDates, {
      formatDate(thisMonday.subtract(const Duration(days: 7))),
    });

    // Every visible unchecked day of the frozen week renders ❄, plus the 3
    // wallet slots.
    final frozenWeekMonday = thisMonday.subtract(const Duration(days: 7));
    var visibleFrozenDays = 0;
    for (var i = 0; i < 7; i++) {
      final day = frozenWeekMonday.add(Duration(days: i));
      if (day.month == today.month &&
          find
              .byKey(ValueKey('heatmap-${formatDate(day)}'))
              .evaluate()
              .isNotEmpty) {
        visibleFrozenDays++;
      }
    }
    expect(visibleFrozenDays, greaterThan(0));
    expect(find.byIcon(M3EIcons.ac_unit), findsNWidgets(3 + visibleFrozenDays));
    await cleanup(tester);
  });
}
