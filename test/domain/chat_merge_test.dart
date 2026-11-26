import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/sync_merge.dart';

/// Chat notes participate in the same deterministic LWW/tombstone merge as
/// every other parent table.
void main() {
  final now = DateTime.utc(2026, 11, 25, 12);

  Map<String, Object?> env(
    String device, {
    List<Map<String, Object?>> notes = const [],
    List<Map<String, Object?>> tombstones = const [],
  }) {
    return {
      'schemaVersion': 7,
      'exportedAt': now.millisecondsSinceEpoch,
      'deviceId': device,
      'data': {'chatNotes': notes, 'tombstones': tombstones},
    };
  }

  Map<String, Object?> note(String uuid, int updatedAt, String body) => {
    'id': 1,
    'uuid': uuid,
    'updatedAt': updatedAt,
    'createdAt': 100,
    'body': body,
  };

  List<Map<String, Object?>> mergedNotes(SyncMergeResult result) {
    final data = result.envelope['data'] as Map<String, Object?>;
    return (data['chatNotes'] as List).cast<Map<String, Object?>>();
  }

  test('newer note copy wins regardless of envelope order', () {
    final older = env('a', notes: [note('n1', 100, 'old')]);
    final newer = env('b', notes: [note('n1', 200, 'new')]);
    for (final envelopes in [
      [older, newer],
      [newer, older],
    ]) {
      final result = mergeEnvelopes(
        envelopes: envelopes,
        deviceId: 'c',
        now: now,
      );
      final rows = mergedNotes(result);
      expect(rows, hasLength(1));
      expect(rows.single['body'], 'new');
      expect(result.envelope['schemaVersion'], 8);
    }
  });

  test('tombstone removes a note when the delete is at least as new', () {
    final result = mergeEnvelopes(
      envelopes: [
        env('a', notes: [note('n1', 100, 'gone')]),
        env(
          'b',
          tombstones: [
            {
              'uuid': 'n1',
              'sourceTable': 'chatNotes',
              'deletedAt': 150,
              'deviceId': 'b',
            },
          ],
        ),
      ],
      deviceId: 'c',
      now: now,
    );
    expect(mergedNotes(result), isEmpty);
    expect(result.stats.deletedByTombstone, 1);
  });

  test('pre-v8 envelope without chatNotes merges as an empty table', () {
    final result = mergeEnvelopes(
      envelopes: [
        {'schemaVersion': 7, 'exportedAt': 0, 'deviceId': 'old', 'data': {}},
      ],
      deviceId: 'c',
      now: now,
    );
    expect(mergedNotes(result), isEmpty);
  });
}
