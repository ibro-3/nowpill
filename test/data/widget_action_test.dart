import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/widget/widget_action_handler.dart';
import 'package:nowpill/domain/date_utils.dart';

import 'test_database.dart';

/// Widget check-in action path: payload parsing and the repository apply
/// (sync-stamped, measurable goals completed, fresh snapshot returned).
void main() {
  group('parseWidgetActionPayload', () {
    test('valid check payload', () {
      final p = parseWidgetActionPayload('check:42');
      expect(p, isNotNull);
      expect(p!.action, kWidgetActionCheck);
      expect(p.habitId, 42);
    });

    test('malformed payloads are rejected', () {
      for (final s in [
        null,
        '',
        'check',
        'check:',
        'check:abc',
        'open',
        'check:1:2',
        'done:1',
      ]) {
        expect(parseWidgetActionPayload(s), isNull, reason: '$s');
      }
    });
  });

  group('applyWidgetCheckIn', () {
    late AppDatabase db;
    late HabitRepository habits;

    setUp(() {
      db = createTestDatabase();
      habits = HabitRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('checks in today and returns a fresh snapshot', () async {
      final id = await habits.create(name: 'Read', color: 0xFF2DD4A8);
      final snapshot = await applyWidgetCheckIn(db, id);
      expect(snapshot, isNotNull);
      final checkins = await habits.getCheckins(id);
      expect(checkins.single.date, formatDate(DateTime.now()));
      expect(snapshot!.done, 1);
      expect(snapshot.total, 1);
      expect(snapshot.habits.single.done, isTrue);
      expect(snapshot.nextUndoneHabit, isNull);
    });

    test('measurable habit completes the whole goal', () async {
      final id = await habits.create(
        name: 'Water',
        color: 0xFF5B8DEF,
        targetAmount: 8,
      );
      await habits.checkIn(id, formatDate(DateTime.now()), amount: 3);
      final snapshot = await applyWidgetCheckIn(db, id);
      final checkins = await habits.getCheckins(id);
      expect(checkins.single.amount, 8);
      expect(snapshot!.habits.single.done, isTrue);
    });

    test('classic check-in is idempotent', () async {
      final id = await habits.create(name: 'Read', color: 0xFF2DD4A8);
      await applyWidgetCheckIn(db, id);
      await applyWidgetCheckIn(db, id);
      expect(await habits.getCheckins(id), hasLength(1));
    });

    test('missing or archived habit is a guarded no-op', () async {
      expect(await applyWidgetCheckIn(db, 999), isNull);
      final id = await habits.create(name: 'Read', color: 0xFF2DD4A8);
      await habits.archive(id);
      expect(await applyWidgetCheckIn(db, id), isNull);
      expect(await habits.getCheckins(id), isEmpty);
    });

    test('updatedAt is stamped so sync picks the write up', () async {
      final id = await habits.create(name: 'Read', color: 0xFF2DD4A8);
      final before = DateTime.now().toUtc().millisecondsSinceEpoch;
      await applyWidgetCheckIn(db, id);
      final checkins = await habits.getCheckins(id);
      expect(
        checkins.single.updatedAt.millisecondsSinceEpoch,
        greaterThanOrEqualTo(before - 1000),
      );
    });
  });
}
