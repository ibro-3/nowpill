import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'sync_folder_base.dart';
import 'web_sync_folder.dart';

/// True on Chromium browsers that expose the File System Access directory
/// picker (Chrome/Edge). Firefox and Safari fall back to Export/Import.
bool get webFolderSyncSupported {
  final picker = (web.window as JSObject).getProperty<JSAny?>(
    'showDirectoryPicker'.toJS,
  );
  return picker != null && picker.typeofEquals('function');
}

/// Shows the browser directory picker and persists the returned handle for
/// later sessions. Returns null when cancelled or unsupported.
Future<SyncFolder?> pickWebSyncFolder() async {
  if (!webFolderSyncSupported) return null;
  try {
    // Must run in the picker's user-gesture context, so keep this call as the
    // first await-free operation in the method.
    final handle = await _WindowFs._(web.window)
        .showDirectoryPicker(_readWriteOptions())
        .toDart;
    await _WebHandleStore.save(handle);
    return WebSyncFolder(webSyncHandleFor(handle.name), _WebDirectoryBackend());
  } catch (_) {
    // AbortError (user cancelled), NotAllowedError, SecurityError, …
    return null;
  }
}

/// Rebuilds the web folder from a persisted `web:` handle. The directory
/// handle itself is loaded lazily from IndexedDB on the first operation.
SyncFolder? webSyncFolderFromHandle(String handle) {
  if (webSyncNameFromHandle(handle) == null) return null;
  return WebSyncFolder(handle, _WebDirectoryBackend());
}

JSObject _readWriteOptions() =>
    JSObject()..setProperty('mode'.toJS, 'readwrite'.toJS);

/// `showDirectoryPicker` is not in package:web's generated bindings yet.
extension type _WindowFs._(JSObject _) implements JSObject {
  external JSPromise<web.FileSystemDirectoryHandle> showDirectoryPicker(
    JSObject options,
  );
}

// The permission methods are part of the File System Access spec but are not
// in package:web's `FileSystemHandle` bindings.
extension type _PermissionAwareHandle._(JSObject _) implements JSObject {
  external JSPromise<JSString> queryPermission(JSObject descriptor);
  external JSPromise<JSString> requestPermission(JSObject descriptor);
}

// `FileSystemDirectoryHandle.values()` returns an async iterator, which
// package:web does not type yet.
extension type _DirectoryValues._(JSObject _) implements JSObject {
  external _AsyncIterator values();
}

extension type _AsyncIterator._(JSObject _) implements JSObject {
  external JSPromise<_IteratorStep> next();
}

extension type _IteratorStep._(JSObject _) implements JSObject {
  external bool get done;
  external JSAny? get value;
}

/// Browser-backed directory operations for one persisted folder handle.
class _WebDirectoryBackend implements WebSyncBackend {
  @override
  Future<bool> ensureAccess() async {
    final dir = await _WebHandleStore.load();
    if (dir == null) return false;
    return _ensurePermission(dir);
  }

  @override
  Future<List<SyncRemoteFile>> listFiles() async {
    final dir = await _WebHandleStore.load();
    if (dir == null || !await _ensurePermission(dir)) return const [];
    return _listSyncFiles(dir);
  }

  @override
  Future<void> write(String fileName, String content) async {
    final dir = await _WebHandleStore.load();
    if (dir == null || !await _ensurePermission(dir)) {
      throw StateError('sync-folder-unavailable');
    }
    await _writeFile(dir, fileName, content);
  }
}

/// Queries read/write permission and re-requests it when the browser still
/// reports `prompt` (allowed only from a user gesture, e.g. "Sync now").
Future<bool> _ensurePermission(web.FileSystemDirectoryHandle handle) async {
  final aware = _PermissionAwareHandle._(handle);
  try {
    final state =
        (await aware.queryPermission(_readWriteOptions()).toDart).toDart;
    if (state == 'granted') return true;
    if (state == 'denied') return false;
  } catch (_) {
    // Browser without the permission extension: the picker already granted
    // access; let the guarded IO surface any real error.
    return true;
  }
  try {
    final state =
        (await aware.requestPermission(_readWriteOptions()).toDart).toDart;
    return state == 'granted';
  } catch (_) {
    // No transient user activation (background poll): retry on manual sync.
    return false;
  }
}

Future<List<SyncRemoteFile>> _listSyncFiles(
  web.FileSystemDirectoryHandle dir,
) async {
  final result = <SyncRemoteFile>[];
  final iterator = _DirectoryValues._(dir).values();
  while (true) {
    final step = await iterator.next().toDart;
    if (step.done) break;
    final entry = step.value;
    if (entry == null) continue;
    try {
      final handle = entry as web.FileSystemHandle;
      if (handle.kind != 'file') continue;
      final name = handle.name;
      if (!isSyncFileName(name)) continue;
      final file = await (handle as web.FileSystemFileHandle).getFile().toDart;
      final content = (await file.text().toDart).toDart;
      result.add(SyncRemoteFile(name: name, content: content));
    } catch (_) {
      // Skip a file being written/removed by another tab; next poll retries.
    }
  }
  return result;
}

Future<void> _writeFile(
  web.FileSystemDirectoryHandle dir,
  String fileName,
  String content,
) async {
  final handle = await dir
      .getFileHandle(fileName, web.FileSystemGetFileOptions(create: true))
      .toDart;
  final writable = await handle.createWritable().toDart;
  try {
    await writable.write(content.toJS).toDart;
    await writable.close().toDart;
  } catch (_) {
    try {
      await writable.abort().toDart;
    } catch (_) {}
    rethrow;
  }
}

/// Persists the picked `FileSystemDirectoryHandle` (structured clone) in
/// IndexedDB so sync resumes across launches. A static cache avoids an IDB
/// round-trip per operation and lets a re-picked folder update every existing
/// [WebSyncFolder] instance.
class _WebHandleStore {
  static const _dbName = 'nowpill_sync';
  static const _storeName = 'handles';
  static const _folderKey = 'folder';

  static web.FileSystemDirectoryHandle? _cached;
  static Future<web.FileSystemDirectoryHandle?>? _loading;

  static Future<web.FileSystemDirectoryHandle?> load() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _loading ??= _loadFromDb().then(
      (handle) {
        _cached = handle;
        _loading = null;
        return handle;
      },
      onError: (Object _) {
        _loading = null;
        return null;
      },
    );
  }

  static Future<void> save(web.FileSystemDirectoryHandle handle) async {
    _cached = handle;
    final db = await _openDb();
    try {
      final tx = db.transaction(_storeName.toJS, 'readwrite');
      tx.objectStore(_storeName).put(handle, _folderKey.toJS);
      await _transactionDone(tx);
    } finally {
      db.close();
    }
  }

  static Future<web.FileSystemDirectoryHandle?> _loadFromDb() async {
    try {
      final db = await _openDb();
      try {
        final tx = db.transaction(_storeName.toJS, 'readonly');
        final request = tx.objectStore(_storeName).get(_folderKey.toJS);
        final value = await _requestDone(request);
        return value as web.FileSystemDirectoryHandle?;
      } finally {
        db.close();
      }
    } catch (_) {
      return null;
    }
  }

  static Future<web.IDBDatabase> _openDb() async {
    final request = web.window.indexedDB.open(_dbName, 1);
    request.onupgradeneeded = ((web.Event _) {
      final db = request.result;
      if (db.isA<web.IDBDatabase>()) {
        (db as web.IDBDatabase).createObjectStore(_storeName);
      }
    }).toJS;
    final db = await _requestDone(request);
    return db as web.IDBDatabase;
  }

  static Future<JSAny?> _requestDone(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) {
      if (!completer.isCompleted) completer.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(request.error?.message ?? 'IndexedDB request failed'),
        );
      }
    }).toJS;
    return completer.future;
  }

  static Future<void> _transactionDone(web.IDBTransaction tx) {
    final completer = Completer<void>();
    tx.oncomplete = ((web.Event _) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    tx.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('IndexedDB transaction failed'));
      }
    }).toJS;
    tx.onabort = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('IndexedDB transaction aborted'));
      }
    }).toJS;
    return completer.future;
  }
}
