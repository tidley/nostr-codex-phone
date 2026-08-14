import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:html';

import 'package:nostr/nostr.dart';

import 'nostr_transport.dart';
import 'rust/api/nostr.dart';

const _defaultRelays = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.primal.net',
  'wss://nostr.mom',
  'wss://purplepag.es',
];

class NostrTransportImpl implements NostrTransport {
  final List<WebSocket> _sockets = [];
  final ListQueue<BridgeIncomingMessage> _pendingMessages = ListQueue();
  final Map<String, Completer<List<BridgeIncomingMessage>>> _recent = {};
  final Map<String, List<BridgeIncomingMessage>> _recentMessages = {};
  Keys? _keys;
  String? _peerPubkey;
  Set<String> _receivePubkeys = {};
  Completer<BridgeIncomingMessage?>? _nextMessageWaiter;
  var _subscriptionId = 0;

  @override
  List<String> defaultRelays() => _defaultRelays;

  @override
  BridgeKeyPair generateSecretKey() => _keyPair(Keys.generate());

  @override
  BridgeKeyPair publicKey(String secretKey) => _keyPair(Keys(secretKey.trim()));

  @override
  Future<BridgeSessionStatus> start(BridgeNostrConfig config) async {
    await stop();
    _keys = Keys(config.secretKey.trim());
    _peerPubkey = _normalizePubkey(config.peerPubkey);
    _receivePubkeys = {
      ...config.receivePubkeys.map(_normalizePubkey),
      _peerPubkey!,
    }..remove('');
    final relays = config.relays
        .map((relay) => relay.trim())
        .where(
          (relay) => relay.startsWith('ws://') || relay.startsWith('wss://'),
        )
        .toSet()
        .toList();
    if (relays.isEmpty) throw StateError('At least one relay URL is required');

    await Future.wait(relays.map(_connect));
    if (_sockets.isEmpty) throw StateError('Could not connect to any relay');
    _subscribeLive();
    return BridgeSessionStatus(
      publicKey: _keys!.npub,
      publicKeyHex: _keys!.public,
      peerPubkey: config.peerPubkey,
      relayCount: _sockets.length,
    );
  }

  @override
  Future<void> stop() async {
    for (final socket in _sockets) {
      socket.close();
    }
    _sockets.clear();
    _keys = null;
    _peerPubkey = null;
    _pendingMessages.clear();
    _nextMessageWaiter?.complete(null);
    _nextMessageWaiter = null;
    _recent.clear();
    _recentMessages.clear();
  }

  @override
  Future<String> sendQuery(String query) async {
    final keys = _keys;
    if (keys == null) throw StateError('Nostr session is not started');
    if (query.trim().isEmpty)
      throw ArgumentError.value(query, 'query', 'Cannot be empty');
    final peer = _peerPubkey;
    if (peer == null) throw StateError('Peer public key is not configured');
    final event = await _createDirectMessage(
      message: query,
      authorSecretKey: keys.secret,
      recipientPubkey: peer,
    );
    _broadcast(['EVENT', event.toMap()]);
    return event.id;
  }

  @override
  Future<String> sendEphemeralQuery(String query, Duration expiresIn) async {
    final keys = _keys;
    if (keys == null) throw StateError('Nostr session is not started');
    if (query.trim().isEmpty) {
      throw ArgumentError.value(query, 'query', 'Cannot be empty');
    }
    final peer = _peerPubkey;
    if (peer == null) throw StateError('Peer public key is not configured');
    final event = await _createDirectMessage(
      message: query,
      authorSecretKey: keys.secret,
      recipientPubkey: peer,
      expiresAt: DateTime.now().add(expiresIn).millisecondsSinceEpoch ~/ 1000,
    );
    _broadcast(['EVENT', event.toMap()]);
    return event.id;
  }

  @override
  Future<BridgeIncomingMessage?> nextMessage(Duration timeout) {
    if (_pendingMessages.isNotEmpty) {
      return Future.value(_pendingMessages.removeFirst());
    }
    final waiter = Completer<BridgeIncomingMessage?>();
    _nextMessageWaiter = waiter;
    return waiter.future.timeout(timeout, onTimeout: () => null).whenComplete(
      () {
        if (identical(_nextMessageWaiter, waiter)) {
          _nextMessageWaiter = null;
        }
      },
    );
  }

  @override
  Future<List<BridgeIncomingMessage>> fetchRecentMessages(
    Duration lookback,
  ) async {
    final keys = _keys;
    if (keys == null) throw StateError('Nostr session is not started');
    final id = 'recent-${++_subscriptionId}';
    final completer = Completer<List<BridgeIncomingMessage>>();
    _recent[id] = completer;
    _recentMessages[id] = [];
    _broadcast([
      'REQ',
      id,
      {
        'kinds': [1059],
        '#p': [keys.public],
        'since':
            DateTime.now().subtract(lookback).millisecondsSinceEpoch ~/ 1000,
        'limit': 1000,
      },
    ]);
    return completer.future
        .timeout(
          const Duration(seconds: 12),
          onTimeout: () => _recentMessages.remove(id) ?? const [],
        )
        .whenComplete(() {
          _recent.remove(id);
          _recentMessages.remove(id);
          _broadcast(['CLOSE', id]);
        });
  }

  Future<void> _connect(String relay) async {
    try {
      final socket = WebSocket(relay);
      await socket.onOpen.first.timeout(const Duration(seconds: 4));
      socket.onMessage.listen(_handleFrame);
      _sockets.add(socket);
      print('Nostr web connected to $relay');
    } catch (error) {
      // Other relays remain available when one endpoint is offline.
      print('Nostr web could not connect to $relay: $error');
    }
  }

  void _subscribeLive() {
    final keys = _keys;
    if (keys == null) return;
    _broadcast([
      'REQ',
      'live',
      {
        'kinds': [1059],
        '#p': [keys.public],
      },
    ]);
  }

  void _broadcast(List<Object> frame) {
    final encoded = jsonEncode(frame);
    var sent = 0;
    for (final socket in _sockets.where((socket) => socket.readyState == 1)) {
      socket.send(encoded);
      sent++;
    }
    print('Nostr web sent ${frame.first} to $sent relay(s)');
  }

  Future<void> _handleFrame(MessageEvent event) async {
    if (event.data is! String) return;
    final frame = jsonDecode(event.data as String);
    if (frame is! List || frame.length < 2) return;
    if (frame.first == 'OK' || frame.first == 'NOTICE') {
      print('Nostr web relay ${frame.first}: ${jsonEncode(frame)}');
      return;
    }
    if (frame.first == 'EOSE') {
      final subscription = frame[1] as String?;
      final completer = subscription == null ? null : _recent[subscription];
      if (completer != null && !completer.isCompleted) {
        completer.complete(_recentMessages[subscription] ?? const []);
      }
      return;
    }
    if (frame.first != 'EVENT') return;
    final subscription = frame[1] as String?;
    final payload = frame.length > 2 ? frame[2] : null;
    if (subscription == null || payload is! Map) return;
    try {
      final message = await _decode(Event.fromJson(jsonEncode(payload)));
      if (message == null) return;
      final recent = _recentMessages[subscription];
      if (recent != null) recent.add(message);
      _queueIncoming(message);
    } catch (error) {
      // Do not expose decrypted content, but make transport failures visible
      // in browser diagnostics while the web client is being introduced.
      print('Nostr web ignored event: $error');
    }
  }

  void _queueIncoming(BridgeIncomingMessage message) {
    final waiter = _nextMessageWaiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(message);
      return;
    }
    _pendingMessages.addLast(message);
  }

  Future<Event> _createDirectMessage({
    required String message,
    required String authorSecretKey,
    required String recipientPubkey,
    int? expiresAt,
  }) async {
    final author = Keys(authorSecretKey);
    // nostr-sdk preserves a rumor's canonical ID while stripping its
    // signature. Rust rejects the id-less rumor created by the Dart helper.
    final signedRumor = Event.from(
      kind: DirectMessage.kindDirectMessage,
      content: message,
        tags: [
          ['p', recipientPubkey],
          if (expiresAt != null) ['expiration', '$expiresAt'],
        ],
      secretKey: author.secret,
    );
    final rumor = signedRumor.toMap()..remove('sig');
    final seal = Event.from(
      kind: GiftWrap.kindSeal,
      content: await Encryption.encrypt(
        plaintext: jsonEncode(rumor),
        recipientPubkey: recipientPubkey,
        senderSecretKey: author.secret,
      ),
      secretKey: author.secret,
      tags: const [],
    );
    final ephemeral = Keys.generate();
    return Event.from(
      kind: GiftWrap.kindGiftWrap,
      content: await Encryption.encrypt(
        plaintext: seal.toJson(),
        recipientPubkey: recipientPubkey,
        senderSecretKey: ephemeral.secret,
      ),
      secretKey: ephemeral.secret,
      pubkey: ephemeral.public,
      tags: [
        ['p', recipientPubkey],
      ],
    );
  }

  Future<BridgeIncomingMessage?> _decode(Event event) async {
    final keys = _keys;
    if (keys == null || event.kind != GiftWrap.kindGiftWrap) return null;
    final rumor = await DirectMessage.parse(
      giftWrap: event,
      recipientSecretKey: keys.secret,
    );
    if (!_receivePubkeys.contains(rumor.pubkey)) {
      print('Nostr web ignored message from an unconfigured sender');
      return null;
    }
    final rawJson = rumor.content;
    final decoded = jsonDecode(rawJson);
    final kind = decoded is Map && decoded.length == 1
        ? decoded.keys.single.toString()
        : 'invalid';
    final text = _messageText(decoded, rawJson);
    print('Nostr web received $kind');
    return BridgeIncomingMessage(
      senderPubkey: Bech32Entity.encode(
        prefix: Nip19Prefix.npub,
        data: rumor.pubkey,
      ),
      senderPubkeyHex: rumor.pubkey,
      kind: kind,
      text: text,
      rawJson: rawJson,
      eventId: event.id,
    );
  }

  String _messageText(Object? decoded, String rawJson) {
    if (decoded is Map && decoded.length == 1) {
      final value = decoded.values.single;
      if (value is String) return value;
      if (value is Map) {
        for (final key in ['query', 'response', 'error', 'transcript']) {
          final text = value[key];
          if (text is String) return text;
        }
      }
    }
    return rawJson;
  }

  BridgeKeyPair _keyPair(Keys keys) => BridgeKeyPair(
    secretKey: keys.nsec,
    publicKey: keys.npub,
    publicKeyHex: keys.public,
  );

  String _normalizePubkey(String value) {
    final cleaned = value.trim().replaceFirst(RegExp(r'^nostr:'), '');
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(cleaned))
      return cleaned.toLowerCase();
    final decoded = Bech32Entity.decode(payload: cleaned);
    return decoded.data;
  }
}
