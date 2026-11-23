import 'date_utils.dart';
import 'enums.dart';
import 'recurrence_rule.dart';

/// The result of parsing a natural-language quick-add phrase. Everything the
/// parser recognized is lifted out of [title]; unrecognized text stays.
///
/// Pure and clock-injected like the streak/reminder engines — no Flutter, no
/// locale lookups beyond the built-in EN/ES vocabularies.
class QuickAddParse {
  const QuickAddParse({
    required this.title,
    this.dueDay,
    this.reminderMinutes,
    this.recurrence,
    this.tags = const [],
    this.priority = TaskPriority.none,
  });

  /// The task title with all recognized tokens removed.
  final String title;

  /// Recognized calendar day (local, date-only). Null = no date phrase.
  final DateTime? dueDay;

  /// Recognized time-of-day as minutes since midnight (for the reminder).
  /// Null = no time phrase.
  final int? reminderMinutes;

  /// Recognized recurrence ("every day", "weekly", "every monday", …).
  final RecurrenceRule? recurrence;

  /// `#tag` tokens in order of appearance (deduped, case preserved).
  final List<String> tags;

  /// `!high` / `!med` / `!low` (or ES equivalents).
  final TaskPriority priority;

  /// Whether anything beyond the plain title was recognized.
  bool get hasMetadata =>
      dueDay != null ||
      reminderMinutes != null ||
      recurrence != null ||
      tags.isNotEmpty ||
      priority != TaskPriority.none;

  /// The due instant the task should be created with: the recognized day at
  /// the recognized time, or end-of-day (23:59) when only a day was given.
  /// [fallbackDay] is used when no date phrase was recognized (Today's bar
  /// passes the current day, preserving the pre-v0.4 default).
  DateTime dueAtOrDefault(DateTime fallbackDay) {
    final day = dueDay ?? fallbackDay;
    final minutes = reminderMinutes ?? 23 * 60 + 59;
    return DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
  }

  /// The reminder instant: only when an explicit time was recognized.
  DateTime? get reminderAt {
    final day = dueDay;
    final minutes = reminderMinutes;
    if (day == null || minutes == null) return null;
    return DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
  }
}

/// Weekday vocabularies (ISO 1 = Monday … 7 = Sunday), EN + ES.
const Map<String, int> _weekdays = {
  'monday': 1,
  'mon': 1,
  'lunes': 1,
  'lun': 1,
  'tuesday': 2,
  'tue': 2,
  'tues': 2,
  'martes': 2,
  'mar': 2,
  'wednesday': 3,
  'wed': 3,
  'miércoles': 3,
  'miercoles': 3,
  'mie': 3,
  'mié': 3,
  'thursday': 4,
  'thu': 4,
  'thur': 4,
  'thurs': 4,
  'jueves': 4,
  'jue': 4,
  'friday': 5,
  'fri': 5,
  'viernes': 5,
  'vie': 5,
  'saturday': 6,
  'sat': 6,
  'sábado': 6,
  'sabado': 6,
  'sab': 6,
  'sáb': 6,
  'sunday': 7,
  'sun': 7,
  'domingo': 7,
  'dom': 7,
};

/// Month vocabularies (1–12), EN + ES.
const Map<String, int> _months = {
  'january': 1,
  'jan': 1,
  'enero': 1,
  'ene': 1,
  'february': 2,
  'feb': 2,
  'febrero': 2,
  'march': 3,
  'mar': 3,
  'marzo': 3,
  'april': 4,
  'apr': 4,
  'abril': 4,
  'abr': 4,
  'may': 5,
  'mayo': 5,
  'june': 6,
  'jun': 6,
  'junio': 6,
  'july': 7,
  'jul': 7,
  'julio': 7,
  'august': 8,
  'aug': 8,
  'agosto': 8,
  'ago': 8,
  'september': 9,
  'sep': 9,
  'sept': 9,
  'septiembre': 9,
  'setiembre': 9,
  'october': 10,
  'oct': 10,
  'octubre': 10,
  'november': 11,
  'nov': 11,
  'noviembre': 11,
  'december': 12,
  'dec': 12,
  'diciembre': 12,
  'dic': 12,
};

const Map<String, TaskPriority> _priorities = {
  'high': TaskPriority.high,
  'h': TaskPriority.high,
  'alta': TaskPriority.high,
  'medium': TaskPriority.medium,
  'med': TaskPriority.medium,
  'm': TaskPriority.medium,
  'media': TaskPriority.medium,
  'low': TaskPriority.low,
  'l': TaskPriority.low,
  'baja': TaskPriority.low,
};

/// Parses a quick-add phrase. Recognized tokens (dates, times, recurrence,
/// #tags, !priority) are removed from the title; everything else is kept
/// verbatim (whitespace collapsed). Never throws; a phrase with no recognized
/// tokens returns the trimmed input unchanged.
QuickAddParse parseQuickAdd(String input, {required DateTime now}) {
  final today = DateTime(now.year, now.month, now.day);
  var text = input.trim();
  if (text.isEmpty) {
    return const QuickAddParse(title: '');
  }

  DateTime? dueDay;
  int? reminderMinutes;
  RecurrenceRule? recurrence;
  var priority = TaskPriority.none;
  final tags = <String>[];

  // --- #tags and !priority (token-level, anywhere in the phrase). ---
  final keptWords = <String>[];
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.length > 1 && word.startsWith('#')) {
      final tag = word.substring(1);
      if (!tags.contains(tag)) tags.add(tag);
      continue;
    }
    if (word.length > 1 && word.startsWith('!')) {
      final p = _priorities[word.substring(1).toLowerCase()];
      if (p != null) {
        priority = p;
        continue;
      }
    }
    keptWords.add(word);
  }
  text = keptWords.join(' ');

  // Helper: removes the first match of [pattern] (case-insensitive) and
  // reports whether it matched. Multi-word phrases are matched before their
  // single-word subsets by call order.
  String? take(RegExp pattern) {
    final m = pattern.firstMatch(text);
    if (m == null) return null;
    text = (text.substring(0, m.start) + text.substring(m.end)).trim();
    return m.group(0);
  }

  // Like [take], but restores the text when [accept] rejects the match —
  // invalid dates stay in the title instead of being silently eaten.
  String? takeIf(RegExp pattern, bool Function(String match) accept) {
    final before = text;
    final m = take(pattern);
    if (m != null && !accept(m)) {
      text = before;
      return null;
    }
    return m;
  }

  RegExp p(String s) => RegExp(s, caseSensitive: false);

  // --- Recurrence (before dates: "every monday" must not parse as a date). --
  final everyWeekday = take(
    p(
      r'\b(?:every|cada)\s+(monday|mon|tuesday|tue|tues|wednesday|wed|'
      r'thursday|thu|thur|thurs|friday|fri|saturday|sat|sunday|sun|'
      r'lunes|lun|martes|mar|mi[eé]rcoles|mie|mié|jueves|jue|viernes|vie|'
      r's[aá]bado|sab|sáb|domingo|dom)\b',
    ),
  );
  if (everyWeekday != null) {
    final name = everyWeekday.split(RegExp(r'\s+')).last.toLowerCase();
    final iso = _weekdays[name]!;
    recurrence = const RecurrenceRule(unit: RecurrenceUnit.week);
    // The first occurrence lands on the named weekday (today if it matches).
    final delta = (iso - today.weekday + 7) % 7;
    dueDay = DateTime(today.year, today.month, today.day + delta);
  } else {
    final everyN = take(
      p(
        r'\b(?:every|cada)\s+(\d+)\s*(days?|d[ií]as?|weeks?|semanas?|'
        r'months?|mes(?:es)?)\b',
      ),
    );
    if (everyN != null) {
      final m = p(r'(\d+)\s*(\w+)').firstMatch(everyN)!;
      final n = int.parse(m.group(1)!);
      recurrence = RecurrenceRule(
        unit: _unitOf(m.group(2)!),
        interval: n < 1 ? 1 : n,
      );
    } else if (take(
          p(r'\b(?:every\s*day|daily|diario|diaria|todos\s+los\s+d[ií]as)\b'),
        ) !=
        null) {
      recurrence = const RecurrenceRule(unit: RecurrenceUnit.day);
    } else if (take(p(r'\b(?:every\s*week|weekly|semanal|cada\s+semana)\b')) !=
        null) {
      recurrence = const RecurrenceRule(unit: RecurrenceUnit.week);
    } else if (take(p(r'\b(?:every\s*month|monthly|mensual|cada\s+mes)\b')) !=
        null) {
      recurrence = const RecurrenceRule(unit: RecurrenceUnit.month);
    }
  }

  // --- Explicit clock time ("at 5pm", "at 17:00", "a las 17h"). ---
  final timeMatch = take(
    p(
      r'\b(?:at|a\s+las?)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.|h)?\b',
    ),
  );
  if (timeMatch != null) {
    final m = p(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.|h)?\s*$')
        .firstMatch(timeMatch)!;
    var hour = int.parse(m.group(1)!);
    final minute = int.tryParse(m.group(2) ?? '') ?? 0;
    final suffix = (m.group(3) ?? '').toLowerCase().replaceAll('.', '');
    if (suffix == 'pm' && hour < 12) hour += 12;
    if (suffix == 'am' && hour == 12) hour = 0;
    if (hour <= 23 && minute <= 59) {
      reminderMinutes = hour * 60 + minute;
    }
  }

  // --- Relative day phrases (longest first). ---
  if (take(p(r'\b(?:day\s+after\s+tomorrow|pasado\s+ma[nñ]ana)\b')) != null) {
    dueDay = DateTime(today.year, today.month, today.day + 2);
  } else if (take(p(r'\b(?:tomorrow|ma[nñ]ana)\b')) != null) {
    dueDay = DateTime(today.year, today.month, today.day + 1);
  } else if (take(p(r'\b(?:today|hoy)\b')) != null) {
    dueDay = today;
  } else if (take(p(r'\b(?:next\s+week|la\s+pr[oó]xima\s+semana)\b')) != null) {
    dueDay = startOfWeek(today).add(const Duration(days: 7));
  } else if (take(p(r'\b(?:next\s+month|el\s+pr[oó]ximo\s+mes)\b')) != null) {
    dueDay = DateTime(today.year, today.month + 1, 1);
  } else {
    // "next friday" / "el viernes" / bare weekday → next occurrence.
    final nextWeekday = take(
      p(
        r'\b(?:next|pr[oó]ximo|pr[oó]xima|el|this|este)\s+'
        r'(monday|mon|tuesday|tue|tues|wednesday|wed|thursday|thu|thur|'
        r'thurs|friday|fri|saturday|sat|sunday|sun|lunes|lun|martes|mar|'
        r'mi[eé]rcoles|mie|mié|jueves|jue|viernes|vie|s[aá]bado|sab|sáb|'
        r'domingo|dom)\b',
      ),
    );
    var weekdayToken = nextWeekday?.split(RegExp(r'\s+')).last;
    weekdayToken ??= take(
      p(
        r'\b(?:on|el)\s+(monday|tuesday|wednesday|thursday|friday|saturday|'
        r'sunday|lunes|martes|mi[eé]rcoles|jueves|viernes|s[aá]bado|domingo)\b',
      ),
    )?.split(RegExp(r'\s+')).last;
    // Bare weekday name ("Water plants friday"). Runs after month-name dates
    // would have matched "mar"/"may" inside a date phrase — those are handled
    // below, so a bare weekday that is also a month abbreviation only parses
    // as a weekday when it is the whole trailing token.
    weekdayToken ??= take(
      p(
        r'\b(monday|mon|tuesday|tue|tues|wednesday|wed|thursday|thu|thur|'
        r'thurs|friday|fri|saturday|sat|sunday|sun|lunes|lun|martes|'
        r'mi[eé]rcoles|mie|mié|jueves|jue|viernes|vie|s[aá]bado|sab|sáb|'
        r'domingo|dom)$',
      ),
    );
    if (weekdayToken != null) {
      final iso = _weekdays[weekdayToken.toLowerCase()]!;
      final isNext =
          nextWeekday != null &&
          p(r'^(next|pr[oó]ximo|pr[oó]xima)').hasMatch(nextWeekday);
      var delta = (iso - today.weekday + 7) % 7;
      if (delta == 0 && isNext) delta = 7;
      dueDay = DateTime(today.year, today.month, today.day + delta);
    } else {
      // "in N days/weeks" / "en N días".
      final inN = take(
        p(r'\b(?:in|en)\s+(\d+)\s*(days?|d[ií]as?|weeks?|semanas?)\b'),
      );
      if (inN != null) {
        final m = p(r'(\d+)\s*(\w+)').firstMatch(inN)!;
        final n = int.parse(m.group(1)!);
        final days = _unitOf(m.group(2)!) == RecurrenceUnit.week ? n * 7 : n;
        dueDay = DateTime(today.year, today.month, today.day + days);
      } else {
        // Month-name dates: "Nov 30", "30 nov", "30 de noviembre".
        final monthDay = take(
          p(r'\b(' + _months.keys.join('|') + r')\.?\s+(\d{1,2})\b'),
        );
        final dayMonth = monthDay == null
            ? take(
                p(
                  r'\b(\d{1,2})\s*(?:de\s+)?(' +
                      _months.keys.join('|') +
                      r')\.?\b',
                ),
              )
            : null;
        if (monthDay != null) {
          final m = p(r'(\w+)\.?\s+(\d{1,2})').firstMatch(monthDay)!;
          dueDay = _resolveMonthDay(
            today,
            _months[m.group(1)!.toLowerCase()]!,
            int.parse(m.group(2)!),
          );
        } else if (dayMonth != null) {
          final m = p(r'(\d{1,2})\s*(?:de\s+)?(\w+)').firstMatch(dayMonth)!;
          dueDay = _resolveMonthDay(
            today,
            _months[m.group(2)!.toLowerCase().replaceAll('.', '')]!,
            int.parse(m.group(1)!),
          );
        } else {
          // Numeric dates: 2026-12-01, 12/01, 12-01 (month/day). Invalid
          // values (e.g. 31/02) are restored to the title.
          final iso = takeIf(p(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b'), (s) {
            final m = p(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s)!;
            return _safeDay(
                  int.parse(m.group(1)!),
                  int.parse(m.group(2)!),
                  int.parse(m.group(3)!),
                ) !=
                null;
          });
          if (iso != null) {
            final m = p(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(iso)!;
            dueDay = _safeDay(
              int.parse(m.group(1)!),
              int.parse(m.group(2)!),
              int.parse(m.group(3)!),
            );
          } else {
            final numeric = takeIf(p(r'\b(\d{1,2})[/-](\d{1,2})\b'), (s) {
              final m = p(r'(\d{1,2})[/-](\d{1,2})').firstMatch(s)!;
              return _resolveMonthDay(
                    today,
                    int.parse(m.group(1)!),
                    int.parse(m.group(2)!),
                  ) !=
                  null;
            });
            if (numeric != null) {
              final m = p(r'(\d{1,2})[/-](\d{1,2})').firstMatch(numeric)!;
              dueDay = _resolveMonthDay(
                today,
                int.parse(m.group(1)!),
                int.parse(m.group(2)!),
              );
            }
          }
        }
      }
    }
  }

  // A time without a date means today (or tomorrow when already past).
  if (reminderMinutes != null && dueDay == null && recurrence == null) {
    final at = DateTime(
      today.year,
      today.month,
      today.day,
      reminderMinutes ~/ 60,
      reminderMinutes % 60,
    );
    dueDay = at.isAfter(now)
        ? today
        : DateTime(today.year, today.month, today.day + 1);
  }
  // Recurrence without an explicit day starts today.
  if (recurrence != null && dueDay == null) {
    dueDay = today;
  }

  final title = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return QuickAddParse(
    title: title,
    dueDay: dueDay,
    reminderMinutes: reminderMinutes,
    recurrence: recurrence,
    tags: tags,
    priority: priority,
  );
}

RecurrenceUnit _unitOf(String word) {
  final w = word.toLowerCase();
  if (w.startsWith('week') || w.startsWith('semana')) {
    return RecurrenceUnit.week;
  }
  if (w.startsWith('month') || w.startsWith('mes')) return RecurrenceUnit.month;
  return RecurrenceUnit.day;
}

/// A month/day pair resolves to this year, or next year when already past.
DateTime? _resolveMonthDay(DateTime today, int month, int day) {
  if (month < 1 || month > 12) return null;
  final candidate = _safeDay(today.year, month, day);
  if (candidate == null) return null;
  if (candidate.isBefore(today)) {
    return _safeDay(today.year + 1, month, day);
  }
  return candidate;
}

/// Date-only construction that rejects overflow (e.g. Feb 31).
DateTime? _safeDay(int year, int month, int day) {
  if (day < 1 || day > daysInMonth(year, month)) return null;
  return DateTime(year, month, day);
}
