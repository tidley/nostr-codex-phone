import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:nostr_codex_phone/src/rust/api/nostr.dart';
import 'package:nostr_codex_phone/src/rust/frb_generated.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

const _autoBlossomServer = 'auto';
const _blossomPresets = <_BlossomPreset>[
  _BlossomPreset(
    label: 'Auto-select',
    url: _autoBlossomServer,
    note: 'Try public free-tier servers in order',
  ),
  _BlossomPreset(
    label: 'Nostr.build',
    url: 'https://blossom.nostr.build',
    note: 'Free audio uploads up to 20 MiB',
  ),
  _BlossomPreset(
    label: 'Primal',
    url: 'https://blossom.primal.net',
    note: 'Public Blossom server',
  ),
  _BlossomPreset(
    label: 'Nostrcheck',
    url: 'https://cdn.nostrcheck.me',
    note: 'Public Blossom endpoint',
  ),
];

const _autoBlossomUploadServers = <String>[
  'https://blossom.nostr.build',
  'https://blossom.primal.net',
  'https://cdn.nostrcheck.me',
];

class _BlossomPreset {
  const _BlossomPreset({
    required this.label,
    required this.url,
    required this.note,
  });

  final String label;
  final String url;
  final String note;
}

String cleanTextForSpeech(String text) {
  var cleaned = text.replaceAll('\r\n', '\n');

  cleaned = cleaned.replaceAllMapped(
    RegExp(r'```[^\n]*\n?([\s\S]*?)```'),
    (match) => match.group(1) ?? '',
  );
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'`([^`]+)`'),
    (match) => match.group(1) ?? '',
  );
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]+\)'),
    (match) => match.group(1) ?? '',
  );
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (match) => match.group(1) ?? '',
  );
  cleaned = cleaned.replaceAll(
    RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true),
    '',
  );
  cleaned = cleaned.replaceAll(
    RegExp(r'^\s{0,3}[-*+]\s+', multiLine: true),
    '',
  );
  cleaned = cleaned.replaceAll(
    RegExp(r'^\s{0,3}\d+[.)]\s+', multiLine: true),
    '',
  );
  cleaned = cleaned.replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '');
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'(\*\*|__)(.*?)\1'),
    (match) => match.group(2) ?? '',
  );
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'(\*|_)(.*?)\1'),
    (match) => match.group(2) ?? '',
  );
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'~~(.*?)~~'),
    (match) => match.group(1) ?? '',
  );
  cleaned = cleaned.replaceAll(
    RegExp(r'^\s*[-*_]{3,}\s*$', multiLine: true),
    '',
  );
  cleaned = cleaned
      .split('\n')
      .map((line) => line.trim())
      .join('\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');

  return cleaned.trim();
}

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
  static const _ttsLanguageStorageKey = 'tts_language';
  static const _ttsEngineStorageKey = 'tts_engine';
  static const _ttsRateStorageKey = 'tts_rate';
  static const _ttsPitchStorageKey = 'tts_pitch';
  static const _ttsVolumeStorageKey = 'tts_volume';
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
  bool _speaking = false;
  bool _connectionExpanded = true;
  double _ttsRate = 0.48;
  double _ttsPitch = 1.0;
  double _ttsVolume = 1.0;
  String _ttsLanguage = 'en-US';
  String? _ttsEngine;
  List<String> _ttsLanguages = const ['en-US'];
  List<String> _ttsEngines = const [];
  String? _lastSpokenText;
  String? _ownPubkey;
  String? _status;

  @override
  void initState() {
    super.initState();
    _configureTtsHandlers();
    unawaited(_loadSettings());
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
    final ttsLanguage = await _storage.read(key: _ttsLanguageStorageKey);
    final ttsEngine = await _storage.read(key: _ttsEngineStorageKey);
    final ttsRate = await _storage.read(key: _ttsRateStorageKey);
    final ttsPitch = await _storage.read(key: _ttsPitchStorageKey);
    final ttsVolume = await _storage.read(key: _ttsVolumeStorageKey);

    if (!mounted) return;
    setState(() {
      _secretKeyController.text = secretKey ?? '';
      _peerPubkeyController.text = peerPubkey ?? '';
      _relayController.text = relays?.replaceAll(',', '\n') ?? defaultRelays;
      _blossomServerController.text = blossomServer ?? _autoBlossomServer;
      _ttsLanguage = _cleanStoredString(ttsLanguage) ?? _ttsLanguage;
      _ttsEngine = _cleanStoredString(ttsEngine);
      _ttsRate = _storedDouble(ttsRate, _ttsRate, 0.1, 1.0);
      _ttsPitch = _storedDouble(ttsPitch, _ttsPitch, 0.5, 2.0);
      _ttsVolume = _storedDouble(ttsVolume, _ttsVolume, 0.0, 1.0);
      _loadingSettings = false;
    });
    _refreshOwnPubkey();
    await _applyTtsSettings();
    unawaited(_loadTtsOptions());
  }

  void _configureTtsHandlers() {
    _tts.setStartHandler(() {
      if (mounted) setState(() => _speaking = true);
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _speaking = false);
    });
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
    await _saveTtsSettings();
  }

  Future<void> _saveTtsSettings() async {
    await _storage.write(key: _ttsLanguageStorageKey, value: _ttsLanguage);
    await _storage.write(key: _ttsRateStorageKey, value: _ttsRate.toString());
    await _storage.write(key: _ttsPitchStorageKey, value: _ttsPitch.toString());
    await _storage.write(
      key: _ttsVolumeStorageKey,
      value: _ttsVolume.toString(),
    );

    final engine = _cleanStoredString(_ttsEngine);
    if (engine == null) {
      await _storage.delete(key: _ttsEngineStorageKey);
    } else {
      await _storage.write(key: _ttsEngineStorageKey, value: engine);
    }
  }

  Future<void> _loadTtsOptions() async {
    try {
      final languages = _cleanStringList(await _tts.getLanguages);
      final engines = Platform.isAndroid
          ? _cleanStringList(await _tts.getEngines)
          : <String>[];
      final defaultEngine = Platform.isAndroid
          ? _cleanStoredString((await _tts.getDefaultEngine)?.toString())
          : null;

      if (!mounted) return;
      setState(() {
        _ttsLanguages = _withSelected(_ttsLanguage, languages);
        _ttsEngines = engines;
        _ttsEngine ??= defaultEngine;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'TTS options unavailable: $error');
    }
  }

  Future<void> _applyTtsSettings() async {
    try {
      final engine = _cleanStoredString(_ttsEngine);
      if (Platform.isAndroid && engine != null) {
        await _tts.setEngine(engine);
      }
      await _tts.setLanguage(_ttsLanguage);
      await _tts.setSpeechRate(_ttsRate);
      await _tts.setPitch(_ttsPitch);
      await _tts.setVolume(_ttsVolume);
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'TTS settings error: $error');
    }
  }

  Future<void> _applyAndSaveTtsSettings() async {
    await _applyTtsSettings();
    await _saveTtsSettings();
  }

  void _setTtsLanguage(String language) {
    setState(() => _ttsLanguage = language);
    unawaited(_applyAndSaveTtsSettings());
  }

  void _setTtsEngine(String? engine) {
    setState(() => _ttsEngine = _cleanStoredString(engine));
    unawaited(_applyAndSaveTtsSettings().then((_) => _loadTtsOptions()));
  }

  void _setTtsRate(double value) {
    setState(() => _ttsRate = value);
  }

  void _setTtsPitch(double value) {
    setState(() => _ttsPitch = value);
  }

  void _setTtsVolume(double value) {
    setState(() => _ttsVolume = value);
  }

  void _commitTtsSettings(double _) {
    unawaited(_applyAndSaveTtsSettings());
  }

  Future<void> _testTtsSettings() async {
    await _speak('Text to speech test. Rate, pitch, and volume are active.');
  }

  String? _cleanStoredString(String? value) {
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) return null;
    return cleaned;
  }

  double _storedDouble(String? raw, double fallback, double min, double max) {
    final parsed = double.tryParse(raw ?? '');
    if (parsed == null) return fallback;
    return parsed.clamp(min, max).toDouble();
  }

  List<String> _cleanStringList(dynamic raw) {
    final values = raw is Iterable ? raw : const [];
    final cleaned =
        values
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return cleaned;
  }

  List<String> _withSelected(String selected, List<String> values) {
    final next = values.toSet()..add(selected);
    final sorted = next.toList()..sort();
    return sorted;
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
        _connectionExpanded = false;
        _ownPubkey = status.publicKey;
        _status = 'Connected to ${status.relayCount} relays';
      });
      _startPolling();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connected = false;
        _connectionExpanded = true;
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
      _connectionExpanded = true;
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
      unawaited(_speak(message.text, remember: true));
    }
  }

  Future<void> _speak(String text, {bool remember = false}) async {
    final spoken = cleanTextForSpeech(text);
    if (spoken.isEmpty) return;

    try {
      await _tts.stop();
      if (mounted) {
        setState(() {
          _speaking = true;
          if (remember) _lastSpokenText = text;
        });
      }
      await _tts.speak(spoken);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _speaking = false;
        _status = 'Text-to-speech error: $error';
      });
    }
  }

  Future<void> _stopSpeaking() async {
    try {
      await _tts.stop();
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  Future<void> _replayLastSpoken() async {
    final text = _lastSpokenText;
    if (text == null || text.trim().isEmpty) return;
    await _speak(text);
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
      final audio = await _uploadAudioToBlossom(path, fileName);

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

  Future<BridgeAudioReference> _uploadAudioToBlossom(
    String path,
    String fileName,
  ) async {
    final servers = _selectedBlossomServers();
    Object? lastError;

    for (final server in servers) {
      if (mounted) {
        setState(
          () => _status = 'Uploading voice note to ${_serverLabel(server)}...',
        );
      }

      try {
        return await blossomUploadAudio(
          config: BridgeBlossomUploadConfig(
            secretKey: _secretKeyController.text.trim(),
            serverUrl: server,
            filePath: path,
            contentType: _audioContentType,
            fileName: fileName,
          ),
        );
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception(
      'all Blossom uploads failed across ${servers.length} server(s): $lastError',
    );
  }

  List<String> _selectedBlossomServers() {
    final selected = _blossomServerController.text.trim();
    if (_isAutoBlossom(selected)) {
      return _autoBlossomUploadServers;
    }
    return [selected];
  }

  bool _isAutoBlossom(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == _autoBlossomServer ||
        normalized == 'auto-select';
  }

  String _serverLabel(String server) {
    for (final preset in _blossomPresets) {
      if (preset.url == server) return preset.label;
    }
    return server.replaceFirst(RegExp(r'^https?://'), '');
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
    final privacy = audio.encryption == null
        ? 'unencrypted payload'
        : 'encrypted payload';
    return '${audio.name ?? 'voice note'}\n${audio.url}\n$privacy\ncipher sha256: $shortHash...';
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
              blossomPresets: _blossomPresets,
              ownPubkey: _ownPubkey,
              connected: _connected,
              connecting: _connecting,
              expanded: _connectionExpanded,
              onGenerateKey: _generateKey,
              onSecretChanged: (_) => _refreshOwnPubkey(),
              onConnect: _connect,
              onDisconnect: _disconnect,
              onExpandedChanged: (value) {
                setState(() => _connectionExpanded = value);
              },
            ),
            const SizedBox(height: 12),
            _PlaybackControls(
              speaking: _speaking,
              hasReplay: _lastSpokenText?.trim().isNotEmpty ?? false,
              autoSpeak: _autoSpeak,
              onStop: _stopSpeaking,
              onReplay: _replayLastSpoken,
              onAutoSpeakChanged: (value) => setState(() => _autoSpeak = value),
            ),
            const SizedBox(height: 12),
            _SpeechSettingsPanel(
              language: _ttsLanguage,
              languages: _ttsLanguages,
              engine: _ttsEngine,
              engines: _ttsEngines,
              rate: _ttsRate,
              pitch: _ttsPitch,
              volume: _ttsVolume,
              onLanguageChanged: _setTtsLanguage,
              onEngineChanged: _setTtsEngine,
              onRateChanged: _setTtsRate,
              onPitchChanged: _setTtsPitch,
              onVolumeChanged: _setTtsVolume,
              onSliderChangeEnd: _commitTtsSettings,
              onTest: _testTtsSettings,
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
    required this.blossomPresets,
    required this.ownPubkey,
    required this.connected,
    required this.connecting,
    required this.expanded,
    required this.onGenerateKey,
    required this.onSecretChanged,
    required this.onConnect,
    required this.onDisconnect,
    required this.onExpandedChanged,
  });

  final TextEditingController secretKeyController;
  final TextEditingController peerPubkeyController;
  final TextEditingController relayController;
  final TextEditingController blossomServerController;
  final List<_BlossomPreset> blossomPresets;
  final String? ownPubkey;
  final bool connected;
  final bool connecting;
  final bool expanded;
  final VoidCallback onGenerateKey;
  final ValueChanged<String> onSecretChanged;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final ValueChanged<bool> onExpandedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusText = connecting
        ? 'Connecting'
        : connected
        ? 'Connected'
        : 'Disconnected';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onExpandedChanged(!expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      connected ? Icons.cloud_done : Icons.cloud_off,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Relay session',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$statusText${ownPubkey == null ? '' : ' · ${_compactPubkey(ownPubkey!)}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              crossFadeState: expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                          style: theme.textTheme.bodySmall,
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
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'Blossom server',
                      helperText: 'Use auto or choose a public server',
                      suffixIcon: PopupMenuButton<String>(
                        tooltip: 'Choose Blossom server',
                        icon: const Icon(Icons.expand_more),
                        onSelected: (value) =>
                            blossomServerController.text = value,
                        itemBuilder: (context) => [
                          for (final preset in blossomPresets)
                            PopupMenuItem<String>(
                              value: preset.url,
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(preset.label),
                                subtitle: Text(preset.note),
                              ),
                            ),
                        ],
                      ),
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
              secondChild: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  String _compactPubkey(String pubkey) {
    if (pubkey.length <= 18) return pubkey;
    return '${pubkey.substring(0, 10)}...${pubkey.substring(pubkey.length - 6)}';
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({
    required this.speaking,
    required this.hasReplay,
    required this.autoSpeak,
    required this.onStop,
    required this.onReplay,
    required this.onAutoSpeakChanged,
  });

  final bool speaking;
  final bool hasReplay;
  final bool autoSpeak;
  final VoidCallback onStop;
  final VoidCallback onReplay;
  final ValueChanged<bool> onAutoSpeakChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              speaking ? Icons.volume_up : Icons.volume_off,
              color: speaking ? colorScheme.primary : colorScheme.secondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                speaking ? 'Speaking' : 'Speech idle',
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Tooltip(
              message: autoSpeak ? 'Auto speak on' : 'Auto speak off',
              child: Switch(value: autoSpeak, onChanged: onAutoSpeakChanged),
            ),
            IconButton.filledTonal(
              tooltip: 'Replay speech',
              onPressed: hasReplay ? onReplay : null,
              icon: const Icon(Icons.replay),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              tooltip: 'Stop speech',
              onPressed: speaking ? onStop : null,
              icon: const Icon(Icons.stop),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeechSettingsPanel extends StatelessWidget {
  const _SpeechSettingsPanel({
    required this.language,
    required this.languages,
    required this.engine,
    required this.engines,
    required this.rate,
    required this.pitch,
    required this.volume,
    required this.onLanguageChanged,
    required this.onEngineChanged,
    required this.onRateChanged,
    required this.onPitchChanged,
    required this.onVolumeChanged,
    required this.onSliderChangeEnd,
    required this.onTest,
  });

  final String language;
  final List<String> languages;
  final String? engine;
  final List<String> engines;
  final double rate;
  final double pitch;
  final double volume;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<String?> onEngineChanged;
  final ValueChanged<double> onRateChanged;
  final ValueChanged<double> onPitchChanged;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onSliderChangeEnd;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final languageItems = (languages.toSet()..add(language)).toList()..sort();
    final engineValue = engine != null && engines.contains(engine)
        ? engine!
        : '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Voice',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: onTest,
                  icon: const Icon(Icons.record_voice_over),
                  label: const Text('Test'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: languageItems.contains(language)
                  ? language
                  : languageItems.first,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Language',
              ),
              items: [
                for (final item in languageItems)
                  DropdownMenuItem(value: item, child: Text(item)),
              ],
              onChanged: (value) {
                if (value != null) onLanguageChanged(value);
              },
            ),
            if (engines.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: engineValue,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Engine',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('System default'),
                  ),
                  for (final item in engines)
                    DropdownMenuItem(value: item, child: Text(item)),
                ],
                onChanged: (value) => onEngineChanged(
                  value == null || value.isEmpty ? null : value,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _SpeechSlider(
              label: 'Rate',
              value: rate,
              min: 0.1,
              max: 1.0,
              divisions: 18,
              onChanged: onRateChanged,
              onChangeEnd: onSliderChangeEnd,
            ),
            _SpeechSlider(
              label: 'Pitch',
              value: pitch,
              min: 0.5,
              max: 2.0,
              divisions: 30,
              onChanged: onPitchChanged,
              onChangeEnd: onSliderChangeEnd,
            ),
            _SpeechSlider(
              label: 'Volume',
              value: volume,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: onVolumeChanged,
              onChangeEnd: onSliderChangeEnd,
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeechSlider extends StatelessWidget {
  const _SpeechSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(value.toStringAsFixed(2)),
          ],
        ),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          label: value.toStringAsFixed(2),
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
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
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: incoming
          ? colorScheme.surfaceContainerHigh
          : colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(incoming ? Icons.call_received : Icons.call_made),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message.kind,
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _formatTime(message.timestamp),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            MarkdownBody(
              data: message.text,
              selectable: true,
              softLineBreak: true,
            ),
          ],
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
