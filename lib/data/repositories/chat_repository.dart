import '../db/app_database.dart';
import '../db/daos/chat_notes_dao.dart';

/// Maximum length of a note, after trimming.
const int kMaxChatNoteLength = 4000;

/// Thrown when a note body is empty or too long.
class InvalidChatNoteException implements Exception {
  const InvalidChatNoteException(this.message);
  final String message;
  @override
  String toString() => 'InvalidChatNoteException: $message';
}

/// Validates and normalizes note text before it reaches the database.
String normalizeChatNoteBody(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) {
    throw const InvalidChatNoteException('A note cannot be empty.');
  }
  if (trimmed.length > kMaxChatNoteLength) {
    throw const InvalidChatNoteException(
      'A note cannot exceed $kMaxChatNoteLength characters.',
    );
  }
  return trimmed;
}

/// Repository for the local-only personal chat stream.
class ChatRepository {
  ChatRepository(this._db);

  final AppDatabase _db;

  ChatNotesDao get _notes => _db.chatNotesDao;

  Stream<List<ChatNote>> watchAll() => _notes.watchAll();

  Future<List<ChatNote>> getAll() => _notes.getAll();

  Future<int> create(String body) {
    return _notes.insertNote(
      ChatNotesCompanion.insert(
        body: normalizeChatNoteBody(body),
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<bool> edit(int id, String body) async {
    final note = await _notes.getNote(id);
    if (note == null) return false;
    return _notes.updateNote(note.copyWith(body: normalizeChatNoteBody(body)));
  }

  Future<int> delete(int id) => _notes.deleteNote(id);
}
