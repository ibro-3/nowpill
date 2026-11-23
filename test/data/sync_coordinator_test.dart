import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/export/export_service.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/data/sync/sync_coordinator.dart';
import 'package:nowpill/data/sync/sync_folder.dart';

/// Sentinel distinguishing "folder not passed" from an explicit null folder.
const Object _defaultFolder = Object();

/// SyncCoordinator over real temp-dir IoSyncFolders: two simulated devices
/// converge through the folder, deletes propagate, and the disabled /
/// unavailable paths are guarded.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nowpill_sync_test_');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  ({AppDatabase db, ExportService export, SyncCoordinator sync}) device(
    String id, {
    Object? folder = _defaultFolder,
  }) {
    final db = AppDatabase.withExecutor(NativeDatabase.memory(), deviceId: id);
    addTearDown(db.close);
    final export = ExportService(db);
    final sync = SyncCoordinator(
      export: export,
      deviceId: id,
      folder: identical(folder, _defaultFolder)
          ? IoSyncFolder(dir.path)
          : folder as SyncFolder?,
      // Long poll: tests drive cycles explicitly.
      pollInterval: const Duration(hours: 1),
    );
    addTearDown(sync.dispose);
    return (db: db, export: export, sync: sync);
  }

  test('two devices converge through the folder', () async {
    final a = device('devA');
    final b = device('devB');
    final habitsA = HabitRepository(a.db);
    final habitsB = HabitRepository(b.db);

    // A creates data and publishes.
    final idA = await habitsA.create(name: 'Meditate', color: 1);
    await habitsA.checkIn(idA, '2026-11-20');
    await a.sync.syncNow();
    expect(a.sync.state.status, SyncStatus.ok);
    expect(File('${dir.path}/nowpill-sync-devA.json').existsSync(), isTrue);

    // B has its own task; syncing pulls A's habit and keeps B's task.
    await TaskRepository(b.db).create(title: 'B task');
    await b.sync.syncNow();
    expect((await habitsB.getAll()).single.name, 'Meditate');
    expect(await habitsB.getAllCheckins(), hasLength(1));
    expect(await TaskRepository(b.db).getAll(), hasLength(1));
    expect(File('${dir.path}/nowpill-sync-devB.json').existsSync(), isTrue);

    // A syncs again and receives B's task.
    await a.sync.syncNow();
    expect(await TaskRepository(a.db).getAll(), hasLength(1));
    expect((await TaskRepository(a.db).getAll()).single.title, 'B task');

    // Content converged: both devices hold identical uuid sets.
    final aHabits = await habitsA.getAll();
    final bHabits = await habitsB.getAll();
    expect(aHabits.single.uuid, bHabits.single.uuid);
  });

  test('remote delete propagates on the next cycle', () async {
    final a = device('devA');
    final b = device('devB');
    final habitsA = HabitRepository(a.db);
    final habitsB = HabitRepository(b.db);

    final idA = await habitsA.create(name: 'Read', color: 1);
    await habitsA.checkIn(idA, '2026-11-20');
    await a.sync.syncNow();
    await b.sync.syncNow();
    expect(await habitsB.getAll(), hasLength(1));

    await habitsA.delete(idA);
    await a.sync.syncNow();
    await b.sync.syncNow();
    expect(await habitsB.getAll(), isEmpty);
    expect(await habitsB.getAllCheckins(), isEmpty);

    // And stays deleted (tombstone persisted on both sides).
    await b.sync.syncNow();
    await a.sync.syncNow();
    expect(await habitsA.getAll(), isEmpty);
    expect(await habitsB.getAll(), isEmpty);
  });

  test('concurrent edits resolve deterministically on both devices', () async {
    final a = device('devA');
    final b = device('devB');
    final habitsA = HabitRepository(a.db);
    final habitsB = HabitRepository(b.db);

    final idA = await habitsA.create(name: 'Read', color: 1);
    await a.sync.syncNow();
    await b.sync.syncNow();
    final idB = (await habitsB.getAll()).single.id;

    // Both rename; B later.
    await habitsA.update(
      (await habitsA.getById(idA))!.copyWith(name: 'A name'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await habitsB.update(
      (await habitsB.getById(idB))!.copyWith(name: 'B name'),
    );

    await a.sync.syncNow();
    await b.sync.syncNow();
    await a.sync.syncNow();
    expect((await habitsA.getAll()).single.name, 'B name');
    expect((await habitsB.getAll()).single.name, 'B name');
  });

  test('equal-timestamp divergent copies converge (no flip-flop)', () async {
    // Regression: two devices hold the same uuid with different content at
    // the SAME updatedAt. A deviceId tiebreak would make each prefer its own
    // copy and swap forever; the content tiebreak must reach a fixed point.
    final a = device('devA');
    final b = device('devB');
    final habitsA = HabitRepository(a.db);
    final habitsB = HabitRepository(b.db);

    final idA = await habitsA.create(name: 'Read', color: 1);
    await a.sync.syncNow();
    await b.sync.syncNow();
    final idB = (await habitsB.getAll()).single.id;

    // Force both copies to the same updatedAt but different names (simulates
    // clock skew / an out-of-band edit).
    final stamp = DateTime.utc(2026, 11, 23, 12);
    await habitsA.update(
      (await habitsA.getById(idA))!.copyWith(name: 'A name', updatedAt: stamp),
    );
    await habitsB.update(
      (await habitsB.getById(idB))!.copyWith(name: 'B name', updatedAt: stamp),
    );

    // Alternate cycles; both devices must settle on the SAME name and stay.
    for (var i = 0; i < 3; i++) {
      await a.sync.syncNow();
      await b.sync.syncNow();
    }
    final nameA = (await habitsA.getAll()).single.name;
    final nameB = (await habitsB.getAll()).single.name;
    expect(nameA, nameB);
    // One more round must not change it (fixed point).
    await a.sync.syncNow();
    await b.sync.syncNow();
    expect((await habitsA.getAll()).single.name, nameA);
    expect((await habitsB.getAll()).single.name, nameB);
  });

  test('unchanged data does not rewrite the file', () async {
    final a = device('devA');
    await HabitRepository(a.db).create(name: 'Read', color: 1);
    await a.sync.syncNow();
    final file = File('${dir.path}/nowpill-sync-devA.json');
    final firstModified = file.lastModifiedSync();
    final firstContent = file.readAsStringSync();

    await Future<void>.delayed(const Duration(milliseconds: 20));
    await a.sync.syncNow();
    expect(file.readAsStringSync(), firstContent);
    expect(file.lastModifiedSync(), firstModified);
  });

  test('disabled coordinator is a no-op', () async {
    final a = device('devA', folder: null);
    await HabitRepository(a.db).create(name: 'Read', color: 1);
    await a.sync.syncNow();
    expect(a.sync.state.status, SyncStatus.idle);
    expect(dir.listSync(), isEmpty);
  });

  test('missing folder reports unavailable without throwing', () async {
    final missing = Directory('${dir.path}/gone');
    final a = device('devA', folder: IoSyncFolder(missing.path));
    await a.sync.syncNow();
    expect(a.sync.state.status, SyncStatus.folderUnavailable);
  });

  test('partial remote file is skipped and retried next cycle', () async {
    final a = device('devA');
    await HabitRepository(a.db).create(name: 'Read', color: 1);
    // Simulate a half-copied remote envelope.
    await File('${dir.path}/nowpill-sync-devB.json')
        .writeAsString('{"schemaVersion": 3, "data": {');
    await a.sync.syncNow();
    expect(a.sync.state.status, SyncStatus.ok);
    expect(await HabitRepository(a.db).getAll(), hasLength(1));

    // The transport finishes the copy; the next cycle picks it up.
    final b = device('devB');
    await HabitRepository(b.db).create(name: 'Run', color: 2);
    await b.sync.syncNow();
    await a.sync.syncNow();
    expect(await HabitRepository(a.db).getAll(), hasLength(2));
  });

  test('setFolder enables and disables at runtime', () async {
    final a = device('devA', folder: null);
    await HabitRepository(a.db).create(name: 'Read', color: 1);
    a.sync.start();
    expect(dir.listSync(), isEmpty);

    a.sync.setFolder(IoSyncFolder(dir.path));
    await a.sync.syncNow();
    expect(dir.listSync(), hasLength(1));

    a.sync.setFolder(null);
    await a.sync.syncNow();
    expect(a.sync.state.status, SyncStatus.idle);
  });

  test('envelope files carry the device id and v4 shape', () async {
    final a = device('devA');
    await HabitRepository(a.db).create(name: 'Read', color: 1);
    await a.sync.syncNow();
    final content = File('${dir.path}/nowpill-sync-devA.json')
        .readAsStringSync();
    final decoded = jsonDecode(content) as Map<String, Object?>;
    expect(decoded['schemaVersion'], 4);
    expect(decoded['deviceId'], 'devA');
  });
}
