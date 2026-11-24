import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../domain/date_utils.dart';
import '../../domain/schedule.dart';
import '../../domain/stats_engine.dart';
import '../../domain/streak_engine.dart';
import '../../domain/weekly_review.dart';
import '../habits/habit_providers.dart';
import '../tasks/task_providers.dart';
import 'stats_view_model.dart';

// Drift-typed providers are hand-written (riverpod_generator cannot resolve
// Drift part-file row classes). See doc/m3e_spike_decision.md.

/// The Stats dashboard's derived view model: 30-day trend, weekly summary,
/// streak leaderboard, and tag donut — all reactive.
final statsViewModelProvider = Provider<StatsViewModel>((ref) {
  final tasks = ref.watch(allTasksProvider).value ?? const <Task>[];
  final habits = ref.watch(activeHabitsProvider).value ?? const <Habit>[];
  final checkins =
      ref.watch(allCheckinsProvider).value ?? const <HabitCheckin>[];
  final tags = ref.watch(allTagsProvider).value ?? const <Tag>[];
  final links = ref.watch(allTaskTagsProvider).value ?? const <TaskTag>[];

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
  final entries = <LeaderboardEntry>[];
  var bestOverall = 0;
  for (final habit in habits) {
    final schedule = scheduleFromFields(
      type: habit.scheduleType,
      weekdays: habit.weekdays,
      targetPerWeek: habit.targetPerWeek,
    );
    final streak = replayStreak(
      schedule: schedule,
      checkins: checkinsByHabit[habit.id] ?? const <String>{},
      today: now,
      startDate: habit.createdAt.toLocal(),
      targetAmount: habit.targetAmount,
      amounts: amountsByHabit[habit.id] ?? const <String, double>{},
    );
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
  );
  final todayKey = formatDate(now);
  final checkedTodayHabitIds = {
    for (final c in checkins)
      if (c.date == todayKey) c.habitId,
  };
  final review = buildWeeklyReview(
    today: now,
    weeks: weeks,
    leaderboard: entries,
    checkedTodayHabitIds: checkedTodayHabitIds,
    dueDates: tasks.where((t) => t.completedAt == null).map((t) => t.dueAt),
  );

  final tagsById = <int, ({String name, int color})>{
    for (final tag in tags) tag.id: (name: tag.name, color: tag.color),
  };

  return StatsViewModel(
    trend: dailyTrend(
      today: now,
      checkinsByDay: checkinsByDay,
      tasksDoneByDay: tasksDoneByDay,
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
