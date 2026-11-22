import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Opens a web SQLite connection using the locally-served `sqlite3.wasm` and
/// `drift_worker.js` assets (see `web/`). Drift picks the best available
/// storage (OPFS with a shared worker, falling back to IndexedDB).
Future<QueryExecutor> openConnection() async {
  final result = await WasmDatabase.open(
    databaseName: 'nowpill',
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );
  return result.resolvedExecutor;
}
