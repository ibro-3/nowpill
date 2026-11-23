import '../../features/today/today_view_model.dart';

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
      other.dateKey == dateKey;

  @override
  int get hashCode => Object.hash(
    done,
    total,
    remaining,
    allDone,
    topStreak,
    topHabitName,
    dateKey,
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
  );
}
