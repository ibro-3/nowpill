import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/enums.dart';
import '../../domain/sync_merge.dart';
import '../db/app_database.dart';

/// Current export envelope schema version. Bump when the payload shape changes
/// and add a migration path in `ExportService.importFromString`.
///
/// v8 (v0.10.0) adds the personal chat thought stream: a `chatNotes` list
/// (older payloads import with no notes).
/// v7 (v0.7.0) adds routines and scoped vacation: `routines` + `vacationScopes`
/// lists, `routineId` / `routineUuid` on habits, and `allHabits` on vacations
/// (older payloads import as unrouted habits with all-habits vacations).
/// v6 (v0.6.0) adds quit habits and planned vacation: `relapses` + `vacations`
/// lists and `kind` on habits (older payloads import as build habits).
/// v5 (v0.5.0) adds task lists: a `taskLists` list plus nullable `listId` /
/// `listUuid` on tasks (older payloads import their tasks into the inbox).
/// v4 (v0.3.0) adds measurable habits: per-habit `targetAmount` and per-check-in
/// `amount` (both nullable — pre-v4 rows import as classic habits / full
/// completions).
/// v3 adds cross-device sync identity: per-row `uuid` + `updatedAt`, parent
/// uuid references, a `tombstones` list, and the source `deviceId`.
/// v2 adds the `freezes` list and per-habit `freezeMode`.
/// v1 payloads still import: habits default to auto mode with no freezes;
/// pre-v3 rows receive fresh uuids and derived timestamps.
const int kExportSchemaVersion = 8;

/// Oldest envelope version this build can import.
const int kMinImportSchemaVersion = 1;

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
    required this.taskLists,
    required this.tags,
    required this.taskTags,
    required this.habits,
    required this.checkins,
    required this.relapses,
    required this.vacations,
    required this.routines,
    required this.vacationScopes,
    this.chatNotes = const [],
    this.freezes = const [],
    this.tombstones = const [],
    this.deviceId = '',
  });

  /// Parses and validates an envelope. Throws [ImportFormatException] on
  /// malformed or unsupported payloads. Accepts schema versions
  /// [kMinImportSchemaVersion]…[kExportSchemaVersion]; older payloads are
  /// upgraded (v1 habits become auto-mode with no freezes; pre-v3 rows get
  /// fresh uuids, derived updatedAt values, and resolved parent uuids).
  factory ExportEnvelope.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version is! int) {
      throw ImportFormatException('Missing or invalid schemaVersion.');
    }
    if (version < kMinImportSchemaVersion || version > kExportSchemaVersion) {
      throw ImportFormatException(
        'Unsupported schemaVersion $version '
        '(expected $kMinImportSchemaVersion–$kExportSchemaVersion).',
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
      // v1 payloads predate freezeMode/freezes. Upgrade habit rows to auto mode
      // and treat the freezes list as empty.
      var habitRows = rows('habits').map((h) {
        if (version < 2 && !h.containsKey('freezeMode')) {
          return {...h, 'freezeMode': FreezeMode.auto.index};
        }
        return h;
      }).toList();
      final freezeRows = version >= 2 && data['freezes'] is List
          ? (data['freezes'] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];

      // v5 payloads carry the list table; older ones have none. An absent key
      // is treated as an empty list so old backups still import.
      final taskListRows = version >= 5 && data['taskLists'] is List
          ? (data['taskLists'] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];

      // v6 payloads carry relapse events and planned vacations; older ones
      // have neither (quit habits did not exist).
      final relapseRows = version >= 6 && data['relapses'] is List
          ? (data['relapses'] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      var vacationRows = version >= 6 && data['vacations'] is List
          ? (data['vacations'] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];

      final routineRows = version >= 7 && data['routines'] is List
          ? (data['routines'] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      final scopeRows = version >= 7 && data['vacationScopes'] is List
          ? (data['vacationScopes'] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];

      // v8 payloads carry personal chat notes; earlier ones have none.
      final chatNoteRows = version >= 8 && data['chatNotes'] is List
          ? (data['chatNotes'] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];

      if (version < 7) {
        // Pre-v7 payloads have no routines/scopes. Habits become Unrouted and
        // v6 vacations become all-habits (exactly their original meaning).
        vacationRows = vacationRows
            .map((v) => {...v, 'allHabits': v['allHabits'] ?? true})
            .toList();
        habitRows = habitRows
            .map(
              (h) => {
                ...h,
                'routineId': h['routineId'],
                'routineUuid': h['routineUuid'],
              },
            )
            .toList();
      }

      if (version < 6) {
        // Pre-v6 habits are all "build" habits.
        habitRows = habitRows
            .map(
              (h) => h.containsKey('kind')
                  ? h
                  : {...h, 'kind': HabitKind.build.index},
            )
            .toList();
      }

      var taskRows = rows('tasks');
      var subtaskRows = rows('subtasks');
      var tagRows = rows('tags');
      var taskTagRows = rows('taskTags');
      var checkinRows = rows('checkins');
      var freezeRowsTyped = freezeRows;
      final tombstoneRows = version >= 3 && data['tombstones'] is List
          ? (data['tombstones'] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];

      if (version < 3) {
        // Pre-v3 payloads have no sync identity. Assign fresh uuids to parent
        // rows first, then resolve child parent-uuid references through the
        // payload's local integer ids. Timestamps are derived exactly like the
        // v2→v3 SQL migration so both upgrade paths agree.
        const uuid = Uuid();
        Map<int, String> assignUuids(List<Map<String, dynamic>> rs) {
          final byId = <int, String>{};
          for (var i = 0; i < rs.length; i++) {
            final id = uuid.v4();
            rs[i] = {...rs[i], 'uuid': id};
            final localId = rs[i]['id'];
            if (localId is int) byId[localId] = id;
          }
          return byId;
        }

        int millisOf(Object? v) => v is int ? v : 0;

        final taskUuids = assignUuids(taskRows);
        taskRows = taskRows.map((t) {
          final created = millisOf(t['createdAt']);
          final completed = millisOf(t['completedAt']);
          return {...t, 'updatedAt': completed > created ? completed : created};
        }).toList();

        final habitUuids = assignUuids(habitRows);
        habitRows = habitRows
            .map((h) => {...h, 'updatedAt': millisOf(h['createdAt'])})
            .toList();

        final tagUuids = assignUuids(tagRows);
        tagRows = tagRows.map((t) => {...t, 'updatedAt': 0}).toList();

        subtaskRows = subtaskRows.map((s) {
          final parentId = s['taskId'];
          final parentUuid = parentId is int ? taskUuids[parentId] : null;
          final parent = taskRows.firstWhere(
            (t) => t['id'] == parentId,
            orElse: () => const {},
          );
          return {
            ...s,
            'taskUuid': parentUuid ?? '',
            'updatedAt': millisOf(parent['updatedAt']),
          };
        }).toList();

        taskTagRows = taskTagRows.map((l) {
          final taskId = l['taskId'];
          final tagId = l['tagId'];
          return {
            ...l,
            'taskUuid': (taskId is int ? taskUuids[taskId] : null) ?? '',
            'tagUuid': (tagId is int ? tagUuids[tagId] : null) ?? '',
            'updatedAt': 0,
          };
        }).toList();

        checkinRows = checkinRows.map((c) {
          final habitId = c['habitId'];
          final date = c['date'];
          // Local day at noon UTC — same proxy as the SQL migration.
          final dayMillis = date is String
              ? (DateTime.tryParse('${date}T12:00:00Z')
                        ?.millisecondsSinceEpoch ??
                    0)
              : 0;
          return {
            ...c,
            'habitUuid': (habitId is int ? habitUuids[habitId] : null) ?? '',
            'updatedAt': dayMillis,
          };
        }).toList();

        freezeRowsTyped = freezeRowsTyped.map((f) {
          final habitId = f['habitId'];
          return {
            ...f,
            'habitUuid': (habitId is int ? habitUuids[habitId] : null) ?? '',
            'updatedAt': millisOf(f['createdAt']),
          };
        }).toList();
      }

      if (version < 5) {
        // Pre-v5 tasks have no list link; they become inbox tasks.
        taskRows = taskRows
            .map(
              (t) => {...t, 'listId': t['listId'], 'listUuid': t['listUuid']},
            )
            .toList();
      }

      if (version < 4) {
        // Pre-v4 payloads have no measurable-habit fields. Null target =
        // classic habit; null amount = full completion (streaks unchanged).
        habitRows = habitRows
            .map(
              (h) => h.containsKey('targetAmount')
                  ? h
                  : {...h, 'targetAmount': null},
            )
            .toList();
        checkinRows = checkinRows
            .map((c) => c.containsKey('amount') ? c : {...c, 'amount': null})
            .toList();
      }

      return ExportEnvelope(
        schemaVersion: kExportSchemaVersion,
        exportedAt: DateTime.fromMillisecondsSinceEpoch(
          exportedAt,
          isUtc: true,
        ),
        deviceId: json['deviceId'] is String ? json['deviceId'] as String : '',
        tasks: taskRows.map(Task.fromJson).toList(),
        subtasks: subtaskRows.map(Subtask.fromJson).toList(),
        taskLists: taskListRows.map(TaskList.fromJson).toList(),
        tags: tagRows.map(Tag.fromJson).toList(),
        taskTags: taskTagRows.map(TaskTag.fromJson).toList(),
        habits: habitRows.map(Habit.fromJson).toList(),
        checkins: checkinRows.map(HabitCheckin.fromJson).toList(),
        relapses: relapseRows.map(HabitRelapse.fromJson).toList(),
        vacations: vacationRows.map(VacationPeriod.fromJson).toList(),
        routines: routineRows.map(Routine.fromJson).toList(),
        vacationScopes: scopeRows.map(VacationScope.fromJson).toList(),
        chatNotes: chatNoteRows.map(ChatNote.fromJson).toList(),
        freezes: freezeRowsTyped.map(HabitFreeze.fromJson).toList(),
        tombstones: tombstoneRows.map(Tombstone.fromJson).toList(),
      );
    } on ImportFormatException {
      rethrow;
    } catch (e) {
      throw ImportFormatException('Failed to decode rows: $e');
    }
  }

  final int schemaVersion;
  final DateTime exportedAt;

  /// The device that produced this envelope (empty for pre-v3 payloads).
  final String deviceId;

  final List<Task> tasks;
  final List<Subtask> subtasks;
  final List<TaskList> taskLists;
  final List<Tag> tags;
  final List<TaskTag> taskTags;
  final List<Habit> habits;
  final List<HabitCheckin> checkins;
  final List<HabitRelapse> relapses;
  final List<VacationPeriod> vacations;
  final List<Routine> routines;
  final List<VacationScope> vacationScopes;
  final List<ChatNote> chatNotes;
  final List<HabitFreeze> freezes;
  final List<Tombstone> tombstones;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'exportedAt': exportedAt.toUtc().millisecondsSinceEpoch,
    'deviceId': deviceId,
    'data': {
      'tasks': tasks.map((t) => t.toJson()).toList(),
      'subtasks': subtasks.map((s) => s.toJson()).toList(),
      'taskLists': taskLists.map((l) => l.toJson()).toList(),
      'tags': tags.map((t) => t.toJson()).toList(),
      'taskTags': taskTags.map((t) => t.toJson()).toList(),
      'habits': habits.map((h) => h.toJson()).toList(),
      'checkins': checkins.map((c) => c.toJson()).toList(),
      'relapses': relapses.map((r) => r.toJson()).toList(),
      'vacations': vacations.map((v) => v.toJson()).toList(),
      'routines': routines.map((r) => r.toJson()).toList(),
      'vacationScopes': vacationScopes.map((s) => s.toJson()).toList(),
      'chatNotes': chatNotes.map((n) => n.toJson()).toList(),
      'freezes': freezes.map((f) => f.toJson()).toList(),
      'tombstones': tombstones.map((t) => t.toJson()).toList(),
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

  /// The full database as an envelope (also used by the sync coordinator).
  Future<ExportEnvelope> collect() => _collect();

  Future<ExportEnvelope> _collect() async {
    return ExportEnvelope(
      schemaVersion: kExportSchemaVersion,
      exportedAt: DateTime.now().toUtc(),
      deviceId: _db.deviceId,
      tasks: await _db.select(_db.tasks).get(),
      subtasks: await _db.select(_db.subtasks).get(),
      taskLists: await _db.select(_db.taskLists).get(),
      tags: await _db.select(_db.tags).get(),
      taskTags: await _db.select(_db.taskTags).get(),
      habits: await _db.select(_db.habits).get(),
      checkins: await _db.select(_db.habitCheckins).get(),
      relapses: await _db.select(_db.habitRelapses).get(),
      vacations: await _db.select(_db.vacationPeriods).get(),
      routines: await _db.select(_db.routines).get(),
      vacationScopes: await _db.select(_db.vacationScopes).get(),
      chatNotes: await _db.select(_db.chatNotes).get(),
      freezes: await _db.select(_db.habitFreezes).get(),
      tombstones: await _db.select(_db.tombstones).get(),
    );
  }

  /// Parses [json] and replaces all data in a single transaction. On any
  /// failure the transaction rolls back, leaving the database untouched.
  ///
  /// Returns the imported envelope (for confirmation UI / reminder reschedule).
  Future<ExportEnvelope> importFromString(String json) async {
    final envelope = parseEnvelope(json);
    await replaceAll(envelope);
    return envelope;
  }

  /// Parses and validates [json] without touching the database. Used by the
  /// import flow to show a confirm-replace summary before committing.
  /// Throws [ImportFormatException] on malformed payloads.
  ExportEnvelope parseEnvelope(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (e) {
      throw ImportFormatException('Invalid JSON: $e');
    }
    if (decoded is! Map<String, Object?>) {
      throw ImportFormatException('Top-level JSON must be an object.');
    }
    return ExportEnvelope.fromJson(decoded);
  }

  /// Replaces all local data with [e] in a single transaction, adopting its
  /// tombstones (replace-all means "become this state", not "merge").
  Future<void> replaceAll(ExportEnvelope e) => _replaceAll(e);

  /// Applies a merged envelope (from [mergeEnvelopes]) to the local database:
  /// upserts every surviving row by uuid (preserving existing local integer
  /// ids), deletes rows whose uuid is gone, and adopts the tombstone set.
  /// Runs in one transaction; child parent-ids are remapped to local ids.
  Future<void> applyMerged(Map<String, Object?> mergedJson) async {
    final merged = ExportEnvelope.fromJson(mergedJson);
    await _db.transaction(() async {
      // Lists are parents of tasks but soft ones: apply them first, then
      // remap each task's listUuid to this device's local id (or clear it).
      final listIds = await _upsertByUuid<$TaskListsTable, TaskList>(
        table: _db.taskLists,
        rows: merged.taskLists,
        uuidOf: (r) => r.uuid,
        idOf: (r) => r.id,
        whereUuid: (t, u) => t.uuid.equals(u),
        resolve: (r) => r.toCompanion(true),
        contentJson: (r) => _contentJson(r.toJson()),
      );
      // Routines are soft parents of habits: apply first and remap the stable
      // routineUuid to this device's private routineId (or clear it).
      final routineIds = await _upsertByUuid<$RoutinesTable, Routine>(
        table: _db.routines,
        rows: merged.routines,
        uuidOf: (r) => r.uuid,
        idOf: (r) => r.id,
        whereUuid: (t, u) => t.uuid.equals(u),
        resolve: (r) => r.toCompanion(true),
        contentJson: (r) => _contentJson(r.toJson()),
      );
      final taskIds = await _upsertByUuid<$TasksTable, Task>(
        table: _db.tasks,
        rows: merged.tasks,
        uuidOf: (r) => r.uuid,
        idOf: (r) => r.id,
        whereUuid: (t, u) => t.uuid.equals(u),
        resolve: (r) {
          final localListId = r.listUuid == null ? null : listIds[r.listUuid];
          return r
              .copyWith(
                listId: Value(localListId),
                listUuid: localListId == null
                    ? const Value(null)
                    : Value(r.listUuid),
              )
              .toCompanion(true);
        },
        // The local list id is device-private; listUuid is the stable identity.
        contentJson: (r) => _contentJson(
          Map<String, Object?>.from(r.toJson())..remove('listId'),
        ),
      );
      final habitIds = await _upsertByUuid<$HabitsTable, Habit>(
        table: _db.habits,
        rows: merged.habits,
        uuidOf: (r) => r.uuid,
        idOf: (r) => r.id,
        whereUuid: (t, u) => t.uuid.equals(u),
        resolve: (r) {
          final localRoutineId = r.routineUuid == null
              ? null
              : routineIds[r.routineUuid];
          return r
              .copyWith(
                routineId: Value(localRoutineId),
                routineUuid: localRoutineId == null
                    ? const Value(null)
                    : Value(r.routineUuid),
              )
              .toCompanion(true);
        },
        contentJson: (r) => _contentJson(
          Map<String, Object?>.from(r.toJson())..remove('routineId'),
        ),
      );
      final tagIds = await _upsertByUuid<$TagsTable, Tag>(
        table: _db.tags,
        rows: merged.tags,
        uuidOf: (r) => r.uuid,
        idOf: (r) => r.id,
        whereUuid: (t, u) => t.uuid.equals(u),
        resolve: (r) => r.toCompanion(true),
        contentJson: (r) => _contentJson(r.toJson()),
      );

      // Vacation periods are parents of scopes. Scopes use only stable uuids,
      // so no local-id remap is needed for either table.
      await _upsertByUuid<$VacationPeriodsTable, VacationPeriod>(
        table: _db.vacationPeriods,
        rows: merged.vacations,
        uuidOf: (r) => r.uuid,
        whereUuid: (t, u) => t.uuid.equals(u),
        resolve: (r) => r.toCompanion(true),
        contentJson: (r) => _contentJson(r.toJson()),
      );
      await _upsertByUuid<$VacationScopesTable, VacationScope>(
        table: _db.vacationScopes,
        rows: merged.vacationScopes,
        uuidOf: (r) => r.uuid,
        whereUuid: (t, u) => t.uuid.equals(u),
        resolve: (r) => r.toCompanion(true),
        contentJson: (r) => _contentJson(r.toJson()),
      );
      // Chat notes are standalone (no parent uuid to remap).
      await _upsertByUuid<$ChatNotesTable, ChatNote>(
        table: _db.chatNotes,
        rows: merged.chatNotes,
        uuidOf: (r) => r.uuid,
        whereUuid: (t, u) => t.uuid.equals(u),
        resolve: (r) => r.toCompanion(true),
        contentJson: (r) => _contentJson(r.toJson()),
      );
      await _upsertByUuid<$HabitRelapsesTable, HabitRelapse>(
        table: _db.habitRelapses,
        rows: merged.relapses,
        uuidOf: (r) => r.uuid,
        whereUuid: (t, u) => t.uuid.equals(u),
        resolve: (r) {
          final id = habitIds[r.habitUuid];
          return id == null ? null : r.copyWith(habitId: id).toCompanion(true);
        },
        contentJson: (r) => _contentJson(r.toJson()),
      );

      await _upsertByUuid<$SubtasksTable, Subtask>(
        table: _db.subtasks,
        rows: merged.subtasks,
        uuidOf: (r) => r.uuid,
        whereUuid: (t, u) => t.uuid.equals(u),
        resolve: (r) {
          final id = taskIds[r.taskUuid];
          return id == null ? null : r.copyWith(taskId: id).toCompanion(true);
        },
        contentJson: (r) => _contentJson(r.toJson()),
      );
      await _upsertByUuid<$HabitCheckinsTable, HabitCheckin>(
        table: _db.habitCheckins,
        rows: merged.checkins,
        uuidOf: (r) => r.uuid,
        whereUuid: (t, u) => t.uuid.equals(u),
        resolve: (r) {
          final id = habitIds[r.habitUuid];
          return id == null ? null : r.copyWith(habitId: id).toCompanion(true);
        },
        contentJson: (r) => _contentJson(r.toJson()),
      );
      await _upsertByUuid<$HabitFreezesTable, HabitFreeze>(
        table: _db.habitFreezes,
        rows: merged.freezes,
        uuidOf: (r) => r.uuid,
        whereUuid: (t, u) => t.uuid.equals(u),
        resolve: (r) {
          final id = habitIds[r.habitUuid];
          return id == null ? null : r.copyWith(habitId: id).toCompanion(true);
        },
        contentJson: (r) => _contentJson(r.toJson()),
      );
      await _upsertByUuid<$TaskTagsTable, TaskTag>(
        table: _db.taskTags,
        rows: merged.taskTags,
        uuidOf: (r) => r.uuid,
        whereUuid: (t, u) => t.uuid.equals(u),
        resolve: (r) {
          final taskId = taskIds[r.taskUuid];
          final tagId = tagIds[r.tagUuid];
          if (taskId == null || tagId == null) return null;
          return r.copyWith(taskId: taskId, tagId: tagId).toCompanion(true);
        },
        contentJson: (r) => _contentJson(r.toJson()),
      );

      // Adopt the merged tombstone set (union, never pruned). Only rewrite
      // when it actually changed — an unconditional delete+reinsert would
      // fire table notifications every apply and re-trigger the data streams.
      final currentTombs = await _db.select(_db.tombstones).get();
      final currentKeys = {
        for (final t in currentTombs)
          '${t.uuid}|${t.sourceTable}|${t.deletedAt.toUtc().millisecondsSinceEpoch}|${t.deviceId}',
      };
      final wantedKeys = {
        for (final t in merged.tombstones)
          '${t.uuid}|${t.sourceTable}|${t.deletedAt.toUtc().millisecondsSinceEpoch}|${t.deviceId}',
      };
      if (currentKeys.length != wantedKeys.length ||
          !currentKeys.containsAll(wantedKeys)) {
        await _db.delete(_db.tombstones).go();
        await _db.batch((b) {
          b.insertAll(_db.tombstones, merged.tombstones);
        });
      }
    });
  }

  /// Upserts rows by uuid: deletes local rows the merge dropped, inserts new
  /// uuids with fresh local ids, and writes changed content onto existing
  /// rows without moving their local identity. Returns uuid → local id when
  /// [idOf] is given (parent tables, for child remaps).
  Future<Map<String, int>> _upsertByUuid<T extends Table, R extends DataClass>({
    required TableInfo<T, R> table,
    required List<R> rows,
    required String Function(R row) uuidOf,
    required Expression<bool> Function(T table, String uuid) whereUuid,
    required Insertable<R>? Function(R row) resolve,
    required String Function(R row) contentJson,
    int Function(R row)? idOf,
  }) async {
    final existing = await _db.select(table).get();
    final existingByUuid = {for (final r in existing) uuidOf(r): r};
    final wanted = rows.map(uuidOf).toSet();

    for (final r in existing) {
      if (!wanted.contains(uuidOf(r))) {
        await (_db.delete(table)..where((t) => whereUuid(t, uuidOf(r)))).go();
      }
    }

    final ids = <String, int>{};
    for (final row in rows) {
      final uuid = uuidOf(row);
      final companion = resolve(row);
      if (companion == null) continue; // Orphan guard (merge already dropped).
      final current = existingByUuid[uuid];
      if (current == null) {
        final id = await _db.into(table).insert(_withoutId(companion));
        if (idOf != null) ids[uuid] = id;
      } else {
        if (idOf != null) ids[uuid] = idOf(current);
        if (contentJson(current) != contentJson(row)) {
          await (_db.update(
            table,
          )..where((t) => whereUuid(t, uuid))).write(_withoutId(companion));
        }
      }
    }
    return ids;
  }

  /// Strips the `id` column so inserts allocate a fresh local id and updates
  /// never move a row's local identity.
  Insertable<R> _withoutId<R extends DataClass>(Insertable<R> companion) {
    final columns = Map<String, Expression<Object>>.from(
      companion.toColumns(true),
    );
    columns.remove('id');
    return RawValuesInsertable<R>(columns);
  }

  /// Row content without the device-private local id.
  String _contentJson(Map<String, Object?> json) {
    final copy = Map<String, Object?>.from(json)..remove('id');
    return jsonEncode(copy);
  }

  Future<void> _replaceAll(ExportEnvelope e) async {
    await _db.transaction(() async {
      // Delete children before parents (FK-safe even with cascades enabled).
      await _db.delete(_db.tombstones).go();
      await _db.delete(_db.habitFreezes).go();
      await _db.delete(_db.habitCheckins).go();
      await _db.delete(_db.habitRelapses).go();
      await _db.delete(_db.vacationScopes).go();
      await _db.delete(_db.vacationPeriods).go();
      await _db.delete(_db.chatNotes).go();
      await _db.delete(_db.taskTags).go();
      await _db.delete(_db.subtasks).go();
      await _db.delete(_db.tasks).go();
      await _db.delete(_db.taskLists).go();
      await _db.delete(_db.habits).go();
      await _db.delete(_db.routines).go();
      await _db.delete(_db.tags).go();

      // Insert parents before children. Explicit ids are preserved so links
      // remain valid.
      await _db.batch((b) {
        b.insertAll(_db.tags, e.tags);
        b.insertAll(_db.routines, e.routines);
        b.insertAll(_db.habits, e.habits);
        b.insertAll(_db.taskLists, e.taskLists);
        b.insertAll(_db.tasks, e.tasks);
        b.insertAll(_db.subtasks, e.subtasks);
        b.insertAll(_db.taskTags, e.taskTags);
        b.insertAll(_db.habitCheckins, e.checkins);
        b.insertAll(_db.habitRelapses, e.relapses);
        b.insertAll(_db.vacationPeriods, e.vacations);
        b.insertAll(_db.vacationScopes, e.vacationScopes);
        b.insertAll(_db.chatNotes, e.chatNotes);
        b.insertAll(_db.habitFreezes, e.freezes);
        b.insertAll(_db.tombstones, e.tombstones);
      });
    });
  }
}
