import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import '../../../l10n/generated/app_localizations.dart';

/// Empty stream state: support copy on top, a single primary CTA below.
///
/// From M3: one primary task per page with the CTA placed low and reachable;
/// supporting text uses `on surface variant`. There is no M3 empty-state
/// component, so this composition is my design decision.
class ChatEmptyState extends StatelessWidget {
  const ChatEmptyState({required this.onWrite, super.key});

  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                M3EIcons.chat_bubble_outline,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.chatEmptyTitle,
                textAlign: TextAlign.center,
                style: theme.typography.emphasized.titleMedium.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.chatEmptyBody,
                textAlign: TextAlign.center,
                style: theme.typography.baseline.bodyMedium.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              M3EButton.filled(
                label: Text(l10n.chatWriteFirst),
                icon: const Icon(M3EIcons.edit_outlined),
                onPressed: onWrite,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
