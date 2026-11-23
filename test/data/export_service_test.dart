import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/export/export_service.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/tag_repository.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/recurrence_rule.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late ExportService service;

  setUp(() {
    db = createTestDatabase();
    service = ExportService(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seed() async {
    final tasks = TaskRepository(db);
    final habits = HabitRepository(db);
    final tags = TagRepository(db);

    final tagId = await tags.create(name: 'health', color: 0xFF2DD4A8);
    final taskId = await tasks.create(
      title: 'Morning run',
      notes: '5k',
      dueAt: DateTime.utc(2026, 11, 22, 7),
      priority: TaskPriority.medium,
      recurrence: const RecurrenceRule(unit: RecurrenceUnit.day),
    );
    await tasks.addSubtask(taskId, 'Warm up');
    await tasks.setTags(taskId, [tagId]);

    final habitId = await habits.create(
      name: 'Hydrate',
      color: 0xFF2DD4A8,
      scheduleType: HabitScheduleType.weekdays,
      weekdays: [1, 2, 3, 4, 5],
    );
    await habits.checkIn(habitId, '2026-11-20');
    await habits.checkIn(habitId, '2026-11-21');
  }

  group('export', () {
    test('produces a valid versioned envelope', () async {
      await seed();
      final json = await service.exportToString();
      final decoded = jsonDecode(json) as Map<String, Object?>;
      expect(decoded['schemaVersion'], kExportSchemaVersion);
      expect(decoded['exportedAt'], isA<int>());
      final data = decoded['data'] as Map<String, Object?>;
      expect((data['tasks'] as List).length, 1);
      expect((data['subtasks'] as List).length, 1);
      expect((data['tags'] as List).length, 1);
      expect((data['taskTags'] as List).length, 1);
      expect((data['habits'] as List).length, 1);
      expect((data['checkins'] as List).length, 2);
    });
  });

  group('import round-trip', () {
    test('restores all rows into a fresh database', () async {
      await seed();
      final json = await service.exportToString();

      final fresh = createTestDatabase();
      addTearDown(fresh.close);
      final freshService = ExportService(fresh);
      await freshService.importFromString(json);

      expect(await fresh.select(fresh.tasks).get(), hasLength(1));
      expect(await fresh.select(fresh.subtasks).get(), hasLength(1));
      expect(await fresh.select(fresh.tags).get(), hasLength(1));
      expect(await fresh.select(fresh.taskTags).get(), hasLength(1));
      expect(await fresh.select(fresh.habits).get(), hasLength(1));
      expect(await fresh.select(fresh.habitCheckins).get(), hasLength(2));

      final task = (await fresh.select(fresh.tasks).get()).single;
      expect(task.title, 'Morning run');
      expect(task.dueAt, DateTime.utc(2026, 11, 22, 7));
      expect(
        task.recurrenceRule,
        const RecurrenceRule(unit: RecurrenceUnit.day),
      );

      final habit = (await fresh.select(fresh.habits).get()).single;
      expect(habit.weekdays, [1, 2, 3, 4, 5]);
    });

    test('replace-all removes pre-existing data', () async {
      await seed();
      final json = await service.exportToString();

      // Add extra data that should be wiped on import.
      await TaskRepository(db).create(title: 'Should be removed');
      expect(await db.select(db.tasks).get(), hasLength(2));

      await service.importFromString(json);
      final tasks = await db.select(db.tasks).get();
      expect(tasks, hasLength(1));
      expect(tasks.single.title, 'Morning run');
    });

    test('preserves explicit ids and links', () async {
      await seed();
      final json = await service.exportToString();
      final fresh = createTestDatabase();
      addTearDown(fresh.close);
      await ExportService(fresh).importFromString(json);

      final task = (await fresh.select(fresh.tasks).get()).single;
      final link = (await fresh.select(fresh.taskTags).get()).single;
      expect(link.taskId, task.id);
      final subtask = (await fresh.select(fresh.subtasks).get()).single;
      expect(subtask.taskId, task.id);
    });
  });

  group('parseEnvelope (validate without writing)', () {
    test('returns the envelope without touching the database', () async {
      await seed();
      final json = await service.exportToString();
      final before = await db.select(db.tasks).get();

      final envelope = service.parseEnvelope(json);
      expect(envelope.habits, hasLength(1));
      expect(envelope.checkins, hasLength(2));
      expect(envelope.tasks, hasLength(1));

      final after = await db.select(db.tasks).get();
      expect(after.length, before.length);
    });

    test('throws on invalid payloads', () {
      expect(
        () => service.parseEnvelope('not json'),
        throwsA(isA<ImportFormatException>()),
      );
      expect(
        () => service.parseEnvelope('{"schemaVersion": 999}'),
        throwsA(isA<ImportFormatException>()),
      );
    });
  });

  group('import validation', () {
    test('rejects invalid JSON', () async {
      expect(
        () => service.importFromString('not json'),
        throwsA(isA<ImportFormatException>()),
      );
    });

    test('rejects unsupported schema version', () async {
      final payload = jsonEncode({
        'schemaVersion': 999,
        'exportedAt': 0,
        'data': {
          'tasks': <Object?>[],
          'subtasks': <Object?>[],
          'tags': <Object?>[],
          'taskTags': <Object?>[],
          'habits': <Object?>[],
          'checkins': <Object?>[],
        },
      });
      expect(
        () => service.importFromString(payload),
        throwsA(isA<ImportFormatException>()),
      );
    });

    test('rejects missing data lists', () async {
      final payload = jsonEncode({
        'schemaVersion': kExportSchemaVersion,
        'exportedAt': 0,
        'data': {'tasks': <Object?>[]},
      });
      expect(
        () => service.importFromString(payload),
        throwsA(isA<ImportFormatException>()),
      );
    });

    test('failed import leaves database untouched', () async {
      await seed();
      final before = await db.select(db.tasks).get();
      expect(
        () => service.importFromString('{"schemaVersion": 999}'),
        throwsA(isA<ImportFormatException>()),
      );
      final after = await db.select(db.tasks).get();
      expect(after.length, before.length);
    });
  });
}
