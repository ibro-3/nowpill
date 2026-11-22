import 'dart:convert';

import '../db/app_database.dart';

/// Current export envelope schema version. Bump when the payload shape changes
/// and add a migration path in `ExportService.importFromString`.
const int kExportSchemaVersion = 1;

/// Thrown when an import payload is malformed or unsupported.
class ImportFormatException implements Exception {
  ImportFormatException(this.message);
  final String message;
  @override
  String toString() => 'ImportFormatException: $message';
}

/// Versioned backup envelope.
class ExportEnvelope {
  const ExportEnvelope({
    required this.schemaVersion,
    required this.exportedAt,
    required this.tasks,
    required this.subtasks,
    required this.tags,
    required this.taskTags,
    required this.habits,
    required this.checkins,
  });

  /// Parses and validates an envelope. Throws [ImportFormatException] on
  /// malformed or unsupported payloads.
  factory ExportEnvelope.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version is! int) {
      throw ImportFormatException('Missing or invalid schemaVersion.');
    }
    if (version != kExportSchemaVersion) {
      throw ImportFormatException(
        'Unsupported schemaVersion $version (expected $kExportSchemaVersion).',
      );
    }
    final exportedAt = json['exportedAt'];
    if (exportedAt is! int) {
      throw ImportFormatException('Missing or invalid exportedAt.');
    }
    final data = json['data'];
    if (data is! Map<String, Object?>) {
      throw ImportFormatException('Missing data object.');
    }

    List<Map<String, dynamic>> rows(String key) {
      final value = data[key];
      if (value is! List) {
        throw ImportFormatException('Missing or invalid "$key" list.');
      }
      return value.cast<Map<String, dynamic>>();
    }

    try {
      return ExportEnvelope(
        schemaVersion: version,
        exportedAt: DateTime.fromMillisecondsSinceEpoch(
          exportedAt,
          isUtc: true,
        ),
        tasks: rows('tasks').map(Task.fromJson).toList(),
        subtasks: rows('subtasks').map(Subtask.fromJson).toList(),
        tags: rows('tags').map(Tag.fromJson).toList(),
        taskTags: rows('taskTags').map(TaskTag.fromJson).toList(),
        habits: rows('habits').map(Habit.fromJson).toList(),
        checkins: rows('checkins').map(HabitCheckin.fromJson).toList(),
      );
    } on ImportFormatException {
      rethrow;
    } catch (e) {
      throw ImportFormatException('Failed to decode rows: $e');
    }
  }

  final int schemaVersion;
  final DateTime exportedAt;
  final List<Task> tasks;
  final List<Subtask> subtasks;
  final List<Tag> tags;
  final List<TaskTag> taskTags;
  final List<Habit> habits;
  final List<HabitCheckin> checkins;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'exportedAt': exportedAt.toUtc().millisecondsSinceEpoch,
    'data': {
      'tasks': tasks.map((t) => t.toJson()).toList(),
      'subtasks': subtasks.map((s) => s.toJson()).toList(),
      'tags': tags.map((t) => t.toJson()).toList(),
      'taskTags': taskTags.map((t) => t.toJson()).toList(),
      'habits': habits.map((h) => h.toJson()).toList(),
      'checkins': checkins.map((c) => c.toJson()).toList(),
    },
  };
}

/// Exports the full database to a versioned JSON envelope and restores it via
/// a replace-all transaction.
class ExportService {
  ExportService(this._db);

  final AppDatabase _db;

  /// Serializes the entire database to a pretty-printed JSON string.
  Future<String> exportToString() async {
    final envelope = await _collect();
    return const JsonEncoder.withIndent('  ').convert(envelope.toJson());
  }

  Future<ExportEnvelope> _collect() async {
    return ExportEnvelope(
      schemaVersion: kExportSchemaVersion,
      exportedAt: DateTime.now().toUtc(),
      tasks: await _db.select(_db.tasks).get(),
      subtasks: await _db.select(_db.subtasks).get(),
      tags: await _db.select(_db.tags).get(),
      taskTags: await _db.select(_db.taskTags).get(),
      habits: await _db.select(_db.habits).get(),
      checkins: await _db.select(_db.habitCheckins).get(),
    );
  }

  /// Parses [json] and replaces all data in a single transaction. On any
  /// failure the transaction rolls back, leaving the database untouched.
  ///
  /// Returns the imported envelope (for confirmation UI / reminder reschedule).
  Future<ExportEnvelope> importFromString(String json) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (e) {
      throw ImportFormatException('Invalid JSON: $e');
    }
    if (decoded is! Map<String, Object?>) {
      throw ImportFormatException('Top-level JSON must be an object.');
    }
    final envelope = ExportEnvelope.fromJson(decoded);
    await _replaceAll(envelope);
    return envelope;
  }

  Future<void> _replaceAll(ExportEnvelope e) async {
    await _db.transaction(() async {
      // Delete children before parents (FK-safe even with cascades enabled).
      await _db.delete(_db.habitCheckins).go();
      await _db.delete(_db.taskTags).go();
      await _db.delete(_db.subtasks).go();
      await _db.delete(_db.tasks).go();
      await _db.delete(_db.habits).go();
      await _db.delete(_db.tags).go();

      // Insert parents before children. Explicit ids are preserved so links
      // remain valid.
      await _db.batch((b) {
        b.insertAll(_db.tags, e.tags);
        b.insertAll(_db.habits, e.habits);
        b.insertAll(_db.tasks, e.tasks);
        b.insertAll(_db.subtasks, e.subtasks);
        b.insertAll(_db.taskTags, e.taskTags);
        b.insertAll(_db.habitCheckins, e.checkins);
      });
    });
  }
}
