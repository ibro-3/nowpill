import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/export/export_service.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:sqlite3/sqlite3.dart';

import 'test_database.dart';

/// Schema v4 (measurable habits): migration, amount upsert semantics, and
/// export v4 round-trip + backward-compatible import.
void main() {
  group('migration v3 → v4', () {
    test('adds targetAmount + amount, preserving existing rows', () async {
      // Build a genuine v3 database (sync identity, no measurable columns).
      final raw = sqlite3.openInMemory();
      raw.execute('PRAGMA user_version = 3');
      raw.execute('''
        CREATE TABLE habits (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          uuid TEXT NOT NULL DEFAULT '', updated_at INTEGER NOT NULL DEFAULT 0,
          name TEXT NOT NULL, notes TEXT,
          icon_key TEXT NOT NULL DEFAULT 'spark', color INTEGER NOT NULL,
          schedule_type INTEGER NOT NULL, weekdays TEXT,
          target_per_week INTEGER, reminder_time INTEGER,
          freeze_mode INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL, archived_at INTEGER,
          sort_order INTEGER NOT NULL DEFAULT 0
        )
      ''');
      raw.execute('''
        CREATE TABLE habit_checkins (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          uuid TEXT NOT NULL DEFAULT '', updated_at INTEGER NOT NULL DEFAULT 0,
          habit_id INTEGER NOT NULL REFERENCES habits (id) ON DELETE CASCADE,
          habit_uuid TEXT NOT NULL DEFAULT '',
          date TEXT NOT NULL, note TEXT, UNIQUE (habit_id, date)
        )
      ''');
      raw.execute(
        'INSERT INTO habits (uuid, name, color, schedule_type, created_at) '
        "VALUES ('h-uuid', 'Water', 1, 0, 1000)",
      );
      raw.execute(
        'INSERT INTO habit_checkins (uuid, habit_id, habit_uuid, date) '
        "VALUES ('c-uuid', 1, 'h-uuid', '2026-11-20')",
      );

      final db = AppDatabase.withExecutor(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: true),
      );
      final habit = (await db.select(db.habits).get()).single;
      expect(habit.targetAmount, isNull); // classic by default
      final checkin = (await db.select(db.habitCheckins).get()).single;
      expect(checkin.amount, isNull); // full completion by default
      expect(checkin.uuid, 'c-uuid'); // identity preserved

      // New columns are usable.
      await db
          .into(db.habitCheckins)
          .insert(
            HabitCheckinsCompanion.insert(
              habitId: 1,
              habitUuid: 'h-uuid',
              date: '2026-11-21',
              amount: const Value(4),
            ),
          );
      final version = await db
          .customSelect('PRAGMA user_version')
          .map((r) => r.data.values.first as int)
          .getSingle();
      expect(version, 7);
      await db.close();
    });
  });

  group('amount check-in semantics', () {
    late AppDatabase db;
    late HabitRepository habits;

    setUp(() {
      db = createTestDatabase();
      habits = HabitRepository(db);
    });
    tearDown(() => db.close());

    test('classic check-in stays idempotent', () async {
      final id = await habits.create(name: 'Read', color: 1);
      final first = await habits.checkIn(id, '2026-11-20');
      final second = await habits.checkIn(id, '2026-11-20');
      expect(first, greaterThan(0));
      expect(second, -1);
      expect(await habits.getCheckins(id), hasLength(1));
    });

    test('measurable check-in updates the amount in place', () async {
      final id = await habits.create(name: 'Water', color: 1, targetAmount: 8);
      await habits.checkIn(id, '2026-11-20', amount: 3);
      await habits.checkIn(id, '2026-11-20', amount: 5);
      final rows = await habits.getCheckins(id);
      expect(rows, hasLength(1));
      expect(rows.single.amount, 5);
    });

    test('amount update keeps the row uuid (merges as an edit)', () async {
      final id = await habits.create(name: 'Water', color: 1, targetAmount: 8);
      await habits.checkIn(id, '2026-11-20', amount: 3);
      final before = (await habits.getCheckins(id)).single;
      await habits.checkIn(id, '2026-11-20', amount: 8);
      final after = (await habits.getCheckins(id)).single;
      expect(after.uuid, before.uuid);
      expect(after.updatedAt.isAfter(before.updatedAt), isTrue);
      // No tombstone — this is an edit, not a delete+recreate.
      expect(await db.select(db.tombstones).get(), isEmpty);
    });

    test('targetAmount persists through update', () async {
      final id = await habits.create(name: 'Water', color: 1);
      final h = (await habits.getById(id))!;
      await habits.update(h.copyWith(targetAmount: const Value(8)));
      expect((await habits.getById(id))!.targetAmount, 8);
      await habits.update(
        (await habits.getById(id))!.copyWith(targetAmount: const Value(null)),
      );
      expect((await habits.getById(id))!.targetAmount, isNull);
    });
  });

  group('export v4', () {
    late AppDatabase db;
    late HabitRepository habits;

    setUp(() {
      db = createTestDatabase();
      habits = HabitRepository(db);
    });
    tearDown(() => db.close());

    test('round-trips targetAmount and amounts', () async {
      final id = await habits.create(name: 'Water', color: 1, targetAmount: 8);
      await habits.checkIn(id, '2026-11-20', amount: 5);
      final json = await ExportService(db).exportToString();
      final decoded = jsonDecode(json) as Map<String, Object?>;
      expect(decoded['schemaVersion'], 7);

      final db2 = createTestDatabase();
      addTearDown(db2.close);
      await ExportService(db2).importFromString(json);
      final h2 = (await HabitRepository(db2).getAll()).single;
      expect(h2.targetAmount, 8);
      expect((await HabitRepository(db2).getAllCheckins()).single.amount, 5);
    });

    test('imports a v3 payload as classic habits / full completions', () async {
      final id = await habits.create(name: 'Read', color: 1);
      await habits.checkIn(id, '2026-11-20');
      final v3json = await ExportService(db).exportToString();
      final decoded = jsonDecode(v3json) as Map<String, Object?>;
      // Strip the v4 fields to simulate a genuine v3 envelope.
      decoded['schemaVersion'] = 3;
      final data = decoded['data'] as Map<String, Object?>;
      for (final h in (data['habits'] as List).cast<Map<String, Object?>>()) {
        h.remove('targetAmount');
      }
      for (final c in (data['checkins'] as List).cast<Map<String, Object?>>()) {
        c.remove('amount');
      }

      final db2 = createTestDatabase();
      addTearDown(db2.close);
      final envelope = await ExportService(db2)
          .importFromString(jsonEncode(decoded));
      expect(envelope.habits.single.targetAmount, isNull);
      expect(envelope.checkins.single.amount, isNull);
    });
  });
}
