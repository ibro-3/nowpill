import '../db/app_database.dart';
import '../db/daos/tags_dao.dart';

/// Feature-level API for tags.
class TagRepository {
  TagRepository(this._db);

  final AppDatabase _db;

  TagsDao get _tags => _db.tagsDao;

  Stream<List<Tag>> watchAll() => _tags.watchAllTags();

  Future<List<Tag>> getAll() => _tags.getAllTags();

  Future<Tag?> getById(int id) => _tags.getTag(id);

  Future<int> create({required String name, required int color}) {
    return _tags.insertTag(TagsCompanion.insert(name: name, color: color));
  }

  Future<bool> update(Tag tag) => _tags.updateTag(tag);

  Future<int> delete(int id) => _tags.deleteTag(id);
}
