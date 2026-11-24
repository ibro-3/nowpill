/// Device clocks are trusted; skew is a documented caveat, not corrected.
library;

import 'dart:convert';

/// Pure last-write-wins merge for cross-device sync (v0.3.0).
///
/// Operates on normalized v3 envelope JSON (see `ExportEnvelope`): every row
/// carries a `uuid` + `updatedAt`, child rows carry parent uuid references,
/// and deletions are recorded as tombstones. No Flutter or database imports —
/// the whole merge is deterministic and unit-testable, like the streak replay.
///
/// Rules (all deterministic, independent of input order):
///  * Per uuid, the copy with the greatest `updatedAt` wins; ties break by a
///    symmetric content hash (device-private `id` excluded) so every device
///    picks the same winner and the merged state is a fixed point.
///  * A tombstone kills its uuid when `deletedAt >= updatedAt` (at equal
///    timestamps the delete wins). A strictly newer row copy survives —
///    an edit after a delete resurrects the row on every device.
///  * Tags are deduped by name (newest wins); links referencing a losing tag
///    uuid are remapped to the winner.
///  * Child rows whose parent uuid did not survive are dropped (orphans).
///  * Natural-key duplicates (check-in / freeze per habit+day, link per
///    task+tag) collapse to the newest copy.
///
/// Device clocks are trusted; skew is a documented caveat, not corrected.

/// Row tables in the envelope's `data` object, parents before children.
/// `taskLists` is a soft parent: a task may reference it by uuid, but a
/// missing list never removes the task (the link is simply cleared).
const List<String> kSyncParentTables = [
  'taskLists',
  'tasks',
  'habits',
  'tags',
  'vacations',
];
const List<String> kSyncChildTables = [
  'subtasks',
  'taskTags',
  'checkins',
  'freezes',
  'relapses',
];

/// Parent-uuid field → parent table, per child table.
const Map<String, Map<String, String>> kSyncParentRefs = {
  'subtasks': {'taskUuid': 'tasks'},
  'taskTags': {'taskUuid': 'tasks', 'tagUuid': 'tags'},
  'checkins': {'habitUuid': 'habits'},
  'freezes': {'habitUuid': 'habits'},
  'relapses': {'habitUuid': 'habits'},
};

/// Full current-schema (v6) key set per row table. Older envelopes (e.g. a
/// pre-v6 device's file) omit nullable columns added later; rows are
/// normalized to these keys (missing → null) before merging so a missing key
/// and an explicit null compare equal. Without this, a v4 device would see
/// its own row as "changed" against an older copy every cycle and rewrite it
/// forever (a sync feedback loop).
const Map<String, List<String>> kSyncRowKeys = {
  'tasks': [
    'id',
    'uuid',
    'updatedAt',
    'title',
    'notes',
    'dueAt',
    'priority',
    'completedAt',
    'recurrenceRule',
    'reminderAt',
    'createdAt',
    'sortOrder',
    'listId',
    'listUuid',
  ],
  'taskLists': ['id', 'uuid', 'updatedAt', 'name', 'color', 'sortOrder'],
  'habits': [
    'id',
    'uuid',
    'updatedAt',
    'name',
    'notes',
    'iconKey',
    'color',
    'scheduleType',
    'weekdays',
    'targetPerWeek',
    'reminderTime',
    'freezeMode',
    'kind',
    'targetAmount',
    'createdAt',
    'archivedAt',
    'sortOrder',
  ],
  'tags': ['id', 'uuid', 'updatedAt', 'name', 'color'],
  'subtasks': [
    'id',
    'uuid',
    'updatedAt',
    'taskId',
    'taskUuid',
    'title',
    'done',
    'position',
  ],
  'taskTags': ['uuid', 'updatedAt', 'taskId', 'tagId', 'taskUuid', 'tagUuid'],
  'checkins': [
    'id',
    'uuid',
    'updatedAt',
    'habitId',
    'habitUuid',
    'date',
    'note',
    'amount',
  ],
  'freezes': [
    'id',
    'uuid',
    'updatedAt',
    'habitId',
    'habitUuid',
    'date',
    'createdAt',
  ],
  'relapses': [
    'id',
    'uuid',
    'updatedAt',
    'habitId',
    'habitUuid',
    'date',
    'note',
  ],
  'vacations': ['id', 'uuid', 'updatedAt', 'startDate', 'endDate'],
  'tombstones': ['uuid', 'sourceTable', 'deletedAt', 'deviceId'],
};

/// Returns [row] with every current-schema key present (missing → null).
/// Unknown keys are preserved. Pure; never mutates the input.
Map<String, Object?> normalizeSyncRow(String table, Map<String, Object?> row) {
  final keys = kSyncRowKeys[table];
  if (keys == null) return row;
  final result = Map<String, Object?>.from(row);
  for (final key in keys) {
    result.putIfAbsent(key, () => null);
  }
  return result;
}

/// What the merge did, for the sync status UI and tests.
class SyncMergeStats {
  const SyncMergeStats({
    this.conflictsResolved = 0,
    this.deletedByTombstone = 0,
    this.orphansDropped = 0,
    this.duplicatesMerged = 0,
  });

  /// Uuids that had more than one distinct surviving copy (LWW applied).
  final int conflictsResolved;

  /// Row copies dropped because a tombstone won.
  final int deletedByTombstone;

  /// Child rows dropped because their parent did not survive.
  final int orphansDropped;

  /// Natural-key / tag-name duplicates collapsed.
  final int duplicatesMerged;

  bool get changedAnything =>
      conflictsResolved > 0 ||
      deletedByTombstone > 0 ||
      orphansDropped > 0 ||
      duplicatesMerged > 0;
}

/// The merged envelope (v3 JSON) plus a summary of what happened.
class SyncMergeResult {
  const SyncMergeResult({required this.envelope, required this.stats});

  final Map<String, Object?> envelope;
  final SyncMergeStats stats;
}

/// A candidate row copy together with the device that produced it.
class _Candidate {
  _Candidate(this.row, this.deviceId);

  final Map<String, Object?> row;
  final String deviceId;

  String get uuid => row['uuid'] as String;
  int get updatedAt => (row['updatedAt'] as int?) ?? 0;
}

/// Merges normalized v3 envelopes (typically: this device's state plus every
/// other device's file in the sync folder) into one converged envelope.
///
/// [deviceId] labels the output envelope (the device applying the merge);
/// [now] stamps its `exportedAt`. Inputs are never mutated.
SyncMergeResult mergeEnvelopes({
  required List<Map<String, Object?>> envelopes,
  required String deviceId,
  required DateTime now,
}) {
  var conflicts = 0;
  var deletedByTombstone = 0;
  var orphansDropped = 0;
  var duplicatesMerged = 0;

  // --- 1. Union tombstones: greatest deletedAt wins (tie: deviceId). ---
  final tombstones = <String, Map<String, Object?>>{};
  for (final env in envelopes) {
    for (final t in _rows(env, 'tombstones')) {
      final uuid = t['uuid'] as String?;
      if (uuid == null || uuid.isEmpty) continue;
      final current = tombstones[uuid];
      if (current == null ||
          _compareTombstones(t, current, _deviceId(env), _deviceIdOf(current)) >
              0) {
        tombstones[uuid] = t;
      }
    }
  }

  // --- 2. LWW per uuid across all row tables. ---
  final winners = <String, Map<String, _Candidate>>{};
  for (final table in [...kSyncParentTables, ...kSyncChildTables]) {
    final byUuid = <String, _Candidate>{};
    for (final env in envelopes) {
      final sourceDevice = _deviceId(env);
      for (final row in _rows(env, table)) {
        final uuid = row['uuid'] as String?;
        if (uuid == null || uuid.isEmpty) continue;
        final candidate = _Candidate(row, sourceDevice);
        final current = byUuid[uuid];
        if (current == null) {
          byUuid[uuid] = candidate;
        } else {
          if (_canonical(current.row) != _canonical(candidate.row)) {
            conflicts++;
          }
          if (_compareCandidates(candidate, current) > 0) {
            byUuid[uuid] = candidate;
          }
        }
      }
    }

    // --- 3. Tombstone filter: delete wins at equal timestamps. ---
    byUuid.removeWhere((uuid, candidate) {
      final tomb = tombstones[uuid];
      if (tomb == null) return false;
      final deletedAt = (tomb['deletedAt'] as int?) ?? 0;
      if (deletedAt >= candidate.updatedAt) {
        deletedByTombstone++;
        return true;
      }
      return false;
    });

    winners[table] = byUuid;
  }

  // --- 4. Tag-name dedupe (tags are unique-by-name locally). ---
  final tagRemap = <String, String>{};
  {
    final byName = <String, List<_Candidate>>{};
    for (final c in winners['tags']!.values) {
      final name = c.row['name'] as String? ?? '';
      (byName[name] ??= []).add(c);
    }
    for (final group in byName.values) {
      if (group.length < 2) continue;
      group.sort(_compareCandidates);
      final winner = group.last;
      for (final loser in group.take(group.length - 1)) {
        tagRemap[loser.uuid] = winner.uuid;
        winners['tags']!.remove(loser.uuid);
        duplicatesMerged++;
      }
    }
  }

  // Remap links that referenced a losing tag uuid.
  if (tagRemap.isNotEmpty) {
    final links = winners['taskTags']!;
    for (final entry in links.entries.toList()) {
      final tagUuid = entry.value.row['tagUuid'] as String?;
      final mapped = tagUuid == null ? null : tagRemap[tagUuid];
      if (mapped != null) {
        links[entry.key] = _Candidate({
          ...entry.value.row,
          'tagUuid': mapped,
        }, entry.value.deviceId);
      }
    }
  }

  // --- 4b. List-name dedupe (lists are unique-by-name locally). Tasks that
  // referenced a losing list are remapped to the winner. ---
  {
    final byName = <String, List<_Candidate>>{};
    for (final c in winners['taskLists']!.values) {
      final name = c.row['name'] as String? ?? '';
      (byName[name] ??= []).add(c);
    }
    for (final group in byName.values) {
      if (group.length < 2) continue;
      group.sort(_compareCandidates);
      final winner = group.last;
      for (final loser in group.take(group.length - 1)) {
        final tasks = winners['tasks']!;
        for (final entry in tasks.entries.toList()) {
          if (entry.value.row['listUuid'] == loser.uuid) {
            tasks[entry.key] = _Candidate({
              ...entry.value.row,
              'listUuid': winner.uuid,
            }, entry.value.deviceId);
          }
        }
        winners['taskLists']!.remove(loser.uuid);
        duplicatesMerged++;
      }
    }
  }

  // --- 5. Drop orphans (parent uuid did not survive). ---
  for (final table in kSyncChildTables) {
    final refs = kSyncParentRefs[table]!;
    winners[table]!.removeWhere((uuid, candidate) {
      for (final ref in refs.entries) {
        final parentUuid = candidate.row[ref.key] as String?;
        if (parentUuid == null ||
            !winners[ref.value]!.containsKey(parentUuid)) {
          orphansDropped++;
          return true;
        }
      }
      return false;
    });
  }

  // --- 5b. Lists are soft references: a task whose list was deleted (or is
  // still unknown locally) stays, with the link cleared to "inbox". ---
  {
    final tasks = winners['tasks']!;
    final listUuids = winners['taskLists']!.keys.toSet();
    for (final entry in tasks.entries.toList()) {
      final listUuid = entry.value.row['listUuid'] as String?;
      if (listUuid != null && !listUuids.contains(listUuid)) {
        tasks[entry.key] = _Candidate({
          ...entry.value.row,
          'listId': null,
          'listUuid': null,
        }, entry.value.deviceId);
      }
    }
  }

  // --- 6. Natural-key dedupe: newest copy per logical key. ---
  void dedupe(String table, List<String> keyFields) {
    final byKey = <String, List<_Candidate>>{};
    for (final c in winners[table]!.values) {
      final key = keyFields.map((f) => '${c.row[f]}').join('|');
      (byKey[key] ??= []).add(c);
    }
    for (final group in byKey.values) {
      if (group.length < 2) continue;
      group.sort(_compareCandidates);
      for (final loser in group.take(group.length - 1)) {
        winners[table]!.remove(loser.uuid);
        duplicatesMerged++;
      }
    }
  }

  dedupe('checkins', ['habitUuid', 'date']);
  dedupe('freezes', ['habitUuid', 'date']);
  dedupe('relapses', ['habitUuid', 'date']);
  dedupe('taskTags', ['taskUuid', 'tagUuid']);

  // --- 7. Assemble the merged envelope. ---
  final data = <String, Object?>{
    for (final table in [...kSyncParentTables, ...kSyncChildTables])
      table: winners[table]!.values.map((c) => c.row).toList(),
    'tombstones': tombstones.values.toList(),
  };

  return SyncMergeResult(
    envelope: {
      'schemaVersion': 6,
      'exportedAt': now.toUtc().millisecondsSinceEpoch,
      'deviceId': deviceId,
      'data': data,
    },
    stats: SyncMergeStats(
      conflictsResolved: conflicts,
      deletedByTombstone: deletedByTombstone,
      orphansDropped: orphansDropped,
      duplicatesMerged: duplicatesMerged,
    ),
  );
}

List<Map<String, Object?>> _rows(Map<String, Object?> envelope, String table) {
  final data = envelope['data'];
  if (data is! Map<String, Object?>) return const [];
  final rows = data[table];
  if (rows is! List) return const [];
  // Normalize to the full current-schema key set so older envelopes (missing
  // nullable columns) merge and compare identically to current ones.
  return rows
      .whereType<Map<String, Object?>>()
      .map((r) => normalizeSyncRow(table, r))
      .toList();
}

String _deviceId(Map<String, Object?> envelope) =>
    envelope['deviceId'] as String? ?? '';

String _deviceIdOf(Map<String, Object?> tombstone) =>
    tombstone['deviceId'] as String? ?? '';

/// Orders candidates worst → best: updatedAt, then a symmetric content hash.
///
/// The tiebreak deliberately does NOT use the source deviceId: at equal
/// timestamps two devices hold the same uuid with different content, and a
/// deviceId tiebreak would make each device prefer its own copy — they would
/// swap winners every cycle and never converge. A content-only tiebreak gives
/// every device the same winner, so the state is a fixed point. The local
/// `id` is device-private and excluded (it differs across devices for the
/// same logical row and must not sway the outcome).
int _compareCandidates(_Candidate a, _Candidate b) {
  final byTime = a.updatedAt.compareTo(b.updatedAt);
  if (byTime != 0) return byTime;
  return _contentKey(a.row).compareTo(_contentKey(b.row));
}

/// Canonical content key: sorted-key JSON with the device-private `id`
/// removed. Matches the sync coordinator's change-detection comparison so a
/// merged result that equals the local state is never re-applied.
String _contentKey(Map<String, Object?> row) {
  final copy = Map<String, Object?>.from(row)..remove('id');
  return _canonical(copy);
}

int _compareTombstones(
  Map<String, Object?> a,
  Map<String, Object?> b,
  String deviceA,
  String deviceB,
) {
  final byTime = ((a['deletedAt'] as int?) ?? 0).compareTo(
    (b['deletedAt'] as int?) ?? 0,
  );
  if (byTime != 0) return byTime;
  return deviceA.compareTo(deviceB);
}

/// Canonical JSON with sorted keys — a stable tiebreak independent of map
/// insertion order.
String _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => '$k').toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${_canonical(value[k])}').join(',')}}';
  }
  if (value is List) {
    return '[${value.map(_canonical).join(',')}]';
  }
  return jsonEncode(value);
}
