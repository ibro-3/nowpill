import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/search.dart';

/// Pure search matcher: case/diacritic-insensitive substring matching.
void main() {
  group('normalizeForSearch', () {
    test('lowercases', () {
      expect(normalizeForSearch('Hello WORLD'), 'hello world');
    });

    test('strips Spanish accents', () {
      expect(normalizeForSearch('mañana'), 'manana');
      expect(normalizeForSearch('Miércoles'), 'miercoles');
      expect(normalizeForSearch('pingüino'), 'pinguino');
      expect(normalizeForSearch('AÑOS'), 'anos');
    });

    test('strips other diacritics', () {
      expect(normalizeForSearch('café résumé naïve'), 'cafe resume naive');
    });

    test('keeps punctuation and digits', () {
      expect(normalizeForSearch('PR-5: fix!'), 'pr-5: fix!');
    });
  });

  group('searchMatches', () {
    test('case-insensitive substring', () {
      expect(searchMatches('GROC', 'Buy groceries'), isTrue);
      expect(searchMatches('dentist', 'Call the Dentist'), isTrue);
    });

    test('accent-insensitive both directions', () {
      expect(searchMatches('manana', 'Llamar mañana'), isTrue);
      expect(searchMatches('mañana', 'Llamar manana'), isTrue);
      expect(searchMatches('miercoles', 'Yoga el miércoles'), isTrue);
    });

    test('empty/whitespace query matches nothing', () {
      expect(searchMatches('', 'anything'), isFalse);
      expect(searchMatches('   ', 'anything'), isFalse);
    });

    test('non-match', () {
      expect(searchMatches('xyz', 'Buy groceries'), isFalse);
    });

    test('query is trimmed', () {
      expect(searchMatches('  milk  ', 'Buy milk'), isTrue);
    });
  });

  group('searchMatchesAny', () {
    test('matches any non-null text', () {
      expect(
        searchMatchesAny('plants', ['Buy milk', null, 'Water plants']),
        isTrue,
      );
    });

    test('all null / no match', () {
      expect(searchMatchesAny('x', [null, null]), isFalse);
      expect(searchMatchesAny('x', ['a', 'b']), isFalse);
    });
  });
}
