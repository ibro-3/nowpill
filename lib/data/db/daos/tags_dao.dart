import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'tags_dao.g.dart';

/// Data access for tags.
@DriftAccessor(tables: [Tags, TaskTags])
class TagsDao extends DatabaseAccessor<AppDatabase> with _$TagsDaoMixin {
  TagsDao(super.db);

  Stream<List<Tag>> watchAllTags() {
    return (select(
      tags,
    )..orderBy([(t) => OrderingTerm(expression: t.name)])).watch();
  }

  Future<List<Tag>> getAllTags() => select(tags).get();

  Future<Tag?> getTag(int id) {
    return (select(tags)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertTag(TagsCompanion entry) => into(tags).insert(entry);

  Future<bool> updateTag(Tag entry) => update(tags).replace(entry);

  Future<int> deleteTag(int id) {
    return (delete(tags)..where((t) => t.id.equals(id))).go();
  }

  /// Tags attached to a task (joined through task_tags).
  Stream<List<Tag>> watchTagsForTask(int taskId) {
    final query =
        select(tags)
            .join([innerJoin(taskTags, taskTags.tagId.equalsExp(tags.id))])
          ..where(taskTags.taskId.equals(taskId))
          ..orderBy([OrderingTerm(expression: tags.name)]);
    return query.map((row) => row.readTable(tags)).watch();
  }
}
