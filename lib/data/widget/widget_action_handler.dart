import '../../domain/date_utils.dart';
import '../db/app_database.dart';
import '../repositories/habit_repository.dart';
import '../repositories/task_repository.dart';
import 'widget_bridge_service.dart';
import 'widget_snapshot.dart';
import 'widget_snapshot_controller.dart';

// The background entry point touches dart:ffi (via drift/native), so it lives
// behind a conditional export: native platforms get the real handler, web a
// no-op. Only Android's Kotlin receiver ever launches it.
export 'widget_action_stub.dart'
    if (dart.library.io) 'widget_action_native.dart';

/// The widget check-in action id, shared by the Android broadcast receiver
/// and the Dart handler.
const String kWidgetActionCheck = 'check';

/// Parses a widget action payload (`check:<habitId>`). Null when malformed.
({String action, int habitId})? parseWidgetActionPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  final parts = payload.split(':');
  if (parts.length != 2 || parts[0] != kWidgetActionCheck) return null;
  final id = int.tryParse(parts[1]);
  if (id == null) return null;
  return (action: parts[0], habitId: id);
}

/// Applies a widget check-in through the repository (so `updatedAt` is
/// stamped and sync picks it up) and returns the recomputed snapshot, or
/// null when the habit is missing/archived or anything failed. The caller
/// decides how to deliver the snapshot: the background isolate hands the
/// JSON to Kotlin over the action channel (the headless engine has no widget
/// bridge handler); the foreground path pushes through the normal bridge.
/// Guarded: a failed action must never crash the caller.
Future<WidgetSnapshot?> applyWidgetCheckIn(AppDatabase db, int habitId) async {
  try {
    final habits = HabitRepository(db);
    final habit = await habits.getById(habitId);
    if (habit == null || habit.archivedAt != null) return null;
    // Measurable habits: a widget check completes the whole goal (same rule
    // as the notification Done action).
    await habits.checkIn(
      habitId,
      formatDate(DateTime.now()),
      amount: habit.targetAmount,
    );
    return await WidgetSnapshotController(
      habits: habits,
      tasks: TaskRepository(db),
      bridge: WidgetBridgeService(),
    ).compute();
  } catch (_) {
    // Guarded.
    return null;
  }
}
