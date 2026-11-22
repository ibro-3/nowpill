import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'recurrence_rule.freezed.dart';
part 'recurrence_rule.g.dart';

/// A recurrence rule for a task: repeat every [interval] [unit]s.
///
/// Examples:
/// * every day: `RecurrenceRule(unit: day, interval: 1)`
/// * every 2 weeks: `RecurrenceRule(unit: week, interval: 2)`
/// * monthly: `RecurrenceRule(unit: month, interval: 1)`
///
/// The next occurrence is computed by the pure `recurrence.dart` engine
/// (Phase 3), anchored to the original due date so cadence is preserved.
@freezed
abstract class RecurrenceRule with _$RecurrenceRule {
  const factory RecurrenceRule({
    required RecurrenceUnit unit,
    @Default(1) int interval,
  }) = _RecurrenceRule;

  factory RecurrenceRule.fromJson(Map<String, Object?> json) =>
      _$RecurrenceRuleFromJson(json);
}
