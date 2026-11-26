import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/export/export_service.dart';
import 'package:nowpill/data/repositories/chat_repository.dart';
import 'package:sqlite3/sqlite3.dart';

import 'test_database.dart';

/// Schema v8: the personal chat table, repository rules, tombstones and
/// export/import compatibility with older envelopes.
void main() {
  group('migration → v8', () {
    test('adds chat_notes without touching existing data', () async {
      final raw = sqlite3.openInMemory();
      raw.execute('PRAGMA user_version = 7');
      raw.execute('''
        CREATE TABLE tasks (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          uuid TEXT NOT NULL DEFAULT '', updated_at INTEGER NOT NULL DEFAULT 0,
          title TEXT NOT NULL, notes TEXT,
          due_at INTEGER, priority INTEGER NOT NULL DEFAULT 0,
          completed_at INTEGER, recurrence_rule TEXT, reminder_at INTEGER,
          created_at INTEGER NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0,
          list_id INTEGER, list_uuid TEXT
        )
      ''');
      raw.execute(
        "INSERT INTO tasks (id, title, created_at) VALUES (1, 'Keep me', 1000)",
      );

      final db = AppDatabase.withExecutor(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: true),
      );
      final version = await db
          .customSelect('PRAGMA user_version')
          .map((r) => r.data.values.first as int)
          .getSingle();
      expect(version, 8);
      expect(await db.select(db.chatNotes).get(), isEmpty);
      expect((await db.select(db.tasks).get()).single.title, 'Keep me');
      await db.close();
    });
  });

  group('chat repository', () {
    late AppDatabase db;
    late ChatRepository repo;

    setUp(() {
      db = createTestDatabase();
      repo = ChatRepository(db);
    });
    tearDown(() => db.close());

    test('creates trimmed notes, edits them, and tombstones deletes', () async {
      final id = await repo.create('  hello self  ');
      final note = (await repo.getAll()).single;
      expect(note.id, id);
      expect(note.body, 'hello self');
      expect(
        note.updatedAt.millisecondsSinceEpoch,
        greaterThanOrEqualTo(note.createdAt.millisecondsSinceEpoch),
      );

      expect(await repo.edit(id, '  edited  '), isTrue);
      final edited = (await repo.getAll()).single;
      expect(edited.body, 'edited');
      expect(
        edited.updatedAt.millisecondsSinceEpoch,
        greaterThanOrEqualTo(note.updatedAt.millisecondsSinceEpoch),
      );

      expect(await repo.delete(id), 1);
      expect(await repo.getAll(), isEmpty);
      final tombstones = await db.select(db.tombstones).get();
      expect(tombstones.single.uuid, edited.uuid);
      expect(tombstones.single.sourceTable, 'chatNotes');
    });

    test('rejects empty and overlong bodies', () async {
      expect(
        () => repo.create('   '),
        throwsA(isA<InvalidChatNoteException>()),
      );
      expect(
        () => repo.create('x' * (kMaxChatNoteLength + 1)),
        throwsA(isA<InvalidChatNoteException>()),
      );
      expect(await repo.getAll(), isEmpty);
    });
  });

  group('export / import', () {
    test('v8 round-trip preserves notes', () async {
      final db = createTestDatabase();
      final repo = ChatRepository(db);
      await repo.create('first thought');
      await repo.create('second thought');
      final json = await ExportService(db).exportToString();
      await db.close();

      final restored = createTestDatabase();
      await ExportService(restored).importFromString(json);
      final bodies =
          (await restored.select(restored.chatNotes).get())
              .map((n) => n.body)
              .toList()
            ..sort();
      expect(bodies, ['first thought', 'second thought']);
      await restored.close();
    });

    test('v7 payload without chatNotes imports as an empty stream', () async {
      final payload = {
        'schemaVersion': 7,
        'exportedAt': DateTime.utc(2026, 11, 25).millisecondsSinceEpoch,
        'deviceId': 'old',
        'data': {
          'tasks': <Object>[],
          'subtasks': <Object>[],
          'taskLists': <Object>[],
          'tags': <Object>[],
          'taskTags': <Object>[],
          'habits': <Object>[],
          'checkins': <Object>[],
          'relapses': <Object>[],
          'vacations': <Object>[],
          'routines': <Object>[],
          'vacationScopes': <Object>[],
          'freezes': <Object>[],
          'tombstones': <Object>[],
        },
      };
      final db = createTestDatabase();
      final envelope = await ExportService(db)
          .importFromString(jsonEncode(payload));
      expect(envelope.schemaVersion, kExportSchemaVersion);
      expect(envelope.chatNotes, isEmpty);
      await db.close();
    });
  });
}
