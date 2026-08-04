import 'dart:async';

import 'package:flutter/material.dart';
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

  testWidgets('jump action reaches the latest dynamically loaded history row', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _HistoryChat()));

    await tester.tap(find.byTooltip('Jump to latest message'));
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(find.byType(ListView));
    expect(
      list.controller!.position.pixels,
      list.controller!.position.maxScrollExtent,
    );
  });
}

class _HistoryChat extends StatefulWidget {
  const _HistoryChat();

  @override
  State<_HistoryChat> createState() => _HistoryChatState();
}

class _HistoryChatState extends State<_HistoryChat> {
  final _controller = ScrollController();
  var _messageCount = 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _loadHistoryAndJump() {
    setState(() => _messageCount = 50);
    unawaited(
      scrollChatToLatestAfterLayout(
        _controller,
        duration: const Duration(milliseconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _controller,
            itemCount: _messageCount,
            itemBuilder: (_, index) =>
                SizedBox(height: 48, child: Text('History message $index')),
          ),
        ),
        IconButton(
          tooltip: 'Jump to latest message',
          onPressed: _loadHistoryAndJump,
          icon: const Icon(Icons.arrow_downward),
        ),
      ],
    ),
  );
}
