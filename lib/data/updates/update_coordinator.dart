import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/settings/app_settings.dart';
import '../../core/settings/app_settings_provider.dart';
import '../../domain/update_checker.dart';
import 'github_release_service.dart';
import 'update_installer.dart';

part 'update_coordinator.g.dart';

/// Provides the real app version (the About card previously hardcoded 0.9.2).
final packageInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});

enum UpdateStatus { idle, checking, available, upToDate, error, downloaded }

class UpdateState {
  const UpdateState({
    this.status = UpdateStatus.idle,
    this.release,
    this.message,
    this.progress = 0,
    this.lastChecked,
  });

  final UpdateStatus status;
  final ReleaseInfo? release;
  final String? message;
  final double progress;
  final DateTime? lastChecked;
}

@Riverpod(keepAlive: true)
class UpdateStateNotifier extends _$UpdateStateNotifier {
  @override
  UpdateState build() => const UpdateState();
  void set(UpdateState state) => this.state = state;
}

/// Owns the update check timer and the download/install flow.
class UpdateCoordinator {
  UpdateCoordinator({
    required this.service,
    required this.installer,
    required this.currentVersion,
    required this.onState,
    required this.onChecked,
  });

  final ReleaseSource service;
  final UpdateInstaller installer;
  final String Function() currentVersion;
  final void Function(UpdateState state) onState;
  final void Function(DateTime at) onChecked;

  Timer? _timer;
  String? _etag;
  UpdateCheckMode _mode = UpdateCheckMode.startup;
  bool _disposed = false;

  UpdatePlatform get _platform {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return UpdatePlatform.android;
    }
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return UpdatePlatform.linux;
    }
    return UpdatePlatform.other;
  }

  void start() {
    _schedule();
    // Defer the first check so the provider is not modified while building.
    if (_mode == UpdateCheckMode.startup) {
      Future<void>.microtask(() {
        if (!_disposed) checkNow();
      });
    }
  }

  void setMode(UpdateCheckMode mode) {
    if (_mode == mode && _timer != null) return;
    _mode = mode;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    final duration = switch (_mode) {
      UpdateCheckMode.daily => const Duration(days: 1),
      UpdateCheckMode.weekly => const Duration(days: 7),
      _ => null,
    };
    if (duration != null) {
      // In-process only: periodic checks run while the app is open.
      _timer = Timer.periodic(duration, (_) => checkNow());
    }
  }

  Future<void> checkNow() async {
    if (_disposed) return;
    onState(const UpdateState(status: UpdateStatus.checking));
    try {
      final result = await service.fetchLatest(etag: _etag);
      if (_disposed) {
        return;
      }
      onChecked(DateTime.now().toUtc());
      if (result.notModified) {
        onState(
          UpdateState(
            status: UpdateStatus.upToDate,
            lastChecked: DateTime.now(),
          ),
        );
        return;
      }
      _etag = result.etag;
      final release = result.release;
      if (release == null) {
        throw const FormatException('No release in response');
      }
      final newer = isNewerVersion(release.version, currentVersion());
      onState(
        UpdateState(
          status: newer ? UpdateStatus.available : UpdateStatus.upToDate,
          release: release,
          lastChecked: DateTime.now(),
        ),
      );
    } catch (e) {
      if (!_disposed) {
        onState(
          UpdateState(
            status: UpdateStatus.error,
            message: e.toString(),
            lastChecked: DateTime.now(),
          ),
        );
      }
    }
  }

  /// Downloads the best asset for this device, verifies its SHA-256 and hands
  /// it to the platform installer. Returns true when the hand-off succeeded.
  Future<bool> downloadAndInstall(ReleaseInfo release) async {
    final asset = selectAsset(
      release,
      _platform,
      abi: await installer.preferredAbi(),
    );
    if (asset == null || _disposed) return false;

    onState(
      UpdateState(status: UpdateStatus.checking, release: release, progress: 0),
    );
    try {
      final expected = await _expectedChecksum(release, asset.name);
      final handle = await installer.download(
        asset,
        onProgress: (value) {
          if (_disposed) return;
          onState(
            UpdateState(
              status: UpdateStatus.checking,
              release: release,
              progress: value,
            ),
          );
        },
      );
      final ok = await installer.install(
        handle,
        expectedSha256: expected,
        fileName: asset.name,
      );
      if (_disposed) return ok;
      onState(
        UpdateState(
          status: ok ? UpdateStatus.downloaded : UpdateStatus.error,
          release: release,
          message: ok ? null : 'Verification or install failed',
          lastChecked: DateTime.now(),
        ),
      );
      return ok;
    } catch (e) {
      if (!_disposed) {
        onState(
          UpdateState(
            status: UpdateStatus.error,
            release: release,
            message: e.toString(),
          ),
        );
      }
      return false;
    }
  }

  Future<bool> canInstall() => installer.canInstall();

  Future<void> openInstallSettings() => installer.openInstallSettings();

  Future<String?> _expectedChecksum(
    ReleaseInfo release,
    String fileName,
  ) async {
    final suffix = _platform == UpdatePlatform.android
        ? 'SHA256SUMS-android'
        : 'SHA256SUMS-linux';
    final sums = release.assets.where(
      (a) => a.name == suffix || a.name == 'SHA256SUMS',
    );
    if (sums.isEmpty) return null;
    final raw = await service.fetchChecksums(sums.first.url);
    return parseChecksums(raw)[fileName];
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

@Riverpod(keepAlive: true)
UpdateCoordinator updateCoordinator(Ref ref) {
  final service = GithubReleaseService();
  final installer = createUpdateInstaller();
  final coordinator = UpdateCoordinator(
    service: service,
    installer: installer,
    currentVersion: () =>
        ref.read(packageInfoProvider).value?.version ?? '0.0.0',
    onState: (state) => ref.read(updateStateProvider.notifier).set(state),
    onChecked: (at) =>
        ref.read(appSettingsProvider.notifier).recordUpdateCheck(at),
  );

  ref.listen<AsyncValue<AppSettings>>(appSettingsProvider, (prev, next) {
    final settings = next.value;
    if (settings != null) coordinator.setMode(settings.updateCheckMode);
  }, fireImmediately: true);

  ref.onDispose(() {
    coordinator.dispose();
    service.close();
  });
  // No unsolicited network checks in debug/test builds; manual checks still work.
  if (!kDebugMode) {
    coordinator.start();
  }
  return coordinator;
}
