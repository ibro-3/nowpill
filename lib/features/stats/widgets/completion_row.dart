import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_surfaces.dart';
import '../../../core/widgets/spring_progress.dart';

/// One ranked completion row: icon, label, detail, percentage, and bar.
class CompletionRow extends StatelessWidget {
  const CompletionRow({
    required this.label,
    required this.percent,
    required this.color,
    this.detail,
    this.icon,
    this.onTap,
    super.key,
  });

  final String label;
  final String? detail;
  final int percent;
  final Color color;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final scheme = theme.colorScheme;

    final content = Row(
      children: [
        M3EShapeContainer(
          kind: M3EShapeKind.cookie6Sided,
          width: 36,
          height: 36,
          color: color.withValues(alpha: 0.18),
          child: Icon(
            icon ?? M3EIcons.groups,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.baseline.titleSmall.copyWith(
                  color: scheme.onSurface,
                ),
              ),
              if (detail != null)
                Text(
                  detail!,
                  style: theme.typography.baseline.labelSmall.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$percent%',
          style: theme.typography.emphasized.titleSmall.copyWith(
            color: scheme.onSurface,
          ),
        ),
      ],
    );

    return Semantics(
      container: true,
      label: '$label $percent%',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (onTap != null)
              InkWell(
                onTap: onTap,
                // Optical roundness: the child of a 12dp card must not reuse
                // the parent's radius (inner = outer - padding).
                borderRadius: BorderRadius.circular(
                  AppShape.inner(AppShape.card, 4),
                ),
                // M3 lists need a 48dp-high target; the row's 36dp icon does
                // not reach it on its own.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: content,
                ),
              )
            else
              content,
            const SizedBox(height: 6),
            SpringWavyProgressBar(
              value: percent / 100,
              // M3: the active indicator uses the primary role so it clears
              // 3:1 on the track. Per-entity color stays in the icon wash.
              color: scheme.primary,
              semanticsLabel: '$percent%',
            ),
          ],
        ),
      ),
    );
  }
}
