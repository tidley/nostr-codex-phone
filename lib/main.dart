import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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
const _blossomUploadTimeout = Duration(minutes: 2);
const _nostrSendTimeout = Duration(seconds: 15);

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
    this.workdir,
    this.parentPubkey,
    this.parentRelays,
    this.parentWorkdir,
    this.parentName,
  });

  final String id;
  final String name;
  final String pubkey;
  final List<String> relays;
  final String? workdir;
  final String? parentPubkey;
  final List<String>? parentRelays;
  final String? parentWorkdir;
  final String? parentName;

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
    if (workdir != null && workdir!.trim().isNotEmpty) 'workdir': workdir,
    if (parentPubkey != null && parentPubkey!.trim().isNotEmpty)
      'parent_pubkey': parentPubkey,
    if (parentRelays != null && parentRelays!.isNotEmpty)
      'parent_relays': parentRelays,
    if (parentWorkdir != null && parentWorkdir!.trim().isNotEmpty)
      'parent_workdir': parentWorkdir,
    if (parentName != null && parentName!.trim().isNotEmpty)
      'parent_name': parentName,
  };

  static _RepoTarget? fromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id']?.toString().trim() ?? '';
    final name = raw['name']?.toString().trim() ?? '';
    final pubkey = raw['pubkey']?.toString().trim() ?? '';
    final workdir = raw['workdir']?.toString().trim();
    final parentPubkey = raw['parent_pubkey']?.toString().trim();
    final parentWorkdir = raw['parent_workdir']?.toString().trim();
    final parentName = raw['parent_name']?.toString().trim();
    final rawRelays = raw['relays'];
    final relays = rawRelays is Iterable
        ? rawRelays
              .map((relay) => relay.toString().trim())
              .where((relay) => relay.isNotEmpty)
              .toList()
        : <String>[];
    final rawParentRelays = raw['parent_relays'];
    final parentRelays = rawParentRelays is Iterable
        ? rawParentRelays
              .map((relay) => relay.toString().trim())
              .where((relay) => relay.isNotEmpty)
              .toList()
        : <String>[];
    if (id.isEmpty || pubkey.isEmpty || relays.isEmpty) return null;
    return _RepoTarget(
      id: id,
      name: name,
      pubkey: pubkey,
      relays: relays,
      workdir: workdir == null || workdir.isEmpty ? null : workdir,
      parentPubkey: parentPubkey == null || parentPubkey.isEmpty
          ? null
          : parentPubkey,
      parentRelays: parentRelays.isEmpty ? null : parentRelays,
      parentWorkdir: parentWorkdir == null || parentWorkdir.isEmpty
          ? null
          : parentWorkdir,
      parentName: parentName == null || parentName.isEmpty ? null : parentName,
    );
  }
}

class _RepoChoice {
  const _RepoChoice({
    required this.name,
    required this.path,
    required this.relativePath,
    required this.isGitRepo,
  });

  final String name;
  final String path;
  final String relativePath;
  final bool isGitRepo;

  String get displayName => relativePath.isEmpty ? name : relativePath;

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'relative_path': relativePath,
    'is_git_repo': isGitRepo,
  };

  static _RepoChoice? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final name = raw['name']?.toString().trim() ?? '';
    final path = raw['path']?.toString().trim() ?? '';
    final relativePath = raw['relative_path']?.toString().trim() ?? '';
    if (name.isEmpty || path.isEmpty || relativePath.isEmpty) return null;
    return _RepoChoice(
      name: name,
      path: path,
      relativePath: relativePath,
      isGitRepo: raw['is_git_repo'] == true,
    );
  }
}

enum _PendingMessageCompletion { transcript, response }

enum _WorkingAnimationStyle {
  off('off', 'Off'),
  digitalFlow('digital_flow', 'Digital flow'),
  neuralLattice('neural_lattice', 'Neural lattice'),
  orbitSync('orbit_sync', 'Orbit sync'),
  scanLine('scan_line', 'Scan line'),
  dataPackets('data_packets', 'Data packets'),
  pulseSpectrum('pulse_spectrum', 'Pulse spectrum');

  const _WorkingAnimationStyle(this.storageValue, this.label);

  final String storageValue;
  final String label;
  bool get enabled => this != _WorkingAnimationStyle.off;

  static _WorkingAnimationStyle fromStorage(String? value) {
    final cleaned = value?.trim();
    for (final style in _WorkingAnimationStyle.values) {
      if (style.storageValue == cleaned) return style;
    }
    return _WorkingAnimationStyle.digitalFlow;
  }
}

class _PendingProcessingMessage {
  const _PendingProcessingMessage({
    required this.conversationKey,
    required this.eventId,
    required this.completion,
  });

  final String conversationKey;
  final String eventId;
  final _PendingMessageCompletion completion;
}

class _PendingSessionStart {
  const _PendingSessionStart({required this.workdir, required this.completer});

  final String workdir;
  final Completer<_RepoTarget> completer;
}

class _MediaUploadCancelledException implements Exception {
  const _MediaUploadCancelledException({
    required this.server,
    required this.sessionId,
  });

  final String server;
  final int sessionId;

  @override
  String toString() =>
      'Media upload cancelled (session=$sessionId, server=$server)';
}

enum _MediaSource { camera, photoPicker, filePicker }

class _MediaSelection {
  const _MediaSelection({
    required this.path,
    required this.fileName,
    required this.extension,
    required this.contentType,
  });

  final String path;
  final String fileName;
  final String? extension;
  final String contentType;
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

int bridgeUIntToJsonInt(BigInt value) {
  if (value.isNegative) {
    throw ArgumentError.value(value, 'value', 'integer must be non-negative');
  }
  final converted = value.toInt();
  if (BigInt.from(converted) != value) {
    throw ArgumentError.value(value, 'value', 'integer is too large for JSON');
  }
  return converted;
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
  static const _workingAnimationStorageKey = 'working_animation_style';
  static const _hapticFeedbackStorageKey = 'haptic_feedback_enabled';
  static const _conversationHistoryStorageKey = 'conversation_history_v1';
  static const _seenIncomingEventIdsStorageKey = 'seen_incoming_event_ids_v1';
  static const _unreadCountsStorageKey = 'unread_counts_v1';
  static const _repoChoicesStorageKey = 'repo_choices_v1';
  static const _recentMessagesWindow = Duration(hours: 1);
  static const _maxConversationMessages = 200;
  static const _maxSeenIncomingEventIds = 5000;
  static const _catchUpLookback = Duration(days: 4);

  final _secretKeyController = TextEditingController();
  final _targetNameController = TextEditingController();
  final _peerPubkeyController = TextEditingController();
  final _relayController = TextEditingController();
  final _blossomServerController = TextEditingController();
  final _queryController = TextEditingController();
  final _queryFocusNode = FocusNode();
  final _recorder = AudioRecorder();
  final _tts = FlutterTts();
  final _messagesByTarget = <String, List<ConversationMessage>>{};
  final _seenIncomingEventIds = <String>{};
  final _unreadCountsByTarget = <String, int>{};
  final _pendingReplyTargetIds = <String>{};
  final ScrollController _chatScrollController = ScrollController();

  bool _loadingSettings = true;
  bool _connecting = false;
  bool _connected = false;
  bool _polling = false;
  bool _sending = false;
  bool _recording = false;
  bool _sendingAudio = false;
  bool _sendingMedia = false;
  String? _sendingConversationKey;
  String? _sendingAudioConversationKey;
  String? _sendingMediaConversationKey;
  String? _connectedPeerPubkey;
  List<String> _connectedRelays = const [];
  bool _mediaUploadCancelled = false;
  int _mediaUploadSessionId = 0;
  Completer<void>? _mediaUploadCancelCompleter;
  DateTime? _recordingStartedAt;
  Timer? _recordingTimer;
  final _pendingProcessingMessages = <_PendingProcessingMessage>[];
  Completer<List<_RepoChoice>>? _pendingRepoListCompleter;
  _PendingSessionStart? _pendingSessionStart;
  List<_RepoChoice> _cachedRepoChoices = const [];
  bool _autoSpeak = true;
  bool _speaking = false;
  bool _wavRetryRequested = false;
  List<_RepoTarget> _repoTargets = const [];
  String? _selectedRepoTargetId;
  double _ttsRate = 0.48;
  double _ttsPitch = 1.0;
  double _ttsVolume = 1.0;
  _WorkingAnimationStyle _workingAnimationStyle =
      _WorkingAnimationStyle.digitalFlow;
  bool _hapticFeedbackEnabled = true;
  String _ttsLanguage = 'en-US';
  String? _ttsEngine;
  List<String> _ttsLanguages = const ['en-US'];
  List<String> _ttsEngines = const [];
  int _speechGeneration = 0;
  String? _speakingMessageEventId;
  DateTime? _autoSpeakSuppressedUntil;
  String? _lastSpokenText;
  String? _recordingPath;
  _VoiceRecordingFormat? _activeRecordingFormat;
  String? _ownPubkey;
  String? _status;
  _MediaSelection? _pendingMediaAttachment;
  String? _pendingMediaFileName;

  bool get _hasPendingMediaAttachment => _pendingMediaAttachment != null;

  String get _recordingDurationLabel {
    if (_recordingStartedAt == null) return '00:00';
    final elapsed = DateTime.now().difference(_recordingStartedAt!);
    final totalSeconds = elapsed.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get _activeConversationKey {
    final selected = _selectedRepoTargetId;
    if (selected != null && selected.isNotEmpty) return selected;
    final peer = _peerPubkeyController.text.trim();
    if (peer.isNotEmpty) return peer;
    return 'default';
  }

  List<ConversationMessage> get _messages =>
      _messagesByTarget.putIfAbsent(_activeConversationKey, () => []);

  bool get _sendingInActiveConversation =>
      _sending && _sendingConversationKey == _activeConversationKey;

  bool get _sendingAudioInActiveConversation =>
      _sendingAudio && _sendingAudioConversationKey == _activeConversationKey;

  bool get _sendingMediaInActiveConversation =>
      _sendingMedia && _sendingMediaConversationKey == _activeConversationKey;

  List<ConversationMessage> get _recentMessagesForActiveConversation {
    final now = DateTime.now();
    final cutoff = now.subtract(_recentMessagesWindow);
    final filtered = _messages
        .where(
          (message) =>
              message.timestamp.isAfter(cutoff) ||
              message.timestamp.isAtSameMomentAs(cutoff),
        )
        .toList();
    return filtered.reversed.toList();
  }

  Future<void> _loadConversationHistoryForActiveSession() async {
    final activeKey = _activeConversationKey;
    final loaded = await _readConversationHistory(activeKey);
    if (!mounted || _activeConversationKey != activeKey) return;
    setState(() {
      _messagesByTarget[activeKey] = _mergeConversationMessages(
        _messagesByTarget[activeKey] ?? const [],
        loaded,
      );
    });
    _scrollToLatestMessage();
  }

  List<ConversationMessage> _mergeConversationMessages(
    List<ConversationMessage> current,
    List<ConversationMessage> loaded,
  ) {
    final byKey = <String, ConversationMessage>{};
    for (final message in loaded.reversed.followedBy(current.reversed)) {
      final eventId = message.eventId.trim();
      final key = eventId.isEmpty
          ? '${message.direction.name}:${message.kind}:${message.timestamp.toIso8601String()}:${message.text}'
          : eventId;
      byKey[key] = message;
    }
    final merged = byKey.values.toList()
      ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
    return merged.take(_maxConversationMessages).toList();
  }

  void _scrollToLatestMessage() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chatScrollController.hasClients) return;
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _dismissQueryKeyboard() {
    _queryFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void initState() {
    super.initState();
    _configureTtsHandlers();
    unawaited(_loadSettings());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _dismissQueryKeyboard();
    });
  }

  @override
  void dispose() {
    _polling = false;
    final recordingPath = _recordingPath;
    unawaited(_recorder.dispose());
    if (recordingPath != null) {
      unawaited(_deleteTempAudio(recordingPath));
    }
    _recordingTimer?.cancel();
    _tts.stop();
    _chatScrollController.dispose();
    _secretKeyController.dispose();
    _targetNameController.dispose();
    _peerPubkeyController.dispose();
    _relayController.dispose();
    _blossomServerController.dispose();
    _queryController.dispose();
    _queryFocusNode.dispose();
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
    final workingAnimation = await _storage.read(
      key: _workingAnimationStorageKey,
    );
    final hapticFeedback = await _storage.read(key: _hapticFeedbackStorageKey);
    final seenEventIds = await _storage.read(
      key: _seenIncomingEventIdsStorageKey,
    );
    final unreadCounts = await _storage.read(key: _unreadCountsStorageKey);
    final repoChoices = await _storage.read(key: _repoChoicesStorageKey);

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
      _workingAnimationStyle = _WorkingAnimationStyle.fromStorage(
        workingAnimation,
      );
      _hapticFeedbackEnabled = _storedBool(hapticFeedback, true);
      _seenIncomingEventIds
        ..clear()
        ..addAll(_decodeSeenEventIds(seenEventIds));
      _unreadCountsByTarget
        ..clear()
        ..addAll(_decodeUnreadCounts(unreadCounts));
      _cachedRepoChoices = _decodeRepoChoicesCache(repoChoices);
      _loadingSettings = false;
    });
    await _loadConversationHistoryForActiveSession();
    _dismissQueryKeyboard();
    _refreshOwnPubkey();
    await _applyTtsSettings();
    unawaited(_loadTtsOptions());
  }

  void _configureTtsHandlers() {
    _tts.setStartHandler(() {
      if (mounted) setState(() => _speaking = true);
    });
    _tts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _speaking = false;
          _speakingMessageEventId = null;
        });
      }
    });
    _tts.setCancelHandler(() {
      if (mounted) {
        setState(() {
          _speaking = false;
          _speakingMessageEventId = null;
        });
      }
    });
    _tts.setErrorHandler((_) {
      if (mounted) {
        setState(() {
          _speaking = false;
          _speakingMessageEventId = null;
        });
      }
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
    await _saveWorkingAnimationStyle();
    await _saveHapticFeedbackEnabled();
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

  List<String> _decodeSeenEventIds(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .take(_maxSeenIncomingEventIds)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, int> _decodeUnreadCounts(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final counts = <String, int>{};
      for (final entry in decoded.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value;
        final count = value is num ? value.toInt() : int.tryParse('$value');
        if (key.isNotEmpty && count != null && count > 0) {
          counts[key] = count;
        }
      }
      return counts;
    } catch (_) {
      return {};
    }
  }

  List<_RepoChoice> _decodeRepoChoicesCache(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final choices = decoded
          .map(_RepoChoice.fromJson)
          .whereType<_RepoChoice>()
          .toList();
      choices.sort(
        (left, right) => left.relativePath.toLowerCase().compareTo(
          right.relativePath.toLowerCase(),
        ),
      );
      return choices;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveSeenIncomingEventIds() async {
    await _storage.write(
      key: _seenIncomingEventIdsStorageKey,
      value: jsonEncode(_seenIncomingEventIds.toList()),
    );
  }

  Future<void> _saveUnreadCounts() async {
    await _storage.write(
      key: _unreadCountsStorageKey,
      value: jsonEncode(_unreadCountsByTarget),
    );
  }

  Future<void> _saveRepoChoicesCache() async {
    await _storage.write(
      key: _repoChoicesStorageKey,
      value: jsonEncode(
        _cachedRepoChoices.map((item) => item.toJson()).toList(),
      ),
    );
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
    final existing = _targetById(_repoTargets, _selectedRepoTargetId);
    return _RepoTarget(
      id: _selectedRepoTargetId ?? _newRepoTargetId(),
      name: name.isEmpty ? _defaultTargetName(pubkey) : name,
      pubkey: pubkey,
      relays: relays,
      workdir: existing?.workdir,
      parentPubkey: existing?.parentPubkey,
      parentRelays: existing?.parentRelays,
      parentWorkdir: existing?.parentWorkdir,
      parentName: existing?.parentName,
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
    await _loadConversationHistoryForActiveSession();
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
      _pendingProcessingMessages.clear();
      _wavRetryRequested = false;
      _messagesByTarget.putIfAbsent('default', () => []);
      _status = 'New repo target';
    });
    await _deleteConversationHistoryForKey('default');
  }

  Future<void> _scanRepoTargetQr() async {
    final payload = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _RepoTargetQrScannerPage()),
    );
    if (!mounted || payload == null || payload.trim().isEmpty) return;

    final target = _repoTargetFromQrPayload(payload);
    if (target == null) {
      _showError('QR did not contain a Nostr Codex target');
      return;
    }

    if (_recording) {
      await _cancelRecording();
    }
    if (_connected || _connecting) {
      await _disconnect(expand: true);
    }
    if (!mounted) return;

    final targets = [..._repoTargets];
    final existingIndex = targets.indexWhere(
      (item) => item.pubkey == target.pubkey,
    );
    final savedTarget = existingIndex == -1
        ? target
        : _RepoTarget(
            id: targets[existingIndex].id,
            name: target.name,
            pubkey: target.pubkey,
            relays: target.relays,
            workdir: target.workdir,
            parentPubkey: target.parentPubkey,
            parentRelays: target.parentRelays,
            parentWorkdir: target.parentWorkdir,
            parentName: target.parentName,
          );
    if (existingIndex == -1) {
      targets.add(savedTarget);
    } else {
      targets[existingIndex] = savedTarget;
    }

    setState(() {
      _repoTargets = targets;
      _applyRepoTargetFields(savedTarget);
      _messagesByTarget.putIfAbsent(savedTarget.id, () => []);
      _wavRetryRequested = false;
      _status = 'Scanned target ${savedTarget.displayName}';
    });
    await _saveSettings();
    await _loadConversationHistoryForActiveSession();
  }

  _RepoTarget? _repoTargetFromQrPayload(String raw) {
    try {
      final payload = raw.trim();
      if (payload.isEmpty) return null;

      final jsonPayload = payload.startsWith('nostr-codex-target:')
          ? _decodeTargetUriPayload(payload)
          : payload;
      if (jsonPayload == null) return null;

      final decoded = jsonDecode(jsonPayload);
      if (decoded is! Map<String, dynamic>) return null;
      final type = decoded['type']?.toString();
      if (type != 'nostr_codex_target' && type != 'nostr-codex-target') {
        return null;
      }

      final pubkey =
          decoded['pubkey']?.toString().trim() ??
          decoded['npub']?.toString().trim() ??
          '';
      if (pubkey.isEmpty) return null;

      final rawRelays = decoded['relays'];
      final relays = rawRelays is Iterable
          ? rawRelays
                .map((relay) => relay.toString().trim())
                .where((relay) => relay.isNotEmpty)
                .toList()
          : _splitRelayText(rawRelays?.toString() ?? '');
      if (relays.isEmpty) return null;

      final workdir = decoded['workdir']?.toString().trim();
      final parent = decoded['parent'];
      final parentPubkey = parent is Map
          ? parent['pubkey']?.toString().trim()
          : decoded['parent_pubkey']?.toString().trim();
      final rawParentRelays = parent is Map
          ? parent['relays']
          : decoded['parent_relays'];
      final parentRelays = rawParentRelays is Iterable
          ? rawParentRelays
                .map((relay) => relay.toString().trim())
                .where((relay) => relay.isNotEmpty)
                .toList()
          : _splitRelayText(rawParentRelays?.toString() ?? '');
      final parentWorkdir = parent is Map
          ? parent['workdir']?.toString().trim()
          : decoded['parent_workdir']?.toString().trim();
      final parentName = parent is Map
          ? parent['name']?.toString().trim()
          : decoded['parent_name']?.toString().trim();
      final rawName = decoded['name']?.toString().trim() ?? '';
      final name = rawName.isNotEmpty
          ? rawName
          : _workdirTargetName(workdir) ?? _defaultTargetName(pubkey);
      return _RepoTarget(
        id: _newRepoTargetId(),
        name: name,
        pubkey: pubkey,
        relays: relays,
        workdir: workdir == null || workdir.isEmpty ? null : workdir,
        parentPubkey: parentPubkey == null || parentPubkey.isEmpty
            ? null
            : parentPubkey,
        parentRelays: parentRelays.isEmpty ? null : parentRelays,
        parentWorkdir: parentWorkdir == null || parentWorkdir.isEmpty
            ? null
            : parentWorkdir,
        parentName: parentName == null || parentName.isEmpty
            ? null
            : parentName,
      );
    } catch (_) {
      return null;
    }
  }

  _RepoTarget? _repoTargetFromInvitePayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final invite = decoded['target_invite'];
      if (invite is! Map<String, dynamic>) return null;
      final type = invite['type']?.toString();
      if (type != 'nostr_codex_target' && type != 'nostr-codex-target') {
        return null;
      }
      final pubkey = invite['pubkey']?.toString().trim() ?? '';
      if (pubkey.isEmpty) return null;
      final rawRelays = invite['relays'];
      final relays = rawRelays is Iterable
          ? rawRelays
                .map((relay) => relay.toString().trim())
                .where((relay) => relay.isNotEmpty)
                .toList()
          : _splitRelayText(rawRelays?.toString() ?? '');
      if (relays.isEmpty) return null;
      final workdir = invite['workdir']?.toString().trim();
      final parent = invite['parent'];
      final parentPubkey = parent is Map
          ? parent['pubkey']?.toString().trim()
          : invite['parent_pubkey']?.toString().trim();
      final rawParentRelays = parent is Map
          ? parent['relays']
          : invite['parent_relays'];
      final parentRelays = rawParentRelays is Iterable
          ? rawParentRelays
                .map((relay) => relay.toString().trim())
                .where((relay) => relay.isNotEmpty)
                .toList()
          : _splitRelayText(rawParentRelays?.toString() ?? '');
      final parentWorkdir = parent is Map
          ? parent['workdir']?.toString().trim()
          : invite['parent_workdir']?.toString().trim();
      final parentName = parent is Map
          ? parent['name']?.toString().trim()
          : invite['parent_name']?.toString().trim();
      final rawName = invite['name']?.toString().trim() ?? '';
      final name = rawName.isNotEmpty
          ? rawName
          : _workdirTargetName(workdir) ?? _defaultTargetName(pubkey);
      return _RepoTarget(
        id: _newRepoTargetId(),
        name: name,
        pubkey: pubkey,
        relays: relays,
        workdir: workdir == null || workdir.isEmpty ? null : workdir,
        parentPubkey: parentPubkey == null || parentPubkey.isEmpty
            ? null
            : parentPubkey,
        parentRelays: parentRelays.isEmpty ? null : parentRelays,
        parentWorkdir: parentWorkdir == null || parentWorkdir.isEmpty
            ? null
            : parentWorkdir,
        parentName: parentName == null || parentName.isEmpty
            ? null
            : parentName,
      );
    } catch (_) {
      return null;
    }
  }

  _RepoTarget _targetWithParentRouteFromMessage(
    _RepoTarget target,
    BridgeIncomingMessage message,
  ) {
    if (target.parentPubkey?.trim().isNotEmpty == true &&
        target.parentRelays?.isNotEmpty == true) {
      return target;
    }

    final parentPubkey = message.senderPubkey.trim().isNotEmpty
        ? message.senderPubkey.trim()
        : message.senderPubkeyHex.trim();
    if (parentPubkey.isEmpty || parentPubkey == target.pubkey) {
      return target;
    }

    final selectedParent = _targetById(_repoTargets, _selectedRepoTargetId);
    final parentRelays = _relayLines().isNotEmpty
        ? _relayLines()
        : target.relays;
    final parentName = selectedParent?.displayName ?? _activeTargetName();

    return _RepoTarget(
      id: target.id,
      name: target.name,
      pubkey: target.pubkey,
      relays: target.relays,
      workdir: target.workdir,
      parentPubkey: parentPubkey,
      parentRelays: parentRelays,
      parentWorkdir: selectedParent?.workdir,
      parentName: parentName,
    );
  }

  List<_RepoChoice>? _repoChoicesFromRepoListPayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final repoList = decoded['repo_list'];
      if (repoList is! Map<String, dynamic>) return null;
      final roots = repoList['roots'];
      if (roots is! Iterable) return const [];
      final choices = <_RepoChoice>[];
      for (final root in roots) {
        if (root is! Map) continue;
        final repos = root['repos'];
        if (repos is! Iterable) continue;
        for (final repo in repos) {
          if (repo is! Map) continue;
          final name = repo['name']?.toString().trim() ?? '';
          final path = repo['path']?.toString().trim() ?? '';
          final relativePath = repo['relative_path']?.toString().trim() ?? '';
          if (name.isEmpty || path.isEmpty || relativePath.isEmpty) continue;
          choices.add(
            _RepoChoice(
              name: name,
              path: path,
              relativePath: relativePath,
              isGitRepo: repo['is_git_repo'] == true,
            ),
          );
        }
      }
      choices.sort(
        (left, right) => left.relativePath.toLowerCase().compareTo(
          right.relativePath.toLowerCase(),
        ),
      );
      return choices;
    } catch (_) {
      return null;
    }
  }

  Future<void> _offerTargetInvite(_RepoTarget target) async {
    if (!mounted) return;
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Session request'),
        content: Text(
          target.workdir == null || target.workdir!.isEmpty
              ? 'Add ${target.displayName}?'
              : 'Add ${target.displayName} at ${target.workdir}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ignore'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    if (accept != true || !mounted) return;
    await _saveAndSelectRepoTarget(target, status: 'Accepted session request');
  }

  Future<void> _saveAndSelectRepoTarget(
    _RepoTarget target, {
    required String status,
  }) async {
    if (_recording) {
      await _cancelRecording();
    }
    if (_connected || _connecting) {
      await _disconnect(expand: false);
    }
    if (!mounted) return;

    final targets = [..._repoTargets];
    final existingIndex = targets.indexWhere(
      (item) => item.pubkey == target.pubkey,
    );
    final savedTarget = existingIndex == -1
        ? target
        : _RepoTarget(
            id: targets[existingIndex].id,
            name: target.name,
            pubkey: target.pubkey,
            relays: target.relays,
            workdir: target.workdir,
            parentPubkey: target.parentPubkey,
            parentRelays: target.parentRelays,
            parentWorkdir: target.parentWorkdir,
            parentName: target.parentName,
          );
    if (existingIndex == -1) {
      targets.add(savedTarget);
    } else {
      targets[existingIndex] = savedTarget;
    }

    setState(() {
      _repoTargets = targets;
      _applyRepoTargetFields(savedTarget);
      _messagesByTarget.putIfAbsent(savedTarget.id, () => []);
      _wavRetryRequested = false;
      _status = '$status: ${savedTarget.displayName}';
    });
    await _saveSettings();
    await _loadConversationHistoryForActiveSession();
  }

  String? _decodeTargetUriPayload(String payload) {
    final encoded = payload.substring('nostr-codex-target:'.length).trim();
    if (encoded.isEmpty) return null;
    try {
      return utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
    } catch (_) {
      return null;
    }
  }

  String? _workdirTargetName(String? workdir) {
    final cleaned = workdir?.trim();
    if (cleaned == null || cleaned.isEmpty) return null;
    final parts = cleaned
        .split(RegExp(r'[/\\]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    return parts.last;
  }

  bool _sameWorkdir(String? left, String? right) {
    final cleanedLeft = left?.trim();
    final cleanedRight = right?.trim();
    return cleanedLeft != null &&
        cleanedLeft.isNotEmpty &&
        cleanedRight != null &&
        cleanedRight.isNotEmpty &&
        cleanedLeft == cleanedRight;
  }

  Future<void> _acceptPendingSessionStart(
    _RepoTarget target,
    Completer<_RepoTarget> completer,
  ) async {
    await _saveAndSelectRepoTarget(target, status: 'Started session');
    if (!completer.isCompleted) {
      completer.complete(target);
    }
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
      if (nextTarget == null) {
        _messagesByTarget['default'] = [];
      } else {
        _messagesByTarget[nextTarget.id] = [];
      }
      _messagesByTarget.remove(selectedId);
      _unreadCountsByTarget.remove(selectedId);
      _pendingReplyTargetIds.remove(selectedId);
      _pendingProcessingMessages.clear();
      _wavRetryRequested = false;
      _status = nextTarget == null
          ? 'Deleted target'
          : 'Deleted target, selected ${nextTarget.displayName}';
    });
    await _deleteConversationHistoryForKey(selectedId);
    await _saveUnreadCounts();
    await _saveSettings();
    await _loadConversationHistoryForActiveSession();
  }

  Future<void> _selectRepoTarget(String targetId) async {
    if (targetId == _selectedRepoTargetId) return;
    final target = _targetById(_repoTargets, targetId);
    if (target == null) return;

    _dismissQueryKeyboard();
    final reconnect = _connected;
    if (_recording) {
      await _cancelRecording();
    }
    if (_connected || _connecting) {
      await _disconnect(expand: false);
    }
    if (!mounted) return;
    final targetKey = target.id;
    setState(() {
      _clearPendingMediaAttachment();
      _applyRepoTargetFields(target);
      _messagesByTarget.putIfAbsent(targetKey, () => []);
      _wavRetryRequested = false;
      _unreadCountsByTarget.remove(targetKey);
      _status = 'Selected ${target.displayName}';
    });
    await _saveSettings();
    await _saveUnreadCounts();
    await _loadConversationHistoryForActiveSession();
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

  Future<Map<String, dynamic>> _readConversationHistoryStore() async {
    final raw = await _storage.read(key: _conversationHistoryStorageKey);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  Future<List<ConversationMessage>> _readConversationHistory(
    String conversationKey,
  ) async {
    final store = await _readConversationHistoryStore();
    final rawMessages = store[conversationKey];
    if (rawMessages is! List) return [];

    final messages = <ConversationMessage>[];
    for (final item in rawMessages) {
      final conversationMessage = ConversationMessage.fromJson(item);
      if (conversationMessage != null) {
        messages.add(conversationMessage);
      }
    }
    messages.sort((left, right) => right.timestamp.compareTo(left.timestamp));
    return messages;
  }

  Future<void> _writeConversationHistoryStore(
    Map<String, dynamic> store,
  ) async {
    await _storage.write(
      key: _conversationHistoryStorageKey,
      value: jsonEncode(store),
    );
  }

  Future<void> _saveConversationHistoryForKey(String conversationKey) async {
    final messages = _messagesByTarget[conversationKey];
    if (messages == null) return;
    final trimmed = messages.take(_maxConversationMessages).toList();
    final store = await _readConversationHistoryStore();
    store[conversationKey] = trimmed.map((item) => item.toJson()).toList();
    await _writeConversationHistoryStore(store);
  }

  Future<void> _deleteConversationHistoryForKey(String conversationKey) async {
    final store = await _readConversationHistoryStore();
    if (!store.remove(conversationKey)) return;
    await _writeConversationHistoryStore(store);
  }

  void _appendMessageForActiveConversation(ConversationMessage message) {
    _appendMessageForConversation(_activeConversationKey, message);
  }

  void _appendMessageForConversation(
    String conversationKey,
    ConversationMessage message,
  ) {
    final messages = _messagesByTarget.putIfAbsent(conversationKey, () => []);
    messages.insert(0, message);
    unawaited(_saveConversationHistoryForKey(conversationKey));
    if (conversationKey == _activeConversationKey) {
      _scrollToLatestMessage();
    }
  }

  void _appendPendingTranscriptionMessage({
    required String conversationKey,
    required String eventId,
    required String label,
    _PendingMessageCompletion completion = _PendingMessageCompletion.transcript,
  }) {
    _pendingProcessingMessages.add(
      _PendingProcessingMessage(
        conversationKey: conversationKey,
        eventId: eventId,
        completion: completion,
      ),
    );
    _appendMessageForConversation(
      conversationKey,
      ConversationMessage(
        direction: MessageDirection.outgoing,
        kind: 'transcribing',
        text: label,
        eventId: eventId,
        timestamp: DateTime.now(),
      ),
    );
  }

  bool _tryCompleteTranscription(String conversationKey, String transcript) {
    while (true) {
      final pending = _takePendingProcessingMessage(
        conversationKey,
        _PendingMessageCompletion.transcript,
      );
      if (pending == null) return false;

      final index = _pendingProcessingMessageIndex(
        conversationKey,
        pending.eventId,
      );
      if (index < 0) continue;

      final messages = _messagesByTarget.putIfAbsent(conversationKey, () => []);
      messages[index] = ConversationMessage(
        direction: MessageDirection.outgoing,
        kind: 'transcript',
        text: transcript,
        eventId: pending.eventId,
        timestamp: DateTime.now(),
        audio: messages[index].audio,
      );
      unawaited(_saveConversationHistoryForKey(conversationKey));
      _appendIncomingProcessingPlaceholder(conversationKey, pending.eventId);
      if (conversationKey == _activeConversationKey) {
        _scrollToLatestMessage();
      }
      return true;
    }
  }

  bool _dropPendingProcessingMessage(
    String conversationKey, {
    _PendingMessageCompletion? completion,
  }) {
    final pending = _takePendingProcessingMessage(conversationKey, completion);
    if (pending == null) return false;

    final index = _pendingProcessingMessageIndex(
      conversationKey,
      pending.eventId,
    );
    if (index >= 0) {
      final messages = _messagesByTarget[conversationKey];
      messages?.removeAt(index);
      unawaited(_saveConversationHistoryForKey(conversationKey));
      if (conversationKey == _activeConversationKey) {
        _scrollToLatestMessage();
      }
    }
    return true;
  }

  _PendingProcessingMessage? _takePendingProcessingMessage(
    String conversationKey,
    _PendingMessageCompletion? completion,
  ) {
    if (_pendingProcessingMessages.isEmpty) return null;
    final index = _pendingProcessingMessages.indexWhere(
      (pending) =>
          pending.conversationKey == conversationKey &&
          (completion == null || pending.completion == completion),
    );
    if (index < 0) return null;
    return _pendingProcessingMessages.removeAt(index);
  }

  int _pendingProcessingMessageIndex(String conversationKey, String eventId) {
    final messages = _messagesByTarget[conversationKey];
    if (messages == null) return -1;
    return messages.indexWhere(
      (message) =>
          message.kind == 'transcribing' &&
          message.direction == MessageDirection.outgoing &&
          message.eventId == eventId,
    );
  }

  void _appendIncomingProcessingPlaceholder(
    String conversationKey,
    String eventId,
  ) {
    _pendingReplyTargetIds.add(conversationKey);
    final messages = _messagesByTarget.putIfAbsent(conversationKey, () => []);
    final alreadyVisible = messages.any(
      (message) =>
          message.kind == 'processing' &&
          message.direction == MessageDirection.incoming &&
          message.eventId == eventId,
    );
    if (alreadyVisible) return;

    _appendMessageForConversation(
      conversationKey,
      ConversationMessage(
        direction: MessageDirection.incoming,
        kind: 'processing',
        text: '',
        eventId: eventId,
        timestamp: DateTime.now(),
      ),
    );
  }

  bool _replaceOldestIncomingProcessingPlaceholder(
    String conversationKey,
    ConversationMessage replacement,
  ) {
    final messages = _messagesByTarget[conversationKey];
    if (messages == null) return false;

    for (var index = messages.length - 1; index >= 0; index -= 1) {
      final message = messages[index];
      if (message.kind == 'processing' &&
          message.direction == MessageDirection.incoming) {
        messages[index] = replacement;
        _syncPendingReplyTarget(conversationKey);
        unawaited(_saveConversationHistoryForKey(conversationKey));
        if (conversationKey == _activeConversationKey) {
          _scrollToLatestMessage();
        }
        return true;
      }
    }
    _syncPendingReplyTarget(conversationKey);
    return false;
  }

  bool _dropIncomingProcessingPlaceholder(String conversationKey) {
    final messages = _messagesByTarget[conversationKey];
    if (messages == null) return false;
    final index = messages.indexWhere(
      (message) =>
          message.kind == 'processing' &&
          message.direction == MessageDirection.incoming,
    );
    if (index < 0) return false;
    messages.removeAt(index);
    _syncPendingReplyTarget(conversationKey);
    unawaited(_saveConversationHistoryForKey(conversationKey));
    if (conversationKey == _activeConversationKey) {
      _scrollToLatestMessage();
    }
    return true;
  }

  void _syncPendingReplyTarget(String conversationKey) {
    final messages = _messagesByTarget[conversationKey] ?? const [];
    final hasPendingResponse = messages.any(
      (message) =>
          message.kind == 'processing' &&
          message.direction == MessageDirection.incoming,
    );
    if (hasPendingResponse) {
      _pendingReplyTargetIds.add(conversationKey);
    } else {
      _pendingReplyTargetIds.remove(conversationKey);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _SettingsPage(
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
          workingAnimationStyle: _workingAnimationStyle,
          hapticFeedbackEnabled: _hapticFeedbackEnabled,
          language: _ttsLanguage,
          languages: _ttsLanguages,
          engine: _ttsEngine,
          engines: _ttsEngines,
          rate: _ttsRate,
          pitch: _ttsPitch,
          volume: _ttsVolume,
          onTargetChanged: (value) {
            if (value != null) unawaited(_selectRepoTarget(value));
          },
          onSaveTarget: () => unawaited(_saveCurrentRepoTarget()),
          onNewTarget: () => unawaited(_createRepoTarget()),
          onScanTarget: () => unawaited(_scanRepoTargetQr()),
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
          onWorkingAnimationChanged: _setWorkingAnimationStyle,
          onHapticFeedbackChanged: _setHapticFeedbackEnabled,
          onLanguageChanged: _setTtsLanguage,
          onEngineChanged: _setTtsEngine,
          onRateChanged: _setTtsRate,
          onPitchChanged: _setTtsPitch,
          onVolumeChanged: _setTtsVolume,
          onSliderChangeEnd: _commitTtsSettings,
          onTest: _testTtsSettings,
          messagesInActiveConversation:
              _recentMessagesForActiveConversation.length,
        ),
      ),
    );
  }

  Future<void> _renameRepoTarget(_RepoTarget target) async {
    final controller = TextEditingController(text: target.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename session'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Session name',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (!mounted || newName == null) return;
    final cleaned = newName.trim();
    if (cleaned.isEmpty) {
      _showError('Session name cannot be empty');
      return;
    }

    final targets = [..._repoTargets];
    final index = targets.indexWhere((item) => item.id == target.id);
    if (index == -1) {
      _showError('Session no longer exists');
      return;
    }

    targets[index] = _RepoTarget(
      id: target.id,
      name: cleaned,
      pubkey: target.pubkey,
      relays: target.relays,
      workdir: target.workdir,
      parentPubkey: target.parentPubkey,
      parentRelays: target.parentRelays,
      parentWorkdir: target.parentWorkdir,
      parentName: target.parentName,
    );
    setState(() {
      _repoTargets = targets;
      if (_selectedRepoTargetId == target.id) {
        _targetNameController.text = cleaned;
      }
      _status = 'Renamed session';
    });
    await _saveSettings();
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

  Future<void> _saveWorkingAnimationStyle() async {
    await _storage.write(
      key: _workingAnimationStorageKey,
      value: _workingAnimationStyle.storageValue,
    );
  }

  void _setWorkingAnimationStyle(_WorkingAnimationStyle style) {
    setState(() => _workingAnimationStyle = style);
    unawaited(_saveWorkingAnimationStyle());
  }

  Future<void> _saveHapticFeedbackEnabled([bool? enabled]) async {
    await _storage.write(
      key: _hapticFeedbackStorageKey,
      value: (enabled ?? _hapticFeedbackEnabled).toString(),
    );
  }

  void _setHapticFeedbackEnabled(bool enabled) {
    setState(() => _hapticFeedbackEnabled = enabled);
    unawaited(_saveHapticFeedbackEnabled(enabled));
    if (enabled) {
      unawaited(_performTapHapticFeedback());
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

  bool _storedBool(String? raw, bool fallback) {
    final cleaned = raw?.trim().toLowerCase();
    if (cleaned == 'true') return true;
    if (cleaned == 'false') return false;
    return fallback;
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
    if (_connected || _connecting) return;

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
          receivePubkeys: _receivePubkeysForInbox(peer),
          relays: relays,
        ),
      );
      if (!mounted) return;
      setState(() {
        _connected = true;
        _connectedPeerPubkey = peer;
        _connectedRelays = relays;
        _ownPubkey = status.publicKey;
        _status = 'Checking recent messages...';
      });
      await _fetchRecentInboxMessages(allowCatchUpSpeech: true);
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _status = 'Connected to ${status.relayCount} relays';
      });
      _startPolling();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connected = false;
        _connectedPeerPubkey = null;
        _connectedRelays = const [];
        _status = 'Connection failed';
      });
      _showError('Connection failed: $error');
    }
  }

  Future<void> _connectToTargetInBackground(_RepoTarget target) async {
    if (_connected || _connecting) return;

    final secret = _secretKeyController.text.trim();
    final peer = target.pubkey.trim();
    final relays = target.relays
        .map((relay) => relay.trim())
        .where((relay) => relay.isNotEmpty)
        .toList();

    if (secret.isEmpty || peer.isEmpty || relays.isEmpty) {
      _showError('Secret key, target pubkey, and relays are required');
      return;
    }

    setState(() {
      _connecting = true;
      _status = 'Connecting to ${target.displayName}...';
    });

    try {
      final status = await nostrStart(
        config: BridgeNostrConfig(
          secretKey: secret,
          peerPubkey: peer,
          receivePubkeys: _receivePubkeysForInbox(peer),
          relays: relays,
        ),
      );
      if (!mounted) return;
      setState(() {
        _connected = true;
        _connecting = false;
        _connectedPeerPubkey = peer;
        _connectedRelays = relays;
        _ownPubkey = status.publicKey;
        _status = 'Connected to ${target.displayName}';
      });
      _startPolling();
      unawaited(_fetchRecentInboxMessages());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connected = false;
        _connectedPeerPubkey = null;
        _connectedRelays = const [];
        _status = 'Connection failed';
      });
      _showError('Connection failed: $error');
    }
  }

  Future<bool> _ensureConnectedForSend() async {
    final target = _targetById(_repoTargets, _selectedRepoTargetId);
    if (_shouldStartRepoTargetForSend(target)) {
      final startedSession = await _startSelectedRepoTargetForSend(target!);
      if (startedSession != null) return startedSession;
      return false;
    }

    if (_connected) return true;
    if (_connecting) return false;

    setState(() => _status = 'Connecting before send...');
    await _connect();
    return mounted && _connected;
  }

  bool _shouldStartRepoTargetForSend(_RepoTarget? target) {
    if (target == null || _isParentRepoTarget(target)) return false;
    final workdir = target.workdir?.trim();
    return workdir != null && workdir.isNotEmpty;
  }

  bool _isParentRepoTarget(_RepoTarget target) {
    final workdir = target.workdir?.trim();
    if (workdir == '/home/tom/code/phone') return true;
    return target.displayName.toLowerCase().contains('phone');
  }

  Future<bool?> _startSelectedRepoTargetForSend(_RepoTarget target) async {
    final workdir = target.workdir?.trim();
    if (workdir == null || workdir.isEmpty) return null;

    final parent = _parentRepoTargetFor(target);
    if (parent == null) {
      _showError(
        'Could not start ${target.displayName}: parent phone session is not saved',
      );
      return null;
    }

    final completer = Completer<_RepoTarget>();
    _pendingSessionStart = _PendingSessionStart(
      workdir: workdir,
      completer: completer,
    );

    try {
      if (_connected || _connecting) {
        await _disconnect(expand: false);
      }
      if (!mounted) return false;
      setState(() {
        _wavRetryRequested = false;
        _status = 'Starting ${target.displayName}...';
      });

      await _connectToTargetInBackground(parent);
      if (!mounted || !_connected) return false;

      await _sendSpawnSessionRequest(
        path: workdir,
        create: false,
        sendingStatus: 'Starting ${target.displayName}...',
        outgoingText: 'Start session in $workdir',
        sentStatus: 'Waiting for ${target.displayName}...',
        recordOutgoing: false,
        silent: true,
      );
      if (!mounted) return false;

      _RepoTarget targetToConnect;
      try {
        targetToConnect = await completer.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException(
            'Session invite timed out',
            const Duration(seconds: 30),
          ),
        );
      } on TimeoutException {
        if (!mounted) return false;
        targetToConnect = _targetById(_repoTargets, target.id) ?? target;
        setState(() {
          _status =
              'Session invite timed out; connecting to saved ${target.displayName}...';
        });
      }
      if (!mounted) return false;

      return await _connectToRepoTargetForSend(targetToConnect);
    } catch (error) {
      if (mounted) {
        _showError('Could not start ${target.displayName}: $error');
      }
      return false;
    } finally {
      if (identical(_pendingSessionStart?.completer, completer)) {
        _pendingSessionStart = null;
      }
    }
  }

  Future<bool> _connectToRepoTargetForSend(_RepoTarget target) async {
    if (!mounted) return false;

    if (_connected || _connecting) {
      await _disconnect(expand: false);
    }
    if (!mounted) return false;

    setState(() {
      _applyRepoTargetFields(target);
      _status = 'Connecting to ${target.displayName}...';
    });
    await _connectToTargetInBackground(target);
    return mounted && _connected && _connectedPeerPubkey == target.pubkey;
  }

  _RepoTarget? _parentRepoTargetFor(_RepoTarget target) {
    final parentPubkey = target.parentPubkey?.trim();
    final parentRelays = target.parentRelays;
    if (parentPubkey != null &&
        parentPubkey.isNotEmpty &&
        parentRelays != null &&
        parentRelays.isNotEmpty) {
      return _RepoTarget(
        id: 'parent-${target.id}',
        name: target.parentName?.trim().isNotEmpty == true
            ? target.parentName!.trim()
            : 'phone',
        pubkey: parentPubkey,
        relays: parentRelays,
        workdir: target.parentWorkdir,
      );
    }

    final targetWorkdir = target.workdir?.trim();
    final candidates = _repoTargets.where((candidate) {
      if (candidate.id == target.id) return false;
      return candidate.pubkey != target.pubkey;
    }).toList();
    if (candidates.isEmpty) return null;

    _RepoTarget? firstWhere(bool Function(_RepoTarget target) test) {
      for (final candidate in candidates) {
        if (test(candidate)) return candidate;
      }
      return null;
    }

    return firstWhere((candidate) {
          final workdir = candidate.workdir?.trim();
          return workdir != null &&
              workdir.isNotEmpty &&
              workdir != targetWorkdir &&
              workdir == '/home/tom/code/phone';
        }) ??
        firstWhere((candidate) {
          final workdir = candidate.workdir?.trim();
          return workdir != null &&
              workdir.isNotEmpty &&
              workdir != targetWorkdir &&
              candidate.displayName.toLowerCase().contains('phone');
        }) ??
        firstWhere((candidate) {
          final workdir = candidate.workdir?.trim();
          return workdir == null || workdir.isEmpty;
        });
  }

  BridgeNostrConfig _activeNostrConfig() {
    final secret = _secretKeyController.text.trim();
    final peer = _connectedPeerPubkey?.trim().isNotEmpty == true
        ? _connectedPeerPubkey!.trim()
        : _peerPubkeyController.text.trim();
    final relays = _connectedRelays.isNotEmpty
        ? _connectedRelays
        : _relayLines();
    if (secret.isEmpty || peer.isEmpty || relays.isEmpty) {
      throw StateError('Secret key, peer pubkey, and relays are required');
    }
    return BridgeNostrConfig(
      secretKey: secret,
      peerPubkey: peer,
      receivePubkeys: _receivePubkeysForInbox(peer),
      relays: relays,
    );
  }

  List<String> _receivePubkeysForInbox(String selectedPeer) {
    final pubkeys = <String>{};
    final cleanedSelected = selectedPeer.trim();
    if (cleanedSelected.isNotEmpty) pubkeys.add(cleanedSelected);
    for (final target in _repoTargets) {
      final pubkey = target.pubkey.trim();
      if (pubkey.isNotEmpty) pubkeys.add(pubkey);
    }
    return pubkeys.toList()..sort();
  }

  bool _isRecoverableNostrSendError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('no relay accepted') ||
        message.contains('relay not connected') ||
        message.contains('timed out sending giftwrapped dm') ||
        message.contains('failed to send giftwrapped dm');
  }

  Future<void> _restartNostrForSendRecovery() async {
    final config = _activeNostrConfig();
    _polling = false;
    if (mounted) {
      setState(() {
        _connecting = true;
        _status = 'Reconnecting to relays...';
      });
    }

    try {
      await nostrStop();
    } catch (_) {
      // A broken session should not prevent rebuilding a fresh one.
    }

    try {
      final status = await nostrStart(config: config);
      if (!mounted) return;
      setState(() {
        _connected = true;
        _connecting = false;
        _ownPubkey = status.publicKey;
        _status = 'Reconnected to ${status.relayCount} relays';
      });
      _startPolling();
      unawaited(_fetchRecentInboxMessages());
      await Future<void>.delayed(const Duration(milliseconds: 900));
    } catch (error) {
      if (mounted) {
        setState(() {
          _connected = false;
          _connecting = false;
          _status = 'Reconnect failed';
        });
      }
      rethrow;
    }
  }

  Future<void> _disconnect({bool expand = true}) async {
    _polling = false;
    await nostrStop();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _connectedPeerPubkey = null;
      _connectedRelays = const [];
      _status = 'Disconnected';
    });
  }

  Future<String> _sendWithAutoRecovery({
    required String label,
    required Future<String> Function() sender,
  }) async {
    Future<String> attemptSend() => sender().timeout(
      _nostrSendTimeout,
      onTimeout: () =>
          throw TimeoutException('$label timed out', _nostrSendTimeout),
    );

    try {
      return await attemptSend();
    } catch (firstError) {
      if (!_isRecoverableNostrSendError(firstError)) {
        rethrow;
      }
      if (!mounted) {
        rethrow;
      }
      setState(() => _status = '$label relay issue, retrying...');
      try {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        return await attemptSend();
      } catch (secondError) {
        if (!_isRecoverableNostrSendError(secondError)) {
          rethrow;
        }
        if (!mounted) {
          rethrow;
        }
        setState(() => _status = '$label relay issue, reconnecting...');
        await _restartNostrForSendRecovery();
        if (!mounted) {
          rethrow;
        }
        return await attemptSend();
      }
    }
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

  Future<int> _fetchRecentInboxMessages({
    bool allowCatchUpSpeech = false,
  }) async {
    try {
      final messages = await nostrFetchRecentMessages(
        lookbackSecs: BigInt.from(_catchUpLookback.inSeconds),
      );
      if (!mounted || messages.isEmpty) return 0;
      var accepted = 0;
      for (final message in messages) {
        if (_receiveMessage(
          message,
          fromCatchUp: true,
          allowAutoSpeak: allowCatchUpSpeech,
        )) {
          accepted += 1;
        }
      }
      if (mounted && accepted > 0) {
        setState(() => _status = 'Fetched $accepted recent message(s)');
      }
      return accepted;
    } catch (error) {
      if (mounted) setState(() => _status = 'Recent message fetch failed');
      debugPrint('recent message fetch failed: $error');
      return 0;
    }
  }

  bool _receiveMessage(
    BridgeIncomingMessage message, {
    bool fromCatchUp = false,
    bool allowAutoSpeak = true,
  }) {
    final eventId = message.eventId.trim();
    if (eventId.isNotEmpty && !_rememberIncomingEventId(eventId)) {
      return false;
    }

    if (message.kind == 'target_invite') {
      if (!_incomingFromActivePeer(message)) return false;
      final parsedTarget = _repoTargetFromInvitePayload(message.rawJson);
      final target = parsedTarget == null
          ? null
          : _targetWithParentRouteFromMessage(parsedTarget, message);
      if (target == null) {
        _showError('Received malformed session request');
        return true;
      }
      final pendingSessionStart = _pendingSessionStart;
      if (pendingSessionStart != null &&
          _sameWorkdir(target.workdir, pendingSessionStart.workdir)) {
        unawaited(
          _acceptPendingSessionStart(target, pendingSessionStart.completer),
        );
        return true;
      }
      setState(() => _status = 'Received session request');
      unawaited(_offerTargetInvite(target));
      return true;
    }

    if (message.kind == 'repo_list') {
      if (!_incomingFromActivePeer(message)) return false;
      final choices = _repoChoicesFromRepoListPayload(message.rawJson);
      if (choices == null) {
        _showError('Received malformed repo list');
        return true;
      }
      final pending = _pendingRepoListCompleter;
      if (pending != null && !pending.isCompleted) {
        pending.complete(choices);
      }
      _cacheRepoChoices(choices);
      setState(() => _status = 'Loaded ${choices.length} repo folders');
      return true;
    }

    final targetKey = _conversationKeyForIncoming(message);
    final isActiveConversation = targetKey == _activeConversationKey;
    if (!isActiveConversation && message.kind == 'status') return false;

    if (message.kind == 'transcript' &&
        _tryCompleteTranscription(targetKey, message.text)) {
      setState(() {
        _status = 'Transcription received';
      });
      return true;
    }

    final conversationMessage = ConversationMessage(
      direction: MessageDirection.incoming,
      kind: message.kind,
      text: message.text,
      eventId: message.eventId,
      timestamp: DateTime.now(),
    );
    final audioRetryRequested = message.kind == 'audio_retry';
    final completesPendingRequest =
        message.kind == 'response' ||
        audioRetryRequested ||
        message.kind == 'error' ||
        message.kind == 'invalid';
    setState(() {
      if (isActiveConversation && message.kind == 'response') {
        _dropPendingProcessingMessage(
          targetKey,
          completion: _PendingMessageCompletion.response,
        );
      } else if (audioRetryRequested || message.kind == 'error') {
        _dropPendingProcessingMessage(targetKey);
      }
      if (message.kind != 'status') {
        final replacedPending = completesPendingRequest
            ? _replaceOldestIncomingProcessingPlaceholder(
                targetKey,
                conversationMessage,
              )
            : false;
        if (!replacedPending) {
          if (!completesPendingRequest) {
            _dropIncomingProcessingPlaceholder(targetKey);
          }
          _appendMessageForConversation(targetKey, conversationMessage);
        }
        if (isActiveConversation &&
            !fromCatchUp &&
            message.kind == 'transcript') {
          _appendIncomingProcessingPlaceholder(targetKey, message.eventId);
        }
        if (!isActiveConversation) {
          _unreadCountsByTarget[targetKey] =
              (_unreadCountsByTarget[targetKey] ?? 0) + 1;
          unawaited(_saveUnreadCounts());
        }
      } else {
        final statusText = message.text.trim();
        _status = statusText.isEmpty
            ? 'Received status update'
            : 'Server: $statusText';
      }

      if (audioRetryRequested) {
        _wavRetryRequested = true;
        _status = 'Server requested WAV retry';
      } else if (message.kind != 'status') {
        _status = fromCatchUp
            ? 'Fetched ${message.kind}'
            : 'Received ${message.kind}';
      }
    });

    if (isActiveConversation &&
        _autoSpeak &&
        !_autoSpeakSuppressed &&
        !_recording &&
        !_sending &&
        !_sendingAudio &&
        !_sendingMedia &&
        (!fromCatchUp || allowAutoSpeak) &&
        (message.kind == 'response' ||
            message.kind == 'audio_retry' ||
            message.kind == 'error' ||
            message.kind == 'invalid')) {
      unawaited(
        _speak(
          message.text,
          remember: true,
          manual: false,
          messageEventId: message.eventId,
          conversationKey: targetKey,
        ),
      );
    }
    return true;
  }

  bool _rememberIncomingEventId(String eventId) {
    if (_seenIncomingEventIds.contains(eventId)) return false;
    _seenIncomingEventIds.add(eventId);
    while (_seenIncomingEventIds.length > _maxSeenIncomingEventIds) {
      _seenIncomingEventIds.remove(_seenIncomingEventIds.first);
    }
    unawaited(_saveSeenIncomingEventIds());
    return true;
  }

  String _conversationKeyForIncoming(BridgeIncomingMessage message) {
    for (final target in _repoTargets) {
      if (target.pubkey == message.senderPubkey ||
          target.pubkey == message.senderPubkeyHex) {
        return target.id;
      }
    }
    return message.senderPubkey.isNotEmpty ? message.senderPubkey : 'default';
  }

  bool _incomingFromActivePeer(BridgeIncomingMessage message) {
    final activePeer = _peerPubkeyController.text.trim();
    final connectedPeer = _connectedPeerPubkey?.trim();
    return (activePeer.isNotEmpty &&
            (message.senderPubkey == activePeer ||
                message.senderPubkeyHex == activePeer)) ||
        (connectedPeer != null &&
            connectedPeer.isNotEmpty &&
            (message.senderPubkey == connectedPeer ||
                message.senderPubkeyHex == connectedPeer));
  }

  void _cacheRepoChoices(List<_RepoChoice> choices) {
    final byRelativePath = <String, _RepoChoice>{};
    for (final choice in choices) {
      byRelativePath[choice.relativePath] = choice;
    }
    final next = byRelativePath.values.toList()
      ..sort(
        (left, right) => left.relativePath.toLowerCase().compareTo(
          right.relativePath.toLowerCase(),
        ),
      );
    _cachedRepoChoices = next;
    unawaited(_saveRepoChoicesCache());
  }

  Future<void> _speak(
    String text, {
    bool remember = false,
    bool manual = true,
    String? messageEventId,
    String? conversationKey,
  }) async {
    if (!manual && _autoSpeakSuppressed) return;
    if (!manual &&
        conversationKey != null &&
        conversationKey != _activeConversationKey) {
      return;
    }
    if (manual) _clearAutoSpeakSuppression();

    final spoken = cleanTextForSpeech(text);
    if (spoken.isEmpty) return;
    final generation = ++_speechGeneration;

    try {
      await _tts.stop();
      if (generation != _speechGeneration) return;
      if (!manual &&
          conversationKey != null &&
          conversationKey != _activeConversationKey) {
        return;
      }
      if (mounted) {
        setState(() {
          _speaking = true;
          _speakingMessageEventId = messageEventId;
          if (remember) _lastSpokenText = text;
        });
      }
      await _tts.speak(spoken);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _speaking = false;
        _speakingMessageEventId = null;
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
        _speakingMessageEventId = null;
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
          _speakingMessageEventId = null;
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
    final conversationKey = _activeConversationKey;
    if (!await _ensureConnectedForSend()) {
      return;
    }
    _clearAutoSpeakSuppression();

    setState(() {
      _sending = true;
      _sendingConversationKey = conversationKey;
      _status = 'Sending query...';
    });

    try {
      final eventId = await _sendWithAutoRecovery(
        label: 'query send',
        sender: () => nostrSendQuery(query: query),
      );
      if (!mounted) return;
      setState(() {
        _appendMessageForConversation(
          conversationKey,
          ConversationMessage(
            direction: MessageDirection.outgoing,
            kind: 'query',
            text: query,
            eventId: eventId,
            timestamp: DateTime.now(),
          ),
        );
        _appendIncomingProcessingPlaceholder(conversationKey, eventId);
        _queryController.clear();
        _status = 'Query sent';
      });
    } catch (error) {
      _showError('Send failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendingConversationKey = null;
        });
      }
    }
  }

  Future<void> _requestSpawnSession() async {
    if (!_connected) {
      _showError('Connect to the parent service first');
      return;
    }
    final request = await showDialog<_SpawnSessionRequest>(
      context: context,
      builder: (context) => _SpawnSessionDialog(
        initialRepoChoices: _cachedRepoChoices,
        onLoadRepos: _requestRepoChoices,
      ),
    );
    if (request == null || !mounted) return;

    final path = '/home/tom/code/${request.path}';
    await _sendSpawnSessionRequest(
      path: path,
      create: request.create,
      sendingStatus: request.create
          ? 'Requesting new project session...'
          : 'Requesting session spawn...',
      outgoingText: request.create
          ? 'Create session in $path'
          : 'Spawn session in $path',
      sentStatus: 'Spawn request sent',
    );
  }

  Future<void> _restartRepoTarget(_RepoTarget target) async {
    final workdir = target.workdir?.trim();
    if (workdir == null || workdir.isEmpty) {
      _showError('This session does not have a saved folder path');
      return;
    }
    if (!_connected) {
      _showError('Connect to the parent service first');
      return;
    }
    if (target.id == _selectedRepoTargetId) {
      _showError('Select the parent service first, then restart this session');
      return;
    }
    await _sendSpawnSessionRequest(
      path: workdir,
      create: false,
      sendingStatus: 'Requesting session restart...',
      outgoingText: 'Restart session in $workdir',
      sentStatus: 'Restart request sent',
    );
  }

  Future<void> _sendSpawnSessionRequest({
    required String path,
    required bool create,
    required String sendingStatus,
    required String outgoingText,
    required String sentStatus,
    bool recordOutgoing = true,
    bool silent = false,
  }) async {
    final payload = jsonEncode({
      'spawn_session': {
        'workdir': path,
        'create': create,
        if (silent) 'silent': true,
      },
    });

    setState(() {
      _sending = true;
      _sendingConversationKey = _activeConversationKey;
      _status = sendingStatus;
    });
    try {
      final eventId = await _sendWithAutoRecovery(
        label: 'spawn session request',
        sender: () => nostrSendQuery(query: payload),
      );
      if (recordOutgoing) {
        _appendMessageForActiveConversation(
          ConversationMessage(
            direction: MessageDirection.outgoing,
            kind: 'query',
            text: outgoingText,
            eventId: eventId,
            timestamp: DateTime.now(),
          ),
        );
      }
      if (!mounted) return;
      setState(() => _status = sentStatus);
    } catch (error) {
      _showError('Session request failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendingConversationKey = null;
        });
      }
    }
  }

  Future<List<_RepoChoice>> _requestRepoChoices() async {
    if (!_connected) {
      throw StateError('Connect to the parent service first');
    }
    final existing = _pendingRepoListCompleter;
    if (existing != null && !existing.isCompleted) {
      existing.completeError(StateError('Repo list request replaced'));
    }
    final completer = Completer<List<_RepoChoice>>();
    _pendingRepoListCompleter = completer;

    final payload = jsonEncode({
      'repo_list_request': {
        'roots': ['/home/tom/code', '/home/tom/code/pave'],
      },
    });

    try {
      setState(() {
        _sending = true;
        _sendingConversationKey = _activeConversationKey;
        _status = 'Requesting repo folders...';
      });
      await _sendWithAutoRecovery(
        label: 'repo folder list request',
        sender: () => nostrSendQuery(query: payload),
      );
      if (mounted) setState(() => _status = 'Waiting for repo folders...');
      return await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('Repo list request timed out'),
      );
    } finally {
      if (identical(_pendingRepoListCompleter, completer)) {
        _pendingRepoListCompleter = null;
      }
      if (mounted) {
        setState(() {
          _sending = false;
          _sendingConversationKey = null;
        });
      }
    }
  }

  Future<void> _sendMediaOrText() async {
    if (_hasPendingMediaAttachment) {
      await _sendPendingMediaAttachment();
      return;
    }
    await _sendQuery();
  }

  Future<void> _sendPendingMediaAttachment() async {
    final selected = _pendingMediaAttachment;
    if (selected == null) return;
    if (_sendingMedia || _sending || _sendingAudio || _recording) return;
    final conversationKey = _activeConversationKey;
    if (!await _ensureConnectedForSend()) {
      return;
    }

    final caption = _queryController.text.trim();
    _mediaUploadCancelled = false;
    _mediaUploadCancelCompleter = Completer<void>();
    final uploadSessionId = ++_mediaUploadSessionId;

    setState(() {
      _sendingMedia = true;
      _sendingMediaConversationKey = conversationKey;
      _status = 'Uploading encrypted attachment to Blossom...';
    });

    try {
      final attachment = await _uploadAudioToBlossom(
        selected.path,
        selected.fileName,
        selected.contentType,
        mediaUploadSessionId: uploadSessionId,
      );
      if (!mounted) return;
      if (_mediaUploadCancelled || uploadSessionId != _mediaUploadSessionId) {
        return;
      }

      setState(() {
        _mediaUploadCancelCompleter = null;
        _status = 'Sending attachment reference...';
      });

      final analysisQuery = _buildMediaBundlePayload(
        attachment: attachment,
        caption: caption,
      );
      final eventId = await _sendWithAutoRecovery(
        label: 'attachment send',
        sender: () => nostrSendQuery(query: analysisQuery),
      );
      if (!mounted) return;
      setState(() {
        final expectsTranscript = attachment.mediaType.toLowerCase().startsWith(
          'audio/',
        );
        _appendPendingTranscriptionMessage(
          conversationKey: conversationKey,
          eventId: eventId,
          label: expectsTranscript
              ? 'Transcribing message...'
              : 'Processing attachment...',
          completion: expectsTranscript
              ? _PendingMessageCompletion.transcript
              : _PendingMessageCompletion.response,
        );
        if (!expectsTranscript) {
          _pendingReplyTargetIds.add(conversationKey);
        }
        _queryController.clear();
        _clearPendingMediaAttachmentInMemory();
        _status = 'Attachment sent';
      });
    } catch (error) {
      if (!mounted) return;
      if (error is _MediaUploadCancelledException) {
        setState(() {
          _status = 'Attachment upload cancelled';
        });
        return;
      }
      _showError('Attachment message failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _sendingMedia = false;
          _sendingMediaConversationKey = null;
          _mediaUploadCancelCompleter = null;
        });
      }
    }
  }

  void _clearPendingMediaAttachment() {
    setState(() {
      _clearPendingMediaAttachmentInMemory();
    });
  }

  void _clearPendingMediaAttachmentInMemory() {
    _pendingMediaAttachment = null;
    _pendingMediaFileName = null;
  }

  bool _isResendableMessage(ConversationMessage message) {
    if (message.kind == 'query' &&
        message.direction == MessageDirection.outgoing &&
        message.text.trim().isNotEmpty) {
      return true;
    }
    if (message.kind == 'transcript' && message.text.trim().isNotEmpty) {
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
        !_sendingMedia &&
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

  Future<void> _attachAndSendMedia() async {
    if (_sending || _sendingAudio || _sendingMedia || _recording) return;
    if (!_connected) {
      _showError('Connect before sending media');
      return;
    }

    final selected = await _pickMediaAttachment();
    final path = selected?.path.trim();
    if (path == null || path.isEmpty) {
      return;
    }

    final fileName = selected!.fileName;

    setState(() {
      _clearPendingMediaAttachmentInMemory();
      _pendingMediaAttachment = selected;
      _pendingMediaFileName = fileName;
      _status = 'Attachment ready. Press Send.';
    });
  }

  void _cancelMediaUpload() {
    if (!_sendingMedia || _mediaUploadSessionId == 0) return;
    if (_mediaUploadCancelCompleter?.isCompleted ?? true) return;

    _mediaUploadCancelled = true;
    _mediaUploadCancelCompleter!.complete();
    if (!mounted) return;
    setState(() {
      _sendingMedia = false;
      _sendingMediaConversationKey = null;
      _mediaUploadCancelCompleter = null;
      _status = 'Attachment upload cancelled';
      _clearPendingMediaAttachmentInMemory();
    });
  }

  Future<void> _cancelCurrentAction() async {
    if (_recording) {
      await _cancelRecording();
      return;
    }
    if (_sendingMedia) {
      _cancelMediaUpload();
    }
  }

  Future<_MediaSelection?> _pickMediaAttachment() async {
    final source = await _chooseMediaSource();
    if (source == null) return null;

    try {
      if (source == _MediaSource.filePicker) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: false,
          allowCompression: true,
          withData: false,
        );
        if (result == null || result.files.isEmpty) return null;

        final file = result.files.first;
        final path = file.path?.trim();
        if (path == null || path.isEmpty) {
          _showError('Could not read selected file');
          return null;
        }
        return _MediaSelection(
          path: path,
          fileName: _normalizeName(file.name, path),
          extension: file.extension,
          contentType: _inferContentType(file.name, file.extension),
        );
      }

      final picker = ImagePicker();
      final image = await (source == _MediaSource.camera
          ? picker.pickImage(source: ImageSource.camera)
          : picker.pickImage(source: ImageSource.gallery));
      if (image == null) return null;

      final imagePath = image.path;
      return _MediaSelection(
        path: imagePath,
        fileName: _normalizeName(
          imagePath.split(Platform.pathSeparator).last,
          imagePath,
        ),
        extension: _pathExtension(imagePath),
        contentType: _inferContentType(
          imagePath.split(Platform.pathSeparator).last,
          _pathExtension(imagePath),
        ),
      );
    } catch (error) {
      _showError('Media picker failed: $error');
      return null;
    }
  }

  Future<_MediaSource?> _chooseMediaSource() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return _MediaSource.filePicker;
    }

    final source = await showModalBottomSheet<_MediaSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take photo'),
                onTap: () => Navigator.of(context).pop(_MediaSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose photo'),
                onTap: () =>
                    Navigator.of(context).pop(_MediaSource.photoPicker),
              ),
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: const Text('Choose file'),
                onTap: () => Navigator.of(context).pop(_MediaSource.filePicker),
              ),
            ],
          ),
        );
      },
    );

    return source;
  }

  String _normalizeName(String name, String path) {
    final trimmedName = name.trim();
    if (trimmedName.isNotEmpty) return trimmedName;
    return path.split(Platform.pathSeparator).last;
  }

  Future<void> _resendTextMessage(
    String query, {
    required bool fromTranscript,
  }) async {
    if (_sending) return;
    final conversationKey = _activeConversationKey;
    setState(() {
      _sending = true;
      _sendingConversationKey = conversationKey;
      _status = fromTranscript
          ? 'Sending transcript as query...'
          : 'Resending query...';
    });

    try {
      final eventId = await _sendWithAutoRecovery(
        label: 'resend query',
        sender: () => nostrSendQuery(query: query),
      );
      if (!mounted) return;
      setState(() {
        _appendMessageForConversation(
          conversationKey,
          ConversationMessage(
            direction: MessageDirection.outgoing,
            kind: 'query',
            text: query,
            eventId: eventId,
            timestamp: DateTime.now(),
          ),
        );
        _appendIncomingProcessingPlaceholder(conversationKey, eventId);
        _status = fromTranscript ? 'Transcript sent' : 'Query resent';
      });
    } catch (error) {
      _showError('Resend failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendingConversationKey = null;
        });
      }
    }
  }

  Future<void> _resendAudioMessage(BridgeAudioReference audio) async {
    if (_sendingAudio) return;
    final conversationKey = _activeConversationKey;
    setState(() {
      _sendingAudio = true;
      _sendingAudioConversationKey = conversationKey;
      _status = 'Resending voice note...';
    });

    try {
      final eventId = await _sendWithAutoRecovery(
        label: 'resend voice note',
        sender: () => nostrSendAudio(audio: audio),
      );
      if (!mounted) return;
      setState(() {
        _appendPendingTranscriptionMessage(
          conversationKey: conversationKey,
          eventId: eventId,
          label: 'Resending voice transcript...',
        );
        _status = 'Voice note resent';
      });
    } catch (error) {
      _showError('Voice resend failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _sendingAudio = false;
          _sendingAudioConversationKey = null;
        });
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_speaking) {
      await _stopSpeaking();
    }
    if (_recording) {
      _tapHapticFeedback();
      await _stopAndSendRecording();
      return;
    }

    if (_sending || _sendingAudio) return;
    _tapHapticFeedback();
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
        _recordingStartedAt = DateTime.now();
        _status = recordingFormat.format == _VoiceFormat.wav
            ? 'Recording WAV retry...'
            : 'Recording voice query...';
      });
      _startRecordingTimer();
    } catch (error) {
      if (path != null) unawaited(_deleteTempAudio(path));
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recordingPath = null;
        _activeRecordingFormat = null;
        _recordingStartedAt = null;
        _stopRecordingTimer();
      });
      _showError('Recording failed: $error');
    }
  }

  void _tapHapticFeedback() {
    if (!_hapticFeedbackEnabled) return;
    unawaited(_performTapHapticFeedback());
  }

  Future<void> _performTapHapticFeedback() async {
    if (Platform.isAndroid) {
      try {
        await _ttsControlChannel.invokeMethod<void>('hapticTap');
        return;
      } catch (_) {
        // Fall back to Flutter's platform haptic if native vibration is unavailable.
      }
    }
    await HapticFeedback.lightImpact();
  }

  Future<void> _stopAndSendRecording() async {
    final conversationKey = _activeConversationKey;
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
          _recordingStartedAt = null;
          _stopRecordingTimer();
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
      _recordingStartedAt = null;
      _stopRecordingTimer();
      _sendingAudio = true;
      _sendingAudioConversationKey = conversationKey;
      _status = 'Uploading voice note to Blossom...';
    });

    if (path == null) {
      _showError('Recording did not produce an audio file');
      if (mounted) {
        setState(() {
          _sendingAudio = false;
          _sendingAudioConversationKey = null;
        });
      }
      return;
    }

    try {
      setState(() => _status = 'Preparing voice session...');
      if (!await _ensureConnectedForSend()) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _sendingAudioConversationKey = conversationKey;
        _status = 'Uploading voice note to Blossom...';
      });

      final fileName = path.split(Platform.pathSeparator).last;
      final audio = await _uploadAudioToBlossom(
        path,
        fileName,
        recordingFormat.contentType,
      );

      if (!mounted) return;
      setState(() => _status = 'Sending Blossom audio reference...');

      final eventId = await _sendWithAutoRecovery(
        label: 'voice note send',
        sender: () => nostrSendAudio(audio: audio),
      );
      if (!mounted) return;
      setState(() {
        if (recordingFormat.format == _VoiceFormat.wav) {
          _wavRetryRequested = false;
        }
        _appendPendingTranscriptionMessage(
          conversationKey: conversationKey,
          eventId: eventId,
          label: 'Transcribing voice...',
        );
        _status = 'Voice query sent';
      });
    } catch (error) {
      _showError('Voice query failed: $error');
    } finally {
      unawaited(_deleteTempAudio(path));
      if (mounted) {
        setState(() {
          _sendingAudio = false;
          _sendingAudioConversationKey = null;
        });
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
      _recordingStartedAt = null;
      _stopRecordingTimer();
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

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_recording || !mounted) {
        _stopRecordingTimer();
        return;
      }
      setState(() {});
    });
  }

  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  Future<BridgeAudioReference> _uploadAudioToBlossom(
    String path,
    String fileName,
    String contentType, {
    int mediaUploadSessionId = 0,
  }) async {
    final servers = _selectedBlossomServers();
    Object? lastError;
    final activeSecret = _secretKeyController.text.trim();

    for (final server in servers) {
      if (mediaUploadSessionId != 0 &&
          mediaUploadSessionId != _mediaUploadSessionId) {
        throw _MediaUploadCancelledException(
          server: server,
          sessionId: mediaUploadSessionId,
        );
      }
      if (mounted) {
        setState(
          () => _status = 'Uploading attachment to ${_serverLabel(server)}...',
        );
      }

      try {
        final uploadFuture =
            blossomUploadAudio(
              config: BridgeBlossomUploadConfig(
                secretKey: activeSecret,
                serverUrl: server,
                filePath: path,
                contentType: contentType,
                fileName: fileName,
              ),
            ).timeout(
              _blossomUploadTimeout,
              onTimeout: () {
                throw Exception(
                  'Blossom upload timed out after ${_blossomUploadTimeout.inSeconds}s on $server',
                );
              },
            );
        unawaited(uploadFuture.then((_) {}).catchError((_) {}));

        final cancelCompleter = _mediaUploadCancelCompleter;
        if (cancelCompleter == null) {
          return await uploadFuture;
        }

        final cancelMessage = _MediaUploadCancelledException(
          server: server,
          sessionId: mediaUploadSessionId,
        );
        return await Future.any([
          uploadFuture,
          cancelCompleter.future.then((_) => throw cancelMessage),
        ]);
      } catch (error) {
        if (error is _MediaUploadCancelledException) {
          _mediaUploadCancelled = true;
          rethrow;
        }
        lastError = error;
      }
    }

    throw Exception(
      'all Blossom uploads failed across ${servers.length} server(s): $lastError',
    );
  }

  String _inferContentType(String fileName, String? extension) {
    final normalizedExtension =
        extension?.trim().toLowerCase() ??
        _pathExtension(fileName).toLowerCase();
    switch (normalizedExtension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'svg':
        return 'image/svg+xml';
      case 'mp4':
        return 'video/mp4';
      case 'm4v':
        return 'video/x-m4v';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'avi':
        return 'video/x-msvideo';
      case 'mkv':
        return 'video/x-matroska';
      case 'mp3':
        return 'audio/mpeg';
      case 'flac':
        return 'audio/flac';
      case 'm4a':
        return 'audio/mp4';
      case 'ogg':
        return 'audio/ogg';
      case 'wav':
        return 'audio/wav';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'json':
        return 'application/json';
      case 'md':
        return 'text/markdown';
      case 'csv':
        return 'text/csv';
      default:
        return 'application/octet-stream';
    }
  }

  String _pathExtension(String fileName) {
    final value = fileName.trim();
    final dotIndex = value.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == value.length - 1) return '';
    return value.substring(dotIndex + 1);
  }

  String _buildMediaBundlePayload({
    required BridgeAudioReference attachment,
    required String caption,
  }) {
    final encryption = attachment.encryption;
    final attachmentPayload = {
      'name': attachment.name ?? 'media',
      'url': attachment.url,
      'sha256': attachment.sha256,
      'size': bridgeUIntToJsonInt(attachment.size),
      'type': attachment.mediaType,
      if (encryption != null)
        'encryption': {
          'algorithm': encryption.algorithm,
          'key': encryption.key,
          'nonce': encryption.nonce,
          'plaintext_sha256': encryption.plaintextSha256,
          'plaintext_size': bridgeUIntToJsonInt(encryption.plaintextSize),
          'plaintext_type': encryption.plaintextMediaType,
        },
    };
    final mediaBundle = <String, dynamic>{
      'attachments': [attachmentPayload],
    };
    final trimmedCaption = caption.trim();
    if (trimmedCaption.isNotEmpty) {
      mediaBundle['query'] = trimmedCaption;
    }
    final payload = {'media_bundle': mediaBundle};
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(payload);
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

  List<String> _relayLines() {
    return _relayController.text
        .split(RegExp(r'[\n,]'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  void _showError(String message) {
    if (!mounted) return;
    final previousStatus = _status;
    setState(() => _status = message);
    debugPrint('status update: ${previousStatus ?? '(none)'} -> $message');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSettings) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final selectedTarget =
        _selectedRepoTargetId != null &&
            _repoTargets.any((target) => target.id == _selectedRepoTargetId)
        ? _selectedRepoTargetId
        : _repoTargets.isNotEmpty
        ? _repoTargets.first.id
        : null;
    final hasUnreadConversations = _unreadCountsByTarget.values.any(
      (count) => count > 0,
    );

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Conversations',
            icon: Badge(
              isLabelVisible: hasUnreadConversations,
              smallSize: 9,
              child: const Icon(Icons.menu),
            ),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: _repoTargets.isEmpty
            ? Text(
                _activeTargetName(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedTarget,
                  isDense: true,
                  isExpanded: true,
                  icon: const Icon(Icons.expand_more),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  items: [
                    for (final target in _repoTargets)
                      DropdownMenuItem(
                        value: target.id,
                        child: Text(
                          target.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      unawaited(_selectRepoTarget(value));
                    }
                  },
                ),
              ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0),
          child: const SizedBox.shrink(),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => unawaited(_openSettings()),
          ),
        ],
      ),
      drawer: _SessionDrawer(
        targets: _repoTargets,
        selectedTargetId: _selectedRepoTargetId,
        connectedTargetId: _connected ? _selectedRepoTargetId : null,
        unreadCountsByTarget: _unreadCountsByTarget,
        pendingReplyTargetIds: _pendingReplyTargetIds,
        loadedTargetIds: _messagesByTarget.keys.toSet(),
        workingAnimationStyle: _workingAnimationStyle,
        onSelectTarget: (targetId) => unawaited(_selectRepoTarget(targetId)),
        onNewTarget: () => unawaited(_createRepoTarget()),
        onSpawnSession: () => unawaited(_requestSpawnSession()),
        onRestartTarget: (target) => unawaited(_restartRepoTarget(target)),
        onRenameTarget: (target) => unawaited(_renameRepoTarget(target)),
        onDeleteTarget: (targetId) {
          unawaited(() async {
            final target = _targetById(_repoTargets, targetId);
            if (target == null) return;
            if (target.id == _selectedRepoTargetId) {
              await _deleteSelectedRepoTarget();
            } else {
              setState(() {
                _repoTargets = _repoTargets
                    .where((item) => item.id != target.id)
                    .toList();
                _messagesByTarget.remove(target.id);
                _unreadCountsByTarget.remove(target.id);
                _pendingReplyTargetIds.remove(target.id);
                _status = 'Deleted session ${target.displayName}';
              });
              await _deleteConversationHistoryForKey(target.id);
              await _saveUnreadCounts();
              await _saveSettings();
            }
          }());
        },
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _recentMessagesForActiveConversation.isEmpty
                  ? const Center(child: Text('No messages in last hour'))
                  : ListView.builder(
                      controller: _chatScrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      itemCount: _recentMessagesForActiveConversation.length,
                      itemBuilder: (context, index) {
                        final message =
                            _recentMessagesForActiveConversation[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _MessageTile(
                            message: message,
                            showResend: _isResendableMessage(message),
                            speaking:
                                _speaking &&
                                message.eventId == _speakingMessageEventId,
                            workingAnimationStyle: _workingAnimationStyle,
                            stopSpeakingOnTap:
                                _speaking &&
                                message.direction == MessageDirection.incoming,
                            onStopSpeaking: _stopSpeaking,
                            onResend: _canResendMessage(message)
                                ? () => _resendMessage(message)
                                : null,
                          ),
                        );
                      },
                    ),
            ),
            _Composer(
              controller: _queryController,
              focusNode: _queryFocusNode,
              connected: _connected,
              connecting: _connecting,
              sending: _sendingInActiveConversation,
              sendingAudio: _sendingAudioInActiveConversation,
              sendingMedia: _sendingMediaInActiveConversation,
              recording: _recording,
              recordingDurationLabel: _recordingDurationLabel,
              wavRetryRequested: _wavRetryRequested,
              hasPendingMedia: _hasPendingMediaAttachment,
              pendingMediaName: _pendingMediaFileName,
              onMicPressed: _toggleRecording,
              onAttachMedia: _attachAndSendMedia,
              onCancelRecording: () => unawaited(_cancelCurrentAction()),
              onClearPendingMedia: _clearPendingMediaAttachment,
              onSendPressed: () => _sendMediaOrText(),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _SessionDrawer extends StatelessWidget {
  const _SessionDrawer({
    required this.targets,
    required this.selectedTargetId,
    required this.connectedTargetId,
    required this.unreadCountsByTarget,
    required this.pendingReplyTargetIds,
    required this.loadedTargetIds,
    required this.workingAnimationStyle,
    required this.onSelectTarget,
    required this.onNewTarget,
    required this.onSpawnSession,
    required this.onRestartTarget,
    required this.onRenameTarget,
    required this.onDeleteTarget,
  });

  final List<_RepoTarget> targets;
  final String? selectedTargetId;
  final String? connectedTargetId;
  final Map<String, int> unreadCountsByTarget;
  final Set<String> pendingReplyTargetIds;
  final Set<String> loadedTargetIds;
  final _WorkingAnimationStyle workingAnimationStyle;
  final ValueChanged<String> onSelectTarget;
  final VoidCallback onNewTarget;
  final VoidCallback onSpawnSession;
  final ValueChanged<_RepoTarget> onRestartTarget;
  final ValueChanged<_RepoTarget> onRenameTarget;
  final ValueChanged<String> onDeleteTarget;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.record_voice_over),
              title: const Text('Sessions'),
              subtitle: Text('${targets.length} sessions'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New session'),
              onTap: () {
                Navigator.of(context).pop();
                onNewTarget();
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Spawn on computer'),
              onTap: () {
                Navigator.of(context).pop();
                onSpawnSession();
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 8),
                children: [
                  for (final target in targets)
                    Builder(
                      builder: (context) {
                        final theme = Theme.of(context);
                        final dark = theme.brightness == Brightness.dark;
                        final activeColor = dark
                            ? const Color(0xff81c784)
                            : const Color(0xff2e7d32);
                        final loadedColor = dark
                            ? const Color(0xff90caf9)
                            : const Color(0xff1565c0);
                        final unreadCount =
                            unreadCountsByTarget[target.id] ?? 0;
                        final hasWorkdir =
                            target.workdir?.trim().isNotEmpty == true;
                        final selected = target.id == selectedTargetId;
                        final connected = target.id == connectedTargetId;
                        final loaded = loadedTargetIds.contains(target.id);
                        final pending = pendingReplyTargetIds.contains(
                          target.id,
                        );
                        final statusColor = selected
                            ? activeColor
                            : connected || loaded
                            ? loadedColor
                            : null;
                        final tileColor = selected
                            ? activeColor.withValues(alpha: 0.12)
                            : connected || loaded
                            ? loadedColor.withValues(alpha: 0.08)
                            : null;
                        final menu = PopupMenuButton<_SessionDrawerAction>(
                          onSelected: (action) async {
                            if (action == _SessionDrawerAction.restart) {
                              onRestartTarget(target);
                            } else if (action == _SessionDrawerAction.rename) {
                              onRenameTarget(target);
                            } else if (action == _SessionDrawerAction.delete) {
                              final shouldDelete = await _confirmDelete(
                                context,
                                target,
                              );
                              if (shouldDelete && context.mounted) {
                                onDeleteTarget(target.id);
                              }
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: _SessionDrawerAction.restart,
                              enabled: hasWorkdir,
                              child: const ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.restart_alt),
                                title: Text('Restart'),
                              ),
                            ),
                            const PopupMenuItem(
                              value: _SessionDrawerAction.rename,
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.edit),
                                title: Text('Rename'),
                              ),
                            ),
                            const PopupMenuItem(
                              value: _SessionDrawerAction.delete,
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.delete_outline),
                                title: Text('Delete'),
                              ),
                            ),
                          ],
                        );
                        return ListTile(
                          selected: selected,
                          selectedColor: activeColor,
                          selectedTileColor: tileColor,
                          tileColor: selected ? null : tileColor,
                          leading: Badge(
                            isLabelVisible: unreadCount > 0,
                            smallSize: 9,
                            child: SizedBox.square(
                              dimension: 30,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  if (pending)
                                    SizedBox.square(
                                      dimension: 28,
                                      child: Center(
                                        child: workingAnimationStyle.enabled
                                            ? _DigitalThinkingIndicator(
                                                width: 28,
                                                height: 16,
                                                color:
                                                    statusColor ?? loadedColor,
                                                style: workingAnimationStyle,
                                              )
                                            : Icon(
                                                connected
                                                    ? Icons.cloud_done_outlined
                                                    : Icons.chat_bubble_outline,
                                                color: statusColor,
                                              ),
                                      ),
                                    )
                                  else
                                    Icon(
                                      connected
                                          ? Icons.cloud_done_outlined
                                          : Icons.chat_bubble_outline,
                                      color: statusColor,
                                    ),
                                ],
                              ),
                            ),
                          ),
                          title: Text(
                            target.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: statusColor == null
                                ? null
                                : TextStyle(
                                    color: statusColor,
                                    fontWeight: selected || connected
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                  ),
                          ),
                          subtitle: Text(
                            target.workdir?.trim().isNotEmpty == true
                                ? target.workdir!
                                : _compactIdentifier(target.pubkey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: unreadCount > 0
                              ? Badge(label: Text('$unreadCount'), child: menu)
                              : menu,
                          onTap: () {
                            Navigator.of(context).pop();
                            onSelectTarget(target.id);
                          },
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, _RepoTarget target) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete session?'),
            content: Text('Delete ${target.displayName}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

enum _SessionDrawerAction { restart, rename, delete }

class _SpawnSessionRequest {
  const _SpawnSessionRequest({required this.path, required this.create});

  final String path;
  final bool create;
}

class _SpawnSessionDialog extends StatefulWidget {
  const _SpawnSessionDialog({
    required this.initialRepoChoices,
    required this.onLoadRepos,
  });

  final List<_RepoChoice> initialRepoChoices;
  final Future<List<_RepoChoice>> Function() onLoadRepos;

  @override
  State<_SpawnSessionDialog> createState() => _SpawnSessionDialogState();
}

class _SpawnSessionDialogState extends State<_SpawnSessionDialog> {
  final _pathController = TextEditingController();
  bool _create = true;
  bool _loadingRepos = false;
  List<_RepoChoice> _repoChoices = const [];

  @override
  void initState() {
    super.initState();
    _repoChoices = widget.initialRepoChoices;
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  String? _validationError(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return 'Path is required';
    if (cleaned.contains('\x00')) return 'Path contains an invalid character';
    if (cleaned.startsWith('/') || cleaned.startsWith('~')) {
      return 'Use a folder name under /home/tom/code';
    }
    if (cleaned.split('/').any((part) => part == '..')) {
      return 'Folder name cannot contain ..';
    }
    return null;
  }

  Future<void> _loadRepos() async {
    setState(() => _loadingRepos = true);
    try {
      final choices = await widget.onLoadRepos();
      if (!mounted) return;
      setState(() => _repoChoices = choices);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load repos: $error')));
    } finally {
      if (mounted) setState(() => _loadingRepos = false);
    }
  }

  void _submit() {
    final cleaned = _pathController.text.trim();
    final error = _validationError(cleaned);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.of(
      context,
    ).pop(_SpawnSessionRequest(path: cleaned, create: _create));
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = (MediaQuery.sizeOf(context).width - 64).clamp(
      280.0,
      480.0,
    );

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Spawn session'),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.create_new_folder_outlined),
                    label: Text('Create'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.folder_open),
                    label: Text('Open'),
                  ),
                ],
                selected: {_create},
                onSelectionChanged: (selection) {
                  setState(() => _create = selection.first);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pathController,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  helperText: 'Under /home/tom/code',
                  labelText: _create ? 'New folder' : 'Folder',
                  hintText: _create ? 'my-new-project' : 'phone',
                ),
              ),
              if (!_create) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _loadingRepos ? null : _loadRepos,
                    icon: _loadingRepos
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(
                      _repoChoices.isEmpty ? 'Get folders' : 'Refresh',
                    ),
                  ),
                ),
                if (_repoChoices.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _repoChoices.length,
                      itemBuilder: (context, index) {
                        final choice = _repoChoices[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            choice.isGitRepo
                                ? Icons.account_tree_outlined
                                : Icons.folder_outlined,
                          ),
                          title: Text(
                            choice.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            _pathController.text = choice.relativePath;
                          },
                        );
                      },
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send),
          label: const Text('Request'),
        ),
      ],
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
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
    required this.workingAnimationStyle,
    required this.hapticFeedbackEnabled,
    required this.language,
    required this.languages,
    required this.engine,
    required this.engines,
    required this.rate,
    required this.pitch,
    required this.volume,
    required this.messagesInActiveConversation,
    required this.onTargetChanged,
    required this.onSaveTarget,
    required this.onNewTarget,
    required this.onScanTarget,
    required this.onDeleteTarget,
    required this.onGenerateKey,
    required this.onSecretChanged,
    required this.onConnect,
    required this.onDisconnect,
    required this.onStop,
    required this.onReplay,
    required this.onAutoSpeakChanged,
    required this.onWorkingAnimationChanged,
    required this.onHapticFeedbackChanged,
    required this.onLanguageChanged,
    required this.onEngineChanged,
    required this.onRateChanged,
    required this.onPitchChanged,
    required this.onVolumeChanged,
    required this.onSliderChangeEnd,
    required this.onTest,
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
  final _WorkingAnimationStyle workingAnimationStyle;
  final bool hapticFeedbackEnabled;
  final String language;
  final List<String> languages;
  final String? engine;
  final List<String> engines;
  final double rate;
  final double pitch;
  final double volume;
  final int messagesInActiveConversation;
  final ValueChanged<String?> onTargetChanged;
  final VoidCallback onSaveTarget;
  final VoidCallback onNewTarget;
  final VoidCallback onScanTarget;
  final VoidCallback? onDeleteTarget;
  final VoidCallback onGenerateKey;
  final ValueChanged<String> onSecretChanged;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onStop;
  final VoidCallback onReplay;
  final ValueChanged<bool> onAutoSpeakChanged;
  final ValueChanged<_WorkingAnimationStyle> onWorkingAnimationChanged;
  final ValueChanged<bool> onHapticFeedbackChanged;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Session & speech')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ConnectionPanel(
            repoTargets: repoTargets,
            selectedRepoTargetId: selectedRepoTargetId,
            activeTargetName: activeTargetName,
            targetNameController: targetNameController,
            secretKeyController: secretKeyController,
            peerPubkeyController: peerPubkeyController,
            relayController: relayController,
            blossomServerController: blossomServerController,
            blossomPresets: blossomPresets,
            ownPubkey: ownPubkey,
            connected: connected,
            connecting: connecting,
            speaking: speaking,
            hasReplay: hasReplay,
            autoSpeak: autoSpeak,
            language: language,
            languages: languages,
            engine: engine,
            engines: engines,
            rate: rate,
            pitch: pitch,
            volume: volume,
            onTargetChanged: onTargetChanged,
            onSaveTarget: onSaveTarget,
            onNewTarget: onNewTarget,
            onScanTarget: onScanTarget,
            onDeleteTarget: onDeleteTarget,
            onGenerateKey: onGenerateKey,
            onSecretChanged: onSecretChanged,
            onConnect: onConnect,
            onDisconnect: onDisconnect,
            onStop: onStop,
            onReplay: onReplay,
            onAutoSpeakChanged: onAutoSpeakChanged,
            onLanguageChanged: onLanguageChanged,
            onEngineChanged: onEngineChanged,
            onRateChanged: onRateChanged,
            onPitchChanged: onPitchChanged,
            onVolumeChanged: onVolumeChanged,
            onSliderChangeEnd: onSliderChangeEnd,
            onTest: onTest,
          ),
          const SizedBox(height: 16),
          _WorkingAnimationSettings(
            initialStyle: workingAnimationStyle,
            onChanged: onWorkingAnimationChanged,
          ),
          const SizedBox(height: 16),
          _HapticFeedbackSettings(
            initialEnabled: hapticFeedbackEnabled,
            onChanged: onHapticFeedbackChanged,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('App info', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Active session: $activeTargetName'),
                  Text('Messages: $messagesInActiveConversation'),
                  Text(
                    connected
                        ? 'Status: connected'
                        : connecting
                        ? 'Status: connecting'
                        : 'Status: disconnected',
                  ),
                  if (ownPubkey != null && ownPubkey!.isNotEmpty)
                    Text('Local pubkey: ${_compactIdentifier(ownPubkey!)}'),
                  if (ownPubkey == null || ownPubkey!.isEmpty)
                    const Text('Local pubkey not available'),
                  Text('Total saved sessions: ${repoTargets.length}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkingAnimationSettings extends StatefulWidget {
  const _WorkingAnimationSettings({
    required this.initialStyle,
    required this.onChanged,
  });

  final _WorkingAnimationStyle initialStyle;
  final ValueChanged<_WorkingAnimationStyle> onChanged;

  @override
  State<_WorkingAnimationSettings> createState() =>
      _WorkingAnimationSettingsState();
}

class _WorkingAnimationSettingsState extends State<_WorkingAnimationSettings> {
  late _WorkingAnimationStyle _selectedStyle;

  @override
  void initState() {
    super.initState();
    _selectedStyle = widget.initialStyle;
  }

  @override
  void didUpdateWidget(covariant _WorkingAnimationSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStyle != widget.initialStyle) {
      _selectedStyle = widget.initialStyle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Working animation', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<_WorkingAnimationStyle>(
                    initialValue: _selectedStyle,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Processing style',
                    ),
                    items: [
                      for (final style in _WorkingAnimationStyle.values)
                        DropdownMenuItem(
                          value: style,
                          child: Text(style.label),
                        ),
                    ],
                    onChanged: (style) {
                      if (style == null) return;
                      setState(() => _selectedStyle = style);
                      widget.onChanged(style);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 84,
                  child: Center(
                    child: _selectedStyle.enabled
                        ? _DigitalThinkingIndicator(
                            width: 64,
                            height: 28,
                            color: theme.colorScheme.primary,
                            style: _selectedStyle,
                          )
                        : Text('Off', style: theme.textTheme.labelMedium),
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

class _HapticFeedbackSettings extends StatefulWidget {
  const _HapticFeedbackSettings({
    required this.initialEnabled,
    required this.onChanged,
  });

  final bool initialEnabled;
  final ValueChanged<bool> onChanged;

  @override
  State<_HapticFeedbackSettings> createState() =>
      _HapticFeedbackSettingsState();
}

class _HapticFeedbackSettingsState extends State<_HapticFeedbackSettings> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.initialEnabled;
  }

  @override
  void didUpdateWidget(covariant _HapticFeedbackSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialEnabled != widget.initialEnabled) {
      _enabled = widget.initialEnabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        secondary: const Icon(Icons.vibration),
        title: const Text('Haptic feedback'),
        subtitle: const Text('Record start and send taps'),
        value: _enabled,
        onChanged: (enabled) {
          setState(() => _enabled = enabled);
          widget.onChanged(enabled);
        },
      ),
    );
  }
}

class _AutoSpeakSwitch extends StatefulWidget {
  const _AutoSpeakSwitch({
    required this.initialEnabled,
    required this.onChanged,
  });

  final bool initialEnabled;
  final ValueChanged<bool> onChanged;

  @override
  State<_AutoSpeakSwitch> createState() => _AutoSpeakSwitchState();
}

class _AutoSpeakSwitchState extends State<_AutoSpeakSwitch> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.initialEnabled;
  }

  @override
  void didUpdateWidget(covariant _AutoSpeakSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialEnabled != widget.initialEnabled) {
      _enabled = widget.initialEnabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _enabled ? 'Auto speak on' : 'Auto speak off',
      child: Switch(
        value: _enabled,
        onChanged: (enabled) {
          setState(() => _enabled = enabled);
          widget.onChanged(enabled);
        },
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
    required this.onTargetChanged,
    required this.onSaveTarget,
    required this.onNewTarget,
    required this.onScanTarget,
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
  final ValueChanged<String?> onTargetChanged;
  final VoidCallback onSaveTarget;
  final VoidCallback onNewTarget;
  final VoidCallback onScanTarget;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            Text('Session and speech', style: theme.textTheme.titleMedium),
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
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: connecting ? null : onNewTarget,
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                ),
                TextButton.icon(
                  onPressed: connecting ? null : onSaveTarget,
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                ),
                TextButton.icon(
                  onPressed: connecting ? null : onScanTarget,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan'),
                ),
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
                  onSelected: (value) => blossomServerController.text = value,
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
                  color: speaking ? colorScheme.primary : colorScheme.secondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Speech', style: theme.textTheme.titleSmall),
                ),
                _AutoSpeakSwitch(
                  initialEnabled: autoSpeak,
                  onChanged: onAutoSpeakChanged,
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

class _RepoTargetQrScannerPage extends StatefulWidget {
  const _RepoTargetQrScannerPage();

  @override
  State<_RepoTargetQrScannerPage> createState() =>
      _RepoTargetQrScannerPageState();
}

class _RepoTargetQrScannerPageState extends State<_RepoTargetQrScannerPage> {
  final _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;
      _handled = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Target')),
      body: MobileScanner(controller: _controller, onDetect: _handleDetect),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.connected,
    required this.connecting,
    required this.sending,
    required this.sendingAudio,
    required this.sendingMedia,
    required this.recording,
    required this.recordingDurationLabel,
    required this.wavRetryRequested,
    required this.hasPendingMedia,
    required this.pendingMediaName,
    required this.onMicPressed,
    required this.onAttachMedia,
    required this.onCancelRecording,
    required this.onClearPendingMedia,
    required this.onSendPressed,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool connected;
  final bool connecting;
  final bool sending;
  final bool sendingAudio;
  final bool sendingMedia;
  final bool recording;
  final String recordingDurationLabel;
  final bool wavRetryRequested;
  final bool hasPendingMedia;
  final String? pendingMediaName;
  final VoidCallback onMicPressed;
  final VoidCallback onAttachMedia;
  final VoidCallback onCancelRecording;
  final VoidCallback onClearPendingMedia;
  final VoidCallback onSendPressed;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canClearPendingAttachment =
        !widget.sending &&
        !widget.sendingAudio &&
        !widget.sendingMedia &&
        !widget.connecting;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (widget.hasPendingMedia && widget.pendingMediaName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.attachment,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Attached: ${widget.pendingMediaName}',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Tooltip(
                      message: 'Clear attachment',
                      child: IconButton(
                        onPressed: canClearPendingAttachment
                            ? widget.onClearPendingMedia
                            : null,
                        icon: const Icon(Icons.close),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              autofocus: false,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Query',
                hintText: 'Type a message, or record',
              ),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                final canSendFromInput = hasText || widget.hasPendingMedia;
                final busy =
                    widget.sending ||
                    widget.sendingAudio ||
                    widget.sendingMedia;
                final canUseMainAction = !busy && !widget.connecting;
                final onMainPressed = canUseMainAction
                    ? widget.connected
                          ? widget.recording
                                ? widget.onMicPressed
                                : canSendFromInput
                                ? widget.onSendPressed
                                : widget.onMicPressed
                          : canSendFromInput
                          ? widget.onSendPressed
                          : widget.onMicPressed
                    : null;

                final canAttach = !busy && !widget.connecting;
                final attachIcon = widget.recording
                    ? const Icon(Icons.close)
                    : widget.sendingMedia
                    ? const Icon(Icons.close)
                    : const Icon(Icons.attach_file);
                final attachAction = widget.recording
                    ? widget.onCancelRecording
                    : widget.sendingMedia
                    ? widget.onCancelRecording
                    : widget.onAttachMedia;
                final attachTooltip = widget.recording
                    ? 'Cancel recording'
                    : widget.sendingMedia
                    ? 'Cancel attachment send'
                    : 'Attach photo or file';
                final attachStyle = widget.recording
                    ? IconButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        minimumSize: const Size(48, 48),
                      )
                    : widget.sendingMedia
                    ? IconButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        minimumSize: const Size(48, 48),
                      )
                    : IconButton.styleFrom(minimumSize: const Size(48, 48));
                final recordingShell = widget.recording || widget.sendingAudio;

                final icon = busy
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: recordingShell
                              ? const Color(0xff1b140f)
                              : theme.colorScheme.onPrimary,
                        ),
                      )
                    : widget.recording
                    ? const Icon(Icons.send)
                    : canSendFromInput
                    ? const Icon(Icons.send)
                    : Icon(
                        widget.wavRetryRequested
                            ? Icons.mic_external_on
                            : Icons.mic,
                      );
                final label = widget.sendingAudio || widget.sendingMedia
                    ? 'Sending'
                    : !widget.connected && canSendFromInput
                    ? 'Send'
                    : widget.recording
                    ? 'Recording... ${widget.recordingDurationLabel}'
                    : canSendFromInput
                    ? 'Send'
                    : widget.wavRetryRequested
                    ? 'Record WAV'
                    : 'Record';
                final tooltip = widget.recording
                    ? 'Send recording'
                    : !widget.connected && canSendFromInput
                    ? 'Connect and send'
                    : !widget.connected
                    ? 'Connect and record'
                    : canSendFromInput
                    ? widget.hasPendingMedia
                          ? 'Send attachment'
                          : 'Send text'
                    : widget.wavRetryRequested
                    ? 'Record WAV retry'
                    : 'Record voice query';
                final mainButtonStyle = FilledButton.styleFrom(
                  minimumSize: const Size(112, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                );
                final mainButton = Tooltip(
                  message: tooltip,
                  child: FilledButton.icon(
                    style: recordingShell
                        ? mainButtonStyle.copyWith(
                            backgroundColor: const WidgetStatePropertyAll(
                              Colors.transparent,
                            ),
                            foregroundColor: const WidgetStatePropertyAll(
                              Color(0xff1b140f),
                            ),
                          )
                        : mainButtonStyle,
                    onPressed: onMainPressed,
                    icon: icon,
                    label: Text(label),
                  ),
                );
                final actionButton = recordingShell
                    ? _RecordingButton(
                        sendWipe: widget.sendingAudio && !widget.recording,
                        child: mainButton,
                      )
                    : mainButton;

                return Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: attachTooltip,
                      onPressed: (widget.recording || widget.sendingMedia)
                          ? attachAction
                          : canAttach
                          ? attachAction
                          : null,
                      style: attachStyle,
                      icon: attachIcon,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: actionButton),
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

class _RecordingButton extends StatefulWidget {
  const _RecordingButton({required this.child, required this.sendWipe});

  final Widget child;
  final bool sendWipe;

  @override
  State<_RecordingButton> createState() => _RecordingButtonState();
}

class _RecordingButtonState extends State<_RecordingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wipeController;
  late final Animation<double> _wipeAnimation;

  @override
  void initState() {
    super.initState();
    _wipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _wipeAnimation = CurvedAnimation(
      parent: _wipeController,
      curve: Curves.easeOutCubic,
    );
    if (widget.sendWipe) {
      _wipeController.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _RecordingButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sendWipe && !oldWidget.sendWipe) {
      _wipeController.forward(from: 0);
    } else if (!widget.sendWipe && oldWidget.sendWipe) {
      _wipeController.value = 0;
    }
  }

  @override
  void dispose() {
    _wipeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xffdfa257))),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _wipeAnimation,
              builder: (context, _) {
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: _wipeAnimation.value,
                    widthFactor: 1,
                    alignment: Alignment.bottomCenter,
                    child: const ColoredBox(color: Color(0xff68d49f)),
                  ),
                );
              },
            ),
          ),
          FilledButtonTheme(
            data: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: const Color(0xff1b140f),
              ),
            ),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _DigitalThinkingIndicator extends StatefulWidget {
  const _DigitalThinkingIndicator({
    required this.color,
    this.style = _WorkingAnimationStyle.digitalFlow,
    this.width = 42,
    this.height = 18,
  });

  final Color color;
  final _WorkingAnimationStyle style;
  final double width;
  final double height;

  @override
  State<_DigitalThinkingIndicator> createState() =>
      _DigitalThinkingIndicatorState();
}

class _DigitalThinkingIndicatorState extends State<_DigitalThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2560),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: CustomPaint(
        painter: _DigitalThinkingPainter(
          animation: _controller,
          color: widget.color,
          style: widget.style,
        ),
      ),
    );
  }
}

class _DigitalThinkingPainter extends CustomPainter {
  const _DigitalThinkingPainter({
    required this.animation,
    required this.color,
    required this.style,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final _WorkingAnimationStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case _WorkingAnimationStyle.off:
        return;
      case _WorkingAnimationStyle.digitalFlow:
        _paintDigitalFlow(canvas, size);
        break;
      case _WorkingAnimationStyle.neuralLattice:
        _paintNeuralLattice(canvas, size);
        break;
      case _WorkingAnimationStyle.orbitSync:
        _paintOrbitSync(canvas, size);
        break;
      case _WorkingAnimationStyle.scanLine:
        _paintScanLine(canvas, size);
        break;
      case _WorkingAnimationStyle.dataPackets:
        _paintDataPackets(canvas, size);
        break;
      case _WorkingAnimationStyle.pulseSpectrum:
        _paintPulseSpectrum(canvas, size);
        break;
    }
  }

  void _paintDigitalFlow(Canvas canvas, Size size) {
    final t = animation.value;
    final centerY = size.height / 2;
    final count = size.width > 34 ? 7 : 5;
    final step = size.width / (count - 1);
    final points = <Offset>[];

    for (var index = 0; index < count; index++) {
      final phase = (t * math.pi * 2) + (index * 0.72);
      final x = index * step;
      final y = centerY + math.sin(phase) * size.height * 0.22;
      points.add(Offset(x, y));
    }

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.34)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, linePaint);

    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final pulse = (math.sin((t * math.pi * 2) + (index * 0.95)) + 1) / 2;
      final radius = 1.8 + (pulse * 1.5);
      final nodePaint = Paint()
        ..color = color.withValues(alpha: 0.42 + (pulse * 0.5))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(point, radius, nodePaint);

      if (index.isEven) {
        final tickPaint = Paint()
          ..color = color.withValues(alpha: 0.16 + (pulse * 0.22))
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(point.dx, centerY - size.height * 0.42),
          Offset(point.dx, centerY - size.height * 0.32),
          tickPaint,
        );
        canvas.drawLine(
          Offset(point.dx, centerY + size.height * 0.32),
          Offset(point.dx, centerY + size.height * 0.42),
          tickPaint,
        );
      }
    }
  }

  void _paintNeuralLattice(Canvas canvas, Size size) {
    final t = animation.value;
    final rows = 3;
    final columns = size.width > 40 ? 6 : 4;
    final xStep = size.width / (columns - 1);
    final yStep = size.height / (rows - 1);
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns - 1; column++) {
        final a = Offset(column * xStep, row * yStep);
        final b = Offset((column + 1) * xStep, row * yStep);
        canvas.drawLine(a, b, linePaint);
      }
    }
    for (var column = 0; column < columns; column++) {
      canvas.drawLine(
        Offset(column * xStep, 0),
        Offset(column * xStep, size.height),
        linePaint..color = color.withValues(alpha: 0.08),
      );
    }

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final phase = (t + ((row + column) * 0.11)) % 1;
        final pulse = (math.sin(phase * math.pi * 2) + 1) / 2;
        final radius = 1.4 + (pulse * 1.9);
        final paint = Paint()
          ..color = color.withValues(alpha: 0.28 + (pulse * 0.6));
        canvas.drawCircle(Offset(column * xStep, row * yStep), radius, paint);
      }
    }
  }

  void _paintOrbitSync(Canvas canvas, Size size) {
    final t = animation.value;
    final center = Offset(size.width / 2, size.height / 2);
    final radiusX = size.width * 0.38;
    final radiusY = size.height * 0.32;
    final orbitPaint = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    canvas.drawOval(
      Rect.fromCenter(center: center, width: radiusX * 2, height: radiusY * 2),
      orbitPaint,
    );
    canvas.drawCircle(
      center,
      math.max(1.8, size.height * 0.12),
      Paint()..color = color.withValues(alpha: 0.4),
    );

    for (var index = 0; index < 5; index++) {
      final angle = (t * math.pi * 2) + (index * math.pi * 0.4);
      final depth = (math.sin(angle) + 1) / 2;
      final point = Offset(
        center.dx + math.cos(angle) * radiusX,
        center.dy + math.sin(angle) * radiusY,
      );
      canvas.drawCircle(
        point,
        1.5 + depth * 2.1,
        Paint()..color = color.withValues(alpha: 0.28 + depth * 0.62),
      );
    }
  }

  void _paintScanLine(Canvas canvas, Size size) {
    final t = animation.value;
    final scanX = size.width * t;
    final backgroundPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (var y = 2.0; y < size.height; y += 5) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), backgroundPaint);
    }

    final scanPaint = Paint()
      ..color = color.withValues(alpha: 0.72)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(scanX, 0), Offset(scanX, size.height), scanPaint);
    for (var index = 0; index < 6; index++) {
      final x = (scanX - (index * size.width / 7)) % size.width;
      final alpha = (0.5 - index * 0.06).clamp(0.12, 0.5).toDouble();
      canvas.drawCircle(
        Offset(x, size.height * (0.24 + (index % 3) * 0.26)),
        1.5,
        Paint()..color = color.withValues(alpha: alpha),
      );
    }
  }

  void _paintDataPackets(Canvas canvas, Size size) {
    final t = animation.value;
    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final yValues = [size.height * 0.28, size.height * 0.5, size.height * 0.72];
    for (final y in yValues) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), trackPaint);
    }

    for (var index = 0; index < 7; index++) {
      final lane = index % yValues.length;
      final progress = (t + index * 0.17) % 1;
      final packetWidth = math.max(4.0, size.width * 0.12);
      final x = progress * (size.width + packetWidth) - packetWidth;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x,
          yValues[lane] - size.height * 0.11,
          packetWidth,
          math.max(3.0, size.height * 0.18),
        ),
        const Radius.circular(2),
      );
      final pulse = (math.sin((progress + lane * 0.21) * math.pi * 2) + 1) / 2;
      canvas.drawRRect(
        rect,
        Paint()..color = color.withValues(alpha: 0.28 + pulse * 0.5),
      );
    }
  }

  void _paintPulseSpectrum(Canvas canvas, Size size) {
    final t = animation.value;
    final bars = size.width > 40 ? 9 : 6;
    final gap = size.width * 0.045;
    final barWidth = (size.width - (gap * (bars - 1))) / bars;
    for (var index = 0; index < bars; index++) {
      final phase = (t * math.pi * 2) + index * 0.55;
      final pulse = (math.sin(phase) + 1) / 2;
      final height = size.height * (0.22 + pulse * 0.72);
      final left = index * (barWidth + gap);
      final top = (size.height - height) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barWidth, height),
          Radius.circular(barWidth / 2),
        ),
        Paint()..color = color.withValues(alpha: 0.28 + pulse * 0.58),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DigitalThinkingPainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.color != color ||
        oldDelegate.style != style;
  }
}

class _SpeakingEqualizer extends StatelessWidget {
  const _SpeakingEqualizer({required this.animation, required this.color});

  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 136,
      height: 16,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var index = 0; index < 18; index++)
                _EqualizerBar(
                  color: color,
                  height: _barHeight(animation.value, index),
                ),
            ],
          );
        },
      ),
    );
  }

  double _barHeight(double value, int index) {
    final phase = (value + (index * 0.1)) % 1.0;
    final rise = 1 - ((phase - 0.5).abs() * 2);
    return 4 + (10 * rise.clamp(0, 1));
  }
}

class _EqualizerBar extends StatelessWidget {
  const _EqualizerBar({required this.color, required this.height});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _MessageTile extends StatefulWidget {
  const _MessageTile({
    required this.message,
    required this.showResend,
    required this.speaking,
    required this.workingAnimationStyle,
    required this.stopSpeakingOnTap,
    required this.onStopSpeaking,
    required this.onResend,
  });

  final ConversationMessage message;
  final bool showResend;
  final bool speaking;
  final _WorkingAnimationStyle workingAnimationStyle;
  final bool stopSpeakingOnTap;
  final VoidCallback? onStopSpeaking;
  final VoidCallback? onResend;

  @override
  State<_MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<_MessageTile>
    with SingleTickerProviderStateMixin {
  bool _flash = false;
  late final AnimationController _equalizerController;

  @override
  void initState() {
    super.initState();
    _equalizerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    );
    _syncEqualizer();
  }

  @override
  void didUpdateWidget(covariant _MessageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speaking != widget.speaking) {
      _syncEqualizer();
    }
  }

  @override
  void dispose() {
    _equalizerController.dispose();
    super.dispose();
  }

  void _syncEqualizer() {
    if (widget.speaking) {
      _equalizerController.repeat();
    } else {
      _equalizerController.stop();
      _equalizerController.value = 0;
    }
  }

  void _handleTap() {
    if (widget.stopSpeakingOnTap) {
      widget.onStopSpeaking?.call();
    }
    setState(() => _flash = true);
    Future<void>.delayed(const Duration(milliseconds: 170), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final incoming = widget.message.direction == MessageDirection.incoming;
    final transcript = widget.message.kind == 'transcript';
    final processing = widget.message.kind == 'transcribing';
    final userSide = !incoming || transcript;
    final canFlashOnTap = widget.stopSpeakingOnTap;
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = userSide
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHigh;
    final flashColor = Color.lerp(baseColor, colorScheme.primary, 0.16)!;

    if (widget.message.kind == 'processing') {
      if (!widget.workingAnimationStyle.enabled) {
        return const SizedBox.shrink();
      }
      return Card(
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          width: 58,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: _DigitalThinkingIndicator(
            width: 34,
            height: 20,
            color: colorScheme.primary,
            style: widget.workingAnimationStyle,
          ),
        ),
      );
    }

    final title = _messageTitle(widget.message.kind);
    final headerActions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatTime(widget.message.timestamp),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        if (widget.showResend) ...[
          const SizedBox(width: 4),
          SizedBox.square(
            dimension: 36,
            child: IconButton(
              tooltip: _resendTooltip(),
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: widget.onResend,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ],
        if (incoming && widget.message.text.trim().isNotEmpty) ...[
          const SizedBox(width: 4),
          SizedBox.square(
            dimension: 36,
            child: IconButton(
              tooltip: widget.speaking ? 'Stop speaking' : 'Copy full message',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: widget.speaking
                  ? widget.onStopSpeaking
                  : () => _copyMessage(context),
              icon: Icon(
                widget.speaking
                    ? Icons.stop_circle_outlined
                    : Icons.content_copy,
              ),
            ),
          ),
        ],
      ],
    );
    final tile = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _messageIcon(
                  incoming: incoming,
                  transcript: transcript,
                  processing: processing,
                ),
                color: userSide
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: Row(
                    children: [
                      Expanded(
                        child: widget.speaking
                            ? Center(
                                child: _SpeakingEqualizer(
                                  animation: _equalizerController,
                                  color: userSide
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.primary,
                                ),
                              )
                            : Align(
                                alignment: Alignment.centerLeft,
                                child: title.isEmpty
                                    ? const SizedBox.shrink()
                                    : Text(
                                        title,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                              ),
                      ),
                      headerActions,
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (processing)
            Row(
              children: [
                if (widget.workingAnimationStyle.enabled) ...[
                  _DigitalThinkingIndicator(
                    width: 42,
                    height: 18,
                    color: userSide
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.primary,
                    style: widget.workingAnimationStyle,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: MarkdownBody(
                    data: widget.message.text,
                    selectable: !widget.stopSpeakingOnTap,
                    softLineBreak: true,
                  ),
                ),
              ],
            )
          else
            MarkdownBody(
              data: widget.message.text,
              selectable: !widget.stopSpeakingOnTap,
              softLineBreak: true,
            ),
        ],
      ),
    );

    return Card(
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: _flash ? flashColor : baseColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: canFlashOnTap ? _handleTap : null,
          child: tile,
        ),
      ),
    );
  }

  String _messageTitle(String kind) {
    if (kind == 'response' ||
        kind == 'transcript' ||
        kind == 'transcribing' ||
        kind == 'processing') {
      return '';
    }
    return kind;
  }

  String _resendTooltip() {
    if (widget.message.kind == 'audio') return 'Resend voice note';
    if (widget.message.kind == 'transcript') return 'Send transcript as query';
    return 'Resend query';
  }

  Future<void> _copyMessage(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.message.text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied')));
  }

  IconData _messageIcon({
    required bool incoming,
    required bool transcript,
    required bool processing,
  }) {
    if (processing || transcript) return Icons.notes;
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

  Map<String, dynamic> toJson() => {
    'direction': direction == MessageDirection.incoming
        ? 'incoming'
        : 'outgoing',
    'kind': kind,
    'text': text,
    'eventId': eventId,
    'timestamp': timestamp.toIso8601String(),
    if (audio != null) 'audio': _serializeBridgeAudioReference(audio!),
  };

  static ConversationMessage? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final direction = _decodeDirection(raw['direction']);
    final kind = raw['kind']?.toString().trim();
    final text = raw['text']?.toString() ?? '';
    final eventId = raw['eventId']?.toString() ?? '';
    final timestampRaw = raw['timestamp']?.toString() ?? '';
    final timestamp = DateTime.tryParse(timestampRaw);
    if (kind == null || kind.isEmpty) return null;
    return ConversationMessage(
      direction: direction,
      kind: kind,
      text: text,
      eventId: eventId,
      timestamp: timestamp ?? DateTime.now(),
      audio: _deserializeBridgeAudioReference(raw['audio']),
    );
  }

  static MessageDirection _decodeDirection(dynamic raw) {
    final direction = raw?.toString();
    if (direction == 'incoming') return MessageDirection.incoming;
    return MessageDirection.outgoing;
  }
}

Map<String, dynamic>? _serializeBridgeAudioReference(
  BridgeAudioReference audio,
) {
  return {
    'url': audio.url,
    'sha256': audio.sha256,
    'size': audio.size.toString(),
    'mediaType': audio.mediaType,
    if (audio.name != null) 'name': audio.name,
    if (audio.encryption != null)
      'encryption': {
        'algorithm': audio.encryption!.algorithm,
        'key': audio.encryption!.key,
        'nonce': audio.encryption!.nonce,
        'plaintextSha256': audio.encryption!.plaintextSha256,
        'plaintextSize': audio.encryption!.plaintextSize.toString(),
        'plaintextMediaType': audio.encryption!.plaintextMediaType,
      },
  };
}

BridgeAudioReference? _deserializeBridgeAudioReference(dynamic raw) {
  if (raw is! Map) return null;
  final url = raw['url']?.toString();
  final sha256 = raw['sha256']?.toString();
  final sizeRaw = raw['size']?.toString();
  final mediaType = raw['mediaType']?.toString();
  if (url == null || sha256 == null || sizeRaw == null || mediaType == null) {
    return null;
  }

  final encryptionRaw = raw['encryption'];
  final encryption = encryptionRaw is Map
      ? _deserializeBridgeAudioEncryption(encryptionRaw)
      : null;
  final size = BigInt.tryParse(sizeRaw);
  if (size == null) return null;

  return BridgeAudioReference(
    url: url,
    sha256: sha256,
    size: size,
    mediaType: mediaType,
    name: raw['name']?.toString(),
    encryption: encryption,
  );
}

BridgeAudioEncryption? _deserializeBridgeAudioEncryption(Map encryptionRaw) {
  final algorithm = encryptionRaw['algorithm']?.toString();
  final key = encryptionRaw['key']?.toString();
  final nonce = encryptionRaw['nonce']?.toString();
  final plaintextSha256 = encryptionRaw['plaintextSha256']?.toString();
  final plaintextSizeRaw = encryptionRaw['plaintextSize']?.toString();
  final plaintextMediaType = encryptionRaw['plaintextMediaType']?.toString();
  final plaintextSize = BigInt.tryParse(plaintextSizeRaw ?? '');
  if (algorithm == null ||
      algorithm.isEmpty ||
      key == null ||
      key.isEmpty ||
      nonce == null ||
      nonce.isEmpty ||
      plaintextSha256 == null ||
      plaintextSha256.isEmpty ||
      plaintextSize == null ||
      plaintextMediaType == null ||
      plaintextMediaType.isEmpty) {
    return null;
  }

  return BridgeAudioEncryption(
    algorithm: algorithm,
    key: key,
    nonce: nonce,
    plaintextSha256: plaintextSha256,
    plaintextSize: plaintextSize,
    plaintextMediaType: plaintextMediaType,
  );
}
