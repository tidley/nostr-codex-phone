import 'package:flutter_test/flutter_test.dart';
import 'package:nostr_codex_phone/src/workspace_models.dart';

void main() {
  test('workspace state merges persisted updates without fake records', () {
    final state = WorkspaceState();
    state.apply({
      'workspace_update': {
        'action': 'snapshot',
        'channels': [
          {'id': 'channel-1', 'name': 'engineering'},
        ],
        'members': ['owner', 'member'],
      },
    });
    state.apply({
      'workspace_update': {
        'action': 'message_created',
        'messages': [
          {
            'id': 'message-1',
            'channel_id': 'channel-1',
            'sender_pubkey': 'owner',
            'body': 'Persisted message',
            'created_at': 2,
          },
          {
            'id': 'message-2',
            'channel_id': 'channel-1',
            'sender_pubkey': 'member',
            'body': 'Thread reply',
            'parent_id': 'message-1',
            'created_at': 3,
          },
        ],
      },
    });

    expect(state.channels.single.name, 'engineering');
    expect(state.members, ['owner', 'member']);
    expect(state.messages['channel-1']![1].parentId, 'message-1');
  });

  test('direct message keys are stable regardless of participant order', () {
    expect(
      WorkspaceState.directKey('alice', 'bob'),
      WorkspaceState.directKey('bob', 'alice'),
    );
  });
}
