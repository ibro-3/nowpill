import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import '../../../data/db/app_database.dart';
import '../../../domain/chat_links.dart';
import '../../../l10n/generated/app_localizations.dart';

/// A single note in the thought stream.
///
/// From M3: a filled card uses `surface container highest` with 12dp corners,
/// 16dp horizontal padding and `on surface` body text. Links use `primary` and
/// are underlined (links are `primary` in M3; TYPO §Accessibility).
/// There is no M3 chat-bubble component, so consecutive notes form one
/// start-aligned column rather than left/right alternating bubbles.
class NoteCard extends StatelessWidget {
  const NoteCard({
    required this.note,
    required this.onDelete,
    required this.onOpenLink,
    super.key,
  });

  final ChatNote note;
  final VoidCallback onDelete;
  final ValueChanged<String> onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final time = DateFormat.jm(locale).format(note.createdAt.toLocal());

    return M3ECard(
      variant: M3ECardVariant.filled,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LinkedBody(
                  key: ValueKey('body-${note.uuid}'),
                  body: note.body,
                  onOpenLink: onOpenLink,
                  l10n: l10n,
                ),
                const SizedBox(height: 6),
                Semantics(
                  label: time,
                  child: Text(
                    time,
                    style: theme.typography.baseline.labelSmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          M3EIconButton(
            variant: M3EIconButtonVariant.standard,
            icon: const Icon(M3EIcons.delete_outlined),
            tooltip: l10n.chatDelete,
            semanticLabel: l10n.chatDelete,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Renders a body as rich text, turning detected URLs into tappable spans.
class _LinkedBody extends StatefulWidget {
  const _LinkedBody({
    required this.body,
    required this.onOpenLink,
    required this.l10n,
    super.key,
  });

  final String body;
  final ValueChanged<String> onOpenLink;
  final AppLocalizations l10n;

  @override
  State<_LinkedBody> createState() => _LinkedBodyState();
}

class _LinkedBodyState extends State<_LinkedBody> {
  final _recognizers = <TapGestureRecognizer>[];

  void _releaseRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void didUpdateWidget(covariant _LinkedBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body) _releaseRecognizers();
  }

  @override
  void dispose() {
    _releaseRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilt spans own fresh recognizers; the previous ones are no longer in
    // the tree, so release them here as well as on body changes/dispose.
    _releaseRecognizers();

    final theme = M3ETheme.of(context);
    final bodyStyle = theme.typography.baseline.bodyMedium.copyWith(
      color: theme.colorScheme.onSurface,
    );
    // From M3: links are primary and underlined. Baseline body text is never
    // emphasized; emphasis is reserved for actions/selection.
    final linkStyle = bodyStyle.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
    );

    final children = <InlineSpan>[];
    for (final segment in parseChatBody(widget.body)) {
      if (!segment.isLink) {
        children.add(TextSpan(text: segment.text));
        continue;
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onOpenLink(segment.text);
      _recognizers.add(recognizer);
      children.add(
        TextSpan(
          text: segment.text,
          style: linkStyle,
          recognizer: recognizer,
          semanticsLabel: widget.l10n.chatLinkSemantic(segment.text),
        ),
      );
    }
    return Text.rich(
      TextSpan(style: bodyStyle, children: children),
      textAlign: TextAlign.start,
    );
  }
}
