import 'date_utils.dart';
import 'enums.dart';
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
///
/// [freezeMode] selects how freezes are spent:
/// * [FreezeMode.auto] (default) — a missed scheduled day auto-consumes a token
///   if one is available; freezes are derived purely from history.
/// * [FreezeMode.manual] — a missed day is bridged only when [manualFreezes]
///   contains an explicit freeze for it (the day for day-based habits, the
///   week's Monday for weekly-target) AND a token is available at that point in
///   the replay. Tokens are still earned by the same cadence.
///
/// In both modes a real check-in always wins over a freeze, so backfilling a
/// frozen day refunds the token (the freeze is simply not needed/consumed).
///
/// [targetAmount] enables measurable habits (v0.3.0): when non-null, a day
/// only counts toward the streak if its logged [amounts] entry reaches the
/// target (100%). Partial progress is UI-only — it never extends the streak.
/// A check-in without an amount counts as full (legacy / one-tap check-ins).
/// When [targetAmount] is null the output is byte-identical to pre-v0.3.0.
/// For weekly-target habits each fully-met day counts once toward the weekly
/// target; partial days do not count.
StreakResult replayStreak({
  required HabitSchedule schedule,
  required Set<String> checkins,
  required DateTime today,
  required DateTime startDate,
  FreezeMode freezeMode = FreezeMode.auto,
  Set<String> manualFreezes = const {},
  double? targetAmount,
  Map<String, double> amounts = const {},
}) {
  // startDate is a calendar day ("the first day the habit existed"), not an
  // instant. Normalize to date-only local so a creation time later in the day
  // does not exclude same-day check-ins (parsed as local midnight).
  final startDay = DateTime(startDate.year, startDate.month, startDate.day);
  if (schedule.isDayBased) {
    return _replayDayBased(
      schedule: schedule,
      checkins: checkins,
      today: today,
      startDate: startDay,
      freezeMode: freezeMode,
      manualFreezes: manualFreezes,
      targetAmount: targetAmount,
      amounts: amounts,
    );
  }
  return _replayWeeklyTarget(
    schedule: schedule,
    checkins: checkins,
    today: today,
    startDate: startDay,
    freezeMode: freezeMode,
    manualFreezes: manualFreezes,
    targetAmount: targetAmount,
    amounts: amounts,
  );
}

/// Whether a check-in on [key] satisfies the habit's numeric goal. With no
/// target every check-in counts; with a target a missing amount counts as
/// full (one-tap / legacy check-ins), otherwise the amount must reach it.
bool dayMeetsGoal(
  String key,
  double? targetAmount,
  Map<String, double> amounts,
) {
  if (targetAmount == null) return true;
  final amount = amounts[key];
  if (amount == null) return true;
  return amount >= targetAmount;
}

StreakResult _replayDayBased({
  required HabitSchedule schedule,
  required Set<String> checkins,
  required DateTime today,
  required DateTime startDate,
  required FreezeMode freezeMode,
  required Set<String> manualFreezes,
  required double? targetAmount,
  required Map<String, double> amounts,
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
    final metGoal = checked && dayMeetsGoal(key, targetAmount, amounts);
    final due = schedule.isDueOn(day);

    if (metGoal) {
      completedDays++;
      current++;
      if (current > best) best = current;
      if (current % daysPerToken == 0 && tokens < maxTokens) {
        tokens++;
        earns.add(key);
      }
    } else if (due && !isToday) {
      // A missed scheduled day that has fully elapsed (a partial measurable
      // day counts as missed — only 100% keeps the streak). In auto mode any
      // available token bridges it; in manual mode only an explicit freeze does.
      final bridged =
          freezeMode == FreezeMode.auto || manualFreezes.contains(key);
      if (bridged && tokens > 0) {
        tokens--;
        frozen.add(key);
        current++;
        if (current > best) best = current;
      } else {
        current = 0;
      }
    }
    // Unscheduled days, partial progress today, and today-without-checkin
    // leave the streak unchanged.

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
  required FreezeMode freezeMode,
  required Set<String> manualFreezes,
  required double? targetAmount,
  required Map<String, double> amounts,
}) {
  final target = schedule.targetPerWeek ?? 1;
  var current = 0;
  var best = 0;
  var tokens = 0;
  var completedDays = 0;
  final frozen = <String>{};
  final earns = <String>{};

  // Count goal-met check-ins per week (Monday-start). For measurable habits a
  // partial day does not count toward the weekly target.
  final perWeek = <DateTime, int>{};
  for (final key in checkins) {
    final day = parseDate(key);
    if (day.isBefore(
      DateTime(startDate.year, startDate.month, startDate.day),
    )) {
      continue;
    }
    if (day.isAfter(today)) continue;
    if (!dayMeetsGoal(key, targetAmount, amounts)) continue;
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
      // A fully-elapsed week that missed its target. Auto mode bridges with any
      // available token; manual mode requires an explicit freeze on the Monday.
      final weekKey = formatDate(week);
      final bridged =
          freezeMode == FreezeMode.auto || manualFreezes.contains(weekKey);
      if (bridged && tokens > 0) {
        tokens--;
        frozen.add(weekKey);
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
