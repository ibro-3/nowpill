import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/update_checker.dart';
import 'update_installer_base.dart';

/// Android uses the system DownloadManager and an install intent.
class AndroidUpdateInstaller extends UpdateInstaller {
  const AndroidUpdateInstaller();

  static const MethodChannel _channel = MethodChannel('app.nowpill/update');

  @override
  bool get supportsInstall => true;

  @override
  Future<String> download(
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    final id = await _channel.invokeMethod<int>('download', {
      'url': asset.url,
      'fileName': asset.name,
    });
    if (id == null) throw StateError('No download id returned');
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    while (DateTime.now().isBefore(deadline)) {
      final status = await _channel.invokeMapMethod<String, Object>(
        'status',
        id,
      );
      final code = status?['status'];
      if (code == 4) return id.toString(); // DownloadManager.STATUS_SUCCESSFUL
      if (code == 5 || code == 16) {
        throw StateError('Download failed');
      }
      final received = (status?['received'] as int?) ?? 0;
      final total = (status?['total'] as int?) ?? 0;
      onProgress?.call(total > 0 ? received / total : 0);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw TimeoutException('Update download timed out');
  }

  @override
  Future<bool> install(
    String handle, {
    String? expectedSha256,
    String? fileName,
  }) async {
    final installed = await _channel.invokeMethod<bool>('verifyAndInstall', {
      'id': int.tryParse(handle),
      'sha256': expectedSha256,
      'fileName': fileName,
    });
    if (installed == true) return true;
    // The user may need to grant "install unknown apps" first.
    if (!await canInstall()) await openInstallSettings();
    return false;
  }

  @override
  Future<String?> preferredAbi() async {
    final abis = await _channel.invokeMethod<List<dynamic>>('abis');
    if (abis == null || abis.isEmpty) return null;
    return abis.first.toString();
  }

  @override
  Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;

  @override
  Future<void> openInstallSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');
}

/// Linux saves the tarball to Downloads, verifies it, then reveals the folder.
/// Self-replacement of a running executable is deliberately not attempted.
class LinuxUpdateInstaller extends UpdateInstaller {
  const LinuxUpdateInstaller();

  @override
  bool get supportsInstall => false;

  @override
  Future<String> download(
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    final directory = await getDownloadsDirectory();
    final targetDir =
        directory ??
        Directory('${Platform.environment['HOME'] ?? '.'}/Downloads');
    await targetDir.create(recursive: true);
    final target = File(
      '${targetDir.path}${Platform.pathSeparator}${asset.name}',
    );
    final temporary = File('${target.path}.part');

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(asset.url));
      request.headers.set('User-Agent', 'NowPill-Updater');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      final sink = temporary.openWrite();
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(total > 0 ? received / total : 0);
      }
      await sink.close();
    } finally {
      client.close(force: true);
    }

    if (target.existsSync()) await target.delete();
    await temporary.rename(target.path);
    return target.path;
  }

  @override
  Future<bool> install(
    String handle, {
    String? expectedSha256,
    String? fileName,
  }) async {
    final file = File(handle);
    if (!file.existsSync()) return false;
    if (expectedSha256 != null) {
      final digest = sha256.convert(await file.readAsBytes()).toString();
      if (digest.toLowerCase() != expectedSha256.toLowerCase()) return false;
    }
    try {
      final result = await Process.run('xdg-open', [file.parent.path]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

UpdateInstaller createUpdateInstaller() {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return const AndroidUpdateInstaller();
  }
  if (defaultTargetPlatform == TargetPlatform.linux) {
    return const LinuxUpdateInstaller();
  }
  return const UnsupportedUpdateInstaller();
}

/// Used on platforms without an in-app download path (web, iOS, macOS, Windows).
class UnsupportedUpdateInstaller extends UpdateInstaller {
  const UnsupportedUpdateInstaller();

  @override
  bool get supportsInstall => false;

  @override
  Future<String> download(
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
  }) async => throw UnsupportedError(
    'Updates are downloaded from the releases page on this platform',
  );

  @override
  Future<bool> install(
    String handle, {
    String? expectedSha256,
    String? fileName,
  }) async => false;
}
