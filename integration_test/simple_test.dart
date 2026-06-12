import 'package:flutter_test/flutter_test.dart';
import 'package:nostr_codex_phone/main.dart';
import 'package:nostr_codex_phone/src/rust/api/nostr.dart';
import 'package:nostr_codex_phone/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('can call rust and render app shell', (
    WidgetTester tester,
  ) async {
    expect(nostrDefaultRelays(), isNotEmpty);
    await tester.pumpWidget(const NostrCodexApp());
    await tester.pump();
    expect(find.text('Nostr Codex'), findsWidgets);
  });
}
