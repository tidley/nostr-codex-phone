import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
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

const _ttsControlChannel = MethodChannel('nostr_codex_phone/tts_control');

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

class _RepoTarget {
  const _RepoTarget({
    required this.id,
    required this.name,
    required this.pubkey,
    required this.relays,
  });

  final String id;
  final String name;
  final String pubkey;
  final List<String> relays;

  String get displayName {
    final cleaned = name.trim();
    if (cleaned.isNotEmpty) return cleaned;
    return _compactIdentifier(pubkey);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'pubkey': pubkey,
    'relays': relays,
  };

  static _RepoTarget? fromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id']?.toString().trim() ?? '';
    final name = raw['name']?.toString().trim() ?? '';
    final pubkey = raw['pubkey']?.toString().trim() ?? '';
    final rawRelays = raw['relays'];
    final relays = rawRelays is Iterable
        ? rawRelays
              .map((relay) => relay.toString().trim())
              .where((relay) => relay.isNotEmpty)
              .toList()
        : <String>[];
    if (id.isEmpty || pubkey.isEmpty || relays.isEmpty) return null;
    return _RepoTarget(id: id, name: name, pubkey: pubkey, relays: relays);
  }
}

enum _VoiceFormat { opus, wav }

class _VoiceRecordingFormat {
  const _VoiceRecordingFormat({
    required this.format,
    required this.extension,
    required this.contentType,
    required this.encoder,
    required this.bitRate,
  });

  final _VoiceFormat format;
  final String extension;
  final String contentType;
  final AudioEncoder encoder;
  final int bitRate;
}

const _opusVoiceFormat = _VoiceRecordingFormat(
  format: _VoiceFormat.opus,
  extension: 'ogg',
  contentType: 'audio/ogg',
  encoder: AudioEncoder.opus,
  bitRate: 32000,
);

const _wavVoiceFormat = _VoiceRecordingFormat(
  format: _VoiceFormat.wav,
  extension: 'wav',
  contentType: 'audio/wav',
  encoder: AudioEncoder.wav,
  bitRate: 256000,
);

String _compactIdentifier(String value) {
  if (value.length <= 18) return value;
  return '${value.substring(0, 10)}...${value.substring(value.length - 6)}';
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
  static const _repoTargetsStorageKey = 'repo_targets_v1';
  static const _selectedRepoTargetStorageKey = 'selected_repo_target_id';
  static const _blossomServerStorageKey = 'blossom_server';
  static const _ttsLanguageStorageKey = 'tts_language';
  static const _ttsEngineStorageKey = 'tts_engine';
  static const _ttsRateStorageKey = 'tts_rate';
  static const _ttsPitchStorageKey = 'tts_pitch';
  static const _ttsVolumeStorageKey = 'tts_volume';

  final _secretKeyController = TextEditingController();
  final _targetNameController = TextEditingController();
  final _peerPubkeyController = TextEditingController();
  final _relayController = TextEditingController();
  final _blossomServerController = TextEditingController();
  final _queryController = TextEditingController();
  final _recorder = AudioRecorder();
  final _tts = FlutterTts();
  final _messagesByTarget = <String, List<ConversationMessage>>{};
  final _seenIncomingEventIds = <String>{};

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
  bool _wavRetryRequested = false;
  List<_RepoTarget> _repoTargets = const [];
  String? _selectedRepoTargetId;
  double _ttsRate = 0.48;
  double _ttsPitch = 1.0;
  double _ttsVolume = 1.0;
  String _ttsLanguage = 'en-US';
  String? _ttsEngine;
  List<String> _ttsLanguages = const ['en-US'];
  List<String> _ttsEngines = const [];
  int _speechGeneration = 0;
  DateTime? _autoSpeakSuppressedUntil;
  String? _lastSpokenText;
  String? _recordingPath;
  _VoiceRecordingFormat? _activeRecordingFormat;
  String? _ownPubkey;
  String? _status;

  String get _activeConversationKey {
    final selected = _selectedRepoTargetId;
    if (selected != null && selected.isNotEmpty) return selected;
    final peer = _peerPubkeyController.text.trim();
    if (peer.isNotEmpty) return peer;
    return 'default';
  }

  List<ConversationMessage> get _messages =>
      _messagesByTarget.putIfAbsent(_activeConversationKey, () => []);

  @override
  void initState() {
    super.initState();
    _configureTtsHandlers();
    unawaited(_loadSettings());
  }

  @override
  void dispose() {
    _polling = false;
    final recordingPath = _recordingPath;
    unawaited(_recorder.dispose());
    if (recordingPath != null) {
      unawaited(_deleteTempAudio(recordingPath));
    }
    _tts.stop();
    _secretKeyController.dispose();
    _targetNameController.dispose();
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
    final repoTargets = await _storage.read(key: _repoTargetsStorageKey);
    final selectedRepoTarget = await _storage.read(
      key: _selectedRepoTargetStorageKey,
    );
    final blossomServer = await _storage.read(key: _blossomServerStorageKey);
    final ttsLanguage = await _storage.read(key: _ttsLanguageStorageKey);
    final ttsEngine = await _storage.read(key: _ttsEngineStorageKey);
    final ttsRate = await _storage.read(key: _ttsRateStorageKey);
    final ttsPitch = await _storage.read(key: _ttsPitchStorageKey);
    final ttsVolume = await _storage.read(key: _ttsVolumeStorageKey);

    final migratedRelays = relays?.replaceAll(',', '\n') ?? defaultRelays;
    final targets = _decodeRepoTargets(repoTargets);
    if (targets.isEmpty && _cleanStoredString(peerPubkey) != null) {
      targets.add(
        _RepoTarget(
          id: _newRepoTargetId(),
          name: 'Default repo',
          pubkey: peerPubkey!.trim(),
          relays: _splitRelayText(migratedRelays),
        ),
      );
    }
    final selectedTarget =
        _targetById(targets, selectedRepoTarget) ??
        (targets.isNotEmpty ? targets.first : null);

    if (!mounted) return;
    setState(() {
      _secretKeyController.text = secretKey ?? '';
      _repoTargets = targets;
      _selectedRepoTargetId = selectedTarget?.id;
      _targetNameController.text = selectedTarget?.name ?? '';
      _peerPubkeyController.text = selectedTarget?.pubkey ?? peerPubkey ?? '';
      _relayController.text = selectedTarget == null
          ? migratedRelays
          : selectedTarget.relays.join('\n');
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
    _saveActiveRepoTargetInMemory();
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
    await _storage.write(
      key: _repoTargetsStorageKey,
      value: jsonEncode(_repoTargets.map((target) => target.toJson()).toList()),
    );
    final selectedTargetId = _selectedRepoTargetId;
    if (selectedTargetId == null || selectedTargetId.isEmpty) {
      await _storage.delete(key: _selectedRepoTargetStorageKey);
    } else {
      await _storage.write(
        key: _selectedRepoTargetStorageKey,
        value: selectedTargetId,
      );
    }
    await _saveTtsSettings();
  }

  List<_RepoTarget> _decodeRepoTargets(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final targets = <_RepoTarget>[];
      final seenIds = <String>{};
      for (final item in decoded) {
        final target = _RepoTarget.fromJson(item);
        if (target == null || !seenIds.add(target.id)) continue;
        targets.add(target);
      }
      return targets;
    } catch (_) {
      return [];
    }
  }

  _RepoTarget? _targetById(List<_RepoTarget> targets, String? id) {
    final cleaned = _cleanStoredString(id);
    if (cleaned == null) return null;
    for (final target in targets) {
      if (target.id == cleaned) return target;
    }
    return null;
  }

  String _newRepoTargetId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  List<String> _splitRelayText(String value) => value
      .split(RegExp(r'[\n,]'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  String _defaultTargetName(String pubkey) {
    if (pubkey.trim().isEmpty) return 'Repo';
    return 'Repo ${_compactIdentifier(pubkey.trim())}';
  }

  _RepoTarget? _activeRepoTargetFromControllers() {
    final pubkey = _peerPubkeyController.text.trim();
    final relays = _relayLines();
    if (pubkey.isEmpty || relays.isEmpty) return null;

    final name = _targetNameController.text.trim();
    return _RepoTarget(
      id: _selectedRepoTargetId ?? _newRepoTargetId(),
      name: name.isEmpty ? _defaultTargetName(pubkey) : name,
      pubkey: pubkey,
      relays: relays,
    );
  }

  void _saveActiveRepoTargetInMemory() {
    final target = _activeRepoTargetFromControllers();
    if (target == null) return;

    final targets = [..._repoTargets];
    final index = targets.indexWhere((item) => item.id == target.id);
    if (index == -1) {
      targets.add(target);
    } else {
      targets[index] = target;
    }
    _repoTargets = targets;
    _selectedRepoTargetId = target.id;
    _targetNameController.text = target.name;
  }

  Future<void> _saveCurrentRepoTarget() async {
    if (_peerPubkeyController.text.trim().isEmpty || _relayLines().isEmpty) {
      _showError('Target pubkey and relays are required');
      return;
    }
    await _saveSettings();
    if (!mounted) return;
    setState(() => _status = 'Saved target ${_activeTargetName()}');
  }

  Future<void> _createRepoTarget() async {
    if (_recording) {
      await _cancelRecording();
    }
    if (_connected || _connecting) {
      await _disconnect(expand: true);
    }
    if (!mounted) return;
    final defaultRelays = nostrDefaultRelays().join('\n');
    setState(() {
      _selectedRepoTargetId = null;
      _targetNameController.text = '';
      _peerPubkeyController.text = '';
      _relayController.text = defaultRelays;
      _seenIncomingEventIds.clear();
      _wavRetryRequested = false;
      _status = 'New repo target';
      _connectionExpanded = true;
    });
  }

  Future<void> _deleteSelectedRepoTarget() async {
    final selectedId = _selectedRepoTargetId;
    if (selectedId == null) return;
    final nextTargets = _repoTargets
        .where((target) => target.id != selectedId)
        .toList();
    final nextTarget = nextTargets.isNotEmpty ? nextTargets.first : null;

    if (_recording) {
      await _cancelRecording();
    }
    if (_connected || _connecting) {
      await _disconnect(expand: true);
    }
    if (!mounted) return;
    setState(() {
      _repoTargets = nextTargets;
      _applyRepoTargetFields(nextTarget);
      _seenIncomingEventIds.clear();
      _wavRetryRequested = false;
      _status = nextTarget == null
          ? 'Deleted target'
          : 'Deleted target, selected ${nextTarget.displayName}';
    });
    await _saveSettings();
  }

  Future<void> _selectRepoTarget(String targetId) async {
    if (targetId == _selectedRepoTargetId) return;
    final target = _targetById(_repoTargets, targetId);
    if (target == null) return;

    final reconnect = _connected;
    if (_recording) {
      await _cancelRecording();
    }
    if (_connected || _connecting) {
      await _disconnect(expand: false);
    }
    if (!mounted) return;
    setState(() {
      _applyRepoTargetFields(target);
      _seenIncomingEventIds.clear();
      _wavRetryRequested = false;
      _status = 'Selected ${target.displayName}';
    });
    await _saveSettings();
    if (reconnect && mounted) {
      await _connect();
    }
  }

  void _applyRepoTargetFields(_RepoTarget? target) {
    _selectedRepoTargetId = target?.id;
    _targetNameController.text = target?.name ?? '';
    _peerPubkeyController.text = target?.pubkey ?? '';
    _relayController.text =
        target?.relays.join('\n') ?? nostrDefaultRelays().join('\n');
  }

  String _activeTargetName() {
    final selected = _targetById(_repoTargets, _selectedRepoTargetId);
    if (selected != null) return selected.displayName;
    final name = _targetNameController.text.trim();
    if (name.isNotEmpty) return name;
    final peer = _peerPubkeyController.text.trim();
    if (peer.isNotEmpty) return _defaultTargetName(peer);
    return 'No target';
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
      if (Platform.isAndroid) {
        await _tts.setQueueMode(0);
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
    await _speak(
      'Text to speech test. Rate, pitch, and volume are active.',
      manual: true,
    );
  }

  bool get _autoSpeakSuppressed {
    final until = _autoSpeakSuppressedUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  void _clearAutoSpeakSuppression() {
    _autoSpeakSuppressedUntil = null;
  }

  void _suppressAutoSpeakBriefly() {
    _autoSpeakSuppressedUntil = DateTime.now().add(const Duration(seconds: 3));
  }

  Future<void> _ignoreTtsFailure(Future<dynamic> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Stop paths should be best-effort. The visible status is updated once.
    }
  }

  Future<void> _nativeAndroidTtsStop() async {
    if (!Platform.isAndroid) return;
    await _ignoreTtsFailure(
      () => _ttsControlChannel.invokeMethod<void>('hardStop'),
    );
  }

  Future<void> _stopTtsEngines() async {
    await _ignoreTtsFailure(() => _tts.pause());
    await _ignoreTtsFailure(() => _tts.stop());
    await _nativeAndroidTtsStop();
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

  Future<void> _disconnect({bool expand = true}) async {
    _polling = false;
    await nostrStop();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _connectionExpanded = expand;
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
    final eventId = message.eventId.trim();
    if (eventId.isNotEmpty && !_seenIncomingEventIds.add(eventId)) {
      return;
    }

    final conversationMessage = ConversationMessage(
      direction: MessageDirection.incoming,
      kind: message.kind,
      text: message.text,
      eventId: message.eventId,
      timestamp: DateTime.now(),
    );
    final audioRetryRequested = message.kind == 'audio_retry';
    setState(() {
      _messages.insert(0, conversationMessage);
      if (audioRetryRequested) {
        _wavRetryRequested = true;
        _status = 'Server requested WAV retry';
      } else {
        _status = 'Received ${message.kind}';
      }
    });

    if (_autoSpeak &&
        !_autoSpeakSuppressed &&
        (message.kind == 'response' ||
            message.kind == 'audio_retry' ||
            message.kind == 'error' ||
            message.kind == 'invalid')) {
      unawaited(_speak(message.text, remember: true, manual: false));
    }
  }

  Future<void> _speak(
    String text, {
    bool remember = false,
    bool manual = true,
  }) async {
    if (!manual && _autoSpeakSuppressed) return;
    if (manual) _clearAutoSpeakSuppression();

    final spoken = cleanTextForSpeech(text);
    if (spoken.isEmpty) return;
    final generation = ++_speechGeneration;

    try {
      await _tts.stop();
      if (generation != _speechGeneration) return;
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
    final generation = ++_speechGeneration;
    _suppressAutoSpeakBriefly();
    if (mounted) {
      setState(() {
        _speaking = false;
        _status = 'Stopping speech...';
      });
    }

    try {
      await _stopTtsEngines();
      if (Platform.isAndroid) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (generation == _speechGeneration) {
          await _stopTtsEngines();
        }
      }
    } finally {
      if (mounted && generation == _speechGeneration) {
        setState(() {
          _speaking = false;
          _status = 'Speech stopped';
        });
      }
    }
  }

  Future<void> _replayLastSpoken() async {
    final text = _lastSpokenText;
    if (text == null || text.trim().isEmpty) return;
    await _speak(text, manual: true);
  }

  Future<void> _sendQuery() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;
    if (_sending) return;
    if (!_connected) {
      _showError('Connect before sending a query');
      return;
    }
    _clearAutoSpeakSuppression();

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

  bool _isResendableMessage(ConversationMessage message) {
    if (message.kind == 'query' &&
        message.direction == MessageDirection.outgoing &&
        message.text.trim().isNotEmpty) {
      return true;
    }
    if (message.kind == 'transcript' &&
        message.direction == MessageDirection.incoming &&
        message.text.trim().isNotEmpty) {
      return true;
    }
    return message.kind == 'audio' &&
        message.direction == MessageDirection.outgoing &&
        message.audio != null;
  }

  bool _canResendMessage(ConversationMessage message) {
    return _isResendableMessage(message) &&
        _connected &&
        !_sending &&
        !_sendingAudio &&
        !_recording;
  }

  Future<void> _resendMessage(ConversationMessage message) async {
    if (!_canResendMessage(message)) return;
    _clearAutoSpeakSuppression();

    final audio = message.audio;
    if (audio != null && message.kind == 'audio') {
      await _resendAudioMessage(audio);
      return;
    }

    final query = message.text.trim();
    if (query.isEmpty) return;
    await _resendTextMessage(
      query,
      fromTranscript: message.kind == 'transcript',
    );
  }

  Future<void> _resendTextMessage(
    String query, {
    required bool fromTranscript,
  }) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _status = fromTranscript
          ? 'Sending transcript as query...'
          : 'Resending query...';
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
        _status = fromTranscript ? 'Transcript sent' : 'Query resent';
      });
    } catch (error) {
      _showError('Resend failed: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _resendAudioMessage(BridgeAudioReference audio) async {
    if (_sendingAudio) return;
    setState(() {
      _sendingAudio = true;
      _status = 'Resending voice note...';
    });

    try {
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
            audio: audio,
          ),
        );
        _status = 'Voice note resent';
      });
    } catch (error) {
      _showError('Voice resend failed: $error');
    } finally {
      if (mounted) setState(() => _sendingAudio = false);
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
    _clearAutoSpeakSuppression();

    String? path;
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        _showError('Microphone permission denied');
        return;
      }

      await _saveSettings();
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final recordingFormat = _wavRetryRequested
          ? _wavVoiceFormat
          : _opusVoiceFormat;
      path =
          '${directory.path}/nostr_codex_voice_$timestamp.${recordingFormat.extension}';
      await _recorder.start(
        RecordConfig(
          encoder: recordingFormat.encoder,
          bitRate: recordingFormat.bitRate,
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
        _recordingPath = path;
        _activeRecordingFormat = recordingFormat;
        _status = recordingFormat.format == _VoiceFormat.wav
            ? 'Recording WAV retry...'
            : 'Recording voice query...';
      });
    } catch (error) {
      if (path != null) unawaited(_deleteTempAudio(path));
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recordingPath = null;
        _activeRecordingFormat = null;
      });
      _showError('Recording failed: $error');
    }
  }

  Future<void> _stopAndSendRecording() async {
    final fallbackPath = _recordingPath;
    final recordingFormat = _activeRecordingFormat ?? _opusVoiceFormat;
    String? path;
    try {
      path = await _recorder.stop();
      path = _usableAudioPath(path, fallbackPath);
    } catch (error) {
      if (mounted) {
        setState(() {
          _recording = false;
          _recordingPath = null;
          _activeRecordingFormat = null;
        });
        _showError('Stop recording failed: $error');
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordingPath = null;
      _activeRecordingFormat = null;
      _sendingAudio = true;
      _status = 'Uploading voice note to Blossom...';
    });

    if (path == null) {
      _showError('Recording did not produce an audio file');
      if (mounted) setState(() => _sendingAudio = false);
      return;
    }

    try {
      final fileName = path.split(Platform.pathSeparator).last;
      final audio = await _uploadAudioToBlossom(
        path,
        fileName,
        recordingFormat.contentType,
      );

      if (!mounted) return;
      setState(() => _status = 'Sending Blossom audio reference...');

      final eventId = await nostrSendAudio(audio: audio);
      if (!mounted) return;
      setState(() {
        if (recordingFormat.format == _VoiceFormat.wav) {
          _wavRetryRequested = false;
        }
        _messages.insert(
          0,
          ConversationMessage(
            direction: MessageDirection.outgoing,
            kind: 'audio',
            text: _audioSummary(audio),
            eventId: eventId,
            timestamp: DateTime.now(),
            audio: audio,
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

  Future<void> _cancelRecording() async {
    if (!_recording) return;

    final fallbackPath = _recordingPath;
    String? path;
    Object? stopError;
    try {
      path = await _recorder.stop();
    } catch (error) {
      stopError = error;
    }

    final deletePath = _usableAudioPath(path, fallbackPath);
    if (deletePath != null) {
      unawaited(_deleteTempAudio(deletePath));
    }

    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordingPath = null;
      _activeRecordingFormat = null;
      _status = stopError == null
          ? 'Recording cancelled'
          : 'Cancel recording failed: $stopError';
    });

    if (stopError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cancel recording failed: $stopError')),
      );
    }
  }

  String? _usableAudioPath(String? primary, String? fallback) {
    final cleanedPrimary = primary?.trim();
    if (cleanedPrimary != null && cleanedPrimary.isNotEmpty) {
      return cleanedPrimary;
    }
    final cleanedFallback = fallback?.trim();
    if (cleanedFallback != null && cleanedFallback.isNotEmpty) {
      return cleanedFallback;
    }
    return null;
  }

  Future<BridgeAudioReference> _uploadAudioToBlossom(
    String path,
    String fileName,
    String contentType,
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
            contentType: contentType,
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
              repoTargets: _repoTargets,
              selectedRepoTargetId: _selectedRepoTargetId,
              activeTargetName: _activeTargetName(),
              targetNameController: _targetNameController,
              secretKeyController: _secretKeyController,
              peerPubkeyController: _peerPubkeyController,
              relayController: _relayController,
              blossomServerController: _blossomServerController,
              blossomPresets: _blossomPresets,
              ownPubkey: _ownPubkey,
              connected: _connected,
              connecting: _connecting,
              speaking: _speaking,
              hasReplay: _lastSpokenText?.trim().isNotEmpty ?? false,
              autoSpeak: _autoSpeak,
              language: _ttsLanguage,
              languages: _ttsLanguages,
              engine: _ttsEngine,
              engines: _ttsEngines,
              rate: _ttsRate,
              pitch: _ttsPitch,
              volume: _ttsVolume,
              expanded: _connectionExpanded,
              onTargetChanged: (value) {
                if (value != null) unawaited(_selectRepoTarget(value));
              },
              onSaveTarget: () => unawaited(_saveCurrentRepoTarget()),
              onNewTarget: () => unawaited(_createRepoTarget()),
              onDeleteTarget: _selectedRepoTargetId == null
                  ? null
                  : () => unawaited(_deleteSelectedRepoTarget()),
              onGenerateKey: _generateKey,
              onSecretChanged: (_) => _refreshOwnPubkey(),
              onConnect: _connect,
              onDisconnect: _disconnect,
              onStop: _stopSpeaking,
              onReplay: _replayLastSpoken,
              onAutoSpeakChanged: (value) {
                if (value) _clearAutoSpeakSuppression();
                setState(() => _autoSpeak = value);
                if (!value) unawaited(_stopSpeaking());
              },
              onLanguageChanged: _setTtsLanguage,
              onEngineChanged: _setTtsEngine,
              onRateChanged: _setTtsRate,
              onPitchChanged: _setTtsPitch,
              onVolumeChanged: _setTtsVolume,
              onSliderChangeEnd: _commitTtsSettings,
              onTest: _testTtsSettings,
              onExpandedChanged: (value) {
                setState(() => _connectionExpanded = value);
              },
            ),
            const SizedBox(height: 16),
            _Composer(
              controller: _queryController,
              connected: _connected,
              sending: _sending,
              sendingAudio: _sendingAudio,
              recording: _recording,
              wavRetryRequested: _wavRetryRequested,
              onMicPressed: _toggleRecording,
              onCancelRecording: _cancelRecording,
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
              ..._messages.map(
                (message) => _MessageTile(
                  message: message,
                  showResend: _isResendableMessage(message),
                  onResend: _canResendMessage(message)
                      ? () => _resendMessage(message)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({
    required this.repoTargets,
    required this.selectedRepoTargetId,
    required this.activeTargetName,
    required this.targetNameController,
    required this.secretKeyController,
    required this.peerPubkeyController,
    required this.relayController,
    required this.blossomServerController,
    required this.blossomPresets,
    required this.ownPubkey,
    required this.connected,
    required this.connecting,
    required this.speaking,
    required this.hasReplay,
    required this.autoSpeak,
    required this.language,
    required this.languages,
    required this.engine,
    required this.engines,
    required this.rate,
    required this.pitch,
    required this.volume,
    required this.expanded,
    required this.onTargetChanged,
    required this.onSaveTarget,
    required this.onNewTarget,
    required this.onDeleteTarget,
    required this.onGenerateKey,
    required this.onSecretChanged,
    required this.onConnect,
    required this.onDisconnect,
    required this.onStop,
    required this.onReplay,
    required this.onAutoSpeakChanged,
    required this.onLanguageChanged,
    required this.onEngineChanged,
    required this.onRateChanged,
    required this.onPitchChanged,
    required this.onVolumeChanged,
    required this.onSliderChangeEnd,
    required this.onTest,
    required this.onExpandedChanged,
  });

  final List<_RepoTarget> repoTargets;
  final String? selectedRepoTargetId;
  final String activeTargetName;
  final TextEditingController targetNameController;
  final TextEditingController secretKeyController;
  final TextEditingController peerPubkeyController;
  final TextEditingController relayController;
  final TextEditingController blossomServerController;
  final List<_BlossomPreset> blossomPresets;
  final String? ownPubkey;
  final bool connected;
  final bool connecting;
  final bool speaking;
  final bool hasReplay;
  final bool autoSpeak;
  final String language;
  final List<String> languages;
  final String? engine;
  final List<String> engines;
  final double rate;
  final double pitch;
  final double volume;
  final bool expanded;
  final ValueChanged<String?> onTargetChanged;
  final VoidCallback onSaveTarget;
  final VoidCallback onNewTarget;
  final VoidCallback? onDeleteTarget;
  final VoidCallback onGenerateKey;
  final ValueChanged<String> onSecretChanged;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onStop;
  final VoidCallback onReplay;
  final ValueChanged<bool> onAutoSpeakChanged;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<String?> onEngineChanged;
  final ValueChanged<double> onRateChanged;
  final ValueChanged<double> onPitchChanged;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onSliderChangeEnd;
  final VoidCallback onTest;
  final ValueChanged<bool> onExpandedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusText = connecting
        ? 'Connecting'
        : connected
        ? 'Connected'
        : 'Disconnected';
    final colorScheme = theme.colorScheme;
    final languageItems = (languages.toSet()..add(language)).toList()..sort();
    final engineValue = engine != null && engines.contains(engine)
        ? engine!
        : '';
    final targetValue =
        selectedRepoTargetId != null &&
            repoTargets.any((target) => target.id == selectedRepoTargetId)
        ? selectedRepoTargetId
        : null;
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
                            'Session and speech',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$activeTargetName · $statusText · ${speaking ? 'Speaking' : 'Speech idle'}${ownPubkey == null ? '' : ' · ${_compactPubkey(ownPubkey!)}'}',
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
                  Text('Repo target', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: targetValue,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Active repo service',
                    ),
                    hint: const Text('New unsaved target'),
                    items: [
                      for (final target in repoTargets)
                        DropdownMenuItem(
                          value: target.id,
                          child: Text(
                            target.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: connecting ? null : onTargetChanged,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: targetNameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Target name',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: connecting ? null : onNewTarget,
                        icon: const Icon(Icons.add),
                        label: const Text('New'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: connecting ? null : onSaveTarget,
                        icon: const Icon(Icons.save),
                        label: const Text('Save'),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Delete target',
                        onPressed: connecting ? null : onDeleteTarget,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  Text('Relay session', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
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
                  const Divider(height: 28),
                  Row(
                    children: [
                      Icon(
                        speaking ? Icons.volume_up : Icons.volume_off,
                        color: speaking
                            ? colorScheme.primary
                            : colorScheme.secondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Speech',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Tooltip(
                        message: autoSpeak ? 'Auto speak on' : 'Auto speak off',
                        child: Switch(
                          value: autoSpeak,
                          onChanged: onAutoSpeakChanged,
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Replay speech',
                        onPressed: hasReplay ? onReplay : null,
                        icon: const Icon(Icons.replay),
                      ),
                      const SizedBox(width: 4),
                      IconButton.filled(
                        tooltip: 'Stop speech',
                        onPressed: onStop,
                        icon: const Icon(Icons.stop),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Voice settings',
                          style: theme.textTheme.titleSmall,
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

// ignore: unused_element
class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({
    required this.speaking,
    required this.hasReplay,
    required this.autoSpeak,
    required this.expanded,
    required this.language,
    required this.languages,
    required this.engine,
    required this.engines,
    required this.rate,
    required this.pitch,
    required this.volume,
    required this.onStop,
    required this.onReplay,
    required this.onAutoSpeakChanged,
    required this.onExpandedChanged,
    required this.onLanguageChanged,
    required this.onEngineChanged,
    required this.onRateChanged,
    required this.onPitchChanged,
    required this.onVolumeChanged,
    required this.onSliderChangeEnd,
    required this.onTest,
  });

  final bool speaking;
  final bool hasReplay;
  final bool autoSpeak;
  final bool expanded;
  final String language;
  final List<String> languages;
  final String? engine;
  final List<String> engines;
  final double rate;
  final double pitch;
  final double volume;
  final VoidCallback onStop;
  final VoidCallback onReplay;
  final ValueChanged<bool> onAutoSpeakChanged;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<String?> onEngineChanged;
  final ValueChanged<double> onRateChanged;
  final ValueChanged<double> onPitchChanged;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onSliderChangeEnd;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
                Icon(
                  speaking ? Icons.volume_up : Icons.volume_off,
                  color: speaking ? colorScheme.primary : colorScheme.secondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onExpandedChanged(!expanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Speech', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            speaking ? 'Speaking' : 'Speech idle',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Tooltip(
                  message: autoSpeak ? 'Auto speak on' : 'Auto speak off',
                  child: Switch(
                    value: autoSpeak,
                    onChanged: onAutoSpeakChanged,
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Replay speech',
                  onPressed: hasReplay ? onReplay : null,
                  icon: const Icon(Icons.replay),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  tooltip: 'Stop speech',
                  onPressed: onStop,
                  icon: const Icon(Icons.stop),
                ),
                IconButton(
                  tooltip: expanded
                      ? 'Collapse speech settings'
                      : 'Expand speech settings',
                  onPressed: () => onExpandedChanged(!expanded),
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                ),
              ],
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Voice settings',
                          style: theme.textTheme.titleSmall,
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
              secondChild: const SizedBox.shrink(),
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

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.connected,
    required this.sending,
    required this.sendingAudio,
    required this.recording,
    required this.wavRetryRequested,
    required this.onMicPressed,
    required this.onCancelRecording,
    required this.onSendPressed,
  });

  final TextEditingController controller;
  final bool connected;
  final bool sending;
  final bool sendingAudio;
  final bool recording;
  final bool wavRetryRequested;
  final VoidCallback onMicPressed;
  final VoidCallback onCancelRecording;
  final VoidCallback onSendPressed;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breatheController;
  late final Animation<double> _breathe;

  @override
  void initState() {
    super.initState();
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );
    _breathe = CurvedAnimation(
      parent: _breatheController,
      curve: Curves.easeInOut,
    );
    _syncBreatheAnimation();
  }

  @override
  void didUpdateWidget(covariant _Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recording != widget.recording) {
      _syncBreatheAnimation();
    }
  }

  @override
  void dispose() {
    _breatheController.dispose();
    super.dispose();
  }

  void _syncBreatheAnimation() {
    if (widget.recording) {
      _breatheController.repeat(reverse: true);
    } else {
      _breatheController.stop();
      _breatheController.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: widget.controller,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Query',
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                final busy = widget.sending || widget.sendingAudio;
                final onMainPressed = !widget.connected || busy
                    ? null
                    : widget.recording
                    ? widget.onMicPressed
                    : hasText
                    ? widget.onSendPressed
                    : widget.onMicPressed;
                final icon = busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : widget.recording || hasText
                    ? const Icon(Icons.send)
                    : Icon(
                        widget.wavRetryRequested
                            ? Icons.mic_external_on
                            : Icons.mic,
                      );
                final label = widget.sendingAudio
                    ? 'Sending voice...'
                    : widget.sending
                    ? 'Sending...'
                    : widget.recording || hasText
                    ? 'Send'
                    : widget.wavRetryRequested
                    ? 'Record WAV'
                    : 'Record';
                final tooltip = widget.recording
                    ? 'Send recording'
                    : hasText
                    ? 'Send query'
                    : widget.wavRetryRequested
                    ? 'Record WAV retry'
                    : 'Record voice query';
                final mainButton = Tooltip(
                  message: tooltip,
                  child: FilledButton.icon(
                    onPressed: onMainPressed,
                    icon: icon,
                    label: Text(label),
                  ),
                );

                return Row(
                  children: [
                    if (widget.recording) ...[
                      IconButton.outlined(
                        tooltip: 'Cancel recording',
                        onPressed: busy ? null : widget.onCancelRecording,
                        style: IconButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        icon: const Icon(Icons.close),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: widget.recording
                          ? _BreathingRecordButton(
                              animation: _breathe,
                              child: mainButton,
                            )
                          : mainButton,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BreathingRecordButton extends StatelessWidget {
  const _BreathingRecordButton({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final pulse = animation.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.16 * pulse),
                blurRadius: 18 * pulse,
                spreadRadius: 2 * pulse,
              ),
            ],
          ),
          child: Transform.scale(scale: 1 + (0.025 * pulse), child: child),
        );
      },
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.showResend,
    required this.onResend,
  });

  final ConversationMessage message;
  final bool showResend;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    final incoming = message.direction == MessageDirection.incoming;
    final transcript = message.kind == 'transcript';
    final userSide = !incoming || transcript;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: userSide
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _messageIcon(incoming: incoming, transcript: transcript),
                  color: userSide
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
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
                if (showResend) ...[
                  const SizedBox(width: 4),
                  SizedBox.square(
                    dimension: 36,
                    child: IconButton(
                      tooltip: _resendTooltip(),
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      onPressed: onResend,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                ],
                if (incoming && message.text.trim().isNotEmpty) ...[
                  const SizedBox(width: 4),
                  SizedBox.square(
                    dimension: 36,
                    child: IconButton(
                      tooltip: 'Copy full message',
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      onPressed: () => _copyMessage(context),
                      icon: const Icon(Icons.content_copy),
                    ),
                  ),
                ],
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

  String _resendTooltip() {
    if (message.kind == 'audio') return 'Resend voice note';
    if (message.kind == 'transcript') return 'Send transcript as query';
    return 'Resend query';
  }

  Future<void> _copyMessage(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: message.text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied')));
  }

  IconData _messageIcon({required bool incoming, required bool transcript}) {
    if (transcript) return Icons.notes;
    return incoming ? Icons.call_received : Icons.call_made;
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
    this.audio,
  });

  final MessageDirection direction;
  final String kind;
  final String text;
  final String eventId;
  final DateTime timestamp;
  final BridgeAudioReference? audio;
}
