import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'sync_folder_base.dart';
import 'web_sync_platform_stub.dart'
    if (dart.library.js_interop) 'web_sync_platform_web.dart'
    as web_platform;

export 'sync_folder_base.dart';

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

/// Whether folder sync can work on this platform. Web requires a Chromium
/// browser exposing the File System Access directory picker.
bool get isSyncFolderSupported {
  if (kIsWeb) return web_platform.webFolderSyncSupported;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;
}

/// Picks a sync folder using the platform-appropriate mechanism. Returns null
/// when the user cancels. Android opens the SAF tree picker (persistable
/// permission), desktop opens the native directory picker, and Chromium web
/// opens the File System Access directory picker.
Future<SyncFolder?> pickSyncFolder({MethodChannel? safChannel}) async {
  if (kIsWeb) return web_platform.pickWebSyncFolder();
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
  final webFolder = web_platform.webSyncFolderFromHandle(handle);
  if (webFolder != null) return webFolder;
  if (handle.startsWith('content://')) return SafSyncFolder(handle);
  return IoSyncFolder(handle);
}
