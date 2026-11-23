/// Pure search matching for tasks, habits, and tags (v0.4). Case- and
/// diacritic-insensitive substring matching — datasets are small, so no index
/// table; the UI recomputes reactively on every keystroke.
library;

/// Normalizes text for matching: lowercase + diacritics stripped (é → e,
/// ñ → n, ü → u). Keeps letters/digits/spaces; other characters pass through
/// so punctuation in titles still matches literally.
String normalizeForSearch(String text) {
  const map = {
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'ã': 'a',
    'å': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ñ': 'n',
    'ç': 'c',
    'ý': 'y',
    'ÿ': 'y',
  };
  final lower = text.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(map[ch] ?? ch);
  }
  return buffer.toString();
}

/// Whether [query] matches [text] (normalized substring). An empty/whitespace
/// query matches nothing (the UI shows hints instead of everything).
bool searchMatches(String query, String text) {
  final q = normalizeForSearch(query.trim());
  if (q.isEmpty) return false;
  return normalizeForSearch(text).contains(q);
}

/// Whether [query] matches any of [texts].
bool searchMatchesAny(String query, Iterable<String?> texts) {
  for (final t in texts) {
    if (t != null && searchMatches(query, t)) return true;
  }
  return false;
}
