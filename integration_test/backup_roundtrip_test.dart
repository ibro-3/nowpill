import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/providers.dart';
import 'package:nowpill/data/repositories/tag_repository.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/recurrence_rule.dart';
import 'package:nowpill/features/shell/feature_placeholders.dart';
import 'package:nowpill/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/disk_file_picker.dart';

/// End-to-end backup round-trip through the real Settings UI.
///
/// Only the platform file dialog is substituted (a D-Bus portal on Linux is
/// not a mockable platform channel); everything above it is production code:
/// Settings → BackupService → ExportService, with real JSON bytes written to
/// and read from real files on disk.
///
/// Journey: seed → export via the Export button → verify the file → mutate
/// the database → import the saved file via the Import button + replace-all
/// confirm → verify every row is restored.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory dir;
  late DiskFilePicker picker;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'settings.motionMode': 'standard'});
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('nowpill_backup_e2e_');
    picker = DiskFilePicker(dir);
    picker.install();
  });

  tearDown(() async {
    picker.uninstall();
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<void> boot(WidgetTester tester) async {
    // Tall viewport keeps the whole Settings page in view (no scrolling).
    tester.view.physicalSize = const Size(420, 2100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const NowPillApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpFor(WidgetTester tester, [int ms = 350]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
  }

  testWidgets('export → mutate → import restores all data', (tester) async {
    final habits = HabitRepository(db);
    final tasks = TaskRepository(db);
    final tags = TagRepository(db);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // --- Seed a representative dataset (all seven tables). ---
    final habitId = await habits.create(
      name: 'Meditate',
      color: 0xFF2DD4A8,
      freezeMode: FreezeMode.manual,
    );
    await habits.update(
      (await habits.getById(
        habitId,
      ))!.copyWith(createdAt: today.subtract(const Duration(days: 10)).toUtc()),
    );
    for (var i = 2; i >= 0; i--) {
      await habits.checkIn(
        habitId,
        formatDate(today.subtract(Duration(days: i))),
      );
    }
    await habits.placeFreeze(
      habitId,
      formatDate(today.subtract(const Duration(days: 3))),
    );

    final taskId = await tasks.create(
      title: 'Water plants',
      dueAt: today,
      recurrence: const RecurrenceRule(unit: RecurrenceUnit.day),
    );
    await tasks.addSubtask(taskId, 'Kitchen');
    final tagId = await tags.create(name: 'home', color: 0xFFFFB454);
    await tasks.setTags(taskId, [tagId]);

    await boot(tester);

    // --- Export via the Settings UI. ---
    await tester.tap(find.byType(SettingsAction));
    await pumpFor(tester, 400);
    await tester.tap(find.text('Export'));
    await pumpFor(tester, 600);
    expect(find.text('Backup exported.'), findsOneWidget);

    // The file exists and carries the full v2 envelope.
    expect(picker.lastSavedPath, isNotNull);
    final exported = File(picker.lastSavedPath!);
    expect(exported.existsSync(), isTrue);
    final envelope =
        jsonDecode(await exported.readAsString()) as Map<String, Object?>;
    expect(envelope['schemaVersion'], 4);
    final data = envelope['data'] as Map<String, Object?>;
    expect(data['habits'], hasLength(1));
    expect(data['checkins'], hasLength(3));
    expect(data['freezes'], hasLength(1));
    expect(data['tasks'], hasLength(1));
    expect(data['subtasks'], hasLength(1));
    expect(data['tags'], hasLength(1));
    expect(data['taskTags'], hasLength(1));
    final habitRow = (data['habits'] as List).single as Map<String, Object?>;
    expect(habitRow['freezeMode'], FreezeMode.manual.index);

    // --- Mutate the database so import has something to replace. ---
    await tasks.create(title: 'Scratch task', dueAt: today);
    await habits.delete(habitId); // Cascades check-ins + freezes.
    expect(await tasks.getAll(), hasLength(2)); // original + scratch
    expect(await habits.getAll(), isEmpty);

    // --- Import the saved file via the Settings UI. ---
    picker.nextPickPath = picker.lastSavedPath;
    await tester.tap(find.text('Import'));
    await pumpFor(tester, 600);

    // Replace-all confirmation summarizes the envelope.
    expect(find.text('Replace all data?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-confirm')));
    await pumpFor(tester, 600);
    expect(find.text('Backup restored.'), findsOneWidget);

    // --- Every row is restored, including v2 freeze data. ---
    final restoredHabits = await habits.getAll();
    expect(restoredHabits, hasLength(1));
    expect(restoredHabits.single.name, 'Meditate');
    expect(restoredHabits.single.freezeMode, FreezeMode.manual);
    expect(await habits.getAllCheckins(), hasLength(3));
    final freezes = await habits.getAllFreezes();
    expect(freezes, hasLength(1));
    expect(
      freezes.single.date,
      formatDate(today.subtract(const Duration(days: 3))),
    );

    final restoredTasks = await tasks.getAll();
    expect(restoredTasks, hasLength(1));
    expect(restoredTasks.single.title, 'Water plants');
    expect(
      restoredTasks.single.recurrenceRule,
      const RecurrenceRule(unit: RecurrenceUnit.day),
    );
    expect(await tasks.getSubtasks(taskId), hasLength(1));
    expect(await tags.getAll(), hasLength(1));
    expect(await db.select(db.taskTags).get(), hasLength(1));
  });

  testWidgets('invalid backup is rejected without touching the data', (
    tester,
  ) async {
    final habits = HabitRepository(db);
    await habits.create(name: 'Keep me', color: 0xFF2DD4A8);

    final bad = File('${dir.path}/bad.json');
    await bad.writeAsString('{"schemaVersion": 99}');

    await boot(tester);
    await tester.tap(find.byType(SettingsAction));
    await pumpFor(tester, 400);

    picker.nextPickPath = bad.path;
    await tester.tap(find.text('Import'));
    await pumpFor(tester, 600);

    // Rejected before the confirm dialog; data untouched.
    expect(find.text('Replace all data?'), findsNothing);
    expect(find.textContaining('Invalid backup:'), findsOneWidget);
    expect(await habits.getAll(), hasLength(1));
    expect((await habits.getAll()).single.name, 'Keep me');
  });
}
