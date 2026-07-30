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
  final Map<String, List<WorkspaceMessage>> messages = {};

  void apply(Map<String, dynamic> raw) {
    final update = raw['workspace_update'];
    if (update is! Map) return;
    final data = Map<String, dynamic>.from(update);
    final incomingChannels = _channels(data['channels']);
    if (incomingChannels.isNotEmpty) {
      final byId = {for (final channel in channels) channel.id: channel};
      for (final channel in incomingChannels) {
        byId[channel.id] = channel;
      }
      channels = byId.values.toList();
    }
    final incomingMembers = _strings(data['members']);
    if (incomingMembers.isNotEmpty) members = incomingMembers;
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
  static String _directKey(String one, String? two) =>
      ([one, two ?? '']..sort()).join(':');
  static List<String> _strings(Object? raw) => raw is List
      ? raw
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList()
      : [];
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
