import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/export/backup_service.dart';
import 'package:nowpill/data/export/export_service.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/task_repository.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late BackupService backup;

  setUp(() {
    db = createTestDatabase();
    backup = BackupService(ExportService(db));
  });

  tearDown(() async {
    await db.close();
  });

  group('suggestFileName', () {
    test('formats a dated backup name', () {
      expect(
        backup.suggestFileName(DateTime(2026, 11, 23)),
        'nowpill-backup-2026-11-23.json',
      );
      expect(
        backup.suggestFileName(DateTime(2026, 1, 5)),
        'nowpill-backup-2026-01-05.json',
      );
    });
  });

  group('validate', () {
    test('accepts a real export and reports counts', () async {
      await HabitRepository(db).create(name: 'Meditate', color: 0xFF2DD4A8);
      await TaskRepository(db).create(title: 'Buy milk');
      final json = await backup.exportToString();

      final envelope = backup.validate(json);
      expect(envelope.habits, hasLength(1));
      expect(envelope.tasks, hasLength(1));
    });

    test('rejects garbage without touching the database', () async {
      await TaskRepository(db).create(title: 'Keep me');
      expect(
        () => backup.validate('definitely not json'),
        throwsA(isA<ImportFormatException>()),
      );
      expect(await db.select(db.tasks).get(), hasLength(1));
    });
  });

  group('restore', () {
    test('round-trips into a fresh database', () async {
      final habits = HabitRepository(db);
      final id = await habits.create(name: 'Read', color: 0xFF5B8DEF);
      await habits.checkIn(id, '2026-11-22');
      final json = await backup.exportToString();

      final fresh = createTestDatabase();
      addTearDown(fresh.close);
      final freshBackup = BackupService(ExportService(fresh));
      final envelope = await freshBackup.restore(json);

      expect(envelope.habits.single.name, 'Read');
      expect(await fresh.select(fresh.habits).get(), hasLength(1));
      expect(await fresh.select(fresh.habitCheckins).get(), hasLength(1));
    });

    test('replace-all wipes pre-existing rows', () async {
      await TaskRepository(db).create(title: 'Old task');
      final json = await backup.exportToString();
      await TaskRepository(db).create(title: 'Extra task');
      expect(await db.select(db.tasks).get(), hasLength(2));

      await backup.restore(json);
      final tasks = await db.select(db.tasks).get();
      expect(tasks, hasLength(1));
      expect(tasks.single.title, 'Old task');
    });
  });
}
