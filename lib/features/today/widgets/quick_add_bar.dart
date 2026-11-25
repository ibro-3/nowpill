import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:motor/motor.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_scheme_provider.dart';
import '../../../core/theme/app_surfaces.dart';
import '../../../data/repositories/providers.dart';
import '../../../domain/enums.dart';
import '../../../domain/quick_add_parser.dart';
import '../../../l10n/generated/app_localizations.dart';

/// One-line task capture pinned to the bottom of the Today dashboard.
///
/// v0.4: natural-language parsing — dates ("tomorrow at 5pm"), recurrence
/// ("every monday"), #tags, and !priority are lifted out of the title, with
/// live preview chips shown before submit. Plain text keeps the pre-v0.4
/// behavior (task due today at 23:59).
class QuickAddBar extends ConsumerStatefulWidget {
  const QuickAddBar({super.key});

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<QuickAddBar>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  bool _busy = false;
  QuickAddParse? _preview;
  QuickAddParse? _lastPreview;
  late final SingleMotionController _chips;

  @override
  void initState() {
    super.initState();
    _chips = SingleMotionController.bounded(
      motion: MotionTokens.expressive.spatialFast,
      vsync: this,
      lowerBound: 0,
      upperBound: 1,
      initialValue: 0,
    );
    _controller.addListener(_reparse);
  }

  @override
  void dispose() {
    _controller.removeListener(_reparse);
    _controller.dispose();
    _chips.dispose();
    super.dispose();
  }

  void _reparse() {
    final text = _controller.text;
    final next = text.trim().isEmpty
        ? null
        : parseQuickAdd(text, now: DateTime.now());
    final hasMetadata = next?.hasMetadata ?? false;
    if (next != null) _lastPreview = next;
    // Retarget in flight — fast typing never stacks size animations. Under
    // reduced motion there is nothing to animate, so snap the reveal value.
    if (MotionScope.of(context).reduced) {
      _chips.value = hasMetadata ? 1 : 0;
    } else if (hasMetadata) {
      _chips.animateTo(1);
    } else {
      _chips.animateTo(0);
    }
    setState(() => _preview = next);
  }

  Future<void> _submit() async {
    final parsed = parseQuickAdd(_controller.text, now: DateTime.now());
    if (parsed.title.isEmpty || _busy) return;
    setState(() => _busy = true);
    final now = DateTime.now();
    final repo = ref.read(taskRepositoryProvider);
    final id = await repo.create(
      title: parsed.title,
      dueAt: parsed.dueAtOrDefault(DateTime(now.year, now.month, now.day)),
      priority: parsed.priority,
      recurrence: parsed.recurrence,
      reminderAt: parsed.reminderAt,
    );
    // Resolve #tags: reuse existing tags by name, create missing ones.
    if (parsed.tags.isNotEmpty) {
      final tags = ref.read(tagRepositoryProvider);
      final existing = await tags.getAll();
      final ids = <int>[];
      for (final name in parsed.tags) {
        final match = existing
            .where((t) => t.name.toLowerCase() == name.toLowerCase())
            .firstOrNull;
        ids.add(
          match?.id ??
              await tags.create(name: name, color: _tagColor(existing.length)),
        );
      }
      await repo.setTags(id, ids);
    }
    // Fire-and-forget: haptics must never block the UI path (and the platform
    // channel does not complete in widget tests).
    unawaited(HapticFeedback.lightImpact());
    _controller.clear();
    if (mounted) setState(() => _busy = false);
  }

  /// Deterministic palette rotation for auto-created tags.
  int _tagColor(int seed) => const [
    0xFF5B8DEF,
    0xFF2DD4A8,
    0xFFFF6B5E,
    0xFFB889F8,
    0xFFFFC24B,
    0xFF00B4D8,
  ][seed % 6];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = M3ETheme.of(context);
    final tokens = MotionScope.of(context);
    _chips.motion = tokens.spatialFast;
    final hasPreview = _preview?.hasMetadata ?? false;
    final chips = _lastPreview;
    final showChips = chips != null && (hasPreview || _chips.value > 0.01);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showChips)
            SizeTransition(
              sizeFactor: tokens.reduced
                  ? AlwaysStoppedAnimation<double>(hasPreview ? 1 : 0)
                  : _chips,
              alignment: AlignmentDirectional.topStart,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PreviewChips(parse: chips, theme: theme, l10n: l10n),
              ),
            ),
          M3ETextField(
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
        ],
      ),
    );
  }
}

/// Live chips describing what the parser recognized (due date, reminder,
/// recurrence, tags, priority) — shown before the user submits.
class _PreviewChips extends StatelessWidget {
  const _PreviewChips({
    required this.parse,
    required this.theme,
    required this.l10n,
  });

  final QuickAddParse parse;
  final M3EThemeData theme;
  final AppLocalizations l10n;

  String _dateLabel(DateTime day) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[day.month - 1]} ${day.day}';
  }

  String _timeLabel(int minutes) {
    final hh = (minutes ~/ 60).toString().padLeft(2, '0');
    final mm = (minutes % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _cadenceLabel() {
    final r = parse.recurrence!;
    if (r.interval == 1) {
      return switch (r.unit) {
        RecurrenceUnit.day => l10n.cadenceDaily,
        RecurrenceUnit.week => l10n.cadenceWeekly,
        RecurrenceUnit.month => l10n.cadenceMonthly,
      };
    }
    return switch (r.unit) {
      RecurrenceUnit.day => l10n.cadenceEveryNDays(r.interval),
      RecurrenceUnit.week => l10n.cadenceEveryNWeeks(r.interval),
      RecurrenceUnit.month => l10n.cadenceEveryNMonths(r.interval),
    };
  }

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    void add(IconData icon, String label, {Color? color}) {
      chips.add(
        Container(
          key: ValueKey('quick-add-chip-$label'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: (color ?? theme.colorScheme.primary).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppShape.small),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.typography.baseline.labelSmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final due = parse.dueDay;
    if (due != null) {
      add(M3EIcons.today, l10n.quickAddPreviewDue(_dateLabel(due)));
    }
    final minutes = parse.reminderMinutes;
    if (minutes != null) {
      add(
        M3EIcons.notifications_active,
        l10n.quickAddPreviewReminder(_timeLabel(minutes)),
      );
    }
    if (parse.recurrence != null) {
      add(M3EIcons.repeat, l10n.quickAddPreviewRepeats(_cadenceLabel()));
    }
    for (final tag in parse.tags) {
      add(M3EIcons.tag, '#$tag');
    }
    switch (parse.priority) {
      case TaskPriority.high:
        add(M3EIcons.flag, l10n.priorityHigh, color: theme.colorScheme.error);
      case TaskPriority.medium:
        add(M3EIcons.flag, l10n.priorityMedium);
      case TaskPriority.low:
        add(
          M3EIcons.flag,
          l10n.priorityLow,
          color: theme.colorScheme.onSurfaceVariant,
        );
      case TaskPriority.none:
        break;
    }

    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}
