import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/recurrence.dart';
import 'package:nowpill/domain/recurrence_rule.dart';

void main() {
  group('daily recurrence', () {
    test('every day advances one day', () {
      final anchor = DateTime(2026, 11, 22, 9, 30);
      final next = nextOccurrence(
        anchor,
        const RecurrenceRule(unit: RecurrenceUnit.day),
      );
      expect(next, DateTime(2026, 11, 23, 9, 30));
    });

    test('every 3 days', () {
      final anchor = DateTime(2026, 11, 22);
      final next = nextOccurrence(
        anchor,
        const RecurrenceRule(unit: RecurrenceUnit.day, interval: 3),
      );
      expect(next, DateTime(2026, 11, 25));
    });

    test('crosses month boundary', () {
      final anchor = DateTime(2026, 11, 30);
      final next = nextOccurrence(
        anchor,
        const RecurrenceRule(unit: RecurrenceUnit.day),
      );
      expect(next, DateTime(2026, 12, 1));
    });
  });

  group('weekly recurrence', () {
    test('every week keeps the weekday', () {
      // 2026-11-22 is a Sunday.
      final anchor = DateTime(2026, 11, 22, 8);
      final next = nextOccurrence(
        anchor,
        const RecurrenceRule(unit: RecurrenceUnit.week),
      );
      expect(next, DateTime(2026, 11, 29, 8));
      expect(next.weekday, anchor.weekday);
    });

    test('every 2 weeks', () {
      final anchor = DateTime(2026, 11, 22);
      final next = nextOccurrence(
        anchor,
        const RecurrenceRule(unit: RecurrenceUnit.week, interval: 2),
      );
      expect(next, DateTime(2026, 12, 6));
    });
  });

  group('monthly recurrence', () {
    test('same day next month', () {
      final anchor = DateTime(2026, 11, 15, 10);
      final next = nextOccurrence(
        anchor,
        const RecurrenceRule(unit: RecurrenceUnit.month),
      );
      expect(next, DateTime(2026, 12, 15, 10));
    });

    test('Jan 31 clamps to Feb 28 in a common year', () {
      final anchor = DateTime(2026, 1, 31);
      final next = nextOccurrence(
        anchor,
        const RecurrenceRule(unit: RecurrenceUnit.month),
      );
      expect(next, DateTime(2026, 2, 28));
    });

    test('Jan 31 clamps to Feb 29 in a leap year', () {
      final anchor = DateTime(2028, 1, 31);
      final next = nextOccurrence(
        anchor,
        const RecurrenceRule(unit: RecurrenceUnit.month),
      );
      expect(next, DateTime(2028, 2, 29));
    });

    test('Mar 31 clamps to Apr 30', () {
      final anchor = DateTime(2026, 3, 31);
      final next = nextOccurrence(
        anchor,
        const RecurrenceRule(unit: RecurrenceUnit.month),
      );
      expect(next, DateTime(2026, 4, 30));
    });

    test('every 3 months crosses year', () {
      final anchor = DateTime(2026, 11, 15);
      final next = nextOccurrence(
        anchor,
        const RecurrenceRule(unit: RecurrenceUnit.month, interval: 3),
      );
      expect(next, DateTime(2027, 2, 15));
    });

    test('cadence is anchored, not drifted by clamping', () {
      // Jan 31 -> Feb 28 (clamped) -> Mar 31 (back to the anchor day, not 28).
      const rule = RecurrenceRule(unit: RecurrenceUnit.month);
      final jan = DateTime(2026, 1, 31);
      final feb = nextOccurrence(jan, rule);
      final mar = nextOccurrence(
        jan,
        const RecurrenceRule(unit: RecurrenceUnit.month, interval: 2),
      );
      expect(feb, DateTime(2026, 2, 28));
      expect(mar, DateTime(2026, 3, 31));
    });
  });

  group('time preservation', () {
    test('preserves time of day across units', () {
      final anchor = DateTime(2026, 11, 22, 14, 45, 30, 500);
      for (final unit in RecurrenceUnit.values) {
        final next = nextOccurrence(anchor, RecurrenceRule(unit: unit));
        expect(next.hour, 14);
        expect(next.minute, 45);
        expect(next.second, 30);
        expect(next.millisecond, 500);
      }
    });

    test('preserves UTC flag (no timezone shift)', () {
      final anchor = DateTime.utc(2026, 11, 22, 9, 30);
      for (final unit in RecurrenceUnit.values) {
        final next = nextOccurrence(anchor, RecurrenceRule(unit: unit));
        expect(next.isUtc, isTrue);
        expect(next.hour, 9);
        expect(next.minute, 30);
      }
    });

    test('preserves local flag', () {
      final anchor = DateTime(2026, 11, 22, 9, 30);
      final next = nextOccurrence(
        anchor,
        const RecurrenceRule(unit: RecurrenceUnit.day),
      );
      expect(next.isUtc, isFalse);
      expect(next.hour, 9);
    });
  });

  group('validation', () {
    test('rejects zero interval', () {
      expect(
        () => nextOccurrence(
          DateTime(2026, 11, 22),
          const RecurrenceRule(unit: RecurrenceUnit.day, interval: 0),
        ),
        throwsArgumentError,
      );
    });

    test('rejects negative interval', () {
      expect(
        () => nextOccurrence(
          DateTime(2026, 11, 22),
          const RecurrenceRule(unit: RecurrenceUnit.week, interval: -1),
        ),
        throwsArgumentError,
      );
    });
  });
}
