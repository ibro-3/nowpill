import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import '../../../data/repositories/chat_repository.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Docked composer for sending a note to yourself.
///
/// From M3: a filled text field is 56dp tall with 8dp top/bottom padding and a
/// clear affordance once text is present; the filled icon button is the single
/// high-emphasis action, and Enter sends. Docking above navigation and the
/// 8dp gap to Send are my design decisions (M3 has no chat composer spec).
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    required this.controller,
    required this.focusNode,
    required this.hasText,
    required this.onSend,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasText;
  final VoidCallback onSend;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return Container(
      color: theme.colorScheme.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: M3ETextField(
              controller: controller,
              focusNode: focusNode,
              label: l10n.chatComposerLabel,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              onChanged: onChanged,
              showClearButton: true,
              clearButtonSemanticsLabel: l10n.chatClear,
              maxLength: kMaxChatNoteLength,
              showCounter: false,
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            // Align the 40dp visual with the first line of the growing field.
            padding: const EdgeInsets.only(bottom: 8),
            child: M3EIconButton(
              variant: M3EIconButtonVariant.filled,
              size: M3EIconButtonSize.sm,
              icon: rtl
                  ? Transform.rotate(
                      angle: math.pi,
                      child: const Icon(M3EIcons.send),
                    )
                  : const Icon(M3EIcons.send),
              tooltip: l10n.chatSend,
              semanticLabel: l10n.chatSend,
              onPressed: hasText ? onSend : null,
            ),
          ),
        ],
      ),
    );
  }
}
