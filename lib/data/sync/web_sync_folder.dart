import 'sync_folder_base.dart';

/// Prefix marking a persisted handle as belonging to the web folder provider.
const String webSyncHandlePrefix = 'web:';

/// Builds the settings handle for a picked directory. The handle only needs to
/// be stable across launches; the real `FileSystemDirectoryHandle` lives in
/// IndexedDB (structured clone) and cannot be serialized to a string. The
/// folder name is carried along so Settings can label it without awaiting IO.
String webSyncHandleFor(String displayName) =>
    '$webSyncHandlePrefix${Uri.encodeComponent(displayName)}';

/// Human-readable folder name carried by a web handle, or null when [handle]
/// is not a web handle.
String? webSyncNameFromHandle(String handle) {
  if (!handle.startsWith(webSyncHandlePrefix)) return null;
  final encoded = handle.substring(webSyncHandlePrefix.length);
  if (encoded.isEmpty) return null;
  try {
    return Uri.decodeComponent(encoded);
  } catch (_) {
    return null;
  }
}

/// The platform-independent directory operations a [WebSyncFolder] needs.
/// Implemented over the File System Access API in `web_sync_platform_web.dart`;
/// tests inject an in-memory fake.
abstract class WebSyncBackend {
  /// Queries (and, when possible, re-requests) read/write permission.
  Future<bool> ensureAccess();

  /// Lists the sync envelope files currently in the folder.
  Future<List<SyncRemoteFile>> listFiles();

  /// Creates or replaces a file by name.
  Future<void> write(String fileName, String content);
}

/// Web sync folder backed by a persisted `FileSystemDirectoryHandle`.
///
/// Kept free of `package:web` imports so its filtering/labelling rules are
/// unit-testable on the VM; the browser adapter lives behind a conditional
/// import and is only compiled for web builds.
class WebSyncFolder implements SyncFolder {
  WebSyncFolder(this.handle, this._backend)
    : assert(
        handle.startsWith(webSyncHandlePrefix),
        'web sync handles must start with $webSyncHandlePrefix',
      );

  @override
  final String handle;

  final WebSyncBackend _backend;

  @override
  String get displayName => webSyncNameFromHandle(handle) ?? 'Folder';

  @override
  Future<bool> isAccessible() => _backend.ensureAccess();

  @override
  Future<List<SyncRemoteFile>> readOthers(String ownFileName) async {
    final files = await _backend.listFiles();
    return [
      for (final file in files)
        if (isSyncFileName(file.name) && file.name != ownFileName) file,
    ];
  }

  @override
  Future<void> write(String fileName, String content) =>
      _backend.write(fileName, content);
}
