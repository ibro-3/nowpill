import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves the database file path. Honors the `NOWPILL_DB_PATH` override
/// (demos/tests), otherwise `<application documents>/nowpill.sqlite`.
///
/// Shared by the main connection and the notification background handler
/// (Phase 22) so both open the exact same file.
Future<String> resolveDatabasePath() async {
  final override = Platform.environment['NOWPILL_DB_PATH'];
  if (override != null && override.isNotEmpty) return override;
  final dir = await getApplicationDocumentsDirectory();
  return p.join(dir.path, 'nowpill.sqlite');
}

/// Opens a native (mobile/desktop) SQLite connection backed by a file in the
/// application documents directory.
///
/// Uses [NativeDatabase.createInBackground] so database work runs off the UI
/// isolate. sqlite3 3.x bundles its native library via build hooks, so no
/// manual library loading is required.
Future<QueryExecutor> openConnection() async {
  final path = await resolveDatabasePath();
  return NativeDatabase.createInBackground(File(path));
}
