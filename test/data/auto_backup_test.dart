import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/backup/auto_backup_service.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/export/export_service.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';

/// Rotating daily backups: one snapshot per day, keep-7 pruning, explicit
/// restore round-trip, and guarded failure paths.
void main() {
  late AppDatabase db;
  late Directory dir;
  late DateTime now;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory(), deviceId: 'devA');
    dir = Directory.systemTemp.createTempSync('nowpill_autobackup_');
    now = DateTime(2026, 11, 23, 8);
  });
  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  AutoBackupService service({int keep = 7}) => AutoBackupService(
    export: ExportService(db),
    directoryPath: dir.path,
    keep: keep,
    clock: () => now,
  );

  test('first run of the day writes a v3 snapshot', () async {
    await HabitRepository(db).create(name: 'Read', color: 1);
    final file = await service().runDailyBackup();
    expect(file, isNotNull);
    expect(file!.path, endsWith('nowpill-auto-2026-11-23.json'));
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(decoded['schemaVersion'], 4);
    expect((decoded['data'] as Map)['habits'], hasLength(1));
  });

  test('second run the same day is a no-op', () async {
    final svc = service();
    final first = await svc.runDailyBackup();
    final content = first!.readAsStringSync();
    // Data changes after the snapshot; the same-day run must not rewrite it.
    await HabitRepository(db).create(name: 'Another', color: 2);
    final second = await svc.runDailyBackup();
    expect(second, isNull);
    expect(first.readAsStringSync(), content);
  });

  test('a new day writes a new snapshot', () async {
    final svc = service();
    await svc.runDailyBackup();
    now = DateTime(2026, 11, 24, 8);
    final next = await svc.runDailyBackup();
    expect(next, isNotNull);
    expect(next!.path, endsWith('nowpill-auto-2026-11-24.json'));
    expect(svc.listBackups(), hasLength(2));
  });

  test('prunes beyond keep, oldest first', () async {
    final svc = service(keep: 7);
    for (var day = 10; day <= 20; day++) {
      now = DateTime(2026, 11, day, 8);
      await svc.runDailyBackup();
    }
    final files = svc.listBackups();
    expect(files, hasLength(7));
    // Kept the newest 7: Nov 14..20.
    expect(files.first.path, endsWith('nowpill-auto-2026-11-14.json'));
    expect(files.last.path, endsWith('nowpill-auto-2026-11-20.json'));
  });

  test('listBackups ignores unrelated files and sorts oldest first', () async {
    File('${dir.path}/notes.txt').writeAsStringSync('hi');
    File('${dir.path}/nowpill-auto-2026-11-22.json').writeAsStringSync('{}');
    File('${dir.path}/nowpill-auto-2026-11-20.json').writeAsStringSync('{}');
    final files = service().listBackups();
    expect(files, hasLength(2));
    expect(files.first.path, endsWith('2026-11-20.json'));
  });

  test('restore round-trips through replace-all', () async {
    final habits = HabitRepository(db);
    final id = await habits.create(name: 'Read', color: 1);
    await habits.checkIn(id, '2026-11-20');
    final file = await service().runDailyBackup();

    // Mutate, then restore the snapshot.
    await habits.delete(id);
    expect(await habits.getAll(), isEmpty);
    final json = service().readBackup(file!);
    await ExportService(db).importFromString(json);
    expect((await habits.getAll()).single.name, 'Read');
    expect(await habits.getAllCheckins(), hasLength(1));
  });

  test('missing documents dir is guarded (returns null, no throw)', () async {
    final svc = AutoBackupService(
      export: ExportService(db),
      directoryPath: '${dir.path}/does/not/exist',
      clock: () => now,
    );
    // createSync(recursive) succeeds for a nested path; force a failure by
    // pointing at a path whose parent is a file.
    final blocker = File('${dir.path}/blocker')..writeAsStringSync('x');
    final blocked = AutoBackupService(
      export: ExportService(db),
      directoryPath: '${blocker.path}/sub',
      clock: () => now,
    );
    expect(await blocked.runDailyBackup(), isNull);
    expect(await svc.runDailyBackup(), isNotNull);
  });
}
