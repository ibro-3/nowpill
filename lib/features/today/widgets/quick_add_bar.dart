import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import '../../../data/repositories/providers.dart';
import '../../../l10n/generated/app_localizations.dart';

/// One-line task capture pinned to the bottom of the Today dashboard.
/// Submitting creates a task due today without leaving the screen.
class QuickAddBar extends ConsumerStatefulWidget {
  const QuickAddBar({super.key});

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _controller.text.trim();
    if (title.isEmpty || _busy) return;
    setState(() => _busy = true);
    final now = DateTime.now();
    await ref
        .read(taskRepositoryProvider)
        .create(
          title: title,
          dueAt: DateTime(now.year, now.month, now.day, 23, 59),
        );
    // Fire-and-forget: haptics must never block the UI path (and the platform
    // channel does not complete in widget tests).
    unawaited(HapticFeedback.lightImpact());
    _controller.clear();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: M3ETextField(
        controller: _controller,
        label: l10n.quickAddHint,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        trailing: M3EIconButton(
          variant: M3EIconButtonVariant.filled,
          icon: const Icon(M3EIcons.send),
          tooltip: l10n.addTask,
          onPressed: _busy ? null : _submit,
        ),
      ),
    );
  }
}
