import 'sync_folder_base.dart';

/// Non-web builds have no File System Access API.
bool get webFolderSyncSupported => false;

/// Web sync is unavailable in non-web builds.
Future<SyncFolder?> pickWebSyncFolder() async => null;

/// Web handles cannot be rebuilt on non-web platforms.
SyncFolder? webSyncFolderFromHandle(String handle) => null;
