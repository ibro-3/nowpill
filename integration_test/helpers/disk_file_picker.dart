import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';

/// A disk-backed stand-in for the platform file picker in integration tests.
///
/// The real Linux picker is a D-Bus portal dialog (not a mockable platform
/// channel), so tests swap in this implementation of [FilePickerPlatform].
/// Everything above it is the production path: Settings → BackupService →
/// ExportService, real JSON bytes written to and read from real files.
///
/// Call [install] before booting the app; restore with [uninstall] afterwards.
class DiskFilePicker extends FilePickerPlatform {
  DiskFilePicker(this.directory);

  /// The folder used for both saving exports and picking imports.
  final Directory directory;

  /// The most recent path passed to `saveFile` (the export target).
  String? lastSavedPath;

  /// The next path `pickFile` returns; set this before tapping Import.
  String? nextPickPath;

  static FilePickerPlatform? _previous;

  /// Installs this picker as the platform implementation.
  void install() {
    _previous = FilePickerPlatform.instance;
    FilePickerPlatform.instance = this;
  }

  /// Restores the previous platform implementation.
  void uninstall() {
    final previous = _previous;
    if (previous != null) FilePickerPlatform.instance = previous;
    _previous = null;
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    void Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes);
    lastSavedPath = file.path;
    return file.uri;
  }

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    final path = nextPickPath;
    if (path == null) return null; // Simulates the user cancelling.
    return _DiskPlatformFile(path);
  }
}

/// Minimal [PlatformFile] over a file on disk.
base class _DiskPlatformFile extends PlatformFile {
  _DiskPlatformFile(String path)
    : file = File(path),
      name = path.split(Platform.pathSeparator).last;

  final File file;

  @override
  final String name;

  @override
  Uri get uri => file.uri;

  @override
  XFile get xFile => XFile(file.path, name: name);

  @override
  int? lengthSync() => file.existsSync() ? file.lengthSync() : null;

  @override
  Future<int?> length() async => file.existsSync() ? file.length() : null;

  @override
  Future<Uint8List> readAsBytes() => file.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      file.openRead().map(Uint8List.fromList);
}
