import 'date_utils.dart';
import 'habit_schedule.dart';

/// The derived streak state for a habit, replayed purely from its check-in
/// history and schedule. No mutable counters are stored — this is recomputed
/// from source data, so backfilling a past day automatically refunds any
/// freeze it would have consumed.
class StreakResult {
  const StreakResult({
    required this.currentStreak,
    required this.bestStreak,
    required this.tokens,
    required this.frozenDates,
    required this.earnEvents,
    required this.completedDays,
  });

  /// The active streak length as of `today`.
  ///
  /// Day-based habits: consecutive satisfied scheduled days ending today (or
  /// the most recent scheduled day). Weekly-target habits: consecutive
  /// completed weeks ending with the current week.
  final int currentStreak;

  /// The longest streak ever reached.
  final int bestStreak;

  /// Freeze tokens currently in the wallet (0…[maxTokens]).
  final int tokens;

  /// Days where a freeze was auto-consumed to bridge a missed scheduled day
  /// (`yyyy-MM-dd`). Rendered as ❄ on the heatmap.
  final Set<String> frozenDates;

  /// Days where a token was earned (`yyyy-MM-dd`).
  final Set<String> earnEvents;

  /// Total check-ins counted (for stats).
  final int completedDays;

  static const StreakResult empty = StreakResult(
    currentStreak: 0,
    bestStreak: 0,
    tokens: 0,
    frozenDates: {},
    earnEvents: {},
    completedDays: 0,
  );
}

/// Maximum freeze tokens a habit can hold.
const int maxTokens = 3;

/// Scheduled days needed to earn one freeze token (day-based habits).
const int daysPerToken = 7;

/// Completed weeks needed to earn one freeze token (weekly-target habits).
const int weeksPerToken = 4;

/// Replays a habit's check-in history to derive its streak state.
///
/// [schedule] determines which days are scheduled. [checkins] is the set of
/// `yyyy-MM-dd` days the habit was completed (order-independent). [today] is
/// the current calendar day; [startDate] is the first day the habit existed
/// (its creation day) — days before it are not counted as misses.
///
/// Rules (locked):
/// * Strict: a missed scheduled day resets the streak unless a freeze token is
///   auto-consumed to bridge it.
/// * Today counts immediately if checked; today is never "missed".
/// * Earn 1 token per [daysPerToken] streak days (day-based) or per
///   [weeksPerToken] completed weeks (weekly-target); wallet caps at [maxTokens].
/// * A freeze bridges exactly one missed scheduled day and keeps the streak
///   alive (the frozen day counts toward the streak length).
///
/// For weekly-target habits, streaks count completed weeks (a week is complete
/// when it has ≥ `targetPerWeek` check-ins). The current week counts as soon as
/// its target is met. Missed weeks consume a freeze if available.
StreakResult replayStreak({
  required HabitSchedule schedule,
  required Set<String> checkins,
  required DateTime today,
  required DateTime startDate,
}) {
  if (schedule.isDayBased) {
    return _replayDayBased(
      schedule: schedule,
      checkins: checkins,
      today: today,
      startDate: startDate,
    );
  }
  return _replayWeeklyTarget(
    schedule: schedule,
    checkins: checkins,
    today: today,
    startDate: startDate,
  );
}

StreakResult _replayDayBased({
  required HabitSchedule schedule,
  required Set<String> checkins,
  required DateTime today,
  required DateTime startDate,
}) {
  var current = 0;
  var best = 0;
  var tokens = 0;
  var completedDays = 0;
  final frozen = <String>{};
  final earns = <String>{};

  var day = DateTime(startDate.year, startDate.month, startDate.day);
  final end = DateTime(today.year, today.month, today.day);

  while (!day.isAfter(end)) {
    final key = formatDate(day);
    final isToday = daysBetween(day, end) == 0;
    final checked = checkins.contains(key);
    final due = schedule.isDueOn(day);

    if (checked) {
      completedDays++;
      current++;
      if (current > best) best = current;
      if (current % daysPerToken == 0 && tokens < maxTokens) {
        tokens++;
        earns.add(key);
      }
    } else if (due && !isToday) {
      // A missed scheduled day that has fully elapsed.
      if (tokens > 0) {
        tokens--;
        frozen.add(key);
        current++;
        if (current > best) best = current;
      } else {
        current = 0;
      }
    }
    // Unscheduled days and today-without-checkin leave the streak unchanged.

    day = nextDay(day);
  }

  return StreakResult(
    currentStreak: current,
    bestStreak: best,
    tokens: tokens,
    frozenDates: frozen,
    earnEvents: earns,
    completedDays: completedDays,
  );
}

StreakResult _replayWeeklyTarget({
  required HabitSchedule schedule,
  required Set<String> checkins,
  required DateTime today,
  required DateTime startDate,
}) {
  final target = schedule.targetPerWeek ?? 1;
  var current = 0;
  var best = 0;
  var tokens = 0;
  var completedDays = 0;
  final frozen = <String>{};
  final earns = <String>{};

  // Count check-ins per week (Monday-start).
  final perWeek = <DateTime, int>{};
  for (final key in checkins) {
    final day = parseDate(key);
    if (day.isBefore(
      DateTime(startDate.year, startDate.month, startDate.day),
    )) {
      continue;
    }
    if (day.isAfter(today)) continue;
    completedDays++;
    final week = startOfWeek(day);
    perWeek[week] = (perWeek[week] ?? 0) + 1;
  }

  var week = startOfWeek(startDate);
  final currentWeek = startOfWeek(today);

  while (!week.isAfter(currentWeek)) {
    final count = perWeek[week] ?? 0;
    final isCurrentWeek = daysBetween(week, currentWeek) == 0;
    final met = count >= target;

    if (met) {
      current++;
      if (current > best) best = current;
      if (current % weeksPerToken == 0 && tokens < maxTokens) {
        tokens++;
        earns.add(formatDate(week));
      }
    } else if (!isCurrentWeek) {
      // A fully-elapsed week that missed its target.
      if (tokens > 0) {
        tokens--;
        frozen.add(formatDate(week));
        current++;
        if (current > best) best = current;
      } else {
        current = 0;
      }
    }
    // The current week, if not yet met, is still in progress — no penalty.

    week = nextDay(week).add(const Duration(days: 6));
    week = startOfWeek(week);
  }

  return StreakResult(
    currentStreak: current,
    bestStreak: best,
    tokens: tokens,
    frozenDates: frozen,
    earnEvents: earns,
    completedDays: completedDays,
  );
}
