import 'enums.dart';

/// A pure description of when a habit is due. Decoupled from the database row
/// so the domain engines stay testable without Drift.
///
/// * `daily` — due every day.
/// * `weekdays` — due on the ISO weekdays in [weekdays] (1 = Mon … 7 = Sun).
/// * `weeklyTarget` — due any day; the goal is [targetPerWeek] completions in
///   each Monday-start week. Individual days are never "missed"; streaks are
///   counted in completed weeks.
class HabitSchedule {
  const HabitSchedule({
    required this.type,
    this.weekdays = const [],
    this.targetPerWeek,
  });

  const HabitSchedule.daily() : this(type: HabitScheduleType.daily);

  const HabitSchedule.weekdays(List<int> weekdays)
    : this(type: HabitScheduleType.weekdays, weekdays: weekdays);

  const HabitSchedule.weeklyTarget(int targetPerWeek)
    : this(type: HabitScheduleType.weeklyTarget, targetPerWeek: targetPerWeek);

  final HabitScheduleType type;

  /// ISO weekdays (1 = Mon … 7 = Sun) for [HabitScheduleType.weekdays].
  final List<int> weekdays;

  /// Weekly completion goal for [HabitScheduleType.weeklyTarget].
  final int? targetPerWeek;

  /// Whether this schedule tracks individual days (daily / weekdays) as
  /// opposed to whole weeks (weeklyTarget).
  bool get isDayBased => type != HabitScheduleType.weeklyTarget;

  /// Whether the habit is due on the given calendar day.
  ///
  /// For [HabitScheduleType.weeklyTarget] every day is "due" (any day can count
  /// toward the weekly goal); day-level miss logic does not apply.
  bool isDueOn(DateTime day) {
    switch (type) {
      case HabitScheduleType.daily:
      case HabitScheduleType.weeklyTarget:
        return true;
      case HabitScheduleType.weekdays:
        return weekdays.contains(day.weekday);
    }
  }
}
