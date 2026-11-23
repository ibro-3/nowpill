import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/data/repositories/tag_repository.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/features/today/widgets/quick_add_bar.dart';

import '../data/test_database.dart';
import '../helpers/test_localizations.dart';

/// Natural-language quick-add: live preview chips + submit creates the parsed
/// task (due date, reminder, recurrence, auto-created tags, priority).
void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
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
          child: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: QuickAddBar(),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpBar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  }

  testWidgets('plain text: no chips, task due today (pre-v0.4 behavior)', (
    tester,
  ) async {
    await pumpBar(tester);
    await tester.enterText(find.byType(EditableText).first, 'Buy milk');
    await tester.pump();
    expect(find.textContaining('Due'), findsNothing);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final tasks = await TaskRepository(db).getAll();
    expect(tasks.single.title, 'Buy milk');
    final now = DateTime.now();
    expect(tasks.single.dueAt!.toLocal().day, now.day);
    await cleanup(tester);
  });

  testWidgets('preview chips appear for a parsed phrase', (tester) async {
    await pumpBar(tester);
    await tester.enterText(
      find.byType(EditableText).first,
      'Call dentist tomorrow at 5pm #health !high',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('Due'), findsOneWidget);
    expect(find.textContaining('Remind 17:00'), findsOneWidget);
    expect(find.text('#health'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    await cleanup(tester);
  });

  testWidgets('submit creates the parsed task with reminder + tag + priority', (
    tester,
  ) async {
    await pumpBar(tester);
    await tester.enterText(
      find.byType(EditableText).first,
      'Call dentist tomorrow at 5pm #health !high',
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final tasks = await TaskRepository(db).getAll();
    final task = tasks.single;
    expect(task.title, 'Call dentist');
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final due = task.dueAt!.toLocal();
    expect(due.day, tomorrow.day);
    expect(due.hour, 17);
    expect(task.reminderAt, isNotNull);
    expect(task.priority, TaskPriority.high);

    final tags = await TagRepository(db).getAll();
    expect(tags.single.name, 'health');
    final links = await TaskRepository(db).getAllTaskTags();
    expect(links.single.tagId, tags.single.id);
    await cleanup(tester);
  });

  testWidgets('recurrence phrase creates a recurring task', (tester) async {
    await pumpBar(tester);
    await tester.enterText(
      find.byType(EditableText).first,
      'Water plants every 2 weeks #home',
    );
    await tester.pump();
    expect(find.textContaining('Repeats'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final task = (await TaskRepository(db).getAll()).single;
    expect(task.title, 'Water plants');
    expect(task.recurrenceRule!.unit, RecurrenceUnit.week);
    expect(task.recurrenceRule!.interval, 2);
    await cleanup(tester);
  });

  testWidgets('existing tag is reused, not duplicated', (tester) async {
    await TagRepository(db).create(name: 'home', color: 1);
    await pumpBar(tester);
    await tester.enterText(find.byType(EditableText).first, 'Buy paint #home');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final tags = await TagRepository(db).getAll();
    expect(tags, hasLength(1));
    final links = await TaskRepository(db).getAllTaskTags();
    expect(links.single.tagId, tags.single.id);
    await cleanup(tester);
  });
}
