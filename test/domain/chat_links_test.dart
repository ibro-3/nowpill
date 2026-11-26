import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/chat_links.dart';

/// Pure URL detection for chat notes: no network, no Flutter.
void main() {
  List<String> parts(String body) =>
      parseChatBody(body).map((s) => s.text).toList();
  List<bool> flags(String body) =>
      parseChatBody(body).map((s) => s.isLink).toList();

  test('plain bodies stay a single text segment', () {
    expect(parts('just a thought'), ['just a thought']);
    expect(flags('just a thought'), [false]);
    expect(parseChatBody(''), isEmpty);
  });

  test('detects http and https URLs', () {
    const body = 'Read https://example.com/a and http://example.org/b';
    expect(parts(body), [
      'Read ',
      'https://example.com/a',
      ' and ',
      'http://example.org/b',
    ]);
    expect(flags(body), [false, true, false, true]);
  });

  test('leaves sentence punctuation outside the link', () {
    const body = 'See https://example.com/a, then go.';
    expect(parts(body), ['See ', 'https://example.com/a', ', then go.']);
    expect(flags(body), [false, true, false]);
  });

  test('keeps balanced parentheses in a URL', () {
    const body = '(https://en.wikipedia.org/wiki/Foo_(bar))';
    expect(parts(body), ['(', 'https://en.wikipedia.org/wiki/Foo_(bar)', ')']);
  });

  test('bare www, custom schemes and empty hosts are not links', () {
    for (final body in [
      'visit www.example.com today',
      'call mailto:me@example.com',
      'try https://',
    ]) {
      expect(flags(body), [false], reason: body);
      expect(parts(body), [body]);
    }
  });

  test('isOpenableLink only accepts http/https with a host', () {
    expect(isOpenableLink('https://example.com/a'), isTrue);
    expect(isOpenableLink('http://example.org'), isTrue);
    expect(isOpenableLink('javascript:alert(1)'), isFalse);
    expect(isOpenableLink('file:///tmp/x'), isFalse);
    expect(isOpenableLink('https://'), isFalse);
    expect(isOpenableLink('not a url'), isFalse);
  });
}
