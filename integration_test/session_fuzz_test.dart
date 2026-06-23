import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nostr_codex_phone/main.dart';
import 'package:nostr_codex_phone/src/rust/api/nostr.dart';
import 'package:nostr_codex_phone/src/rust/frb_generated.dart';

const _storage = FlutterSecureStorage();
const _storageKeys = [
  'nostr_secret_key',
  'nostr_peer_pubkey',
  'nostr_relays',
  'repo_targets_v1',
  'selected_repo_target_id',
  'conversation_history_v1',
  'seen_incoming_event_ids_v1',
  'unread_counts_v1',
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  setUpAll(() async => RustLib.init());

  testWidgets(
    'hardware fuzzes temporary session switching and sends',
    (tester) async {
      final originalStorage = <String, String?>{
        for (final key in _storageKeys) key: await _storage.read(key: key),
      };

      try {
        final owner = nostrGenerateSecretKey();
        final targets = List.generate(4, (index) {
          final pair = nostrGenerateSecretKey();
          return {
            'id': 'hardware-fuzz-$index',
            'name': 'HW fuzz $index',
            'pubkey': pair.publicKey,
            'relays': nostrDefaultRelays(),
          };
        });

        await _storage.write(key: 'nostr_secret_key', value: owner.secretKey);
        await _storage.write(
          key: 'nostr_relays',
          value: nostrDefaultRelays().join('\n'),
        );
        await _storage.write(
          key: 'nostr_peer_pubkey',
          value: targets.first['pubkey']! as String,
        );
        await _storage.write(
          key: 'repo_targets_v1',
          value: jsonEncode(targets),
        );
        await _storage.write(
          key: 'selected_repo_target_id',
          value: 'hardware-fuzz-0',
        );
        await _storage.write(
          key: 'conversation_history_v1',
          value: jsonEncode({}),
        );
        await _storage.write(
          key: 'seen_incoming_event_ids_v1',
          value: jsonEncode([]),
        );
        await _storage.write(key: 'unread_counts_v1', value: jsonEncode({}));

        await tester.pumpWidget(const NostrCodexApp());
        await _waitForShell(tester);

        final random = Random(912837);
        for (var step = 0; step < 20; step += 1) {
          final targetIndex = random.nextInt(targets.length);
          await _selectSession(tester, 'HW fuzz $targetIndex');
          await _expectSessionVisible(tester, 'HW fuzz $targetIndex');

          if (step % 3 == 0) {
            await _sendShortMessage(tester, 'hardware fuzz message $step');
            await tester.pump(const Duration(milliseconds: 300));

            final nextIndex = (targetIndex + 1) % targets.length;
            await _trySelectSession(tester, 'HW fuzz $nextIndex');
            await _expectSessionVisible(tester, 'HW fuzz $targetIndex');
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        for (final entry in originalStorage.entries) {
          if (entry.value == null) {
            await _storage.delete(key: entry.key);
          } else {
            await _storage.write(key: entry.key, value: entry.value);
          }
        }
        await nostrStop();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _waitForShell(WidgetTester tester) async {
  for (var attempt = 0; attempt < 80; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.byType(TextField).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('app shell did not render');
}

Future<void> _selectSession(WidgetTester tester, String label) async {
  await _openDrawer(tester);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

Future<void> _trySelectSession(WidgetTester tester, String label) async {
  await _openDrawer(tester);
  final target = find.text(label);
  if (target.evaluate().isNotEmpty) {
    await tester.tap(target.last);
  }
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.dragFrom(const Offset(2, 400), const Offset(320, 0));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

Future<void> _expectSessionVisible(WidgetTester tester, String label) async {
  await _openDrawer(tester);
  final tile = find.ancestor(
    of: find.text(label).last,
    matching: find.byType(ListTile),
  );
  expect(tile, findsWidgets);
  expect(tester.widget<ListTile>(tile.first).selected, isTrue);
  await _closeDrawer(tester);
}

Future<void> _sendShortMessage(WidgetTester tester, String message) async {
  final input = find.byType(TextField);
  await tester.ensureVisible(input);
  await tester.tap(input, warnIfMissed: false);
  await tester.enterText(find.byType(TextField), message);
  await tester.pump(const Duration(milliseconds: 100));
  final send = find.text('Send').last;
  await tester.ensureVisible(send);
  await tester.tap(send, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _closeDrawer(WidgetTester tester) async {
  await tester.tapAt(const Offset(390, 400));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}
