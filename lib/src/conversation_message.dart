import 'package:nostr_codex_phone/src/rust/api/nostr.dart';

enum MessageDirection { incoming, outgoing }

class ConversationMessage {
  const ConversationMessage({
    required this.direction,
    required this.kind,
    required this.text,
    required this.eventId,
    required this.timestamp,
    this.audio,
  });

  final MessageDirection direction;
  final String kind;
  final String text;
  final String eventId;
  final DateTime timestamp;
  final BridgeAudioReference? audio;

  Map<String, dynamic> toJson() => {
    'direction': direction == MessageDirection.incoming
        ? 'incoming'
        : 'outgoing',
    'kind': kind,
    'text': text,
    'eventId': eventId,
    'timestamp': timestamp.toIso8601String(),
    if (audio != null) 'audio': _serializeBridgeAudioReference(audio!),
  };

  static ConversationMessage? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final direction = _decodeDirection(raw['direction']);
    final kind = raw['kind']?.toString().trim();
    final text = raw['text']?.toString() ?? '';
    final eventId = raw['eventId']?.toString() ?? '';
    final timestampRaw = raw['timestamp']?.toString() ?? '';
    final timestamp = DateTime.tryParse(timestampRaw);
    if (kind == null || kind.isEmpty) return null;
    return ConversationMessage(
      direction: direction,
      kind: kind,
      text: text,
      eventId: eventId,
      timestamp: timestamp ?? DateTime.now(),
      audio: _deserializeBridgeAudioReference(raw['audio']),
    );
  }

  static MessageDirection _decodeDirection(dynamic raw) {
    final direction = raw?.toString();
    if (direction == 'incoming') return MessageDirection.incoming;
    return MessageDirection.outgoing;
  }
}

int compareConversationMessagesChronological(
  ConversationMessage left,
  ConversationMessage right,
) {
  final pendingCompare = _pendingPlaceholderRank(
    left,
  ).compareTo(_pendingPlaceholderRank(right));
  if (pendingCompare != 0) return pendingCompare;

  final timestampCompare = left.timestamp.compareTo(right.timestamp);
  if (timestampCompare != 0) return timestampCompare;

  final eventCompare = left.eventId.compareTo(right.eventId);
  if (eventCompare != 0) return eventCompare;

  final directionCompare = _conversationMessageDirectionRank(
    left.direction,
  ).compareTo(_conversationMessageDirectionRank(right.direction));
  if (directionCompare != 0) return directionCompare;

  final kindCompare = left.kind.compareTo(right.kind);
  if (kindCompare != 0) return kindCompare;

  return left.text.compareTo(right.text);
}

int _pendingPlaceholderRank(ConversationMessage message) {
  if (message.direction == MessageDirection.outgoing &&
      message.kind == 'transcribing') {
    return 1;
  }
  return 0;
}

int compareConversationMessagesNewestFirst(
  ConversationMessage left,
  ConversationMessage right,
) => compareConversationMessagesChronological(right, left);

List<ConversationMessage> sortConversationMessagesChronological(
  Iterable<ConversationMessage> messages,
) {
  return messages.toList()..sort(compareConversationMessagesChronological);
}

List<ConversationMessage> sortConversationMessagesNewestFirst(
  Iterable<ConversationMessage> messages,
) {
  return messages.toList()..sort(compareConversationMessagesNewestFirst);
}

int oldestActiveTranscribingPlaceholderIndex(
  List<ConversationMessage> messages,
) {
  var oldestIndex = -1;
  for (var index = 0; index < messages.length; index += 1) {
    final message = messages[index];
    if (message.direction != MessageDirection.outgoing ||
        message.kind != 'transcribing' ||
        message.text.trim().toLowerCase() == 'queued') {
      continue;
    }
    if (oldestIndex < 0 ||
        message.timestamp.isBefore(messages[oldestIndex].timestamp)) {
      oldestIndex = index;
    }
  }
  return oldestIndex;
}

int _conversationMessageDirectionRank(MessageDirection direction) {
  switch (direction) {
    case MessageDirection.outgoing:
      return 0;
    case MessageDirection.incoming:
      return 1;
  }
}

Map<String, dynamic>? _serializeBridgeAudioReference(
  BridgeAudioReference audio,
) {
  return {
    'url': audio.url,
    'sha256': audio.sha256,
    'size': audio.size.toString(),
    'mediaType': audio.mediaType,
    if (audio.name != null) 'name': audio.name,
    if (audio.encryption != null)
      'encryption': {
        'algorithm': audio.encryption!.algorithm,
        'key': audio.encryption!.key,
        'nonce': audio.encryption!.nonce,
        'plaintextSha256': audio.encryption!.plaintextSha256,
        'plaintextSize': audio.encryption!.plaintextSize.toString(),
        'plaintextMediaType': audio.encryption!.plaintextMediaType,
      },
  };
}

BridgeAudioReference? _deserializeBridgeAudioReference(dynamic raw) {
  if (raw is! Map) return null;
  final url = raw['url']?.toString();
  final sha256 = raw['sha256']?.toString();
  final sizeRaw = raw['size']?.toString();
  final mediaType = raw['mediaType']?.toString();
  if (url == null || sha256 == null || sizeRaw == null || mediaType == null) {
    return null;
  }

  final encryptionRaw = raw['encryption'];
  final encryption = encryptionRaw is Map
      ? _deserializeBridgeAudioEncryption(encryptionRaw)
      : null;
  final size = BigInt.tryParse(sizeRaw);
  if (size == null) return null;

  return BridgeAudioReference(
    url: url,
    sha256: sha256,
    size: size,
    mediaType: mediaType,
    name: raw['name']?.toString(),
    encryption: encryption,
  );
}

BridgeAudioEncryption? _deserializeBridgeAudioEncryption(Map encryptionRaw) {
  final algorithm = encryptionRaw['algorithm']?.toString();
  final key = encryptionRaw['key']?.toString();
  final nonce = encryptionRaw['nonce']?.toString();
  final plaintextSha256 = encryptionRaw['plaintextSha256']?.toString();
  final plaintextSizeRaw = encryptionRaw['plaintextSize']?.toString();
  final plaintextMediaType = encryptionRaw['plaintextMediaType']?.toString();
  final plaintextSize = BigInt.tryParse(plaintextSizeRaw ?? '');
  if (algorithm == null ||
      algorithm.isEmpty ||
      key == null ||
      key.isEmpty ||
      nonce == null ||
      nonce.isEmpty ||
      plaintextSha256 == null ||
      plaintextSha256.isEmpty ||
      plaintextSize == null ||
      plaintextMediaType == null ||
      plaintextMediaType.isEmpty) {
    return null;
  }

  return BridgeAudioEncryption(
    algorithm: algorithm,
    key: key,
    nonce: nonce,
    plaintextSha256: plaintextSha256,
    plaintextSize: plaintextSize,
    plaintextMediaType: plaintextMediaType,
  );
}
