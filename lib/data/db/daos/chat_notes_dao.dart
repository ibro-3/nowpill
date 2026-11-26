import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'chat_notes_dao.g.dart';

/// Data access for the personal chat thought stream.
@DriftAccessor(tables: [ChatNotes, Tombstones])
class ChatNotesDao extends DatabaseAccessor<AppDatabase>
    with _$ChatNotesDaoMixin {
  ChatNotesDao(super.db);

  /// Newest first, so the stream reads like a conversation.
  Stream<List<ChatNote>> watchAll() {
    return (select(chatNotes)..orderBy([
          (n) => OrderingTerm(expression: n.createdAt, mode: OrderingMode.desc),
        ]))
        .watch();
  }

  Future<List<ChatNote>> getAll() => select(chatNotes).get();

  Future<ChatNote?> getNote(int id) {
    return (select(chatNotes)..where((n) => n.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertNote(ChatNotesCompanion entry) =>
      into(chatNotes).insert(entry);

  /// Edits stamp `updatedAt` so LWW sync sees the new content.
  Future<bool> updateNote(ChatNote entry) =>
      update(chatNotes)
          .replace(entry.copyWith(updatedAt: DateTime.now().toUtc()));

  /// Deletes the note and records its uuid for sync in the same transaction.
  Future<int> deleteNote(int id) async {
    return attachedDatabase.transaction(() async {
      final note = await getNote(id);
      if (note == null) return 0;
      await into(tombstones).insert(
        TombstonesCompanion.insert(
          uuid: note.uuid,
          sourceTable: 'chatNotes',
          deletedAt: DateTime.now().toUtc(),
          deviceId: attachedDatabase.deviceId,
        ),
        mode: InsertMode.insertOrReplace,
      );
      return (delete(chatNotes)..where((n) => n.id.equals(id))).go();
    });
  }
}
