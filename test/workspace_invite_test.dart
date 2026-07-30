import 'package:flutter_test/flutter_test.dart';
import 'package:nostr_codex_phone/src/workspace_invite.dart';

void main() {
  test('normalizes a grouped workspace invite code', () {
    expect(normalizeWorkspaceInviteCode('ab-cd ef-1234'), 'ABCDEF1234');
    expect(isWorkspaceInviteCode('ab-cd ef-1234'), isTrue);
  });

  test('rejects malformed workspace invite codes', () {
    expect(isWorkspaceInviteCode('short'), isFalse);
    expect(isWorkspaceInviteCode('ABCDEFGHIJ'), isFalse);
  });
}
