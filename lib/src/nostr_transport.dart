import 'rust/api/nostr.dart';
import 'nostr_transport_native.dart'
    if (dart.library.js_interop) 'nostr_transport_web.dart';

abstract class NostrTransport {
  factory NostrTransport() = NostrTransportImpl;

  List<String> defaultRelays();
  BridgeKeyPair generateSecretKey();
  BridgeKeyPair publicKey(String secretKey);
  Future<BridgeSessionStatus> start(BridgeNostrConfig config);
  Future<void> stop();
  Future<String> sendQuery(String query);
  Future<BridgeIncomingMessage?> nextMessage(Duration timeout);
  Future<List<BridgeIncomingMessage>> fetchRecentMessages(Duration lookback);
}
