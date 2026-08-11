import 'rust/api/nostr.dart';
import 'nostr_transport.dart';

class NostrTransportImpl implements NostrTransport {
  @override
  List<String> defaultRelays() => nostrDefaultRelays();

  @override
  BridgeKeyPair generateSecretKey() => nostrGenerateSecretKey();

  @override
  BridgeKeyPair publicKey(String secretKey) =>
      nostrPublicKey(secretKey: secretKey);

  @override
  Future<BridgeSessionStatus> start(BridgeNostrConfig config) =>
      nostrStart(config: config);

  @override
  Future<void> stop() => nostrStop();

  @override
  Future<String> sendQuery(String query) => nostrSendQuery(query: query);

  @override
  Future<BridgeIncomingMessage?> nextMessage(Duration timeout) =>
      nostrNextMessage(timeoutMs: BigInt.from(timeout.inMilliseconds));

  @override
  Future<List<BridgeIncomingMessage>> fetchRecentMessages(Duration lookback) =>
      nostrFetchRecentMessages(lookbackSecs: BigInt.from(lookback.inSeconds));
}
