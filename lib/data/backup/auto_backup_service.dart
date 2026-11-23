import 'dart:io';

import 'package:path/path.dart' as p;

import '../export/export_service.dart';

/// Rotating daily local backups — a safety net that needs no user action.
///
/// On the first app launch of a day the coordinator writes a full v3 envelope
/// to `<documents>/nowpill-backups/nowpill-auto-YYYY-MM-DD.json` and prunes
/// older files beyond [keep]. Restoring is always explicit (Settings list →
/// confirm → replace-all); nothing is ever restored automatically.
class AutoBackupService {
  AutoBackupService({
    required this._export,
    required this._directoryPath,
    this.keep = 7,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ExportService _export;
  final String _directoryPath;
  final DateTime Function() _clock;

  /// How many daily snapshots to keep.
  final int keep;

  static const String prefix = 'nowpill-auto-';
  static const String suffix = '.json';

  Directory get directory => Directory(_directoryPath);

  String fileNameFor(DateTime day) => '$prefix${_dayKey(day)}$suffix';

  String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Writes today's snapshot if it does not exist yet, then prunes. Returns
  /// the file written, or null when today's backup already existed. Never
  /// throws — a failing backup must not affect the app.
  Future<File?> runDailyBackup() async {
    try {
      final dir = directory;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final target = File(p.join(dir.path, fileNameFor(_clock())));
      if (target.existsSync()) return null;
      final json = await _export.exportToString();
      // Write-then-rename: a crash mid-write never leaves a partial snapshot
      // that a later launch would treat as today's finished backup.
      final temp = File('${target.path}.tmp');
      temp.writeAsStringSync(json, flush: true);
      temp.renameSync(target.path);
      prune();
      return target;
    } catch (_) {
      return null;
    }
  }

  /// Deletes the oldest snapshots beyond [keep]. Returns files removed.
  List<File> prune() {
    final files = listBackups();
    if (files.length <= keep) return const [];
    // Names are date-keyed, so lexical order == chronological order.
    final excess = files.sublist(0, files.length - keep);
    final removed = <File>[];
    for (final f in excess) {
      try {
        f.deleteSync();
        removed.add(f);
      } catch (_) {
        // Leave undeletable files; next run retries.
      }
    }
    return removed;
  }

  /// Existing snapshots, oldest first.
  List<File> listBackups() {
    final dir = directory;
    if (!dir.existsSync()) return const [];
    final files =
        dir.listSync().whereType<File>().where((f) {
            final name = p.basename(f.path);
            return name.startsWith(prefix) && name.endsWith(suffix);
          }).toList()
          ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return files;
  }

  /// Reads a snapshot for the restore flow. Throws on unreadable files (the
  /// caller reports the failure); validation happens in the import path.
  String readBackup(File file) => file.readAsStringSync();
}
