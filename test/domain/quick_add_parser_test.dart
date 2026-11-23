import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/quick_add_parser.dart';

/// Natural-language quick-add phrase matrix (EN + ES). The parser is pure and
/// clock-injected: `now` is Monday 2026-11-23 08:00 local throughout.
void main() {
  final now = DateTime(2026, 11, 23, 8); // Monday
  QuickAddParse parse(String s) => parseQuickAdd(s, now: now);

  group('plain text', () {
    test('unrecognized text is kept verbatim', () {
      final r = parse('Buy groceries');
      expect(r.title, 'Buy groceries');
      expect(r.hasMetadata, isFalse);
      expect(r.dueDay, isNull);
    });

    test('empty input', () {
      expect(parse('   ').title, '');
      expect(parse('').hasMetadata, isFalse);
    });

    test('dueAtOrDefault falls back to the given day at 23:59', () {
      final r = parse('Buy milk');
      final fallback = DateTime(2026, 11, 23);
      expect(r.dueAtOrDefault(fallback), DateTime(2026, 11, 23, 23, 59));
    });

    test('words that merely contain keywords are not parsed', () {
      final r = parse('Read the mayan calendar history');
      expect(r.title, 'Read the mayan calendar history');
      expect(r.dueDay, isNull);
    });
  });

  group('relative days', () {
    test('today / hoy', () {
      expect(parse('Stretch today').dueDay, DateTime(2026, 11, 23));
      expect(parse('Estirar hoy').dueDay, DateTime(2026, 11, 23));
      expect(parse('Stretch today').title, 'Stretch');
    });

    test('tomorrow / mañana', () {
      expect(parse('Call mom tomorrow').dueDay, DateTime(2026, 11, 24));
      expect(parse('Llamar a mamá mañana').dueDay, DateTime(2026, 11, 24));
      expect(parse('Llamar a mamá mañana').title, 'Llamar a mamá');
    });

    test('day after tomorrow / pasado mañana', () {
      expect(
        parse('Ship it day after tomorrow').dueDay,
        DateTime(2026, 11, 25),
      );
      expect(parse('Enviar pasado mañana').dueDay, DateTime(2026, 11, 25));
    });

    test('in N days / en N días', () {
      expect(parse('Renew passport in 3 days').dueDay, DateTime(2026, 11, 26));
      expect(
        parse('Renovar pasaporte en 10 días').dueDay,
        DateTime(2026, 12, 3),
      );
    });

    test('in 2 weeks / en 2 semanas', () {
      expect(parse('Dentist in 2 weeks').dueDay, DateTime(2026, 12, 7));
      expect(parse('Dentista en 2 semanas').dueDay, DateTime(2026, 12, 7));
    });

    test('next week → next Monday', () {
      expect(parse('Plan sprint next week').dueDay, DateTime(2026, 11, 30));
      expect(parse('Planear la próxima semana').dueDay, DateTime(2026, 11, 30));
    });

    test('next month → 1st of next month', () {
      expect(parse('Pay rent next month').dueDay, DateTime(2026, 12, 1));
    });
  });

  group('weekdays', () {
    test('bare weekday → next occurrence (Friday from Monday)', () {
      final r = parse('Water plants friday');
      expect(r.dueDay, DateTime(2026, 11, 27));
      expect(r.title, 'Water plants');
    });

    test('same weekday without next → today', () {
      expect(parse('Standup monday').dueDay, DateTime(2026, 11, 23));
    });

    test('next + same weekday → +7', () {
      expect(parse('Standup next monday').dueDay, DateTime(2026, 11, 30));
    });

    test('on friday / el viernes', () {
      expect(parse('Deploy on friday').dueDay, DateTime(2026, 11, 27));
      expect(parse('Desplegar el viernes').dueDay, DateTime(2026, 11, 27));
    });

    test('Spanish accented weekdays', () {
      expect(parse('Yoga el miércoles').dueDay, DateTime(2026, 11, 25));
      expect(parse('Fútbol el sábado').dueDay, DateTime(2026, 11, 28));
    });
  });

  group('calendar dates', () {
    test('month name + day (Nov 30)', () {
      final r = parse('File taxes Nov 30');
      expect(r.dueDay, DateTime(2026, 11, 30));
      expect(r.title, 'File taxes');
    });

    test('day + month name (30 nov / 30 de noviembre)', () {
      expect(parse('File taxes 30 nov').dueDay, DateTime(2026, 11, 30));
      expect(
        parse('Pagar impuestos 30 de noviembre').dueDay,
        DateTime(2026, 11, 30),
      );
    });

    test('past month/day rolls to next year', () {
      expect(parse('Anniversary Jan 5').dueDay, DateTime(2027, 1, 5));
    });

    test('ISO date', () {
      expect(parse('Conference 2026-12-01').dueDay, DateTime(2026, 12, 1));
    });

    test('numeric month/day', () {
      expect(parse('Submit report 12/01').dueDay, DateTime(2026, 12, 1));
      expect(parse('Submit report 12-01').dueDay, DateTime(2026, 12, 1));
    });

    test('invalid dates are left as text', () {
      final r = parse('Party 31/02');
      expect(r.dueDay, isNull);
      expect(r.title, 'Party 31/02');
    });
  });

  group('time', () {
    test('at 5pm with a day', () {
      final r = parse('Call dentist tomorrow at 5pm');
      expect(r.dueDay, DateTime(2026, 11, 24));
      expect(r.reminderMinutes, 17 * 60);
      expect(r.reminderAt, DateTime(2026, 11, 24, 17));
      expect(r.dueAtOrDefault(now), DateTime(2026, 11, 24, 17));
      expect(r.title, 'Call dentist');
    });

    test('at 17:30 (24h)', () {
      final r = parse('Review PR tomorrow at 17:30');
      expect(r.reminderMinutes, 17 * 60 + 30);
    });

    test('at 9am', () {
      expect(parse('Standup tomorrow at 9am').reminderMinutes, 9 * 60);
    });

    test('12am → midnight, 12pm → noon', () {
      expect(parse('Reset tomorrow at 12am').reminderMinutes, 0);
      expect(parse('Lunch tomorrow at 12pm').reminderMinutes, 12 * 60);
    });

    test('a las 17h (ES)', () {
      final r = parse('Llamar mañana a las 17h');
      expect(r.reminderMinutes, 17 * 60);
      expect(r.title, 'Llamar');
    });

    test('time only, later today → today', () {
      final r = parse('Meditate at 9pm');
      expect(r.dueDay, DateTime(2026, 11, 23));
      expect(r.reminderAt, DateTime(2026, 11, 23, 21));
    });

    test('time only, already past → tomorrow', () {
      final r = parse('Meditate at 7am'); // now is 08:00
      expect(r.dueDay, DateTime(2026, 11, 24));
    });
  });

  group('recurrence', () {
    test('every day / daily / diario', () {
      for (final s in ['Walk every day', 'Walk daily', 'Caminar diario']) {
        final r = parse(s);
        expect(r.recurrence?.unit, RecurrenceUnit.day, reason: s);
        expect(r.recurrence?.interval, 1, reason: s);
        expect(r.title, anyOf('Walk', 'Caminar'), reason: s);
      }
    });

    test('weekly / cada semana', () {
      expect(parse('Clean weekly').recurrence?.unit, RecurrenceUnit.week);
      expect(
        parse('Limpiar cada semana').recurrence?.unit,
        RecurrenceUnit.week,
      );
    });

    test('monthly / mensual', () {
      expect(parse('Backup monthly').recurrence?.unit, RecurrenceUnit.month);
      expect(parse('Respaldo mensual').recurrence?.unit, RecurrenceUnit.month);
    });

    test('every 2 weeks', () {
      final r = parse('Water plants every 2 weeks');
      expect(r.recurrence?.unit, RecurrenceUnit.week);
      expect(r.recurrence?.interval, 2);
    });

    test('cada 3 días', () {
      final r = parse('Regar cada 3 días');
      expect(r.recurrence?.unit, RecurrenceUnit.day);
      expect(r.recurrence?.interval, 3);
    });

    test('every monday → weekly, first occurrence that weekday', () {
      final r = parse('Team sync every monday');
      expect(r.recurrence?.unit, RecurrenceUnit.week);
      expect(r.dueDay, DateTime(2026, 11, 23)); // today is Monday
      final fri = parse('Retro every friday');
      expect(fri.dueDay, DateTime(2026, 11, 27));
    });

    test('cada lunes', () {
      final r = parse('Sincronizar cada lunes');
      expect(r.recurrence?.unit, RecurrenceUnit.week);
      expect(r.dueDay, DateTime(2026, 11, 23));
    });

    test('recurrence without a day starts today', () {
      expect(parse('Journal daily').dueDay, DateTime(2026, 11, 23));
    });
  });

  group('tags + priority', () {
    test('#tags extracted in order, deduped', () {
      final r = parse('Buy groceries #home #errands #home');
      expect(r.tags, ['home', 'errands']);
      expect(r.title, 'Buy groceries');
    });

    test('!high / !med / !low', () {
      expect(parse('Ship release !high').priority, TaskPriority.high);
      expect(parse('Tidy desk !low').priority, TaskPriority.low);
      expect(parse('Review !med').priority, TaskPriority.medium);
    });

    test('ES priorities', () {
      expect(parse('Enviar !alta').priority, TaskPriority.high);
      expect(parse('Ordenar !baja').priority, TaskPriority.low);
    });

    test('unknown !token stays in the title', () {
      final r = parse('Wow! !urgent');
      expect(r.priority, TaskPriority.none);
      expect(r.title, 'Wow! !urgent');
    });

    test('bare # stays in the title', () {
      expect(parse('Issue # 5').title, 'Issue # 5');
    });
  });

  group('combined phrases', () {
    test('everything at once', () {
      final r = parse('Call dentist tomorrow at 5pm #health !high');
      expect(r.title, 'Call dentist');
      expect(r.dueDay, DateTime(2026, 11, 24));
      expect(r.reminderMinutes, 17 * 60);
      expect(r.tags, ['health']);
      expect(r.priority, TaskPriority.high);
    });

    test('ES combined', () {
      final r = parse('Llamar al dentista mañana a las 9am #salud !alta');
      expect(r.title, 'Llamar al dentista');
      expect(r.dueDay, DateTime(2026, 11, 24));
      expect(r.reminderMinutes, 9 * 60);
      expect(r.tags, ['salud']);
      expect(r.priority, TaskPriority.high);
    });

    test('recurrence + tag + time', () {
      final r = parse('Standup daily at 9:30 #work');
      expect(r.title, 'Standup');
      expect(r.recurrence?.unit, RecurrenceUnit.day);
      expect(r.reminderMinutes, 9 * 60 + 30);
      expect(r.tags, ['work']);
      expect(r.dueDay, DateTime(2026, 11, 23));
    });

    test('whitespace collapses after token removal', () {
      final r = parse('  Buy   milk   tomorrow   #home  ');
      expect(r.title, 'Buy milk');
    });
  });
}
