import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/domain/enums.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late HabitRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = HabitRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('HabitRepository CRUD', () {
    test('create and read a daily habit', () async {
      final id = await repo.create(
        name: 'Meditate',
        color: 0xFF2DD4A8,
        notes: '10 minutes',
      );
      final habit = await repo.getById(id);
      expect(habit, isNotNull);
      expect(habit!.name, 'Meditate');
      expect(habit.scheduleType, HabitScheduleType.daily);
      expect(habit.archivedAt, isNull);
    });

    test('create a weekdays habit stores the weekday list', () async {
      final id = await repo.create(
        name: 'Gym',
        color: 0xFFFF6B5E,
        scheduleType: HabitScheduleType.weekdays,
        weekdays: [1, 3, 5],
      );
      final habit = await repo.getById(id);
      expect(habit!.weekdays, [1, 3, 5]);
    });

    test('create a weekly-target habit', () async {
      final id = await repo.create(
        name: 'Read',
        color: 0xFFFFB454,
        scheduleType: HabitScheduleType.weeklyTarget,
        targetPerWeek: 3,
      );
      final habit = await repo.getById(id);
      expect(habit!.targetPerWeek, 3);
    });

    test('archive hides from active but keeps history', () async {
      final id = await repo.create(name: 'Archive me', color: 0xFF000000);
      await repo.checkIn(id, '2026-11-22');
      await repo.archive(id, at: DateTime.utc(2026, 11, 22));

      final active = await repo.watchActive().first;
      expect(active, isEmpty);

      final all = await repo.watchAll().first;
      expect(all.length, 1);
      expect(all.single.archivedAt, isNotNull);

      final checkins = await repo.getCheckins(id);
      expect(checkins.length, 1);
    });

    test('unarchive restores to active', () async {
      final id = await repo.create(name: 'Restore me', color: 0xFF000000);
      await repo.archive(id);
      await repo.unarchive(id);
      final active = await repo.watchActive().first;
      expect(active.length, 1);
    });

    test('hard delete cascades to checkins', () async {
      final id = await repo.create(name: 'Delete me', color: 0xFF000000);
      await repo.checkIn(id, '2026-11-22');
      await repo.delete(id);
      final checkins = await db.select(db.habitCheckins).get();
      expect(checkins, isEmpty);
    });
  });

  group('check-ins', () {
    test('check-in is idempotent per habit+date', () async {
      final id = await repo.create(name: 'Once a day', color: 0xFF000000);
      final first = await repo.checkIn(id, '2026-11-22');
      final second = await repo.checkIn(id, '2026-11-22');
      expect(first, greaterThan(0));
      expect(second, -1);
      final checkins = await repo.getCheckins(id);
      expect(checkins.length, 1);
    });

    test('different dates create separate checkins', () async {
      final id = await repo.create(name: 'Daily', color: 0xFF000000);
      await repo.checkIn(id, '2026-11-21');
      await repo.checkIn(id, '2026-11-22');
      final checkins = await repo.getCheckins(id);
      expect(checkins.length, 2);
      expect(checkins.map((c) => c.date), ['2026-11-21', '2026-11-22']);
    });

    test('removeCheckIn deletes a specific day', () async {
      final id = await repo.create(name: 'Backfill', color: 0xFF000000);
      await repo.checkIn(id, '2026-11-21');
      await repo.checkIn(id, '2026-11-22');
      final removed = await repo.removeCheckIn(id, '2026-11-21');
      expect(removed, 1);
      final checkins = await repo.getCheckins(id);
      expect(checkins.single.date, '2026-11-22');
    });

    test('getCheckinsInRange filters inclusively', () async {
      final id = await repo.create(name: 'Range', color: 0xFF000000);
      await repo.checkIn(id, '2026-11-20');
      await repo.checkIn(id, '2026-11-21');
      await repo.checkIn(id, '2026-11-22');
      await repo.checkIn(id, '2026-11-23');
      final range = await repo.getCheckinsInRange(
        id,
        '2026-11-21',
        '2026-11-22',
      );
      expect(range.map((c) => c.date), ['2026-11-21', '2026-11-22']);
    });

    test('checkins stream emits on insert', () async {
      final id = await repo.create(name: 'Streamed', color: 0xFF000000);
      final emissions = <List<HabitCheckin>>[];
      final sub = repo.watchCheckins(id).listen(emissions.add);
      await pumpEventQueue();

      await repo.checkIn(id, '2026-11-22');
      await pumpEventQueue();
      expect(emissions.last.length, 1);

      await sub.cancel();
    });
  });
}
