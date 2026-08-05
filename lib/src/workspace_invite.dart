import 'dart:convert';

import 'package:crew/src/repo_target.dart';

const _workspaceInvitePrefix = 'nci1.';
const _maxWorkspaceInviteLength = 4096;

class WorkspaceInvite {
  const WorkspaceInvite({required this.secret, required this.target});

  final String secret;
  final RepoTarget target;
}

WorkspaceInvite? parseWorkspaceInviteCode(String value) {
  final code = value.trim();
  if (!code.startsWith(_workspaceInvitePrefix) ||
      code.length > _maxWorkspaceInviteLength) {
    return null;
  }
  final encoded = code.substring(_workspaceInvitePrefix.length);
  if (encoded.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(encoded)) {
    return null;
  }
  try {
    final bytes = base64Url.decode(base64Url.normalize(encoded));
    if (bytes.length > 3072) return null;
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map || decoded['v'] != 1) return null;
    final secret = decoded['t']?.toString() ?? '';
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(secret)) return null;
    final rawTarget = decoded['target'];
    if (rawTarget is! Map) return null;
    final type = rawTarget['type']?.toString();
    final version = rawTarget['version'];
    final id = rawTarget['id']?.toString().trim() ?? '';
    final name = rawTarget['name']?.toString().trim() ?? '';
    final pubkey = rawTarget['pubkey']?.toString().trim() ?? '';
    final rawRelays = rawTarget['relays'];
    if (type != 'nostr_codex_target' ||
        version != 1 ||
        !_boundedIdentifier(id) ||
        !_boundedText(name, 128) ||
        !_boundedIdentifier(pubkey) ||
        rawRelays is! Iterable) {
      return null;
    }
    final relays = <String>[];
    for (final rawRelay in rawRelays) {
      final relay = rawRelay.toString().trim();
      final uri = Uri.tryParse(relay);
      if (relay.length > 512 ||
          uri == null ||
          (uri.scheme != 'wss' && uri.scheme != 'ws') ||
          uri.host.isEmpty) {
        return null;
      }
      relays.add(relay);
    }
    if (relays.isEmpty || relays.length > 8) return null;
    return WorkspaceInvite(
      secret: secret,
      target: RepoTarget(id: id, name: name, pubkey: pubkey, relays: relays),
    );
  } catch (_) {
    return null;
  }
}

bool _boundedIdentifier(String value) =>
    value.isNotEmpty &&
    value.length <= 128 &&
    RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);

bool _boundedText(String value, int maximum) =>
    value.isNotEmpty && value.length <= maximum;
