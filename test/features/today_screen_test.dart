import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/features/today/today_screen.dart';
import 'package:nowpill/features/today/widgets/confetti_overlay.dart';
import 'package:nowpill/features/today/widgets/floating_pills.dart';
import 'package:nowpill/features/today/widgets/today_progress_ring.dart';

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
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(const TodayScreen()));
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

  testWidgets('empty state shows floating pills and ring at zero', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.byType(FloatingPills), findsOneWidget);
    expect(find.text('A clear day ahead'), findsOneWidget);
    expect(find.text('0/0'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('sections render overdue, habits, and due-today', (tester) async {
    final tasks = TaskRepository(db);
    final habits = HabitRepository(db);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    await tasks.create(
      title: 'Pay rent',
      dueAt: today.subtract(const Duration(days: 2)),
    );
    await tasks.create(title: 'Buy groceries', dueAt: today);
    await habits.create(name: 'Meditate', color: 0xFF2DD4A8);

    await pumpScreen(tester);

    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Habits'), findsOneWidget);
    expect(find.text('Due today'), findsOneWidget);
    expect(find.text('Pay rent'), findsOneWidget);
    expect(find.text('Buy groceries'), findsOneWidget);
    expect(find.text('Meditate'), findsOneWidget);
    expect(find.text('0/3'), findsOneWidget);
    expect(find.text('3 to go · 0 done'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('mixed completion updates ring then celebrates', (tester) async {
    final tasks = TaskRepository(db);
    final habits = HabitRepository(db);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final taskId = await tasks.create(title: 'Buy groceries', dueAt: today);
    final habitId = await habits.create(name: 'Meditate', color: 0xFF2DD4A8);

    await pumpScreen(tester);
    expect(find.text('0/2'), findsOneWidget);
    expect(find.text('All done for today!'), findsNothing);

    // Complete the task.
    await tester.tap(find.bySemanticsLabel('Mark complete'));
    await settle(tester);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('Done today'), findsOneWidget);
    expect(find.text('All done for today!'), findsNothing);

    // Check in the habit -> all done, celebration fires.
    await tester.tap(find.bySemanticsLabel('Check in Meditate'));
    await settle(tester);
    expect(find.text('2/2'), findsOneWidget);
    expect(find.text('all done!'), findsOneWidget);
    expect(find.text('All done for today!'), findsOneWidget);
    expect(find.text('Everything done — enjoy your day!'), findsOneWidget);
    final confetti = tester.widget<ConfettiOverlay>(
      find.byType(ConfettiOverlay),
    );
    expect(confetti.playToken, greaterThan(0));
    expect(
      tester
          .widget<TodayProgressRing>(find.byType(TodayProgressRing))
          .celebrate,
      isTrue,
    );

    // Undo the habit check-in -> celebration stops.
    await tester.tap(find.bySemanticsLabel('Undo check-in for Meditate'));
    await settle(tester);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('All done for today!'), findsNothing);

    // Reopen the task from the Done section.
    await tester.tap(find.bySemanticsLabel('Mark incomplete'));
    await settle(tester);
    expect(find.text('0/2'), findsOneWidget);
    expect(find.text('Done today'), findsNothing);

    final checkins = await habits.getCheckins(habitId);
    expect(checkins, isEmpty);
    final task = await tasks.getById(taskId);
    expect(task!.completedAt, isNull);
    await cleanup(tester);
  });

  testWidgets('overdue task stays until completed', (tester) async {
    final tasks = TaskRepository(db);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await tasks.create(
      title: 'Pay rent',
      dueAt: today.subtract(const Duration(days: 2)),
    );

    await pumpScreen(tester);
    expect(find.text('Overdue'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Mark complete'));
    await settle(tester);

    expect(find.text('Overdue'), findsNothing);
    expect(find.text('Done today'), findsOneWidget);
    expect(find.text('All done for today!'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('quick-add creates a task due today', (tester) async {
    await pumpScreen(tester);
    expect(find.text('A clear day ahead'), findsOneWidget);

    await tester.enterText(find.byType(M3ETextField), 'Water the plants');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    final tasks = await db.select(db.tasks).get();
    expect(tasks.length, 1);
    expect(tasks.single.title, 'Water the plants');
    expect(formatDate(tasks.single.dueAt!), formatDate(DateTime.now()));
    expect(tasks.single.completedAt, isNull);

    // Field cleared after submit; the new task shows in Due today.
    final field = tester.widget<M3ETextField>(find.byType(M3ETextField));
    expect(field.controller!.text, isEmpty);
    expect(find.text('Water the plants'), findsOneWidget);
    expect(find.text('Due today'), findsOneWidget);
    expect(find.text('0/1'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('weekly-target habit appears every day', (tester) async {
    final habits = HabitRepository(db);
    final now = DateTime.now();
    // Ensure today is NOT a scheduled weekday for a weekdays habit, but the
    // weekly-target habit must still appear.
    await habits.create(
      name: 'Journal',
      color: 0xFF9B6DFF,
      scheduleType: HabitScheduleType.weeklyTarget,
      targetPerWeek: 3,
    );
    final otherDay = (now.weekday % 7) + 1; // a weekday that is not today
    await habits.create(
      name: 'Sauna',
      color: 0xFFFF6B5E,
      scheduleType: HabitScheduleType.weekdays,
      weekdays: [otherDay],
    );

    await pumpScreen(tester);
    expect(find.text('Journal'), findsOneWidget);
    expect(find.text('Sauna'), findsNothing);
    await cleanup(tester);
  });
}
