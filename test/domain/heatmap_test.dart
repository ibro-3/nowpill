import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/date_utils.dart';
import 'package:nowpill/domain/habit_schedule.dart';
import 'package:nowpill/domain/heatmap.dart';

/// Pure heatmap aggregation: day-state rules shared by month/year grids, and
/// the 53-week trailing-year layout.
void main() {
  final today = DateTime(2026, 11, 23); // Monday
  final start = DateTime(2026, 1, 1);
  const daily = HabitSchedule.daily();

  HeatmapDayState stateFor(
    DateTime day, {
    Set<String> checkins = const {},
    Set<String> frozen = const {},
    double? target,
    Map<String, double> amounts = const {},
    HabitSchedule schedule = daily,
    DateTime? startDate,
  }) {
    return heatmapDayState(
      day: day,
      today: today,
      startDate: startDate ?? start,
      schedule: schedule,
      checkins: checkins,
      frozenDates: frozen,
      targetAmount: target,
      amounts: amounts,
    );
  }

  group('heatmapDayState', () {
    test('future and pre-lifetime are inactive', () {
      expect(stateFor(DateTime(2026, 11, 24)), HeatmapDayState.inactive);
      expect(stateFor(DateTime(2025, 12, 31)), HeatmapDayState.inactive);
    });

    test('checked day is done; partial measurable is partial', () {
      const key = '2026-11-20';
      expect(
        stateFor(DateTime(2026, 11, 20), checkins: {key}),
        HeatmapDayState.done,
      );
      expect(
        stateFor(
          DateTime(2026, 11, 20),
          checkins: {key},
          target: 8,
          amounts: {key: 3},
        ),
        HeatmapDayState.partial,
      );
      expect(
        stateFor(
          DateTime(2026, 11, 20),
          checkins: {key},
          target: 8,
          amounts: {key: 8},
        ),
        HeatmapDayState.done,
      );
    });

    test('frozen day', () {
      expect(
        stateFor(DateTime(2026, 11, 20), frozen: {'2026-11-20'}),
        HeatmapDayState.frozen,
      );
    });

    test('weekly-target freeze covers the whole week', () {
      const weekly = HabitSchedule.weeklyTarget(3);
      // 2026-11-16 is the Monday of that week.
      expect(
        stateFor(
          DateTime(2026, 11, 18),
          frozen: {'2026-11-16'},
          schedule: weekly,
        ),
        HeatmapDayState.frozen,
      );
    });

    test('today unchecked is todayPending', () {
      expect(stateFor(today), HeatmapDayState.todayPending);
    });

    test('missed vs unscheduled', () {
      expect(stateFor(DateTime(2026, 11, 20)), HeatmapDayState.missed);
      const mwf = HabitSchedule.weekdays([1, 3, 5]);
      expect(
        stateFor(DateTime(2026, 11, 21), schedule: mwf), // Saturday
        HeatmapDayState.unscheduled,
      );
    });

    test('weekly-target unchecked days are neutral, never missed', () {
      const weekly = HabitSchedule.weeklyTarget(3);
      expect(
        stateFor(DateTime(2026, 11, 20), schedule: weekly),
        HeatmapDayState.unscheduled,
      );
    });
  });

  group('yearHeatmapWeeks', () {
    test('53 Monday-start columns ending with the current week', () {
      final weeks = yearHeatmapWeeks(
        today: today,
        startDate: start,
        schedule: daily,
        checkins: const {},
        frozenDates: const {},
      );
      expect(weeks, hasLength(53));
      expect(weeks.last.monday, startOfWeek(today));
      expect(
        weeks.first.monday,
        startOfWeek(today).subtract(const Duration(days: 52 * 7)),
      );
      for (final w in weeks) {
        expect(w.monday.weekday, DateTime.monday);
        expect(w.states, hasLength(7));
      }
    });

    test('states match the shared day rules', () {
      final weeks = yearHeatmapWeeks(
        today: today,
        startDate: start,
        schedule: daily,
        checkins: {'2026-11-20'},
        frozenDates: {'2026-11-10'},
      );
      // Find 2026-11-20 (Friday of last week) and 2026-11-10.
      HeatmapDayState? stateOf(String key) {
        for (final w in weeks) {
          for (var d = 0; d < 7; d++) {
            if (formatDate(w.monday.add(Duration(days: d))) == key) {
              return w.states[d];
            }
          }
        }
        return null;
      }

      expect(stateOf('2026-11-20'), HeatmapDayState.done);
      expect(stateOf('2026-11-10'), HeatmapDayState.frozen);
      expect(stateOf('2026-11-23'), HeatmapDayState.todayPending);
      expect(stateOf('2026-11-24'), HeatmapDayState.inactive); // future
      expect(stateOf('2025-11-25'), HeatmapDayState.inactive); // pre-lifetime
    });

    test('mid-week today: trailing days of the last column are inactive', () {
      final wednesday = DateTime(2026, 11, 25);
      final weeks = yearHeatmapWeeks(
        today: wednesday,
        startDate: start,
        schedule: daily,
        checkins: const {},
        frozenDates: const {},
      );
      final last = weeks.last;
      expect(last.states[0], HeatmapDayState.missed); // Monday passed
      expect(last.states[2], HeatmapDayState.todayPending); // Wednesday
      expect(last.states[3], HeatmapDayState.inactive); // Thursday future
    });
  });
}
