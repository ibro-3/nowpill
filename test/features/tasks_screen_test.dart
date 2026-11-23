import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/recurrence_rule.dart';
import 'package:nowpill/features/tasks/tasks_screen.dart';

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
    await tester.pumpWidget(wrap(const TasksScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  // Drift keeps stream-cache timers alive after listeners cancel; they must be
  // flushed and the database closed inside the test's fake-async zone, or the
  // test fails with "pending timers" at teardown.
  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  }

  testWidgets('empty state shows for Today filter', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Nothing due today. Enjoy the calm!'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('created task appears in All filter', (tester) async {
    final repo = TaskRepository(db);
    await repo.create(title: 'Buy groceries');

    await pumpScreen(tester);
    await tester.tap(find.text('All').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Buy groceries'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('tapping check pill completes a task', (tester) async {
    final repo = TaskRepository(db);
    final id = await repo.create(title: 'Finish report');

    await pumpScreen(tester);
    await tester.tap(find.text('All').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.bySemanticsLabel('Mark complete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final task = await repo.getById(id);
    expect(task!.completedAt, isNotNull);
    await cleanup(tester);
  });

  testWidgets('completing a recurring task spawns the next occurrence', (
    tester,
  ) async {
    final repo = TaskRepository(db);
    await repo.create(
      title: 'Daily standup',
      dueAt: DateTime.now().toUtc(),
      recurrence: const RecurrenceRule(unit: RecurrenceUnit.day),
    );

    await pumpScreen(tester);
    expect(find.text('Daily standup'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Mark complete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final all = await db.select(db.tasks).get();
    expect(all.length, 2);
    expect(all.where((t) => t.completedAt != null).length, 1);
    expect(all.where((t) => t.completedAt == null).length, 1);
    await cleanup(tester);
  });

  testWidgets('Done filter shows completed tasks', (tester) async {
    final repo = TaskRepository(db);
    final id = await repo.create(title: 'Archived item');
    await repo.complete(id);

    await pumpScreen(tester);
    await tester.tap(find.text('Done').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Archived item'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('editor sheet creates a task with title', (tester) async {
    // Tall viewport so the editor's save button is visible without scrolling
    // the sheet's nested scrollables.
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(const TasksScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.bySemanticsLabel('New task'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(M3ETextField).first, 'Water plants');
    await tester.pump();
    await tester.tap(find.text('Add task'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    final tasks = await db.select(db.tasks).get();
    expect(tasks.any((t) => t.title == 'Water plants'), isTrue);
    await cleanup(tester);
  });
}
