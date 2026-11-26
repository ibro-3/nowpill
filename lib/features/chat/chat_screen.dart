import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/motion/spring_entrance.dart';
import '../../core/platform/link_launcher.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/providers.dart';
import '../../domain/chat_links.dart';
import '../../domain/date_utils.dart';
import '../../l10n/generated/app_localizations.dart';
import '../shell/feature_placeholders.dart';
import 'chat_providers.dart';
import 'chat_view_model.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_date_heading.dart';
import 'widgets/chat_empty_state.dart';
import 'widgets/note_card.dart';

/// Personal chat: a private, offline stream of notes to yourself.
///
/// The composer is the only creation affordance — no FAB competes with it.
/// Notes are shown newest-first in one start-aligned column; M3 has no
/// chat-bubble component, so bubble tails and alternating sides are out.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    // The M3E clear affordance empties the controller directly, so track text
    // through the listener rather than relying only on onChanged callbacks.
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText && mounted) setState(() => _hasText = hasText);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    await ref.read(chatRepositoryProvider).create(text);
    _controller.clear();
    _focus.unfocus();
  }

  /// Opens detected links in the system browser. Unsupported schemes never
  /// reach here (the parser only emits http/https), and a failed launch is a
  /// low-priority snackbar rather than a blocking dialog.
  Future<void> _openLink(String value) async {
    if (!isOpenableLink(value)) return;
    final uri = Uri.parse(value);
    final opened = await ref.read(linkLauncherProvider).open(uri);
    if (!opened && mounted) {
      M3ESnackbar.show(
        context,
        message: AppLocalizations.of(context).chatLinkError,
      );
    }
  }

  Future<void> _confirmDelete(ChatNote note) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await M3EDialog.show<bool>(
      context,
      dialog: M3EDialog(
        title: l10n.chatDeleteTitle,
        content: Text(l10n.chatDeleteBody),
        actions: [
          M3EButton(
            style: M3EButtonStyle.text,
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(false),
            label: Text(l10n.cancel),
          ),
          M3EButton(
            style: M3EButtonStyle.text,
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
            label: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(chatRepositoryProvider).delete(note.id);
    }
  }

  String _dayLabel(ChatDayGroup group, AppLocalizations l10n) {
    final today = formatDate(DateTime.now());
    final yesterday = formatDate(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    if (group.dateKey == today) return l10n.chatToday;
    if (group.dateKey == yesterday) return l10n.chatYesterday;
    final date = parseDate(group.dateKey);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return DateFormat('EEEE, MMM d', locale).format(date);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vm = ref.watch(chatViewModelProvider);
    final wide = MediaQuery.sizeOf(context).width >= 840;

    return Scaffold(
      // The shell paints the shared ambient backdrop behind the branch.
      backgroundColor: Colors.transparent,
      appBar: M3EAppBar.top(
        backgroundColor: Colors.transparent,
        titleText: l10n.chatTitle,
        actions: const [SearchAction(), SettingsAction()],
      ),
      body: Column(
        children: [
          Expanded(
            child: vm.groups.isEmpty
                ? ChatEmptyState(onWrite: _focus.requestFocus)
                : Center(
                    child: ConstrainedBox(
                      // My design decision: no second pane for a single stream.
                      // M3's messaging list-detail example is for many threads.
                      constraints: BoxConstraints(
                        maxWidth: wide ? 640 : double.infinity,
                      ),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        children: [
                          for (final group in vm.groups) ...[
                            ChatDateHeading(label: _dayLabel(group, l10n)),
                            for (final note in group.notes)
                              SpringEntrance(
                                key: ValueKey('chat-note-${note.id}'),
                                // M3 publishes no stagger values: notes appear
                                // together rather than in a choreographed cascade.
                                staggerStep: Duration.zero,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: NoteCard(
                                    note: note,
                                    onDelete: () => _confirmDelete(note),
                                    onOpenLink: _openLink,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
          ChatComposer(
            controller: _controller,
            focusNode: _focus,
            hasText: _hasText,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}
