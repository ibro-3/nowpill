import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import 'converters.dart';

/// Tasks (to-dos). Completing a recurring task spawns the next occurrence;
/// history is preserved via [completedAt].
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get title => text().withLength(min: 1, max: 500)();

  TextColumn get notes => text().nullable()();

  /// When the task is due. Null = no due date (inbox-style).
  IntColumn get dueAt => integer().nullable().map(const UtcMillisConverter())();

  IntColumn get priority => intEnum<TaskPriority>()();

  /// Set when completed; null while open.
  IntColumn get completedAt =>
      integer().nullable().map(const UtcMillisConverter())();

  /// Null = one-off task.
  TextColumn get recurrenceRule =>
      text().nullable().map(const RecurrenceRuleConverter())();

  /// Optional reminder time for this task.
  IntColumn get reminderAt =>
      integer().nullable().map(const UtcMillisConverter())();

  IntColumn get createdAt => integer().map(const UtcMillisConverter())();

  /// Manual ordering within lists.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

/// Checklist items belonging to a task.
class Subtasks extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();

  TextColumn get title => text().withLength(min: 1, max: 500)();

  BoolColumn get done => boolean().withDefault(const Constant(false))();

  IntColumn get position => integer().withDefault(const Constant(0))();
}

/// User-defined tags for organizing tasks.
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 100).unique()();

  /// ARGB color value.
  IntColumn get color => integer()();
}

/// Many-to-many link between tasks and tags.
class TaskTags extends Table {
  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();

  IntColumn get tagId =>
      integer().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {taskId, tagId};
}

/// Habits with schedules, streaks, and freeze tokens (derived by the domain
/// engine from check-in history).
class Habits extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 200)();

  TextColumn get notes => text().nullable()();

  /// Key into the curated icon set (see Phase 5).
  TextColumn get iconKey => text().withDefault(const Constant('spark'))();

  /// ARGB color value.
  IntColumn get color => integer()();

  IntColumn get scheduleType => intEnum<HabitScheduleType>()();

  /// ISO weekdays (1 = Mon … 7 = Sun) for [HabitScheduleType.weekdays].
  TextColumn get weekdays => text().nullable().map(const WeekdaysConverter())();

  /// Target completions per week for [HabitScheduleType.weeklyTarget].
  IntColumn get targetPerWeek => integer().nullable()();

  /// Optional daily reminder time (stored as UTC millis; the time-of-day is
  /// what matters, interpreted in the device's local zone when scheduling).
  IntColumn get reminderTime =>
      integer().nullable().map(const UtcMillisConverter())();

  IntColumn get createdAt => integer().map(const UtcMillisConverter())();

  /// Archived habits are hidden from active lists but keep their history.
  IntColumn get archivedAt =>
      integer().nullable().map(const UtcMillisConverter())();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

/// One check-in per habit per day. Dates are `yyyy-MM-dd` local-day strings
/// (timezone-proof); the unique constraint prevents double check-ins.
class HabitCheckins extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get habitId =>
      integer().references(Habits, #id, onDelete: KeyAction.cascade)();

  /// Local calendar day, `yyyy-MM-dd`.
  TextColumn get date => text().withLength(min: 10, max: 10)();

  TextColumn get note => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {habitId, date},
  ];
}
