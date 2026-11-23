import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Opens a native (mobile/desktop) SQLite connection backed by a file in the
/// application documents directory.
///
/// Uses [NativeDatabase.createInBackground] so database work runs off the UI
/// isolate. sqlite3 3.x bundles its native library via build hooks, so no
/// manual library loading is required.
Future<QueryExecutor> openConnection() async {
  // Optional override for demos/tests: NOWPILL_DB_PATH points at an alternate
  // database file (never used in production builds).
  final override = Platform.environment['NOWPILL_DB_PATH'];
  final String path;
  if (override != null && override.isNotEmpty) {
    path = override;
  } else {
    final dir = await getApplicationDocumentsDirectory();
    path = p.join(dir.path, 'nowpill.sqlite');
  }
  return NativeDatabase.createInBackground(File(path));
}
