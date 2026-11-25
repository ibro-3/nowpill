import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_surfaces.dart';

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
  final int color;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final scheme = theme.colorScheme;
    final accent = Color(color);

    final content = Row(
      children: [
        M3EShapeContainer(
          kind: M3EShapeKind.cookie6Sided,
          width: 36,
          height: 36,
          color: accent.withValues(alpha: 0.18),
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
                child: content,
              )
            else
              content,
            const SizedBox(height: 6),
            M3EProgressIndicator.linear(
              value: percent / 100,
              color: accent,
              trackColor: scheme.surfaceContainerHighest,
              semanticsLabel: '$percent%',
            ),
          ],
        ),
      ),
    );
  }
}
