import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/features/chat/chat_view_model.dart';

/// Pure day grouping for the chat stream.
void main() {
  ChatNote note(int id, DateTime createdAt) => ChatNote(
    id: id,
    uuid: 'u$id',
    createdAt: createdAt,
    updatedAt: createdAt,
    body: 'note $id',
  );

  test('empty stream has no groups', () {
    expect(computeChatViewModel(const []).groups, isEmpty);
    expect(computeChatViewModel(const []).count, 0);
  });

  test('groups by local calendar day, newest note first', () {
    final vm = computeChatViewModel([
      note(1, DateTime(2026, 11, 24, 9)),
      note(2, DateTime(2026, 11, 25, 8)),
      note(3, DateTime(2026, 11, 25, 20)),
    ]);

    expect(vm.groups.map((g) => g.dateKey), ['2026-11-25', '2026-11-24']);
    expect(vm.groups.first.notes.map((n) => n.id), [
      3,
      2,
    ], reason: 'newest note in a day comes first');
    expect(vm.count, 3);
  });

  test('a note just after midnight moves to the next day', () {
    final vm = computeChatViewModel([
      note(1, DateTime(2026, 11, 24, 23, 59)),
      note(2, DateTime(2026, 11, 25, 0, 1)),
    ]);
    expect(vm.groups.map((g) => g.dateKey), ['2026-11-25', '2026-11-24']);
  });
}
