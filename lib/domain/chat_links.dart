/// Pure URL detection for personal chat notes. No Flutter or network imports —
/// the renderer only decides how to display and open the segments returned here.
library;

/// One piece of a note body: either plain text or a tappable link.
class ChatSegment {
  const ChatSegment._(this.text, this.isLink);

  factory ChatSegment.text(String text) => ChatSegment._(text, false);
  factory ChatSegment.link(String text) => ChatSegment._(text, true);

  final String text;
  final bool isLink;
}

const String _kTrailingPunctuation = '.,;:!?\'"]';
final RegExp _kUrlPattern = RegExp(r'https?://[^\s<>]+', caseSensitive: false);

int _count(String char, String text) => text.split(char).length - 1;

/// Splits [body] into plain and linked segments.
///
/// **My design decision (not in M3):** only `http://` and `https://` are links.
/// Bare `www.` addresses, custom schemes andmailto:/file: URLs stay plain text,
/// so a note can never launch something unexpected. Sentence punctuation that
/// follows a URL is kept as plain text instead of being swallowed by the link.
List<ChatSegment> parseChatBody(String body) {
  if (body.isEmpty) return const [];
  final segments = <ChatSegment>[];
  var cursor = 0;

  for (final match in _kUrlPattern.allMatches(body)) {
    if (match.start < cursor) continue;
    if (match.start > cursor) {
      segments.add(ChatSegment.text(body.substring(cursor, match.start)));
    }

    var url = match.group(0)!;
    while (url.isNotEmpty &&
        _kTrailingPunctuation.contains(url.substring(url.length - 1))) {
      url = url.substring(0, url.length - 1);
    }
    while (url.endsWith(')') && _count('(', url) < _count(')', url)) {
      url = url.substring(0, url.length - 1);
    }

    final host = url.replaceFirst(
      RegExp(r'^https?://', caseSensitive: false),
      '',
    );
    final valid =
        host.isNotEmpty &&
        host.split('').any((c) => c.contains(RegExp(r'[a-zA-Z0-9]')));

    if (!valid) {
      cursor = match.end;
      continue;
    }
    segments.add(ChatSegment.link(url));
    // Leave trailing punctuation behind for the next plain segment.
    cursor = match.start + url.length;
  }

  if (cursor < body.length) {
    segments.add(ChatSegment.text(body.substring(cursor)));
  }
  return segments;
}

/// Whether [text] is a URL we are willing to open externally.
bool isOpenableLink(String text) {
  final uri = Uri.tryParse(text);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}
