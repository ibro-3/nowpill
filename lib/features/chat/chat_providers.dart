import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/providers.dart';
import 'chat_view_model.dart';

/// All chat notes, newest first. Hand-written because riverpod_generator
/// cannot resolve Drift's part-file row classes (see m3e_spike_decision.md).
final allChatNotesProvider = StreamProvider<List<ChatNote>>((ref) {
  return ref.watch(chatRepositoryProvider).watchAll();
});

/// Day-grouped stream derived from the reactive note list.
final chatViewModelProvider = Provider<ChatViewModel>((ref) {
  return computeChatViewModel(
    ref.watch(allChatNotesProvider).value ?? const [],
  );
});
