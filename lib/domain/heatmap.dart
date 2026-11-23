import 'date_utils.dart';
import 'habit_schedule.dart';

/// The visual state of a single heatmap day (shared by the month and year
/// heatmaps).
enum HeatmapDayState {
  /// Checked in (measurable habits: goal fully met).
  done,

  /// Measurable habit: some progress logged, but below the daily goal.
  partial,

  /// A freeze token bridged this missed day.
  frozen,

  /// A scheduled day that was missed (no token).
  missed,

  /// Not a scheduled day.
  unscheduled,

  /// Today, not yet checked (in progress).
  todayPending,

  /// Outside the habit's lifetime or in the future.
  inactive,
}

/// Pure day-state classification for heatmaps. Identical rules for the month
/// grid and the year grid so a day never changes meaning between views.
HeatmapDayState heatmapDayState({
  required DateTime day,
  required DateTime today,
  required DateTime startDate,
  required HabitSchedule schedule,
  required Set<String> checkins,
  required Set<String> frozenDates,
  double? targetAmount,
  Map<String, double> amounts = const {},
}) {
  final d = DateTime(day.year, day.month, day.day);
  final t = DateTime(today.year, today.month, today.day);
  final start = DateTime(startDate.year, startDate.month, startDate.day);
  final key = formatDate(d);
  if (d.isAfter(t)) return HeatmapDayState.inactive;
  if (d.isBefore(start)) return HeatmapDayState.inactive;
  if (checkins.contains(key)) {
    // Measurable habits: full goal = done, partial progress = partial shade.
    if (targetAmount != null) {
      final amount = amounts[key];
      if (amount != null && amount < targetAmount) {
        return HeatmapDayState.partial;
      }
    }
    return HeatmapDayState.done;
  }
  // Weekly-target freezes are stored under the week's Monday; render frozen
  // on every unchecked day of a frozen week.
  final frozenKey = schedule.isDayBased ? key : formatDate(startOfWeek(d));
  if (frozenDates.contains(frozenKey)) return HeatmapDayState.frozen;
  if (daysBetween(d, t) == 0) return HeatmapDayState.todayPending;
  // Weekly-target habits never miss individual days — only whole weeks
  // count, so unchecked days stay neutral.
  if (!schedule.isDayBased) return HeatmapDayState.unscheduled;
  if (schedule.isDueOn(d)) return HeatmapDayState.missed;
  return HeatmapDayState.unscheduled;
}

/// One week-column of the year heatmap: the Monday and its seven day states.
class YearHeatmapWeek {
  const YearHeatmapWeek({required this.monday, required this.states});

  final DateTime monday;

  /// Monday…Sunday states, in order.
  final List<HeatmapDayState> states;
}

/// Aggregates the trailing 52 weeks + current week (53 Monday-start columns,
/// GitHub-style) ending with the week containing [today]. Pure — the widget
/// only renders what this produces.
List<YearHeatmapWeek> yearHeatmapWeeks({
  required DateTime today,
  required DateTime startDate,
  required HabitSchedule schedule,
  required Set<String> checkins,
  required Set<String> frozenDates,
  double? targetAmount,
  Map<String, double> amounts = const {},
}) {
  final t = DateTime(today.year, today.month, today.day);
  final lastMonday = startOfWeek(t);
  final firstMonday = lastMonday.subtract(const Duration(days: 52 * 7));
  return List.generate(53, (i) {
    final monday = firstMonday.add(Duration(days: i * 7));
    return YearHeatmapWeek(
      monday: monday,
      states: List.generate(7, (d) {
        final day = monday.add(Duration(days: d));
        return heatmapDayState(
          day: day,
          today: t,
          startDate: startDate,
          schedule: schedule,
          checkins: checkins,
          frozenDates: frozenDates,
          targetAmount: targetAmount,
          amounts: amounts,
        );
      }),
    );
  });
}
