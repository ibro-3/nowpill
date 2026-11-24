import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../domain/date_utils.dart';
import '../../domain/enums.dart';
import '../../domain/insights_engine.dart';
import '../../domain/schedule.dart';
import '../../domain/stats_engine.dart';
import '../../domain/streak_engine.dart';
import '../../domain/weekly_review.dart';
import '../habits/habit_providers.dart';
import '../tasks/task_providers.dart';
import 'stats_view_model.dart';

// Drift-typed providers are hand-written (riverpod_generator cannot resolve
// Drift part-file row classes). See doc/m3e_spike_decision.md.

/// Session-only range shared by the Stats trend and insight cards.
final statsRangeProvider = NotifierProvider<StatsRangeNotifier, InsightRange>(
  StatsRangeNotifier.new,
);

class StatsRangeNotifier extends Notifier<InsightRange> {
  @override
  InsightRange build() => InsightRange.last30Days;

  void set(InsightRange value) => state = value;
}

/// The Stats dashboard's derived view model: 30-day trend, weekly summary,
/// streak leaderboard, and tag donut — all reactive.
final statsViewModelProvider = Provider<StatsViewModel>((ref) {
  final tasks = ref.watch(allTasksProvider).value ?? const <Task>[];
  final habits = ref.watch(activeHabitsProvider).value ?? const <Habit>[];
  final checkins =
      ref.watch(allCheckinsProvider).value ?? const <HabitCheckin>[];
  final relapses =
      ref.watch(allRelapsesProvider).value ?? const <HabitRelapse>[];
  final tags = ref.watch(allTagsProvider).value ?? const <Tag>[];
  final links = ref.watch(allTaskTagsProvider).value ?? const <TaskTag>[];
  final routines = ref.watch(allRoutinesProvider).value ?? const <Routine>[];
  final range = ref.watch(statsRangeProvider);

  final now = DateTime.now();

  // Per-day completion counts.
  final checkinsByDay = <String, int>{};
  for (final c in checkins) {
    checkinsByDay[c.date] = (checkinsByDay[c.date] ?? 0) + 1;
  }
  final tasksDoneByDay = <String, int>{};
  var totalTasksDone = 0;
  for (final t in tasks) {
    final completedAt = t.completedAt;
    if (completedAt == null) continue;
    totalTasksDone++;
    final key = formatDate(completedAt.toLocal());
    tasksDoneByDay[key] = (tasksDoneByDay[key] ?? 0) + 1;
  }

  // Leaderboard: replay each active habit's streak from its check-ins.
  final checkinsByHabit = <int, Set<String>>{};
  final amountsByHabit = <int, Map<String, double>>{};
  for (final c in checkins) {
    (checkinsByHabit[c.habitId] ??= <String>{}).add(c.date);
    if (c.amount != null) {
      (amountsByHabit[c.habitId] ??= <String, double>{})[c.date] = c.amount!;
    }
  }
  final relapsesByHabit = <int, Set<String>>{};
  for (final r in relapses) {
    (relapsesByHabit[r.habitId] ??= <String>{}).add(r.date);
  }

  final entries = <LeaderboardEntry>[];
  final quitHabitIds = <int>{};
  final allPausedDates = <String>{};
  final pausedByHabit = <int, Set<String>>{};
  var bestOverall = 0;
  for (final habit in habits) {
    if (habit.kind == HabitKind.quit) quitHabitIds.add(habit.id);
    final schedule = scheduleFromFields(
      type: habit.scheduleType,
      weekdays: habit.weekdays,
      targetPerWeek: habit.targetPerWeek,
    );
    final pausedForHabit = ref.watch(
      pausedDaysProvider((
        start: habit.createdAt.toLocal(),
        habitUuid: habit.uuid,
        routineUuid: habit.routineUuid,
      )),
    );
    final streak = replayStreak(
      schedule: schedule,
      checkins: checkinsByHabit[habit.id] ?? const <String>{},
      today: now,
      startDate: habit.createdAt.toLocal(),
      targetAmount: habit.targetAmount,
      amounts: amountsByHabit[habit.id] ?? const <String, double>{},
      kind: habit.kind,
      relapses: relapsesByHabit[habit.id] ?? const <String>{},
      pausedDates: pausedForHabit,
    );
    allPausedDates.addAll(pausedForHabit);
    pausedByHabit[habit.id] = pausedForHabit;
    if (streak.bestStreak > bestOverall) bestOverall = streak.bestStreak;
    entries.add(
      LeaderboardEntry(
        habitId: habit.id,
        name: habit.name,
        iconKey: habit.iconKey,
        color: habit.color,
        currentStreak: streak.currentStreak,
        bestStreak: streak.bestStreak,
        isWeekly: !schedule.isDayBased,
      ),
    );
  }

  final weeks = weeklySummary(
    today: now,
    checkinsByDay: checkinsByDay,
    tasksDoneByDay: tasksDoneByDay,
    pausedDates: allPausedDates,
  );
  final todayKey = formatDate(now);
  final checkedTodayHabitIds = {
    for (final c in checkins)
      if (c.date == todayKey) c.habitId,
  };
  // A vacation day is neutral: paused habits are not "at risk" for skipping it.
  final pausedTodayIds = ref.watch(pausedTodayHabitIdsProvider);
  final review = buildWeeklyReview(
    today: now,
    weeks: weeks,
    leaderboard: entries,
    checkedTodayHabitIds: checkedTodayHabitIds,
    dueDates: tasks.where((t) => t.completedAt == null).map((t) => t.dueAt),
    excludedHabitIds: {...quitHabitIds, ...pausedTodayIds},
  );

  final tagsById = <int, ({String name, int color})>{
    for (final tag in tags) tag.id: (name: tag.name, color: tag.color),
  };

  // Completion insights reuse each habit's already-resolved paused days so
  // vacations and freezes are treated identically to the streak engine.
  final insights = <int, HabitInsight>{};
  final completion = <HabitCompletionEntry>[];
  for (final habit in habits) {
    final freezes =
        ref.watch(habitFreezesProvider(habit.id)).value ??
        const <HabitFreeze>[];
    final insight = buildHabitInsight(
      schedule: scheduleFromFields(
        type: habit.scheduleType,
        weekdays: habit.weekdays,
        targetPerWeek: habit.targetPerWeek,
      ),
      kind: habit.kind,
      startDate: habit.createdAt.toLocal(),
      today: now,
      checkins: checkinsByHabit[habit.id] ?? const <String>{},
      pausedDates: pausedByHabit[habit.id] ?? const <String>{},
      frozenDates: {for (final f in freezes) f.date},
      relapseDates: relapsesByHabit[habit.id] ?? const <String>{},
      targetAmount: habit.targetAmount,
      amounts: amountsByHabit[habit.id] ?? const <String, double>{},
      range: range,
    );
    insights[habit.id] = insight;
    completion.add(
      HabitCompletionEntry(
        habitId: habit.id,
        name: habit.name,
        iconKey: habit.iconKey,
        color: habit.color,
        insight: insight,
      ),
    );
  }
  completion.sort((a, b) {
    final ar = a.insight.rate;
    final br = b.insight.rate;
    if (ar == null && br == null) return a.name.compareTo(b.name);
    if (ar == null) return 1;
    if (br == null) return -1;
    final c = br.compareTo(ar);
    return c != 0 ? c : a.name.compareTo(b.name);
  });

  final routineInsights = buildRoutineInsights(
    labels: {
      for (final routine in routines) routine.id: routine.name,
      null: '',
    },
    habits: [
      for (final habit in habits)
        (routineId: habit.routineId, insight: insights[habit.id]!),
    ],
  );

  return StatsViewModel(
    range: range,
    habitCompletion: completion,
    routineCompletion: routineInsights,
    trend: dailyTrend(
      today: now,
      checkinsByDay: checkinsByDay,
      tasksDoneByDay: tasksDoneByDay,
      days: range.days,
    ),
    weeks: weeks,
    leaderboard: rankLeaderboard(entries),
    tagSlices: tagDistribution(
      tagsById: tagsById,
      links: links.map((l) => (taskId: l.taskId, tagId: l.tagId)),
    ),
    totalCheckins: checkins.length,
    totalTasksDone: totalTasksDone,
    activeHabits: habits.length,
    bestStreakOverall: bestOverall,
    review: review,
  );
});
