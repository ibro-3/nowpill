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
///  * Per uuid, the copy with the greatest `updatedAt` wins; ties break by
///    source `deviceId`, then by canonical row JSON.
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
const List<String> kSyncParentTables = ['tasks', 'habits', 'tags'];
const List<String> kSyncChildTables = [
  'subtasks',
  'taskTags',
  'checkins',
  'freezes',
];

/// Parent-uuid field → parent table, per child table.
const Map<String, Map<String, String>> kSyncParentRefs = {
  'subtasks': {'taskUuid': 'tasks'},
  'taskTags': {'taskUuid': 'tasks', 'tagUuid': 'tags'},
  'checkins': {'habitUuid': 'habits'},
  'freezes': {'habitUuid': 'habits'},
};

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
  dedupe('taskTags', ['taskUuid', 'tagUuid']);

  // --- 7. Assemble the merged envelope. ---
  final data = <String, Object?>{
    for (final table in [...kSyncParentTables, ...kSyncChildTables])
      table: winners[table]!.values.map((c) => c.row).toList(),
    'tombstones': tombstones.values.toList(),
  };

  return SyncMergeResult(
    envelope: {
      'schemaVersion': 4,
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
  return rows.whereType<Map<String, Object?>>().toList();
}

String _deviceId(Map<String, Object?> envelope) =>
    envelope['deviceId'] as String? ?? '';

String _deviceIdOf(Map<String, Object?> tombstone) =>
    tombstone['deviceId'] as String? ?? '';

/// Orders candidates worst → best: updatedAt, then deviceId, then canonical
/// JSON. Deterministic regardless of input order.
int _compareCandidates(_Candidate a, _Candidate b) {
  final byTime = a.updatedAt.compareTo(b.updatedAt);
  if (byTime != 0) return byTime;
  final byDevice = a.deviceId.compareTo(b.deviceId);
  if (byDevice != 0) return byDevice;
  return _canonical(a.row).compareTo(_canonical(b.row));
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
