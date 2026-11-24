import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/enums.dart';
import 'converters.dart';

/// Shared UUID generator for cross-device row identity (schema v3). Local
/// integer PKs remain the on-device keys; uuids identify rows across devices.
const Uuid syncUuid = Uuid();

/// User-defined lists (projects) for grouping tasks (schema v5).
///
/// A task's list is a soft reference: deleting a list clears the link but
/// keeps its tasks. That makes the reference safe across devices where a list
/// may not have arrived yet.
class TaskLists extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Cross-device identity (schema v3). Preserved on merge.
  TextColumn get uuid => text().unique().clientDefault(syncUuid.v4)();

  /// Last modification time (UTC millis) for sync merge.
  IntColumn get updatedAt => integer()
      .map(const UtcMillisConverter())
      .clientDefault(() => DateTime.now().toUtc().millisecondsSinceEpoch)();

  TextColumn get name => text().withLength(min: 1, max: 100).unique()();

  /// ARGB color value.
  IntColumn get color => integer()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

/// Tasks (to-dos). Completing a recurring task spawns the next occurrence;
/// history is preserved via [completedAt].
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Cross-device identity (schema v3). Unique per row, preserved on merge.
  TextColumn get uuid => text().unique().clientDefault(syncUuid.v4)();

  /// Last modification time (UTC millis) for sync merge (schema v3).
  IntColumn get updatedAt => integer()
      .map(const UtcMillisConverter())
      .clientDefault(() => DateTime.now().toUtc().millisecondsSinceEpoch)();

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

  /// Optional parent list (schema v5). Null = inbox / no list. Deleting the
  /// list sets this to null but keeps the task (soft reference).
  IntColumn get listId => integer().nullable().references(
    TaskLists,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Parent list uuid (schema v5) — survives merges that remap local ids.
  TextColumn get listUuid => text().nullable()();
}

/// Checklist items belonging to a task.
class Subtasks extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Cross-device identity (schema v3).
  TextColumn get uuid => text().unique().clientDefault(syncUuid.v4)();

  /// Last modification time (UTC millis) for sync merge (schema v3).
  IntColumn get updatedAt => integer()
      .map(const UtcMillisConverter())
      .clientDefault(() => DateTime.now().toUtc().millisecondsSinceEpoch)();

  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();

  /// Parent task uuid (schema v3) — survives merges that remap local ids.
  TextColumn get taskUuid => text()();

  TextColumn get title => text().withLength(min: 1, max: 500)();

  BoolColumn get done => boolean().withDefault(const Constant(false))();

  IntColumn get position => integer().withDefault(const Constant(0))();
}

/// User-defined tags for organizing tasks.
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Cross-device identity (schema v3).
  TextColumn get uuid => text().unique().clientDefault(syncUuid.v4)();

  /// Last modification time (UTC millis) for sync merge (schema v3).
  IntColumn get updatedAt => integer()
      .map(const UtcMillisConverter())
      .clientDefault(() => DateTime.now().toUtc().millisecondsSinceEpoch)();

  TextColumn get name => text().withLength(min: 1, max: 100).unique()();

  /// ARGB color value.
  IntColumn get color => integer()();
}

/// Many-to-many link between tasks and tags.
class TaskTags extends Table {
  /// Cross-device identity (schema v3).
  TextColumn get uuid => text().unique().clientDefault(syncUuid.v4)();

  /// Last modification time (UTC millis) for sync merge (schema v3).
  IntColumn get updatedAt => integer()
      .map(const UtcMillisConverter())
      .clientDefault(() => DateTime.now().toUtc().millisecondsSinceEpoch)();

  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();

  IntColumn get tagId =>
      integer().references(Tags, #id, onDelete: KeyAction.cascade)();

  /// Parent uuids (schema v3) — survive merges that remap local ids.
  TextColumn get taskUuid => text()();
  TextColumn get tagUuid => text()();

  @override
  Set<Column> get primaryKey => {taskId, tagId};
}

/// Named groups of habits (schema v7). Routines are cosmetic + filtering;
/// they also scope planned vacations. Like task lists, names are unique.
class Routines extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get uuid => text().unique().clientDefault(syncUuid.v4)();

  IntColumn get updatedAt => integer()
      .map(const UtcMillisConverter())
      .clientDefault(() => DateTime.now().toUtc().millisecondsSinceEpoch)();

  TextColumn get name => text().withLength(min: 1, max: 100).unique()();

  /// ARGB color value.
  IntColumn get color => integer()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

/// Habits with schedules, streaks, and freeze tokens (derived by the domain
/// engine from check-in history).
class Habits extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Cross-device identity (schema v3).
  TextColumn get uuid => text().unique().clientDefault(syncUuid.v4)();

  /// Last modification time (UTC millis) for sync merge (schema v3).
  IntColumn get updatedAt => integer()
      .map(const UtcMillisConverter())
      .clientDefault(() => DateTime.now().toUtc().millisecondsSinceEpoch)();

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

  /// How freeze tokens are spent: auto-consume (default) or explicit manual
  /// placement. Added in schema v2. Ignored for [HabitKind.quit] habits.
  IntColumn get freezeMode =>
      intEnum<FreezeMode>().withDefault(const Constant(0))();

  /// Build (default) or quit. Quit habits derive streaks from the absence of
  /// relapses and do not use tokens. Added in schema v6.
  IntColumn get kind => intEnum<HabitKind>().withDefault(const Constant(0))();

  /// Optional routine membership (schema v7). Deleting a routine clears the
  /// link and never deletes the habit — the same soft rule as task lists.
  IntColumn get routineId => integer().nullable().references(
    Routines,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Stable routine identity across merges (schema v7).
  TextColumn get routineUuid => text().nullable()();

  /// Optional numeric daily goal (schema v4, measurable habits). When set, a
  /// check-in only counts toward the streak at 100% of this amount; partial
  /// progress is UI-only. Null = classic one-tap habit.
  RealColumn get targetAmount => real().nullable()();

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

  /// Cross-device identity (schema v3).
  TextColumn get uuid => text().unique().clientDefault(syncUuid.v4)();

  /// Last modification time (UTC millis) for sync merge (schema v3).
  IntColumn get updatedAt => integer()
      .map(const UtcMillisConverter())
      .clientDefault(() => DateTime.now().toUtc().millisecondsSinceEpoch)();

  IntColumn get habitId =>
      integer().references(Habits, #id, onDelete: KeyAction.cascade)();

  /// Parent habit uuid (schema v3) — survives merges that remap local ids.
  TextColumn get habitUuid => text()();

  /// Local calendar day, `yyyy-MM-dd`.
  TextColumn get date => text().withLength(min: 10, max: 10)();

  TextColumn get note => text().nullable()();

  /// Logged amount for measurable habits (schema v4). Null = full completion
  /// (one-tap check-ins and pre-v4 rows count as 100%).
  RealColumn get amount => real().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {habitId, date},
  ];
}

/// Explicit user-placed freezes for habits in [FreezeMode.manual]. Each row
/// spends one token to bridge a missed day (day-based: the day; weekly-target:
/// the week's Monday). Added in schema v2. Auto-mode habits ignore this table.
class HabitFreezes extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Cross-device identity (schema v3).
  TextColumn get uuid => text().unique().clientDefault(syncUuid.v4)();

  /// Last modification time (UTC millis) for sync merge (schema v3).
  IntColumn get updatedAt => integer()
      .map(const UtcMillisConverter())
      .clientDefault(() => DateTime.now().toUtc().millisecondsSinceEpoch)();

  IntColumn get habitId =>
      integer().references(Habits, #id, onDelete: KeyAction.cascade)();

  /// Parent habit uuid (schema v3) — survives merges that remap local ids.
  TextColumn get habitUuid => text()();

  /// Local calendar day (`yyyy-MM-dd`) — the missed day, or the week's Monday
  /// for weekly-target habits.
  TextColumn get date => text().withLength(min: 10, max: 10)();

  IntColumn get createdAt => integer().map(const UtcMillisConverter())();

  @override
  List<Set<Column>> get uniqueKeys => [
    {habitId, date},
  ];
}

/// Relapse events for quit habits (schema v6). One per day: presence of a row
/// means the user broke the clean streak on that local calendar day. Absence
/// of a row means the day was clean — no check-in required.
class HabitRelapses extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get uuid => text().unique().clientDefault(syncUuid.v4)();

  IntColumn get updatedAt => integer()
      .map(const UtcMillisConverter())
      .clientDefault(() => DateTime.now().toUtc().millisecondsSinceEpoch)();

  IntColumn get habitId =>
      integer().references(Habits, #id, onDelete: KeyAction.cascade)();

  /// Parent habit uuid (schema v3) — survives merges that remap local ids.
  TextColumn get habitUuid => text()();

  /// Local calendar day of the relapse (`yyyy-MM-dd`).
  TextColumn get date => text().withLength(min: 10, max: 10)();

  TextColumn get note => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {habitId, date},
  ];
}

/// Planned vacation ranges (schema v6, scoped in v7). [allHabits] is true for
/// v6 rows and means "pause everything"; when false the [VacationScopes] rows
/// decide which habits are paused. Ranges are inclusive local day strings.
class VacationPeriods extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get uuid => text().unique().clientDefault(syncUuid.v4)();

  IntColumn get updatedAt => integer()
      .map(const UtcMillisConverter())
      .clientDefault(() => DateTime.now().toUtc().millisecondsSinceEpoch)();

  TextColumn get startDate => text().withLength(min: 10, max: 10)();

  TextColumn get endDate => text().withLength(min: 10, max: 10)();

  /// Pause all habits. Defaults true so v6 rows keep their meaning.
  BoolColumn get allHabits => boolean().withDefault(const Constant(true))();
}

/// A routine/habit target of a scoped vacation period (schema v7). All
/// identities are uuids so merges need no local-id remapping.
class VacationScopes extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get uuid => text().unique().clientDefault(syncUuid.v4)();

  IntColumn get updatedAt => integer()
      .map(const UtcMillisConverter())
      .clientDefault(() => DateTime.now().toUtc().millisecondsSinceEpoch)();

  TextColumn get periodUuid => text()();

  IntColumn get targetKind => intEnum<VacationTargetKind>()();

  TextColumn get targetUuid => text()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {periodUuid, targetKind, targetUuid},
  ];
}

/// Deletion markers for sync (schema v3). When a row is deleted locally its
/// uuid is recorded here so other devices drop it on merge instead of
/// resurrecting it. Never pruned — history must not come back.
class Tombstones extends Table {
  /// The uuid of the deleted row.
  TextColumn get uuid => text()();

  /// Source table name (`tasks`, `habit_checkins`, …).
  TextColumn get sourceTable => text()();

  /// When the delete happened (UTC millis). LWW against surviving row copies.
  IntColumn get deletedAt => integer().map(const UtcMillisConverter())();

  /// The device that performed the delete (deterministic tiebreak).
  TextColumn get deviceId => text()();

  @override
  Set<Column> get primaryKey => {uuid};
}
