import 'dart:convert';

import 'package:crew/src/rust/api/nostr.dart';

Map<String, String> decodeWorkspaceMemberAliases(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return {
      for (final entry in decoded.entries)
        if (entry.key.toString().trim().isNotEmpty &&
            entry.value.toString().trim().isNotEmpty)
          entry.key.toString().trim(): entry.value.toString().trim(),
    };
  } catch (_) {
    return {};
  }
}

class _WorkspaceHistoryTransfer {
  _WorkspaceHistoryTransfer(this.total);

  final int total;
  final Map<int, Map<String, dynamic>> chunks = {};
}

class _WorkspaceHistoryTransferAction {
  const _WorkspaceHistoryTransferAction(
    this.id,
    this.sequence,
    this.total,
    this.action,
  );

  final String id;
  final int sequence;
  final int total;
  final String action;
}

_WorkspaceHistoryTransferAction? _historyTransferAction(String? value) {
  if (value == null) return null;
  final parts = value.split(':');
  if (parts.length != 6 || parts[0] != 'history_transfer' || parts[1] != 'v1') {
    return null;
  }
  final sequence = int.tryParse(parts[3]);
  final total = int.tryParse(parts[4]);
  if (parts[2].isEmpty ||
      sequence == null ||
      total == null ||
      sequence < 0 ||
      sequence >= total ||
      total < 1 ||
      parts[5].isEmpty) {
    return null;
  }
  return _WorkspaceHistoryTransferAction(parts[2], sequence, total, parts[5]);
}

bool isWorkspaceAgentSender(String senderPubkey) =>
    senderPubkey.trim().toLowerCase().startsWith('agent:');

bool isWorkspaceLocalSender(
  String senderPubkey,
  Iterable<String> localSenderIds,
) {
  final sender = senderPubkey.trim().toLowerCase();
  return sender.isNotEmpty &&
      localSenderIds.any((id) => id.trim().toLowerCase() == sender);
}

/// Consecutive messages from one identity share their visual message group.
bool isWorkspaceMessageGroupedWithPrevious(
  WorkspaceMessage message,
  WorkspaceMessage? previous,
) {
  return previous != null &&
      previous.senderPubkey.trim().toLowerCase() ==
          message.senderPubkey.trim().toLowerCase() &&
      previous.parentId == message.parentId;
}

/// Produces a stable palette slot without persisting presentation data.
int workspaceAvatarColorIndex(String identity, String name, int colorCount) {
  if (colorCount <= 0) return 0;
  final source = identity.trim().isNotEmpty ? identity : name.trim();
  var hash = 0x811c9dc5;
  for (final unit in source.toLowerCase().codeUnits) {
    hash = (hash ^ unit) * 0x01000193;
    hash &= 0x7fffffff;
  }
  return hash % colorCount;
}

class WorkspaceChannel {
  const WorkspaceChannel({required this.id, required this.name});
  final String id;
  final String name;

  factory WorkspaceChannel.fromJson(Map<String, dynamic> json) =>
      WorkspaceChannel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );
}

/// Ephemeral channel-call metadata carried by group call control messages.
/// FIPS media sessions are intentionally not persisted in workspace snapshots.
class WorkspaceGroupCall {
  const WorkspaceGroupCall({
    required this.callId,
    required this.channelId,
    required this.participantPubkeys,
    required this.senderPubkey,
  });

  final String callId;
  final String channelId;
  final List<String> participantPubkeys;
  final String senderPubkey;

  factory WorkspaceGroupCall.fromJson(Map<String, dynamic> json) =>
      WorkspaceGroupCall(
        callId: json['call_id']?.toString().trim() ?? '',
        channelId: json['channel_id']?.toString().trim() ?? '',
        participantPubkeys: (json['participant_pubkeys'] as List? ?? const [])
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false),
        senderPubkey: json['sender_pubkey']?.toString().trim() ?? '',
      );

  bool get isValid =>
      callId.isNotEmpty &&
      channelId.isNotEmpty &&
      participantPubkeys.length >= 2 &&
      participantPubkeys.length <= 4 &&
      participantPubkeys.toSet().length == participantPubkeys.length &&
      senderPubkey.isNotEmpty;
}

class WorkspaceMessage {
  const WorkspaceMessage({
    required this.id,
    required this.senderPubkey,
    required this.body,
    required this.createdAt,
    this.channelId,
    this.recipientPubkey,
    this.parentId,
    this.alsoSendToMain = false,
    this.attachments = const [],
    this.mentions = const [],
    this.reactions = const [],
  });
  final String id;
  final String? channelId;
  final String? recipientPubkey;
  final String senderPubkey;
  final String body;
  final String? parentId;
  final bool alsoSendToMain;
  final List<BridgeAudioReference> attachments;
  final List<WorkspaceMention> mentions;
  final List<WorkspaceReaction> reactions;
  final int createdAt;

  factory WorkspaceMessage.fromJson(Map<String, dynamic> json) =>
      WorkspaceMessage(
        id: json['id']?.toString() ?? '',
        channelId: json['channel_id']?.toString(),
        recipientPubkey: json['recipient_pubkey']?.toString(),
        senderPubkey: json['sender_pubkey']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        parentId: json['parent_id']?.toString(),
        alsoSendToMain: json['also_send_to_main'] == true,
        attachments: _attachments(json['attachments']),
        mentions: _mentions(json['mentions']),
        reactions: _reactions(json['reactions']),
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      );
}

class WorkspaceReaction {
  const WorkspaceReaction({required this.emoji, required this.senderPubkey});
  final String emoji;
  final String senderPubkey;
}

List<WorkspaceReaction> _reactions(Object? raw) => raw is List
    ? raw
          .whereType<Map>()
          .map(
            (item) => WorkspaceReaction(
              emoji: item['emoji']?.toString() ?? '',
              senderPubkey: item['sender_pubkey']?.toString() ?? '',
            ),
          )
          .where(
            (item) => item.emoji.isNotEmpty && item.senderPubkey.isNotEmpty,
          )
          .toList(growable: false)
    : const [];

class WorkspaceMention {
  const WorkspaceMention({
    required this.kind,
    required this.id,
    required this.label,
  });

  final String kind;
  final String id;
  final String label;

  Map<String, Object> toJson() => {'kind': kind, 'id': id, 'label': label};
}

List<WorkspaceMention> workspaceSelectedMentionsIn(
  String text,
  Iterable<WorkspaceMention> selected,
) => selected
    .where(
      (mention) => RegExp(
        '${RegExp.escape('@${mention.label}')}(?![A-Za-z0-9_-])',
      ).hasMatch(text),
    )
    .toList(growable: false);

List<BridgeAudioReference> _attachments(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) {
        final encryption = item['encryption'];
        return BridgeAudioReference(
          url: item['url']?.toString() ?? '',
          sha256: item['sha256']?.toString() ?? '',
          size: BigInt.tryParse(item['size']?.toString() ?? '') ?? BigInt.zero,
          mediaType: (item['type'] ?? item['mediaType'])?.toString() ?? '',
          name: item['name']?.toString(),
          encryption: encryption is Map
              ? BridgeAudioEncryption(
                  algorithm: encryption['algorithm']?.toString() ?? '',
                  key: encryption['key']?.toString() ?? '',
                  nonce: encryption['nonce']?.toString() ?? '',
                  plaintextSha256:
                      (encryption['plaintext_sha256'] ??
                              encryption['plaintextSha256'])
                          ?.toString() ??
                      '',
                  plaintextSize:
                      BigInt.tryParse(
                        (encryption['plaintext_size'] ??
                                    encryption['plaintextSize'])
                                ?.toString() ??
                            '',
                      ) ??
                      BigInt.zero,
                  plaintextMediaType:
                      (encryption['plaintext_type'] ??
                              encryption['plaintextMediaType'])
                          ?.toString() ??
                      '',
                )
              : null,
        );
      })
      .where(
        (attachment) =>
            attachment.url.isNotEmpty &&
            attachment.sha256.isNotEmpty &&
            attachment.size > BigInt.zero &&
            attachment.mediaType.isNotEmpty,
      )
      .toList(growable: false);
}

List<WorkspaceMention> _mentions(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map(
        (item) => WorkspaceMention(
          kind: item['kind']?.toString() ?? '',
          id: item['id']?.toString() ?? '',
          label: item['label']?.toString() ?? '',
        ),
      )
      .where(
        (mention) =>
            (mention.kind == 'member' || mention.kind == 'agent') &&
            mention.id.isNotEmpty &&
            mention.label.isNotEmpty,
      )
      .toList(growable: false);
}

class WorkspaceAgent {
  const WorkspaceAgent({
    required this.id,
    required this.name,
    required this.role,
    required this.traits,
    required this.skills,
    this.preset,
    this.openCodeProviderId,
    this.openCodeProviderName,
    this.openCodeModelId,
    this.openCodeModelName,
    this.openCodeAgent,
    this.workdir,
    this.restartOnFailure = true,
    this.openCodeSessionId,
    this.sessionStatus = 'failed',
    this.sessionError,
    this.createdAt = 0,
    this.initializedAt,
    this.inputTokens,
    this.outputTokens,
  });
  final String id;
  final String name;
  final String role;
  final String traits;
  final List<String> skills;
  final String? preset;
  final String? openCodeProviderId;
  final String? openCodeProviderName;
  final String? openCodeModelId;
  final String? openCodeModelName;
  final String? openCodeAgent;
  final String? workdir;
  final bool restartOnFailure;
  final String? openCodeSessionId;
  final String sessionStatus;
  final String? sessionError;
  final int createdAt;
  final int? initializedAt;
  final int? inputTokens;
  final int? outputTokens;

  factory WorkspaceAgent.fromJson(Map<String, dynamic> json) => WorkspaceAgent(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    role: json['role']?.toString() ?? '',
    traits: json['traits']?.toString() ?? '',
    skills: json['skills'] is List
        ? (json['skills'] as List)
              .map((value) => value.toString())
              .where((value) => value.isNotEmpty)
              .toList()
        : const [],
    preset: json['preset']?.toString(),
    openCodeProviderId: json['opencode_provider_id']?.toString(),
    openCodeProviderName: json['opencode_provider_name']?.toString(),
    openCodeModelId: json['opencode_model_id']?.toString(),
    openCodeModelName: json['opencode_model_name']?.toString(),
    openCodeAgent: json['opencode_agent']?.toString(),
    workdir: json['workdir']?.toString(),
    restartOnFailure: json['restart_on_failure'] != false,
    openCodeSessionId: json['opencode_session_id']?.toString(),
    sessionStatus:
        json['session_status']?.toString() ??
        (json['opencode_session_id'] == null ? 'failed' : 'ready'),
    sessionError: json['session_error']?.toString(),
    createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
    initializedAt: (json['initialized_at'] as num?)?.toInt(),
    inputTokens: (json['input_tokens'] as num?)?.toInt(),
    outputTokens: (json['output_tokens'] as num?)?.toInt(),
  );
}

class WorkspaceConversationAgent {
  const WorkspaceConversationAgent({
    required this.agentId,
    this.channelId,
    this.memberPubkey,
    this.peerPubkey,
    this.folderScope = const [],
  });
  final String agentId;
  final String? channelId;
  final String? memberPubkey;
  final String? peerPubkey;
  final List<String> folderScope;

  factory WorkspaceConversationAgent.fromJson(Map<String, dynamic> json) =>
      WorkspaceConversationAgent(
        agentId: json['agent_id']?.toString() ?? '',
        channelId: json['channel_id']?.toString(),
        memberPubkey: json['member_pubkey']?.toString(),
        peerPubkey: json['peer_pubkey']?.toString(),
        folderScope: (json['folder_scope'] as List? ?? const [])
            .map((path) => path.toString().trim())
            .where((path) => path.isNotEmpty)
            .toList(growable: false),
      );
}

class WorkspaceConversationPreprompt {
  const WorkspaceConversationPreprompt({
    required this.preprompt,
    this.channelId,
    this.memberPubkey,
    this.peerPubkey,
  });
  final String preprompt;
  final String? channelId;
  final String? memberPubkey;
  final String? peerPubkey;

  factory WorkspaceConversationPreprompt.fromJson(Map<String, dynamic> json) =>
      WorkspaceConversationPreprompt(
        preprompt: json['preprompt']?.toString() ?? '',
        channelId: json['channel_id']?.toString(),
        memberPubkey: json['member_pubkey']?.toString(),
        peerPubkey: json['peer_pubkey']?.toString(),
      );
}

class WorkspaceTyping {
  const WorkspaceTyping({
    required this.senderPubkey,
    this.agentId,
    this.agentName,
    this.stage,
    this.channelId,
    this.recipientPubkey,
    this.memberPubkey,
    this.peerPubkey,
    required this.expiresAt,
  });

  final String senderPubkey;
  final String? agentId;
  final String? agentName;
  final String? stage;
  final String? channelId;
  final String? recipientPubkey;
  final String? memberPubkey;
  final String? peerPubkey;
  final int expiresAt;

  factory WorkspaceTyping.fromJson(Map<String, dynamic> json) =>
      WorkspaceTyping(
        senderPubkey: json['sender_pubkey']?.toString() ?? '',
        agentId: json['agent_id']?.toString(),
        agentName: json['agent_name']?.toString(),
        stage: json['stage']?.toString(),
        channelId: json['channel_id']?.toString(),
        recipientPubkey: json['recipient_pubkey']?.toString(),
        memberPubkey: json['member_pubkey']?.toString(),
        peerPubkey: json['peer_pubkey']?.toString(),
        expiresAt: (json['expires_at'] as num?)?.toInt() ?? 0,
      );
}

class WorkspaceState {
  List<WorkspaceChannel> channels = [];
  List<String> members = [];
  final Map<String, String> memberNames = {};
  final Map<String, List<WorkspaceMessage>> messages = {};
  List<WorkspaceAgent> agents = [];
  List<WorkspaceConversationAgent> conversationAgents = [];
  List<WorkspaceConversationPreprompt> conversationPreprompts = [];
  final Map<String, WorkspaceTyping> typing = {};
  final Map<String, _WorkspaceHistoryTransfer> _historyTransfers = {};

  List<WorkspaceMessage> apply(
    Map<String, dynamic> raw, {
    Iterable<String> localSenderIds = const [],
  }) {
    final update = raw['workspace_update'];
    if (update is! Map) return const [];
    final data = Map<String, dynamic>.from(update);
    final transfer = _historyTransferAction(data['action']?.toString());
    if (transfer != null) {
      final pending = _historyTransfers.putIfAbsent(
        transfer.id,
        () => _WorkspaceHistoryTransfer(transfer.total),
      );
      if (pending.total != transfer.total) return const [];
      pending.chunks.putIfAbsent(transfer.sequence, () => data);
      if (pending.chunks.length != pending.total) return const [];
      _historyTransfers.remove(transfer.id);
      final added = <WorkspaceMessage>[];
      for (var sequence = 0; sequence < pending.total; sequence++) {
        final chunk = pending.chunks[sequence];
        if (chunk == null) return const [];
        chunk['action'] = _historyTransferAction(
          chunk['action']?.toString(),
        )!.action;
        added.addAll(
          apply({'workspace_update': chunk}, localSenderIds: localSenderIds),
        );
      }
      return added;
    }
    final addedMessages = <WorkspaceMessage>[];
    final isSnapshot = data['action'] == 'snapshot';
    final isSnapshotHeaderWithoutMessages =
        isSnapshot && (data['messages'] as List?)?.isEmpty == true;
    if (isSnapshot) {
      // Large snapshots arrive as an empty header followed by message chunks.
      // Keep visible rows until those chunks arrive, including local rows that
      // have not yet returned through a relay.
      final localMessages = <String, List<WorkspaceMessage>>{};
      if (!isSnapshotHeaderWithoutMessages) {
        for (final entry in messages.entries) {
          final local = entry.value
              .where(
                (message) => isWorkspaceLocalSender(
                  message.senderPubkey,
                  localSenderIds,
                ),
              )
              .toList(growable: false);
          if (local.isNotEmpty) localMessages[entry.key] = local;
        }
      }
      channels = [];
      members = [];
      memberNames.clear();
      if (!isSnapshotHeaderWithoutMessages) {
        messages
          ..clear()
          ..addAll(localMessages);
      }
      agents = [];
      conversationAgents = [];
      conversationPreprompts = [];
      typing.clear();
    }
    final incomingTyping = data['typing'];
    if (incomingTyping is Map) {
      final status = WorkspaceTyping.fromJson(
        Map<String, dynamic>.from(incomingTyping),
      );
      final key = _typingKey(status);
      if (status.senderPubkey.isNotEmpty && status.expiresAt > 0) {
        typing[key] = status;
      } else {
        typing.remove(key);
      }
    }
    final incomingConversationAgents = _conversationAgents(
      data['conversation_agents'],
    );
    if (isSnapshot ||
        data['action'] == 'conversation_agents_updated' ||
        data['action'] == 'agent_deleted') {
      conversationAgents = incomingConversationAgents;
    }
    final incomingPreprompts = _conversationPreprompts(
      data['conversation_preprompts'],
    );
    if (isSnapshot || data['action'] == 'conversation_preprompt_updated') {
      conversationPreprompts = incomingPreprompts;
    }
    final incomingAgents = _agents(data['agents']);
    if (isSnapshot || data['action'] == 'agent_deleted') {
      agents = incomingAgents;
    } else if (incomingAgents.isNotEmpty) {
      final byId = {for (final agent in agents) agent.id: agent};
      for (final agent in incomingAgents) {
        byId[agent.id] = agent;
      }
      agents = byId.values.toList();
    }
    final incomingChannels = _channels(data['channels']);
    if (incomingChannels.isNotEmpty) {
      final byId = {for (final channel in channels) channel.id: channel};
      for (final channel in incomingChannels) {
        byId[channel.id] = channel;
      }
      channels = byId.values.toList();
    }
    final incomingMembers = _members(data['members']);
    if (incomingMembers.isNotEmpty) {
      if (isSnapshot) {
        members = incomingMembers.keys.toList();
      } else {
        final knownMembers = members.toSet()..addAll(incomingMembers.keys);
        members = knownMembers.toList();
      }
      for (final entry in incomingMembers.entries) {
        if (entry.value.isEmpty) {
          memberNames.remove(entry.key);
        } else {
          memberNames[entry.key] = entry.value;
        }
      }
    }
    final incomingMessages = _messages(data['messages']);
    if (data['action'] == 'message_created') {
      for (final message in incomingMessages) {
        typing.removeWhere(
          (_, status) => _typingMatchesMessage(status, message),
        );
      }
    }
    for (final message in incomingMessages) {
      final key = message.channelId ?? _messageDirectKey(message);
      final current = {for (final item in messages[key] ?? []) item.id: item};
      if (!current.containsKey(message.id)) addedMessages.add(message);
      current[message.id] = message;
      messages[key] = current.values.cast<WorkspaceMessage>().toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    return addedMessages;
  }

  static String directKey(String one, String? two) => _directKey(one, two);
  String conversationKeyForMessage(WorkspaceMessage message) =>
      message.channelId ?? _messageDirectKey(message);
  static String _typingKey(WorkspaceTyping status) => [
    status.senderPubkey,
    status.channelId ?? '',
    status.memberPubkey ?? '',
    status.peerPubkey ?? '',
    status.recipientPubkey ?? '',
  ].join(':');
  static bool _typingMatchesMessage(
    WorkspaceTyping status,
    WorkspaceMessage message,
  ) {
    if (status.senderPubkey != message.senderPubkey) return false;
    if (status.channelId != null) return status.channelId == message.channelId;
    if (status.agentId != null) {
      return message.channelId == null &&
          status.peerPubkey == message.recipientPubkey;
    }
    return message.channelId == null &&
        status.recipientPubkey == message.recipientPubkey;
  }

  List<WorkspaceTyping> activeTyping({
    required String? channelId,
    required String ownPubkey,
    required String? peerPubkey,
    required int nowSeconds,
  }) {
    typing.removeWhere((_, status) => status.expiresAt <= nowSeconds);
    return typing.values
        .where((status) {
          if (status.channelId != null) return status.channelId == channelId;
          if (status.agentId != null) {
            return channelId == null &&
                ((status.memberPubkey == ownPubkey &&
                        status.peerPubkey == peerPubkey) ||
                    (status.memberPubkey == peerPubkey &&
                        status.peerPubkey == ownPubkey));
          }
          return channelId == null &&
              ((status.senderPubkey == ownPubkey &&
                      status.recipientPubkey == peerPubkey) ||
                  (status.senderPubkey == peerPubkey &&
                      status.recipientPubkey == ownPubkey));
        })
        .toList(growable: false);
  }

  String? channelName(String id) {
    for (final channel in channels) {
      if (channel.id == id && channel.name.isNotEmpty) return channel.name;
    }
    return null;
  }

  String conversationPreprompt({
    required String? channelId,
    required String ownPubkey,
    required String? peerPubkey,
  }) {
    for (final prompt in conversationPreprompts) {
      if (channelId != null && prompt.channelId == channelId) {
        return prompt.preprompt;
      }
      if (channelId == null &&
          {prompt.memberPubkey, prompt.peerPubkey}.contains(ownPubkey) &&
          {prompt.memberPubkey, prompt.peerPubkey}.contains(peerPubkey)) {
        return prompt.preprompt;
      }
    }
    return '';
  }

  List<String> directPeers(String ownPubkey) {
    final peers = <String>{};
    for (final conversation in messages.values) {
      for (final message in conversation) {
        if (message.channelId != null) continue;
        if (message.senderPubkey == ownPubkey &&
            message.recipientPubkey != null) {
          peers.add(message.recipientPubkey!);
        } else if (message.recipientPubkey == ownPubkey &&
            !isWorkspaceAgentSender(message.senderPubkey)) {
          peers.add(message.senderPubkey);
        }
      }
    }
    return peers.toList()..sort();
  }

  int channelHumanMemberCount(String channelId) {
    if (!channels.any((channel) => channel.id == channelId)) return 0;
    return members.where((member) => !member.startsWith('agent:')).length;
  }

  static String _directKey(String one, String? two) =>
      ([one, two ?? '']..sort()).join(':');
  String _messageDirectKey(WorkspaceMessage message) {
    if (!message.senderPubkey.startsWith('agent:')) {
      return _directKey(message.senderPubkey, message.recipientPubkey);
    }
    final agentId = message.senderPubkey.substring('agent:'.length);
    for (final membership in conversationAgents) {
      if (membership.agentId == agentId &&
          membership.channelId == null &&
          (membership.memberPubkey == message.recipientPubkey ||
              membership.peerPubkey == message.recipientPubkey)) {
        return _directKey(membership.memberPubkey!, membership.peerPubkey);
      }
    }
    return _directKey(message.senderPubkey, message.recipientPubkey);
  }

  static Map<String, String> _members(Object? raw) {
    if (raw is! List) return {};
    final members = <String, String>{};
    for (final member in raw) {
      if (member is Map &&
          member['pubkey']?.toString().trim().isNotEmpty == true) {
        members[member['pubkey'].toString().trim()] =
            member['display_name']?.toString().trim() ?? '';
      } else if (member is String && member.trim().isNotEmpty) {
        members[member.trim()] = '';
      }
    }
    return members;
  }

  static List<WorkspaceChannel> _channels(Object? raw) => raw is List
      ? raw
            .whereType<Map>()
            .map(
              (item) =>
                  WorkspaceChannel.fromJson(Map<String, dynamic>.from(item)),
            )
            .where((item) => item.id.isNotEmpty)
            .toList()
      : [];
  static List<WorkspaceMessage> _messages(Object? raw) => raw is List
      ? raw
            .whereType<Map>()
            .map(
              (item) =>
                  WorkspaceMessage.fromJson(Map<String, dynamic>.from(item)),
            )
            .where((item) => item.id.isNotEmpty)
            .toList()
      : [];
  static List<WorkspaceAgent> _agents(Object? raw) => raw is List
      ? raw
            .whereType<Map>()
            .map(
              (item) =>
                  WorkspaceAgent.fromJson(Map<String, dynamic>.from(item)),
            )
            .where((item) => item.id.isNotEmpty)
            .toList()
      : [];
  static List<WorkspaceConversationAgent> _conversationAgents(Object? raw) =>
      raw is List
      ? raw
            .whereType<Map>()
            .map(
              (item) => WorkspaceConversationAgent.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .where((item) => item.agentId.isNotEmpty)
            .toList()
      : [];
  static List<WorkspaceConversationPreprompt> _conversationPreprompts(
    Object? raw,
  ) => raw is List
      ? raw
            .whereType<Map>()
            .map(
              (item) => WorkspaceConversationPreprompt.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false)
      : [];
}
