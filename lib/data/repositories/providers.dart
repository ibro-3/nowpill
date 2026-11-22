import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../db/app_database.dart';
import '../export/export_service.dart';
import 'habit_repository.dart';
import 'tag_repository.dart';
import 'task_repository.dart';

part 'providers.g.dart';

/// The single shared [AppDatabase] instance for the app.
///
/// Disposed when the provider scope closes. Tests override this with an
/// in-memory database.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}

@Riverpod(keepAlive: true)
TaskRepository taskRepository(Ref ref) {
  return TaskRepository(ref.watch(appDatabaseProvider));
}

@Riverpod(keepAlive: true)
HabitRepository habitRepository(Ref ref) {
  return HabitRepository(ref.watch(appDatabaseProvider));
}

@Riverpod(keepAlive: true)
TagRepository tagRepository(Ref ref) {
  return TagRepository(ref.watch(appDatabaseProvider));
}

@Riverpod(keepAlive: true)
ExportService exportService(Ref ref) {
  return ExportService(ref.watch(appDatabaseProvider));
}
