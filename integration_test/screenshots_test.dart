import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/chat_repository.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/data/repositories/tag_repository.dart';
import 'package:nowpill/data/repositories/task_list_repository.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/recurrence_rule.dart';
import 'package:nowpill/features/shell/feature_placeholders.dart';
import 'package:nowpill/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Captures placeholder-data screenshots for every page in both themes.
///
/// Run on Linux with:
///   flutter test integration_test/screenshots_test.dart -d linux
/// Raw PNGs land in /tmp/opencode/nowpill-shots; tool/compose_screenshots.py
/// turns each light/dark pair into one diagonally split README asset.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const output = '/tmp/opencode/nowpill-shots';

  Future<AppDatabase> seed() async {
    // Each theme pass gets its own in-memory executor; no two databases share
    // one, so the multi-instance warning does not apply here.
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final habits = HabitRepository(db);
    final water = await habits.create(
      name: 'Drink water',
      color: 0xFF2DD4A8,
      iconKey: 'water',
    );
    final read = await habits.create(
      name: 'Read',
      color: 0xFFFF6B5E,
      iconKey: 'book',
      targetAmount: 10,
    );
    final stretch = await habits.create(
      name: 'Morning stretch',
      color: 0xFFFFB454,
      iconKey: 'spark',
      scheduleType: HabitScheduleType.weekdays,
      weekdays: const [1, 3, 5],
    );
    final journal = await habits.create(
      name: 'Journal',
      color: 0xFF5B8DEF,
      iconKey: 'edit',
    );
    final routine = await habits.createRoutine('Morning', 0xFF2DD4A8);
    await habits.setHabitRoutine(water, routine);
    await habits.setHabitRoutine(stretch, routine);
    await habits.archive(journal);

    for (var i = 13; i >= 0; i--) {
      final date = formatDate(today.subtract(Duration(days: i)));
      if (i % 5 != 2) await habits.checkIn(water, date);
      if (i % 3 != 0) {
        await habits.checkIn(read, date, amount: i.isEven ? 10 : 6);
      }
      if (i.isEven) await habits.checkIn(stretch, date);
    }

    final lists = TaskListRepository(db);
    final listId = await lists.create(name: 'Home', color: 0xFF5B8DEF);
    final tags = TagRepository(db);
    final tagId = await tags.create(name: 'home', color: 0xFFFFB454);
    final tasks = TaskRepository(db);
    final due = await tasks.create(
      title: 'Water the plants',
      notes: 'Kitchen and balcony',
      dueAt: today,
      priority: TaskPriority.high,
      listId: listId,
    );
    await tasks.addSubtask(due, 'Check the soil');
    await tasks.addSubtask(due, 'Fill the watering can');
    await tasks.setTags(due, [tagId]);
    await tasks.create(
      title: 'Weekly groceries',
      notes: 'Oat milk, coffee, avocados',
      dueAt: today.add(const Duration(days: 1)),
      recurrence: const RecurrenceRule(unit: RecurrenceUnit.week),
      listId: listId,
    );
    await tasks.create(title: 'Book the dentist', priority: TaskPriority.low);
    await tasks.create(
      title: 'Take out the recycling',
      dueAt: today.subtract(const Duration(days: 1)),
    );

    final chat = ChatRepository(db);
    await chat.create('Morning walk done — the park was quiet today.');
    await chat.create('Idea: try the new sourdough recipe this weekend.');
    await chat.create('Useful link: https://material.io/design');

    return db;
  }

  Future<void> pumpTheme(WidgetTester tester, String theme) async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({
      'settings.onboardingComplete': true,
      'settings.motionMode': 'standard',
      'settings.dynamicColor': false,
      'settings.themeMode': theme,
      'settings.localeCode': 'en',
    });
    final db = await seed();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const SizedBox.expand(
          child: RepaintBoundary(
            key: Key('screenshot-boundary'),
            child: NowPillApp(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('screenshot-boundary')),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$output/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('captures every page in light and dark', (tester) async {
    tester.view.physicalSize = const Size(840, 1800);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await Directory(output).create(recursive: true);

    for (final theme in ['light', 'dark']) {
      await pumpTheme(tester, theme);
      for (final entry in {
        'Today': 'today',
        'Tasks': 'tasks',
        'Habits': 'habits',
        'Stats': 'stats',
        'To me': 'chat',
      }.entries) {
        await tester.tap(find.text(entry.key).last);
        await settle(tester);
        await capture(tester, '${entry.value}-$theme');
      }
      await tester.tap(find.byType(SettingsAction).first);
      await settle(tester);
      await capture(tester, 'settings-$theme');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tester.takeException(), isNull);
  });
}
