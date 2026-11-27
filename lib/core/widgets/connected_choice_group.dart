import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

/// Single-choice control for a short list of options.
///
/// M3 Expressive no longer recommends the segmented button — the **connected
/// button group** replaces it (see `components/buttons.md`). This wrapper keeps
/// call sites as small as the old `M3ESegmentedButton` while using the
/// M3E-correct component, with a 2dp gap and joined inner corners. Labels that
/// don't fit collapse into a trailing overflow menu instead of being truncated.
class ConnectedChoiceGroup<T> extends StatelessWidget {
  const ConnectedChoiceGroup({
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.icons,
    this.semanticLabel,
    this.overflow = M3EButtonGroupOverflow.menu,
    super.key,
  });

  /// Values in display order; their indices drive the group's selection.
  final List<T> values;

  /// One label per [values] entry.
  final List<String> labels;

  /// Currently selected value.
  final T selected;

  /// Called with the newly selected value.
  final ValueChanged<T> onChanged;

  /// Optional leading icon per [values] entry.
  final List<IconData>? icons;

  /// Optional accessibility label for the group container.
  final String? semanticLabel;

  /// How the group handles options that don't fit. Defaults to an overflow
  /// menu so labels stay readable on narrow screens: a connected group that
  /// spans its surface would otherwise split into equal segments and ellipsize
  /// longer labels (for example "Expressive" or the five update-check modes).
  final M3EButtonGroupOverflow overflow;

  @override
  Widget build(BuildContext context) {
    assert(
      icons == null || icons!.length == values.length,
      'icons must have one entry per value',
    );
    return M3EButtonGroup(
      type: M3EButtonGroupType.connected,
      style: M3EButtonStyle.tonal,
      selectionRequired: true,
      semanticLabel: semanticLabel,
      overflow: overflow,
      selectedIndex: values.indexOf(selected),
      onSelectedIndexChanged: (index) {
        if (index != null) onChanged(values[index]);
      },
      actions: [
        for (var i = 0; i < values.length; i++)
          M3EButtonGroupAction(
            label: Text(labels[i]),
            icon: icons == null ? null : Icon(icons![i]),
          ),
      ],
    );
  }
}
