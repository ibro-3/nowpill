import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/updates/github_release_service.dart';
import 'package:nowpill/data/updates/update_coordinator.dart';
import 'package:nowpill/data/updates/update_installer.dart';
import 'package:nowpill/domain/update_checker.dart';

ReleaseInfo release(String version) => ReleaseInfo(
  version: version,
  tag: 'v$version',
  notes: 'notes',
  assets: [
    ReleaseAsset(
      name: 'nowpill-$version-arm64-v8a.apk',
      url: 'https://github.com/o/arm64.apk',
      size: 24,
    ),
    ReleaseAsset(
      name: 'nowpill-$version-universal.apk',
      url: 'https://github.com/o/universal.apk',
      size: 71,
    ),
    const ReleaseAsset(
      name: 'SHA256SUMS-android',
      url: 'https://github.com/o/sums',
      size: 1,
    ),
  ],
);

class _FakeSource implements ReleaseSource {
  _FakeSource(this.result);

  ReleaseFetchResult result;
  final fetched = <String>[];
  String? lastEtag;

  @override
  Future<ReleaseFetchResult> fetchLatest({String? etag}) async {
    lastEtag = etag;
    return result;
  }

  @override
  Future<String> fetchChecksums(String url) async {
    fetched.add(url);
    return '${'a' * 64}  nowpill-0.10.0-arm64-v8a.apk\n';
  }

  @override
  void close() {}
}

class _FakeInstaller extends UpdateInstaller {
  @override
  bool get supportsInstall => true;

  final progress = <double>[];
  String? installedSha;
  String? installedName;
  bool installResult = true;

  @override
  Future<String?> preferredAbi() async => 'arm64-v8a';

  @override
  Future<String> download(
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.5);
    onProgress?.call(1.0);
    return '42';
  }

  @override
  Future<bool> install(
    String handle, {
    String? expectedSha256,
    String? fileName,
  }) async {
    installedSha = expectedSha256;
    installedName = fileName;
    return installResult;
  }

  @override
  Future<bool> canInstall() async => true;
}

void main() {
  UpdateCoordinator coordinatorFor(
    _FakeSource source,
    _FakeInstaller installer,
    List<UpdateState> states,
  ) {
    return UpdateCoordinator(
      service: source,
      installer: installer,
      currentVersion: () => '0.9.6',
      onState: states.add,
      onChecked: (_) {},
    );
  }

  test(
    'checkNow publishes checking then available and caches the ETag',
    () async {
      final source = _FakeSource(
        ReleaseFetchResult(release: release('0.10.0'), etag: 'etag-1'),
      );
      final states = <UpdateState>[];
      final coordinator = coordinatorFor(source, _FakeInstaller(), states);

      await coordinator.checkNow();
      expect(states.map((s) => s.status), [
        UpdateStatus.checking,
        UpdateStatus.available,
      ]);
      expect(states.last.release?.version, '0.10.0');

      await coordinator.checkNow();
      expect(source.lastEtag, 'etag-1');
      coordinator.dispose();
    },
  );

  test('unchanged version yields upToDate; 304 yields upToDate too', () async {
    final source = _FakeSource(
      ReleaseFetchResult(release: release('0.9.6'), etag: 'etag'),
    );
    final states = <UpdateState>[];
    final coordinator = coordinatorFor(source, _FakeInstaller(), states);
    await coordinator.checkNow();
    expect(states.last.status, UpdateStatus.upToDate);

    source.result = const ReleaseFetchResult(notModified: true);
    await coordinator.checkNow();
    expect(states.last.status, UpdateStatus.upToDate);
    coordinator.dispose();
  });

  test('errors are reported without throwing', () async {
    final source = _FakeSource(ReleaseFetchResult(release: release('0.10.0')));
    final states = <UpdateState>[];
    final coordinator = coordinatorFor(source, _FakeInstaller(), states);
    // A throwing source still produces an error state.
    final throwing = _ThrowingSource();
    final errorCoordinator = UpdateCoordinator(
      service: throwing,
      installer: _FakeInstaller(),
      currentVersion: () => '0.9.6',
      onState: states.add,
      onChecked: (_) {},
    );
    await errorCoordinator.checkNow();
    expect(states.last.status, UpdateStatus.error);
    expect(states.last.message, contains('rate limit'));
    coordinator.dispose();
    errorCoordinator.dispose();
  });

  test('download verifies and installs the ABI-specific asset', () async {
    final source = _FakeSource(ReleaseFetchResult(release: release('0.10.0')));
    final installer = _FakeInstaller();
    final states = <UpdateState>[];
    final coordinator = coordinatorFor(source, installer, states);

    final ok = await coordinator.downloadAndInstall(release('0.10.0'));
    expect(ok, isTrue);
    expect(source.fetched.single, 'https://github.com/o/sums');
    expect(installer.installedName, 'nowpill-0.10.0-arm64-v8a.apk');
    expect(installer.installedSha, 'a' * 64);
    expect(states.last.status, UpdateStatus.downloaded);
    coordinator.dispose();
  });
}

class _ThrowingSource implements ReleaseSource {
  @override
  Future<ReleaseFetchResult> fetchLatest({String? etag}) async =>
      throw const UpdateRateLimitException();

  @override
  Future<String> fetchChecksums(String url) async => '';

  @override
  void close() {}
}
