import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/date_utils.dart';

void main() {
  group('formatDate / parseDate', () {
    test('formats with zero padding', () {
      expect(formatDate(DateTime(2026, 1, 5)), '2026-01-05');
      expect(formatDate(DateTime(2026, 11, 22)), '2026-11-22');
    });

    test('round-trips', () {
      final day = DateTime(2026, 11, 22);
      expect(parseDate(formatDate(day)), day);
    });

    test('parseDate rejects overflow', () {
      expect(() => parseDate('2026-02-30'), throwsFormatException);
      expect(() => parseDate('2026-13-01'), throwsFormatException);
    });

    test('parseDate rejects malformed strings', () {
      expect(() => parseDate('2026-11'), throwsFormatException);
      expect(() => parseDate('not-a-date'), throwsFormatException);
    });
  });

  group('day arithmetic', () {
    test('nextDay crosses month boundary', () {
      expect(nextDay(DateTime(2026, 1, 31)), DateTime(2026, 2, 1));
    });

    test('nextDay crosses year boundary', () {
      expect(nextDay(DateTime(2026, 12, 31)), DateTime(2027, 1, 1));
    });

    test('previousDay crosses month boundary', () {
      expect(previousDay(DateTime(2026, 3, 1)), DateTime(2026, 2, 28));
    });

    test('daysBetween ignores time of day', () {
      final a = DateTime(2026, 11, 22, 23, 59);
      final b = DateTime(2026, 11, 23, 0, 1);
      expect(daysBetween(a, b), 1);
      expect(daysBetween(b, a), -1);
      expect(daysBetween(a, a), 0);
    });
  });

  group('startOfWeek', () {
    test('Monday is its own week start', () {
      // 2026-11-23 is a Monday.
      final monday = DateTime(2026, 11, 23);
      expect(monday.weekday, DateTime.monday);
      expect(startOfWeek(monday), monday);
    });

    test('Sunday maps back to Monday', () {
      // 2026-11-22 is a Sunday.
      final sunday = DateTime(2026, 11, 22);
      expect(sunday.weekday, DateTime.sunday);
      expect(startOfWeek(sunday), DateTime(2026, 11, 16));
    });
  });

  group('daysInMonth', () {
    test('February in a common year', () {
      expect(daysInMonth(2026, 2), 28);
    });

    test('February in a leap year', () {
      expect(daysInMonth(2028, 2), 29);
    });

    test('31-day month', () {
      expect(daysInMonth(2026, 1), 31);
    });

    test('30-day month', () {
      expect(daysInMonth(2026, 4), 30);
    });
  });
}
