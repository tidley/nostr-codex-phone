import 'package:flutter_test/flutter_test.dart';
import 'package:nostr_codex_phone/src/workspace_models.dart';

void main() {
  test('agent profiles retain an optional saved working folder', () {
    final scoped = WorkspaceAgent.fromJson({
      'id': 'builder',
      'name': 'Builder',
      'role': 'Build changes',
      'workdir': '/home/tom/code/phone',
    });
    final defaultFolder = WorkspaceAgent.fromJson({
      'id': 'reviewer',
      'name': 'Reviewer',
      'role': 'Review changes',
    });

    expect(scoped.workdir, '/home/tom/code/phone');
    expect(defaultFolder.workdir, isNull);
  });

  test(
    'classifies local and agent senders without depending on display names',
    () {
      expect(isWorkspaceAgentSender('agent:review-bot'), isTrue);
      expect(isWorkspaceAgentSender('Agent:review-bot'), isTrue);
      expect(isWorkspaceAgentSender('review-bot'), isFalse);
      expect(
        isWorkspaceLocalSender('ABC123', {'abc123', 'npub-local'}),
        isTrue,
      );
      expect(
        isWorkspaceLocalSender('other-member', {'abc123', 'npub-local'}),
        isFalse,
      );
    },
  );

  test('avatar colors are stable by identity and use names as a fallback', () {
    expect(
      workspaceAvatarColorIndex('alice', 'Ada', 5),
      workspaceAvatarColorIndex('alice', 'Renamed Ada', 5),
    );
    expect(
      workspaceAvatarColorIndex('', 'Ada', 5),
      workspaceAvatarColorIndex('', 'Ada', 5),
    );
    expect(workspaceAvatarColorIndex('alice', 'Ada', 0), 0);
  });

  test('message grouping only joins consecutive messages from one sender', () {
    const first = WorkspaceMessage(
      id: 'first',
      senderPubkey: 'agent:scout',
      body: 'First',
      createdAt: 1,
      channelId: 'workspace',
    );
    const second = WorkspaceMessage(
      id: 'second',
      senderPubkey: 'AGENT:SCOUT',
      body: 'Second',
      createdAt: 2,
      channelId: 'workspace',
    );
    const threaded = WorkspaceMessage(
      id: 'threaded',
      senderPubkey: 'agent:scout',
      body: 'Thread reply',
      createdAt: 3,
      channelId: 'workspace',
      parentId: 'first',
    );

    expect(isWorkspaceMessageGroupedWithPrevious(second, first), isTrue);
    expect(isWorkspaceMessageGroupedWithPrevious(threaded, second), isFalse);
  });

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

  test('workspace state reports only newly inserted messages', () {
    final state = WorkspaceState();
    final update = {
      'workspace_update': {
        'action': 'message_created',
        'messages': [
          {
            'id': 'message-1',
            'channel_id': 'channel-1',
            'sender_pubkey': 'member',
            'body': 'Hello',
            'created_at': 1,
          },
        ],
      },
    };

    expect(state.apply(update).single.id, 'message-1');
    expect(state.apply(update), isEmpty);
  });

  test('conversation agent retains its folder scope', () {
    final agent = WorkspaceConversationAgent.fromJson({
      'agent_id': 'agent-1',
      'channel_id': 'channel-1',
      'folder_scope': ['/work/apps', ' /work/tools '],
    });

    expect(agent.folderScope, ['/work/apps', '/work/tools']);
  });

  test('group call metadata accepts only a unique two-to-four member mesh', () {
    final call = WorkspaceGroupCall.fromJson({
      'call_id': 'call-1',
      'channel_id': 'channel-1',
      'participant_pubkeys': ['alice', 'bob', 'carol'],
      'sender_pubkey': 'alice',
    });

    expect(call.isValid, isTrue);
    expect(
      WorkspaceGroupCall.fromJson({
        'call_id': 'call-1',
        'channel_id': 'channel-1',
        'participant_pubkeys': ['alice', 'alice'],
        'sender_pubkey': 'alice',
      }).isValid,
      isFalse,
    );
  });

  test(
    'workspace rehydrates broadcast reactions and main-thread visibility',
    () {
      final state = WorkspaceState()
        ..apply({
          'workspace_update': {
            'action': 'message_updated',
            'messages': [
              {
                'id': 'reply-1',
                'channel_id': 'channel-1',
                'sender_pubkey': 'member',
                'body': 'Visible reply',
                'parent_id': 'message-1',
                'also_send_to_main': true,
                'reactions': [
                  {'emoji': '👍', 'sender_pubkey': 'owner'},
                ],
                'created_at': 3,
              },
            ],
          },
        });

      final message = state.messages['channel-1']!.single;
      expect(message.alsoSendToMain, isTrue);
      expect(message.reactions.single.emoji, '👍');
      expect(message.reactions.single.senderPubkey, 'owner');
    },
  );

  test('workspace state retains attachment references on messages', () {
    final state = WorkspaceState()
      ..apply({
        'workspace_update': {
          'action': 'message_created',
          'messages': [
            {
              'id': 'message-1',
              'channel_id': 'channel-1',
              'sender_pubkey': 'owner',
              'body': '',
              'attachments': [
                {
                  'url': 'https://cdn.example/report',
                  'sha256': 'a' * 64,
                  'size': 4,
                  'type': 'application/pdf',
                  'name': 'report.pdf',
                },
              ],
              'created_at': 2,
            },
          ],
        },
      });

    final attachment = state.messages['channel-1']!.single.attachments.single;
    expect(attachment.name, 'report.pdf');
    expect(attachment.mediaType, 'application/pdf');
  });

  test('workspace snapshot rehydrates messages and replaces stale state', () {
    final state = WorkspaceState()
      ..apply({
        'workspace_update': {
          'action': 'snapshot',
          'channels': [
            {'id': 'old-channel', 'name': 'old'},
          ],
          'members': ['old-member'],
          'messages': [
            {
              'id': 'old-message',
              'channel_id': 'old-channel',
              'sender_pubkey': 'old-member',
              'body': 'old',
              'created_at': 1,
            },
          ],
        },
      })
      ..apply({
        'workspace_update': {
          'action': 'snapshot',
          'channels': [
            {'id': 'channel-1', 'name': 'engineering'},
          ],
          'members': ['owner', 'member'],
          'messages': [
            {
              'id': 'message-1',
              'channel_id': 'channel-1',
              'sender_pubkey': 'owner',
              'body': 'restored',
              'created_at': 2,
            },
          ],
        },
      });

    expect(state.channels.single.id, 'channel-1');
    expect(state.members, ['owner', 'member']);
    expect(state.messages.keys, ['channel-1']);
    expect(state.messages['channel-1']!.single.body, 'restored');
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

  test('channel member count excludes workspace agents', () {
    final state = WorkspaceState()
      ..apply({
        'workspace_update': {
          'action': 'snapshot',
          'channels': [
            {'id': 'channel-1', 'name': 'engineering'},
          ],
          'members': ['owner', 'member', 'agent:review-bot'],
          'agents': [
            {'id': 'review-bot', 'name': 'ReviewBot', 'role': 'Reviewer'},
          ],
          'conversation_agents': [
            {'agent_id': 'review-bot', 'channel_id': 'channel-1'},
          ],
        },
      });

    expect(state.channelHumanMemberCount('channel-1'), 2);
    expect(state.channelHumanMemberCount('missing-channel'), 0);
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

  test('workspace rehydrates durable agents with OpenCode associations', () {
    final state = WorkspaceState()
      ..apply({
        'workspace_update': {
          'action': 'snapshot',
          'agents': [
            {
              'id': 'agent-1',
              'name': 'Scout',
              'role': 'Researcher',
              'traits': 'Careful',
              'skills': ['Research'],
              'opencode_session_id': 'ses_1',
              'opencode_provider_id': 'openai',
              'opencode_provider_name': 'OpenAI',
              'opencode_model_id': 'gpt-5',
              'opencode_model_name': 'GPT-5',
              'opencode_agent': 'review',
              'workdir': '/workspace/phone',
              'restart_on_failure': false,
            },
          ],
        },
      });

    expect(state.agents.single.name, 'Scout');
    expect(state.agents.single.openCodeSessionId, 'ses_1');
    expect(state.agents.single.sessionStatus, 'ready');
    expect(state.agents.single.skills, ['Research']);
    expect(state.agents.single.openCodeProviderId, 'openai');
    expect(state.agents.single.openCodeProviderName, 'OpenAI');
    expect(state.agents.single.openCodeModelId, 'gpt-5');
    expect(state.agents.single.openCodeModelName, 'GPT-5');
    expect(state.agents.single.openCodeAgent, 'review');
    expect(state.agents.single.workdir, '/workspace/phone');
    expect(state.agents.single.restartOnFailure, isFalse);
  });

  test('selected workspace mention keeps stable metadata with plain text', () {
    const mention = WorkspaceMention(
      kind: 'agent',
      id: 'agent-1',
      label: 'Scout',
    );

    final mentions = workspaceSelectedMentionsIn('Please ask @Scout', [
      mention,
    ]);

    expect(mentions.single.toJson(), {
      'kind': 'agent',
      'id': 'agent-1',
      'label': 'Scout',
    });
    expect(
      workspaceSelectedMentionsIn('Please ask @ScoutBot', [mention]),
      isEmpty,
    );
  });

  test('workspace state merges broadcast agent renames', () {
    final state = WorkspaceState()
      ..apply({
        'workspace_update': {
          'action': 'snapshot',
          'agents': [
            {'id': 'agent-1', 'name': 'Scout', 'role': 'Researcher'},
          ],
        },
      })
      ..apply({
        'workspace_update': {
          'action': 'agent_renamed',
          'agents': [
            {'id': 'agent-1', 'name': 'Navigator', 'role': 'Researcher'},
          ],
        },
      });

    expect(state.agents.single.name, 'Navigator');
  });

  test('workspace state applies agent provisioning failures', () {
    final state = WorkspaceState()
      ..apply({
        'workspace_update': {
          'action': 'agent_created',
          'agents': [
            {
              'id': 'agent-1',
              'name': 'Rev',
              'role': 'Reviewer',
              'session_status': 'failed',
              'session_error': 'OpenCode is unavailable',
            },
          ],
        },
      });

    expect(state.agents.single.sessionStatus, 'failed');
    expect(state.agents.single.sessionError, 'OpenCode is unavailable');
  });

  test('workspace state removes deleted agents and their memberships', () {
    final state = WorkspaceState()
      ..apply({
        'workspace_update': {
          'action': 'snapshot',
          'agents': [
            {'id': 'agent-1', 'name': 'Scout', 'role': 'Researcher'},
          ],
          'conversation_agents': [
            {'agent_id': 'agent-1', 'channel_id': 'channel-1'},
          ],
        },
      })
      ..apply({
        'workspace_update': {
          'action': 'agent_deleted',
          'agents': [],
          'conversation_agents': [],
        },
      });

    expect(state.agents, isEmpty);
    expect(state.conversationAgents, isEmpty);
  });

  test('workspace retains durable conversation agent memberships', () {
    final state = WorkspaceState()
      ..apply({
        'workspace_update': {
          'action': 'snapshot',
          'conversation_agents': [
            {'agent_id': 'agent-1', 'channel_id': 'channel-1'},
          ],
        },
      })
      ..apply({
        'workspace_update': {
          'action': 'conversation_agents_updated',
          'conversation_agents': [
            {
              'agent_id': 'agent-1',
              'member_pubkey': 'alice',
              'peer_pubkey': 'bob',
            },
          ],
        },
      });

    expect(state.conversationAgents.single.peerPubkey, 'bob');
  });

  test(
    'workspace typing is scoped to its conversation and expires in memory',
    () {
      final state = WorkspaceState()
        ..apply({
          'workspace_update': {
            'action': 'typing',
            'typing': {
              'sender_pubkey': 'alice',
              'channel_id': 'engineering',
              'expires_at': 200,
            },
          },
        })
        ..apply({
          'workspace_update': {
            'action': 'typing',
            'typing': {
              'sender_pubkey': 'bob',
              'recipient_pubkey': 'you',
              'expires_at': 200,
            },
          },
        });

      expect(
        state
            .activeTyping(
              channelId: 'engineering',
              ownPubkey: 'you',
              peerPubkey: null,
              nowSeconds: 199,
            )
            .map((status) => status.senderPubkey),
        ['alice'],
      );
      expect(
        state
            .activeTyping(
              channelId: null,
              ownPubkey: 'you',
              peerPubkey: 'bob',
              nowSeconds: 199,
            )
            .map((status) => status.senderPubkey),
        ['bob'],
      );
      expect(
        state.activeTyping(
          channelId: 'engineering',
          ownPubkey: 'you',
          peerPubkey: null,
          nowSeconds: 200,
        ),
        isEmpty,
      );
    },
  );

  test(
    'agent typing has an identity, matches both DM participants, and clears',
    () {
      final state = WorkspaceState()
        ..apply({
          'workspace_update': {
            'action': 'typing',
            'typing': {
              'sender_pubkey': 'agent:rev',
              'agent_id': 'rev',
              'agent_name': 'Rev',
              'member_pubkey': 'alice',
              'peer_pubkey': 'bob',
              'expires_at': 200,
            },
          },
        });

      for (final participants in [('alice', 'bob'), ('bob', 'alice')]) {
        final active = state.activeTyping(
          channelId: null,
          ownPubkey: participants.$1,
          peerPubkey: participants.$2,
          nowSeconds: 199,
        );
        expect(active.single.agentId, 'rev');
        expect(active.single.agentName, 'Rev');
      }

      state.apply({
        'workspace_update': {
          'action': 'typing',
          'typing': {
            'sender_pubkey': 'agent:rev',
            'agent_id': 'rev',
            'agent_name': 'Rev',
            'member_pubkey': 'alice',
            'peer_pubkey': 'bob',
            'expires_at': 0,
          },
        },
      });
      expect(
        state.activeTyping(
          channelId: null,
          ownPubkey: 'alice',
          peerPubkey: 'bob',
          nowSeconds: 199,
        ),
        isEmpty,
      );
    },
  );

  test('a new message immediately clears matching human typing', () {
    final state = WorkspaceState()
      ..apply({
        'workspace_update': {
          'action': 'typing',
          'typing': {
            'sender_pubkey': 'alice',
            'channel_id': 'engineering',
            'expires_at': 200,
          },
        },
      })
      ..apply({
        'workspace_update': {
          'action': 'message_created',
          'messages': [
            {
              'id': 'message-1',
              'sender_pubkey': 'alice',
              'channel_id': 'engineering',
              'body': 'sent',
              'created_at': 100,
            },
          ],
        },
      });

    expect(
      state.activeTyping(
        channelId: 'engineering',
        ownPubkey: 'you',
        peerPubkey: null,
        nowSeconds: 100,
      ),
      isEmpty,
    );
  });

  test('an agent response immediately clears its typing indicator', () {
    final state = WorkspaceState()
      ..apply({
        'workspace_update': {
          'action': 'typing',
          'typing': {
            'sender_pubkey': 'agent:rev',
            'agent_id': 'rev',
            'member_pubkey': 'alice',
            'peer_pubkey': 'bob',
            'expires_at': 200,
          },
        },
      })
      ..apply({
        'workspace_update': {
          'action': 'message_created',
          'messages': [
            {
              'id': 'message-1',
              'sender_pubkey': 'agent:rev',
              'recipient_pubkey': 'bob',
              'body': 'response',
              'created_at': 100,
            },
          ],
        },
      });

    expect(
      state.activeTyping(
        channelId: null,
        ownPubkey: 'alice',
        peerPubkey: 'bob',
        nowSeconds: 100,
      ),
      isEmpty,
    );
  });
}
