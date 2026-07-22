import 'dart:convert';

import 'package:nostr_codex_phone/src/conversation_message.dart';
import 'package:nostr_codex_phone/src/repo_target.dart';

String? incomingRouteWorkdir(String rawJson) {
  if (rawJson.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) return null;
    final workdir = decoded['workdir']?.toString().trim();
    if (workdir != null && workdir.isNotEmpty) return workdir;
    final route = decoded['route'];
    if (route is! Map) return null;
    final routedWorkdir = route['workdir']?.toString().trim();
    return routedWorkdir == null || routedWorkdir.isEmpty
        ? null
        : routedWorkdir;
  } catch (_) {
    return null;
  }
}

String? conversationKeyForIncomingRoute({
  required List<RepoTarget> targets,
  required String senderPubkey,
  required String senderPubkeyHex,
  required String rawJson,
  String? fallbackKey,
}) {
  final routeWorkdir = incomingRouteWorkdir(rawJson);
  if (routeWorkdir != null) {
    for (final target in targets) {
      if (_targetMatchesSender(target, senderPubkey, senderPubkeyHex) &&
          target.workdir?.trim() == routeWorkdir) {
        return target.id;
      }
    }
  }

  final matches = targets
      .where(
        (target) => _targetMatchesSender(target, senderPubkey, senderPubkeyHex),
      )
      .toList();
  if (matches.length == 1) return matches.single.id;
  if (matches.isEmpty) return fallbackKey;

  return null;
}

String? conversationKeyForPendingResponse({
  required List<RepoTarget> targets,
  required Map<String, List<ConversationMessage>> messagesByTarget,
  required String senderPubkey,
  required String senderPubkeyHex,
}) {
  final matches = <String>[];
  for (final target in targets) {
    if (!_targetMatchesSender(target, senderPubkey, senderPubkeyHex)) continue;
    final messages = messagesByTarget[target.id] ?? const [];
    final hasPendingResponse = messages.any(
      (message) =>
          message.kind == 'processing' &&
          message.direction == MessageDirection.incoming,
    );
    if (hasPendingResponse) matches.add(target.id);
  }

  return matches.length == 1 ? matches.single : null;
}

bool _targetMatchesSender(
  RepoTarget target,
  String senderPubkey,
  String senderPubkeyHex,
) {
  final senderKeys = {senderPubkey.trim(), senderPubkeyHex.trim()}..remove('');
  return senderKeys.contains(target.pubkey.trim()) ||
      senderKeys.contains(target.parentPubkey?.trim());
}

String? conversationKeyForPendingTranscript({
  required Map<String, List<ConversationMessage>> messagesByTarget,
  required String sourceEventId,
}) {
  final trimmedEventId = sourceEventId.trim();
  if (trimmedEventId.isEmpty) return null;

  final matches = <String>[];
  for (final entry in messagesByTarget.entries) {
    final hasPendingTranscript = entry.value.any(
      (message) =>
          message.kind == 'transcribing' &&
          message.direction == MessageDirection.outgoing &&
          message.eventId == trimmedEventId,
    );
    if (hasPendingTranscript) matches.add(entry.key);
  }

  return matches.length == 1 ? matches.single : null;
}
