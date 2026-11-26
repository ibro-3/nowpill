import '../../data/db/app_database.dart';
import '../../domain/date_utils.dart';

/// One calendar-day section of the personal chat stream.
class ChatDayGroup {
  const ChatDayGroup({required this.dateKey, required this.notes});

  /// Local day in `yyyy-MM-dd` form (the grouping key).
  final String dateKey;
  final List<ChatNote> notes;
}

/// The chat stream grouped into days, newest first.
class ChatViewModel {
  const ChatViewModel({required this.groups});

  static const ChatViewModel empty = ChatViewModel(groups: []);

  final List<ChatDayGroup> groups;

  int get count => groups.fold(0, (sum, g) => sum + g.notes.length);
}

/// Pure derivation of day sections from note rows.
///
/// Notes are stored as UTC millis but grouped by *local* calendar day, so a
/// note sent just after midnight appears under the new day. Within a day the
/// newest note comes first, matching a conversation read bottom-to-top.
ChatViewModel computeChatViewModel(List<ChatNote> notes) {
  if (notes.isEmpty) return ChatViewModel.empty;
  final sorted = [...notes]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final byDay = <String, List<ChatNote>>{};
  for (final note in sorted) {
    final key = formatDate(note.createdAt.toLocal());
    (byDay[key] ??= []).add(note);
  }
  return ChatViewModel(
    groups: [
      for (final entry in byDay.entries)
        ChatDayGroup(dateKey: entry.key, notes: entry.value),
    ],
  );
}
