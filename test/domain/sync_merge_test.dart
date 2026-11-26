import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/sync_merge.dart';

/// Pure merge-engine matrix: LWW, tombstones, orphans, dedupe, convergence.
void main() {
  final now = DateTime.utc(2026, 11, 23, 12);

  Map<String, Object?> env(
    String device, {
    Map<String, List<Map<String, Object?>>> data = const {},
  }) {
    return {
      'schemaVersion': 3,
      'exportedAt': now.millisecondsSinceEpoch,
      'deviceId': device,
      'data': {
        'tasks': <Object>[],
        'taskLists': <Object>[],
        'habits': <Object>[],
        'tags': <Object>[],
        'subtasks': <Object>[],
        'taskTags': <Object>[],
        'checkins': <Object>[],
        'freezes': <Object>[],
        'relapses': <Object>[],
        'vacations': <Object>[],
        'routines': <Object>[],
        'vacationScopes': <Object>[],
        'tombstones': <Object>[],
        ...data,
      },
    };
  }

  Map<String, Object?> habit(String uuid, int updatedAt, {String name = 'H'}) =>
      {
        'id': 1,
        'uuid': uuid,
        'updatedAt': updatedAt,
        'name': name,
        'notes': null,
        'iconKey': 'spark',
        'color': 1,
        'scheduleType': 0,
        'weekdays': null,
        'targetPerWeek': null,
        'reminderTime': null,
        'freezeMode': 0,
        'createdAt': 0,
        'archivedAt': null,
        'sortOrder': 0,
      };

  Map<String, Object?> checkin(
    String uuid,
    String habitUuid,
    String date,
    int updatedAt,
  ) => {
    'id': 1,
    'uuid': uuid,
    'updatedAt': updatedAt,
    'habitId': 1,
    'habitUuid': habitUuid,
    'date': date,
    'note': null,
  };

  Map<String, Object?> tomb(String uuid, int deletedAt, String device) => {
    'uuid': uuid,
    'sourceTable': 'habit_checkins',
    'deletedAt': deletedAt,
    'deviceId': device,
  };

  List<Map<String, Object?>> rowsOf(SyncMergeResult r, String table) {
    final data = r.envelope['data'] as Map<String, Object?>;
    return (data[table] as List).cast<Map<String, Object?>>();
  }

  group('last-write-wins', () {
    test('newer copy wins regardless of input order', () {
      final old = env(
        'a',
        data: {
          'habits': [habit('u1', 100, name: 'Old')],
        },
      );
      final newer = env(
        'b',
        data: {
          'habits': [habit('u1', 200, name: 'New')],
        },
      );

      for (final order in [
        [old, newer],
        [newer, old],
      ]) {
        final r = mergeEnvelopes(envelopes: order, deviceId: 'a', now: now);
        expect(rowsOf(r, 'habits').single['name'], 'New');
        expect(r.stats.conflictsResolved, 1);
      }
    });

    test('equal timestamps break by content, symmetric across devices', () {
      final a = env(
        'aaa',
        data: {
          'habits': [habit('u1', 100, name: 'A')],
        },
      );
      final b = env(
        'bbb',
        data: {
          'habits': [habit('u1', 100, name: 'B')],
        },
      );
      final r1 = mergeEnvelopes(envelopes: [a, b], deviceId: 'x', now: now);
      final r2 = mergeEnvelopes(envelopes: [b, a], deviceId: 'x', now: now);
      expect(rowsOf(r1, 'habits').single['name'], 'B');
      expect(jsonEncode(r1.envelope['data']), jsonEncode(r2.envelope['data']));

      // Crucially, the winner is the same no matter WHICH device merges —
      // otherwise two devices would swap winners every cycle (never converge).
      final fromA = mergeEnvelopes(
        envelopes: [a, b],
        deviceId: 'aaa',
        now: now,
      );
      final fromB = mergeEnvelopes(
        envelopes: [a, b],
        deviceId: 'bbb',
        now: now,
      );
      expect(
        rowsOf(fromA, 'habits').single['name'],
        rowsOf(fromB, 'habits').single['name'],
      );
    });

    test('identical copies are not a conflict', () {
      final a = env(
        'a',
        data: {
          'habits': [habit('u1', 100)],
        },
      );
      final b = env(
        'b',
        data: {
          'habits': [habit('u1', 100)],
        },
      );
      final r = mergeEnvelopes(envelopes: [a, b], deviceId: 'a', now: now);
      expect(r.stats.conflictsResolved, 0);
      expect(rowsOf(r, 'habits'), hasLength(1));
    });

    test('disjoint rows union', () {
      final a = env(
        'a',
        data: {
          'habits': [habit('u1', 100)],
        },
      );
      final b = env(
        'b',
        data: {
          'habits': [habit('u2', 100)],
        },
      );
      final r = mergeEnvelopes(envelopes: [a, b], deviceId: 'a', now: now);
      expect(rowsOf(r, 'habits'), hasLength(2));
    });
  });

  group('tombstones', () {
    test('delete wins at equal timestamps', () {
      final a = env(
        'a',
        data: {
          'checkins': [checkin('c1', 'h1', '2026-11-20', 100)],
          'habits': [habit('h1', 50)],
        },
      );
      final b = env(
        'b',
        data: {
          'tombstones': [tomb('c1', 100, 'b')],
        },
      );
      final r = mergeEnvelopes(envelopes: [a, b], deviceId: 'a', now: now);
      expect(rowsOf(r, 'checkins'), isEmpty);
      expect(r.stats.deletedByTombstone, 1);
    });

    test('older tombstone does not kill a newer row (edit resurrects)', () {
      final a = env(
        'a',
        data: {
          'checkins': [checkin('c1', 'h1', '2026-11-20', 200)],
          'habits': [habit('h1', 50)],
        },
      );
      final b = env(
        'b',
        data: {
          'tombstones': [tomb('c1', 100, 'b')],
        },
      );
      final r = mergeEnvelopes(envelopes: [a, b], deviceId: 'a', now: now);
      expect(rowsOf(r, 'checkins'), hasLength(1));
    });

    test('tombstones union and greatest deletedAt wins', () {
      final a = env(
        'a',
        data: {
          'tombstones': [tomb('c1', 100, 'a')],
        },
      );
      final b = env(
        'b',
        data: {
          'tombstones': [tomb('c1', 300, 'b'), tomb('c2', 50, 'b')],
        },
      );
      final r = mergeEnvelopes(envelopes: [a, b], deviceId: 'a', now: now);
      final tombs = rowsOf(r, 'tombstones');
      expect(tombs, hasLength(2));
      final c1 = tombs.firstWhere((t) => t['uuid'] == 'c1');
      expect(c1['deletedAt'], 300);
    });

    test('deleted parent removes its children as orphans', () {
      final a = env(
        'a',
        data: {
          'habits': [habit('h1', 50)],
          'checkins': [checkin('c1', 'h1', '2026-11-20', 100)],
        },
      );
      final b = env(
        'b',
        data: {
          'tombstones': [tomb('h1', 500, 'b')],
        },
      );
      final r = mergeEnvelopes(envelopes: [a, b], deviceId: 'a', now: now);
      expect(rowsOf(r, 'habits'), isEmpty);
      expect(rowsOf(r, 'checkins'), isEmpty);
      expect(r.stats.orphansDropped, 1);
    });
  });

  group('orphans and dedupe', () {
    test('child with unknown parent is dropped', () {
      final a = env(
        'a',
        data: {
          'checkins': [checkin('c1', 'missing', '2026-11-20', 100)],
        },
      );
      final r = mergeEnvelopes(envelopes: [a], deviceId: 'a', now: now);
      expect(rowsOf(r, 'checkins'), isEmpty);
      expect(r.stats.orphansDropped, 1);
    });

    test('same habit+day from two devices collapses to newest', () {
      final a = env(
        'a',
        data: {
          'habits': [habit('h1', 50)],
          'checkins': [checkin('cA', 'h1', '2026-11-20', 100)],
        },
      );
      final b = env(
        'b',
        data: {
          'habits': [habit('h1', 50)],
          'checkins': [checkin('cB', 'h1', '2026-11-20', 200)],
        },
      );
      final r = mergeEnvelopes(envelopes: [a, b], deviceId: 'a', now: now);
      final checkins = rowsOf(r, 'checkins');
      expect(checkins, hasLength(1));
      expect(checkins.single['uuid'], 'cB');
      expect(r.stats.duplicatesMerged, 1);
    });

    test('tags dedupe by name and links remap to the winner', () {
      Map<String, Object?> tag(String uuid, int updatedAt) => {
        'id': 1,
        'uuid': uuid,
        'updatedAt': updatedAt,
        'name': 'home',
        'color': 1,
      };
      Map<String, Object?> task(String uuid) => {
        'id': 1,
        'uuid': uuid,
        'updatedAt': 10,
        'title': 'T',
        'notes': null,
        'dueAt': null,
        'priority': 0,
        'completedAt': null,
        'recurrenceRule': null,
        'reminderAt': null,
        'createdAt': 0,
        'sortOrder': 0,
      };
      Map<String, Object?> link(String uuid, String tagUuid, int at) => {
        'uuid': uuid,
        'updatedAt': at,
        'taskId': 1,
        'tagId': 1,
        'taskUuid': 't1',
        'tagUuid': tagUuid,
      };

      final a = env(
        'a',
        data: {
          'tasks': [task('t1')],
          'tags': [tag('tagA', 100)],
          'taskTags': [link('lA', 'tagA', 100)],
        },
      );
      final b = env(
        'b',
        data: {
          'tasks': [task('t1')],
          'tags': [tag('tagB', 200)],
          'taskTags': [link('lB', 'tagB', 200)],
        },
      );
      final r = mergeEnvelopes(envelopes: [a, b], deviceId: 'a', now: now);
      expect(rowsOf(r, 'tags'), hasLength(1));
      expect(rowsOf(r, 'tags').single['uuid'], 'tagB');
      final links = rowsOf(r, 'taskTags');
      expect(links, hasLength(1));
      expect(links.single['tagUuid'], 'tagB');
    });
  });

  group('convergence', () {
    test('three devices converge regardless of merge order', () {
      final a = env(
        'a',
        data: {
          'habits': [habit('h1', 100, name: 'A')],
          'checkins': [checkin('c1', 'h1', '2026-11-20', 100)],
        },
      );
      final b = env(
        'b',
        data: {
          'habits': [habit('h1', 300, name: 'B')],
          'tombstones': [tomb('c1', 200, 'b')],
        },
      );
      final c = env(
        'c',
        data: {
          'habits': [habit('h1', 200, name: 'C')],
          'checkins': [checkin('c2', 'h1', '2026-11-21', 150)],
        },
      );

      final results = [
        mergeEnvelopes(envelopes: [a, b, c], deviceId: 'x', now: now),
        mergeEnvelopes(envelopes: [c, a, b], deviceId: 'x', now: now),
        mergeEnvelopes(envelopes: [b, c, a], deviceId: 'x', now: now),
      ];
      final canonical = results
          .map((r) => jsonEncode(r.envelope['data']))
          .toSet();
      expect(canonical, hasLength(1));

      final r = results.first;
      expect(rowsOf(r, 'habits').single['name'], 'B');
      expect(rowsOf(r, 'checkins').map((c) => c['uuid']), ['c2']);
    });

    test('merging a result with its inputs is idempotent', () {
      final a = env(
        'a',
        data: {
          'habits': [habit('h1', 100, name: 'A')],
        },
      );
      final b = env(
        'b',
        data: {
          'habits': [habit('h1', 200, name: 'B')],
        },
      );
      final once = mergeEnvelopes(envelopes: [a, b], deviceId: 'a', now: now);
      final twice = mergeEnvelopes(
        envelopes: [once.envelope, a, b],
        deviceId: 'a',
        now: now,
      );
      expect(
        jsonEncode(once.envelope['data']),
        jsonEncode(twice.envelope['data']),
      );
    });

    test('pre-v4 rows (missing targetAmount/amount) merge equal to v4 rows', () {
      // A v4 device's row carries explicit nulls for the new nullable columns.
      final v4Habit = {...habit('h1', 100), 'targetAmount': null};
      final v4Checkin = {
        ...checkin('c1', 'h1', '2026-11-20', 100),
        'amount': null,
      };
      // An older device's file omits those keys entirely.
      final oldHabit = habit('h1', 100); // no targetAmount key
      final oldCheckin = checkin('c1', 'h1', '2026-11-20', 100); // no amount

      final a = env(
        'a',
        data: {
          'habits': [v4Habit],
          'checkins': [v4Checkin],
        },
      );
      final b = env(
        'b',
        data: {
          'habits': [oldHabit],
          'checkins': [oldCheckin],
        },
      );
      final merged = mergeEnvelopes(envelopes: [a, b], deviceId: 'a', now: now);
      // Same content → no conflict, and the merged rows carry the full key set
      // so a re-collect compares equal (no rewrite loop).
      expect(merged.stats.conflictsResolved, 0);
      expect(
        rowsOf(merged, 'habits').single.containsKey('targetAmount'),
        isTrue,
      );
      expect(rowsOf(merged, 'checkins').single.containsKey('amount'), isTrue);

      // Idempotent against the normalized output.
      final again = mergeEnvelopes(
        envelopes: [merged.envelope, a, b],
        deviceId: 'a',
        now: now,
      );
      expect(
        jsonEncode(merged.envelope['data']),
        jsonEncode(again.envelope['data']),
      );
    });

    test('normalizeSyncRow fills missing keys with null, keeps unknowns', () {
      final row = {'uuid': 'x', 'name': 'H', 'extra': 1};
      final norm = normalizeSyncRow('habits', row);
      expect(norm['targetAmount'], isNull);
      expect(norm.containsKey('targetAmount'), isTrue);
      expect(norm['extra'], 1);
      expect(norm['name'], 'H');
      // Input untouched.
      expect(row.containsKey('targetAmount'), isFalse);
      // Unknown table passes through.
      expect(normalizeSyncRow('unknown', row), same(row));
    });
  });

  group('quit habits and vacation (schema v6)', () {
    Map<String, Object?> relapse(
      String uuid,
      String habitUuid,
      String date,
      int updatedAt,
    ) => {
      'id': 1,
      'uuid': uuid,
      'updatedAt': updatedAt,
      'habitId': 1,
      'habitUuid': habitUuid,
      'date': date,
      'note': null,
    };

    Map<String, Object?> vacation(
      String uuid,
      int updatedAt, {
      String start = '2026-11-20',
      String end = '2026-11-23',
    }) => {
      'id': 1,
      'uuid': uuid,
      'updatedAt': updatedAt,
      'startDate': start,
      'endDate': end,
    };

    test('preserves HabitKind across a merge', () {
      final quitHabit = {...habit('h1', 100), 'kind': 1};
      final result = mergeEnvelopes(
        envelopes: [
          env(
            'a',
            data: {
              'habits': [quitHabit],
            },
          ),
        ],
        deviceId: 'a',
        now: now,
      );
      expect(rowsOf(result, 'habits').single['kind'], 1);
      expect(result.envelope['schemaVersion'], 8);
    });

    test('relapses dedupe by habit+date, newest wins', () {
      final result = mergeEnvelopes(
        envelopes: [
          env(
            'a',
            data: {
              'habits': [habit('h1', 100)],
              'relapses': [relapse('r1', 'h1', '2026-11-20', 100)],
            },
          ),
          env(
            'b',
            data: {
              'habits': [habit('h1', 100)],
              'relapses': [relapse('r2', 'h1', '2026-11-20', 200)],
            },
          ),
        ],
        deviceId: 'a',
        now: now,
      );
      final relapses = rowsOf(result, 'relapses');
      expect(relapses, hasLength(1));
      expect(relapses.single['uuid'], 'r2');
      expect(result.stats.duplicatesMerged, 1);
    });

    test('an orphan relapse is dropped, a vacation survives LWW', () {
      final result = mergeEnvelopes(
        envelopes: [
          env(
            'a',
            data: {
              'relapses': [relapse('r1', 'ghost', '2026-11-20', 100)],
              'vacations': [vacation('v1', 100)],
            },
          ),
          env(
            'b',
            data: {
              'vacations': [vacation('v1', 200, end: '2026-11-25')],
            },
          ),
        ],
        deviceId: 'a',
        now: now,
      );
      expect(rowsOf(result, 'relapses'), isEmpty);
      expect(result.stats.orphansDropped, 1);
      final periods = rowsOf(result, 'vacations');
      expect(periods, hasLength(1));
      expect(periods.single['endDate'], '2026-11-25');
    });

    test('a vacation tombstone removes the period on every device', () {
      final result = mergeEnvelopes(
        envelopes: [
          env(
            'a',
            data: {
              'vacations': [vacation('v1', 100)],
            },
          ),
          env(
            'b',
            data: {
              'tombstones': [
                tomb('v1', 200, 'b')..['sourceTable'] = 'vacation_periods',
              ],
            },
          ),
        ],
        deviceId: 'a',
        now: now,
      );
      expect(rowsOf(result, 'vacations'), isEmpty);
    });
  });
  group('routines and scoped vacation (schema v7)', () {
    Map<String, Object?> routine(String uuid, String name, int updatedAt) => {
      'id': 1,
      'uuid': uuid,
      'updatedAt': updatedAt,
      'name': name,
      'color': 1,
      'sortOrder': 0,
    };

    Map<String, Object?> scope(
      String uuid,
      String periodUuid,
      int kind,
      String targetUuid,
      int updatedAt,
    ) => {
      'id': 1,
      'uuid': uuid,
      'updatedAt': updatedAt,
      'periodUuid': periodUuid,
      'targetKind': kind,
      'targetUuid': targetUuid,
    };

    test('routine name dedupe remaps habits and scope targets', () {
      final result = mergeEnvelopes(
        envelopes: [
          env(
            'a',
            data: {
              'routines': [routine('r1', 'Morning', 100)],
              'habits': [
                {...habit('h1', 100)..['routineUuid'] = 'r1'},
              ],
            },
          ),
          env(
            'b',
            data: {
              'routines': [routine('r2', 'Morning', 200)],
              'habits': [
                {...habit('h2', 100)..['routineUuid'] = 'r2'},
              ],
              'vacations': [
                {
                  'id': 1,
                  'uuid': 'p1',
                  'updatedAt': 100,
                  'startDate': '2026-11-20',
                  'endDate': '2026-11-22',
                  'allHabits': false,
                },
              ],
              'vacationScopes': [scope('s1', 'p1', 0, 'r2', 100)],
            },
          ),
        ],
        deviceId: 'a',
        now: now,
      );
      expect(rowsOf(result, 'routines'), hasLength(1));
      expect(rowsOf(result, 'routines').single['uuid'], 'r2');
      final habits = rowsOf(result, 'habits');
      expect(habits, hasLength(2));
      expect(
        habits.every((h) => h['routineUuid'] == 'r2' && h['routineId'] == null),
        isTrue,
      );
      expect(rowsOf(result, 'vacationScopes').single['targetUuid'], 'r2');
      expect(result.stats.duplicatesMerged, 1);
      expect(result.envelope['schemaVersion'], 8);
    });

    test('scope natural-key dedupe keeps the newest copy', () {
      final result = mergeEnvelopes(
        envelopes: [
          env(
            'a',
            data: {
              'habits': [habit('h1', 100)],
              'vacations': [
                {
                  'id': 1,
                  'uuid': 'p1',
                  'updatedAt': 100,
                  'startDate': '2026-11-20',
                  'endDate': '2026-11-22',
                  'allHabits': false,
                },
              ],
              'vacationScopes': [scope('s1', 'p1', 1, 'h1', 100)],
            },
          ),
          env(
            'b',
            data: {
              'vacationScopes': [scope('s2', 'p1', 1, 'h1', 200)],
            },
          ),
        ],
        deviceId: 'a',
        now: now,
      );
      final scopes = rowsOf(result, 'vacationScopes');
      expect(scopes, hasLength(1));
      expect(scopes.single['uuid'], 's2');
    });

    test('scopes with missing period or target are dropped', () {
      final result = mergeEnvelopes(
        envelopes: [
          env(
            'a',
            data: {
              'habits': [habit('h1', 100)],
              'routines': [routine('r1', 'Morning', 100)],
              'vacations': [
                {
                  'id': 1,
                  'uuid': 'p1',
                  'updatedAt': 100,
                  'startDate': '2026-11-20',
                  'endDate': '2026-11-22',
                  'allHabits': false,
                },
              ],
              'vacationScopes': [
                scope('s1', 'ghost', 1, 'h1', 100),
                scope('s2', 'p1', 1, 'ghost', 100),
                scope('s3', 'p1', 0, 'r1', 100),
              ],
            },
          ),
        ],
        deviceId: 'a',
        now: now,
      );
      final scopes = rowsOf(result, 'vacationScopes');
      expect(scopes, hasLength(1));
      expect(scopes.single['uuid'], 's3');
      expect(result.stats.orphansDropped, 2);
    });

    test('a deleted routine clears the habit link but keeps the habit', () {
      final habitRow = habit('h1', 100)..['routineUuid'] = 'gone';
      final result = mergeEnvelopes(
        envelopes: [
          env(
            'a',
            data: {
              'habits': [habitRow],
            },
          ),
        ],
        deviceId: 'a',
        now: now,
      );
      final row = rowsOf(result, 'habits').single;
      expect(row['name'], 'H');
      expect(row['routineUuid'], isNull);
      expect(row['routineId'], isNull);
    });

    test('v7 merge reaches a fixed point', () {
      final a = env(
        'a',
        data: {
          'routines': [routine('r1', 'Morning', 100)],
          'habits': [habit('h1', 100)..['routineUuid'] = 'r1'],
          'vacationScopes': [scope('s1', 'p1', 0, 'r1', 100)],
        },
      );
      final b = env(
        'b',
        data: {
          'routines': [routine('r2', 'Evening', 150)],
          'vacationScopes': [scope('s2', 'p1', 0, 'r2', 150)],
        },
      );
      final merged = mergeEnvelopes(envelopes: [a, b], deviceId: 'a', now: now);
      final again = mergeEnvelopes(
        envelopes: [merged.envelope, a, b],
        deviceId: 'a',
        now: now,
      );
      expect(
        jsonEncode(merged.envelope['data']),
        jsonEncode(again.envelope['data']),
      );
    });
  });
}
