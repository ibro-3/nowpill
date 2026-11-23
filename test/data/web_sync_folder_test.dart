import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/export/export_service.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/data/sync/sync_coordinator.dart';
import 'package:nowpill/data/sync/sync_folder.dart';
import 'package:nowpill/data/sync/web_sync_folder.dart';

/// Fake File System Access directory: an in-memory file map. The browser
/// adapter (package:web) is intentionally not imported here, so these rules
/// run on the VM just like any other pure domain test.
class FakeWebBackend implements WebSyncBackend {
  FakeWebBackend({this.accessible = true, Map<String, String>? files})
    : files = files ?? <String, String>{};

  final Map<String, String> files;
  bool accessible;
  int ensureCalls = 0;
  int writeCalls = 0;

  @override
  Future<bool> ensureAccess() async {
    ensureCalls++;
    return accessible;
  }

  @override
  Future<List<SyncRemoteFile>> listFiles() async => [
    for (final e in files.entries)
      SyncRemoteFile(name: e.key, content: e.value),
  ];

  @override
  Future<void> write(String fileName, String content) async {
    writeCalls++;
    files[fileName] = content;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('web sync handle', () {
    test('round-trips the folder name', () {
      const name = 'NowPill sync 📁';
      final handle = webSyncHandleFor(name);
      expect(handle, startsWith(webSyncHandlePrefix));
      expect(webSyncNameFromHandle(handle), name);
    });

    test('rejects non-web and empty handles', () {
      expect(webSyncNameFromHandle('/home/user/nowpill'), isNull);
      expect(
        webSyncNameFromHandle('content://com.android.external/42'),
        isNull,
      );
      expect(webSyncNameFromHandle(webSyncHandlePrefix), isNull);
      expect(webSyncNameFromHandle('web:%ZZ'), isNull);
    });
  });

  group('WebSyncFolder', () {
    test('labels itself from the handle', () {
      final folder = WebSyncFolder(
        webSyncHandleFor('My folder'),
        FakeWebBackend(),
      );
      expect(folder.displayName, 'My folder');
      expect(
        WebSyncFolder(webSyncHandlePrefix, FakeWebBackend()).displayName,
        'Folder',
      );
    });

    test('delegates accessibility and writes', () async {
      final backend = FakeWebBackend(accessible: false);
      final folder = WebSyncFolder(webSyncHandleFor('Drive'), backend);
      expect(await folder.isAccessible(), isFalse);
      backend.accessible = true;
      expect(await folder.isAccessible(), isTrue);
      await folder.write('nowpill-sync-devA.json', '{}');
      expect(backend.files['nowpill-sync-devA.json'], '{}');
      expect(backend.writeCalls, 1);
    });

    test('readOthers keeps only sync envelopes and skips own file', () async {
      final backend = FakeWebBackend(
        files: {
          'nowpill-sync-devA.json': 'own',
          'nowpill-sync-devB.json': 'b',
          'nowpill-sync-devC.json': 'c',
          'notes.txt': 'nope',
          'nowpill-sync-devD.tmp': 'partial',
        },
      );
      final folder = WebSyncFolder(webSyncHandleFor('Drive'), backend);
      final others = await folder.readOthers('nowpill-sync-devA.json');
      expect(others.map((f) => f.name), [
        'nowpill-sync-devB.json',
        'nowpill-sync-devC.json',
      ]);
      expect(others.map((f) => f.content), ['b', 'c']);
    });

    test('parseSyncEnvelope ignores partial JSON', () {
      expect(parseSyncEnvelope('{"schemaVersion":'), isNull);
      expect(parseSyncEnvelope('{"schemaVersion":3,"data":{}}'), isNotNull);
    });
  });

  group('coordinator over a web folder', () {
    test('two devices converge through the shared folder', () async {
      // Both tabs share the same picked folder (IndexedDB handle), but use
      // distinct device ids and databases — the browser analogue of the
      // two-folder IoSyncFolder convergence test.
      final shared = <String, String>{};

      ({AppDatabase db, SyncCoordinator sync}) device(String id) {
        final db = AppDatabase.withExecutor(
          NativeDatabase.memory(),
          deviceId: id,
        );
        addTearDown(db.close);
        final sync = SyncCoordinator(
          export: ExportService(db),
          deviceId: id,
          folder: WebSyncFolder(
            webSyncHandleFor('Shared web folder'),
            FakeWebBackend(files: shared),
          ),
          pollInterval: const Duration(hours: 1),
        );
        addTearDown(sync.dispose);
        return (db: db, sync: sync);
      }

      final a = device('devA');
      final b = device('devB');
      final idA = await HabitRepository(a.db)
          .create(name: 'Meditate', color: 1);
      await HabitRepository(a.db).checkIn(idA, '2026-11-20');
      await a.sync.syncNow();
      expect(a.sync.state.status, SyncStatus.ok);
      expect(shared.containsKey(syncFileNameFor('devA')), isTrue);

      await TaskRepository(b.db).create(title: 'B task');
      await b.sync.syncNow();
      expect((await HabitRepository(b.db).getAll()).single.name, 'Meditate');
      expect(await TaskRepository(b.db).getAll(), hasLength(1));

      await a.sync.syncNow();
      expect((await TaskRepository(a.db).getAll()).single.title, 'B task');
    });
  });
}
