import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// One device's envelope file in the sync folder.
class SyncRemoteFile {
  const SyncRemoteFile({required this.name, required this.content});

  final String name;
  final String content;
}

/// A user-chosen folder that transports per-device envelope files between
/// devices (Syncthing / Dropbox / iCloud Drive / … do the actual copying).
///
/// Implementations: [IoSyncFolder] (desktop `dart:io`) and [SafSyncFolder]
/// (Android Storage Access Framework via the `app.nowpill/sync` channel).
abstract class SyncFolder {
  /// A stable handle persisted in settings (path or SAF tree URI).
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

/// Desktop folder backed by `dart:io`.
class IoSyncFolder implements SyncFolder {
  IoSyncFolder(this.path);

  final String path;

  @override
  String get handle => path;

  @override
  String get displayName => p.basename(path);

  @override
  Future<bool> isAccessible() => Future.value(Directory(path).existsSync());

  @override
  Future<List<SyncRemoteFile>> readOthers(String ownFileName) async {
    final dir = Directory(path);
    if (!dir.existsSync()) return const [];
    final result = <SyncRemoteFile>[];
    for (final entry in dir.listSync()) {
      if (entry is! File) continue;
      final name = p.basename(entry.path);
      if (!isSyncFileName(name) || name == ownFileName) continue;
      try {
        result.add(
          SyncRemoteFile(name: name, content: entry.readAsStringSync()),
        );
      } catch (_) {
        // Unreadable/partial file (mid-copy): skip; next poll retries.
      }
    }
    return result;
  }

  @override
  Future<void> write(String fileName, String content) async {
    // Write-then-rename so readers never observe a half-written envelope.
    // Synchronous IO: the envelope is small and this keeps the operation
    // atomic from the caller's perspective (no interleaved partial reads).
    final target = File(p.join(path, fileName));
    final temp = File(p.join(path, '$fileName.tmp'));
    temp.writeAsStringSync(content, flush: true);
    temp.renameSync(target.path);
  }
}

/// Android folder backed by a persisted SAF tree URI. The native side
/// (MainActivity) resolves the tree via DocumentFile.
class SafSyncFolder implements SyncFolder {
  SafSyncFolder(this.treeUri, {MethodChannel? channel, this._label})
    : _channel = channel ?? const MethodChannel('app.nowpill/sync');

  final String treeUri;
  final MethodChannel _channel;
  final String? _label;
  @override
  String get handle => treeUri;

  @override
  String get displayName =>
      _label ?? Uri.tryParse(treeUri)?.pathSegments.lastOrNull ?? 'Folder';

  @override
  Future<bool> isAccessible() async {
    try {
      return await _channel.invokeMethod<bool>('isAccessible', treeUri) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<SyncRemoteFile>> readOthers(String ownFileName) async {
    final raw = await _channel.invokeMethod<List<Object?>>('readOthers', {
      'treeUri': treeUri,
      'exclude': ownFileName,
    });
    if (raw == null) return const [];
    final result = <SyncRemoteFile>[];
    for (final item in raw.whereType<Map<Object?, Object?>>()) {
      final name = item['name'] as String?;
      final content = item['content'] as String?;
      if (name == null || content == null) continue;
      result.add(SyncRemoteFile(name: name, content: content));
    }
    return result;
  }

  @override
  Future<void> write(String fileName, String content) async {
    await _channel.invokeMethod<void>('write', {
      'treeUri': treeUri,
      'fileName': fileName,
      'content': content,
    });
  }
}

/// Picks a sync folder using the platform-appropriate mechanism. Returns null
/// when the user cancels. Android opens the SAF tree picker (persistable
/// permission); desktop opens the native directory picker.
Future<SyncFolder?> pickSyncFolder({MethodChannel? safChannel}) async {
  if (kIsWeb) return null; // Web sync deferred to v0.4.
  if (defaultTargetPlatform == TargetPlatform.android) {
    final channel = safChannel ?? const MethodChannel('app.nowpill/sync');
    final result = await channel.invokeMethod<Map<Object?, Object?>>(
      'pickFolder',
    );
    if (result == null) return null;
    final uri = result['uri'] as String?;
    if (uri == null) return null;
    return SafSyncFolder(
      uri,
      channel: channel,
      label: result['label'] as String?,
    );
  }
  if (defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows) {
    final uri = await FilePicker.pickDirectory(
      dialogTitle: 'Choose the NowPill sync folder',
    );
    if (uri == null) return null;
    return IoSyncFolder(uri.toFilePath());
  }
  return null; // iOS folder sync needs a Mac-verified document picker; v0.4.
}

/// Rebuilds a [SyncFolder] from a persisted handle.
SyncFolder? syncFolderFromHandle(String handle) {
  if (handle.isEmpty) return null;
  if (handle.startsWith('content://')) return SafSyncFolder(handle);
  return IoSyncFolder(handle);
}

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
