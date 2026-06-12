import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:nostr_codex_phone/src/rust/api/nostr.dart';
import 'package:nostr_codex_phone/src/rust/frb_generated.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const NostrCodexApp());
}

class NostrCodexApp extends StatelessWidget {
  const NostrCodexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nostr Codex',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1f7a63)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff42d3a6),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff0c1110),
        cardTheme: const CardThemeData(
          color: Color(0xff151b1a),
          surfaceTintColor: Color(0xff42d3a6),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xff0c1110),
          foregroundColor: Color(0xffe8f3ef),
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.dark,
      home: const NostrCodexHome(),
    );
  }
}

class NostrCodexHome extends StatefulWidget {
  const NostrCodexHome({super.key});

  @override
  State<NostrCodexHome> createState() => _NostrCodexHomeState();
}

class _NostrCodexHomeState extends State<NostrCodexHome> {
  static const _storage = FlutterSecureStorage();
  static const _secretKeyStorageKey = 'nostr_secret_key';
  static const _peerPubkeyStorageKey = 'nostr_peer_pubkey';
  static const _relaysStorageKey = 'nostr_relays';
  static const _speechRecognizerUnavailable =
      'Speech input is unavailable. On GrapheneOS this usually means no Android speech recognition service is installed or enabled. Use typed input, keyboard dictation, or install a SpeechRecognizer provider.';
  static const _speechRecognizerUnavailableShort =
      'Speech input unavailable. Use typed input or install a SpeechRecognizer provider.';

  final _secretKeyController = TextEditingController();
  final _peerPubkeyController = TextEditingController();
  final _relayController = TextEditingController();
  final _queryController = TextEditingController();
  final _speech = stt.SpeechToText();
  final _tts = FlutterTts();
  final _messages = <ConversationMessage>[];

  bool _loadingSettings = true;
  bool _connecting = false;
  bool _connected = false;
  bool _polling = false;
  bool _speechReady = false;
  bool _listening = false;
  bool _sending = false;
  bool _voiceFinalHandled = false;
  bool _autoSpeak = true;
  String? _ownPubkey;
  String? _status;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    unawaited(_configureTts());
  }

  @override
  void dispose() {
    _polling = false;
    _speech.cancel();
    _tts.stop();
    _secretKeyController.dispose();
    _peerPubkeyController.dispose();
    _relayController.dispose();
    _queryController.dispose();
    unawaited(nostrStop());
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final defaultRelays = nostrDefaultRelays().join('\n');
    final secretKey = await _storage.read(key: _secretKeyStorageKey);
    final peerPubkey = await _storage.read(key: _peerPubkeyStorageKey);
    final relays = await _storage.read(key: _relaysStorageKey);

    if (!mounted) return;
    setState(() {
      _secretKeyController.text = secretKey ?? '';
      _peerPubkeyController.text = peerPubkey ?? '';
      _relayController.text = relays?.replaceAll(',', '\n') ?? defaultRelays;
      _loadingSettings = false;
    });
    _refreshOwnPubkey();
  }

  Future<void> _configureTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.48);
    } catch (_) {
      // Some test and simulator environments do not register a TTS engine.
    }
  }

  Future<void> _saveSettings() async {
    await _storage.write(
      key: _secretKeyStorageKey,
      value: _secretKeyController.text.trim(),
    );
    await _storage.write(
      key: _peerPubkeyStorageKey,
      value: _peerPubkeyController.text.trim(),
    );
    await _storage.write(
      key: _relaysStorageKey,
      value: _relayLines().join(','),
    );
  }

  Future<void> _generateKey() async {
    try {
      final pair = nostrGenerateSecretKey();
      setState(() {
        _secretKeyController.text = pair.secretKey;
        _ownPubkey = pair.publicKey;
        _status = 'Generated local key';
      });
      await _saveSettings();
    } catch (error) {
      _showError('Key generation failed: $error');
    }
  }

  void _refreshOwnPubkey() {
    final secret = _secretKeyController.text.trim();
    if (secret.isEmpty) {
      setState(() => _ownPubkey = null);
      return;
    }

    try {
      final pair = nostrPublicKey(secretKey: secret);
      setState(() => _ownPubkey = pair.publicKey);
    } catch (_) {
      setState(() => _ownPubkey = null);
    }
  }

  Future<void> _connect() async {
    final secret = _secretKeyController.text.trim();
    final peer = _peerPubkeyController.text.trim();
    final relays = _relayLines();

    if (secret.isEmpty || peer.isEmpty || relays.isEmpty) {
      _showError('Secret key, peer pubkey, and relays are required');
      return;
    }

    setState(() {
      _connecting = true;
      _status = 'Connecting to relays...';
    });

    try {
      await _saveSettings();
      final status = await nostrStart(
        config: BridgeNostrConfig(
          secretKey: secret,
          peerPubkey: peer,
          relays: relays,
        ),
      );
      if (!mounted) return;
      setState(() {
        _connected = true;
        _connecting = false;
        _ownPubkey = status.publicKey;
        _status = 'Connected to ${status.relayCount} relays';
      });
      _startPolling();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connected = false;
        _status = 'Connection failed';
      });
      _showError('Connection failed: $error');
    }
  }

  Future<void> _disconnect() async {
    _polling = false;
    await nostrStop();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _status = 'Disconnected';
    });
  }

  void _startPolling() {
    if (_polling) return;
    _polling = true;
    unawaited(_pollLoop());
  }

  Future<void> _pollLoop() async {
    while (mounted && _polling) {
      try {
        final message = await nostrNextMessage(timeoutMs: BigInt.from(1500));
        if (message == null || !mounted) continue;
        _receiveMessage(message);
      } catch (error) {
        if (!mounted || !_polling) return;
        setState(() => _status = 'Receive error: $error');
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  void _receiveMessage(BridgeIncomingMessage message) {
    final conversationMessage = ConversationMessage(
      direction: MessageDirection.incoming,
      kind: message.kind,
      text: message.text,
      eventId: message.eventId,
      timestamp: DateTime.now(),
    );
    setState(() {
      _messages.insert(0, conversationMessage);
      _status = 'Received ${message.kind}';
    });

    if (_autoSpeak &&
        (message.kind == 'response' ||
            message.kind == 'error' ||
            message.kind == 'invalid')) {
      unawaited(_speak(message.text));
    }
  }

  Future<void> _speak(String text) async {
    final spoken = text.trim();
    if (spoken.isEmpty) return;

    try {
      await _tts.stop();
      await _tts.speak(spoken);
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Text-to-speech error: $error');
    }
  }

  Future<void> _sendQuery({bool fromVoice = false}) async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;
    if (_sending) return;
    if (!_connected) {
      _showError('Connect before sending a query');
      return;
    }

    if (!fromVoice && _listening) {
      try {
        await _speech.stop();
      } catch (_) {}
      if (mounted) setState(() => _listening = false);
    }

    setState(() {
      _sending = true;
      _status = 'Sending query...';
    });

    try {
      final eventId = await nostrSendQuery(query: query);
      if (!mounted) return;
      setState(() {
        _messages.insert(
          0,
          ConversationMessage(
            direction: MessageDirection.outgoing,
            kind: 'query',
            text: query,
            eventId: eventId,
            timestamp: DateTime.now(),
          ),
        );
        _queryController.clear();
        _status = 'Query sent';
      });
    } catch (error) {
      _showError('Send failed: $error');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _toggleSpeech() async {
    if (_listening) {
      try {
        await _speech.stop();
      } catch (_) {}
      if (mounted) setState(() => _listening = false);
      return;
    }

    if (!_speechReady) {
      try {
        _speechReady = await _speech.initialize(
          onStatus: (status) {
            if (!mounted) return;
            setState(() => _listening = status == 'listening');
          },
          onError: _handleSpeechError,
        );
      } catch (error) {
        _handleSpeechStartupError(error);
        return;
      }
    }

    if (!_speechReady) {
      if (!mounted) return;
      _showError(_speechRecognizerUnavailableShort);
      setState(() => _status = _speechRecognizerUnavailable);
      return;
    }

    _voiceFinalHandled = false;
    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
          pauseFor: const Duration(seconds: 2),
          listenFor: const Duration(seconds: 20),
        ),
        onResult: (result) {
          if (!mounted) return;
          final recognized = result.recognizedWords.trim();
          setState(() {
            _queryController.text = recognized;
            if (result.finalResult) {
              _listening = false;
              _status = recognized.isEmpty
                  ? 'No speech detected'
                  : 'Speech captured';
            }
          });

          if (result.finalResult &&
              !_voiceFinalHandled &&
              _connected &&
              recognized.isNotEmpty) {
            _voiceFinalHandled = true;
            unawaited(_sendQuery(fromVoice: true));
          }
        },
      );
      if (mounted) {
        setState(() {
          _listening = true;
          _status = 'Listening...';
        });
      }
    } catch (error) {
      _handleSpeechStartupError(error);
    }
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;

    final message = _speechErrorMessage(error.errorMsg);
    final resetRecognizer = _isRecognizerUnavailable(error.errorMsg);
    setState(() {
      _listening = false;
      if (resetRecognizer) _speechReady = false;
      _status = message;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          resetRecognizer ? _speechRecognizerUnavailableShort : message,
        ),
      ),
    );
  }

  void _handleSpeechStartupError(Object error) {
    if (!mounted) return;

    final raw = error.toString();
    final message = _speechErrorMessage(raw);
    final resetRecognizer = _isRecognizerUnavailable(raw);
    setState(() {
      _listening = false;
      if (resetRecognizer) _speechReady = false;
      _status = message;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          resetRecognizer ? _speechRecognizerUnavailableShort : message,
        ),
      ),
    );
  }

  String _speechErrorMessage(String rawError) {
    if (_isRecognizerUnavailable(rawError)) {
      return _speechRecognizerUnavailable;
    }

    return 'Speech error: $rawError';
  }

  bool _isRecognizerUnavailable(String rawError) {
    final normalized = rawError.toLowerCase();
    return normalized.contains('error_client') ||
        normalized.contains('recognitionservice') ||
        normalized.contains('recognition service') ||
        normalized.contains('speech recognition service is not available');
  }

  List<String> _relayLines() {
    return _relayController.text
        .split(RegExp(r'[\n,]'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _status = message);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSettings) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nostr Codex'),
        actions: [
          IconButton(
            tooltip: _connected ? 'Disconnect' : 'Connect',
            onPressed: _connecting
                ? null
                : _connected
                ? _disconnect
                : _connect,
            icon: Icon(_connected ? Icons.link_off : Icons.link),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ConnectionPanel(
              secretKeyController: _secretKeyController,
              peerPubkeyController: _peerPubkeyController,
              relayController: _relayController,
              ownPubkey: _ownPubkey,
              connected: _connected,
              connecting: _connecting,
              autoSpeak: _autoSpeak,
              onGenerateKey: _generateKey,
              onSecretChanged: (_) => _refreshOwnPubkey(),
              onConnect: _connect,
              onDisconnect: _disconnect,
              onAutoSpeakChanged: (value) => setState(() => _autoSpeak = value),
            ),
            const SizedBox(height: 16),
            _Composer(
              controller: _queryController,
              connected: _connected,
              sending: _sending,
              listening: _listening,
              onMicPressed: _toggleSpeech,
              onSendPressed: () => _sendQuery(),
            ),
            const SizedBox(height: 12),
            if (_status != null)
              Text(_status!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Text('Messages', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_messages.isEmpty)
              const Text('No messages yet')
            else
              ..._messages.map((message) => _MessageTile(message: message)),
          ],
        ),
      ),
    );
  }
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({
    required this.secretKeyController,
    required this.peerPubkeyController,
    required this.relayController,
    required this.ownPubkey,
    required this.connected,
    required this.connecting,
    required this.autoSpeak,
    required this.onGenerateKey,
    required this.onSecretChanged,
    required this.onConnect,
    required this.onDisconnect,
    required this.onAutoSpeakChanged,
  });

  final TextEditingController secretKeyController;
  final TextEditingController peerPubkeyController;
  final TextEditingController relayController;
  final String? ownPubkey;
  final bool connected;
  final bool connecting;
  final bool autoSpeak;
  final VoidCallback onGenerateKey;
  final ValueChanged<String> onSecretChanged;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final ValueChanged<bool> onAutoSpeakChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    connected ? 'Relay session active' : 'Relay session',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Switch(value: autoSpeak, onChanged: onAutoSpeakChanged),
                const Text('Speak'),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: secretKeyController,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              onChanged: onSecretChanged,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Local nsec',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    ownPubkey ?? 'No valid local public key',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: connected ? null : onGenerateKey,
                  icon: const Icon(Icons.key),
                  label: const Text('Generate'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: peerPubkeyController,
              enabled: !connected,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Peer npub or hex',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: relayController,
              enabled: !connected,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Relays',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: connecting
                  ? null
                  : connected
                  ? onDisconnect
                  : onConnect,
              icon: connecting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(connected ? Icons.link_off : Icons.link),
              label: Text(connected ? 'Disconnect' : 'Connect'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.connected,
    required this.sending,
    required this.listening,
    required this.onMicPressed,
    required this.onSendPressed,
  });

  final TextEditingController controller;
  final bool connected;
  final bool sending;
  final bool listening;
  final VoidCallback onMicPressed;
  final VoidCallback onSendPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Query',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: listening ? 'Stop listening' : 'Speak query',
                  onPressed: sending ? null : onMicPressed,
                  icon: Icon(listening ? Icons.mic_off : Icons.mic),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: connected && !sending ? onSendPressed : null,
                    icon: sending
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(sending ? 'Sending...' : 'Send query'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message});

  final ConversationMessage message;

  @override
  Widget build(BuildContext context) {
    final incoming = message.direction == MessageDirection.incoming;
    return Card(
      color: incoming
          ? Theme.of(context).colorScheme.surfaceContainerHigh
          : Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        leading: Icon(incoming ? Icons.call_received : Icons.call_made),
        title: Text(message.kind),
        subtitle: Text(message.text),
        trailing: Text(
          _formatTime(message.timestamp),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

enum MessageDirection { incoming, outgoing }

class ConversationMessage {
  const ConversationMessage({
    required this.direction,
    required this.kind,
    required this.text,
    required this.eventId,
    required this.timestamp,
  });

  final MessageDirection direction;
  final String kind;
  final String text;
  final String eventId;
  final DateTime timestamp;
}
