import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../export/export_service.dart';

/// Outcome of an export attempt, for the Settings UI to report.
enum ExportOutcome {
  /// A file was saved (desktop) or the share sheet completed (mobile/web).
  shared,

  /// The user dismissed the save dialog / share sheet.
  cancelled,

  /// The platform could not complete the export.
  failed,
}

/// User-facing backup operations: export the database to a JSON file and
/// restore from one. The pure validate/restore steps delegate to
/// [ExportService]; this layer adds platform file I/O (save dialog on desktop,
/// share sheet on mobile, download on web).
class BackupService {
  BackupService(this._export);

  final ExportService _export;

  /// Suggested backup file name, e.g. `nowpill-backup-2026-11-23.json`.
  String suggestFileName([DateTime? now]) {
    final d = now ?? DateTime.now();
    final stamp =
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return 'nowpill-backup-$stamp.json';
  }

  /// The full database as a pretty-printed JSON string.
  Future<String> exportToString() => _export.exportToString();

  /// Validates a candidate backup without touching the database. Returns the
  /// parsed envelope so the UI can show a replace-all confirmation summary.
  /// Throws [ImportFormatException] when the payload is invalid.
  ExportEnvelope validate(String json) => _export.parseEnvelope(json);

  /// Replaces all data with [json] in a single transaction. Returns the
  /// imported envelope. Throws [ImportFormatException] on invalid payloads
  /// (the database is left untouched on any failure).
  Future<ExportEnvelope> restore(String json) => _export.importFromString(json);

  /// Exports to a file. Desktop opens a save dialog; mobile opens the share
  /// sheet; web triggers a download. Returns the outcome for the UI.
  Future<ExportOutcome> exportToFile() async {
    final String json;
    try {
      json = await exportToString();
    } catch (_) {
      return ExportOutcome.failed;
    }
    final bytes = Uint8List.fromList(utf8.encode(json));
    final fileName = suggestFileName();

    try {
      if (kIsWeb) {
        // On web, saveFile triggers a browser download.
        final uri = await FilePicker.saveFile(
          fileName: fileName,
          bytes: bytes,
          mimeType: 'application/json',
        );
        return uri == null ? ExportOutcome.cancelled : ExportOutcome.shared;
      }
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        final result = await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                bytes,
                mimeType: 'application/json',
                name: fileName,
              ),
            ],
            fileNameOverrides: [fileName],
            subject: 'NowPill backup',
          ),
        );
        return result.status == ShareResultStatus.success
            ? ExportOutcome.shared
            : ExportOutcome.cancelled;
      }
      // Desktop (Linux/macOS/Windows): native save dialog.
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save NowPill backup',
        fileName: fileName,
        bytes: bytes,
        mimeType: 'application/json',
      );
      return uri == null ? ExportOutcome.cancelled : ExportOutcome.shared;
    } catch (_) {
      return ExportOutcome.failed;
    }
  }

  /// Opens a file picker and reads the selected backup as a string. Returns
  /// null if the user cancels. Throws on read failure.
  Future<String?> pickBackupFile() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose a NowPill backup',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return utf8.decode(bytes);
  }
}
