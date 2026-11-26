import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

/// Label for a day section in the stream.
///
/// From M3: contained lists prefer gaps to dividers; the label uses the
/// baseline `label medium` scale with `on surface variant` text. The specific
/// type step for a date label is my design decision — M3 does not assign one.
class ChatDateHeading extends StatelessWidget {
  const ChatDateHeading({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text(
        label,
        style: theme.typography.baseline.labelMedium.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
