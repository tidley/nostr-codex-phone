import 'dart:convert';

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

class WorkspaceMessage {
  const WorkspaceMessage({
    required this.id,
    required this.senderPubkey,
    required this.body,
    required this.createdAt,
    this.channelId,
    this.recipientPubkey,
    this.parentId,
  });
  final String id;
  final String? channelId;
  final String? recipientPubkey;
  final String senderPubkey;
  final String body;
  final String? parentId;
  final int createdAt;

  factory WorkspaceMessage.fromJson(Map<String, dynamic> json) =>
      WorkspaceMessage(
        id: json['id']?.toString() ?? '',
        channelId: json['channel_id']?.toString(),
        recipientPubkey: json['recipient_pubkey']?.toString(),
        senderPubkey: json['sender_pubkey']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        parentId: json['parent_id']?.toString(),
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      );
}

class WorkspaceState {
  List<WorkspaceChannel> channels = [];
  List<String> members = [];
  final Map<String, String> memberNames = {};
  final Map<String, List<WorkspaceMessage>> messages = {};

  void apply(Map<String, dynamic> raw) {
    final update = raw['workspace_update'];
    if (update is! Map) return;
    final data = Map<String, dynamic>.from(update);
    final isSnapshot = data['action'] == 'snapshot';
    if (isSnapshot) {
      channels = [];
      members = [];
      memberNames.clear();
      messages.clear();
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
    for (final message in _messages(data['messages'])) {
      final key =
          message.channelId ??
          _directKey(message.senderPubkey, message.recipientPubkey);
      final current = {for (final item in messages[key] ?? []) item.id: item};
      current[message.id] = message;
      messages[key] = current.values.cast<WorkspaceMessage>().toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
  }

  static String directKey(String one, String? two) => _directKey(one, two);
  String? channelName(String id) {
    for (final channel in channels) {
      if (channel.id == id && channel.name.isNotEmpty) return channel.name;
    }
    return null;
  }

  static String _directKey(String one, String? two) =>
      ([one, two ?? '']..sort()).join(':');
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
}
