import 'dart:convert';

/// One device's envelope file in the sync folder.
class SyncRemoteFile {
  const SyncRemoteFile({required this.name, required this.content});

  final String name;
  final String content;
}

/// A user-chosen folder that transports per-device envelope files between
/// devices (Syncthing / Dropbox / iCloud Drive / … do the actual copying).
///
/// Implementations: `IoSyncFolder` (desktop `dart:io`), `SafSyncFolder`
/// (Android Storage Access Framework via the `app.nowpill/sync` channel), and
/// `WebSyncFolder` (web File System Access API, see `web_sync_folder.dart`).
abstract class SyncFolder {
  /// A stable handle persisted in settings (path, SAF tree URI, or `web:…`).
  String get handle;

  /// A short human-readable label for the Settings UI.
  String get displayName;

  /// Whether the folder is still reachable (permission kept, drive mounted).
  Future<bool> isAccessible();

  /// Reads every `nowpill-sync-*.json` file except this device's own.
  Future<List<SyncRemoteFile>> readOthers(String ownFileName);

  /// Writes (creates or replaces) a file by name.
  Future<void> write(String fileName, String content);
}

/// Envelope file name for a device. Only the owning device writes its file,
/// so the folder never sees concurrent writes to the same file.
String syncFileNameFor(String deviceId) => 'nowpill-sync-$deviceId.json';

/// Whether [name] is a NowPill sync envelope file.
bool isSyncFileName(String name) =>
    name.startsWith('nowpill-sync-') && name.endsWith('.json');

/// Parses a remote envelope, returning null for invalid/partial JSON (a file
/// still being copied by the transport). Never throws.
Map<String, Object?>? parseSyncEnvelope(String content) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is Map<String, Object?> &&
        decoded['schemaVersion'] is int &&
        decoded['data'] is Map<String, Object?>) {
      return decoded;
    }
  } catch (_) {
    // fall through
  }
  return null;
}
