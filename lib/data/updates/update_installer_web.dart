import '../../domain/update_checker.dart';
import 'update_installer_base.dart';

/// Web has no direct filesystem/install access: releases open in a new tab.
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

UpdateInstaller createUpdateInstaller() => const UnsupportedUpdateInstaller();
