/// Task priority levels, ordered from lowest to highest urgency.
///
/// Stored as an integer index in the database (stable ordering — do not
/// reorder these values without a migration).
enum TaskPriority { none, low, medium, high }

/// How a habit's schedule determines which days it is due.
///
/// Stored as an integer index in the database (stable ordering — do not
/// reorder these values without a migration).
enum HabitScheduleType {
  /// Due every day.
  daily,

  /// Due on specific weekdays (see the `weekdays` column).
  weekdays,

  /// Due any day, but must be completed `targetPerWeek` times per week.
  weeklyTarget,
}

/// The unit of a recurrence rule.
enum RecurrenceUnit { day, week, month }

/// How a habit spends freeze tokens to bridge missed days.
///
/// Stored as an integer index in the database (stable ordering — do not
/// reorder these values without a migration).
enum FreezeMode {
  /// Tokens auto-consume to bridge a missed scheduled day (default). The
  /// streak engine derives freezes purely from check-in history.
  auto,

  /// Tokens are spent only when the user explicitly places a freeze on a
  /// missed day. Missed days without an explicit freeze reset the streak.
  manual,
}
