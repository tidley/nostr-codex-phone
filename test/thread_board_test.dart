import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crew/main.dart';
import 'package:crew/src/workspace_models.dart';

Map<String, dynamic> column(String id, String name, int rank) => {
  'id': id, 'name': name, 'rank': rank,
};

Map<String, dynamic> card(String columnId) => {
  'id': 'card-1', 'title': 'Thread title', 'description': 'Original request',
  'column_id': columnId, 'source_thread_id': 'root-1', 'rank': 1024,
  'created_at': 10, 'updated_at': 20,
};

void main() {
  testWidgets('live thread card restores an evicted root before navigation', (tester) async {
    final root = {'id': 'root-1', 'channel_id': 'channel-1', 'sender_pubkey': 'owner', 'body': 'Private original request', 'created_at': 1};
    final state = WorkspaceState()..apply({'workspace_update': {
      'action': 'snapshot', 'revision': 1,
      'messages': [root, for (var i = 0; i < 501; i++) {'id': 'other-$i', 'channel_id': 'channel-1', 'sender_pubkey': 'owner', 'body': 'Other message', 'created_at': i + 2}],
    }});
    expect(state.messages['channel-1']!.any((message) => message.id == 'root-1'), isFalse);
    state.apply({'workspace_update': {
      'action': 'board_updated', 'revision': 2,
      'board_columns': [column('backlog', 'Backlog', 1024)],
      'board_cards': [card('backlog')], 'messages': [root],
    }});
    WorkspaceMessage? opened;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WorkspaceBoard(
      tasks: const [], timelineEntries: const [], isAdmin: false,
      columns: state.boardColumns, cards: state.boardCards,
      conversationLabel: (key) => key,
      onCreate: () async {}, onEdit: (_) async {}, onRetry: (_) async {},
      onCancel: (_) async {}, onMoveToScheduled: (_) async {}, onMove: (_, _) async {},
      onOpenTaskThread: (_) => fail('Must open source thread'),
      onOpenCardThread: (id) => opened = state.messages.values.expand((messages) => messages).firstWhere((message) => message.id == id),
    ))));
    await tester.tap(find.byKey(const ValueKey('board-card-card-1')));
    expect(opened?.id, 'root-1');
    expect(opened?.body, 'Private original request');
  });

  test('thread board keeps linked roots beyond the conversation cache limit', () {
    final state = WorkspaceState()..apply({'workspace_update': {
      'action': 'snapshot', 'board_cards': [card('backlog')],
      'messages': [
        {'id': 'root-1', 'channel_id': 'channel-1', 'sender_pubkey': 'owner', 'body': 'Source thread', 'created_at': 1},
        for (var i = 0; i < 501; i++) {'id': 'other-$i', 'channel_id': 'channel-1', 'sender_pubkey': 'owner', 'body': 'Other message', 'created_at': i + 2},
      ],
    }});
    expect(state.messages['channel-1']!.any((message) => message.id == 'root-1'), isTrue);
  });

  test('thread board survives chunked history and cache, then moves Integrating', () {
    final state = WorkspaceState();
    state.apply({'workspace_update': {
      'action': 'history_transfer:v1:board:1:2:snapshot', 'revision': 5,
      'board_cards': [card('backlog')],
    }});
    expect(state.boardCards, isEmpty);
    state.apply({'workspace_update': {
      'action': 'history_transfer:v1:board:0:2:snapshot', 'revision': 5,
      'board_columns': [column('backlog', 'Backlog', 1024)],
    }});
    expect(state.boardColumns.single.name, 'Backlog');
    expect(state.boardCards.single.sourceThreadId, 'root-1');
    expect(state.boardTasks, isEmpty);
    final cached = WorkspaceState()..apply({'workspace_update': state.toSnapshotJson()});
    expect(cached.boardCards.single.toJson(), state.boardCards.single.toJson());
    cached.apply({'workspace_update': {
      'action': 'board_updated', 'revision': 6,
      'board_columns': [column('backlog', 'Backlog', 1024), column('integrating', 'Integrating', 2048)],
      'board_cards': [card('integrating')],
    }});
    expect(cached.boardCards.single.id, 'card-1');
    expect(cached.boardCards.single.columnId, 'integrating');
    cached.apply({'workspace_update': {'action': 'message_created', 'revision': 7, 'board_cards': [], 'board_columns': []}});
    expect(cached.boardCards, hasLength(1));
    cached.apply({'workspace_update': {'action': 'board_updated', 'revision': 8, 'board_cards': []}});
    expect(cached.boardCards, isEmpty);
    cached.clear();
    expect(cached.boardColumns, isEmpty);
  });

  testWidgets('thread board renders Backlog and opens source without task controls', (tester) async {
    String? opened;
    final columns = [column('backlog', 'Backlog', 1024), column('integrating', 'Integrating', 2048)].map(WorkspaceBoardColumn.fromJson).toList();
    Future<void> show(String columnId) => tester.pumpWidget(MaterialApp(home: Scaffold(body: WorkspaceBoard(
      tasks: const [], timelineEntries: const [], isAdmin: true,
      columns: columns, cards: [WorkspaceBoardCard.fromJson(card(columnId))],
      conversationLabel: (key) => key,
      onCreate: () async {}, onEdit: (_) async {}, onRetry: (_) async {},
      onCancel: (_) async {}, onMoveToScheduled: (_) async {}, onMove: (_, _) async {},
      onOpenTaskThread: (_) => fail('Generic card must not use task navigation'),
      onOpenCardThread: (rootId) => opened = rootId,
    ))));
    await show('backlog');
    expect(find.text('Backlog'), findsOneWidget);
    expect(find.text('Thread title'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('board-card-card-1')));
    expect(opened, 'root-1');
    for (final label in ['Edit', 'Retry', 'Cancel', 'Move to scheduled', 'Next run:']) {
      expect(find.text(label), findsNothing);
    }
    await show('integrating');
    await tester.pump();
    final cardRect = tester.getRect(find.byKey(const ValueKey('board-card-card-1')));
    final reviewRect = tester.getRect(find.text('Review'));
    expect(cardRect.left, greaterThanOrEqualTo(reviewRect.left));
    expect(cardRect.left - reviewRect.left, lessThan(30));
    expect(find.byType(Draggable<WorkspaceBoardTask>), findsNothing);
  });
}
