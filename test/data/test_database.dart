import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:nowpill/data/db/app_database.dart';

/// Creates a fresh in-memory database for a test. The caller must close it.
///
/// Each test uses its own isolated in-memory executor, so drift's
/// "multiple databases" warning (which guards against sharing one executor)
/// does not apply here.
AppDatabase createTestDatabase() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase.withExecutor(NativeDatabase.memory());
}
