import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/providers.dart';
import '../../domain/date_utils.dart';
import '../../domain/schedule.dart';
import '../../domain/streak_engine.dart';

// Drift-typed providers are hand-written (riverpod_generator cannot resolve
// Drift part-file row classes). See doc/m3e_spike_decision.md.

/// Active (non-archived) habits, reactive.
final activeHabitsProvider = StreamProvider<List<Habit>>((ref) {
  return ref.watch(habitRepositoryProvider).watchActive();
});

/// All habits including archived, reactive.
final allHabitsProvider = StreamProvider<List<Habit>>((ref) {
  return ref.watch(habitRepositoryProvider).watchAll();
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

/// The derived streak state for a habit, replayed from its check-in history.
final habitStreakProvider = Provider.family<StreakResult, int>((ref, habitId) {
  final habit = ref.watch(habitProvider(habitId)).value;
  if (habit == null) return StreakResult.empty;

  final checkins =
      ref.watch(habitCheckinsProvider(habitId)).value ?? const <HabitCheckin>[];
  final freezes =
      ref.watch(habitFreezesProvider(habitId)).value ?? const <HabitFreeze>[];
  final schedule = scheduleFromFields(
    type: habit.scheduleType,
    weekdays: habit.weekdays,
    targetPerWeek: habit.targetPerWeek,
  );

  return replayStreak(
    schedule: schedule,
    checkins: checkins.map((c) => c.date).toSet(),
    today: DateTime.now(),
    startDate: habit.createdAt.toLocal(),
    freezeMode: habit.freezeMode,
    manualFreezes: freezes.map((f) => f.date).toSet(),
  );
});

/// Whether a habit is checked in today.
final habitCheckedTodayProvider = Provider.family<bool, int>((ref, habitId) {
  final checkins =
      ref.watch(habitCheckinsProvider(habitId)).value ?? const <HabitCheckin>[];
  final today = formatDate(DateTime.now());
  return checkins.any((c) => c.date == today);
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
