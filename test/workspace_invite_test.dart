import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nostr_codex_phone/src/workspace_invite.dart';

void main() {
  final code =
      'nci1.${base64Url.encode(utf8.encode(jsonEncode({
        'v': 1,
        't': 'a' * 43,
        'target': {
          'type': 'nostr_codex_target',
          'version': 1,
          'id': 'workspace-aabb',
          'name': 'Dev workspace',
          'pubkey': 'npub1aaabbb',
          'relays': ['wss://relay.example.com'],
        },
      })))}';

  test('parses a self-contained workspace invite code', () {
    final invite = parseWorkspaceInviteCode(code);
    expect(invite, isNotNull);
    expect(invite!.target.name, 'Dev workspace');
    expect(invite.target.relays, ['wss://relay.example.com']);
  });

  test('rejects malformed or oversized workspace invite codes', () {
    expect(parseWorkspaceInviteCode('nci1.short'), isNull);
    expect(parseWorkspaceInviteCode('nci1.${'a' * 4096}'), isNull);
  });
}
