import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:sqlite3/sqlite3.dart';

/// Schema v1 → v2 migration: existing habits keep working (default auto mode)
/// and the new HabitFreezes table becomes available.
void main() {
  test('v1 database upgrades to v2 preserving data', () async {
    // Build a genuine v1 database (no freezeMode column, no HabitFreezes table)
    // and seed a habit + check-in, then close it.
    final raw = sqlite3.openInMemory();
    raw.execute('PRAGMA user_version = 1');
    raw.execute('''
      CREATE TABLE habits (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        notes TEXT,
        icon_key TEXT NOT NULL DEFAULT 'spark',
        color INTEGER NOT NULL,
        schedule_type INTEGER NOT NULL,
        weekdays TEXT,
        target_per_week INTEGER,
        reminder_time INTEGER,
        created_at INTEGER NOT NULL,
        archived_at INTEGER,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    raw.execute('''
      CREATE TABLE habit_checkins (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        habit_id INTEGER NOT NULL REFERENCES habits (id) ON DELETE CASCADE,
        date TEXT NOT NULL,
        note TEXT,
        UNIQUE (habit_id, date)
      )
    ''');
    raw.execute(
      'INSERT INTO habits (name, color, schedule_type, created_at) '
      "VALUES ('Legacy', 4281519272, 0, 1767225600000)",
    );
    raw.execute(
      'INSERT INTO habit_checkins (habit_id, date) VALUES (1, \'2026-11-20\')',
    );

    // Open AppDatabase over the same connection: drift sees user_version 1 and
    // runs onUpgrade(1 → 2).
    final db = AppDatabase.withExecutor(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: true),
    );

    final habits = await db.select(db.habits).get();
    expect(habits, hasLength(1));
    expect(habits.single.name, 'Legacy');
    expect(habits.single.freezeMode, FreezeMode.auto); // default applied

    // Check-in survived.
    final checkins = await db.select(db.habitCheckins).get();
    expect(checkins, hasLength(1));
    expect(checkins.single.date, '2026-11-20');

    // The new table exists and is usable.
    await db
        .into(db.habitFreezes)
        .insert(
          HabitFreezesCompanion.insert(
            habitId: 1,
            date: '2026-11-16',
            createdAt: DateTime.utc(2026, 11, 22),
          ),
        );
    expect(await db.select(db.habitFreezes).get(), hasLength(1));

    // Schema is now at v2.
    final version = await db
        .customSelect('PRAGMA user_version')
        .map((r) => r.data.values.first as int)
        .getSingle();
    expect(version, 2);

    await db.close();
  });
}
