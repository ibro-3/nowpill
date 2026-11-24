import 'dart:async';

import '../../domain/date_utils.dart';
import '../../domain/schedule.dart';
import '../../domain/streak_engine.dart';
import '../../domain/vacation.dart' as vacation_domain;
import '../../features/today/today_view_model.dart';
import '../repositories/habit_repository.dart';
import '../repositories/task_repository.dart';
import 'widget_bridge_service.dart';
import 'widget_snapshot.dart';

/// Keeps the home-screen widget in sync with the database.
///
/// Mirrors the reminder coordinator's reactive pattern: watches the habit,
/// check-in, and task streams, recomputes a [WidgetSnapshot] on any change
/// (debounced), and pushes it through the [WidgetBridgeService]. Covers
/// check-ins, task completion, CRUD, and replace-all import automatically.
class WidgetSnapshotController {
  WidgetSnapshotController({
    required this._habits,
    required this._tasks,
    required this._bridge,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final HabitRepository _habits;
  final TaskRepository _tasks;
  final WidgetBridgeService _bridge;
  final DateTime Function() _clock;

  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _debounce;
  bool _started = false;

  /// Starts watching the database. Idempotent.
  void start() {
    if (_started) return;
    _started = true;
    _subs.add(_habits.watchAll().listen((_) => _scheduleRefresh()));
    _subs.add(_habits.watchAllCheckins().listen((_) => _scheduleRefresh()));
    _subs.add(_tasks.watchAll().listen((_) => _scheduleRefresh()));
    _scheduleRefresh();
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), refresh);
  }

  /// Recomputes the snapshot from current data and pushes it to the widget.
  Future<void> refresh() async {
    await _bridge.update(await compute());
  }

  /// Recomputes the snapshot from current data without pushing it. The
  /// widget-action background isolate uses this to hand the JSON to Kotlin
  /// directly (the headless engine has no widget bridge handler).
  Future<WidgetSnapshot> compute() async {
    final now = _clock();
    final habits = await _habits.getAll();
    final checkins = await _habits.getAllCheckins();
    final tasks = await _tasks.getAll();
    final periods = await _habits.getAllVacationPeriods();

    final active = habits.where((h) => h.archivedAt == null).toList();
    final paused = vacation_domain.expandPausedDates(
      periods.map(
        (p) =>
            vacation_domain.VacationPeriod(start: p.startDate, end: p.endDate),
      ),
    );
    final vm = computeTodayViewModel(
      tasks: tasks,
      habits: active,
      checkins: checkins,
      now: now,
      pausedDates: paused,
    );

    // Current streak per active habit (pure replay), for the headline streak.
    final checkedByHabit = <int, Set<String>>{};
    final amountsByHabit = <int, Map<String, double>>{};
    for (final c in checkins) {
      (checkedByHabit[c.habitId] ??= <String>{}).add(c.date);
      if (c.amount != null) {
        (amountsByHabit[c.habitId] ??= <String, double>{})[c.date] = c.amount!;
      }
    }
    final freezes = await _habits.getAllFreezes();
    final freezesByHabit = <int, Set<String>>{};
    for (final f in freezes) {
      (freezesByHabit[f.habitId] ??= <String>{}).add(f.date);
    }
    final streaks = <String, int>{};
    for (final habit in active) {
      final result = replayStreak(
        schedule: scheduleFromFields(
          type: habit.scheduleType,
          weekdays: habit.weekdays,
          targetPerWeek: habit.targetPerWeek,
        ),
        checkins: checkedByHabit[habit.id] ?? const <String>{},
        today: now,
        startDate: habit.createdAt.toLocal(),
        freezeMode: habit.freezeMode,
        manualFreezes: freezesByHabit[habit.id] ?? const <String>{},
        targetAmount: habit.targetAmount,
        amounts: amountsByHabit[habit.id] ?? const <String, double>{},
      );
      streaks[habit.name] = result.currentStreak;
    }

    return buildWidgetSnapshot(
      vm: vm,
      streaksByHabitName: streaks,
      dateKey: formatDate(now),
      now: now,
    );
  }

  /// Stops watching.
  Future<void> dispose() async {
    _debounce?.cancel();
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    _started = false;
  }
}
