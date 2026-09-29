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

class WorkspaceConversationPreference {
  const WorkspaceConversationPreference({
    this.pinned = false,
    this.archived = false,
    this.muted = false,
    this.autoSpeak = false,
    this.sortByRecentReply = true,
  });

  final bool pinned;
  final bool archived;
  final bool muted;
  final bool autoSpeak;
  final bool sortByRecentReply;
  Map<String, bool> toJson() => {
    'pinned': pinned,
    'archived': archived,
    'muted': muted,
    'auto_speak': autoSpeak,
    'sort_by_recent_reply': sortByRecentReply,
  };
}

Map<String, WorkspaceConversationPreference>
decodeWorkspaceConversationPreferences(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return {
      for (final entry in decoded.entries)
        if (entry.key.toString().trim().isNotEmpty && entry.value is Map)
          entry.key.toString().trim(): WorkspaceConversationPreference(
            pinned: entry.value['pinned'] == true,
            archived: entry.value['archived'] == true,
            muted: entry.value['muted'] == true,
            autoSpeak: entry.value['auto_speak'] == true,
            sortByRecentReply: entry.value['sort_by_recent_reply'] != false,
          ),
    };
  } catch (_) {
    return {};
  }
}

class WorkspaceViewPanelSnapshot {
  const WorkspaceViewPanelSnapshot({
    required this.openThreadIds,
    required this.activeThreadId,
    required this.filesSelected,
  });

  final List<String> openThreadIds;
  final String? activeThreadId;
  final bool filesSelected;

  Map<String, Object?> toJson() => {
    'open_thread_ids': openThreadIds,
    if (activeThreadId != null) 'active_thread_id': activeThreadId,
    'files_selected': filesSelected,
  };
}

class WorkspaceViewSnapshot {
  const WorkspaceViewSnapshot(this.conversations);

  static const version = 1;

  final Map<String, WorkspaceViewPanelSnapshot> conversations;

  factory WorkspaceViewSnapshot.decode(String? raw) {
    if (raw == null || raw.isEmpty) return const WorkspaceViewSnapshot({});
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != version) {
        return const WorkspaceViewSnapshot({});
      }
      final rawConversations = decoded['conversations'];
      if (rawConversations is! Map) return const WorkspaceViewSnapshot({});
      final conversations = <String, WorkspaceViewPanelSnapshot>{};
      for (final entry in rawConversations.entries) {
        final key = entry.key.toString().trim();
        final panel = entry.value;
        if (key.isEmpty || panel is! Map || panel['open_thread_ids'] is! List) {
          continue;
        }
        final threadIds = <String>[];
        var valid = true;
        for (final id in panel['open_thread_ids'] as List) {
          if (id is! String || id.trim().isEmpty) {
            valid = false;
            break;
          }
          if (!threadIds.contains(id.trim())) threadIds.add(id.trim());
        }
        final activeThreadId = panel['active_thread_id'];
        if (!valid ||
            (activeThreadId != null &&
                (activeThreadId is! String || activeThreadId.trim().isEmpty)) ||
            panel['files_selected'] is! bool) {
          continue;
        }
        conversations[key] = WorkspaceViewPanelSnapshot(
          openThreadIds: threadIds,
          activeThreadId: activeThreadId == null
              ? null
              : (activeThreadId as String).trim(),
          filesSelected: panel['files_selected'] as bool,
        );
      }
      return WorkspaceViewSnapshot(conversations);
    } catch (_) {
      return const WorkspaceViewSnapshot({});
    }
  }

  Map<String, Object> toJson() => {
    'version': version,
    'conversations': {
      for (final entry in conversations.entries)
        entry.key: entry.value.toJson(),
    },
  };

  WorkspaceViewSnapshot validFor(WorkspaceState workspace, String ownPubkey) {
    final directKeys = workspace
        .directPeers(ownPubkey)
        .map((peer) => WorkspaceState.directKey(ownPubkey, peer))
        .toSet();
    final validConversationKeys = {
      ...workspace.channels.map((channel) => channel.id),
      ...directKeys,
    };
    final valid = <String, WorkspaceViewPanelSnapshot>{};
    for (final entry in conversations.entries) {
      if (!validConversationKeys.contains(entry.key) ||
          !workspace.messages.containsKey(entry.key)) {
        continue;
      }
      final threadIds = workspace.messages[entry.key]!
          .map((message) => message.id)
          .toSet();
      final openThreadIds = entry.value.openThreadIds
          .where(threadIds.contains)
          .toList(growable: false);
      final activeThreadId = threadIds.contains(entry.value.activeThreadId)
          ? entry.value.activeThreadId
          : null;
      valid[entry.key] = WorkspaceViewPanelSnapshot(
        openThreadIds: openThreadIds,
        activeThreadId: activeThreadId,
        filesSelected: entry.value.filesSelected,
      );
    }
    return WorkspaceViewSnapshot(valid);
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
  if (parts.length < 6 || parts[0] != 'history_transfer' || parts[1] != 'v1') {
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
  return _WorkspaceHistoryTransferAction(
    parts[2],
    sequence,
    total,
    parts.skip(5).join(':'),
  );
}

int? _historySince(String action) {
  const prefix = 'messages_since:';
  return action.startsWith(prefix)
      ? int.tryParse(action.substring(prefix.length))
      : null;
}

int? _historySinceValue(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

bool isWorkspaceAgentSender(String senderPubkey) =>
    senderPubkey.trim().toLowerCase().startsWith('agent:');

bool isNativeWorkspaceAgentSender(String senderPubkey) =>
    senderPubkey.trim().toLowerCase() == 'agent:native-opencode';

String workspaceFallbackAgentName(String _) => 'Agent';

String? workspaceThreadTopic(Iterable<WorkspaceMessage> replies) {
  final messages = replies.toList();
  for (final reply in messages.reversed) {
    final match = RegExp(
      r'^\s*\[\[THREAD_TOPIC:\s*([^\]\r\n]+)\]\]',
      caseSensitive: false,
    ).firstMatch(reply.body);
    if (match == null) continue;
    final topic = match
        .group(1)!
        .trim()
        .split(RegExp(r'\s+'))
        .take(3)
        .join(' ');
    if (topic.isNotEmpty) return topic;
  }
  for (final reply in messages.reversed) {
    final hashtags = workspaceMessageHashtags(reply.body);
    if (hashtags.isNotEmpty) return hashtags.take(3).join(' ');
  }
  return null;
}

/// Returns prior threads that are safe to offer as continuations. Matching is
/// deliberately exact: a suggestion must never silently join unrelated work.
List<WorkspaceMessage> workspaceRelatedThreadCandidates(
  Iterable<WorkspaceMessage> messages,
  WorkspaceMessage current, {
  bool includeWhenReferenced = false,
}) {
  final all = messages.toList(growable: false);
  if (!includeWhenReferenced &&
      workspaceActiveRelatedThreadId(all, current) != null) {
    return const [];
  }
  final currentReplies = all
      .where((message) => message.parentId == current.id)
      .where((message) => !isWorkspaceRelatedThreadControlMessage(message))
      .toList(growable: false);
  if (currentReplies.length < 3) return const [];
  final topic = _normalizedWorkspaceThreadTopic(
    workspaceThreadTopic(currentReplies),
  );
  if (topic == null) return const [];
  final candidates = all.where((root) {
    if (root.parentId != null ||
        root.id == current.id ||
        root.createdAt >= current.createdAt) {
      return false;
    }
    final replies = all.where((message) => message.parentId == root.id);
    return _normalizedWorkspaceThreadTopic(workspaceThreadTopic(replies)) ==
            topic &&
        replies.any((message) => isWorkspaceAgentSender(message.senderPubkey));
  }).toList();
  candidates.sort((left, right) => right.createdAt.compareTo(left.createdAt));
  return candidates;
}

String? _normalizedWorkspaceThreadTopic(String? topic) {
  final value = topic
      ?.toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  return value == null || value.isEmpty ? null : value;
}

/// Extracts message hashtags that can be used as thread topics.
List<String> workspaceMessageHashtags(String value) => RegExp(
  r'(?<![\w#])#[A-Za-z][A-Za-z0-9_-]*',
).allMatches(value).map((match) => match.group(0)!).toSet().toList();

String workspaceDisplayMessageText(String value) => value.replaceFirst(
  RegExp(r'^\s*\[\[THREAD_TOPIC:\s*[^\]\r\n]+\]\]\s*', caseSensitive: false),
  '',
);

bool isWorkspaceEmptyAgentMessage(WorkspaceMessage message) =>
    isWorkspaceAgentSender(message.senderPubkey) &&
    workspaceDisplayMessageText(message.body).trim().isEmpty;

bool isWorkspaceThreadTopicRequest(WorkspaceMessage message) =>
    message.body.trim().startsWith('[[THREAD_TOPIC_REQUEST]]');

bool isWorkspaceThreadTopicResponse(WorkspaceMessage message) =>
    workspaceDisplayMessageText(message.body).trim().isEmpty &&
    RegExp(
      r'^\s*\[\[THREAD_TOPIC:',
      caseSensitive: false,
    ).hasMatch(message.body);

bool isWorkspaceThreadTopicControlMessage(WorkspaceMessage message) =>
    isWorkspaceThreadTopicRequest(message) ||
    isWorkspaceThreadTopicResponse(message);

String? workspaceRelatedThreadId(WorkspaceMessage message) {
  final match = _workspaceRelatedThreadMarker.firstMatch(message.body);
  final id = match?.group(1)?.trim();
  return id == null || id.isEmpty ? null : id;
}

bool isWorkspaceRelatedThreadControlMessage(WorkspaceMessage message) =>
    _workspaceRelatedThreadMarker.hasMatch(message.body);

bool isWorkspaceThreadCompletionControlMessage(WorkspaceMessage message) =>
    message.body.trim() == '[[THREAD_COMPLETED]]' ||
    message.body.trim() == '[[THREAD_REOPENED]]';

bool isWorkspaceHiddenMessage(WorkspaceMessage message) =>
    isWorkspaceEmptyAgentMessage(message) ||
    isWorkspaceThreadTopicControlMessage(message) ||
    isWorkspaceRelatedThreadControlMessage(message) ||
    isWorkspaceThreadCompletionControlMessage(message);

bool isWorkspaceThreadCompleted(Iterable<WorkspaceMessage> replies) {
  final controls =
      replies
          .where(isWorkspaceThreadCompletionControlMessage)
          .toList(growable: false)
        ..sort((left, right) {
          final created = left.createdAt.compareTo(right.createdAt);
          return created != 0 ? created : left.id.compareTo(right.id);
        });
  return controls.isNotEmpty &&
      controls.last.body.trim() == '[[THREAD_COMPLETED]]';
}

final _workspaceRelatedThreadMarker = RegExp(
  r'^\s*\[\[RELATED_THREAD:\s*([^\]\r\n]*)\]\]\s*$',
  caseSensitive: false,
);

/// Returns the target set by the newest append-only marker. An empty marker
/// explicitly clears an older reference.
String? workspaceActiveRelatedThreadId(
  Iterable<WorkspaceMessage> messages,
  WorkspaceMessage current,
) {
  final markers =
      messages
          .where((message) => message.parentId == current.id)
          .where(isWorkspaceRelatedThreadControlMessage)
          .toList(growable: false)
        ..sort((left, right) {
          final created = left.createdAt.compareTo(right.createdAt);
          return created != 0 ? created : left.id.compareTo(right.id);
        });
  return markers.isEmpty ? null : workspaceRelatedThreadId(markers.last);
}

/// Returns root threads whose active reference points to [current].
List<WorkspaceMessage> workspaceRelatedThreadBacklinks(
  Iterable<WorkspaceMessage> messages,
  WorkspaceMessage current,
) {
  final all = messages.toList(growable: false);
  final backlinks =
      all
          .where((candidate) => candidate.parentId == null)
          .where((candidate) => candidate.id != current.id)
          .where(
            (candidate) =>
                workspaceActiveRelatedThreadId(all, candidate) == current.id,
          )
          .toList(growable: false)
        ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  return backlinks;
}

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
  const WorkspaceChannel({
    required this.id,
    required this.name,
    this.createdBy = '',
    this.members = const [],
  });
  final String id;
  final String name;
  final String createdBy;
  final List<WorkspaceChannelMember> members;

  factory WorkspaceChannel.fromJson(Map<String, dynamic> json) =>
      WorkspaceChannel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        createdBy: json['created_by']?.toString() ?? '',
        members: (json['members'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (member) => WorkspaceChannelMember.fromJson(
                Map<String, dynamic>.from(member),
              ),
            )
            .where((member) => member.pubkey.isNotEmpty)
            .toList(growable: false),
      );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'created_by': createdBy,
    'members': members.map((member) => member.toJson()).toList(growable: false),
  };
}

class WorkspaceChannelMember {
  const WorkspaceChannelMember({required this.pubkey, this.isAdmin = false});

  final String pubkey;
  final bool isAdmin;

  factory WorkspaceChannelMember.fromJson(Map<String, dynamic> json) =>
      WorkspaceChannelMember(
        pubkey: json['pubkey']?.toString().trim() ?? '',
        isAdmin: json['is_admin'] == true,
      );

  Map<String, Object> toJson() => {'pubkey': pubkey, 'is_admin': isAdmin};
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
    this.pinned = false,
    this.attachments = const [],
    this.mentions = const [],
    this.reactions = const [],
    this.workHistory = const [],
    this.editedAt,
    this.deletedAt,
  });
  final String id;
  final String? channelId;
  final String? recipientPubkey;
  final String senderPubkey;
  final String body;
  final String? parentId;
  final bool alsoSendToMain;
  final bool pinned;
  final List<BridgeAudioReference> attachments;
  final List<WorkspaceMention> mentions;
  final List<WorkspaceReaction> reactions;
  final List<String> workHistory;
  final int? editedAt;
  final int? deletedAt;
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
        pinned: json['pinned'] == true,
        attachments: _attachments(json['attachments']),
        mentions: _mentions(json['mentions']),
        reactions: _reactions(json['reactions']),
        workHistory: (json['work_history'] as List? ?? const [])
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
        editedAt: (json['edited_at'] as num?)?.toInt(),
        deletedAt: (json['deleted_at'] as num?)?.toInt(),
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    if (channelId != null) 'channel_id': channelId,
    if (recipientPubkey != null) 'recipient_pubkey': recipientPubkey,
    'sender_pubkey': senderPubkey,
    'body': body,
    if (parentId != null) 'parent_id': parentId,
    'also_send_to_main': alsoSendToMain,
    'pinned': pinned,
    'attachments': attachments
        .map(
          (attachment) => {
            'url': attachment.url,
            'sha256': attachment.sha256,
            'size': attachment.size.toString(),
            'type': attachment.mediaType,
            if (attachment.name != null) 'name': attachment.name,
            if (attachment.encryption case final encryption?)
              'encryption': {
                'algorithm': encryption.algorithm,
                'key': encryption.key,
                'nonce': encryption.nonce,
                'plaintext_sha256': encryption.plaintextSha256,
                'plaintext_size': encryption.plaintextSize.toString(),
                'plaintext_type': encryption.plaintextMediaType,
              },
          },
        )
        .toList(growable: false),
    'mentions': mentions
        .map((mention) => mention.toJson())
        .toList(growable: false),
    'reactions': reactions
        .map(
          (reaction) => {
            'emoji': reaction.emoji,
            'sender_pubkey': reaction.senderPubkey,
          },
        )
        .toList(growable: false),
    'work_history': workHistory,
    if (editedAt != null) 'edited_at': editedAt,
    if (deletedAt != null) 'deleted_at': deletedAt,
    'created_at': createdAt,
  };
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
    this.availability = 'available',
    this.scopeMemoryBytes,
    this.scopeCpuUsageNsec,
    this.scopeTaskCount,
    this.scopeStartedAt,
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
  final String availability;
  final int? scopeMemoryBytes;
  final int? scopeCpuUsageNsec;
  final int? scopeTaskCount;
  final int? scopeStartedAt;

  String get displayLabel => switch (role) {
    'Conversation worker' || 'Round-robin worker' => 'Agent',
    'Task coordinator' || 'Round-robin coordinator' => 'Coordinator',
    _ => name,
  };

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
    availability: json['availability']?.toString() ?? 'available',
    scopeMemoryBytes: (json['scope_memory_bytes'] as num?)?.toInt(),
    scopeCpuUsageNsec: (json['scope_cpu_usage_nsec'] as num?)?.toInt(),
    scopeTaskCount: (json['scope_task_count'] as num?)?.toInt(),
    scopeStartedAt: (json['scope_started_at'] as num?)?.toInt(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'role': role,
    'traits': traits,
    'skills': skills,
    if (preset != null) 'preset': preset,
    if (openCodeProviderId != null) 'opencode_provider_id': openCodeProviderId,
    if (openCodeProviderName != null)
      'opencode_provider_name': openCodeProviderName,
    if (openCodeModelId != null) 'opencode_model_id': openCodeModelId,
    if (openCodeModelName != null) 'opencode_model_name': openCodeModelName,
    if (openCodeAgent != null) 'opencode_agent': openCodeAgent,
    if (workdir != null) 'workdir': workdir,
    'restart_on_failure': restartOnFailure,
    if (openCodeSessionId != null) 'opencode_session_id': openCodeSessionId,
    'session_status': sessionStatus,
    if (sessionError != null) 'session_error': sessionError,
    'created_at': createdAt,
    if (initializedAt != null) 'initialized_at': initializedAt,
    if (inputTokens != null) 'input_tokens': inputTokens,
    if (outputTokens != null) 'output_tokens': outputTokens,
    'availability': availability,
    if (scopeMemoryBytes != null) 'scope_memory_bytes': scopeMemoryBytes,
    if (scopeCpuUsageNsec != null) 'scope_cpu_usage_nsec': scopeCpuUsageNsec,
    if (scopeTaskCount != null) 'scope_task_count': scopeTaskCount,
    if (scopeStartedAt != null) 'scope_started_at': scopeStartedAt,
  };
}

class WorkspaceBoardColumn {
  WorkspaceBoardColumn.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      rank = json['rank'] as int? ?? 0,
      wipLimit = json['wip_limit'] as int?,
      archivedAt = json['archived_at'] as int?;

  final String id;
  final String name;
  final int rank;
  final int? wipLimit;
  final int? archivedAt;

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'rank': rank,
    'wip_limit': wipLimit, 'archived_at': archivedAt,
  };
}

class WorkspaceBoardCard {
  WorkspaceBoardCard.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      title = json['title'] as String,
      description = json['description'] as String? ?? '',
      columnId = json['column_id'] as String,
      rank = json['rank'] as int? ?? 0,
      priority = json['priority'] as String? ?? 'none',
      estimate = json['estimate'] as int?,
      dueAt = json['due_at'] as int?,
      createdBy = json['created_by'] as String? ?? '',
      createdAt = json['created_at'] as int? ?? 0,
      updatedAt = json['updated_at'] as int? ?? 0,
      archivedAt = json['archived_at'] as int?,
      sourceThreadId = json['source_thread_id'] as String?;

  final String id, title, description, columnId, priority, createdBy;
  final int rank, createdAt, updatedAt;
  final int? estimate, dueAt, archivedAt;
  final String? sourceThreadId;

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'description': description,
    'column_id': columnId, 'rank': rank, 'priority': priority,
    'estimate': estimate, 'due_at': dueAt, 'created_by': createdBy,
    'created_at': createdAt, 'updated_at': updatedAt,
    'archived_at': archivedAt, 'source_thread_id': sourceThreadId,
  };
}

class WorkspaceBoardTask {
  WorkspaceBoardTask({
    required this.id,
    required this.title,
    required this.conversationKey,
    required this.instruction,
    required Iterable<String> folderScope,
    required this.schedule,
    required this.state,
    String? boardColumn,
    this.nextRunAt,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.rootMessageId,
    this.agentId,
  }) : folderScope = List.unmodifiable(folderScope),
       boardColumn = boardColumn ?? state;

  final String id;
  final String title;
  final String conversationKey;
  final String instruction;
  final List<String> folderScope;
  final String schedule;
  final String state;
  final String boardColumn;
  final int? nextRunAt;
  final String createdBy;
  final int createdAt;
  final int updatedAt;
  final String? rootMessageId;
  final String? agentId;

  factory WorkspaceBoardTask.fromJson(Map<String, dynamic> json) =>
      WorkspaceBoardTask(
        id: json['id']?.toString().trim() ?? '',
        title: json['title']?.toString().trim() ?? '',
        conversationKey: json['conversation_key']?.toString().trim() ?? '',
        instruction: json['instruction']?.toString() ?? '',
        folderScope: (json['folder_scope'] as List? ?? const [])
            .map((path) => path.toString().trim())
            .where((path) => path.isNotEmpty),
        schedule: json['schedule']?.toString().trim() ?? '',
        state: json['state']?.toString().trim() ?? '',
        boardColumn: json['board_column']?.toString().trim(),
        nextRunAt: (json['next_run_at'] as num?)?.toInt(),
        createdBy: json['created_by']?.toString().trim() ?? '',
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
        rootMessageId: json['root_message_id']?.toString().trim(),
        agentId: json['agent_id']?.toString().trim(),
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'conversation_key': conversationKey,
    'instruction': instruction,
    'folder_scope': folderScope,
    'schedule': schedule,
    'state': state,
    'board_column': boardColumn,
    if (nextRunAt != null) 'next_run_at': nextRunAt,
    'created_by': createdBy,
    'created_at': createdAt,
    'updated_at': updatedAt,
    if (rootMessageId != null) 'root_message_id': rootMessageId,
    if (agentId != null) 'agent_id': agentId,
  };
}

class WorkspaceBoardTimelineEntry {
  const WorkspaceBoardTimelineEntry({
    required this.id,
    required this.taskId,
    required this.state,
    required this.detail,
    required this.createdAt,
  });

  final String id;
  final String taskId;
  final String state;
  final String detail;
  final int createdAt;

  factory WorkspaceBoardTimelineEntry.fromJson(Map<String, dynamic> json) =>
      WorkspaceBoardTimelineEntry(
        id: json['id']?.toString().trim() ?? '',
        taskId: json['task_id']?.toString().trim() ?? '',
        state: json['state']?.toString().trim() ?? '',
        detail: json['detail']?.toString() ?? '',
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'task_id': taskId,
    'state': state,
    'detail': detail,
    'created_at': createdAt,
  };
}

class WorkspaceConversationAgent {
  const WorkspaceConversationAgent({
    required this.agentId,
    this.channelId,
    this.memberPubkey,
    this.peerPubkey,
    this.parentId,
    this.folderScope = const [],
  });
  final String agentId;
  final String? channelId;
  final String? memberPubkey;
  final String? peerPubkey;
  final String? parentId;
  final List<String> folderScope;

  factory WorkspaceConversationAgent.fromJson(Map<String, dynamic> json) =>
      WorkspaceConversationAgent(
        agentId: json['agent_id']?.toString() ?? '',
        channelId: json['channel_id']?.toString(),
        memberPubkey: json['member_pubkey']?.toString(),
        peerPubkey: json['peer_pubkey']?.toString(),
        parentId: json['parent_id']?.toString(),
        folderScope: (json['folder_scope'] as List? ?? const [])
            .map((path) => path.toString().trim())
            .where((path) => path.isNotEmpty)
            .toList(growable: false),
      );

  Map<String, Object?> toJson() => {
    'agent_id': agentId,
    if (channelId != null) 'channel_id': channelId,
    if (memberPubkey != null) 'member_pubkey': memberPubkey,
    if (peerPubkey != null) 'peer_pubkey': peerPubkey,
    if (parentId != null) 'parent_id': parentId,
    'folder_scope': folderScope,
  };
}

class WorkspaceConversationPreprompt {
  const WorkspaceConversationPreprompt({
    required this.preprompt,
    this.folderScope = const [],
    this.agentRoutingEnabled = false,
    this.model,
    this.channelId,
    this.memberPubkey,
    this.peerPubkey,
  });
  final String preprompt;
  final List<String> folderScope;
  final bool agentRoutingEnabled;
  final String? model;
  final String? channelId;
  final String? memberPubkey;
  final String? peerPubkey;

  factory WorkspaceConversationPreprompt.fromJson(Map<String, dynamic> json) =>
      WorkspaceConversationPreprompt(
        preprompt: json['preprompt']?.toString() ?? '',
        folderScope: (json['folder_scope'] as List? ?? const [])
            .map((path) => path.toString().trim())
            .where((path) => path.isNotEmpty)
            .toList(growable: false),
        agentRoutingEnabled: json['agent_routing_enabled'] == true,
        model: json['model']?.toString(),
        channelId: json['channel_id']?.toString(),
        memberPubkey: json['member_pubkey']?.toString(),
        peerPubkey: json['peer_pubkey']?.toString(),
      );

  Map<String, Object?> toJson() => {
    'preprompt': preprompt,
    'folder_scope': folderScope,
    'agent_routing_enabled': agentRoutingEnabled,
    if (model != null) 'model': model,
    if (channelId != null) 'channel_id': channelId,
    if (memberPubkey != null) 'member_pubkey': memberPubkey,
    if (peerPubkey != null) 'peer_pubkey': peerPubkey,
  };
}

class WorkspaceTyping {
  const WorkspaceTyping({
    required this.senderPubkey,
    this.agentId,
    this.agentName,
    this.stage,
    this.workHistory = const [],
    this.startedAt,
    this.channelId,
    this.recipientPubkey,
    this.memberPubkey,
    this.peerPubkey,
    this.parentId,
    required this.expiresAt,
  });

  final String senderPubkey;
  final String? agentId;
  final String? agentName;
  final String? stage;
  final List<String> workHistory;
  final int? startedAt;
  final String? channelId;
  final String? recipientPubkey;
  final String? memberPubkey;
  final String? peerPubkey;
  final String? parentId;
  final int expiresAt;

  factory WorkspaceTyping.fromJson(Map<String, dynamic> json) =>
      WorkspaceTyping(
        senderPubkey: json['sender_pubkey']?.toString() ?? '',
        agentId: json['agent_id']?.toString(),
        agentName: json['agent_name']?.toString(),
        stage: json['stage']?.toString(),
        workHistory: (json['work_history'] as List? ?? const [])
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
        startedAt: (json['started_at'] as num?)?.toInt(),
        channelId: json['channel_id']?.toString(),
        recipientPubkey: json['recipient_pubkey']?.toString(),
        memberPubkey: json['member_pubkey']?.toString(),
        peerPubkey: json['peer_pubkey']?.toString(),
        parentId: json['parent_id']?.toString(),
        expiresAt: (json['expires_at'] as num?)?.toInt() ?? 0,
      );
}

List<WorkspaceMention> workspaceAgentMentions(Iterable<WorkspaceAgent> agents) {
  final entries = agents.toList(growable: false);
  final counts = <String, int>{};
  for (final agent in entries) {
    counts.update(agent.displayLabel, (count) => count + 1, ifAbsent: () => 1);
  }
  final indexes = <String, int>{};
  return entries
      .map((agent) {
        final label = agent.displayLabel;
        final index = indexes.update(
          label,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        return WorkspaceMention(
          kind: 'agent',
          id: agent.id,
          label: counts[label] == 1 ? label : '$label $index',
        );
      })
      .toList(growable: false);
}

List<WorkspaceMention> workspaceConversationMentions(
  WorkspaceState workspace, {
  String? channelId,
  String? memberPubkey,
  String? peerPubkey,
  String? parentId,
}) {
  final memberships = workspace.conversationAgents.where((membership) {
    if (channelId != null) return membership.channelId == channelId;
    if (memberPubkey == null || peerPubkey == null) return false;
    return membership.channelId == null &&
        ((membership.memberPubkey == memberPubkey &&
                membership.peerPubkey == peerPubkey) ||
            (membership.memberPubkey == peerPubkey &&
                membership.peerPubkey == memberPubkey));
  }).toList();
  final assignedAgentIds = memberships
      .map((membership) => membership.agentId)
      .toSet();
  final agents = workspace.agents.where(
    (agent) => assignedAgentIds.contains(agent.id),
  );
  return [
    ...workspaceCoordinatorMentions(agents),
    if (parentId != null)
      for (final agent in agents)
        if (agent.role != 'Task coordinator' &&
            agent.role != 'Round-robin coordinator' &&
            memberships.any(
              (membership) =>
                  membership.agentId == agent.id &&
                  membership.parentId == parentId,
            ))
          WorkspaceMention(kind: 'agent', id: agent.id, label: 'ThreadAgent'),
  ];
}

List<WorkspaceMention> workspaceCoordinatorMentions(
  Iterable<WorkspaceAgent> agents,
) => agents
    .where(
      (agent) =>
          agent.role == 'Task coordinator' ||
          agent.role == 'Round-robin coordinator',
    )
    .map(
      (agent) =>
          WorkspaceMention(kind: 'agent', id: agent.id, label: 'Coordinator'),
    )
    .toList(growable: false);

class WorkspaceState {
  static const _maxMessagesPerConversation = 500;
  static const _typingStopGrace = Duration(seconds: 30);

  /// Last worker-authoritative workspace revision applied to this state.
  int revision = 0;
  List<WorkspaceChannel> channels = [];
  List<String> members = [];
  final Map<String, String> memberNames = {};
  final Set<String> memberAdmins = {};
  final Map<String, int> memberJoinedAt = {};
  final Map<String, List<WorkspaceMessage>> messages = {};
  List<WorkspaceAgent> agents = [];
  List<WorkspaceConversationAgent> conversationAgents = [];
  List<WorkspaceConversationPreprompt> conversationPreprompts = [];
  List<WorkspaceBoardTask> boardTasks = [];
  List<WorkspaceBoardColumn> boardColumns = [];
  List<WorkspaceBoardCard> boardCards = [];
  List<WorkspaceBoardTimelineEntry> boardTimelineEntries = [];
  final Map<String, WorkspaceTyping> typing = {};
  final Map<String, _WorkspaceHistoryTransfer> _historyTransfers = {};
  int? historySince;
  int? _completedHistorySince;

  void clear() {
    revision = 0;
    channels = [];
    members = [];
    memberNames.clear();
    memberAdmins.clear();
    memberJoinedAt.clear();
    messages.clear();
    agents = [];
    conversationAgents = [];
    conversationPreprompts = [];
    boardTasks = [];
    boardColumns = [];
    boardCards = [];
    boardTimelineEntries = [];
    typing.clear();
    _historyTransfers.clear();
    historySince = null;
    _completedHistorySince = null;
  }

  Map<String, Object> toSnapshotJson() => {
    'action': 'snapshot',
    'revision': revision,
    if (historySince != null) 'history_since': historySince!,
    'channels': channels
        .map((channel) => channel.toJson())
        .toList(growable: false),
    'members': [
      for (final member in members)
        {
          'pubkey': member,
          'display_name': memberNames[member] ?? '',
          'is_admin': memberAdmins.contains(member),
          'joined_at': memberJoinedAt[member] ?? 0,
        },
    ],
    'messages': [
      for (final conversation in messages.values)
        for (final message in conversation)
          if (!isWorkspaceThreadTopicRequest(message)) message.toJson(),
    ],
    'agents': agents.map((agent) => agent.toJson()).toList(growable: false),
    'conversation_agents': conversationAgents
        .map((agent) => agent.toJson())
        .toList(growable: false),
    'conversation_preprompts': conversationPreprompts
        .map((preprompt) => preprompt.toJson())
        .toList(growable: false),
    'board_tasks': boardTasks
        .map((task) => task.toJson())
        .toList(growable: false),
    'board_columns': boardColumns.map((column) => column.toJson()).toList(),
    'board_cards': boardCards.map((card) => card.toJson()).toList(),
    'board_timeline_entries': boardTimelineEntries
        .map((entry) => entry.toJson())
        .toList(growable: false),
  };

  List<WorkspaceMessage> apply(
    Map<String, dynamic> raw, {
    Iterable<String> localSenderIds = const [],
    bool preserveMessagesOnSnapshot = false,
  }) {
    final update = raw['workspace_update'];
    if (update is! Map) return const [];
    final data = Map<String, dynamic>.from(update);
    final incomingRevision = _revision(data['revision']);
    if (incomingRevision < revision) return const [];
    final transfer = _historyTransferAction(data['action']?.toString());
    if (transfer != null) {
      // Channel and direct-message history can span many relay frames. Show
      // each received frame instead of losing the entire history if one frame
      // is delayed or missing. Snapshots still need atomic replacement.
      if (transfer.action != 'snapshot' &&
          _historySince(transfer.action) == null) {
        data['action'] = transfer.action;
        return apply(
          {'workspace_update': data},
          localSenderIds: localSenderIds,
          preserveMessagesOnSnapshot: preserveMessagesOnSnapshot,
        );
      }
      final pending = _historyTransfers.putIfAbsent(
        transfer.id,
        () => _WorkspaceHistoryTransfer(transfer.total),
      );
      if (pending.total != transfer.total) return const [];
      pending.chunks.putIfAbsent(transfer.sequence, () => data);
      if (transfer.sequence == 0 && transfer.action == 'snapshot') {
        // Header metadata is useful immediately, but must not clear cached rows
        // while a slow relay is still delivering the message chunks.
        final header = Map<String, dynamic>.from(data)
          ..['action'] = 'snapshot_header';
        apply(
          {'workspace_update': header},
          localSenderIds: localSenderIds,
          preserveMessagesOnSnapshot: preserveMessagesOnSnapshot,
        );
      }
      if (pending.chunks.length != pending.total) return const [];
      _historyTransfers.remove(transfer.id);
      final chunks = <Map<String, dynamic>>[];
      for (var sequence = 0; sequence < pending.total; sequence++) {
        final chunk = pending.chunks[sequence];
        if (chunk == null) return const [];
        chunks.add(chunk);
      }
      // Apply the transfer atomically. Applying an empty snapshot header before
      // its message chunks would otherwise clear channels and agents in the UI.
      final header = Map<String, dynamic>.from(chunks.first);
      final action = _historyTransferAction(header['action']?.toString());
      if (action == null) return const [];
      header['action'] = action.action;
      for (final field in [
        'channels',
        'members',
        'messages',
        'agents',
        'conversation_agents',
        'conversation_preprompts',
        'board_tasks',
        'board_columns',
        'board_cards',
        'board_timeline_entries',
      ]) {
        header[field] = [
          for (final chunk in chunks) ...(chunk[field] as List? ?? const []),
        ];
      }
      final addedMessages = apply(
        {'workspace_update': header},
        localSenderIds: localSenderIds,
        preserveMessagesOnSnapshot: preserveMessagesOnSnapshot,
      );
      final since = _historySince(action.action);
      if (since != null) {
        historySince = since;
        _completedHistorySince = since;
      }
      return addedMessages;
    }
    if (incomingRevision > revision) revision = incomingRevision;
    final snapshotSince = _historySinceValue(data['history_since']);
    if (snapshotSince != null) historySince = snapshotSince;
    final addedMessages = <WorkspaceMessage>[];
    final isSnapshot = data['action'] == 'snapshot';
    final isSnapshotHeader = data['action'] == 'snapshot_header';
    final replacesBoard = isSnapshot || data['action'] == 'board_updated';
    final isPartialSnapshot =
        isSnapshot &&
        ((data['messages'] as List?)?.isEmpty ?? true) &&
        ((data['agents'] as List?)?.isEmpty ?? true);
    final hasAgentSnapshot = data['agents'] is List;
    final hasConversationAgentSnapshot = data['conversation_agents'] is List;
    final hasPrepromptSnapshot = data['conversation_preprompts'] is List;
    final hasBoardTaskSnapshot = data['board_tasks'] is List;
    final hasBoardTimelineSnapshot = data['board_timeline_entries'] is List;
    if (isSnapshot) {
      // Large snapshots arrive as an empty header followed by message chunks.
      // Keep visible rows until those chunks arrive, including local rows that
      // have not yet returned through a relay.
      final localMessages = <String, List<WorkspaceMessage>>{};
      final currentChannelIds = _channels(
        data['channels'],
      ).map((channel) => channel.id).toSet();
      if (!isPartialSnapshot) {
        for (final entry in messages.entries) {
          final local = entry.value
              .where(
                (message) =>
                    (message.channelId == null ||
                        currentChannelIds.isEmpty ||
                        currentChannelIds.contains(message.channelId)) &&
                    // Worker snapshots are intentionally bounded per
                    // conversation, so replacing this cache would discard
                    // older thread roots and replies that the client already
                    // loaded on demand.
                    true,
              )
              .toList(growable: false);
          if (local.isNotEmpty) localMessages[entry.key] = local;
        }
      }
      channels = [];
      members = [];
      memberNames.clear();
      memberAdmins.clear();
      memberJoinedAt.clear();
      if (!isPartialSnapshot) {
        messages
          ..clear()
          ..addAll(localMessages);
      }
      if (!isPartialSnapshot &&
          hasAgentSnapshot &&
          _agents(data['agents']).isNotEmpty) {
        agents = [];
      }
      if (!isPartialSnapshot && hasConversationAgentSnapshot) {
        conversationAgents = [];
      }
      if (!isPartialSnapshot && hasPrepromptSnapshot) {
        conversationPreprompts = [];
      }
      if (!isPartialSnapshot && hasBoardTaskSnapshot) boardTasks = [];
      if (!isPartialSnapshot && hasBoardTimelineSnapshot) {
        boardTimelineEntries = [];
      }
      typing.clear();
    }
    final incomingTyping = data['typing'];
    if (incomingTyping is Map) {
      var status = WorkspaceTyping.fromJson(
        Map<String, dynamic>.from(incomingTyping),
      );
      final key = _typingKey(status);
      final previous = typing[key];
      if (status.senderPubkey.isNotEmpty && status.expiresAt > 0) {
        // FIPS progress and Nostr lease updates can arrive out of order. A
        // generic lease must not erase a newer, useful agent progress stage.
        if ((status.stage == null || _isFinishedStep(status.stage)) &&
            previous?.stage != null) {
          status = WorkspaceTyping(
            senderPubkey: status.senderPubkey,
            agentId: status.agentId,
            agentName: status.agentName,
            stage: previous!.stage,
            workHistory: previous.workHistory,
            startedAt: previous.startedAt,
            channelId: status.channelId,
            recipientPubkey: status.recipientPubkey,
            memberPubkey: status.memberPubkey,
            peerPubkey: status.peerPubkey,
            parentId: status.parentId,
            expiresAt: status.expiresAt,
          );
        }
        typing[key] = status;
      } else if (status.stage == '') {
        typing.remove(key);
      } else if (previous != null) {
        // A stopped lease can arrive before its final message on another relay
        // update. Keep the preview until that message replaces it.
        typing[key] = WorkspaceTyping(
          senderPubkey: previous.senderPubkey,
          agentId: previous.agentId,
          agentName: previous.agentName,
          stage: previous.stage,
          workHistory: previous.workHistory,
          startedAt: previous.startedAt,
          channelId: previous.channelId,
          recipientPubkey: previous.recipientPubkey,
          memberPubkey: previous.memberPubkey,
          peerPubkey: previous.peerPubkey,
          parentId: previous.parentId,
          expiresAt:
              DateTime.now().millisecondsSinceEpoch ~/ 1000 +
              _typingStopGrace.inSeconds,
        );
      } else {
        typing.remove(key);
      }
    }
    final incomingConversationAgents = _conversationAgents(
      data['conversation_agents'],
    );
    if ((isSnapshot && !isPartialSnapshot && hasConversationAgentSnapshot) ||
        (isSnapshotHeader && incomingConversationAgents.isNotEmpty) ||
        ((data['action'] == 'channel_created' ||
                data['action'] == 'message_created') &&
            incomingConversationAgents.isNotEmpty) ||
        (data['action'] == 'agent_created' &&
            incomingConversationAgents.isNotEmpty) ||
        data['action'] == 'agents' ||
        data['action'] == 'opencode_debug_channel' ||
        data['action'] == 'conversation_agents_updated' ||
        data['action'] == 'agent_deleted') {
      conversationAgents = incomingConversationAgents;
    }
    final incomingPreprompts = _conversationPreprompts(
      data['conversation_preprompts'],
    );
    if ((isSnapshot && hasPrepromptSnapshot) ||
        (isSnapshotHeader && incomingPreprompts.isNotEmpty) ||
        data['action'] == 'conversation_preprompt_updated' ||
        data['action'] == 'workspace_default_agent_prompt_updated' ||
        data['action'] == 'workspace_default_model_updated') {
      conversationPreprompts = incomingPreprompts;
    }
    if (replacesBoard && hasBoardTaskSnapshot && !isSnapshotHeader) {
      boardTasks = _boardTasks(data['board_tasks']);
    }
    if (replacesBoard) {
      if (data['board_columns'] case final List columns) {
        boardColumns = columns.whereType<Map>().map((json) => WorkspaceBoardColumn.fromJson(Map<String, dynamic>.from(json))).toList()
          ..sort((a, b) => a.rank.compareTo(b.rank));
      }
      if (data['board_cards'] case final List cards) {
        boardCards = cards.whereType<Map>().map((json) => WorkspaceBoardCard.fromJson(Map<String, dynamic>.from(json))).toList()
          ..sort((a, b) => a.rank.compareTo(b.rank));
      }
    }
    if (replacesBoard && hasBoardTimelineSnapshot && !isSnapshotHeader) {
      boardTimelineEntries = _boardTimelineEntries(
        data['board_timeline_entries'],
      );
    }
    final incomingAgents = _agents(data['agents']);
    final replacesAgentDirectory =
        isSnapshot &&
        !isPartialSnapshot &&
        hasAgentSnapshot &&
        (incomingAgents.isNotEmpty || agents.isEmpty);
    if (replacesAgentDirectory ||
        (isSnapshotHeader && incomingAgents.isNotEmpty) ||
        data['action'] == 'agent_deleted') {
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
      if (isSnapshot ||
          isSnapshotHeader ||
          data['action'] == 'member_removed') {
        members = incomingMembers.keys.toList();
        memberNames.clear();
        memberAdmins.clear();
        memberJoinedAt.clear();
      } else {
        final knownMembers = members.toSet()..addAll(incomingMembers.keys);
        members = knownMembers.toList();
      }
      for (final entry in incomingMembers.entries) {
        if (entry.value.displayName.isEmpty) {
          memberNames.remove(entry.key);
        } else {
          memberNames[entry.key] = entry.value.displayName;
        }
        if (entry.value.isAdmin) {
          memberAdmins.add(entry.key);
        } else {
          memberAdmins.remove(entry.key);
        }
        if (entry.value.joinedAt > 0) {
          memberJoinedAt[entry.key] = entry.value.joinedAt;
        }
      }
    }
    final incomingMessages = _messages(data['messages']);
    final linkedBoardRoots = boardCards.map((card) => card.sourceThreadId).nonNulls.toSet();
    if (data['action'] == 'message_created') {
      for (final message in incomingMessages) {
        for (final entry in typing.entries.toList()) {
          final status = entry.value;
          if (!_typingMatchesMessage(status, message)) continue;
          if (status.agentId == null) {
            typing.remove(entry.key);
            continue;
          }
          typing.remove(entry.key);
        }
      }
    }
    for (final message in incomingMessages) {
      final key = message.channelId ?? _messageDirectKey(message);
      final current = {for (final item in messages[key] ?? []) item.id: item};
      if (!current.containsKey(message.id)) addedMessages.add(message);
      current[message.id] = message;
      final ordered = current.values.cast<WorkspaceMessage>().toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (ordered.length > _maxMessagesPerConversation) {
        final cutoff = ordered.length - _maxMessagesPerConversation;
        messages[key] = [
          ...ordered.take(cutoff).where((message) => linkedBoardRoots.contains(message.id)),
          ...ordered.skip(cutoff),
        ];
      } else {
        messages[key] = ordered;
      }
    }
    return addedMessages;
  }

  int? takeCompletedHistorySince() {
    final since = _completedHistorySince;
    _completedHistorySince = null;
    return since;
  }

  static bool _isFinishedStep(String? stage) => RegExp(
    r'\bfinished a step\.?$',
    caseSensitive: false,
  ).hasMatch(stage?.trim() ?? '');

  static String directKey(String one, String? two) => _directKey(one, two);
  String conversationKeyForMessage(WorkspaceMessage message) =>
      message.channelId ?? _messageDirectKey(message);

  Map<String, Set<String>> missingThreadRootsByConversation(
    Iterable<WorkspaceMessage> incoming,
  ) {
    final roots = <String, Set<String>>{};
    for (final message in incoming) {
      final parentId = message.parentId;
      if (parentId == null) continue;
      final conversationKey = conversationKeyForMessage(message);
      final hasRoot = (messages[conversationKey] ?? const <WorkspaceMessage>[])
          .any((candidate) => candidate.id == parentId);
      if (!hasRoot) {
        roots.putIfAbsent(conversationKey, () => {}).add(parentId);
      }
    }
    return roots;
  }

  static String _typingKey(WorkspaceTyping status) => [
    status.senderPubkey,
    status.channelId ?? '',
    status.memberPubkey ?? '',
    status.peerPubkey ?? '',
    status.recipientPubkey ?? '',
    status.parentId ?? '',
  ].join(':');
  static bool _typingMatchesMessage(
    WorkspaceTyping status,
    WorkspaceMessage message,
  ) {
    if (status.senderPubkey != message.senderPubkey) return false;
    if (status.parentId != message.parentId) return false;
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
    String? parentId,
    bool includeThreadTyping = false,
    required int nowSeconds,
  }) {
    typing.removeWhere((_, status) => status.expiresAt <= nowSeconds);
    return typing.values
        .where((status) {
          if (!includeThreadTyping && status.parentId != parentId) return false;
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

  String get defaultAgentPrompt {
    for (final prompt in conversationPreprompts) {
      if (prompt.channelId == '') return prompt.preprompt;
    }
    return '';
  }

  String? get defaultModel {
    for (final prompt in conversationPreprompts) {
      if (prompt.channelId == '') return prompt.model;
    }
    return null;
  }

  String? conversationModel({
    required String? channelId,
    required String ownPubkey,
    required String? peerPubkey,
  }) {
    for (final prompt in conversationPreprompts) {
      if (channelId != null && prompt.channelId == channelId)
        return prompt.model;
      if (channelId == null &&
          {prompt.memberPubkey, prompt.peerPubkey}.contains(ownPubkey) &&
          {prompt.memberPubkey, prompt.peerPubkey}.contains(peerPubkey)) {
        return prompt.model;
      }
    }
    return null;
  }

  List<String> conversationFolderScope({
    required String? channelId,
    required String ownPubkey,
    required String? peerPubkey,
  }) {
    for (final prompt in conversationPreprompts) {
      if (channelId != null && prompt.channelId == channelId) {
        return prompt.folderScope;
      }
      if (channelId == null &&
          {prompt.memberPubkey, prompt.peerPubkey}.contains(ownPubkey) &&
          {prompt.memberPubkey, prompt.peerPubkey}.contains(peerPubkey)) {
        return prompt.folderScope;
      }
    }
    return const [];
  }

  bool conversationAgentRoutingEnabled({
    required String? channelId,
    required String ownPubkey,
    required String? peerPubkey,
  }) {
    for (final prompt in conversationPreprompts) {
      if (channelId != null && prompt.channelId == channelId) {
        return prompt.agentRoutingEnabled;
      }
      if (channelId == null &&
          {prompt.memberPubkey, prompt.peerPubkey}.contains(ownPubkey) &&
          {prompt.memberPubkey, prompt.peerPubkey}.contains(peerPubkey)) {
        return prompt.agentRoutingEnabled;
      }
    }
    return false;
  }

  List<String> directPeers(String ownPubkey) {
    final peers = <String>{};
    for (final membership in conversationAgents) {
      if (membership.channelId == null &&
          membership.memberPubkey == ownPubkey &&
          membership.peerPubkey?.startsWith('agent:') == true) {
        peers.add(membership.peerPubkey!);
      }
    }
    for (final conversation in messages.values) {
      for (final message in conversation) {
        if (message.channelId != null || isWorkspaceHiddenMessage(message)) {
          continue;
        }
        if (message.senderPubkey == ownPubkey &&
            message.recipientPubkey != null &&
            message.recipientPubkey != ownPubkey) {
          peers.add(message.recipientPubkey!);
        } else if (message.recipientPubkey == ownPubkey &&
            message.senderPubkey != ownPubkey &&
            !isWorkspaceAgentSender(message.senderPubkey)) {
          peers.add(message.senderPubkey);
        } else if (message.recipientPubkey == ownPubkey &&
            isWorkspaceAgentSender(message.senderPubkey) &&
            !isNativeWorkspaceAgentSender(message.senderPubkey)) {
          peers.add(message.senderPubkey);
        }
      }
    }
    return peers.toList()..sort();
  }

  Set<String> removeSelfConversation(String ownPubkey) {
    final conversationKey = _directKey(ownPubkey, ownPubkey);
    final messageIds = (messages.remove(conversationKey) ?? const [])
        .map((message) => message.id)
        .toSet();
    typing.removeWhere(
      (_, status) =>
          status.channelId == null &&
          ((status.senderPubkey == ownPubkey &&
                  status.recipientPubkey == ownPubkey) ||
              (status.memberPubkey == ownPubkey &&
                  status.peerPubkey == ownPubkey)),
    );
    return messageIds;
  }

  int channelHumanMemberCount(String channelId) {
    for (final channel in channels) {
      if (channel.id == channelId) {
        return channel.members
            .where((member) => !member.pubkey.startsWith('agent:'))
            .length;
      }
    }
    return 0;
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

  static Map<String, ({String displayName, bool isAdmin, int joinedAt})>
  _members(Object? raw) {
    if (raw is! List) return {};
    final members =
        <String, ({String displayName, bool isAdmin, int joinedAt})>{};
    for (final member in raw) {
      if (member is Map &&
          member['pubkey']?.toString().trim().isNotEmpty == true) {
        members[member['pubkey'].toString().trim()] = (
          displayName: member['display_name']?.toString().trim() ?? '',
          isAdmin: member['is_admin'] == true,
          joinedAt: (member['joined_at'] as num?)?.toInt() ?? 0,
        );
      } else if (member is String && member.trim().isNotEmpty) {
        members[member.trim()] = (displayName: '', isAdmin: false, joinedAt: 0);
      }
    }
    return members;
  }

  static int _revision(Object? value) => switch (value) {
    num() => value.toInt(),
    String() => int.tryParse(value) ?? 0,
    _ => 0,
  };

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
  static List<WorkspaceBoardTask> _boardTasks(Object? raw) => raw is List
      ? raw
            .whereType<Map>()
            .map(
              (item) =>
                  WorkspaceBoardTask.fromJson(Map<String, dynamic>.from(item)),
            )
            .where((item) => item.id.isNotEmpty)
            .toList(growable: false)
      : [];
  static List<WorkspaceBoardTimelineEntry> _boardTimelineEntries(Object? raw) =>
      raw is List
      ? raw
            .whereType<Map>()
            .map(
              (item) => WorkspaceBoardTimelineEntry.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .where((item) => item.id.isNotEmpty && item.taskId.isNotEmpty)
            .toList(growable: false)
      : [];
}
