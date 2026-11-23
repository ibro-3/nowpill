import '../../features/today/today_view_model.dart';

/// One habit row in the widget snapshot (v2): enough for the interactive
/// home-screen widgets to render a check pill per habit.
class WidgetHabit {
  const WidgetHabit({
    required this.id,
    required this.name,
    required this.done,
    required this.color,
    this.amount,
    this.target,
  });

  /// Local database id — device-private, only used to dispatch check-ins on
  /// this device (never synced).
  final int id;
  final String name;

  /// Whether today's goal is met (measurable: amount reached target).
  final bool done;

  /// ARGB brand color chosen for the habit.
  final int color;

  /// Today's logged amount (measurable habits only).
  final double? amount;

  /// The numeric daily goal (measurable habits only).
  final double? target;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'done': done,
    'color': color,
    'amount': amount,
    'target': target,
  };

  @override
  bool operator ==(Object other) =>
      other is WidgetHabit &&
      other.id == id &&
      other.name == name &&
      other.done == done &&
      other.color == color &&
      other.amount == amount &&
      other.target == target;

  @override
  int get hashCode => Object.hash(id, name, done, color, amount, target);
}

/// A compact, platform-agnostic summary of today's progress, consumed by the
/// home-screen widgets (Android AppWidget / iOS WidgetKit). Kept pure so it is
/// unit-testable; the bridge layer serializes it and pushes it to the OS.
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.done,
    required this.total,
    required this.remaining,
    required this.allDone,
    required this.topStreak,
    required this.topHabitName,
    required this.dateKey,
    required this.updatedAtMillis,
    this.habits = const [],
  });

  /// Items already done today (checked habits + tasks completed today).
  final int done;

  /// Total items scheduled for today.
  final int total;

  /// Open items remaining.
  final int remaining;

  /// Whether there is work scheduled and every item is done.
  final bool allDone;

  /// Longest current streak across active habits (0 when none).
  final int topStreak;

  /// Name of the habit holding [topStreak] (empty when none).
  final String topHabitName;

  /// Local calendar day the snapshot describes (`yyyy-MM-dd`).
  final String dateKey;

  /// When the snapshot was computed (UTC millis).
  final int updatedAtMillis;

  /// Today's due habits, in dashboard order (v2 — interactive widgets).
  final List<WidgetHabit> habits;

  /// The first habit still undone today, or null when all are done / none due.
  WidgetHabit? get nextUndoneHabit {
    for (final h in habits) {
      if (!h.done) return h;
    }
    return null;
  }

  static const WidgetSnapshot empty = WidgetSnapshot(
    done: 0,
    total: 0,
    remaining: 0,
    allDone: false,
    topStreak: 0,
    topHabitName: '',
    dateKey: '',
    updatedAtMillis: 0,
  );

  /// JSON payload handed to the platform widget bridge.
  Map<String, Object?> toJson() => {
    'done': done,
    'total': total,
    'remaining': remaining,
    'allDone': allDone,
    'topStreak': topStreak,
    'topHabitName': topHabitName,
    'dateKey': dateKey,
    'updatedAtMillis': updatedAtMillis,
    'habits': [for (final h in habits) h.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is WidgetSnapshot &&
      other.done == done &&
      other.total == total &&
      other.remaining == remaining &&
      other.allDone == allDone &&
      other.topStreak == topStreak &&
      other.topHabitName == topHabitName &&
      other.dateKey == dateKey &&
      _habitsEqual(other.habits);

  bool _habitsEqual(List<WidgetHabit> other) {
    if (habits.length != other.length) return false;
    for (var i = 0; i < habits.length; i++) {
      if (habits[i] != other[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    done,
    total,
    remaining,
    allDone,
    topStreak,
    topHabitName,
    dateKey,
    Object.hashAll(habits),
  );
}

/// Builds a [WidgetSnapshot] from the Today view model plus per-habit current
/// streaks. [streaksByHabitName] maps active habit names to their current
/// streak; the highest becomes the headline streak.
WidgetSnapshot buildWidgetSnapshot({
  required TodayViewModel vm,
  required Map<String, int> streaksByHabitName,
  required String dateKey,
  required DateTime now,
}) {
  var topStreak = 0;
  var topName = '';
  for (final entry in streaksByHabitName.entries) {
    if (entry.value > topStreak) {
      topStreak = entry.value;
      topName = entry.key;
    }
  }
  return WidgetSnapshot(
    done: vm.done,
    total: vm.total,
    remaining: vm.remaining,
    allDone: vm.allDone,
    topStreak: topStreak,
    topHabitName: topName,
    dateKey: dateKey,
    updatedAtMillis: now.toUtc().millisecondsSinceEpoch,
    habits: [
      for (final h in vm.habits)
        WidgetHabit(
          id: h.habit.id,
          name: h.habit.name,
          done: h.checkedToday,
          color: h.habit.color,
          amount: h.amountToday,
          target: h.targetAmount,
        ),
    ],
  );
}
