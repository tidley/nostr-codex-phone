import 'package:flutter_test/flutter_test.dart';
import 'package:nostr_codex_phone/src/chat_scroll.dart';

void main() {
  test('identifies the latest-message position with a small tolerance', () {
    expect(isChatAtBottom(pixels: 976, maxScrollExtent: 1000), isTrue);
    expect(isChatAtBottom(pixels: 975, maxScrollExtent: 1000), isFalse);
  });

  test('keeps a reader position when messages arrive away from the bottom', () {
    expect(isChatAtBottom(pixels: 100, maxScrollExtent: 100), isTrue);
    expect(isChatAtBottom(pixels: 100, maxScrollExtent: 220), isFalse);
    expect(shouldScrollChatToLatest(isAtBottom: true), isTrue);
    expect(shouldScrollChatToLatest(isAtBottom: false), isFalse);
    expect(shouldScrollChatToLatest(isAtBottom: false, force: true), isTrue);
  });
}
