import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:nostr_codex_phone/src/rust/api/nostr.dart';
import 'package:nostr_codex_phone/src/rust/frb_generated.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

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
  static const _blossomServerStorageKey = 'blossom_server';
  static const _defaultBlossomServer = 'https://blossom.primal.net';
  static const _audioContentType = 'audio/wav';

  final _secretKeyController = TextEditingController();
  final _peerPubkeyController = TextEditingController();
  final _relayController = TextEditingController();
  final _blossomServerController = TextEditingController();
  final _queryController = TextEditingController();
  final _recorder = AudioRecorder();
  final _tts = FlutterTts();
  final _messages = <ConversationMessage>[];

  bool _loadingSettings = true;
  bool _connecting = false;
  bool _connected = false;
  bool _polling = false;
  bool _sending = false;
  bool _recording = false;
  bool _sendingAudio = false;
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
    unawaited(_recorder.dispose());
    _tts.stop();
    _secretKeyController.dispose();
    _peerPubkeyController.dispose();
    _relayController.dispose();
    _blossomServerController.dispose();
    _queryController.dispose();
    unawaited(nostrStop());
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final defaultRelays = nostrDefaultRelays().join('\n');
    final secretKey = await _storage.read(key: _secretKeyStorageKey);
    final peerPubkey = await _storage.read(key: _peerPubkeyStorageKey);
    final relays = await _storage.read(key: _relaysStorageKey);
    final blossomServer = await _storage.read(key: _blossomServerStorageKey);

    if (!mounted) return;
    setState(() {
      _secretKeyController.text = secretKey ?? '';
      _peerPubkeyController.text = peerPubkey ?? '';
      _relayController.text = relays?.replaceAll(',', '\n') ?? defaultRelays;
      _blossomServerController.text = blossomServer ?? _defaultBlossomServer;
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
    await _storage.write(
      key: _blossomServerStorageKey,
      value: _blossomServerController.text.trim(),
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

  Future<void> _sendQuery() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;
    if (_sending) return;
    if (!_connected) {
      _showError('Connect before sending a query');
      return;
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

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopAndSendRecording();
      return;
    }

    if (!_connected) {
      _showError('Connect before recording a voice query');
      return;
    }
    if (_sending || _sendingAudio) return;

    final blossomServer = _blossomServerController.text.trim();
    if (blossomServer.isEmpty) {
      _showError('Blossom server is required');
      return;
    }

    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        _showError('Microphone permission denied');
        return;
      }

      await _saveSettings();
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${directory.path}/nostr_codex_voice_$timestamp.wav';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          noiseSuppress: true,
        ),
        path: path,
      );

      if (!mounted) return;
      setState(() {
        _recording = true;
        _status = 'Recording voice query...';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _recording = false);
      _showError('Recording failed: $error');
    }
  }

  Future<void> _stopAndSendRecording() async {
    String? path;
    try {
      path = await _recorder.stop();
    } catch (error) {
      if (mounted) {
        setState(() => _recording = false);
        _showError('Stop recording failed: $error');
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _recording = false;
      _sendingAudio = true;
      _status = 'Uploading voice note to Blossom...';
    });

    if (path == null || path.isEmpty) {
      _showError('Recording did not produce an audio file');
      if (mounted) setState(() => _sendingAudio = false);
      return;
    }

    try {
      final fileName = path.split(Platform.pathSeparator).last;
      final audio = await blossomUploadAudio(
        config: BridgeBlossomUploadConfig(
          secretKey: _secretKeyController.text.trim(),
          serverUrl: _blossomServerController.text.trim(),
          filePath: path,
          contentType: _audioContentType,
          fileName: fileName,
        ),
      );

      if (!mounted) return;
      setState(() => _status = 'Sending Blossom audio reference...');

      final eventId = await nostrSendAudio(audio: audio);
      if (!mounted) return;
      setState(() {
        _messages.insert(
          0,
          ConversationMessage(
            direction: MessageDirection.outgoing,
            kind: 'audio',
            text: _audioSummary(audio),
            eventId: eventId,
            timestamp: DateTime.now(),
          ),
        );
        _status = 'Voice query sent';
      });
    } catch (error) {
      _showError('Voice query failed: $error');
    } finally {
      unawaited(_deleteTempAudio(path));
      if (mounted) {
        setState(() => _sendingAudio = false);
      }
    }
  }

  Future<void> _deleteTempAudio(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  String _audioSummary(BridgeAudioReference audio) {
    final shortHash = audio.sha256.length >= 12
        ? audio.sha256.substring(0, 12)
        : audio.sha256;
    return '${audio.name ?? 'voice note'}\n${audio.url}\nsha256: $shortHash...';
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
              blossomServerController: _blossomServerController,
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
              sendingAudio: _sendingAudio,
              recording: _recording,
              onMicPressed: _toggleRecording,
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
    required this.blossomServerController,
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
  final TextEditingController blossomServerController;
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
            TextField(
              controller: blossomServerController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Blossom server',
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
    required this.sendingAudio,
    required this.recording,
    required this.onMicPressed,
    required this.onSendPressed,
  });

  final TextEditingController controller;
  final bool connected;
  final bool sending;
  final bool sendingAudio;
  final bool recording;
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
                  tooltip: recording ? 'Stop recording' : 'Record voice query',
                  onPressed: sending || sendingAudio || !connected
                      ? null
                      : onMicPressed,
                  icon: Icon(recording ? Icons.stop : Icons.mic),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: connected && !sending && !sendingAudio
                        ? onSendPressed
                        : null,
                    icon: sending || sendingAudio
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(
                      sendingAudio
                          ? 'Sending voice...'
                          : sending
                          ? 'Sending...'
                          : 'Send query',
                    ),
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
