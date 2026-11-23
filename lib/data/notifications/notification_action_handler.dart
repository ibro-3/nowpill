import '../../domain/date_utils.dart';
import '../db/app_database.dart';
import '../repositories/habit_repository.dart';
import '../repositories/task_repository.dart';

// The background-isolate entry point touches dart:ffi (via drift/native), so
// it lives behind a conditional export: native platforms get the real
// handler, web gets a no-op (web reminders have no background actions).
export 'notification_background_stub.dart'
    if (dart.library.io) 'notification_background_native.dart';

/// Android notification action ids.
const String kActionDone = 'done';
const String kActionSnooze10 = 'snooze10';
const String kActionSnooze60 = 'snooze60';

/// Parses a reminder payload (`habit:<id>:<dayKey>:<label>` / `task:<id>:<label>`).
({String kind, int id, String? dayKey, String label})? parseReminderPayload(
  String? payload,
) {
  if (payload == null || payload.isEmpty) return null;
  final parts = payload.split(':');
  if (parts.length < 2) return null;
  final id = int.tryParse(parts[1]);
  if (id == null) return null;
  if (parts[0] == 'habit') {
    return (
      kind: 'habit',
      id: id,
      dayKey: parts.length > 2 ? parts[2] : null,
      label: parts.length > 3 ? parts.sublist(3).join(':') : '',
    );
  }
  if (parts[0] == 'task') {
    return (
      kind: 'task',
      id: id,
      dayKey: null,
      label: parts.length > 2 ? parts.sublist(2).join(':') : '',
    );
  }
  return null;
}

/// Applies the Done action through the repositories (so `updatedAt` is stamped
/// and sync picks it up). Shared by the background isolate (own connection)
/// and the foreground handler (the app's shared connection). Guarded: a
/// failed action must never crash the caller.
Future<void> applyDoneAction(
  AppDatabase db,
  ({String kind, int id, String? dayKey, String label}) parsed,
) async {
  try {
    if (parsed.kind == 'habit') {
      final dayKey = parsed.dayKey?.isNotEmpty == true
          ? parsed.dayKey!
          : formatDate(DateTime.now());
      final habits = HabitRepository(db);
      final habit = await habits.getById(parsed.id);
      // Measurable habits: Done completes the whole goal.
      await habits.checkIn(parsed.id, dayKey, amount: habit?.targetAmount);
    } else {
      await TaskRepository(db).complete(parsed.id);
    }
  } catch (_) {
    // Guarded.
  }
}
