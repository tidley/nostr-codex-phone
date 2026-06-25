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
import 'package:nostr_codex_phone/src/bridge_json.dart';
import 'package:nostr_codex_phone/src/blossom_config.dart';
import 'package:nostr_codex_phone/src/compact_identifier.dart';
import 'package:nostr_codex_phone/src/conversation_message.dart';
import 'package:nostr_codex_phone/src/incoming_route.dart';
import 'package:nostr_codex_phone/src/repo_target_merge.dart';
import 'package:nostr_codex_phone/src/repo_choice.dart';
import 'package:nostr_codex_phone/src/repo_target.dart';
import 'package:nostr_codex_phone/src/media_models.dart';
import 'package:nostr_codex_phone/src/text_utils.dart';
import 'package:nostr_codex_phone/src/working_animation.dart';
import 'package:nostr_codex_phone/src/voice_recording.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

part 'src/main_widgets.dart';

const _ttsControlChannel = MethodChannel('nostr_codex_phone/tts_control');
const _blossomUploadTimeout = Duration(minutes: 2);
const _nostrSendTimeout = Duration(seconds: 15);
const _allowedLinkSchemes = {'http', 'https', 'mailto', 'tel', 'nostr'};

enum _PendingMessageCompletion { transcript, response }

class _PendingProcessingMessage {
  const _PendingProcessingMessage({
    required this.conversationKey,
    required this.eventId,
    required this.completion,
    required this.label,
  });

  final String conversationKey;
  final String eventId;
  final _PendingMessageCompletion completion;
  final String label;
}

class _PendingSessionStart {
  const _PendingSessionStart({required this.workdir, required this.completer});

  final String workdir;
  final Completer<RepoTarget> completer;
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

class _NostrCodexHomeState extends State<NostrCodexHome>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
  static const _workingAnimationSpeedStorageKey = 'working_animation_speed';
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
  final _pendingTargetInvites = <RepoTarget>[];
  final ScrollController _chatScrollController = ScrollController();
  late final AnimationController _menuNotificationPulseController;

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
  Completer<List<RepoChoice>>? _pendingRepoListCompleter;
  _PendingSessionStart? _pendingSessionStart;
  List<RepoChoice> _cachedRepoChoices = const [];
  bool _autoSpeak = true;
  bool _speaking = false;
  bool _wavRetryRequested = false;
  List<RepoTarget> _repoTargets = const [];
  String? _selectedRepoTargetId;
  double _ttsRate = 0.48;
  double _ttsPitch = 1.0;
  double _ttsVolume = 1.0;
  WorkingAnimationStyle _workingAnimationStyle =
      WorkingAnimationStyle.digitalFlow;
  double _workingAnimationSpeed = 1.0;
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
  VoiceRecordingFormat? _activeRecordingFormat;
  String? _ownPubkey;
  String? _status;
  MediaSelection? _pendingMediaAttachment;
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

  bool get _activeConversationSendBlocked =>
      _sendingInActiveConversation ||
      _sendingAudioInActiveConversation ||
      _sendingMediaInActiveConversation;

  bool get _sessionSwitchBlocked => _sending || _sendingMedia;

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
    return sortConversationMessagesChronological(filtered);
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
      byKey[_conversationMessageMergeKey(message)] = message;
    }
    return sortConversationMessagesNewestFirst(
      byKey.values,
    ).take(_maxConversationMessages).toList();
  }

  String _conversationMessageMergeKey(ConversationMessage message) {
    final eventId = message.eventId.trim();
    if (eventId.isEmpty) {
      return '${message.direction.name}:${message.kind}:${message.timestamp.toIso8601String()}:${message.text}';
    }

    if (message.direction == MessageDirection.outgoing) {
      final kind =
          message.kind == 'transcribing' || message.kind == 'transcript'
          ? 'transcript'
          : message.kind;
      return 'outgoing:$kind:$eventId';
    }

    final kind =
        message.kind == 'processing' ||
            message.kind == 'response' ||
            message.kind == 'audio_retry' ||
            message.kind == 'error' ||
            message.kind == 'invalid' ||
            message.kind == 'cancelled'
        ? 'response'
        : message.kind;
    return 'incoming:$kind:$eventId';
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
    WidgetsBinding.instance.addObserver(this);
    _menuNotificationPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _configureTtsHandlers();
    unawaited(_loadSettings());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _dismissQueryKeyboard();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    _menuNotificationPulseController.dispose();
    unawaited(nostrStop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_connected) return;
    unawaited(_fetchRecentInboxMessages(allowCatchUpSpeech: true));
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
    final workingAnimationSpeed = await _storage.read(
      key: _workingAnimationSpeedStorageKey,
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
        RepoTarget(
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
      _blossomServerController.text = blossomServer ?? autoBlossomServer;
      _ttsLanguage = _cleanStoredString(ttsLanguage) ?? _ttsLanguage;
      _ttsEngine = _cleanStoredString(ttsEngine);
      _ttsRate = _storedDouble(ttsRate, _ttsRate, 0.1, 1.0);
      _ttsPitch = _storedDouble(ttsPitch, _ttsPitch, 0.5, 2.0);
      _ttsVolume = _storedDouble(ttsVolume, _ttsVolume, 0.0, 1.0);
      _workingAnimationStyle = WorkingAnimationStyle.fromStorage(
        workingAnimation,
      );
      _workingAnimationSpeed = _storedDouble(
        workingAnimationSpeed,
        _workingAnimationSpeed,
        0.1,
        5.0,
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

  List<RepoTarget> _decodeRepoTargets(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final targets = <RepoTarget>[];
      final seenIds = <String>{};
      for (final item in decoded) {
        final target = RepoTarget.fromJson(item);
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

  List<RepoChoice> _decodeRepoChoicesCache(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final choices = decoded
          .map(RepoChoice.fromJson)
          .whereType<RepoChoice>()
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

  RepoTarget? _targetById(List<RepoTarget> targets, String? id) {
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
    return 'Repo ${compactIdentifier(pubkey.trim())}';
  }

  RepoTarget? _activeRepoTargetFromControllers() {
    final pubkey = _peerPubkeyController.text.trim();
    final relays = _relayLines();
    if (pubkey.isEmpty || relays.isEmpty) return null;

    final name = _targetNameController.text.trim();
    final existing = _targetById(_repoTargets, _selectedRepoTargetId);
    return RepoTarget(
      id: _selectedRepoTargetId ?? _newRepoTargetId(),
      name: name.isEmpty ? _defaultTargetName(pubkey) : name,
      pubkey: pubkey,
      relays: relays,
      workdir: existing?.workdir,
      parentPubkey: existing?.parentPubkey,
      parentRelays: existing?.parentRelays,
      parentWorkdir: existing?.parentWorkdir,
      parentName: existing?.parentName,
      pairingSecret: existing?.pairingSecret,
      isMasterSession: existing?.isMasterSession ?? false,
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
    final existingIndex = repoTargetMergeIndex(
      [
        for (final item in targets)
          RepoTargetMergeIdentity(
            id: item.id,
            pubkey: item.pubkey,
            workdir: item.workdir,
          ),
      ],
      RepoTargetMergeIdentity(
        id: target.id,
        pubkey: target.pubkey,
        workdir: target.workdir,
      ),
    );
    final savedTarget = existingIndex == -1
        ? target
        : target.copyWith(
            id: targets[existingIndex].id,
            isMasterSession: targets[existingIndex].isMasterSession,
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

  RepoTarget? _repoTargetFromQrPayload(String raw) {
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
      final pairingSecret = decoded['pairing_secret']?.toString().trim();
      final rawName = decoded['name']?.toString().trim() ?? '';
      final name = rawName.isNotEmpty
          ? rawName
          : _workdirTargetName(workdir) ?? _defaultTargetName(pubkey);
      return RepoTarget(
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
        pairingSecret: pairingSecret == null || pairingSecret.isEmpty
            ? null
            : pairingSecret,
      );
    } catch (_) {
      return null;
    }
  }

  RepoTarget? _repoTargetFromInvitePayload(String raw) {
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
      final pairingSecret = invite['pairing_secret']?.toString().trim();
      final rawName = invite['name']?.toString().trim() ?? '';
      final name = rawName.isNotEmpty
          ? rawName
          : _workdirTargetName(workdir) ?? _defaultTargetName(pubkey);
      return RepoTarget(
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
        pairingSecret: pairingSecret == null || pairingSecret.isEmpty
            ? null
            : pairingSecret,
      );
    } catch (_) {
      return null;
    }
  }

  RepoTarget _targetWithParentRouteFromMessage(
    RepoTarget target,
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

    return RepoTarget(
      id: target.id,
      name: target.name,
      pubkey: target.pubkey,
      relays: target.relays,
      workdir: target.workdir,
      parentPubkey: parentPubkey,
      parentRelays: parentRelays,
      parentWorkdir: selectedParent?.workdir,
      parentName: parentName,
      pairingSecret: target.pairingSecret,
    );
  }

  List<RepoChoice>? _repoChoicesFromRepoListPayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final repoList = decoded['repo_list'];
      if (repoList is! Map<String, dynamic>) return null;
      final roots = repoList['roots'];
      if (roots is! Iterable) return const [];
      final choices = <RepoChoice>[];
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
            RepoChoice(
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

  Future<void> _offerTargetInvite(RepoTarget target) async {
    if (!mounted) return;
    if (_recording) {
      _queueTargetInvite(target);
      return;
    }
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

  void _queueTargetInvite(RepoTarget target) {
    final existingIndex = repoTargetMergeIndex(
      [
        for (final item in _pendingTargetInvites)
          RepoTargetMergeIdentity(
            id: item.id,
            pubkey: item.pubkey,
            workdir: item.workdir,
          ),
      ],
      RepoTargetMergeIdentity(
        id: target.id,
        pubkey: target.pubkey,
        workdir: target.workdir,
      ),
    );
    setState(() {
      if (existingIndex >= 0) {
        _pendingTargetInvites[existingIndex] = target;
      } else {
        _pendingTargetInvites.add(target);
      }
      _status = 'Session request waiting';
    });
    _pulseMenuNotification();
  }

  Future<void> _openSessionsMenu(BuildContext scaffoldContext) async {
    if (_pendingTargetInvites.isNotEmpty && !_recording) {
      final target = _pendingTargetInvites.removeAt(0);
      if (mounted) setState(() {});
      await _offerTargetInvite(target);
      return;
    }
    if (!scaffoldContext.mounted) return;
    Scaffold.of(scaffoldContext).openDrawer();
  }

  void _pulseMenuNotification() {
    if (!mounted) return;
    _menuNotificationPulseController.forward(from: 0);
  }

  Future<RepoTarget?> _saveAndSelectRepoTarget(
    RepoTarget target, {
    required String status,
  }) async {
    if (_recording) {
      await _cancelRecording();
    }
    if (_connected || _connecting) {
      await _disconnect(expand: false);
    }
    if (!mounted) return null;

    final targets = [..._repoTargets];
    final existingIndex = repoTargetMergeIndex(
      [
        for (final item in targets)
          RepoTargetMergeIdentity(
            id: item.id,
            pubkey: item.pubkey,
            workdir: item.workdir,
          ),
      ],
      RepoTargetMergeIdentity(
        id: target.id,
        pubkey: target.pubkey,
        workdir: target.workdir,
      ),
    );
    final savedTarget = existingIndex == -1
        ? target
        : target.copyWith(
            id: targets[existingIndex].id,
            isMasterSession: targets[existingIndex].isMasterSession,
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
    return savedTarget;
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
    RepoTarget target,
    Completer<RepoTarget> completer,
  ) async {
    final savedTarget = await _saveAndSelectRepoTarget(
      target,
      status: 'Started session',
    );
    if (!completer.isCompleted) {
      completer.complete(savedTarget ?? target);
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
    if (_sessionSwitchBlocked) {
      if (mounted) {
        setState(
          () => _status = 'Finish current send before switching sessions',
        );
      }
      return;
    }
    final target = _targetById(_repoTargets, targetId);
    if (target == null) return;

    _dismissQueryKeyboard();
    final deferReconnect = _sendingAudio;
    final reconnect = _connected && !deferReconnect;
    if (_recording) {
      await _cancelRecording();
    }
    if (!deferReconnect && (_connected || _connecting)) {
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
      _status = deferReconnect
          ? 'Selected ${target.displayName}; voice note sending in background'
          : 'Selected ${target.displayName}';
    });
    await _saveSettings();
    await _saveUnreadCounts();
    await _loadConversationHistoryForActiveSession();
    if (reconnect && mounted) {
      await _connect();
    }
  }

  void _applyRepoTargetFields(RepoTarget? target) {
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
    return sortConversationMessagesNewestFirst(messages);
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
    final trimmed = sortConversationMessagesNewestFirst(
      messages,
    ).take(_maxConversationMessages).toList();
    final store = await _readConversationHistoryStore();
    store[conversationKey] = trimmed.map((item) => item.toJson()).toList();
    await _writeConversationHistoryStore(store);
  }

  Future<void> _deleteConversationHistoryForKey(String conversationKey) async {
    final store = await _readConversationHistoryStore();
    if (!store.remove(conversationKey)) return;
    await _writeConversationHistoryStore(store);
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
    final displayLabel =
        completion == _PendingMessageCompletion.transcript &&
            _pendingReplyTargetIds.contains(conversationKey)
        ? 'Queued'
        : label;
    _pendingProcessingMessages.add(
      _PendingProcessingMessage(
        conversationKey: conversationKey,
        eventId: eventId,
        completion: completion,
        label: label,
      ),
    );
    _appendMessageForConversation(
      conversationKey,
      ConversationMessage(
        direction: MessageDirection.outgoing,
        kind: 'transcribing',
        text: displayLabel,
        eventId: eventId,
        timestamp: DateTime.now(),
      ),
    );
  }

  bool _tryCompleteTranscription(
    String conversationKey,
    String transcript,
    String transcriptEventId,
  ) {
    while (true) {
      final pending = _takePendingProcessingMessage(
        conversationKey,
        _PendingMessageCompletion.transcript,
      );
      if (pending == null) {
        var index = _pendingProcessingMessageIndex(
          conversationKey,
          transcriptEventId,
        );
        if (index < 0) {
          index = _singlePendingTranscriptionIndex(conversationKey);
        }
        if (index < 0) return false;
        final messages = _messagesByTarget[conversationKey] ?? const [];
        final eventId = messages[index].eventId;
        _completeTranscriptionAtIndex(
          conversationKey: conversationKey,
          index: index,
          transcript: transcript,
          eventId: eventId,
        );
        return true;
      }

      final index = _pendingProcessingMessageIndex(
        conversationKey,
        pending.eventId,
      );
      if (index < 0) continue;

      _completeTranscriptionAtIndex(
        conversationKey: conversationKey,
        index: index,
        transcript: transcript,
        eventId: pending.eventId,
      );
      return true;
    }
  }

  void _completeTranscriptionAtIndex({
    required String conversationKey,
    required int index,
    required String transcript,
    required String eventId,
  }) {
    final messages = _messagesByTarget.putIfAbsent(conversationKey, () => []);
    messages[index] = ConversationMessage(
      direction: MessageDirection.outgoing,
      kind: 'transcript',
      text: transcript,
      eventId: eventId,
      timestamp: DateTime.now(),
      audio: messages[index].audio,
    );
    unawaited(_saveConversationHistoryForKey(conversationKey));
    _appendIncomingProcessingPlaceholder(conversationKey, eventId);
    if (conversationKey == _activeConversationKey) {
      _scrollToLatestMessage();
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

  int _singlePendingTranscriptionIndex(String conversationKey) {
    final messages = _messagesByTarget[conversationKey];
    if (messages == null) return -1;

    var foundIndex = -1;
    for (var index = 0; index < messages.length; index += 1) {
      final message = messages[index];
      if (message.kind != 'transcribing' ||
          message.direction != MessageDirection.outgoing) {
        continue;
      }
      if (foundIndex >= 0) return -1;
      foundIndex = index;
    }
    return foundIndex;
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

    var oldestIndex = -1;
    for (var index = 0; index < messages.length; index += 1) {
      final message = messages[index];
      if (message.kind == 'processing' &&
          message.direction == MessageDirection.incoming) {
        if (oldestIndex < 0 ||
            message.timestamp.isBefore(messages[oldestIndex].timestamp)) {
          oldestIndex = index;
        }
      }
    }
    if (oldestIndex >= 0) {
      messages[oldestIndex] = replacement;
      _syncPendingReplyTarget(conversationKey);
      unawaited(_saveConversationHistoryForKey(conversationKey));
      if (conversationKey == _activeConversationKey) {
        _scrollToLatestMessage();
      }
      return true;
    }
    _syncPendingReplyTarget(conversationKey);
    return false;
  }

  void _promoteOldestQueuedTranscription(String conversationKey) {
    final messages = _messagesByTarget[conversationKey];
    if (messages == null) return;

    var oldestIndex = -1;
    String label = 'Transcribing...';
    for (var index = 0; index < messages.length; index += 1) {
      final message = messages[index];
      if (message.kind != 'transcribing' ||
          message.direction != MessageDirection.outgoing ||
          message.text.trim().toLowerCase() != 'queued') {
        continue;
      }
      if (oldestIndex < 0 ||
          message.timestamp.isBefore(messages[oldestIndex].timestamp)) {
        oldestIndex = index;
        _PendingProcessingMessage? pending;
        for (final item in _pendingProcessingMessages) {
          if (item.conversationKey == conversationKey &&
              item.eventId == message.eventId) {
            pending = item;
            break;
          }
        }
        label = pending?.label ?? label;
      }
    }
    if (oldestIndex < 0) return;

    final queued = messages[oldestIndex];
    messages[oldestIndex] = ConversationMessage(
      direction: queued.direction,
      kind: queued.kind,
      text: label,
      eventId: queued.eventId,
      timestamp: queued.timestamp,
      audio: queued.audio,
    );
    unawaited(_saveConversationHistoryForKey(conversationKey));
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

  bool _hasIncomingProcessingPlaceholder(String conversationKey) {
    final messages = _messagesByTarget[conversationKey] ?? const [];
    return messages.any(
      (message) =>
          message.kind == 'processing' &&
          message.direction == MessageDirection.incoming,
    );
  }

  bool _replaceIncomingProcessingPlaceholder(
    String conversationKey,
    String eventId,
    ConversationMessage replacement,
  ) {
    final messages = _messagesByTarget[conversationKey];
    if (messages == null) return false;
    final index = messages.indexWhere(
      (message) =>
          message.kind == 'processing' &&
          message.direction == MessageDirection.incoming &&
          message.eventId == eventId,
    );
    if (index < 0) return false;
    messages[index] = replacement;
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
          blossomPresets: blossomPresets,
          ownPubkey: _ownPubkey,
          connected: _connected,
          connecting: _connecting,
          speaking: _speaking,
          hasReplay: _lastSpokenText?.trim().isNotEmpty ?? false,
          autoSpeak: _autoSpeak,
          workingAnimationStyle: _workingAnimationStyle,
          workingAnimationSpeed: _workingAnimationSpeed,
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
          onWorkingAnimationSpeedChanged: _setWorkingAnimationSpeed,
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

  Future<void> _renameRepoTarget(RepoTarget target) async {
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

    targets[index] = target.copyWith(name: cleaned);
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
    await _storage.write(
      key: _workingAnimationSpeedStorageKey,
      value: _workingAnimationSpeed.toString(),
    );
  }

  void _setWorkingAnimationStyle(WorkingAnimationStyle style) {
    setState(() => _workingAnimationStyle = style);
    unawaited(_saveWorkingAnimationStyle());
  }

  void _setWorkingAnimationSpeed(double speed) {
    setState(() => _workingAnimationSpeed = speed.clamp(0.1, 5.0));
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

  Future<void> _connectToTargetInBackground(RepoTarget target) async {
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

  Future<bool> _ensureConnectedForVoiceSend(RepoTarget? target) async {
    if (target == null || _shouldStartRepoTargetForSend(target)) {
      return _ensureConnectedForSend();
    }

    final peer = target.pubkey.trim();
    if (_connected && _connectedPeerPubkey == peer) return true;

    if (_connected || _connecting) {
      await _disconnect(expand: false);
    }
    if (!mounted) return false;

    await _connectToTargetInBackground(target);
    if (!mounted || !_connected || _connectedPeerPubkey != peer) return false;
    return _sendPairingSecretIfNeeded(target);
  }

  Future<void> _reconnectAfterBackgroundVoiceSend() async {
    if (!mounted || _sendingAudio || _sending || _sendingMedia) return;
    if (_connected || _connecting) {
      await _disconnect(expand: false);
    }
    if (!mounted) return;
    setState(() => _status = 'Connecting to selected session...');
    await _connect();
  }

  Future<bool> _ensureConnectedForSend() async {
    final target = _targetById(_repoTargets, _selectedRepoTargetId);
    if (_shouldStartRepoTargetForSend(target)) {
      final startedSession = await _startSelectedRepoTargetForSend(target!);
      if (startedSession != null) return startedSession;
      return false;
    }

    if (_connected) {
      return _sendPairingSecretIfNeeded(target);
    }
    if (_connecting) {
      setState(() => _status = 'Waiting for connection...');
      for (var attempt = 0; attempt < 75; attempt += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!mounted) return false;
        if (_connected) return _sendPairingSecretIfNeeded(target);
        if (!_connecting) break;
      }
      return mounted && _connected && await _sendPairingSecretIfNeeded(target);
    }

    setState(() => _status = 'Connecting before send...');
    await _connect();
    return mounted && _connected && await _sendPairingSecretIfNeeded(target);
  }

  Future<bool> _ensureConnectedToParentService() async {
    final parent = await _parentServiceTargetForSpawn();
    if (parent == null) {
      _showError('Set a master session first');
      return false;
    }

    if (_connected) {
      if (_connectedPeerPubkey == parent.pubkey) return true;
      await _disconnect(expand: false);
    }

    if (_connecting) {
      setState(() => _status = 'Waiting for parent connection...');
      for (var attempt = 0; attempt < 75; attempt += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!mounted) return false;
        if (!_connecting) break;
      }
      if (_connected) {
        if (_connectedPeerPubkey == parent.pubkey) return true;
        await _disconnect(expand: false);
      }
    }

    await _connectToTargetInBackground(parent);
    return mounted && _connected && _connectedPeerPubkey == parent.pubkey;
  }

  Future<RepoTarget?> _parentServiceTargetForSpawn() async {
    final master = _masterRepoTarget();
    if (master != null) return master;

    final selected = _targetById(_repoTargets, _selectedRepoTargetId);
    if (selected != null) {
      if (_canBecomeMasterSession(selected)) {
        return _setMasterRepoTarget(selected, announce: false);
      }
      return _parentRepoTargetFor(selected);
    }

    return null;
  }

  RepoTarget? _masterRepoTarget() {
    for (final target in _repoTargets) {
      if (target.isMasterSession) return target;
    }
    return null;
  }

  bool _canBecomeMasterSession(RepoTarget target) {
    final parentPubkey = target.parentPubkey?.trim();
    return parentPubkey == null || parentPubkey.isEmpty;
  }

  Future<RepoTarget> _setMasterRepoTarget(
    RepoTarget target, {
    bool announce = true,
  }) async {
    final targets = [..._repoTargets];
    final index = targets.indexWhere((item) => item.id == target.id);
    final savedTarget = (index >= 0 ? targets[index] : target).copyWith(
      isMasterSession: true,
    );

    for (var i = 0; i < targets.length; i += 1) {
      targets[i] = targets[i].copyWith(
        isMasterSession: targets[i].id == savedTarget.id,
      );
    }
    if (index < 0) {
      targets.add(savedTarget);
    }

    setState(() {
      _repoTargets = targets;
      if (_selectedRepoTargetId == savedTarget.id) {
        _applyRepoTargetFields(savedTarget);
      }
      if (announce) {
        _status = 'Master session set: ${savedTarget.displayName}';
      }
    });
    await _saveSettings();
    return savedTarget;
  }

  bool _shouldStartRepoTargetForSend(RepoTarget? target) {
    return false;
  }

  Future<bool?> _startSelectedRepoTargetForSend(RepoTarget target) async {
    final workdir = target.workdir?.trim();
    if (workdir == null || workdir.isEmpty) return null;

    final parent = _parentRepoTargetFor(target);
    if (parent == null) {
      _showError(
        'Could not start ${target.displayName}: parent phone session is not saved',
      );
      return null;
    }

    final completer = Completer<RepoTarget>();
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

      if (!await _sendSpawnSessionRequest(
        path: workdir,
        create: false,
        sendingStatus: 'Starting ${target.displayName}...',
        sentStatus: 'Waiting for ${target.displayName}...',
        silent: true,
      )) {
        return false;
      }
      if (!mounted) return false;

      RepoTarget targetToConnect;
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

  Future<bool> _connectToRepoTargetForSend(RepoTarget target) async {
    if (!mounted) return false;

    final peer = target.pubkey.trim();
    if (_connected && _connectedPeerPubkey == peer) {
      setState(() => _applyRepoTargetFields(target));
      return _sendPairingSecretIfNeeded(target);
    }

    if (_connected || _connecting) {
      await _disconnect(expand: false);
    }
    if (!mounted) return false;

    setState(() {
      _applyRepoTargetFields(target);
      _status = 'Connecting to ${target.displayName}...';
    });
    await _connectToTargetInBackground(target);
    if (!mounted || !_connected || _connectedPeerPubkey != target.pubkey) {
      return false;
    }
    return _sendPairingSecretIfNeeded(target);
  }

  Future<bool> _sendPairingSecretIfNeeded(RepoTarget? target) async {
    final secret = target?.pairingSecret?.trim();
    if (target == null || secret == null || secret.isEmpty) return true;
    if (!_connected || _connectedPeerPubkey != target.pubkey) return false;

    try {
      setState(() => _status = 'Pairing ${target.displayName}...');
      await _sendWithAutoRecovery(
        label: 'pairing request',
        sender: () => nostrSendQuery(
          query: jsonEncode(_withActiveRoute({'pairing_secret': secret})),
        ),
      );
      _clearPairingSecret(target.id);
      if (mounted) setState(() => _status = 'Paired ${target.displayName}');
      await _saveSettings();
      return true;
    } catch (error) {
      _showError('Pairing failed: $error');
      return false;
    }
  }

  void _clearPairingSecret(String targetId) {
    final targets = [..._repoTargets];
    final index = targets.indexWhere((target) => target.id == targetId);
    if (index < 0) return;
    final target = targets[index];
    targets[index] = target.copyWith(clearPairingSecret: true);
    _repoTargets = targets;
  }

  RepoTarget? _parentRepoTargetFor(RepoTarget target) {
    final parentPubkey = target.parentPubkey?.trim();
    final parentRelays = target.parentRelays;
    if (parentPubkey != null &&
        parentPubkey.isNotEmpty &&
        parentRelays != null &&
        parentRelays.isNotEmpty) {
      return RepoTarget(
        id: 'parent-${target.id}',
        name: target.parentName?.trim().isNotEmpty == true
            ? target.parentName!.trim()
            : 'phone',
        pubkey: parentPubkey,
        relays: parentRelays,
        workdir: target.parentWorkdir,
        isMasterSession: true,
      );
    }

    return _masterRepoTarget();
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
      _pulseMenuNotification();
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
    if (targetKey == null) return false;
    final isActiveConversation = targetKey == _activeConversationKey;
    if (!isActiveConversation && message.kind == 'status') return false;

    if (message.kind == 'transcript' &&
        _tryCompleteTranscription(targetKey, message.text, message.eventId)) {
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
    if (fromCatchUp &&
        completesPendingRequest &&
        !_hasIncomingProcessingPlaceholder(targetKey)) {
      return false;
    }
    setState(() {
      if (message.kind == 'response') {
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
        if (completesPendingRequest) {
          _promoteOldestQueuedTranscription(targetKey);
        }
        if (isActiveConversation &&
            !fromCatchUp &&
            message.kind == 'transcript') {
          _appendIncomingProcessingPlaceholder(targetKey, message.eventId);
        }
        if (!isActiveConversation) {
          _unreadCountsByTarget[targetKey] =
              (_unreadCountsByTarget[targetKey] ?? 0) + 1;
          _pulseMenuNotification();
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

  String? _conversationKeyForIncoming(BridgeIncomingMessage message) {
    final routedKey = conversationKeyForIncomingRoute(
      targets: _repoTargets,
      senderPubkey: message.senderPubkey,
      senderPubkeyHex: message.senderPubkeyHex,
      rawJson: message.rawJson,
      fallbackKey: message.senderPubkey.isNotEmpty
          ? message.senderPubkey
          : 'default',
    );
    return routedKey;
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

  void _cacheRepoChoices(List<RepoChoice> choices) {
    final byRelativePath = <String, RepoChoice>{};
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
        sender: () => nostrSendQuery(query: _buildQueryPayload(query)),
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

  Future<void> _cancelPendingResponse(ConversationMessage message) async {
    if (message.kind != 'processing' ||
        message.direction != MessageDirection.incoming) {
      return;
    }
    final eventId = message.eventId.trim();
    if (eventId.isEmpty) return;

    final conversationKey = _activeConversationKey;
    if (!_replaceIncomingProcessingPlaceholder(
      conversationKey,
      eventId,
      ConversationMessage(
        direction: MessageDirection.incoming,
        kind: 'cancelled',
        text: 'Cancelled',
        eventId: eventId,
        timestamp: DateTime.now(),
      ),
    )) {
      return;
    }
    if (mounted) {
      setState(() => _status = 'Cancelling task...');
    }

    try {
      if (!await _ensureConnectedForSend()) {
        throw StateError('Not connected');
      }
      final payload = jsonEncode({
        'cancel_request': {'event_id': eventId},
      });
      await _sendWithAutoRecovery(
        label: 'cancel request',
        sender: () => nostrSendQuery(query: payload),
      );
      if (!mounted) return;
      setState(() => _status = 'Cancel requested');
    } catch (error) {
      if (mounted) {
        setState(() {
          _replaceIncomingProcessingPlaceholder(
            conversationKey,
            eventId,
            ConversationMessage(
              direction: MessageDirection.incoming,
              kind: 'processing',
              text: '',
              eventId: eventId,
              timestamp: message.timestamp,
            ),
          );
        });
      }
      _showError('Cancel failed: $error');
    }
  }

  Future<void> _requestSpawnSession() async {
    if (!await _ensureConnectedToParentService()) {
      _showError('Connect to the parent service first');
      return;
    }
    if (!mounted) return;
    final request = await showDialog<_SpawnSessionRequest>(
      context: context,
      builder: (context) => _SpawnSessionDialog(
        initialRepoChoices: _cachedRepoChoices,
        onLoadRepos: _requestRepoChoices,
      ),
    );
    if (request == null || !mounted) return;

    final path = '/home/tom/code/${request.path}';
    await _spawnAndOpenSession(
      path: path,
      create: request.create,
      sendingStatus: request.create
          ? 'Requesting new project session...'
          : 'Requesting session spawn...',
      waitingStatus: request.create
          ? 'Waiting for new project session...'
          : 'Waiting for spawned session...',
      timeoutMessage: 'Session invite timed out',
    );
  }

  Future<void> _restartRepoTarget(RepoTarget target) async {
    final workdir = target.workdir?.trim();
    if (workdir == null || workdir.isEmpty) {
      _showError('This session does not have a saved folder path');
      return;
    }
    if (!await _ensureConnectedToParentService()) {
      _showError('Connect to the parent service first');
      return;
    }
    if (target.id == _selectedRepoTargetId) {
      _showError('Select the parent service first, then restart this session');
      return;
    }
    await _spawnAndOpenSession(
      path: workdir,
      create: false,
      sendingStatus: 'Requesting session restart...',
      waitingStatus: 'Waiting for restarted session...',
      timeoutMessage: 'Session restart timed out',
    );
  }

  Future<bool> _spawnAndOpenSession({
    required String path,
    required bool create,
    required String sendingStatus,
    required String waitingStatus,
    required String timeoutMessage,
  }) async {
    if (_pendingSessionStart != null) {
      _showError('A session is already starting');
      return false;
    }

    final completer = Completer<RepoTarget>();
    _pendingSessionStart = _PendingSessionStart(
      workdir: path,
      completer: completer,
    );

    try {
      if (!await _sendSpawnSessionRequest(
        path: path,
        create: create,
        sendingStatus: sendingStatus,
        sentStatus: waitingStatus,
        silent: true,
      )) {
        return false;
      }

      final target = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException(timeoutMessage),
      );
      if (!mounted) return false;
      return _connectToRepoTargetForSend(target);
    } on TimeoutException catch (error) {
      if (mounted) setState(() => _status = error.message ?? timeoutMessage);
      return false;
    } catch (error) {
      _showError('Could not open session: $error');
      return false;
    } finally {
      if (identical(_pendingSessionStart?.completer, completer)) {
        _pendingSessionStart = null;
      }
    }
  }

  Future<bool> _sendSpawnSessionRequest({
    required String path,
    required bool create,
    required String sendingStatus,
    required String sentStatus,
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
      await _sendWithAutoRecovery(
        label: 'spawn session request',
        sender: () => nostrSendQuery(query: payload),
      );
      if (!mounted) return false;
      setState(() => _status = sentStatus);
      return true;
    } catch (error) {
      _showError('Session request failed: $error');
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendingConversationKey = null;
        });
      }
    }
  }

  Future<List<RepoChoice>> _requestRepoChoices() async {
    if (!await _ensureConnectedToParentService()) {
      throw StateError('Connect to the parent service first');
    }
    final existing = _pendingRepoListCompleter;
    if (existing != null && !existing.isCompleted) {
      existing.completeError(StateError('Repo list request replaced'));
    }
    final completer = Completer<List<RepoChoice>>();
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
      if (error is MediaUploadCancelledException) {
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

  Future<MediaSelection?> _pickMediaAttachment() async {
    final source = await _chooseMediaSource();
    if (source == null) return null;

    try {
      if (source == MediaSource.filePicker) {
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
        return MediaSelection(
          path: path,
          fileName: _normalizeName(file.name, path),
          extension: file.extension,
          contentType: _inferContentType(file.name, file.extension),
        );
      }

      final picker = ImagePicker();
      final image = await (source == MediaSource.camera
          ? picker.pickImage(source: ImageSource.camera)
          : picker.pickImage(source: ImageSource.gallery));
      if (image == null) return null;

      final imagePath = image.path;
      return MediaSelection(
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

  Future<MediaSource?> _chooseMediaSource() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return MediaSource.filePicker;
    }

    final source = await showModalBottomSheet<MediaSource>(
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
                onTap: () => Navigator.of(context).pop(MediaSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose photo'),
                onTap: () => Navigator.of(context).pop(MediaSource.photoPicker),
              ),
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: const Text('Choose file'),
                onTap: () => Navigator.of(context).pop(MediaSource.filePicker),
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
      if (!await _ensureConnectedForSend()) {
        return;
      }
      final eventId = await _sendWithAutoRecovery(
        label: 'resend query',
        sender: () => nostrSendQuery(query: _buildQueryPayload(query)),
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
      if (!await _ensureConnectedForSend()) {
        return;
      }
      final eventId = await _sendWithAutoRecovery(
        label: 'resend voice note',
        sender: () => nostrSendQuery(
          query: _buildMediaBundlePayload(attachment: audio, caption: ''),
        ),
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

    if (_sendingInActiveConversation || _sendingAudioInActiveConversation) {
      return;
    }
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
          ? wavVoiceFormat
          : opusVoiceFormat;
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
        _status = recordingFormat.format == VoiceFormat.wav
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
    final sendTarget = _targetById(_repoTargets, _selectedRepoTargetId);
    final fallbackPath = _recordingPath;
    final recordingFormat = _activeRecordingFormat ?? opusVoiceFormat;
    final recordingStartedAt = _recordingStartedAt;
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
    final recordingDuration = recordingStartedAt == null
        ? null
        : DateTime.now().difference(recordingStartedAt);
    if (recordingDuration != null &&
        recordingDuration < minimumVoiceRecordingDuration) {
      setState(() {
        _recording = false;
        _recordingPath = null;
        _activeRecordingFormat = null;
        _recordingStartedAt = null;
        _stopRecordingTimer();
        _status = 'Recording too short';
      });
      if (path != null) unawaited(_deleteTempAudio(path));
      return;
    }

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
      if (!await _ensureConnectedForVoiceSend(sendTarget)) {
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
        sender: () => nostrSendQuery(
          query: _buildMediaBundlePayload(attachment: audio, caption: ''),
        ),
      );
      if (!mounted) return;
      setState(() {
        if (recordingFormat.format == VoiceFormat.wav) {
          _wavRetryRequested = false;
        }
        _appendPendingTranscriptionMessage(
          conversationKey: conversationKey,
          eventId: eventId,
          label: 'Transcribing...',
        );
        _status = 'Voice query sent';
      });
    } catch (error) {
      _showError('Voice query failed: $error');
    } finally {
      unawaited(_deleteTempAudio(path));
      final reconnectToSelected =
          mounted && _activeConversationKey != conversationKey;
      if (mounted) {
        setState(() {
          _sendingAudio = false;
          _sendingAudioConversationKey = null;
        });
      }
      if (reconnectToSelected) {
        unawaited(_reconnectAfterBackgroundVoiceSend());
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
        throw MediaUploadCancelledException(
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

        final cancelMessage = MediaUploadCancelledException(
          server: server,
          sessionId: mediaUploadSessionId,
        );
        return await Future.any([
          uploadFuture,
          cancelCompleter.future.then((_) => throw cancelMessage),
        ]);
      } catch (error) {
        if (error is MediaUploadCancelledException) {
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
    final payload = _withActiveRoute({'media_bundle': mediaBundle});
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(payload);
  }

  Map<String, dynamic> _withActiveRoute(Map<String, dynamic> payload) {
    final workdir = _targetById(
      _repoTargets,
      _selectedRepoTargetId,
    )?.workdir?.trim();
    if (workdir == null || workdir.isEmpty) return payload;
    return {'workdir': workdir, ...payload};
  }

  String _buildQueryPayload(String query) {
    return jsonEncode(_withActiveRoute({'message': query}));
  }

  List<String> _selectedBlossomServers() {
    final selected = _blossomServerController.text.trim();
    if (_isAutoBlossom(selected)) {
      return autoBlossomUploadServers;
    }
    return [selected];
  }

  bool _isAutoBlossom(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == autoBlossomServer ||
        normalized == 'auto-select';
  }

  String _serverLabel(String server) {
    for (final preset in blossomPresets) {
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

  List<RepoTarget> _activeSessionTargets() {
    return _repoTargets.where((target) {
      return target.id == _selectedRepoTargetId ||
          (_messagesByTarget[target.id]?.isNotEmpty ?? false) ||
          (_unreadCountsByTarget[target.id] ?? 0) > 0 ||
          _pendingReplyTargetIds.contains(target.id);
    }).toList();
  }

  Widget _buildSessionTitle(List<RepoTarget> activeTargets) {
    final selected = _targetById(_repoTargets, _selectedRepoTargetId);
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
    );
    if (activeTargets.length < 2 || selected == null) {
      return selected == null
          ? Text(
              _activeTargetName(),
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            )
          : _buildSessionDropdownLabel(selected, titleStyle, compact: true);
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selected.id,
        isExpanded: true,
        iconEnabledColor: Theme.of(context).colorScheme.onSurface,
        style: titleStyle,
        selectedItemBuilder: (context) => [
          for (final target in activeTargets)
            _buildSessionDropdownLabel(target, titleStyle, compact: true),
        ],
        items: [
          for (final target in activeTargets)
            DropdownMenuItem<String>(
              value: target.id,
              child: _buildSessionDropdownLabel(target, titleStyle),
            ),
        ],
        onChanged: _sessionSwitchBlocked
            ? null
            : (targetId) {
                if (targetId != null) {
                  unawaited(_selectRepoTarget(targetId));
                }
              },
      ),
    );
  }

  Widget _buildSessionDropdownLabel(
    RepoTarget target,
    TextStyle? titleStyle, {
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final activeColor = dark
        ? const Color(0xff81c784)
        : const Color(0xff2e7d32);
    final loadedColor = dark
        ? const Color(0xff90caf9)
        : const Color(0xff1565c0);
    final selected = target.id == _selectedRepoTargetId;
    final connected = _connectedPeerPubkey == target.pubkey;
    final loaded = _messagesByTarget.containsKey(target.id);
    final pending = _pendingReplyTargetIds.contains(target.id);
    final hasUnread = (_unreadCountsByTarget[target.id] ?? 0) > 0;
    final statusColor = selected
        ? activeColor
        : connected || loaded
        ? loadedColor
        : theme.colorScheme.onSurfaceVariant;
    final textStyle = titleStyle?.copyWith(
      color: compact ? titleStyle.color : statusColor,
      fontWeight: selected || connected ? FontWeight.w700 : FontWeight.w500,
    );

    return Row(
      children: [
        if (pending && !compact)
          SizedBox(
            width: 32,
            child: Center(
              child: _workingAnimationStyle.enabled
                  ? DigitalThinkingIndicator(
                      width: 28,
                      height: 16,
                      color: statusColor,
                      style: _workingAnimationStyle,
                      speed: _workingAnimationSpeed,
                    )
                  : Icon(
                      Icons.chat_bubble_outline,
                      color: statusColor,
                      size: 20,
                    ),
            ),
          ),
        Expanded(
          child: Text(
            target.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
        if (hasUnread) ...[
          SizedBox(width: compact ? 6 : 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xffff9f1c),
              shape: BoxShape.circle,
              border: Border.all(color: theme.colorScheme.surface, width: 1),
            ),
            child: SizedBox.square(dimension: compact ? 7 : 8),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSettings) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final hasUnreadConversations = _unreadCountsByTarget.values.any(
      (count) => count > 0,
    );
    final hasMenuNotification =
        hasUnreadConversations || _pendingTargetInvites.isNotEmpty;
    final activeTargets = _activeSessionTargets();

    return Scaffold(
      drawerEnableOpenDragGesture: false,
      appBar: AppBar(
        leading: Builder(
          builder: (context) {
            return IconButton(
              tooltip: hasMenuNotification
                  ? 'Open sessions with notifications'
                  : 'Open sessions',
              icon: SizedBox.square(
                dimension: 28,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Center(child: Icon(Icons.menu)),
                    if (hasMenuNotification)
                      Positioned(
                        top: 4,
                        right: 3,
                        child: AnimatedBuilder(
                          animation: _menuNotificationPulseController,
                          builder: (context, child) {
                            final value =
                                _menuNotificationPulseController.value;
                            final scale = 1 + (math.sin(value * math.pi) * 0.7);
                            return Transform.scale(scale: scale, child: child);
                          },
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xffff9f1c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.surface,
                                width: 1.5,
                              ),
                            ),
                            child: const SizedBox.square(dimension: 8),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              onPressed: () => unawaited(_openSessionsMenu(context)),
            );
          },
        ),
        title: _buildSessionTitle(activeTargets),
      ),
      drawer: _SessionDrawer(
        targets: _repoTargets,
        selectedTargetId: _selectedRepoTargetId,
        connectedTargetId: _connected ? _selectedRepoTargetId : null,
        canSelectTargets: !_sessionSwitchBlocked,
        unreadCountsByTarget: _unreadCountsByTarget,
        pendingReplyTargetIds: _pendingReplyTargetIds,
        loadedTargetIds: _messagesByTarget.keys.toSet(),
        workingAnimationStyle: _workingAnimationStyle,
        workingAnimationSpeed: _workingAnimationSpeed,
        onSelectTarget: (targetId) => unawaited(_selectRepoTarget(targetId)),
        onNewTarget: () => unawaited(_createRepoTarget()),
        onSpawnSession: () => unawaited(_requestSpawnSession()),
        onRestartTarget: (target) => unawaited(_restartRepoTarget(target)),
        onSetMasterTarget: (target) => unawaited(_setMasterRepoTarget(target)),
        onRenameTarget: (target) => unawaited(_renameRepoTarget(target)),
        onOpenSettings: () => unawaited(_openSettings()),
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
                  : ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(overscroll: false),
                      child: ListView.builder(
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
                              workingAnimationSpeed: _workingAnimationSpeed,
                              stopSpeakingOnTap:
                                  _speaking &&
                                  message.direction ==
                                      MessageDirection.incoming,
                              onSpeak: () => unawaited(
                                _speak(
                                  message.text,
                                  remember: true,
                                  manual: true,
                                  messageEventId: message.eventId,
                                ),
                              ),
                              onStopSpeaking: _stopSpeaking,
                              onResend: _canResendMessage(message)
                                  ? () => _resendMessage(message)
                                  : null,
                              onCancelPending:
                                  message.kind == 'processing' &&
                                      message.direction ==
                                          MessageDirection.incoming
                                  ? () => unawaited(
                                      _cancelPendingResponse(message),
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
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
              activeSendBlocked: _activeConversationSendBlocked,
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
