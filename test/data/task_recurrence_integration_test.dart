import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/recurrence_rule.dart';

import 'test_database.dart';

/// Verifies the task repository's completion flow uses the real recurrence
/// engine by default (no injected hook).
void main() {
  late AppDatabase db;
  late TaskRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = TaskRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('daily recurring task spawns tomorrow via the real engine', () async {
    final id = await repo.create(
      title: 'Daily',
      dueAt: DateTime.utc(2026, 11, 22, 9),
      recurrence: const RecurrenceRule(unit: RecurrenceUnit.day),
    );
    final spawnedId = await repo.complete(id);
    expect(spawnedId, isNotNull);
    final spawned = await repo.getById(spawnedId!);
    expect(spawned!.dueAt, DateTime.utc(2026, 11, 23, 9));
    expect(spawned.completedAt, isNull);
  });

  test('monthly recurring task clamps month-end through the repo', () async {
    final id = await repo.create(
      title: 'Monthly report',
      dueAt: DateTime.utc(2026, 1, 31),
      recurrence: const RecurrenceRule(unit: RecurrenceUnit.month),
    );
    final spawnedId = await repo.complete(id);
    final spawned = await repo.getById(spawnedId!);
    expect(spawned!.dueAt, DateTime.utc(2026, 2, 28));
  });

  test('weekly recurring task keeps weekday', () async {
    // 2026-11-22 is a Sunday.
    final id = await repo.create(
      title: 'Weekly review',
      dueAt: DateTime.utc(2026, 11, 22),
      recurrence: const RecurrenceRule(unit: RecurrenceUnit.week),
    );
    final spawnedId = await repo.complete(id);
    final spawned = await repo.getById(spawnedId!);
    expect(spawned!.dueAt, DateTime.utc(2026, 11, 29));
    expect(spawned.dueAt!.weekday, DateTime.sunday);
  });

  test('one-off task does not spawn', () async {
    final id = await repo.create(
      title: 'One-off',
      dueAt: DateTime.utc(2026, 11, 22),
    );
    expect(await repo.complete(id), isNull);
  });

  test('recurring task without due date does not spawn', () async {
    final id = await repo.create(
      title: 'No anchor',
      recurrence: const RecurrenceRule(unit: RecurrenceUnit.day),
    );
    expect(await repo.complete(id), isNull);
  });
}
