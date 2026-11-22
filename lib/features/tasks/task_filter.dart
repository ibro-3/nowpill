/// Which slice of tasks the list shows.
enum TaskFilter {
  /// Due today or overdue, not completed.
  today,

  /// Due after today, not completed.
  upcoming,

  /// Every task regardless of completion.
  all,

  /// Completed tasks only.
  done,
}
