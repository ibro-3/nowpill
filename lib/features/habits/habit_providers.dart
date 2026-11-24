import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/providers.dart';
import '../../domain/date_utils.dart';
import '../../domain/insights_engine.dart';
import '../../domain/schedule.dart';
import '../../domain/streak_engine.dart';
import '../../domain/vacation.dart' as vacation_domain;

part 'habit_providers.g.dart';

// Drift-typed providers are hand-written (riverpod_generator cannot resolve
// Drift part-file row classes). See doc/m3e_spike_decision.md.

/// Session-only routine filter on the Habits tab: null = all, -1 = Unrouted,
/// otherwise a routine id.
@Riverpod(keepAlive: true)
class RoutineFilterNotifier extends _$RoutineFilterNotifier {
  @override
  int? build() => null;

  void set(int? value) => state = value;
}

/// Active (non-archived) habits, reactive.
final activeHabitsProvider = StreamProvider<List<Habit>>((ref) {
  return ref.watch(habitRepositoryProvider).watchActive();
});

/// All habits including archived, reactive.
final allHabitsProvider = StreamProvider<List<Habit>>((ref) {
  return ref.watch(habitRepositoryProvider).watchAll();
});

/// Archived habits only, most recent first, reactive.
final archivedHabitsProvider = Provider<List<Habit>>((ref) {
  final archived = (ref.watch(allHabitsProvider).value ?? const <Habit>[])
      .where((habit) => habit.archivedAt != null)
      .toList();
  archived.sort((a, b) => b.archivedAt!.compareTo(a.archivedAt!));
  return archived;
});

/// A single habit, reactive.
final habitProvider = StreamProvider.family<Habit?, int>((ref, id) {
  return ref.watch(habitRepositoryProvider).watchById(id);
});

/// All check-ins for a habit, reactive.
final habitCheckinsProvider = StreamProvider.family<List<HabitCheckin>, int>((
  ref,
  habitId,
) {
  return ref.watch(habitRepositoryProvider).watchCheckins(habitId);
});

/// Explicit manual freezes for a habit, reactive (schema v2).
final habitFreezesProvider = StreamProvider.family<List<HabitFreeze>, int>((
  ref,
  habitId,
) {
  return ref.watch(habitRepositoryProvider).watchFreezes(habitId);
});

/// All check-ins across habits (for cross-habit stats), reactive.
final allCheckinsProvider = StreamProvider<List<HabitCheckin>>((ref) {
  return ref.watch(habitRepositoryProvider).watchAllCheckins();
});

/// All relapse events across quit habits, reactive.
final allRelapsesProvider = StreamProvider<List<HabitRelapse>>((ref) {
  return ref.watch(habitRepositoryProvider).watchAllRelapses();
});

/// Planned vacation ranges, reactive (now scoped in v7).
final vacationPeriodsProvider = StreamProvider<List<VacationPeriod>>((ref) {
  return ref.watch(habitRepositoryProvider).watchVacationPeriods();
});

/// Routine targets of scoped vacations, reactive.
final vacationScopesProvider = StreamProvider<List<VacationScope>>((ref) {
  return ref.watch(habitRepositoryProvider).watchVacationScopes();
});

/// All routines, reactive (also used by the habit editor's picker).
final allRoutinesProvider = StreamProvider<List<Routine>>((ref) {
  return ref.watch(habitRepositoryProvider).watchRoutines();
});

/// Identity of one habit's pause resolution window.
typedef PausedDaysKey = ({
  DateTime start,
  String habitUuid,
  String? routineUuid,
});

/// The set of paused day keys for one habit's lifetime, reactive. Resolution
/// is per habit: scoping changes never touch the streak engine.
final pausedDaysProvider = Provider.family<Set<String>, PausedDaysKey>((
  ref,
  key,
) {
  final periods =
      ref.watch(vacationPeriodsProvider).value ?? const <VacationPeriod>[];
  final scopes =
      ref.watch(vacationScopesProvider).value ?? const <VacationScope>[];
  return vacation_domain.resolvePausedDates(
    periods: periods.map(
      (p) => vacation_domain.VacationPeriod(
        start: p.startDate,
        end: p.endDate,
        uuid: p.uuid,
        updatedAt: p.updatedAt.millisecondsSinceEpoch,
        allHabits: p.allHabits,
      ),
    ),
    scopes: scopes.map(
      (s) => vacation_domain.VacationScope(
        periodUuid: s.periodUuid,
        targetKind: s.targetKind,
        targetUuid: s.targetUuid,
        uuid: s.uuid,
        updatedAt: s.updatedAt.millisecondsSinceEpoch,
      ),
    ),
    habitUuid: key.habitUuid,
    routineUuid: key.routineUuid,
    windowStart: key.start,
    windowEnd: DateTime.now(),
  );
});

/// Habit ids paused **today**. Used by Today, Stats, and reminders.
final pausedTodayHabitIdsProvider = Provider<Set<int>>((ref) {
  final habits = ref.watch(activeHabitsProvider).value ?? const <Habit>[];
  final now = DateTime.now();
  return {
    for (final habit in habits)
      if (ref
          .watch(
            pausedDaysProvider((
              start: habit.createdAt.toLocal(),
              habitUuid: habit.uuid,
              routineUuid: habit.routineUuid,
            )),
          )
          .contains(formatDate(now)))
        habit.id,
  };
});

/// Relapse events for a quit habit, reactive.
final habitRelapsesProvider = StreamProvider.family<List<HabitRelapse>, int>((
  ref,
  habitId,
) {
  return ref.watch(habitRepositoryProvider).watchRelapses(habitId);
});

/// The derived streak state for a habit, replayed from its check-in history.
final habitStreakProvider = Provider.family<StreakResult, int>((ref, habitId) {
  final habit = ref.watch(habitProvider(habitId)).value;
  if (habit == null) return StreakResult.empty;

  final checkins =
      ref.watch(habitCheckinsProvider(habitId)).value ?? const <HabitCheckin>[];
  final freezes =
      ref.watch(habitFreezesProvider(habitId)).value ?? const <HabitFreeze>[];
  final relapses =
      ref.watch(habitRelapsesProvider(habitId)).value ?? const <HabitRelapse>[];
  final start = habit.createdAt.toLocal();
  final paused = ref.watch(
    pausedDaysProvider((
      start: start,
      habitUuid: habit.uuid,
      routineUuid: habit.routineUuid,
    )),
  );
  final schedule = scheduleFromFields(
    type: habit.scheduleType,
    weekdays: habit.weekdays,
    targetPerWeek: habit.targetPerWeek,
  );

  return replayStreak(
    schedule: schedule,
    checkins: checkins.map((c) => c.date).toSet(),
    today: DateTime.now(),
    startDate: start,
    freezeMode: habit.freezeMode,
    manualFreezes: freezes.map((f) => f.date).toSet(),
    targetAmount: habit.targetAmount,
    amounts: {
      for (final c in checkins)
        if (c.amount != null) c.date: c.amount!,
    },
    kind: habit.kind,
    relapses: relapses.map((r) => r.date).toSet(),
    pausedDates: paused,
  );
});

/// Whether today's check-in satisfies the habit (measurable habits: the
/// logged amount reached the goal; a check-in without an amount counts full).
final habitCheckedTodayProvider = Provider.family<bool, int>((ref, habitId) {
  final habit = ref.watch(habitProvider(habitId)).value;
  final checkins =
      ref.watch(habitCheckinsProvider(habitId)).value ?? const <HabitCheckin>[];
  final today = formatDate(DateTime.now());
  final row = checkins.where((c) => c.date == today).firstOrNull;
  if (row == null) return false;
  final target = habit?.targetAmount;
  if (target == null) return true;
  final amount = row.amount;
  return amount == null || amount >= target;
});

/// The pure schedule for a habit (for due-day rendering).
final habitScheduleProvider = Provider.family<HabitSchedule, int>((
  ref,
  habitId,
) {
  final habit = ref.watch(habitProvider(habitId)).value;
  if (habit == null) return const HabitSchedule.daily();
  return scheduleFromFields(
    type: habit.scheduleType,
    weekdays: habit.weekdays,
    targetPerWeek: habit.targetPerWeek,
  );
});

/// Completion insight for one habit over a trailing window. Vacation and
/// freeze days are resolved per habit through [pausedDaysProvider].
final habitInsightProvider =
    Provider.family<HabitInsight, ({int habitId, InsightRange range})>((
      ref,
      key,
    ) {
      final habit = ref.watch(habitProvider(key.habitId)).value;
      if (habit == null) return HabitInsight.empty;

      final checkins =
          ref.watch(habitCheckinsProvider(key.habitId)).value ?? const [];
      final freezes =
          ref.watch(habitFreezesProvider(key.habitId)).value ?? const [];
      final relapses =
          ref.watch(habitRelapsesProvider(key.habitId)).value ?? const [];
      final paused = ref.watch(
        pausedDaysProvider((
          start: habit.createdAt.toLocal(),
          habitUuid: habit.uuid,
          routineUuid: habit.routineUuid,
        )),
      );

      return buildHabitInsight(
        schedule: ref.watch(habitScheduleProvider(key.habitId)),
        kind: habit.kind,
        startDate: habit.createdAt.toLocal(),
        today: DateTime.now(),
        checkins: checkins.map((c) => c.date).toSet(),
        pausedDates: paused,
        frozenDates: freezes.map((f) => f.date).toSet(),
        relapseDates: relapses.map((r) => r.date).toSet(),
        targetAmount: habit.targetAmount,
        amounts: {
          for (final c in checkins)
            if (c.amount != null) c.date: c.amount!,
        },
        range: key.range,
      );
    });
