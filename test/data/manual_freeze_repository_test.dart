import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/export/export_service.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/domain/enums.dart';

import 'test_database.dart';

/// Manual-freeze persistence (schema v2) and export v1↔v2 compatibility.
void main() {
  late AppDatabase db;
  late HabitRepository habits;

  setUp(() {
    db = createTestDatabase();
    habits = HabitRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('freeze persistence', () {
    test('new habits default to auto mode', () async {
      final id = await habits.create(name: 'Read', color: 0xFF2DD4A8);
      final habit = await habits.getById(id);
      expect(habit!.freezeMode, FreezeMode.auto);
    });

    test('setFreezeMode switches to manual and back', () async {
      final id = await habits.create(name: 'Read', color: 0xFF2DD4A8);
      expect(await habits.setFreezeMode(id, FreezeMode.manual), isTrue);
      expect((await habits.getById(id))!.freezeMode, FreezeMode.manual);
      await habits.setFreezeMode(id, FreezeMode.auto);
      expect((await habits.getById(id))!.freezeMode, FreezeMode.auto);
    });

    test('placeFreeze is idempotent and removeFreeze refunds', () async {
      final id = await habits.create(
        name: 'Read',
        color: 0xFF2DD4A8,
        freezeMode: FreezeMode.manual,
      );
      final first = await habits.placeFreeze(id, '2026-11-16');
      expect(first, greaterThan(0));
      final again = await habits.placeFreeze(id, '2026-11-16');
      expect(again, -1); // already exists
      expect(await habits.getFreezes(id), hasLength(1));

      expect(await habits.removeFreeze(id, '2026-11-16'), 1);
      expect(await habits.getFreezes(id), isEmpty);
    });

    test('deleting a habit cascades its freezes', () async {
      final id = await habits.create(
        name: 'Read',
        color: 0xFF2DD4A8,
        freezeMode: FreezeMode.manual,
      );
      await habits.placeFreeze(id, '2026-11-16');
      await habits.delete(id);
      expect(await db.select(db.habitFreezes).get(), isEmpty);
    });
  });

  group('export v2', () {
    test('round-trips freeze mode and explicit freezes', () async {
      final id = await habits.create(
        name: 'Read',
        color: 0xFF2DD4A8,
        freezeMode: FreezeMode.manual,
      );
      await habits.placeFreeze(id, '2026-11-16');
      await habits.checkIn(id, '2026-11-17');

      final service = ExportService(db);
      final json = await service.exportToString();
      final decoded = jsonDecode(json) as Map<String, Object?>;
      // v0.3.0 exports v3 (sync identity); freeze data still round-trips.
      expect(decoded['schemaVersion'], 8);
      final data = decoded['data'] as Map<String, Object?>;
      expect(data['freezes'], hasLength(1));

      // Replace-all into a fresh database preserves mode + freezes.
      final db2 = createTestDatabase();
      addTearDown(db2.close);
      await ExportService(db2).importFromString(json);
      final habits2 = HabitRepository(db2);
      final restored = (await habits2.getAll()).single;
      expect(restored.freezeMode, FreezeMode.manual);
      expect(await habits2.getFreezes(restored.id), hasLength(1));
      expect((await habits2.getFreezes(restored.id)).single.date, '2026-11-16');
    });

    test('imports a v1 payload as auto mode with no freezes', () async {
      // A minimal v1 envelope: one habit without freezeMode, no freezes key.
      final v1 = {
        'schemaVersion': 1,
        'exportedAt': DateTime.utc(2026, 11, 22).millisecondsSinceEpoch,
        'data': {
          'tasks': <Object>[],
          'subtasks': <Object>[],
          'tags': <Object>[],
          'taskTags': <Object>[],
          'habits': [
            {
              'id': 1,
              'name': 'Legacy',
              'notes': null,
              'iconKey': 'spark',
              'color': 0xFF2DD4A8,
              'scheduleType': HabitScheduleType.daily.index,
              'weekdays': null,
              'targetPerWeek': null,
              'reminderTime': null,
              'createdAt': DateTime.utc(2026, 11, 1).millisecondsSinceEpoch,
              'archivedAt': null,
              'sortOrder': 0,
            },
          ],
          'checkins': <Object>[],
        },
      };
      final service = ExportService(db);
      final envelope = service.parseEnvelope(jsonEncode(v1));
      expect(envelope.habits.single.freezeMode, FreezeMode.auto);
      expect(envelope.freezes, isEmpty);

      await service.importFromString(jsonEncode(v1));
      final restored = (await habits.getAll()).single;
      expect(restored.name, 'Legacy');
      expect(restored.freezeMode, FreezeMode.auto);
    });

    test('rejects an unsupported future schema version', () async {
      final future = {
        'schemaVersion': 99,
        'exportedAt': 0,
        'data': <String, Object?>{},
      };
      expect(
        () => ExportService(db).parseEnvelope(jsonEncode(future)),
        throwsA(isA<ImportFormatException>()),
      );
    });
  });
}
