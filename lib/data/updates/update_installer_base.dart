import '../../domain/update_checker.dart';

/// Platform-specific download/install step after an update is found.
abstract class UpdateInstaller {
  const UpdateInstaller();

  /// Whether this platform can hand an artifact to an installer.
  bool get supportsInstall;

  /// Downloads [asset] and returns a platform handle (download id on Android,
  /// absolute file path on Linux).
  Future<String> download(
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
  });

  /// Verifies and installs (Android) or reveals (Linux) the downloaded file.
  Future<bool> install(
    String handle, {
    String? expectedSha256,
    String? fileName,
  });

  /// Android split-APK ABI hint (e.g. arm64-v8a); null when not applicable.
  Future<String?> preferredAbi() async => null;

  Future<bool> canInstall() async => true;
  Future<void> openInstallSettings() async {}
}
