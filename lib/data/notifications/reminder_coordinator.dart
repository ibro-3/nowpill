import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate, UpdateKind;

import '../../domain/reminder_planner.dart';
import '../../domain/schedule.dart';
import '../db/app_database.dart';
import '../repositories/habit_repository.dart';
import '../repositories/task_repository.dart';
import 'notification_service.dart';

/// How many upcoming occurrences to keep scheduled per habit.
const int kHabitReminderHorizon = 7;

/// Keeps OS notifications in sync with the database.
///
/// Rather than hooking every CRUD path, the coordinator watches the habit,
/// check-in, and task streams and recomputes the full reminder schedule on any
/// change. This covers create/update/delete, check-in (and undo), archive,
/// recurring-task spawn, and replace-all import with a single reactive path.
/// A short debounce coalesces bursts of stream events into one reschedule.
class ReminderCoordinator {
  ReminderCoordinator({
    required this._habits,
    required this._tasks,
    required this._notifications,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final HabitRepository _habits;
  final TaskRepository _tasks;
  final NotificationService _notifications;
  final DateTime Function() _clock;

  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _debounce;
  bool _started = false;

  /// Starts watching the database. Idempotent.
  void start() {
    if (_started) return;
    _started = true;
    _subs.add(_habits.watchAll().listen((_) => _scheduleReschedule()));
    _subs.add(_habits.watchAllCheckins().listen((_) => _scheduleReschedule()));
    _subs.add(_tasks.watchAll().listen((_) => _scheduleReschedule()));
    // Initial sync once the first stream events arrive.
    _scheduleReschedule();
  }

  void _scheduleReschedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), rescheduleAll);
  }

  /// Recomputes and replaces every pending reminder from current data.
  Future<void> rescheduleAll() async {
    if (_notifications.isNoOp) return;
    await _notifications.cancelAll();

    final now = _clock();
    final habits = await _habits.getAll();
    final checkins = await _habits.getAllCheckins();
    final tasks = await _tasks.getAll();

    final checkedByHabit = <int, Set<String>>{};
    for (final c in checkins) {
      (checkedByHabit[c.habitId] ??= <String>{}).add(c.date);
    }

    for (final habit in habits) {
      if (habit.archivedAt != null || habit.reminderTime == null) continue;
      final schedule = scheduleFromFields(
        type: habit.scheduleType,
        weekdays: habit.weekdays,
        targetPerWeek: habit.targetPerWeek,
      );
      final occurrences = planHabitReminders(
        habitName: habit.name,
        schedule: schedule,
        reminderTime: habit.reminderTime,
        now: now,
        checkedDays: checkedByHabit[habit.id] ?? const <String>{},
        count: kHabitReminderHorizon,
        habitId: habit.id,
      );
      await _notifications.scheduleAll(
        occurrences,
        idFor: (occ, slot) => habitReminderId(habit.id, slot),
      );
    }

    for (final task in tasks) {
      final occurrences = planTaskReminder(
        taskTitle: task.title,
        reminderAt: task.reminderAt,
        now: now,
        completed: task.completedAt != null,
        taskId: task.id,
      );
      await _notifications.scheduleAll(
        occurrences,
        idFor: (occ, slot) => taskReminderId(task.id),
      );
    }
  }

  /// Stops watching and cancels pending reminders.
  Future<void> dispose() async {
    _debounce?.cancel();
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    _started = false;
    await _notifications.cancelAll();
    _notifications.dispose();
  }
}

/// Forces drift's stream queries to re-run so the UI picks up writes made by
/// another isolate (e.g. the notification Done action in the background
/// handler, Phase 22). Drift's update notifications are per-connection, so a
/// background write is invisible to the main isolate's streams until nudged.
/// Call on app resume.
void refreshDatabaseStreams(AppDatabase db) {
  try {
    db.notifyUpdates({
      TableUpdate.onTable(db.tasks, kind: UpdateKind.update),
      TableUpdate.onTable(db.subtasks, kind: UpdateKind.update),
      TableUpdate.onTable(db.tags, kind: UpdateKind.update),
      TableUpdate.onTable(db.taskTags, kind: UpdateKind.update),
      TableUpdate.onTable(db.habits, kind: UpdateKind.update),
      TableUpdate.onTable(db.habitCheckins, kind: UpdateKind.update),
      TableUpdate.onTable(db.habitFreezes, kind: UpdateKind.update),
    });
  } catch (_) {
    // Guarded: a refresh failure must not break resume.
  }
}
