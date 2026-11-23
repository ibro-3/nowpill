import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/data/repositories/habit_repository.dart';
import 'package:nowpill/data/repositories/task_repository.dart';
import 'package:nowpill/data/widget/widget_bridge_service.dart';
import 'package:nowpill/data/widget/widget_snapshot.dart';
import 'package:nowpill/data/widget/widget_snapshot_controller.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/features/today/today_view_model.dart';

import 'test_database.dart';

/// Records bridge pushes instead of touching a platform channel.
class RecordingBridge extends WidgetBridgeService {
  RecordingBridge() : super();

  final List<WidgetSnapshot> pushed = [];
  bool isSupported = true;

  @override
  bool get supported => isSupported;

  @override
  Future<bool> update(WidgetSnapshot snapshot) async {
    pushed.add(snapshot);
    return true;
  }
}

void main() {
  group('buildWidgetSnapshot', () {
    test('summarizes progress and picks the top streak', () {
      const vm = TodayViewModel(
        overdueTasks: [],
        dueTodayTasks: [],
        completedTodayTasks: [],
        habits: [],
      );
      final snap = buildWidgetSnapshot(
        vm: vm,
        streaksByHabitName: {'Read': 4, 'Run': 9, 'Walk': 2},
        dateKey: '2026-11-23',
        now: DateTime.utc(2026, 11, 23, 8),
      );
      expect(snap.topStreak, 9);
      expect(snap.topHabitName, 'Run');
      expect(snap.dateKey, '2026-11-23');
      expect(snap.total, 0);
      expect(snap.allDone, isFalse);
    });

    test('empty streak map yields zero headline', () {
      final snap = buildWidgetSnapshot(
        vm: TodayViewModel.empty,
        streaksByHabitName: const {},
        dateKey: '2026-11-23',
        now: DateTime.utc(2026, 11, 23),
      );
      expect(snap.topStreak, 0);
      expect(snap.topHabitName, '');
    });

    test('toJson carries every field', () {
      const snap = WidgetSnapshot(
        done: 2,
        total: 3,
        remaining: 1,
        allDone: false,
        topStreak: 5,
        topHabitName: 'Read',
        dateKey: '2026-11-23',
        updatedAtMillis: 123,
      );
      final json = snap.toJson();
      expect(json['done'], 2);
      expect(json['total'], 3);
      expect(json['remaining'], 1);
      expect(json['topStreak'], 5);
      expect(json['topHabitName'], 'Read');
      expect(json['dateKey'], '2026-11-23');
    });
  });

  group('WidgetBridgeService', () {
    test('unsupported platform is a guarded no-op', () async {
      final bridge = WidgetBridgeService(
        channel: const MethodChannel('test/none'),
      );
      // In the test environment defaultTargetPlatform is android, so force a
      // no-handler channel: the call must not throw.
      final ok = await bridge.update(WidgetSnapshot.empty);
      expect(ok, isFalse); // no handler registered -> swallowed
    });
  });

  group('WidgetSnapshotController', () {
    late AppDatabase db;
    late RecordingBridge bridge;
    late WidgetSnapshotController controller;
    final now = DateTime(2026, 11, 23, 8);

    setUp(() {
      db = createTestDatabase();
      bridge = RecordingBridge();
      controller = WidgetSnapshotController(
        habits: HabitRepository(db),
        tasks: TaskRepository(db),
        bridge: bridge,
        clock: () => now,
      );
    });

    tearDown(() async {
      await controller.dispose();
      await db.close();
    });

    test('reflects today progress and top streak', () async {
      final habits = HabitRepository(db);
      final tasks = TaskRepository(db);
      final id = await habits.create(name: 'Read', color: 0xFF2DD4A8);
      await habits.update(
        (await habits.getById(
          id,
        ))!.copyWith(createdAt: now.subtract(const Duration(days: 12)).toUtc()),
      );
      // 5-day streak ending today.
      for (var i = 4; i >= 0; i--) {
        await habits.checkIn(id, formatDate(now.subtract(Duration(days: i))));
      }
      await tasks.create(
        title: 'Inbox zero',
        dueAt: DateTime(now.year, now.month, now.day),
      );

      await controller.refresh();

      expect(bridge.pushed, hasLength(1));
      final snap = bridge.pushed.single;
      expect(snap.total, 2); // 1 habit + 1 task
      expect(snap.done, 1); // habit checked
      expect(snap.remaining, 1);
      expect(snap.topStreak, 5);
      expect(snap.topHabitName, 'Read');
      expect(snap.dateKey, formatDate(now));
    });

    test('reacts to a check-in via the stream', () async {
      final habits = HabitRepository(db);
      final id = await habits.create(name: 'Read', color: 0xFF2DD4A8);
      controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(bridge.pushed.last.done, 0);

      await habits.checkIn(id, formatDate(now));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(bridge.pushed.last.done, 1);
      expect(bridge.pushed.last.allDone, isTrue);
    });

    test('archived habits are excluded', () async {
      final habits = HabitRepository(db);
      final id = await habits.create(name: 'Read', color: 0xFF2DD4A8);
      await habits.archive(id);
      await controller.refresh();
      expect(bridge.pushed.single.total, 0);
      expect(bridge.pushed.single.topStreak, 0);
    });
  });
}
