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

  test('workspace state applies a broadcast channel creation', () {
    final state = WorkspaceState();

    state.apply({
      'workspace_update': {
        'action': 'channel_created',
        'channels': [
          {
            'id': 'channel-1',
            'name': 'engineering',
            'created_by': 'owner',
            'created_at': 42,
          },
        ],
      },
    });

    expect(state.channels, hasLength(1));
    expect(state.channels.single.id, 'channel-1');
    expect(state.channels.single.name, 'engineering');
  });

  test('direct message keys are stable regardless of participant order', () {
    expect(
      WorkspaceState.directKey('alice', 'bob'),
      WorkspaceState.directKey('bob', 'alice'),
    );
  });

  test('workspace uses a channel name and accepts local member aliases', () {
    final state = WorkspaceState()
      ..apply({
        'workspace_update': {
          'channels': [
            {'id': 'channel-1', 'name': 'engineering'},
          ],
        },
      });

    expect(state.channelName('channel-1'), 'engineering');
    expect(decodeWorkspaceMemberAliases('{"worker":"Desktop"}'), {
      'worker': 'Desktop',
    });
    expect(decodeWorkspaceMemberAliases('not json'), isEmpty);
  });

  test('workspace stores synced member profile names', () {
    final state = WorkspaceState()
      ..apply({
        'workspace_update': {
          'action': 'snapshot',
          'members': [
            {'pubkey': 'worker', 'display_name': 'Desktop'},
          ],
        },
      })
      ..apply({
        'workspace_update': {
          'action': 'profile_updated',
          'members': [
            {'pubkey': 'worker', 'display_name': 'Build machine'},
          ],
        },
      });

    expect(state.members, ['worker']);
    expect(state.memberNames['worker'], 'Build machine');
  });
}
