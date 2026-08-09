part of '../main.dart';

class _SessionDrawer extends StatelessWidget {
  const _SessionDrawer({
    required this.targets,
    required this.recentTargetIds,
    required this.selectedTargetId,
    required this.connectedTargetId,
    required this.canSelectTargets,
    required this.unreadCountsByTarget,
    required this.pendingReplyTargetIds,
    required this.loadedTargetIds,
    required this.workingAnimationStyle,
    required this.workingAnimationSpeed,
    required this.onSelectTarget,
    required this.onSpawnSession,
    required this.onCatchUpTarget,
    required this.onRestartTarget,
    required this.onRenameTarget,
    required this.onTogglePinTarget,
    required this.onOpenWorkers,
    required this.onOpenSettings,
    required this.onDeleteTarget,
  });

  final List<RepoTarget> targets;
  final List<String> recentTargetIds;
  final String? selectedTargetId;
  final String? connectedTargetId;
  final bool canSelectTargets;
  final Map<String, int> unreadCountsByTarget;
  final Set<String> pendingReplyTargetIds;
  final Set<String> loadedTargetIds;
  final WorkingAnimationStyle workingAnimationStyle;
  final double workingAnimationSpeed;
  final ValueChanged<String> onSelectTarget;
  final VoidCallback onSpawnSession;
  final ValueChanged<RepoTarget> onCatchUpTarget;
  final ValueChanged<RepoTarget> onRestartTarget;
  final ValueChanged<RepoTarget> onRenameTarget;
  final ValueChanged<RepoTarget> onTogglePinTarget;
  final VoidCallback onOpenWorkers;
  final VoidCallback onOpenSettings;
  final ValueChanged<String> onDeleteTarget;

  @override
  Widget build(BuildContext context) {
    final recentRank = {
      for (var i = 0; i < recentTargetIds.length; i++) recentTargetIds[i]: i,
    };
    final sortedTargets = [...targets]
      ..sort((left, right) {
        if (left.isMasterSession != right.isMasterSession) {
          return left.isMasterSession ? -1 : 1;
        }
        final recent = (recentRank[left.id] ?? 9999).compareTo(
          recentRank[right.id] ?? 9999,
        );
        if (recent != 0) return recent;
        return left.displayName.toLowerCase().compareTo(
          right.displayName.toLowerCase(),
        );
      });
    var sessionSearchQuery = '';

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
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Spawn on computer'),
              onTap: () {
                Navigator.of(context).pop();
                onSpawnSession();
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: StatefulBuilder(
                builder: (context, refreshSessions) {
                  final query = sessionSearchQuery.trim().toLowerCase();
                  final visibleTargets = query.isEmpty
                      ? sortedTargets
                      : sortedTargets.where((target) {
                          return target.displayName.toLowerCase().contains(
                                query,
                              ) ||
                              (target.workdir ?? '').toLowerCase().contains(
                                query,
                              ) ||
                              target.pubkey.toLowerCase().contains(query);
                        }).toList();
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            labelText: 'Search sessions',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (value) =>
                              refreshSessions(() => sessionSearchQuery = value),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(top: 4),
                          children: [
                            if (visibleTargets.isEmpty)
                              const ListTile(
                                leading: Icon(Icons.search_off),
                                title: Text('No matching sessions'),
                              ),
                            for (final target in visibleTargets)
                              Builder(
                                builder: (context) {
                                  final theme = Theme.of(context);
                                  final dark =
                                      theme.brightness == Brightness.dark;
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
                                  final selected =
                                      target.id == selectedTargetId;
                                  final connected =
                                      target.id == connectedTargetId;
                                  final loaded = loadedTargetIds.contains(
                                    target.id,
                                  );
                                  final pending = pendingReplyTargetIds
                                      .contains(target.id);
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
                                  final menu =
                                      PopupMenuButton<_SessionDrawerAction>(
                                        onSelected: (action) async {
                                          if (action ==
                                              _SessionDrawerAction.catchUp) {
                                            onCatchUpTarget(target);
                                          } else if (action ==
                                              _SessionDrawerAction.restart) {
                                            onRestartTarget(target);
                                          } else if (action ==
                                              _SessionDrawerAction.pin) {
                                            onTogglePinTarget(target);
                                          } else if (action ==
                                              _SessionDrawerAction.rename) {
                                            onRenameTarget(target);
                                          } else if (action ==
                                              _SessionDrawerAction.delete) {
                                            final shouldDelete =
                                                await _confirmDelete(
                                                  context,
                                                  target,
                                                );
                                            if (shouldDelete &&
                                                context.mounted) {
                                              onDeleteTarget(target.id);
                                            }
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem(
                                            value: _SessionDrawerAction.pin,
                                            child: ListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              leading: Icon(
                                                target.isMasterSession
                                                    ? Icons.push_pin
                                                    : Icons.push_pin_outlined,
                                              ),
                                              title: Text(
                                                target.isMasterSession
                                                    ? 'Unpin'
                                                    : 'Pin',
                                              ),
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: _SessionDrawerAction.catchUp,
                                            child: const ListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              leading: Icon(Icons.sync),
                                              title: Text('Catch up'),
                                            ),
                                          ),
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
                                              leading: Icon(
                                                Icons.delete_outline,
                                              ),
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
                                                  child:
                                                      workingAnimationStyle
                                                          .enabled
                                                      ? DigitalThinkingIndicator(
                                                          width: 28,
                                                          height: 16,
                                                          color:
                                                              statusColor ??
                                                              loadedColor,
                                                          style:
                                                              workingAnimationStyle,
                                                          speed:
                                                              workingAnimationSpeed,
                                                        )
                                                      : Icon(
                                                          connected
                                                              ? Icons
                                                                    .cloud_done_outlined
                                                              : Icons
                                                                    .chat_bubble_outline,
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
                                    title: Row(
                                      children: [
                                        if (target.isMasterSession) ...[
                                          const Tooltip(
                                            message: 'Pinned session',
                                            child: Icon(
                                              Icons.push_pin,
                                              size: 16,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Expanded(
                                          child: Text(
                                            target.displayName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: statusColor == null
                                                ? null
                                                : TextStyle(
                                                    color: statusColor,
                                                    fontWeight:
                                                        selected || connected
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                  ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      target.workdir?.trim().isNotEmpty == true
                                          ? target.workdir!
                                          : compactIdentifier(target.pubkey),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: unreadCount > 0
                                        ? Badge(
                                            label: Text('$unreadCount'),
                                            child: menu,
                                          )
                                        : menu,
                                    onTap: canSelectTargets
                                        ? () {
                                            Navigator.of(context).pop();
                                            onSelectTarget(target.id);
                                          }
                                        : null,
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.computer_outlined),
                    title: const Text('Workers'),
                    subtitle: const Text('Add and manage computers'),
                    onTap: () {
                      Navigator.of(context).pop();
                      onOpenWorkers();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings),
                    title: const Text('Settings'),
                    onTap: () {
                      Navigator.of(context).pop();
                      onOpenSettings();
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

  Future<bool> _confirmDelete(BuildContext context, RepoTarget target) async {
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

enum _SessionDrawerAction { pin, catchUp, restart, rename, delete }

class _WorkersPage extends StatelessWidget {
  const _WorkersPage({
    required this.workers,
    required this.selectedWorkerId,
    required this.onAddWorker,
    required this.onSelectWorker,
    required this.onTestWorker,
    required this.onDeleteWorker,
  });

  final List<RepoTarget> workers;
  final String? selectedWorkerId;
  final Future<void> Function() onAddWorker;
  final ValueChanged<RepoTarget> onSelectWorker;
  final ValueChanged<RepoTarget> onTestWorker;
  final ValueChanged<RepoTarget> onDeleteWorker;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workers')),
      floatingActionButton: _supportsCameraQrScan
          ? FloatingActionButton.extended(
              onPressed: () => unawaited(onAddWorker()),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan worker'),
            )
          : null,
      body: workers.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _supportsCameraQrScan
                      ? 'Scan the QR shown by each Linux or Mac worker. Each worker keeps its own sessions and identity.'
                      : 'Add a worker by pasting its target details in Settings. Each worker keeps its own sessions and identity.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: workers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final worker = workers[index];
                final selected = worker.id == selectedWorkerId;
                return Card(
                  color: selected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  child: ListTile(
                    leading: Icon(
                      selected ? Icons.computer : Icons.computer_outlined,
                    ),
                    title: Text(worker.displayName),
                    subtitle: Text(
                      '${compactIdentifier(worker.pubkey)}\n${worker.relays.length} relay${worker.relays.length == 1 ? '' : 's'}',
                    ),
                    isThreeLine: true,
                    onTap: () => onSelectWorker(worker),
                    trailing: PopupMenuButton<_WorkerAction>(
                      onSelected: (action) async {
                        if (action == _WorkerAction.test) {
                          onTestWorker(worker);
                        } else if (action == _WorkerAction.remove &&
                            await _confirmDelete(context, worker)) {
                          onDeleteWorker(worker);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: _WorkerAction.test,
                          child: Text('Test connection'),
                        ),
                        PopupMenuItem(
                          value: _WorkerAction.remove,
                          child: Text('Remove worker'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, RepoTarget worker) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove worker?'),
            content: Text(
              'Remove ${worker.displayName}? Its sessions stay saved.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

enum _WorkerAction { test, remove }

enum _WorkspaceSection { channel, direct, people, access, agents }

class _WorkspaceDraft {
  _WorkspaceDraft(this.value, List<WorkspaceMention> mentions)
    : mentions = List.unmodifiable(mentions);

  final TextEditingValue value;
  final List<WorkspaceMention> mentions;
}

class _WorkspacePanelState {
  const _WorkspacePanelState({
    required this.threadId,
    required this.width,
    required this.alsoSendToMain,
    required this.filesSelected,
    this.fileBrowser,
    this.filePreview,
  });

  final String? threadId;
  final double width;
  final bool alsoSendToMain;
  final bool filesSelected;
  final FileBrowserResult? fileBrowser;
  final FileContentResult? filePreview;
}

class _TeamWorkspace extends StatefulWidget {
  const _TeamWorkspace({
    super.key,
    required this.sessions,
    required this.spaces,
    required this.activeSpace,
    required this.onSwitchSpace,
    required this.onOpenSessions,
    required this.onOpenSettings,
    required this.diagnostics,
    required this.onOpenDiagnostics,
    required this.onOpenWorkerConsole,
    required this.onOpenFiles,
    required this.fileBrowser,
    required this.filePreview,
    required this.onBrowseFiles,
    required this.onReadWorkspaceFile,
    required this.workspaceRevision,
    required this.onLoadOpenCodeModels,
    required this.initialFolderChoices,
    required this.onLoadFolders,
    required this.onOpenAgentConversation,
    required this.inviteCode,
    required this.memberStatus,
    required this.workspace,
    required this.ownPubkey,
    required this.localSenderIds,
    required this.displayName,
    required this.memberAliases,
    required this.memberNames,
    required this.unreadCounts,
    required this.threadUnreadCounts,
    required this.onDisplayNameChanged,
    required this.onMemberAliasChanged,
    required this.onFocusConversation,
    required this.onOpenThread,
    required this.onCloseThread,
    required this.onRequest,
    required this.onLoadFolderChoices,
    required this.onTyping,
    required this.onAttach,
    required this.voiceResult,
    required this.onVoiceTranscribe,
    required this.onOpenAttachment,
    required this.onCreateInvite,
    required this.callPhase,
    required this.callPeerPubkey,
    required this.groupCallPhase,
    required this.groupCallChannelId,
    required this.onStartCall,
    required this.onStartChannelCall,
    required this.onAcceptCall,
    required this.onRejectCall,
    required this.onHangupCall,
    required this.onAcceptGroupCall,
    required this.onRejectGroupCall,
    required this.onHangupGroupCall,
    required this.mediaSource,
    required this.onMediaSourceChanged,
  });

  final List<RepoTarget> sessions;
  final List<RepoTarget> spaces;
  final RepoTarget? activeSpace;
  final ValueChanged<RepoTarget> onSwitchSpace;
  final VoidCallback onOpenSessions;
  final VoidCallback onOpenSettings;
  final ValueNotifier<List<String>> diagnostics;
  final VoidCallback onOpenDiagnostics;
  final VoidCallback onOpenWorkerConsole;
  final Future<void> Function(String conversationKey) onOpenFiles;
  final ValueNotifier<FileBrowserResult?> fileBrowser;
  final ValueNotifier<FileContentResult?> filePreview;
  final Future<void> Function(
    String conversationKey,
    String directory,
    String path,
  )
  onBrowseFiles;
  final Future<void> Function(
    String conversationKey,
    String directory,
    String path,
  )
  onReadWorkspaceFile;
  final ValueListenable<int> workspaceRevision;
  final Future<List<_OpenCodeModelChoice>> Function() onLoadOpenCodeModels;
  final List<RepoChoice> initialFolderChoices;
  final Future<List<RepoChoice>> Function(String? path) onLoadFolders;
  final Future<void> Function(WorkspaceAgent agent) onOpenAgentConversation;
  final String? inviteCode;
  final String memberStatus;
  final WorkspaceState workspace;
  final String ownPubkey;
  final Set<String> localSenderIds;
  final String displayName;
  final Map<String, String> memberAliases;
  final Map<String, String> memberNames;
  final Map<String, int> unreadCounts;
  final Map<String, int> threadUnreadCounts;
  final ValueChanged<String> onDisplayNameChanged;
  final void Function(String pubkey, String alias) onMemberAliasChanged;
  final ValueChanged<String> onFocusConversation;
  final void Function(String conversationKey, String parentId) onOpenThread;
  final VoidCallback onCloseThread;
  final Future<void> Function(Map<String, Object?> request) onRequest;
  final Future<List<RepoChoice>> Function() onLoadFolderChoices;
  final Future<void> Function(Map<String, Object?> request) onTyping;
  final Future<bool> Function(Map<String, Object?> request) onAttach;
  final ValueNotifier<_WorkspaceVoiceResult?> voiceResult;
  final Future<void> Function(String path, Map<String, Object?> request)
  onVoiceTranscribe;
  final Future<void> Function(BridgeAudioReference attachment) onOpenAttachment;
  final Future<void> Function() onCreateInvite;
  final _CallPhase callPhase;
  final String? callPeerPubkey;
  final _CallPhase groupCallPhase;
  final String? groupCallChannelId;
  final ValueChanged<String> onStartCall;
  final Future<void> Function(String channelId) onStartChannelCall;
  final VoidCallback onAcceptCall;
  final VoidCallback onRejectCall;
  final VoidCallback onHangupCall;
  final VoidCallback onAcceptGroupCall;
  final VoidCallback onRejectGroupCall;
  final VoidCallback onHangupGroupCall;
  final _CallMediaSource mediaSource;
  final ValueChanged<_CallMediaSource> onMediaSourceChanged;

  @override
  State<_TeamWorkspace> createState() => _TeamWorkspaceState();
}

class _TeamWorkspaceState extends State<_TeamWorkspace> {
  static const _sidebarMinWidth = 220.0;
  static const _sidebarMaxWidth = 360.0;
  static const _threadPaneMinWidth = 220.0;
  static const _threadPaneMaxWidth = 1100.0;
  static const _conversationMinWidth = 360.0;
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  final _selectedComposerMentions = <WorkspaceMention>[];
  final _threadComposer = TextEditingController();
  final _threadComposerFocus = FocusNode();
  final _selectedThreadMentions = <WorkspaceMention>[];
  final _conversationDrafts = <String, _WorkspaceDraft>{};
  final _threadDrafts = <String, _WorkspaceDraft>{};
  final _panelStates = <String, _WorkspacePanelState>{};
  final _conversationWidgetKey = GlobalKey<_WorkspaceConversationState>();
  final _voiceRecorder = AudioRecorder();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _voiceRecording = false;
  bool _voiceTranscribing = false;
  String? _voicePath;
  DateTime? _voiceStartedAt;
  TextEditingController? _voiceComposer;
  String? _voiceError;
  Timer? _typingRefreshTimer;
  Timer? _typingExpiryTimer;
  DateTime? _lastTypingLease;
  _WorkspaceSection _section = _WorkspaceSection.channel;
  String _active = 'workspace';
  WorkspaceMessage? _thread;
  bool _alsoSendToMain = false;
  bool _filesSelected = false;
  bool _filesFullWindow = false;
  bool _threadFullWindow = false;
  int _agentsPageRevision = 0;
  double _sidebarWidth = 280;
  double _threadPaneWidth = 340;

  String? get _conversationKey => _conversationKeyFor(_section, _active);

  String? _conversationKeyFor(_WorkspaceSection section, String id) =>
      switch (section) {
        _WorkspaceSection.channel => id,
        _WorkspaceSection.direct => WorkspaceState.directKey(
          widget.ownPubkey,
          id,
        ),
        _ => null,
      };

  String? get _threadDraftKey {
    final conversationKey = _conversationKey;
    final thread = _thread;
    return conversationKey == null || thread == null
        ? null
        : '$conversationKey:${thread.id}';
  }

  void _saveMainDraft() {
    final key = _conversationKey;
    if (key == null) return;
    _conversationDrafts[key] = _WorkspaceDraft(
      _composer.value,
      _selectedComposerMentions,
    );
  }

  void _restoreMainDraft(String? key) {
    final draft = key == null ? null : _conversationDrafts[key];
    _composer.value = draft?.value ?? TextEditingValue.empty;
    _selectedComposerMentions
      ..clear()
      ..addAll(draft?.mentions ?? const []);
  }

  void _saveThreadDraft() {
    final key = _threadDraftKey;
    if (key == null) return;
    _threadDrafts[key] = _WorkspaceDraft(
      _threadComposer.value,
      _selectedThreadMentions,
    );
  }

  void _restoreThreadDraft() {
    final draft = _threadDraftKey == null
        ? null
        : _threadDrafts[_threadDraftKey];
    _threadComposer.value = draft?.value ?? TextEditingValue.empty;
    _selectedThreadMentions
      ..clear()
      ..addAll(draft?.mentions ?? const []);
  }

  WorkspaceMessage? _threadWithId(String? id) {
    if (id == null) return null;
    for (final message in _activeMessages) {
      if (message.id == id) return message;
    }
    return null;
  }

  void _reloadActiveMessages() {
    if (_section == _WorkspaceSection.channel) {
      unawaited(
        widget.onRequest({
          'action': 'list_channel_messages',
          'channel_id': _active,
        }),
      );
    } else if (_section == _WorkspaceSection.direct) {
      unawaited(
        widget.onRequest({
          'action': 'list_direct_messages',
          'recipient_pubkey': _active,
        }),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _composer.addListener(_onComposerChanged);
    _composerFocus.addListener(_onComposerChanged);
    _threadComposer.addListener(_onComposerChanged);
    _threadComposerFocus.addListener(_onComposerChanged);
    widget.voiceResult.addListener(_onVoiceResult);
    widget.fileBrowser.addListener(_onFileBrowserChanged);
    widget.filePreview.addListener(_onFileBrowserChanged);
    unawaited(widget.onRequest({'action': 'list'}));
  }

  @override
  void dispose() {
    _composer.removeListener(_onComposerChanged);
    _composer.dispose();
    _composerFocus.removeListener(_onComposerChanged);
    _composerFocus.dispose();
    _threadComposer.removeListener(_onComposerChanged);
    _threadComposer.dispose();
    _threadComposerFocus.removeListener(_onComposerChanged);
    _threadComposerFocus.dispose();
    widget.voiceResult.removeListener(_onVoiceResult);
    widget.fileBrowser.removeListener(_onFileBrowserChanged);
    widget.filePreview.removeListener(_onFileBrowserChanged);
    unawaited(_voiceRecorder.dispose());
    final path = _voicePath;
    if (path != null) unawaited(_deleteVoiceFile(path));
    _typingRefreshTimer?.cancel();
    _typingExpiryTimer?.cancel();
    super.dispose();
  }

  void _onComposerChanged() {
    setState(() {});
    _syncTypingLease();
  }

  void _onVoiceResult() {
    final result = widget.voiceResult.value;
    if (result == null || !_voiceTranscribing) return;
    final composer = _voiceComposer;
    setState(() {
      _voiceTranscribing = false;
      _voiceError = result.error;
      if (result.transcript != null && composer != null) {
        _insertVoiceTranscript(composer, result.transcript!);
      }
    });
    if (result.transcript != null && composer != null) {
      composer == _threadComposer
          ? _threadComposerFocus.requestFocus()
          : _composerFocus.requestFocus();
    }
  }

  void _onFileBrowserChanged() {
    if (!mounted) return;
    setState(() => _filesSelected = widget.fileBrowser.value != null);
  }

  void _insertVoiceTranscript(
    TextEditingController composer,
    String transcript,
  ) {
    final text = transcript.trim();
    if (text.isEmpty) return;
    final selection = composer.selection;
    final start = selection.isValid ? selection.start : composer.text.length;
    final end = selection.isValid ? selection.end : composer.text.length;
    final insert =
        composer.text.isNotEmpty &&
            start > 0 &&
            !RegExp(r'\s$').hasMatch(composer.text.substring(0, start))
        ? ' $text'
        : text;
    composer.value = composer.value.copyWith(
      text: composer.text.replaceRange(start, end, insert),
      selection: TextSelection.collapsed(offset: start + insert.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _toggleVoiceRecording({WorkspaceMessage? thread}) async {
    if (_voiceTranscribing) return;
    if (_voiceRecording) {
      final path = _voicePath;
      final startedAt = _voiceStartedAt;
      try {
        final stopped = await _voiceRecorder.stop();
        final audioPath = _usableVoiceAudioPath(stopped, path);
        if (audioPath == null ||
            startedAt == null ||
            DateTime.now().difference(startedAt) <
                minimumVoiceRecordingDuration) {
          if (audioPath != null) unawaited(_deleteVoiceFile(audioPath));
          if (mounted) {
            setState(() {
              _voiceRecording = false;
              _voicePath = null;
              _voiceError = 'Record at least one second of audio.';
            });
          }
          return;
        }
        if (!mounted) return;
        setState(() {
          _voiceRecording = false;
          _voiceTranscribing = true;
          _voiceError = null;
          _voicePath = null;
        });
        await widget.onVoiceTranscribe(audioPath, {
          'action': _section == _WorkspaceSection.channel
              ? 'send_channel_message'
              : 'send_direct_message',
          if (_section == _WorkspaceSection.channel) 'channel_id': _active,
          if (_section == _WorkspaceSection.direct) 'recipient_pubkey': _active,
          if (thread != null) 'parent_id': thread.id,
          if (thread != null) 'also_send_to_main': _alsoSendToMain,
        });
        unawaited(_deleteVoiceFile(audioPath));
      } catch (error) {
        if (path != null) unawaited(_deleteVoiceFile(path));
        if (mounted) {
          setState(() {
            _voiceRecording = false;
            _voiceTranscribing = false;
            _voicePath = null;
            _voiceError = 'Voice transcription failed: $error';
          });
        }
      }
      return;
    }

    try {
      if (!await _voiceRecorder.hasPermission()) {
        if (mounted) {
          setState(() => _voiceError = 'Microphone permission denied.');
        }
        return;
      }
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}${Platform.pathSeparator}workspace_voice_${DateTime.now().millisecondsSinceEpoch}.ogg';
      await _voiceRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.opus,
          bitRate: 32000,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          noiseSuppress: true,
        ),
        path: path,
      );
      if (mounted) {
        setState(() {
          _voiceRecording = true;
          _voicePath = path;
          _voiceStartedAt = DateTime.now();
          _voiceComposer = thread == null ? _composer : _threadComposer;
          _voiceError = null;
          widget.voiceResult.value = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _voiceError = 'Could not start recording: $error');
      }
    }
  }

  String? _usableVoiceAudioPath(String? primary, String? fallback) {
    final value = primary?.trim();
    if (value != null && value.isNotEmpty) return value;
    final fallbackValue = fallback?.trim();
    return fallbackValue != null && fallbackValue.isNotEmpty
        ? fallbackValue
        : null;
  }

  Future<void> _deleteVoiceFile(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  bool get _canSendTyping =>
      (_section == _WorkspaceSection.channel ||
          _section == _WorkspaceSection.direct) &&
      ((_composerFocus.hasFocus && _composer.text.trim().isNotEmpty) ||
          (_threadComposerFocus.hasFocus &&
              _threadComposer.text.trim().isNotEmpty));

  void _syncTypingLease() {
    if (!_canSendTyping) {
      _typingRefreshTimer?.cancel();
      _typingRefreshTimer = null;
      return;
    }
    _sendTypingLease();
    _typingRefreshTimer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => _sendTypingLease(),
    );
  }

  void _sendTypingLease() {
    if (!_canSendTyping) return;
    final now = DateTime.now();
    if (_lastTypingLease != null &&
        now.difference(_lastTypingLease!) < const Duration(seconds: 6)) {
      return;
    }
    _lastTypingLease = now;
    unawaited(
      widget.onTyping({
        'action': 'typing',
        if (_section == _WorkspaceSection.channel) 'channel_id': _active,
        if (_section == _WorkspaceSection.direct) 'recipient_pubkey': _active,
        if (_threadComposerFocus.hasFocus && _thread != null)
          'parent_id': _thread!.id,
        'expires_in_seconds': 4,
      }),
    );
  }

  List<WorkspaceMention> _mentionOptionsFor(TextEditingController composer) {
    final options = <WorkspaceMention>[
      for (final member in _conversationMembers)
        WorkspaceMention(
          kind: 'member',
          id: member,
          label: _memberLabel(member),
        ),
      for (final agent in _activeAgents)
        WorkspaceMention(kind: 'agent', id: agent.id, label: agent.name),
    ];
    final query = _mentionQueryFor(composer);
    if (query == null) return const [];
    final normalized = query.toLowerCase();
    return options
        .where((option) => option.label.toLowerCase().contains(normalized))
        .toList(growable: false);
  }

  Iterable<String> get _conversationMembers {
    if (_section == _WorkspaceSection.direct) return [_active];
    return {
      widget.ownPubkey,
      for (final message in _activeMessages)
        if (!isWorkspaceAgentSender(message.senderPubkey)) message.senderPubkey,
    };
  }

  String? _mentionQueryFor(TextEditingController composer) {
    final selection = composer.selection;
    final cursor = selection.isValid ? selection.start : composer.text.length;
    final prefix = composer.text.substring(
      0,
      cursor.clamp(0, composer.text.length),
    );
    final start = prefix.lastIndexOf('@');
    if (start < 0 || prefix.substring(start).contains(RegExp(r'\s'))) {
      return null;
    }
    return prefix.substring(start + 1);
  }

  void _insertMention(
    TextEditingController composer,
    List<WorkspaceMention> selectedMentions,
    WorkspaceMention mention,
  ) {
    final selection = composer.selection;
    final cursor = selection.isValid ? selection.start : composer.text.length;
    final text = composer.text;
    final start = text
        .substring(0, cursor.clamp(0, text.length))
        .lastIndexOf('@');
    if (start < 0) return;
    final replacement = '@${mention.label} ';
    composer.value = TextEditingValue(
      text: text.replaceRange(start, cursor, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    if (!selectedMentions.any(
      (selected) => selected.kind == mention.kind && selected.id == mention.id,
    )) {
      selectedMentions.add(mention);
    }
  }

  List<WorkspaceMessage> get _activeMessages =>
      _section == _WorkspaceSection.channel
      ? widget.workspace.messages[_active] ?? const []
      : widget.workspace.messages[WorkspaceState.directKey(
              widget.ownPubkey,
              _active,
            )] ??
            const [];

  List<WorkspaceMessage> get _threadReplies => _thread == null
      ? const []
      : _activeMessages
            .where((message) => message.parentId == _thread!.id)
            .toList(growable: false);

  List<WorkspaceAgent> get _activeAgents =>
      widget.workspace.agents.where((agent) {
        return widget.workspace.conversationAgents.any((membership) {
          if (membership.agentId != agent.id) return false;
          if (_section == _WorkspaceSection.channel) {
            return membership.channelId == _active;
          }
          final participants = [widget.ownPubkey, _active]..sort();
          return membership.memberPubkey == participants[0] &&
              membership.peerPubkey == participants[1];
        });
      }).toList();

  String get _title {
    switch (_section) {
      case _WorkspaceSection.channel:
        return '# ${widget.workspace.channelName(_active) ?? _active}';
      case _WorkspaceSection.direct:
        return _memberLabel(_active);
      case _WorkspaceSection.people:
        return 'People';
      case _WorkspaceSection.access:
        return 'Access';
      case _WorkspaceSection.agents:
        return 'Agents';
    }
  }

  String _memberLabel(String pubkey) {
    if (pubkey == widget.ownPubkey) {
      return widget.memberNames[pubkey] ??
          (widget.displayName.isEmpty ? 'You' : widget.displayName);
    }
    return widget.memberAliases[pubkey] ??
        widget.memberNames[pubkey] ??
        compactIdentifier(pubkey);
  }

  void _send({WorkspaceMessage? thread}) {
    final composer = thread == null ? _composer : _threadComposer;
    final selectedMentions = thread == null
        ? _selectedComposerMentions
        : _selectedThreadMentions;
    final text = composer.text.trim();
    if (text.isEmpty) return;
    final request = <String, Object?>{
      'action': _section == _WorkspaceSection.channel
          ? 'send_channel_message'
          : 'send_direct_message',
      if (_section == _WorkspaceSection.channel) 'channel_id': _active,
      if (_section == _WorkspaceSection.direct) 'recipient_pubkey': _active,
      'body': text,
      'mentions': _mentionsFor(
        text,
        selectedMentions,
      ).map((mention) => mention.toJson()).toList(),
      if (thread != null) 'parent_id': thread.id,
      if (thread != null) 'also_send_to_main': _alsoSendToMain,
    };
    composer.clear();
    selectedMentions.clear();
    if (thread == null) {
      _conversationDrafts.remove(_conversationKey);
    } else {
      _threadDrafts.remove(_threadDraftKey);
    }
    unawaited(widget.onRequest(request));
  }

  Future<void> _attach({WorkspaceMessage? thread}) async {
    final composer = thread == null ? _composer : _threadComposer;
    final selectedMentions = thread == null
        ? _selectedComposerMentions
        : _selectedThreadMentions;
    final sent = await widget.onAttach({
      'action': _section == _WorkspaceSection.channel
          ? 'send_channel_message'
          : 'send_direct_message',
      if (_section == _WorkspaceSection.channel) 'channel_id': _active,
      if (_section == _WorkspaceSection.direct) 'recipient_pubkey': _active,
      'body': composer.text.trim(),
      'mentions': _mentionsFor(
        composer.text,
        selectedMentions,
      ).map((mention) => mention.toJson()).toList(),
      if (thread != null) 'parent_id': thread.id,
      if (thread != null) 'also_send_to_main': _alsoSendToMain,
    });
    if (sent && mounted) {
      composer.clear();
      selectedMentions.clear();
      if (thread == null) {
        _conversationDrafts.remove(_conversationKey);
      } else {
        _threadDrafts.remove(_threadDraftKey);
      }
    }
  }

  List<WorkspaceMention> _mentionsFor(
    String text,
    List<WorkspaceMention> selected,
  ) => workspaceSelectedMentionsIn(text, selected).toList();

  void _select(_WorkspaceSection section, String id) {
    _closeDrawer();
    final previousKey = _conversationKey;
    if (previousKey != null) {
      _saveMainDraft();
      _saveThreadDraft();
      _panelStates[previousKey] = _WorkspacePanelState(
        threadId: _thread?.id,
        width: _threadPaneWidth,
        alsoSendToMain: _alsoSendToMain,
        filesSelected: _filesSelected,
        fileBrowser: widget.fileBrowser.value,
        filePreview: widget.filePreview.value,
      );
    }
    final nextKey = _conversationKeyFor(section, id);
    final nextPanelState = nextKey == null ? null : _panelStates[nextKey];
    setState(() {
      if (section == _WorkspaceSection.agents) _agentsPageRevision++;
      _section = section;
      _active = id;
      _thread = _threadWithId(nextPanelState?.threadId);
      _threadPaneWidth = nextPanelState?.width ?? 340;
      _alsoSendToMain = nextPanelState?.alsoSendToMain ?? false;
      _filesSelected = nextPanelState?.filesSelected ?? false;
      _filesFullWindow = false;
      _threadFullWindow = false;
      _restoreMainDraft(nextKey);
      _restoreThreadDraft();
    });
    widget.fileBrowser.value = nextPanelState?.fileBrowser;
    widget.filePreview.value = nextPanelState?.filePreview;
    if (section == _WorkspaceSection.channel) {
      widget.onFocusConversation(id);
    } else if (section == _WorkspaceSection.direct) {
      widget.onFocusConversation(
        WorkspaceState.directKey(widget.ownPubkey, id),
      );
    }
    final thread = _thread;
    if (nextKey != null && thread != null) {
      widget.onOpenThread(nextKey, thread.id);
    } else {
      widget.onCloseThread();
    }
    _syncTypingLease();
    _reloadActiveMessages();
  }

  void _closeDrawer() => _scaffoldKey.currentState?.closeDrawer();

  @override
  Widget build(BuildContext context) {
    final typing = _activeTyping;
    final threadTyping = _activeThreadTyping;
    final activityLabels = _conversationActivityLabels();
    _scheduleTypingExpiry(widget.workspace.typing.values.toList());
    final wide = MediaQuery.sizeOf(context).width >= 1080;
    final medium = MediaQuery.sizeOf(context).width >= 720;
    final sidebar = _WorkspaceSidebar(
      section: _section,
      selected: _section == _WorkspaceSection.channel ? _active : null,
      direct: _section == _WorkspaceSection.direct ? _active : null,
      sessions: widget.sessions,
      spaces: widget.spaces,
      activeSpace: widget.activeSpace,
      onSwitchSpace: widget.onSwitchSpace,
      channels: widget.workspace.channels,
      members: widget.workspace.directPeers(widget.ownPubkey),
      ownPubkey: widget.ownPubkey,
      displayName: widget.displayName,
      memberAliases: widget.memberAliases,
      memberNames: widget.memberNames,
      unreadCounts: widget.unreadCounts,
      activityLabels: activityLabels,
      onSelect: _select,
      onSessions: () {
        _closeDrawer();
        widget.onOpenSessions();
      },
      onSettings: () {
        _closeDrawer();
        widget.onOpenSettings();
      },
      onDiagnostics: widget.onOpenDiagnostics,
      onWorkerConsole: widget.onOpenWorkerConsole,
      onRefresh: () => unawaited(widget.onRequest({'action': 'refresh'})),
      onCreateChannel: () {
        _closeDrawer();
        unawaited(_createChannel(context));
      },
      onCreateDirect: () {
        _closeDrawer();
        unawaited(_startDirectMessage(context));
      },
      onConversationActions: () => unawaited(
        _conversationWidgetKey.currentState?._showConversationActions(),
      ),
    );
    final conversation = _WorkspaceConversation(
      key: _conversationWidgetKey,
      title: _title,
      section: _section,
      channelId: _section == _WorkspaceSection.channel ? _active : null,
      directPeer: _section == _WorkspaceSection.direct ? _active : null,
      messages: _activeMessages
          .where(
            (message) => message.parentId == null || message.alsoSendToMain,
          )
          .toList(growable: false),
      threadReplyCounts: {
        for (final message in _activeMessages.where(
          (message) => message.parentId != null,
        ))
          message.parentId!: _activeMessages
              .where((reply) => reply.parentId == message.parentId)
              .length,
      },
      threadUnreadCounts: {
        for (final entry in widget.threadUnreadCounts.entries)
          if (_conversationKey != null &&
              entry.key.startsWith('$_conversationKey:'))
            entry.key.substring(_conversationKey!.length + 1): entry.value,
      },
      threadActivityLabels: _threadActivityLabels(typing),
      composer: _composer,
      composerFocus: _composerFocus,
      onSend: _send,
      onAttach: _attach,
      voiceRecording: _voiceRecording,
      voiceTranscribing: _voiceTranscribing,
      voiceError: _voiceError,
      onVoicePressed: () => unawaited(_toggleVoiceRecording()),
      onOpenAttachment: widget.onOpenAttachment,
      onOpenThread: (message) {
        setState(() {
          if (_thread?.id != message.id) {
            _saveThreadDraft();
            _thread = message;
            _restoreThreadDraft();
          }
          _alsoSendToMain = false;
        });
        final conversationKey = _conversationKey;
        if (conversationKey != null) {
          widget.onOpenThread(conversationKey, message.id);
        }
      },
      onCloseThread: () {
        setState(() {
          _saveThreadDraft();
          _thread = null;
          _alsoSendToMain = false;
          _threadFullWindow = false;
        });
        widget.onCloseThread();
      },
      onToggleReaction: (message, emoji) => widget.onRequest({
        'action': 'toggle_reaction',
        'parent_id': message.id,
        'reaction': emoji,
      }),
      thread: _thread,
      alsoSendToMain: _alsoSendToMain,
      onAlsoSendToMainChanged: (value) =>
          setState(() => _alsoSendToMain = value),
      onOpenSettings: widget.onOpenSettings,
      onReload: _reloadActiveMessages,
      onOpenFiles: () {
        final conversationKey = _conversationKey;
        return conversationKey == null
            ? Future<void>.value()
            : widget.onOpenFiles(conversationKey);
      },
      onRenameConversation: (name) async {
        if (_section == _WorkspaceSection.channel) {
          await widget.onRequest({
            'action': 'rename_channel',
            'channel_id': _active,
            'channel_name': name,
          });
        } else if (_section == _WorkspaceSection.direct) {
          widget.onMemberAliasChanged(_active, name);
        }
      },
      onDeleteConversation: () async {
        if (_section == _WorkspaceSection.channel) {
          await widget.onRequest({
            'action': 'delete_channel',
            'channel_id': _active,
          });
        } else if (_section == _WorkspaceSection.direct) {
          await widget.onRequest({
            'action': 'delete_direct_conversation',
            'recipient_pubkey': _active,
          });
        }
        if (mounted) _select(_WorkspaceSection.channel, 'workspace');
      },
      inviteCode: widget.inviteCode,
      memberStatus: widget.memberStatus,
      onCreateInvite: widget.onCreateInvite,
      members: widget.workspace.members,
      channelHumanMemberCount: _section == _WorkspaceSection.channel
          ? widget.workspace.channelHumanMemberCount(_active)
          : 0,
      ownPubkey: widget.ownPubkey,
      localSenderIds: widget.localSenderIds,
      displayName: widget.displayName,
      memberAliases: widget.memberAliases,
      memberNames: widget.memberNames,
      onOpenDirect: (pubkey) => _select(_WorkspaceSection.direct, pubkey),
      onDisplayNameChanged: widget.onDisplayNameChanged,
      onMemberAliasChanged: widget.onMemberAliasChanged,
      workspace: widget.workspace,
      workspaceRevision: widget.workspaceRevision,
      onRequest: widget.onRequest,
      onLoadOpenCodeModels: widget.onLoadOpenCodeModels,
      initialFolderChoices: widget.initialFolderChoices,
      onLoadFolders: widget.onLoadFolders,
      onOpenAgentConversation: widget.onOpenAgentConversation,
      conversationPreprompt: widget.workspace.conversationPreprompt(
        channelId: _section == _WorkspaceSection.channel ? _active : null,
        ownPubkey: widget.ownPubkey,
        peerPubkey: _section == _WorkspaceSection.direct ? _active : null,
      ),
      agentsPageRevision: _agentsPageRevision,
      agents: _activeAgents,
      onManageAgents:
          _section == _WorkspaceSection.channel ||
              _section == _WorkspaceSection.direct
          ? () => _manageAgents(context)
          : null,
      onEditConversationPreprompt: (value) => widget.onRequest({
        'action': 'set_conversation_preprompt',
        'body': value,
        if (_section == _WorkspaceSection.channel) 'channel_id': _active,
        if (_section == _WorkspaceSection.direct) 'recipient_pubkey': _active,
      }),
      mentionOptions: _mentionOptionsFor(_composer),
      onMentionSelected: (mention) =>
          _insertMention(_composer, _selectedComposerMentions, mention),
      typingLabels: _typingLabels(typing),
      callPhase: widget.callPhase,
      callPeerPubkey: widget.callPeerPubkey,
      groupCallPhase: widget.groupCallPhase,
      groupCallChannelId: widget.groupCallChannelId,
      onStartCall: widget.onStartCall,
      onStartChannelCall: widget.onStartChannelCall,
      onAcceptCall: widget.onAcceptCall,
      onRejectCall: widget.onRejectCall,
      onHangupCall: widget.onHangupCall,
      onAcceptGroupCall: widget.onAcceptGroupCall,
      onRejectGroupCall: widget.onRejectGroupCall,
      onHangupGroupCall: widget.onHangupGroupCall,
      mediaSource: widget.mediaSource,
      onMediaSourceChanged: widget.onMediaSourceChanged,
    );
    final contextPane = _WorkspaceContext(
      key: ValueKey(_thread?.id),
      message: _thread,
      replies: _threadReplies,
      title: _title,
      composer: _threadComposer,
      composerFocus: _threadComposerFocus,
      mentionOptions: _mentionOptionsFor(_threadComposer),
      onMentionSelected: (mention) =>
          _insertMention(_threadComposer, _selectedThreadMentions, mention),
      onSend: () => _send(thread: _thread),
      onAttach: () => _attach(thread: _thread),
      voiceRecording: _voiceRecording && _voiceComposer == _threadComposer,
      voiceTranscribing:
          _voiceTranscribing && _voiceComposer == _threadComposer,
      voiceError: _voiceComposer == _threadComposer ? _voiceError : null,
      onVoicePressed: () => unawaited(_toggleVoiceRecording(thread: _thread)),
      alsoSendToMain: _alsoSendToMain,
      onAlsoSendToMainChanged: (value) =>
          setState(() => _alsoSendToMain = value),
      onClose: () {
        setState(() {
          _saveThreadDraft();
          _thread = null;
          _alsoSendToMain = false;
          _threadFullWindow = false;
        });
        widget.onCloseThread();
      },
      onToggleReaction: (message, emoji) => widget.onRequest({
        'action': 'toggle_reaction',
        'parent_id': message.id,
        'reaction': emoji,
      }),
      onOpenAttachment: widget.onOpenAttachment,
      ownPubkey: widget.ownPubkey,
      localSenderIds: widget.localSenderIds,
      displayName: widget.displayName,
      memberAliases: widget.memberAliases,
      memberNames: widget.memberNames,
      agents: _activeAgents,
      typingLabels: _typingLabels(threadTyping),
      fullWindow: _threadFullWindow,
      onToggleFullWindow: () =>
          setState(() => _threadFullWindow = !_threadFullWindow),
    );
    final conversationKey = _conversationKey;
    final fileBrowser = widget.fileBrowser.value;
    final filesPane = fileBrowser == null
        ? null
        : _WorkspaceFilesPanel(
            result: fileBrowser,
            preview: widget.filePreview.value,
            onBrowse: (path) => conversationKey == null
                ? Future<void>.value()
                : widget.onBrowseFiles(
                    conversationKey,
                    fileBrowser.directory,
                    path,
                  ),
            onUp: () {
              final parts = fileBrowser.directory.split('/')..removeLast();
              return conversationKey == null
                  ? Future<void>.value()
                  : widget.onBrowseFiles(conversationKey, '', parts.join('/'));
            },
            onReadFile: (path) => conversationKey == null
                ? Future<void>.value()
                : widget.onReadWorkspaceFile(
                    conversationKey,
                    fileBrowser.directory,
                    path,
                  ),
            onFullWindow: () => setState(() {
              _threadFullWindow = false;
              _filesFullWindow = true;
            }),
            onCloseFullWindow: () => setState(() => _filesFullWindow = false),
            onClosePreview: () => widget.filePreview.value = null,
            fullWindow: _filesFullWindow,
          );
    final showSidePane =
        _thread != null || (_filesSelected && filesPane != null);
    final showFiles = _filesSelected && filesPane != null;
    final fullSidePane = _filesFullWindow || _threadFullWindow;
    final windowWidth = MediaQuery.sizeOf(context).width;
    final persistentChromeWidth = wide ? _sidebarWidth + 7 : 0;
    final canShowInlineSidePane =
        showSidePane &&
        medium &&
        !fullSidePane &&
        windowWidth >=
            persistentChromeWidth +
                _conversationMinWidth +
                _threadPaneMinWidth +
                10;
    final maxSidePaneWidth =
        (windowWidth - persistentChromeWidth - _conversationMinWidth - 10)
            .clamp(_threadPaneMinWidth, _threadPaneMaxWidth);
    final sidePaneWidth = _threadPaneWidth.clamp(
      _threadPaneMinWidth,
      maxSidePaneWidth,
    );
    // Keep the active conversation readable. On a narrow window the detail
    // pane replaces it instead of squeezing both panes into unusable columns.
    final showSingleSidePane =
        showSidePane && !fullSidePane && !canShowInlineSidePane;
    final sidePane = _WorkspaceSidePanel(
      thread: _thread != null ? contextPane : null,
      files: filesPane,
      showFiles: showFiles,
      onShowThread: () => setState(() {
        _filesSelected = false;
        _filesFullWindow = false;
      }),
      onShowFiles: () => setState(() {
        _filesSelected = true;
        _threadFullWindow = false;
      }),
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(
        context,
      ).extension<_WorkspacePalette>()!.background,
      appBar: wide
          ? null
          : AppBar(
              title: const Text('Ribbit'),
              actions: [
                IconButton(
                  onPressed: widget.onOpenSettings,
                  icon: const Icon(Icons.tune_outlined),
                ),
              ],
            ),
      drawer: wide ? null : Drawer(child: SafeArea(child: sidebar)),
      body: SafeArea(
        child: Row(
          children: [
            if (wide) SizedBox(width: _sidebarWidth, child: sidebar),
            if (wide)
              SidebarPaneResizeHandle(
                onResize: (delta) => setState(() {
                  _sidebarWidth = (_sidebarWidth + delta).clamp(
                    _sidebarMinWidth,
                    _sidebarMaxWidth,
                  );
                }),
              ),
            if (wide) const VerticalDivider(width: 1),
            Expanded(
              child: fullSidePane
                  ? sidePane
                  : showSingleSidePane
                  ? sidePane
                  : conversation,
            ),
            if (canShowInlineSidePane) ...[
              ThreadPaneResizeHandle(
                onResize: (delta) => setState(() {
                  _threadPaneWidth = (_threadPaneWidth + delta).clamp(
                    _threadPaneMinWidth,
                    maxSidePaneWidth,
                  );
                  final key = _conversationKey;
                  if (key != null) {
                    _panelStates[key] = _WorkspacePanelState(
                      threadId: _thread?.id,
                      width: _threadPaneWidth,
                      alsoSendToMain: _alsoSendToMain,
                      filesSelected: _filesSelected,
                      fileBrowser: widget.fileBrowser.value,
                      filePreview: widget.filePreview.value,
                    );
                  }
                }),
              ),
              SizedBox(width: sidePaneWidth, child: sidePane),
            ],
          ],
        ),
      ),
    );
  }

  List<WorkspaceTyping> get _activeTyping => widget.workspace.activeTyping(
    channelId: _section == _WorkspaceSection.channel ? _active : null,
    ownPubkey: widget.ownPubkey,
    peerPubkey: _section == _WorkspaceSection.direct ? _active : null,
    parentId: null,
    includeThreadTyping: true,
    nowSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );

  List<WorkspaceTyping> get _activeThreadTyping {
    final parentId = _thread?.id;
    if (parentId == null) return const [];
    return widget.workspace.activeTyping(
      channelId: _section == _WorkspaceSection.channel ? _active : null,
      ownPubkey: widget.ownPubkey,
      peerPubkey: _section == _WorkspaceSection.direct ? _active : null,
      parentId: parentId,
      nowSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  List<String> _typingLabels(List<WorkspaceTyping> statuses) =>
      statuses.map(_typingLabel).toList(growable: false);

  Map<String, String> _conversationActivityLabels() {
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final labels = <String, String>{};
    for (final channel in widget.workspace.channels) {
      final statuses = widget.workspace.activeTyping(
        channelId: channel.id,
        ownPubkey: widget.ownPubkey,
        peerPubkey: null,
        includeThreadTyping: true,
        nowSeconds: nowSeconds,
      );
      if (statuses.isNotEmpty) {
        labels[channel.id] = _typingLabels(statuses).join(' · ');
      }
    }
    for (final member in widget.workspace.directPeers(widget.ownPubkey)) {
      final statuses = widget.workspace.activeTyping(
        channelId: null,
        ownPubkey: widget.ownPubkey,
        peerPubkey: member,
        includeThreadTyping: true,
        nowSeconds: nowSeconds,
      );
      if (statuses.isNotEmpty) {
        labels[WorkspaceState.directKey(widget.ownPubkey, member)] =
            _typingLabels(statuses).join(' · ');
      }
    }
    return labels;
  }

  Map<String, String> _threadActivityLabels(
    Iterable<WorkspaceTyping> statuses,
  ) {
    final labels = <String, List<String>>{};
    for (final status in statuses) {
      final parentId = status.parentId;
      if (parentId != null) {
        labels.putIfAbsent(parentId, () => []).add(_typingLabel(status));
      }
    }
    return {
      for (final entry in labels.entries) entry.key: entry.value.join('\n'),
    };
  }

  String _typingLabel(WorkspaceTyping status) => status.agentId != null
      ? '${status.agentName ?? _memberLabel(status.senderPubkey)} is working...'
      : '${_memberLabel(status.senderPubkey)} is typing...';

  void _scheduleTypingExpiry(List<WorkspaceTyping> typing) {
    _typingExpiryTimer?.cancel();
    if (typing.isEmpty) return;
    final nextExpiry = typing
        .map((status) => status.expiresAt)
        .reduce((a, b) => a < b ? a : b);
    final delay = Duration(
      seconds: (nextExpiry - DateTime.now().millisecondsSinceEpoch ~/ 1000)
          .clamp(1, 30),
    );
    _typingExpiryTimer = Timer(delay, () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _createChannel(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create channel'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'engineering'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await widget.onRequest({
        'action': 'create_channel',
        'channel_name': name.trim(),
      });
    }
  }

  Future<void> _startDirectMessage(BuildContext context) async {
    final peer = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('New direct message')),
            for (final member in widget.workspace.members)
              if (member != widget.ownPubkey)
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(_memberLabel(member)),
                  onTap: () => Navigator.pop(context, member),
                ),
          ],
        ),
      ),
    );
    if (peer != null) _select(_WorkspaceSection.direct, peer);
  }

  Future<void> _manageAgents(BuildContext context) async {
    final attached = _activeAgents.map((agent) => agent.id).toSet();
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Conversation agents')),
            for (final agent in widget.workspace.agents)
              CheckboxListTile(
                value: attached.contains(agent.id),
                title: Text(agent.name),
                subtitle: Text(
                  agent.openCodeSessionId == null
                      ? 'No OpenCode session attached'
                      : agent.role,
                ),
                onChanged: (_) async {
                  final navigator = Navigator.of(context);
                  final action = attached.contains(agent.id)
                      ? 'remove_conversation_agent'
                      : 'add_conversation_agent';
                  final folderScope = action == 'add_conversation_agent'
                      ? await showDialog<List<String>>(
                          context: context,
                          builder: (_) => _FolderScopeDialog(
                            onLoadChoices: widget.onLoadFolderChoices,
                          ),
                        )
                      : null;
                  if (action == 'add_conversation_agent' &&
                      folderScope == null) {
                    return;
                  }
                  if (!mounted) return;
                  unawaited(
                    widget.onRequest({
                      'action': action,
                      'agent_id': agent.id,
                      'folder_scope': ?folderScope,
                      if (_section == _WorkspaceSection.channel)
                        'channel_id': _active,
                      if (_section == _WorkspaceSection.direct)
                        'recipient_pubkey': _active,
                    }),
                  );
                  navigator.pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _FolderScopeDialog extends StatefulWidget {
  const _FolderScopeDialog({
    required this.onLoadChoices,
    this.initialSelected = const [],
  });

  final Future<List<RepoChoice>> Function() onLoadChoices;
  final List<String> initialSelected;

  @override
  State<_FolderScopeDialog> createState() => _FolderScopeDialogState();
}

class _FolderScopeDialogState extends State<_FolderScopeDialog> {
  late final Future<List<RepoChoice>> _choices = widget.onLoadChoices();
  late final _selected = widget.initialSelected.toSet();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Folder access'),
    content: SizedBox(
      width: 460,
      child: FutureBuilder<List<RepoChoice>>(
        future: _choices,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return const Text('Could not load folders from the worker.');
          }
          final folders = snapshot.data ?? const <RepoChoice>[];
          if (folders.isEmpty) return const Text('No folders are available.');
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select folders. Each folder includes all repositories in its subfolders.',
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 300,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final folder in folders)
                      CheckboxListTile(
                        value: _selected.contains(folder.path),
                        title: Text(folder.displayName),
                        subtitle: Text(
                          folder.isGitRepo ? 'Repository folder' : 'Folder',
                        ),
                        onChanged: (selected) => setState(() {
                          if (selected == true) {
                            _selected.add(folder.path);
                          } else {
                            _selected.remove(folder.path);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.pop(context, _selected.toList()..sort()),
        child: const Text('Grant access'),
      ),
    ],
  );
}

class SidebarPaneResizeHandle extends StatelessWidget {
  const SidebarPaneResizeHandle({super.key, required this.onResize});

  final ValueChanged<double> onResize;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Resize sidebar',
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onResize(details.delta.dx),
        child: const SizedBox(width: 6, height: double.infinity),
      ),
    ),
  );
}

class ThreadPaneResizeHandle extends StatelessWidget {
  const ThreadPaneResizeHandle({super.key, required this.onResize});

  final ValueChanged<double> onResize;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Resize side panel',
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onResize(-details.delta.dx),
        child: SizedBox(
          width: 10,
          height: double.infinity,
          child: Center(
            child: Container(
              width: 2,
              height: double.infinity,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    ),
  );
}

class _WorkspaceSidebar extends StatelessWidget {
  const _WorkspaceSidebar({
    required this.section,
    required this.selected,
    required this.direct,
    required this.sessions,
    required this.spaces,
    required this.activeSpace,
    required this.onSwitchSpace,
    required this.channels,
    required this.members,
    required this.ownPubkey,
    required this.displayName,
    required this.memberAliases,
    required this.memberNames,
    required this.unreadCounts,
    required this.activityLabels,
    required this.onSelect,
    required this.onSessions,
    required this.onSettings,
    required this.onDiagnostics,
    required this.onWorkerConsole,
    required this.onRefresh,
    required this.onCreateChannel,
    required this.onCreateDirect,
    required this.onConversationActions,
  });
  final _WorkspaceSection section;
  final String? selected;
  final String? direct;
  final List<RepoTarget> sessions;
  final List<RepoTarget> spaces;
  final RepoTarget? activeSpace;
  final ValueChanged<RepoTarget> onSwitchSpace;
  final List<WorkspaceChannel> channels;
  final List<String> members;
  final String ownPubkey;
  final String displayName;
  final Map<String, String> memberAliases;
  final Map<String, String> memberNames;
  final Map<String, int> unreadCounts;
  final Map<String, String> activityLabels;
  final void Function(_WorkspaceSection, String) onSelect;
  final VoidCallback onSessions;
  final VoidCallback onSettings;
  final VoidCallback onDiagnostics;
  final VoidCallback onWorkerConsole;
  final VoidCallback onRefresh;
  final VoidCallback onCreateChannel;
  final VoidCallback onCreateDirect;
  final VoidCallback onConversationActions;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<_WorkspacePalette>()!;
    String memberLabel(String pubkey) => pubkey == ownPubkey
        ? (memberNames[pubkey] ?? (displayName.isEmpty ? 'You' : displayName))
        : memberAliases[pubkey] ??
              memberNames[pubkey] ??
              compactIdentifier(pubkey);
    Widget item(
      IconData icon,
      String label, {
      bool selected = false,
      VoidCallback? onTap,
      int unreadCount = 0,
      String? count,
      String? activity,
      Widget? action,
    }) => ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: palette.selected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(icon, size: 19),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: activity == null
          ? null
          : Text(
              activity,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
      trailing:
          action ??
          (unreadCount > 0
              ? Semantics(
                  label: '$unreadCount unread messages',
                  child: ExcludeSemantics(
                    child: Badge(label: Text('$unreadCount')),
                  ),
                )
              : count == null
              ? null
              : Text(count, style: Theme.of(context).textTheme.labelSmall)),
      onTap: onTap,
    );
    return ColoredBox(
      color: palette.sidebar,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: PopupMenuButton<String>(
                        tooltip: 'Switch workspace',
                        onSelected: (value) {
                          if (value == 'join') {
                            onSettings();
                            return;
                          }
                          final matches = spaces.where(
                            (space) => 'space:${space.id}' == value,
                          );
                          if (matches.isNotEmpty) onSwitchSpace(matches.first);
                        },
                        itemBuilder: (context) => [
                          for (final space in spaces)
                            CheckedPopupMenuItem(
                              value: 'space:${space.id}',
                              checked: space.id == activeSpace?.id,
                              child: Text(space.displayName),
                            ),
                          if (spaces.isNotEmpty) const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'join',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.group_add_outlined),
                              title: Text('Join space'),
                            ),
                          ),
                        ],
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                activeSpace?.displayName ?? 'Select workspace',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.expand_more, color: palette.label),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_outlined),
                      tooltip: 'Refresh workspace',
                    ),
                    IconButton(
                      onPressed: onSettings,
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: 'Settings',
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Conversations',
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: palette.label),
                      ),
                    ),
                    IconButton(
                      onPressed: onCreateChannel,
                      icon: const Icon(Icons.add, size: 18),
                      tooltip: 'Create channel',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (channels.isEmpty)
                  const ListTile(dense: true, title: Text('No channels yet')),
                for (final channel in channels)
                  item(
                    Icons.tag,
                    channel.name,
                    selected: selected == channel.id,
                    unreadCount: unreadCounts[channel.id] ?? 0,
                    activity: activityLabels[channel.id],
                    action: selected == channel.id
                        ? IconButton(
                            onPressed: onConversationActions,
                            icon: const Icon(Icons.more_vert, size: 18),
                            tooltip: 'Conversation actions',
                            visualDensity: VisualDensity.compact,
                          )
                        : null,
                    onTap: () =>
                        onSelect(_WorkspaceSection.channel, channel.id),
                  ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Direct messages',
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: palette.label),
                      ),
                    ),
                    IconButton(
                      onPressed: onCreateDirect,
                      icon: const Icon(Icons.add, size: 18),
                      tooltip: 'New direct message',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (members.isEmpty)
                  const ListTile(
                    dense: true,
                    title: Text('No direct messages yet'),
                  ),
                for (final member in members)
                  item(
                    Icons.chat_bubble_outline,
                    memberLabel(member),
                    selected: direct == member,
                    unreadCount:
                        unreadCounts[WorkspaceState.directKey(
                          ownPubkey,
                          member,
                        )] ??
                        0,
                    activity:
                        activityLabels[WorkspaceState.directKey(
                          ownPubkey,
                          member,
                        )],
                    action: direct == member
                        ? IconButton(
                            onPressed: onConversationActions,
                            icon: const Icon(Icons.more_vert, size: 18),
                            tooltip: 'Conversation actions',
                            visualDensity: VisualDensity.compact,
                          )
                        : null,
                    onTap: () => onSelect(_WorkspaceSection.direct, member),
                  ),
                const SizedBox(height: 18),
                Text(
                  'Workspace',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: palette.label),
                ),
                const SizedBox(height: 6),
                item(
                  Icons.people_outline,
                  'People',
                  selected: section == _WorkspaceSection.people,
                  onTap: () => onSelect(_WorkspaceSection.people, 'people'),
                ),
                item(
                  Icons.admin_panel_settings_outlined,
                  'Access',
                  selected: section == _WorkspaceSection.access,
                  onTap: () => onSelect(_WorkspaceSection.access, 'access'),
                ),
                item(
                  Icons.smart_toy_outlined,
                  'Agents',
                  selected: section == _WorkspaceSection.agents,
                  onTap: () => onSelect(_WorkspaceSection.agents, 'agents'),
                ),
                const SizedBox(height: 18),
                Text(
                  'Focused work',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: palette.label),
                ),
                const SizedBox(height: 6),
                item(
                  Icons.workspaces_outline,
                  'Sessions',
                  count: sessions.isEmpty ? null : '${sessions.length}',
                  onTap: onSessions,
                ),
                for (final session in sessions.take(3))
                  item(
                    Icons.terminal_outlined,
                    session.displayName,
                    onTap: onSessions,
                  ),
                const SizedBox(height: 18),
                item(
                  Icons.monitor_heart_outlined,
                  'Worker console',
                  onTap: onWorkerConsole,
                ),
                item(
                  Icons.bug_report_outlined,
                  'Diagnostics',
                  onTap: onDiagnostics,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Ribbit $_appVersion',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: palette.label),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceConversation extends StatefulWidget {
  const _WorkspaceConversation({
    super.key,
    required this.title,
    required this.section,
    required this.channelId,
    required this.directPeer,
    required this.messages,
    required this.threadReplyCounts,
    required this.threadUnreadCounts,
    required this.threadActivityLabels,
    required this.composer,
    required this.composerFocus,
    required this.onSend,
    required this.onAttach,
    required this.voiceRecording,
    required this.voiceTranscribing,
    required this.voiceError,
    required this.onVoicePressed,
    required this.onOpenAttachment,
    required this.onOpenThread,
    required this.onCloseThread,
    required this.onToggleReaction,
    required this.thread,
    required this.alsoSendToMain,
    required this.onAlsoSendToMainChanged,
    required this.onOpenSettings,
    required this.onReload,
    required this.onOpenFiles,
    required this.onRenameConversation,
    required this.onDeleteConversation,
    required this.inviteCode,
    required this.memberStatus,
    required this.onCreateInvite,
    required this.members,
    required this.channelHumanMemberCount,
    required this.ownPubkey,
    required this.localSenderIds,
    required this.displayName,
    required this.memberAliases,
    required this.memberNames,
    required this.onOpenDirect,
    required this.onDisplayNameChanged,
    required this.onMemberAliasChanged,
    required this.workspace,
    required this.workspaceRevision,
    required this.onRequest,
    required this.onLoadOpenCodeModels,
    required this.initialFolderChoices,
    required this.onLoadFolders,
    required this.onOpenAgentConversation,
    required this.conversationPreprompt,
    required this.agentsPageRevision,
    required this.agents,
    required this.onManageAgents,
    required this.onEditConversationPreprompt,
    required this.mentionOptions,
    required this.onMentionSelected,
    required this.typingLabels,
    required this.callPhase,
    required this.callPeerPubkey,
    required this.groupCallPhase,
    required this.groupCallChannelId,
    required this.onStartCall,
    required this.onStartChannelCall,
    required this.onAcceptCall,
    required this.onRejectCall,
    required this.onHangupCall,
    required this.onAcceptGroupCall,
    required this.onRejectGroupCall,
    required this.onHangupGroupCall,
    required this.mediaSource,
    required this.onMediaSourceChanged,
  });
  final String title;
  final _WorkspaceSection section;
  final String? channelId;
  final String? directPeer;
  final List<WorkspaceMessage> messages;
  final Map<String, int> threadReplyCounts;
  final Map<String, int> threadUnreadCounts;
  final Map<String, String> threadActivityLabels;
  final TextEditingController composer;
  final FocusNode composerFocus;
  final VoidCallback onSend;
  final Future<void> Function() onAttach;
  final bool voiceRecording;
  final bool voiceTranscribing;
  final String? voiceError;
  final VoidCallback onVoicePressed;
  final Future<void> Function(BridgeAudioReference attachment) onOpenAttachment;
  final ValueChanged<WorkspaceMessage> onOpenThread;
  final VoidCallback onCloseThread;
  final Future<void> Function(WorkspaceMessage message, String emoji)
  onToggleReaction;
  final WorkspaceMessage? thread;
  final bool alsoSendToMain;
  final ValueChanged<bool> onAlsoSendToMainChanged;
  final VoidCallback onOpenSettings;
  final VoidCallback onReload;
  final Future<void> Function() onOpenFiles;
  final Future<void> Function(String name) onRenameConversation;
  final Future<void> Function() onDeleteConversation;
  final String? inviteCode;
  final String memberStatus;
  final Future<void> Function() onCreateInvite;
  final List<String> members;
  final int channelHumanMemberCount;
  final String ownPubkey;
  final Set<String> localSenderIds;
  final String displayName;
  final Map<String, String> memberAliases;
  final Map<String, String> memberNames;
  final ValueChanged<String> onOpenDirect;
  final ValueChanged<String> onDisplayNameChanged;
  final void Function(String pubkey, String alias) onMemberAliasChanged;
  final WorkspaceState workspace;
  final ValueListenable<int> workspaceRevision;
  final Future<void> Function(Map<String, Object?> request) onRequest;
  final Future<List<_OpenCodeModelChoice>> Function() onLoadOpenCodeModels;
  final List<RepoChoice> initialFolderChoices;
  final Future<List<RepoChoice>> Function(String? path) onLoadFolders;
  final Future<void> Function(WorkspaceAgent agent) onOpenAgentConversation;
  final String conversationPreprompt;
  final int agentsPageRevision;
  final List<WorkspaceAgent> agents;
  final VoidCallback? onManageAgents;
  final Future<void> Function(String value) onEditConversationPreprompt;
  final List<WorkspaceMention> mentionOptions;
  final ValueChanged<WorkspaceMention> onMentionSelected;
  final List<String> typingLabels;
  final _CallPhase callPhase;
  final String? callPeerPubkey;
  final _CallPhase groupCallPhase;
  final String? groupCallChannelId;
  final ValueChanged<String> onStartCall;
  final Future<void> Function(String channelId) onStartChannelCall;
  final VoidCallback onAcceptCall;
  final VoidCallback onRejectCall;
  final VoidCallback onHangupCall;
  final VoidCallback onAcceptGroupCall;
  final VoidCallback onRejectGroupCall;
  final VoidCallback onHangupGroupCall;
  final _CallMediaSource mediaSource;
  final ValueChanged<_CallMediaSource> onMediaSourceChanged;

  @override
  State<_WorkspaceConversation> createState() => _WorkspaceConversationState();
}

class _WorkspaceConversationState extends State<_WorkspaceConversation> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String? _lastMessageId;
  double? _lastViewportHeight;
  bool _scrollQueued = false;
  bool _searchOpen = false;
  String _searchQuery = '';

  Future<void> _editConversationPreprompt() async {
    final controller = TextEditingController(
      text: widget.conversationPreprompt,
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agent brief'),
        content: TextField(
          controller: controller,
          maxLength: 4000,
          minLines: 4,
          maxLines: 10,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) await widget.onEditConversationPreprompt(value.trim());
  }

  @override
  void initState() {
    super.initState();
    _lastMessageId = _latestMessageId;
    _queueScrollToLatest();
  }

  @override
  void didUpdateWidget(covariant _WorkspaceConversation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section ||
        oldWidget.channelId != widget.channelId ||
        oldWidget.directPeer != widget.directPeer) {
      _searchController.clear();
      _searchQuery = '';
      _searchOpen = false;
    }
    if (_lastMessageId != _latestMessageId) {
      _lastMessageId = _latestMessageId;
      _queueScrollToLatest();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? get _latestMessageId =>
      widget.messages.isEmpty ? null : widget.messages.last.id;

  List<WorkspaceMessage> get _visibleMessages {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return widget.messages;
    return widget.messages
        .where(
          (message) =>
              message.body.toLowerCase().contains(query) ||
              _memberLabel(message.senderPubkey).toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  Future<void> _renameConversation() async {
    final controller = TextEditingController(text: widget.title);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename conversation'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await widget.onRenameConversation(name.trim());
    }
  }

  Future<void> _deleteConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'This deletes its message history and attached conversation settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onDeleteConversation();
  }

  Future<void> _showConversationActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename conversation'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete conversation',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'rename') {
      await _renameConversation();
    } else {
      await _deleteConversation();
    }
  }

  void _queueScrollToLatest() {
    if (_scrollQueued) return;
    _scrollQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollQueued = false;
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
      // Rich text and attachment controls can increase height after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    });
  }

  String _memberLabel(String pubkey) {
    if (pubkey.startsWith('agent:')) {
      final id = pubkey.substring('agent:'.length);
      for (final agent in widget.agents) {
        if (agent.id == id) return agent.name;
      }
      return 'Agent';
    }
    if (pubkey == widget.ownPubkey) {
      return widget.memberNames[pubkey] ??
          (widget.displayName.isEmpty ? 'You' : widget.displayName);
    }
    return widget.memberAliases[pubkey] ??
        widget.memberNames[pubkey] ??
        compactIdentifier(pubkey);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.section == _WorkspaceSection.people) {
      return _PeopleDirectory(
        members: widget.members,
        ownPubkey: widget.ownPubkey,
        displayName: widget.displayName,
        memberAliases: widget.memberAliases,
        memberNames: widget.memberNames,
        onOpenDirect: widget.onOpenDirect,
        onDisplayNameChanged: widget.onDisplayNameChanged,
        onMemberAliasChanged: widget.onMemberAliasChanged,
      );
    }
    if (widget.section == _WorkspaceSection.access) {
      return _WorkspaceAccessPage(
        inviteCode: widget.inviteCode,
        memberStatus: widget.memberStatus,
        onCreateInvite: widget.onCreateInvite,
        onOpenSettings: widget.onOpenSettings,
      );
    }
    if (widget.section == _WorkspaceSection.agents) {
      return _AgentsPage(
        key: ValueKey(widget.agentsPageRevision),
        workspace: widget.workspace,
        ownPubkey: widget.ownPubkey,
        workspaceRevision: widget.workspaceRevision,
        onRequest: widget.onRequest,
        onLoadOpenCodeModels: widget.onLoadOpenCodeModels,
        initialFolderChoices: widget.initialFolderChoices,
        onLoadFolders: widget.onLoadFolders,
        onOpenConversation: widget.onOpenAgentConversation,
      );
    }
    final palette = Theme.of(context).extension<_WorkspacePalette>()!;
    final visibleMessages = _visibleMessages;
    final searching = _searchQuery.trim().isNotEmpty;
    return ColoredBox(
      color: palette.content,
      child: Column(
        children: [
          Container(
            color: palette.sidebar.withValues(alpha: 0.48),
            padding: const EdgeInsets.fromLTRB(24, 18, 20, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.section == _WorkspaceSection.channel ? 'Channel' : 'Direct message'}${widget.agents.isEmpty ? '' : ' · ${widget.agents.length} agent${widget.agents.length == 1 ? '' : 's'}'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (widget.onManageAgents != null)
                      IconButton(
                        onPressed: widget.onManageAgents,
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        tooltip: 'Manage agents',
                      ),
                    IconButton(
                      onPressed: () => setState(() {
                        _searchOpen = !_searchOpen;
                        if (!_searchOpen) {
                          _searchController.clear();
                          _searchQuery = '';
                        }
                      }),
                      icon: Icon(
                        _searchOpen ? Icons.search_off_outlined : Icons.search,
                      ),
                      tooltip: _searchOpen ? 'Close search' : 'Search messages',
                    ),
                    IconButton(
                      onPressed: widget.onReload,
                      icon: const Icon(Icons.arrow_upward_outlined),
                      tooltip: 'Reload last messages',
                    ),
                    if (widget.section == _WorkspaceSection.channel)
                      IconButton(
                        onPressed: () => unawaited(widget.onOpenFiles()),
                        icon: const Icon(Icons.folder_open_outlined),
                        tooltip: 'Browse repository files',
                      ),
                    IconButton(
                      onPressed: _editConversationPreprompt,
                      icon: const Icon(Icons.edit_note_outlined),
                      tooltip: 'Edit agent brief',
                    ),
                    if (widget.section == _WorkspaceSection.direct)
                      _CallControl(
                        phase:
                            widget.callPeerPubkey == null ||
                                widget.callPeerPubkey == widget.directPeer
                            ? widget.callPhase
                            : _CallPhase.idle,
                        onStart: () => widget.onStartCall(widget.directPeer!),
                        onAccept: widget.onAcceptCall,
                        onReject: widget.onRejectCall,
                        onHangup: widget.onHangupCall,
                        mediaSource: widget.mediaSource,
                        onMediaSourceChanged: widget.onMediaSourceChanged,
                      ),
                    if (widget.section == _WorkspaceSection.channel)
                      _CallControl(
                        phase:
                            widget.groupCallChannelId == null ||
                                widget.groupCallChannelId == widget.channelId
                            ? widget.groupCallPhase
                            : _CallPhase.idle,
                        onStart: () => unawaited(
                          widget.onStartChannelCall(widget.channelId!),
                        ),
                        onAccept: widget.onAcceptGroupCall,
                        onReject: widget.onRejectGroupCall,
                        onHangup: widget.onHangupGroupCall,
                        mediaSource: widget.mediaSource,
                        onMediaSourceChanged: widget.onMediaSourceChanged,
                      ),
                  ],
                ),
                if (_searchOpen) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search messages and people',
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: _searchController.clear,
                              icon: const Icon(Icons.close),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (_lastViewportHeight != constraints.maxHeight) {
                  _lastViewportHeight = constraints.maxHeight;
                  _queueScrollToLatest();
                }
                if (searching && visibleMessages.isEmpty) {
                  return const Center(
                    child: Text('No messages or people match this search.'),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  itemCount: visibleMessages.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      if (widget.conversationPreprompt.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: TextButton.icon(
                            onPressed: _editConversationPreprompt,
                            icon: const Icon(Icons.edit_note_outlined),
                            label: const Text('Add an agent brief'),
                          ),
                        );
                      }
                      return Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: palette.sidebar.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Agent brief',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 5),
                            Text(widget.conversationPreprompt),
                          ],
                        ),
                      );
                    }
                    index -= 1;
                    final m = visibleMessages[index];
                    final grouped = isWorkspaceMessageGroupedWithPrevious(
                      m,
                      index == 0 ? null : visibleMessages[index - 1],
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: KeyedSubtree(
                        key: ValueKey(m.id),
                        child: _WorkspaceMessageRow(
                          message: m,
                          authorName: _memberLabel(m.senderPubkey),
                          groupedWithPrevious: grouped,
                          isLocalSender: isWorkspaceLocalSender(
                            m.senderPubkey,
                            widget.localSenderIds,
                          ),
                          onThread: () => widget.onOpenThread(m),
                          threadReplyCount: widget.threadReplyCounts[m.id] ?? 0,
                          threadUnreadCount:
                              widget.threadUnreadCounts[m.id] ?? 0,
                          threadActivityLabel:
                              widget.threadActivityLabels[m.id],
                          onReact: (emoji) =>
                              unawaited(widget.onToggleReaction(m, emoji)),
                          onOpenAttachment: widget.onOpenAttachment,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.typingLabels.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.typingLabels.join('\n'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                WorkspaceComposer(
                  composer: widget.composer,
                  composerFocus: widget.composerFocus,
                  hintText: 'Message ${widget.title}',
                  mentionOptions: widget.mentionOptions,
                  onMentionSelected: widget.onMentionSelected,
                  onSend: widget.onSend,
                  onAttach: widget.onAttach,
                  voiceRecording: widget.voiceRecording,
                  voiceTranscribing: widget.voiceTranscribing,
                  voiceError: widget.voiceError,
                  onVoicePressed: widget.onVoicePressed,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.phase,
    required this.onStart,
    required this.onAccept,
    required this.onReject,
    required this.onHangup,
    required this.mediaSource,
    required this.onMediaSourceChanged,
  });

  final _CallPhase phase;
  final VoidCallback onStart;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangup;
  final _CallMediaSource mediaSource;
  final ValueChanged<_CallMediaSource> onMediaSourceChanged;

  @override
  Widget build(BuildContext context) => switch (phase) {
    _CallPhase.idle => IconButton(
      tooltip: 'Start call',
      onPressed: onStart,
      icon: const Icon(Icons.call_outlined),
    ),
    _CallPhase.incoming => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text('Preparing FIPS direct connection...'),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: onReject, child: const Text('Reject')),
            FilledButton(
              // FIPS traversal runs after its responder advert is published.
              // Do not make the Nostr answer signal wait for that operation.
              onPressed: onAccept,
              child: const Text('Answer'),
            ),
          ],
        ),
      ],
    ),
    _CallPhase.outgoing => TextButton.icon(
      onPressed: onHangup,
      icon: const Icon(Icons.call_end_outlined),
      label: const Text('Waiting for answer...'),
    ),
    _CallPhase.connecting => TextButton.icon(
      onPressed: onHangup,
      icon: const Icon(Icons.call_end_outlined),
      label: const Text('Establishing FIPS connection...'),
    ),
    _CallPhase.active => Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        _MediaSourceButton(
          source: _CallMediaSource.audioOnly,
          active: mediaSource == _CallMediaSource.audioOnly,
          onPressed: onMediaSourceChanged,
          icon: Icons.volume_up_outlined,
          label: 'Audio only',
        ),
        _MediaSourceButton(
          source: _CallMediaSource.camera,
          active: mediaSource == _CallMediaSource.camera,
          onPressed: onMediaSourceChanged,
          icon: Icons.videocam_outlined,
          label: 'Camera',
        ),
        _MediaSourceButton(
          source: _CallMediaSource.screen,
          active: mediaSource == _CallMediaSource.screen,
          onPressed: onMediaSourceChanged,
          icon: Icons.screen_share_outlined,
          label: 'Share screen',
        ),
        IconButton(
          tooltip: 'Hang up',
          onPressed: onHangup,
          icon: const Icon(Icons.call_end),
        ),
      ],
    ),
  };
}

class _MediaSourceButton extends StatelessWidget {
  const _MediaSourceButton({
    required this.source,
    required this.active,
    required this.onPressed,
    required this.icon,
    required this.label,
  });
  final _CallMediaSource source;
  final bool active;
  final ValueChanged<_CallMediaSource> onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: IconButton(
      onPressed: () => onPressed(source),
      style: IconButton.styleFrom(
        foregroundColor: active
            ? Theme.of(context).colorScheme.onPrimary
            : null,
        backgroundColor: active ? Theme.of(context).colorScheme.primary : null,
      ),
      icon: Icon(icon),
    ),
  );
}

class _WorkspaceMessageRow extends StatefulWidget {
  const _WorkspaceMessageRow({
    required this.message,
    required this.authorName,
    required this.groupedWithPrevious,
    required this.isLocalSender,
    required this.onThread,
    required this.onReact,
    required this.threadReplyCount,
    required this.threadUnreadCount,
    required this.onOpenAttachment,
    this.threadActivityLabel,
    this.showThreadAction = true,
  });
  final WorkspaceMessage message;
  final String authorName;
  final bool groupedWithPrevious;
  final bool isLocalSender;
  final VoidCallback onThread;
  final ValueChanged<String> onReact;
  final int threadReplyCount;
  final int threadUnreadCount;
  final Future<void> Function(BridgeAudioReference attachment) onOpenAttachment;
  final String? threadActivityLabel;
  final bool showThreadAction;
  @override
  State<_WorkspaceMessageRow> createState() => _WorkspaceMessageRowState();
}

class _WorkspaceMessageRowState extends State<_WorkspaceMessageRow> {
  bool _hovered = false;

  Future<void> _showMessageActions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            if (widget.showThreadAction)
              ListTile(
                leading: const Icon(Icons.reply_outlined),
                title: const Text('Reply in thread'),
                onTap: () => Navigator.pop(context, 'thread'),
              ),
            const Divider(height: 1),
            for (final emoji in ['👍', '❤️', '👀'])
              ListTile(
                leading: Text(emoji, style: const TextStyle(fontSize: 20)),
                title: Text('React with $emoji'),
                onTap: () => Navigator.pop(context, 'reaction:$emoji'),
              ),
          ],
        ),
      ),
    );
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: _messageText));
    } else if (action == 'thread') {
      widget.onThread();
    } else if (action?.startsWith('reaction:') == true) {
      widget.onReact(action!.substring('reaction:'.length));
    }
  }

  String get _messageText => isWorkspaceAgentSender(widget.message.senderPubkey)
      ? trimTrailingLineWhitespace(widget.message.body)
      : widget.message.body;

  @override
  Widget build(BuildContext context) {
    final isAgent = isWorkspaceAgentSender(widget.message.senderPubkey);
    final avatar = Semantics(
      label: isAgent ? '${widget.authorName}, agent' : widget.authorName,
      child: _WorkspaceFrogAvatar(
        identity: widget.message.senderPubkey,
        label: widget.authorName,
        radius: 18,
        bot: isAgent,
      ),
    );
    final compactMessage =
        _messageText.runes.length <= 48 && !_messageText.contains('\n');
    final messageContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.isLocalSender
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (!widget.groupedWithPrevious && !widget.isLocalSender)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.authorName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (isAgent) ...[
                const SizedBox(width: 6),
                Text(
                  'AGENT',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ],
            ],
          ),
        if (!widget.groupedWithPrevious && !widget.isLocalSender)
          const SizedBox(height: 3),
        if (_messageText.isNotEmpty)
          _WorkspaceMessageBody(
            text: _messageText,
            mentions: widget.message.mentions,
          ),
        Align(
          alignment: widget.isLocalSender
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _timestamp(context, grouped: true),
                if (widget.threadActivityLabel case final label?) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: label,
                    child: Icon(
                      Icons.more_horiz,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (widget.message.reactions.isNotEmpty)
          Wrap(
            spacing: 4,
            children: [
              for (final emoji
                  in widget.message.reactions
                      .map((reaction) => reaction.emoji)
                      .toSet())
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    '$emoji ${widget.message.reactions.where((reaction) => reaction.emoji == emoji).length}',
                  ),
                  onPressed: () => widget.onReact(emoji),
                ),
            ],
          ),
        if (widget.threadReplyCount > 0)
          TextButton.icon(
            onPressed: widget.onThread,
            icon: const Icon(Icons.forum_outlined, size: 16),
            label: Text(
              '${widget.threadReplyCount} ${widget.threadReplyCount == 1 ? 'reply' : 'replies'}${widget.threadUnreadCount > 0 ? ' · ${widget.threadUnreadCount} new' : ''}',
            ),
          ),
        for (final attachment in widget.message.attachments)
          TextButton.icon(
            onPressed: () => unawaited(widget.onOpenAttachment(attachment)),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: Text(attachment.name ?? 'Attachment'),
          ),
      ],
    );
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isLocalSender) ...[
          if (compactMessage)
            messageContent
          else
            Flexible(child: messageContent),
        ] else ...[
          widget.groupedWithPrevious ? const SizedBox(width: 36) : avatar,
          const SizedBox(width: 12),
          if (compactMessage)
            messageContent
          else
            Flexible(child: messageContent),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubbleWidth = math
            .min(constraints.maxWidth * 0.9, 820)
            .toDouble();
        final leadingWidth = widget.isLocalSender
            ? 0.0
            : widget.groupedWithPrevious
            ? 36.0
            : 48.0;
        final maxContentWidth = math
            .max(0, maxBubbleWidth - leadingWidth - 20)
            .toDouble();
        final bodyWidth = (TextPainter(
          text: TextSpan(
            text: _messageText,
            style: DefaultTextStyle.of(context).style,
          ),
          textDirection: Directionality.of(context),
        )..layout(maxWidth: maxContentWidth)).width;
        final authorWidth = !widget.groupedWithPrevious && !widget.isLocalSender
            ? (TextPainter(
                text: TextSpan(
                  text: widget.authorName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                textDirection: Directionality.of(context),
              )..layout(maxWidth: maxContentWidth)).width
            : 0.0;
        final contentWidth = math
            .max(math.max(bodyWidth, authorWidth), 48.0)
            .toDouble();
        final bubbleWidth = math
            .min(maxBubbleWidth, leadingWidth + contentWidth + 20)
            .toDouble();
        return Align(
          alignment: widget.isLocalSender
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: SizedBox(
            width: bubbleWidth,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                onLongPress: () => unawaited(_showMessageActions(context)),
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: widget.isLocalSender
                            ? Theme.of(context).colorScheme.primaryContainer
                            : isAgent
                            ? const Color(0xff12332d)
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: row,
                    ),
                    if (_hovered)
                      Positioned(
                        top: -8,
                        right: 0,
                        child: Material(
                          elevation: 3,
                          borderRadius: BorderRadius.circular(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Copy',
                                icon: const Icon(Icons.copy_outlined, size: 18),
                                onPressed: () => Clipboard.setData(
                                  ClipboardData(text: _messageText),
                                ),
                              ),
                              if (widget.showThreadAction)
                                IconButton(
                                  tooltip: 'Reply in thread',
                                  icon: const Icon(
                                    Icons.reply_outlined,
                                    size: 18,
                                  ),
                                  onPressed: widget.onThread,
                                ),
                              PopupMenuButton<String>(
                                tooltip: 'React',
                                icon: const Icon(
                                  Icons.add_reaction_outlined,
                                  size: 18,
                                ),
                                onSelected: widget.onReact,
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: '👍', child: Text('👍')),
                                  PopupMenuItem(value: '❤️', child: Text('❤️')),
                                  PopupMenuItem(value: '👀', child: Text('👀')),
                                ],
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'More',
                                icon: const Icon(Icons.more_horiz, size: 18),
                                onSelected: (value) {
                                  if (value == 'copy') {
                                    Clipboard.setData(
                                      ClipboardData(text: _messageText),
                                    );
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'copy',
                                    child: Text('Copy text'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _timestamp(BuildContext context, {bool grouped = false}) => Text(
    DateTime.fromMillisecondsSinceEpoch(
      widget.message.createdAt * 1000,
    ).toLocal().toString().substring(11, 16),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      fontSize: 10,
      color: Theme.of(
        context,
      ).colorScheme.onSurface.withValues(alpha: grouped ? 0.42 : 0.52),
    ),
  );
}

/// A stable frog tint keeps participants recognizable without storing UI state.
class _WorkspaceFrogAvatar extends StatelessWidget {
  const _WorkspaceFrogAvatar({
    required this.identity,
    required this.label,
    this.radius = 18,
    this.bot = false,
  });

  final String identity;
  final String label;
  final double radius;
  final bool bot;

  static const _colors = [
    (Color(0xff78b9df), Color(0xff173d5c)),
    (Color(0xffdfb777), Color(0xff593914)),
    (Color(0xffdf8582), Color(0xff5f2027)),
    (Color(0xff87c8a0), Color(0xff1d563a)),
    (Color(0xffaa96df), Color(0xff38295e)),
    (Color(0xffdf91bc), Color(0xff612546)),
    (Color(0xff79c9c9), Color(0xff155556)),
  ];

  @override
  Widget build(BuildContext context) {
    final colors =
        _colors[workspaceAvatarColorIndex(identity, label, _colors.length)];
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors.$1,
      child: bot
          ? CustomPaint(
              size: Size.square(radius * 1.6),
              painter: _WorkspaceBotAvatarPainter(colors.$2),
            )
          : ColorFiltered(
              colorFilter: ColorFilter.mode(colors.$2, BlendMode.srcIn),
              child: Image.asset(
                'assets/branding/ribbet-mark.png',
                width: radius * 1.85,
                height: radius * 1.85,
                filterQuality: FilterQuality.medium,
              ),
            ),
    );
  }
}

class _WorkspaceBotAvatarPainter extends CustomPainter {
  const _WorkspaceBotAvatarPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 32;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;

    canvas.drawLine(
      Offset(16 * scale, 8 * scale),
      Offset(16 * scale, 4 * scale),
      stroke,
    );
    canvas.drawCircle(Offset(16 * scale, 3 * scale), 1.1 * scale, fill);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(6 * scale, 8 * scale, 20 * scale, 18 * scale),
        Radius.circular(4 * scale),
      ),
      stroke,
    );
    canvas.drawLine(
      Offset(3.5 * scale, 14 * scale),
      Offset(6 * scale, 14 * scale),
      stroke,
    );
    canvas.drawLine(
      Offset(26 * scale, 14 * scale),
      Offset(28.5 * scale, 14 * scale),
      stroke,
    );
    canvas.drawCircle(Offset(12 * scale, 15 * scale), 1.15 * scale, fill);
    canvas.drawCircle(Offset(20 * scale, 15 * scale), 1.15 * scale, fill);
    canvas.drawLine(
      Offset(12 * scale, 21 * scale),
      Offset(20 * scale, 21 * scale),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _WorkspaceBotAvatarPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _WorkspaceMessageBody extends StatefulWidget {
  const _WorkspaceMessageBody({required this.text, required this.mentions});
  final String text;
  final List<WorkspaceMention> mentions;

  @override
  State<_WorkspaceMessageBody> createState() => _WorkspaceMessageBodyState();
}

class _WorkspaceMessageBodyState extends State<_WorkspaceMessageBody> {
  static const _collapsedLines = 20;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(context).style;
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        textDirection: Directionality.of(context),
        maxLines: _collapsedLines,
      )..layout(maxWidth: constraints.maxWidth);
      final truncated = painter.didExceedMaxLines;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WorkspaceMessageText(
            text: widget.text,
            mentions: widget.mentions,
            maxLines: truncated && !_expanded ? _collapsedLines : null,
          ),
          if (truncated)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 32),
              ),
              child: Text(_expanded ? 'Hide' : 'Show all'),
            ),
        ],
      );
    },
  );
}

class _WorkspaceMessageText extends StatelessWidget {
  const _WorkspaceMessageText({
    required this.text,
    required this.mentions,
    this.maxLines,
  });
  final String text;
  final List<WorkspaceMention> mentions;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final recognizedMentions = {
      for (final mention in mentions) mention.label: mention,
    };
    final labels = recognizedMentions.keys.toList()
      ..sort((left, right) => right.length.compareTo(left.length));
    final patterns = [
      r'https?://[^\s<>\]\)]+',
      r'@\[([^\]\r\n]+)\]\((?:member|agent):[^\)\s]+\)',
      r'\*\*[^*\r\n]+\*\*',
      r'`[^`\r\n]+`',
      r'(?<!\w)(?:[~\w.-]+/)+[~\w.-]+',
      if (labels.isNotEmpty)
        '(?<!\\w)@(?:${labels.map(RegExp.escape).join('|')})(?![\\w-])',
    ];
    final matches = RegExp(patterns.join('|')).allMatches(text);
    if (matches.isEmpty) {
      return maxLines == null
          ? SelectableText(text)
          : Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }
    final style = DefaultTextStyle.of(context).style;
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in matches) {
      if (match.start > offset) {
        spans.add(TextSpan(text: text.substring(offset, match.start)));
      }
      final mention = match.group(1);
      final token = match.group(0)!;
      final recognizedMention =
          mention ??
          (token.startsWith('@')
              ? recognizedMentions[token.substring(1)]?.label
              : null);
      if (recognizedMention != null) {
        spans.add(
          TextSpan(
            text: '@$recognizedMention',
            style: style.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
            ),
          ),
        );
      } else {
        if (token.startsWith('http://') || token.startsWith('https://')) {
          spans.add(
            TextSpan(
              text: token,
              style: style.copyWith(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => unawaited(_openWorkspaceLink(context, token)),
            ),
          );
          offset = match.end;
          continue;
        }
        if (token.startsWith('**')) {
          spans.add(
            TextSpan(
              text: token.substring(2, token.length - 2),
              style: style.copyWith(fontWeight: FontWeight.bold),
            ),
          );
          offset = match.end;
          continue;
        }
        spans.add(
          TextSpan(
            text: token.startsWith('`')
                ? token.substring(1, token.length - 1)
                : token,
            style: style.copyWith(
              fontSize: (style.fontSize ?? 14) - 1,
              color: Theme.of(context).colorScheme.secondary,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
            ),
          ),
        );
      }
      offset = match.end;
    }
    if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
    final span = TextSpan(style: style, children: spans);
    return maxLines == null
        ? SelectableText.rich(span)
        : RichText(
            text: span,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          );
  }
}

Future<void> _openWorkspaceLink(BuildContext context, String value) async {
  final uri = Uri.tryParse(value);
  if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
      context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not open link')));
  }
}

class _WorkspaceContext extends StatelessWidget {
  const _WorkspaceContext({
    super.key,
    required this.message,
    required this.replies,
    required this.title,
    required this.composer,
    required this.composerFocus,
    required this.mentionOptions,
    required this.onMentionSelected,
    required this.onSend,
    required this.onAttach,
    required this.voiceRecording,
    required this.voiceTranscribing,
    required this.voiceError,
    required this.onVoicePressed,
    required this.alsoSendToMain,
    required this.onAlsoSendToMainChanged,
    required this.onClose,
    required this.onToggleReaction,
    required this.onOpenAttachment,
    required this.ownPubkey,
    required this.localSenderIds,
    required this.displayName,
    required this.memberAliases,
    required this.memberNames,
    required this.agents,
    required this.typingLabels,
    required this.fullWindow,
    required this.onToggleFullWindow,
  });
  final WorkspaceMessage? message;
  final List<WorkspaceMessage> replies;
  final String title;
  final TextEditingController composer;
  final FocusNode composerFocus;
  final List<WorkspaceMention> mentionOptions;
  final ValueChanged<WorkspaceMention> onMentionSelected;
  final VoidCallback onSend;
  final Future<void> Function() onAttach;
  final bool voiceRecording;
  final bool voiceTranscribing;
  final String? voiceError;
  final VoidCallback onVoicePressed;
  final bool alsoSendToMain;
  final ValueChanged<bool> onAlsoSendToMainChanged;
  final VoidCallback onClose;
  final Future<void> Function(WorkspaceMessage message, String emoji)
  onToggleReaction;
  final Future<void> Function(BridgeAudioReference attachment) onOpenAttachment;
  final String ownPubkey;
  final Set<String> localSenderIds;
  final String displayName;
  final Map<String, String> memberAliases;
  final Map<String, String> memberNames;
  final List<WorkspaceAgent> agents;
  final List<String> typingLabels;
  final bool fullWindow;
  final VoidCallback onToggleFullWindow;

  String _memberLabel(String pubkey) {
    if (pubkey.startsWith('agent:')) {
      final id = pubkey.substring('agent:'.length);
      for (final agent in agents) {
        if (agent.id == id) return agent.name;
      }
      return 'Agent';
    }
    if (pubkey == ownPubkey) {
      return memberNames[pubkey] ?? (displayName.isEmpty ? 'You' : displayName);
    }
    return memberAliases[pubkey] ??
        memberNames[pubkey] ??
        compactIdentifier(pubkey);
  }

  Widget _messageRow(
    WorkspaceMessage message, {
    required bool groupedWithPrevious,
  }) => _WorkspaceMessageRow(
    message: message,
    authorName: _memberLabel(message.senderPubkey),
    groupedWithPrevious: groupedWithPrevious,
    isLocalSender: isWorkspaceLocalSender(message.senderPubkey, localSenderIds),
    onThread: () {},
    onReact: (emoji) => unawaited(onToggleReaction(message, emoji)),
    threadReplyCount: 0,
    threadUnreadCount: 0,
    onOpenAttachment: onOpenAttachment,
    showThreadAction: false,
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: message == null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Conversation details',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 18),
              const _ContextLine(
                Icons.people_outline,
                'Workspace members appear in People',
              ),
              const _ContextLine(Icons.push_pin_outlined, 'No pinned messages'),
              const _ContextLine(
                Icons.folder_outlined,
                'Shared files will appear here',
              ),
              const Spacer(),
              Text(
                'Select a reply count to open a thread.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Thread',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: fullWindow
                        ? 'Return to conversation'
                        : 'Open thread full-window',
                    onPressed: onToggleFullWindow,
                    icon: Icon(
                      fullWindow ? Icons.close_fullscreen : Icons.open_in_full,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close thread',
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _messageRow(message!, groupedWithPrevious: false),
                    const SizedBox(height: 16),
                    Text(
                      '${replies.length} ${replies.length == 1 ? 'reply' : 'replies'}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    for (var index = 0; index < replies.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _messageRow(
                          replies[index],
                          groupedWithPrevious:
                              index > 0 &&
                              isWorkspaceMessageGroupedWithPrevious(
                                replies[index],
                                replies[index - 1],
                              ),
                        ),
                      ),
                  ],
                ),
              ),
              if (typingLabels.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    typingLabels.join('\n'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: alsoSendToMain,
                onChanged: (value) => onAlsoSendToMainChanged(value ?? false),
                title: const Text('Also send to main'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              WorkspaceComposer(
                composer: composer,
                composerFocus: composerFocus,
                hintText: 'Reply in thread',
                mentionOptions: mentionOptions,
                onMentionSelected: onMentionSelected,
                onSend: onSend,
                onAttach: onAttach,
                voiceRecording: voiceRecording,
                voiceTranscribing: voiceTranscribing,
                voiceError: voiceError,
                onVoicePressed: onVoicePressed,
              ),
            ],
          ),
  );
}

class _WorkspaceSidePanel extends StatelessWidget {
  const _WorkspaceSidePanel({
    required this.thread,
    required this.files,
    required this.showFiles,
    required this.onShowThread,
    required this.onShowFiles,
  });

  final Widget? thread;
  final Widget? files;
  final bool showFiles;
  final VoidCallback onShowThread;
  final VoidCallback onShowFiles;

  @override
  Widget build(BuildContext context) {
    final hasTabs = thread != null && files != null;
    final content = showFiles && files != null ? files! : thread!;
    if (!hasTabs) return content;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              _sideTab(
                context,
                label: 'Thread',
                icon: Icons.forum_outlined,
                selected: !showFiles,
                onPressed: onShowThread,
              ),
              const SizedBox(width: 6),
              _sideTab(
                context,
                label: 'Files',
                icon: Icons.folder_open_outlined,
                selected: showFiles,
                onPressed: onShowFiles,
              ),
            ],
          ),
        ),
        const Divider(height: 16),
        Expanded(child: content),
      ],
    );
  }

  Widget _sideTab(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onPressed,
  }) => TextButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
    style: TextButton.styleFrom(
      foregroundColor: selected
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant,
      backgroundColor: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
    ),
  );
}

class _WorkspaceFilesPanel extends StatelessWidget {
  const _WorkspaceFilesPanel({
    required this.result,
    required this.preview,
    required this.onBrowse,
    required this.onUp,
    required this.onReadFile,
    required this.onFullWindow,
    required this.onCloseFullWindow,
    required this.onClosePreview,
    required this.fullWindow,
  });

  final FileBrowserResult result;
  final FileContentResult? preview;
  final Future<void> Function(String path) onBrowse;
  final Future<void> Function() onUp;
  final Future<void> Function(String path) onReadFile;
  final VoidCallback onFullWindow;
  final VoidCallback onCloseFullWindow;
  final VoidCallback onClosePreview;
  final bool fullWindow;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                preview?.path ??
                    (result.directory.isEmpty
                        ? 'Repository files'
                        : result.directory),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            if (preview != null)
              IconButton(
                tooltip: 'Back to files',
                onPressed: onClosePreview,
                icon: const Icon(Icons.arrow_back_outlined),
              ),
            if (preview == null && result.directory.isNotEmpty)
              IconButton(
                tooltip: 'Up folder',
                onPressed: () => unawaited(onUp()),
                icon: const Icon(Icons.drive_folder_upload_outlined),
              ),
            IconButton(
              tooltip: fullWindow
                  ? 'Return to conversation'
                  : 'Open files full-window',
              onPressed: fullWindow ? onCloseFullWindow : onFullWindow,
              icon: Icon(
                fullWindow ? Icons.close_fullscreen : Icons.open_in_full,
              ),
            ),
          ],
        ),
      ),
      if (preview?.truncated == true)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text('Large file: showing the first 40,000 characters.'),
        )
      else if (result.truncated)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'This folder has many items. Refine with its subfolders.',
          ),
        ),
      const Divider(height: 1),
      Expanded(
        child: preview == null
            ? ListView.separated(
                itemCount: result.entries.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 56),
                itemBuilder: (context, index) {
                  final entry = result.entries[index];
                  return ListTile(
                    leading: Icon(
                      entry.isDirectory
                          ? Icons.folder_outlined
                          : Icons.description_outlined,
                    ),
                    title: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Icon(
                      entry.isDirectory
                          ? Icons.chevron_right
                          : Icons.open_in_new,
                      size: 20,
                    ),
                    onTap: () => unawaited(
                      entry.isDirectory
                          ? onBrowse(entry.path)
                          : onReadFile(entry.path),
                    ),
                  );
                },
              )
            : SelectionArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    preview!.content,
                    style: const TextStyle(height: 1.45),
                  ),
                ),
              ),
      ),
    ],
  );
}

class _SelectMentionIntent extends Intent {
  const _SelectMentionIntent();
}

class _InsertComposerNewlineIntent extends Intent {
  const _InsertComposerNewlineIntent();
}

class _DeleteComposerWordIntent extends Intent {
  const _DeleteComposerWordIntent();
}

class _WorkspaceMentionOverlay extends StatelessWidget {
  const _WorkspaceMentionOverlay({
    required this.mentionOptions,
    required this.onMentionSelected,
    required this.child,
  });

  final List<WorkspaceMention> mentionOptions;
  final ValueChanged<WorkspaceMention> onMentionSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final height = (mentionOptions.length * 56.0).clamp(56.0, 144.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (mentionOptions.isNotEmpty)
          SizedBox(
            height: height,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final mention in mentionOptions)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        mention.kind == 'agent'
                            ? Icons.smart_toy_outlined
                            : Icons.person_outline,
                      ),
                      title: Text('@${mention.label}'),
                      subtitle: Text(
                        mention.kind == 'agent' ? 'Agent' : 'Member',
                      ),
                      onTap: () => onMentionSelected(mention),
                    ),
                ],
              ),
            ),
          ),
        child,
      ],
    );
  }
}

class WorkspaceComposer extends StatelessWidget {
  const WorkspaceComposer({
    super.key,
    required this.composer,
    required this.composerFocus,
    required this.hintText,
    required this.mentionOptions,
    required this.onMentionSelected,
    required this.onSend,
    required this.onAttach,
    this.voiceRecording = false,
    this.voiceTranscribing = false,
    this.voiceError,
    this.onVoicePressed,
  });

  final TextEditingController composer;
  final FocusNode composerFocus;
  final String hintText;
  final List<WorkspaceMention> mentionOptions;
  final ValueChanged<WorkspaceMention> onMentionSelected;
  final VoidCallback onSend;
  final Future<void> Function() onAttach;
  final bool voiceRecording;
  final bool voiceTranscribing;
  final String? voiceError;
  final VoidCallback? onVoicePressed;

  bool _isDesktop(TargetPlatform platform) => switch (platform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    _ => false,
  };

  void _sendOnSubmit(bool canSend) {
    if (composer.value.composing.isValid &&
        !composer.value.composing.isCollapsed) {
      return;
    }
    if (canSend) {
      onSend();
    }
  }

  void _insertNewline() {
    final selection = composer.selection;
    final start = selection.isValid ? selection.start : composer.text.length;
    final end = selection.isValid ? selection.end : start;
    composer.value = composer.value.copyWith(
      text: composer.text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (composerFocus.canRequestFocus) composerFocus.requestFocus();
    });
  }

  void _deletePreviousWord() {
    final selection = composer.selection;
    final end = selection.isValid ? selection.end : composer.text.length;
    var start = selection.isValid ? selection.start : end;
    if (start == end) {
      while (start > 0 && RegExp(r'\s').hasMatch(composer.text[start - 1])) {
        start--;
      }
      while (start > 0 && !RegExp(r'\s').hasMatch(composer.text[start - 1])) {
        start--;
      }
    }
    composer.value = composer.value.copyWith(
      text: composer.text.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (composerFocus.canRequestFocus) composerFocus.requestFocus();
    });
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: composer,
    builder: (context, value, _) {
      final canSend = value.text.trim().isNotEmpty;
      final desktop = _isDesktop(Theme.of(context).platform);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WorkspaceMentionOverlay(
            mentionOptions: mentionOptions,
            onMentionSelected: onMentionSelected,
            child: Shortcuts(
              shortcuts: {
                const SingleActivator(LogicalKeyboardKey.enter, alt: true):
                    const _InsertComposerNewlineIntent(),
                const SingleActivator(LogicalKeyboardKey.backspace, alt: true):
                    const _DeleteComposerWordIntent(),
                if (mentionOptions.length == 1)
                  const SingleActivator(LogicalKeyboardKey.tab):
                      const _SelectMentionIntent(),
              },
              child: Actions(
                actions: {
                  _SelectMentionIntent: CallbackAction<_SelectMentionIntent>(
                    onInvoke: (_) {
                      onMentionSelected(mentionOptions.single);
                      return null;
                    },
                  ),
                  _InsertComposerNewlineIntent:
                      CallbackAction<_InsertComposerNewlineIntent>(
                        onInvoke: (_) {
                          _insertNewline();
                          return null;
                        },
                      ),
                  _DeleteComposerWordIntent:
                      CallbackAction<_DeleteComposerWordIntent>(
                        onInvoke: (_) {
                          _deletePreviousWord();
                          return null;
                        },
                      ),
                },
                child: TextField(
                  controller: composer,
                  focusNode: composerFocus,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: desktop
                      ? TextInputAction.send
                      : TextInputAction.newline,
                  onSubmitted: desktop
                      ? (_) {
                          if (HardwareKeyboard.instance.isShiftPressed ||
                              HardwareKeyboard.instance.isAltPressed) {
                            _insertNewline();
                          } else if (mentionOptions.length == 1) {
                            onMentionSelected(mentionOptions.single);
                          } else {
                            _sendOnSubmit(canSend);
                          }
                        }
                      : null,
                  // Keep desktop focus in this field after a submit action.
                  onEditingComplete: () {},
                  decoration: InputDecoration(
                    hintText: hintText,
                    filled: true,
                    fillColor:
                        Theme.of(
                          context,
                        ).extension<_WorkspacePalette>()?.composer ??
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    prefixIcon: IconButton(
                      tooltip: 'Attach file',
                      onPressed: () => unawaited(onAttach()),
                      icon: const Icon(Icons.attach_file),
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onVoicePressed != null)
                          IconButton(
                            tooltip: voiceTranscribing
                                ? 'Transcribing voice'
                                : voiceRecording
                                ? 'Stop recording and transcribe'
                                : 'Record voice to text',
                            onPressed: voiceTranscribing
                                ? null
                                : onVoicePressed,
                            icon: voiceTranscribing
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    voiceRecording
                                        ? Icons.stop_circle_outlined
                                        : Icons.mic_none_outlined,
                                  ),
                          ),
                        IconButton(
                          tooltip: canSend
                              ? desktop
                                    ? 'Send message (Enter)'
                                    : 'Send message'
                              : 'Write a message to send',
                          onPressed: canSend ? onSend : null,
                          icon: const Icon(Icons.send),
                        ),
                      ],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _ContextLine extends StatelessWidget {
  const _ContextLine(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Icon(icon, size: 19),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _AgentsPage extends StatefulWidget {
  const _AgentsPage({
    super.key,
    required this.workspace,
    required this.ownPubkey,
    required this.workspaceRevision,
    required this.onRequest,
    required this.onLoadOpenCodeModels,
    required this.initialFolderChoices,
    required this.onLoadFolders,
    required this.onOpenConversation,
  });
  final WorkspaceState workspace;
  final String ownPubkey;
  final ValueListenable<int> workspaceRevision;
  final Future<void> Function(Map<String, Object?> request) onRequest;
  final Future<List<_OpenCodeModelChoice>> Function() onLoadOpenCodeModels;
  final List<RepoChoice> initialFolderChoices;
  final Future<List<RepoChoice>> Function(String? path) onLoadFolders;
  final Future<void> Function(WorkspaceAgent agent) onOpenConversation;
  @override
  State<_AgentsPage> createState() => _AgentsPageState();
}

class _AgentsPageState extends State<_AgentsPage> {
  String? _selectedAgentId;
  Timer? _runtimeRefresh;
  static const _presets = [
    (
      'Builder',
      'Build and implement focused changes.',
      Icons.handyman_outlined,
    ),
    (
      'Reviewer',
      'Review changes for bugs, risk, and test gaps.',
      Icons.fact_check_outlined,
    ),
    (
      'Researcher',
      'Investigate options and report concise evidence.',
      Icons.travel_explore_outlined,
    ),
    (
      'Coordinator',
      'Break work down and coordinate the next steps.',
      Icons.account_tree_outlined,
    ),
  ];
  @override
  void initState() {
    super.initState();
    unawaited(widget.onRequest({'action': 'list_agents'}));
    _runtimeRefresh = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(widget.onRequest({'action': 'list_agents'}));
    });
  }

  @override
  void dispose() {
    _runtimeRefresh?.cancel();
    super.dispose();
  }

  Future<void> _createPreset((String, String, IconData) preset) =>
      widget.onRequest({
        'action': 'create_agent',
        'agent_name': preset.$1,
        'agent_role': preset.$2,
        'agent_preset': preset.$1.toLowerCase(),
        'agent_skills': const <String>[],
      });
  Future<void> _createCustom() async {
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _AgentEditorDialog(
        onLoadOpenCodeModels: widget.onLoadOpenCodeModels,
        initialFolderChoices: widget.initialFolderChoices,
        onLoadFolders: widget.onLoadFolders,
      ),
    );
    if (result != null) {
      await widget.onRequest({'action': 'create_agent', ...result});
    }
  }

  Future<void> _renameAgent(WorkspaceAgent agent) async {
    final controller = TextEditingController(text: agent.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename agent'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty && name.trim() != agent.name) {
      await widget.onRequest({
        'action': 'rename_agent',
        'agent_id': agent.id,
        'agent_name': name.trim(),
      });
    }
  }

  Future<void> _deleteAgent(WorkspaceAgent agent) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete agent?'),
        content: Text(
          'Delete ${agent.name} and remove it from every channel and direct message?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.onRequest({'action': 'delete_agent', 'agent_id': agent.id});
    }
  }

  Future<void> _editConversationScope(
    WorkspaceAgent agent,
    WorkspaceConversationAgent membership,
  ) async {
    final scope = await showDialog<List<String>>(
      context: context,
      builder: (_) => _FolderScopeDialog(
        initialSelected: membership.folderScope,
        onLoadChoices: () => widget.onLoadFolders(null),
      ),
    );
    if (scope == null) return;
    await widget.onRequest({
      'action': 'add_conversation_agent',
      'agent_id': agent.id,
      'folder_scope': scope,
      if (membership.channelId != null) 'channel_id': membership.channelId,
      if (membership.channelId == null)
        'recipient_pubkey': _directConversationPeer(membership),
    });
  }

  @override
  Widget build(BuildContext context) {
    WorkspaceAgent? selected;
    for (final agent in widget.workspace.agents) {
      if (agent.id == _selectedAgentId) {
        selected = agent;
        break;
      }
    }
    if (selected != null) {
      return _agentDetail(selected);
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Agents',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Agents receive a dedicated OpenCode session in this workspace when created.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _createCustom,
            icon: const Icon(Icons.add),
            label: const Text('Custom agent'),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Start with a role',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final preset in _presets)
              SizedBox(
                width: 170,
                child: OutlinedButton.icon(
                  onPressed: () => _createPreset(preset),
                  icon: Icon(preset.$3),
                  label: Text(preset.$1),
                ),
              ),
          ],
        ),
        const SizedBox(height: 28),
        Text('Your agents', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ValueListenableBuilder<int>(
          valueListenable: widget.workspaceRevision,
          builder: (context, _, _) => Column(
            children: [
              if (widget.workspace.agents.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text('Add a preset or create a custom agent.'),
                  ),
                ),
              for (final agent in widget.workspace.agents) _agentCard(agent),
            ],
          ),
        ),
      ],
    );
  }

  Widget _agentCard(WorkspaceAgent agent) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      child: Icon(
        agent.preset == 'reviewer'
            ? Icons.fact_check
            : Icons.smart_toy_outlined,
      ),
    ),
    title: Text(agent.name),
    subtitle: Text(
      '${_availabilityLabel(agent)} · ${agent.scopeMemoryBytes == null ? 'No active scope' : _formatAgentBytes(agent.scopeMemoryBytes!)}\n${agent.role}\n${agent.sessionStatus == 'ready' ? 'OpenCode ready' : agent.sessionError ?? 'OpenCode provisioning failed'}',
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    ),
    isThreeLine: true,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _availabilityIcon(agent),
          color: _availabilityColor(context, agent),
        ),
        const Icon(Icons.chevron_right),
      ],
    ),
    onTap: () => setState(() => _selectedAgentId = agent.id),
  );

  Widget _agentDetail(WorkspaceAgent agent) {
    final theme = Theme.of(context);
    final memberships = widget.workspace.conversationAgents
        .where((membership) => membership.agentId == agent.id)
        .toList(growable: false);
    final tokens = agent.inputTokens == null || agent.outputTokens == null
        ? 'Unavailable'
        : '${_formatTokenCount(agent.inputTokens! + agent.outputTokens!)} total';
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _selectedAgentId = null),
            icon: const Icon(Icons.arrow_back),
            label: const Text('All agents'),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 28,
              child: Icon(
                agent.preset == 'reviewer'
                    ? Icons.fact_check
                    : Icons.smart_toy_outlined,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agent.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(agent.role, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Chip(
                    avatar: Icon(_availabilityIcon(agent), size: 18),
                    label: Text(_availabilityLabel(agent)),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _renameAgent(agent),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Rename agent',
            ),
          ],
        ),
        if (agent.sessionStatus != 'ready' && agent.sessionError != null) ...[
          const SizedBox(height: 16),
          Text(agent.sessionError!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 28),
        Text('Runtime', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _agentDetailRow(
          Icons.memory_outlined,
          'Memory',
          agent.scopeMemoryBytes == null
              ? 'No active workload'
              : _formatAgentBytes(agent.scopeMemoryBytes!),
        ),
        _agentDetailRow(
          Icons.speed_outlined,
          'CPU time',
          agent.scopeCpuUsageNsec == null
              ? 'Unavailable'
              : _formatAgentCpuTime(agent.scopeCpuUsageNsec!),
        ),
        _agentDetailRow(
          Icons.account_tree_outlined,
          'Tasks',
          agent.scopeTaskCount?.toString() ?? 'Unavailable',
        ),
        _agentDetailRow(
          Icons.play_circle_outline,
          'Work started',
          _formatTimestamp(agent.scopeStartedAt),
        ),
        const SizedBox(height: 20),
        Text('Activity', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _agentDetailRow(
          Icons.schedule_outlined,
          'Initialized',
          _formatTimestamp(agent.initializedAt),
        ),
        _agentDetailRow(Icons.data_usage_outlined, 'Tokens used', tokens),
        if (agent.inputTokens != null && agent.outputTokens != null)
          Padding(
            padding: const EdgeInsets.only(left: 52, bottom: 8),
            child: Text(
              '${_formatTokenCount(agent.inputTokens!)} input · ${_formatTokenCount(agent.outputTokens!)} output',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 20),
        Text('Conversations', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        if (memberships.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.forum_outlined),
            title: Text('Not added to a conversation'),
            subtitle: Text('Add this agent from a channel or direct message.'),
          ),
        for (final membership in memberships)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              membership.channelId == null
                  ? Icons.forum_outlined
                  : Icons.tag_outlined,
            ),
            title: Text(_conversationLabel(membership)),
            subtitle: membership.folderScope.isEmpty
                ? const Text('No folder scope selected')
                : Text('Folders: ${membership.folderScope.join(', ')}'),
            trailing: TextButton(
              onPressed: () => _editConversationScope(agent, membership),
              child: const Text('Edit folders'),
            ),
            onTap: () => _editConversationScope(agent, membership),
          ),
        const SizedBox(height: 20),
        Text('Configuration', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _AgentDetailConfiguration(
          key: ValueKey(agent.id),
          agent: agent,
          onLoadOpenCodeModels: widget.onLoadOpenCodeModels,
          initialFolderChoices: widget.initialFolderChoices,
          onLoadFolders: widget.onLoadFolders,
          onSave: (profile) => widget.onRequest({
            'action': 'update_agent_profile',
            'agent_id': agent.id,
            ...profile,
          }),
        ),
        if (agent.traits.isNotEmpty || agent.skills.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Capabilities', style: theme.textTheme.titleMedium),
          if (agent.traits.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(agent.traits),
          ],
          if (agent.skills.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final skill in agent.skills) Chip(label: Text(skill)),
              ],
            ),
          ],
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => widget.onRequest({
                'action': 'restart_agent_session',
                'agent_id': agent.id,
              }),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Restart session'),
            ),
            TextButton.icon(
              onPressed: () => _deleteAgent(agent),
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              label: Text(
                'Delete agent',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: agent.sessionStatus == 'ready'
              ? () => widget.onOpenConversation(agent)
              : null,
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open session'),
        ),
      ],
    );
  }

  String _availabilityLabel(WorkspaceAgent agent) {
    switch (agent.availability) {
      case 'busy':
        return 'Working';
      case 'stuck':
        return 'Stuck';
      case 'errored':
        return 'Error';
      case 'unavailable':
        return 'Unavailable';
      default:
        return agent.sessionStatus == 'ready'
            ? 'Available'
            : 'Session unavailable';
    }
  }

  IconData _availabilityIcon(WorkspaceAgent agent) {
    switch (agent.availability) {
      case 'busy':
        return Icons.sync;
      case 'stuck':
        return Icons.hourglass_top_outlined;
      case 'errored':
      case 'unavailable':
        return Icons.error_outline;
      default:
        return Icons.check_circle_outline;
    }
  }

  Color _availabilityColor(BuildContext context, WorkspaceAgent agent) {
    final colors = Theme.of(context).colorScheme;
    switch (agent.availability) {
      case 'busy':
        return colors.primary;
      case 'stuck':
        return colors.tertiary;
      case 'errored':
      case 'unavailable':
        return colors.error;
      default:
        return colors.secondary;
    }
  }

  String _formatAgentBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatAgentCpuTime(int nanoseconds) {
    final seconds = nanoseconds ~/ Duration.microsecondsPerSecond ~/ 1000;
    if (seconds < 60) return '${seconds}s';
    return '${seconds ~/ 60}m ${seconds % 60}s';
  }

  Widget _agentDetailRow(IconData icon, String label, String value) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(label),
    subtitle: SelectableText(value),
  );

  String _conversationLabel(WorkspaceConversationAgent membership) {
    if (membership.channelId case final channelId?) {
      return '# ${widget.workspace.channelName(channelId) ?? channelId}';
    }
    return 'Direct message: ${_memberLabel(membership.memberPubkey)} and ${_memberLabel(membership.peerPubkey)}';
  }

  String _memberLabel(String? pubkey) => pubkey == null
      ? 'Unknown member'
      : widget.workspace.memberNames[pubkey] ?? compactIdentifier(pubkey);

  String? _directConversationPeer(WorkspaceConversationAgent membership) {
    final member = membership.memberPubkey;
    final peer = membership.peerPubkey;
    if (member == null || peer == null) return null;
    return member == widget.ownPubkey ? peer : member;
  }

  String _formatTimestamp(int? seconds) {
    if (seconds == null || seconds <= 0) return 'Unavailable';
    return DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
    ).toLocal().toString().substring(0, 16);
  }

  String _formatTokenCount(int value) {
    if (value < 1000) {
      return '$value';
    }
    if (value < 1000000) {
      return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}K';
    }
    return '${(value / 1000000).toStringAsFixed(value % 1000000 == 0 ? 0 : 1)}M';
  }
}

class _AgentDetailConfiguration extends StatefulWidget {
  const _AgentDetailConfiguration({
    super.key,
    required this.agent,
    required this.onLoadOpenCodeModels,
    required this.initialFolderChoices,
    required this.onLoadFolders,
    required this.onSave,
  });

  final WorkspaceAgent agent;
  final Future<List<_OpenCodeModelChoice>> Function() onLoadOpenCodeModels;
  final List<RepoChoice> initialFolderChoices;
  final Future<List<RepoChoice>> Function(String? path) onLoadFolders;
  final Future<void> Function(Map<String, Object?> profile) onSave;

  @override
  State<_AgentDetailConfiguration> createState() =>
      _AgentDetailConfigurationState();
}

class _AgentDetailConfigurationState extends State<_AgentDetailConfiguration> {
  final _profileFieldsKey = GlobalKey<_OpenCodeProfileFieldsState>();
  late final _openCodeAgent = TextEditingController(
    text: widget.agent.openCodeAgent ?? '',
  );
  late final _workdir = TextEditingController(text: widget.agent.workdir ?? '');
  late bool _restartOnFailure = widget.agent.restartOnFailure;
  bool _saving = false;

  @override
  void dispose() {
    _openCodeAgent.dispose();
    _workdir.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final model = _profileFieldsKey.currentState?.selectedModel;
    try {
      await widget.onSave({
        if (model != null) 'opencode_provider_id': model.providerId,
        if (model != null) 'opencode_provider_name': model.providerName,
        if (model != null) 'opencode_model_id': model.modelId,
        if (model != null) 'opencode_model_name': model.modelName,
        if (_openCodeAgent.text.trim().isNotEmpty)
          'opencode_agent': _openCodeAgent.text.trim(),
        if (_workdir.text.trim().isNotEmpty)
          'agent_workdir': _workdir.text.trim(),
        'restart_agent_session_on_failure': _restartOnFailure,
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _cancel() {
    if (_saving) return;
    setState(() {
      _openCodeAgent.text = widget.agent.openCodeAgent ?? '';
      _workdir.text = widget.agent.workdir ?? '';
      _restartOnFailure = widget.agent.restartOnFailure;
    });
    _profileFieldsKey.currentState?.reset();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _OpenCodeProfileFields(
        key: _profileFieldsKey,
        showIntro: false,
        initialModel:
            widget.agent.openCodeProviderId == null ||
                widget.agent.openCodeModelId == null
            ? null
            : _OpenCodeModelChoice(
                providerId: widget.agent.openCodeProviderId!,
                providerName:
                    widget.agent.openCodeProviderName ??
                    widget.agent.openCodeProviderId!,
                modelId: widget.agent.openCodeModelId!,
                modelName:
                    widget.agent.openCodeModelName ??
                    widget.agent.openCodeModelId!,
              ),
        onLoadOpenCodeModels: widget.onLoadOpenCodeModels,
        initialFolderChoices: widget.initialFolderChoices,
        onLoadFolders: widget.onLoadFolders,
        openCodeAgent: _openCodeAgent,
        workdir: _workdir,
        restartOnFailure: _restartOnFailure,
        onRestartOnFailureChanged: (value) =>
            setState(() => _restartOnFailure = value),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          TextButton(
            onPressed: _saving ? null : _cancel,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save and restart'),
          ),
        ],
      ),
    ],
  );
}

class _AgentEditorDialog extends StatefulWidget {
  const _AgentEditorDialog({
    required this.onLoadOpenCodeModels,
    required this.initialFolderChoices,
    required this.onLoadFolders,
  });
  final Future<List<_OpenCodeModelChoice>> Function() onLoadOpenCodeModels;
  final List<RepoChoice> initialFolderChoices;
  final Future<List<RepoChoice>> Function(String? path) onLoadFolders;
  @override
  State<_AgentEditorDialog> createState() => _AgentEditorDialogState();
}

class _AgentEditorDialogState extends State<_AgentEditorDialog> {
  static const _skills = [
    'Code changes',
    'Code review',
    'Research',
    'Planning',
    'Testing',
    'Documentation',
    'Debugging',
    'Git',
  ];
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _traits = TextEditingController();
  final _openCodeAgent = TextEditingController();
  final _workdir = TextEditingController();
  final _profileFieldsKey = GlobalKey<_OpenCodeProfileFieldsState>();
  bool _restartOnFailure = true;
  final _selected = <String>{};
  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _traits.dispose();
    _openCodeAgent.dispose();
    _workdir.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create custom agent'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            controller: _role,
            decoration: const InputDecoration(labelText: 'Role'),
          ),
          TextField(
            controller: _traits,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Traits',
              hintText: 'Concise, skeptical, detail-oriented',
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Skills (up to 8)',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final skill in _skills)
                FilterChip(
                  label: Text(skill),
                  selected: _selected.contains(skill),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _selected.add(skill);
                    } else {
                      _selected.remove(skill);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _OpenCodeProfileFields(
            key: _profileFieldsKey,
            onLoadOpenCodeModels: widget.onLoadOpenCodeModels,
            initialFolderChoices: widget.initialFolderChoices,
            onLoadFolders: widget.onLoadFolders,
            openCodeAgent: _openCodeAgent,
            workdir: _workdir,
            restartOnFailure: _restartOnFailure,
            onRestartOnFailureChanged: (value) =>
                setState(() => _restartOnFailure = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_name.text.trim().isEmpty || _role.text.trim().isEmpty) return;
          Navigator.pop(context, {
            'agent_name': _name.text.trim(),
            'agent_role': _role.text.trim(),
            'agent_traits': _traits.text.trim(),
            'agent_skills': _selected.toList(),
            if (_profileFieldsKey.currentState?.selectedModel case final model?)
              'opencode_provider_id': model.providerId,
            if (_profileFieldsKey.currentState?.selectedModel case final model?)
              'opencode_provider_name': model.providerName,
            if (_profileFieldsKey.currentState?.selectedModel case final model?)
              'opencode_model_id': model.modelId,
            if (_profileFieldsKey.currentState?.selectedModel case final model?)
              'opencode_model_name': model.modelName,
            if (_openCodeAgent.text.trim().isNotEmpty)
              'opencode_agent': _openCodeAgent.text.trim(),
            if (_workdir.text.trim().isNotEmpty)
              'agent_workdir': _workdir.text.trim(),
            'restart_agent_session_on_failure': _restartOnFailure,
          });
        },
        child: const Text('Create'),
      ),
    ],
  );
}

class _AgentOpenCodeProfileDialog extends StatefulWidget {
  const _AgentOpenCodeProfileDialog({
    required this.agent,
    required this.onLoadOpenCodeModels,
    required this.initialFolderChoices,
    required this.onLoadFolders,
  });
  final WorkspaceAgent agent;
  final Future<List<_OpenCodeModelChoice>> Function() onLoadOpenCodeModels;
  final List<RepoChoice> initialFolderChoices;
  final Future<List<RepoChoice>> Function(String? path) onLoadFolders;

  @override
  State<_AgentOpenCodeProfileDialog> createState() =>
      _AgentOpenCodeProfileDialogState();
}

class _AgentOpenCodeProfileDialogState
    extends State<_AgentOpenCodeProfileDialog> {
  late final _openCodeAgent = TextEditingController(
    text: widget.agent.openCodeAgent ?? '',
  );
  late final _workdir = TextEditingController(text: widget.agent.workdir ?? '');
  final _profileFieldsKey = GlobalKey<_OpenCodeProfileFieldsState>();
  late bool _restartOnFailure = widget.agent.restartOnFailure;

  @override
  void dispose() {
    _openCodeAgent.dispose();
    _workdir.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.agent.name} OpenCode profile'),
    content: SingleChildScrollView(
      child: _OpenCodeProfileFields(
        key: _profileFieldsKey,
        initialModel:
            widget.agent.openCodeProviderId == null ||
                widget.agent.openCodeModelId == null
            ? null
            : _OpenCodeModelChoice(
                providerId: widget.agent.openCodeProviderId!,
                providerName:
                    widget.agent.openCodeProviderName ??
                    widget.agent.openCodeProviderId!,
                modelId: widget.agent.openCodeModelId!,
                modelName:
                    widget.agent.openCodeModelName ??
                    widget.agent.openCodeModelId!,
              ),
        onLoadOpenCodeModels: widget.onLoadOpenCodeModels,
        initialFolderChoices: widget.initialFolderChoices,
        onLoadFolders: widget.onLoadFolders,
        openCodeAgent: _openCodeAgent,
        workdir: _workdir,
        restartOnFailure: _restartOnFailure,
        onRestartOnFailureChanged: (value) =>
            setState(() => _restartOnFailure = value),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final model = _profileFieldsKey.currentState?.selectedModel;
          Navigator.pop(context, {
            if (model != null) 'opencode_provider_id': model.providerId,
            if (model != null) 'opencode_provider_name': model.providerName,
            if (model != null) 'opencode_model_id': model.modelId,
            if (model != null) 'opencode_model_name': model.modelName,
            if (_openCodeAgent.text.trim().isNotEmpty)
              'opencode_agent': _openCodeAgent.text.trim(),
            if (_workdir.text.trim().isNotEmpty)
              'agent_workdir': _workdir.text.trim(),
            'restart_agent_session_on_failure': _restartOnFailure,
          });
        },
        child: const Text('Save and restart'),
      ),
    ],
  );
}

class _OpenCodeProfileFields extends StatefulWidget {
  const _OpenCodeProfileFields({
    super.key,
    this.initialModel,
    this.showIntro = true,
    required this.onLoadOpenCodeModels,
    required this.initialFolderChoices,
    required this.onLoadFolders,
    required this.openCodeAgent,
    required this.workdir,
    required this.restartOnFailure,
    required this.onRestartOnFailureChanged,
  });

  final _OpenCodeModelChoice? initialModel;
  final bool showIntro;
  final Future<List<_OpenCodeModelChoice>> Function() onLoadOpenCodeModels;
  final List<RepoChoice> initialFolderChoices;
  final Future<List<RepoChoice>> Function(String? path) onLoadFolders;
  final TextEditingController openCodeAgent;
  final TextEditingController workdir;
  final bool restartOnFailure;
  final ValueChanged<bool> onRestartOnFailureChanged;

  @override
  State<_OpenCodeProfileFields> createState() => _OpenCodeProfileFieldsState();
}

class _OpenCodeProfileFieldsState extends State<_OpenCodeProfileFields> {
  late _OpenCodeModelChoice? selectedModel = widget.initialModel;
  String? _selectedFolderLabel;
  bool _loadingModels = false;
  bool _modelPickerOpen = false;

  @override
  void initState() {
    super.initState();
    final workdir = widget.workdir.text.trim();
    for (final choice in widget.initialFolderChoices) {
      if (choice.path == workdir) {
        _selectedFolderLabel = choice.displayName;
        break;
      }
    }
  }

  void reset() {
    setState(() {
      selectedModel = widget.initialModel;
      _selectedFolderLabel = null;
      for (final choice in widget.initialFolderChoices) {
        if (choice.path == widget.workdir.text.trim()) {
          _selectedFolderLabel = choice.displayName;
          break;
        }
      }
    });
  }

  Future<void> _chooseModel() async {
    if (_loadingModels || _modelPickerOpen) return;
    _loadingModels = true;
    setState(() {});
    try {
      final models = await widget.onLoadOpenCodeModels();
      if (!mounted) return;
      if (models.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OpenCode did not return any configured models'),
          ),
        );
        return;
      }
      _modelPickerOpen = true;
      final value = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => _OpenCodeModelPickerPage(
            models: models,
            selectedModel: selectedModel?.value,
          ),
        ),
      );
      if (value == null || !mounted) return;
      _OpenCodeModelChoice? choice;
      for (final model in models) {
        if (model.value == value) {
          choice = model;
          break;
        }
      }
      setState(() {
        selectedModel = value.isEmpty ? null : choice;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load OpenCode models')),
        );
      }
    } finally {
      _modelPickerOpen = false;
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _chooseWorkingFolder() async {
    final selection = await Navigator.of(context).push<_WorkingFolderSelection>(
      MaterialPageRoute(
        builder: (_) => _WorkingFolderPickerPage(
          initialChoices: widget.initialFolderChoices,
          selectedPath: widget.workdir.text.trim(),
          onLoadFolders: widget.onLoadFolders,
        ),
      ),
    );
    if (selection == null || !mounted) return;
    setState(() {
      widget.workdir.text = selection.path ?? '';
      _selectedFolderLabel = selection.label;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.showIntro) ...[
        Text(
          'OpenCode overrides',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        const Text('Choose a configured model or use the worker default.'),
      ],
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.memory_outlined),
        title: Text(
          selectedModel == null ? 'Server default' : selectedModel!.modelName,
        ),
        subtitle: Text(
          selectedModel == null
              ? 'Use OpenCode’s configured default model'
              : '${selectedModel!.providerName} · ${selectedModel!.value}',
        ),
        trailing: _loadingModels
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right),
        onTap: _loadingModels ? null : _chooseModel,
      ),
      TextField(
        controller: widget.openCodeAgent,
        maxLength: 100,
        decoration: const InputDecoration(
          labelText: 'OpenCode execution profile',
          helperText: 'Named OpenCode profile, for example build or explore.',
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.folder_outlined),
        title: Text(
          widget.workdir.text.trim().isEmpty
              ? 'Working folder: worker default'
              : 'Working folder: ${_selectedFolderLabel ?? widget.workdir.text.trim()}',
        ),
        subtitle: Text(
          widget.workdir.text.trim().isEmpty
              ? 'Used by conversations without an explicit folder scope'
              : widget.workdir.text.trim(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _chooseWorkingFolder,
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Restart session after a failed turn'),
        value: widget.restartOnFailure,
        onChanged: widget.onRestartOnFailureChanged,
      ),
    ],
  );
}

class _PeopleDirectory extends StatefulWidget {
  const _PeopleDirectory({
    required this.members,
    required this.ownPubkey,
    required this.displayName,
    required this.memberAliases,
    required this.memberNames,
    required this.onOpenDirect,
    required this.onDisplayNameChanged,
    required this.onMemberAliasChanged,
  });
  final List<String> members;
  final String ownPubkey;
  final String displayName;
  final Map<String, String> memberAliases;
  final Map<String, String> memberNames;
  final ValueChanged<String> onOpenDirect;
  final ValueChanged<String> onDisplayNameChanged;
  final void Function(String pubkey, String alias) onMemberAliasChanged;
  @override
  State<_PeopleDirectory> createState() => _PeopleDirectoryState();
}

class _PeopleDirectoryState extends State<_PeopleDirectory> {
  late final TextEditingController _displayName = TextEditingController(
    text: widget.displayName,
  );

  @override
  void dispose() {
    _displayName.dispose();
    super.dispose();
  }

  String _memberLabel(String pubkey) {
    if (pubkey == widget.ownPubkey) {
      return widget.memberNames[pubkey] ??
          (_displayName.text.trim().isEmpty ? 'You' : _displayName.text.trim());
    }
    return widget.memberAliases[pubkey] ??
        widget.memberNames[pubkey] ??
        compactIdentifier(pubkey);
  }

  Future<void> _editAlias(String pubkey) async {
    final controller = TextEditingController(
      text: widget.memberAliases[pubkey] ?? widget.memberNames[pubkey] ?? '',
    );
    final alias = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Member name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Local name',
            helperText: 'Saved only on this device',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (alias != null) widget.onMemberAliasChanged(pubkey, alias);
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.members;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'People',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text('Manage your profile and workspace members.'),
        const SizedBox(height: 24),
        Text('Your profile', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _displayName,
          textInputAction: TextInputAction.done,
          onSubmitted: widget.onDisplayNameChanged,
          decoration: InputDecoration(
            labelText: 'Display name',
            hintText: 'How teammates see you',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Save display name',
              icon: const Icon(Icons.save_outlined),
              onPressed: () => widget.onDisplayNameChanged(_displayName.text),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Members', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        if (people.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('No workspace members yet'),
          ),
        for (final person in people)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(_memberLabel(person)),
            subtitle: Text(person == widget.ownPubkey ? 'You' : 'Member'),
            trailing: person == widget.ownPubkey
                ? null
                : IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Set local name',
                    onPressed: () => _editAlias(person),
                  ),
            onTap: person == widget.ownPubkey
                ? null
                : () => widget.onOpenDirect(person),
          ),
      ],
    );
  }
}

class _WorkspaceAccessPage extends StatelessWidget {
  const _WorkspaceAccessPage({
    required this.inviteCode,
    required this.memberStatus,
    required this.onCreateInvite,
    required this.onOpenSettings,
  });

  final String? inviteCode;
  final String memberStatus;
  final Future<void> Function() onCreateInvite;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<_WorkspacePalette>()!;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Access',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text('Confirm workspace access and manage invitations.'),
        const SizedBox(height: 24),
        Text('Workspace status', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          tileColor: palette.selected,
          leading: const Icon(Icons.verified_user_outlined),
          title: Text(memberStatus),
          subtitle: const Text('Your current workspace confirmation status'),
        ),
        const SizedBox(height: 24),
        Text('Invitations', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => onCreateInvite(),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Generate workspace invite code'),
        ),
        if (inviteCode != null) ...[
          const SizedBox(height: 12),
          Center(
            child: QrImageView(
              data: inviteCode!,
              size: 220,
              backgroundColor: Colors.white,
              padding: const EdgeInsets.all(12),
              errorCorrectionLevel: QrErrorCorrectLevel.M,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Workspace invite QR'),
            subtitle: const Text('Scan this code or copy the invite payload.'),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: inviteCode!)),
              tooltip: 'Copy invite code',
            ),
          ),
        ],
        const Divider(height: 40),
        Text('Join workspace', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'Use an invite code to confirm access to another workspace.',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Join with invite code'),
        ),
      ],
    );
  }
}

class _SpawnSessionRequest {
  const _SpawnSessionRequest({required this.path, required this.create});

  final String path;
  final bool create;
}

class _ToolErrorPage extends StatelessWidget {
  const _ToolErrorPage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              SelectableText(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolTextPage extends StatelessWidget {
  const _ToolTextPage({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(text),
        ),
      ),
    );
  }
}

class _ClientDiagnosticsPage extends StatefulWidget {
  const _ClientDiagnosticsPage({
    required this.diagnostics,
    required this.fipsEnabled,
    required this.fipsHeartbeat,
    required this.onFipsEnabledChanged,
  });

  final ValueNotifier<List<String>> diagnostics;
  final ValueNotifier<bool> fipsEnabled;
  final ValueNotifier<_WorkspaceFipsHeartbeat> fipsHeartbeat;
  final ValueChanged<bool> onFipsEnabledChanged;

  @override
  State<_ClientDiagnosticsPage> createState() => _ClientDiagnosticsPageState();
}

class _ClientDiagnosticsPageState extends State<_ClientDiagnosticsPage> {
  _DiagnosticFilter _filter = _DiagnosticFilter.all;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Client diagnostics'),
      actions: [
        IconButton(
          tooltip: 'Copy diagnostics',
          onPressed: () => Clipboard.setData(
            ClipboardData(text: widget.diagnostics.value.join('\n')),
          ),
          icon: const Icon(Icons.copy_outlined),
        ),
        IconButton(
          tooltip: 'Clear diagnostics',
          onPressed: () => widget.diagnostics.value = const [],
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: ValueListenableBuilder<_WorkspaceFipsHeartbeat>(
      valueListenable: widget.fipsHeartbeat,
      builder: (context, heartbeat, _) => ValueListenableBuilder<List<String>>(
        valueListenable: widget.diagnostics,
        builder: (context, entries, _) {
          final theme = Theme.of(context);
          final now = DateTime.now();
          final events = _groupDiagnosticEvents(entries);
          final visibleEvents = events
              .where((event) => _filter.includes(event.category))
              .toList();
          final warnings = events.where((event) => event.isWarning).length;
          final errors = events.where((event) => event.isError).length;
          final liveFor = heartbeat.connectedAt == null
              ? null
              : now.difference(heartbeat.connectedAt!);
          final lastHeartbeat = heartbeat.lastHeartbeatAt == null
              ? null
              : now.difference(heartbeat.lastHeartbeatAt!);
          final active = heartbeat.connectionState == 'active';
          final stateColor = active
              ? const Color(0xff35d6a0)
              : heartbeat.connectionState == 'disabled'
              ? theme.colorScheme.onSurfaceVariant
              : heartbeat.connectionState == 'reconnecting'
              ? const Color(0xffffb547)
              : theme.colorScheme.error;
          final stateLabel = switch (heartbeat.connectionState) {
            'active' => 'Connected',
            'connected' => 'Connected',
            'connecting' => 'Connecting',
            'reconnecting' => 'Reconnecting',
            'disabled' => 'Nostr only',
            _ => 'Disconnected',
          };
          Widget section(String label, {String? trailing}) => Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 8),
            child: Row(
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (trailing != null) ...[
                  const Spacer(),
                  Text(
                    trailing,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          );
          final lifecycle = switch (heartbeat.connectionState) {
            'active' => 3,
            'connected' => 2,
            'connecting' || 'reconnecting' => 1,
            _ => 0,
          };
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              section('Connection settings'),
              ValueListenableBuilder<bool>(
                valueListenable: widget.fipsEnabled,
                builder: (context, enabled, _) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text('Use FIPS transport'),
                  subtitle: Text(
                    enabled
                        ? 'Direct connection with Nostr fallback'
                        : 'Nostr messages only',
                  ),
                  trailing: Switch(
                    value: enabled,
                    onChanged: widget.onFipsEnabledChanged,
                  ),
                ),
              ),
              section('Current status'),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.65, end: active ? 1 : 0.8),
                          duration: const Duration(milliseconds: 750),
                          curve: Curves.easeOutCubic,
                          builder: (context, opacity, child) =>
                              Opacity(opacity: opacity, child: child),
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: stateColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text(
                          stateLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          active ? 'Live' : 'Monitoring',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: stateColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              _DiagnosticStat(
                                label: 'Duration',
                                value: liveFor == null
                                    ? 'Not connected'
                                    : _formatFipsDuration(liveFor),
                              ),
                              const SizedBox(height: 6),
                              _DiagnosticStat(
                                label: 'Heartbeat',
                                value: lastHeartbeat == null
                                    ? 'Waiting'
                                    : '${_formatFipsDuration(lastHeartbeat)} ago',
                              ),
                              const SizedBox(height: 6),
                              _DiagnosticStat(
                                label: 'Heartbeats',
                                value: '${heartbeat.count}',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            children: [
                              _DiagnosticStat(
                                label: 'Transport',
                                value: active ? 'FIPS' : 'Nostr',
                              ),
                              const SizedBox(height: 6),
                              const _DiagnosticStat(
                                label: 'Fallback',
                                value: 'Nostr enabled',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _DiagnosticTimeline(stage: lifecycle, color: stateColor),
              ),
              section(
                'Recent events',
                trailing:
                    '${events.length} total · $warnings warnings · $errors errors',
              ),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: _DiagnosticFilter.values
                    .map(
                      (filter) => ChoiceChip(
                        label: Text(filter.label),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
              if (visibleEvents.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    entries.isEmpty
                        ? 'No connection events yet.'
                        : 'No events match this filter.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final event in visibleEvents)
                  _DiagnosticEvent(event: event),
            ],
          );
        },
      ),
    ),
  );
}

class _DiagnosticStat extends StatelessWidget {
  const _DiagnosticStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(
        fit: FlexFit.tight,
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      Flexible(
        child: Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

class _DiagnosticEvent extends StatelessWidget {
  const _DiagnosticEvent({required this.event});

  final _DiagnosticEventData event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = event.isError
        ? theme.colorScheme.error
        : event.isWarning
        ? const Color(0xffffb547)
        : event.category == _DiagnosticCategory.connection
        ? const Color(0xff35d6a0)
        : event.category == _DiagnosticCategory.snapshot
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final icon = event.isError
        ? Icons.error_outline
        : event.isWarning
        ? Icons.warning_amber_rounded
        : event.category == _DiagnosticCategory.connection
        ? Icons.check_circle_outline
        : event.category == _DiagnosticCategory.snapshot
        ? Icons.downloading_outlined
        : Icons.info_outline;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color:
            (event.isError
                    ? theme.colorScheme.error
                    : event.isWarning
                    ? const Color(0xffffb547)
                    : theme.colorScheme.surfaceContainerHighest)
                .withValues(
                  alpha: event.isError || event.isWarning ? 0.12 : 0.42,
                ),
        borderRadius: BorderRadius.circular(9),
        border: Border(left: BorderSide(color: color, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          if (event.timestamp.isNotEmpty) ...[
            Text(
              event.timestamp,
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.72,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  event.count > 1
                      ? '${event.title} (${event.count})'
                      : event.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight:
                        event.isError ||
                            event.isWarning ||
                            event.category == _DiagnosticCategory.connection
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                if (event.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    event.detail!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _DiagnosticFilter {
  all,
  connection,
  snapshots,
  transport,
  warnings,
  errors,
}

extension on _DiagnosticFilter {
  String get label => switch (this) {
    _DiagnosticFilter.all => 'All',
    _DiagnosticFilter.connection => 'Connection',
    _DiagnosticFilter.snapshots => 'Snapshots',
    _DiagnosticFilter.transport => 'Transport',
    _DiagnosticFilter.warnings => 'Warnings',
    _DiagnosticFilter.errors => 'Errors',
  };

  bool includes(_DiagnosticCategory category) => switch (this) {
    _DiagnosticFilter.all => true,
    _DiagnosticFilter.connection => category == _DiagnosticCategory.connection,
    _DiagnosticFilter.snapshots => category == _DiagnosticCategory.snapshot,
    _DiagnosticFilter.transport => category == _DiagnosticCategory.transport,
    _DiagnosticFilter.warnings => category == _DiagnosticCategory.warning,
    _DiagnosticFilter.errors => category == _DiagnosticCategory.error,
  };
}

enum _DiagnosticCategory {
  connection,
  snapshot,
  transport,
  warning,
  error,
  info,
}

class _DiagnosticEventData {
  const _DiagnosticEventData({
    required this.timestamp,
    required this.category,
    required this.title,
    this.detail,
    this.count = 1,
  });

  final String timestamp;
  final _DiagnosticCategory category;
  final String title;
  final String? detail;
  final int count;

  bool get isWarning => category == _DiagnosticCategory.warning;
  bool get isError => category == _DiagnosticCategory.error;

  _DiagnosticEventData copyWith({String? title, String? detail, int? count}) =>
      _DiagnosticEventData(
        timestamp: timestamp,
        category: category,
        title: title ?? this.title,
        detail: detail ?? this.detail,
        count: count ?? this.count,
      );
}

List<_DiagnosticEventData> _groupDiagnosticEvents(List<String> entries) {
  final grouped = <_DiagnosticEventData>[];
  for (final entry in entries.reversed.take(80)) {
    final event = _diagnosticEvent(entry);
    if (event.category == _DiagnosticCategory.snapshot &&
        grouped.isNotEmpty &&
        grouped.last.category == _DiagnosticCategory.snapshot) {
      final previous = grouped.removeLast();
      grouped.add(
        previous.copyWith(
          title: 'Snapshot exchange',
          detail: event.title,
          count: previous.count + 1,
        ),
      );
      continue;
    }
    grouped.add(event);
  }
  return grouped;
}

_DiagnosticEventData _diagnosticEvent(String entry) {
  final match = RegExp(r'^(\d{2}:\d{2}:\d{2})\s{2}(.*)$').firstMatch(entry);
  final timestamp = match?.group(1) ?? '';
  final raw = match?.group(2) ?? entry;
  final value = _diagnosticSummary(raw);
  final lower = raw.toLowerCase();

  if (lower.contains('failed') || lower.contains('timed out')) {
    final heartbeat = lower.contains('heartbeat');
    return _DiagnosticEventData(
      timestamp: timestamp,
      category: _DiagnosticCategory.error,
      title: 'Session failed',
      detail: heartbeat
          ? 'Heartbeat timed out. Switched to Nostr fallback.'
          : 'Switched to Nostr fallback.',
    );
  }
  if (lower.contains('fallback') ||
      lower.contains('retrying') ||
      lower.contains('reconnecting')) {
    return _DiagnosticEventData(
      timestamp: timestamp,
      category: _DiagnosticCategory.warning,
      title: lower.contains('reconnecting') ? 'Reconnecting' : 'Retrying',
      detail: lower.contains('fallback')
          ? 'Using Nostr fallback.'
          : lower.contains(' in ')
          ? value
          : 'Snapshot exchange is retrying.',
    );
  }
  if (lower.contains('connection:') ||
      lower == 'connected' ||
      lower == 'disconnected') {
    return _DiagnosticEventData(
      timestamp: timestamp,
      category: _DiagnosticCategory.connection,
      title: value.replaceFirst('Connection ', ''),
    );
  }
  if (lower.contains('snapshot')) {
    return _DiagnosticEventData(
      timestamp: timestamp,
      category: _DiagnosticCategory.snapshot,
      title: value.replaceFirst('Snapshot ', ''),
    );
  }
  if (lower.contains('fips') || lower.contains('nostr')) {
    return _DiagnosticEventData(
      timestamp: timestamp,
      category: _DiagnosticCategory.transport,
      title: value,
    );
  }
  return _DiagnosticEventData(
    timestamp: timestamp,
    category: _DiagnosticCategory.info,
    title: value,
  );
}

class _DiagnosticTimeline extends StatelessWidget {
  const _DiagnosticTimeline({required this.stage, required this.color});

  final int stage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _DiagnosticTimelineStep(
          label: 'Connected',
          complete: stage >= 1,
          active: stage == 1,
          color: color,
        ),
        _DiagnosticTimelineLine(complete: stage >= 2, color: color),
        _DiagnosticTimelineStep(
          label: 'Snapshot',
          complete: stage >= 2,
          active: stage == 2,
          color: color,
        ),
        _DiagnosticTimelineLine(complete: stage >= 3, color: color),
        _DiagnosticTimelineStep(
          label: 'Active',
          complete: stage >= 3,
          active: stage == 3,
          color: color,
        ),
      ],
    );
  }
}

class _DiagnosticTimelineLine extends StatelessWidget {
  const _DiagnosticTimelineLine({required this.complete, required this.color});

  final bool complete;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      height: 1,
      margin: const EdgeInsets.only(bottom: 20),
      color: complete ? color : Theme.of(context).colorScheme.outlineVariant,
    ),
  );
}

class _DiagnosticTimelineStep extends StatelessWidget {
  const _DiagnosticTimelineStep({
    required this.label,
    required this.complete,
    required this.active,
    required this.color,
  });

  final String label;
  final bool complete;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: complete
              ? color
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(
          complete
              ? (active ? Icons.circle : Icons.check)
              : Icons.circle_outlined,
          size: active ? 9 : 13,
          color: complete
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: complete
              ? Theme.of(context).colorScheme.onSurface
              : Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ],
  );
}

String _diagnosticSummary(String message) {
  const prefix = 'FIPS workspace ';
  final value = message.startsWith(prefix)
      ? message.substring(prefix.length)
      : message;
  return switch (value) {
    'connection: active' => 'Connection active',
    'connection: connected' => 'Connected',
    'connection: connecting' => 'Connecting',
    'connection: reconnecting' => 'Reconnecting',
    'connection: disconnected' => 'Disconnected',
    'connection: disabled' => 'FIPS disabled',
    'snapshot offer received' => 'Snapshot offer received',
    'snapshot requested' => 'Snapshot requested',
    _ => value,
  };
}

String _formatFipsDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return minutes == 0
      ? '${seconds}s'
      : '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
}

class _WorkerConsolePage extends StatefulWidget {
  const _WorkerConsolePage({
    required this.data,
    required this.cache,
    required this.onRequestRange,
  });

  final Map<String, dynamic> data;
  final Map<String, Map<String, dynamic>> cache;
  final Future<void> Function(
    String range,
    void Function(Map<String, dynamic>? data, String? error) onResult,
  )
  onRequestRange;

  @override
  State<_WorkerConsolePage> createState() => _WorkerConsolePageState();
}

class _WorkerConsolePageState extends State<_WorkerConsolePage> {
  late Map<String, dynamic> data;
  late String _selectedRange;
  bool _loadingRange = false;
  bool _showAllInterfaces = false;

  @override
  void initState() {
    super.initState();
    data = widget.data;
    _selectedRange = data['history_range']?.toString() ?? '24h';
  }

  Future<void> _selectRange(String range, {bool refresh = false}) async {
    final cached = refresh ? null : widget.cache[range];
    if (cached != null) {
      setState(() {
        data = cached;
        _selectedRange = range;
      });
      return;
    }
    setState(() => _loadingRange = true);
    await widget.onRequestRange(range, (result, error) {
      if (!mounted) return;
      setState(() {
        _loadingRange = false;
        if (result != null) {
          data = result;
          _selectedRange = range;
        }
      });
      if (error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    });
  }

  Map<String, dynamic> get _current =>
      (data['current'] as Map?)?.cast<String, dynamic>() ?? data;

  Map<String, dynamic> _map(String key) =>
      (_current[key] as Map?)?.cast<String, dynamic>() ?? const {};

  double _number(dynamic value) => value is num ? value.toDouble() : 0;

  _ConsoleMetricStatus _statusForRatio(double value, double total) {
    final ratio = total <= 0 ? 0.0 : value / total;
    if (ratio >= 0.95) return _ConsoleMetricStatus.critical;
    if (ratio >= 0.80) return _ConsoleMetricStatus.warning;
    return _ConsoleMetricStatus.normal;
  }

  String _bytes(dynamic value) {
    final bytes = _number(value);
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var unit = 0;
    var readable = bytes;
    while (readable >= 1024 && unit < units.length - 1) {
      readable /= 1024;
      unit++;
    }
    return '${readable.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  @override
  Widget build(BuildContext context) {
    final memory = _map('memory');
    final swap = _map('swap');
    final filesystem = _map('filesystem');
    final disk = _map('disk_io');
    final load = (_current['load'] as List? ?? const []).map(_number).toList();
    final networks = (_current['networks'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => entry.cast<String, dynamic>())
        .toList();
    final temperatures = (_current['temperatures'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => entry.cast<String, dynamic>())
        .toList();
    final sampledAt = _number(_current['sampled_at']).toInt();
    final history = (data['history'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => entry.cast<String, dynamic>())
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Worker console'),
        actions: [
          IconButton(
            tooltip: 'Refresh worker stats',
            onPressed: _loadingRange
                ? null
                : () => unawaited(_selectRange(_selectedRange, refresh: true)),
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1400;
          final medium = constraints.maxWidth >= 900;
          const gap = 16.0;
          final contentWidth =
              (constraints.maxWidth > 1600 ? 1600.0 : constraints.maxWidth) -
              48;
          final metricWidth = wide
              ? (contentWidth - gap * 3) / 4
              : medium
              ? (contentWidth - gap) / 2
              : contentWidth;
          final chartWidth = wide ? (contentWidth - gap * 2) / 3 : contentWidth;
          final cpuValues = history
              .map((sample) => _number(sample['cpu_percent']))
              .toList();
          final memoryValues = history.map((sample) {
            final value =
                (sample['memory'] as Map?)?.cast<String, dynamic>() ?? const {};
            final total = _number(value['total_bytes']);
            return total == 0
                ? 0.0
                : 100.0 * _number(value['used_bytes']) / total;
          }).toList();
          final swapValues = history.map((sample) {
            final value =
                (sample['swap'] as Map?)?.cast<String, dynamic>() ?? const {};
            final total = _number(value['total_bytes']);
            return total == 0
                ? 0.0
                : 100.0 * _number(value['used_bytes']) / total;
          }).toList();
          final diskValues = history.map((sample) {
            final value =
                (sample['filesystem'] as Map?)?.cast<String, dynamic>() ??
                const {};
            final total = _number(value['total_bytes']);
            return total == 0
                ? 0.0
                : 100.0 * _number(value['used_bytes']) / total;
          }).toList();
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1600),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Text(
                                sampledAt == 0
                                    ? 'Waiting for worker metrics'
                                    : 'Sampled ${DateTime.fromMillisecondsSinceEpoch(sampledAt * 1000).toLocal().toString().substring(11, 19)}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              for (final range in const [
                                ('1h', '1 h'),
                                ('24h', '24 h'),
                                ('1w', '7 d'),
                                ('all', 'All'),
                              ])
                                ChoiceChip(
                                  label: Text(range.$2),
                                  selected: _selectedRange == range.$1,
                                  visualDensity: VisualDensity.compact,
                                  labelStyle: Theme.of(
                                    context,
                                  ).textTheme.labelSmall,
                                  onSelected: _loadingRange
                                      ? null
                                      : (_) =>
                                            unawaited(_selectRange(range.$1)),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            SizedBox(
                              width: metricWidth,
                              height: 168,
                              child: _ConsoleMetric(
                                label: 'CPU',
                                icon: Icons.memory_outlined,
                                value: _number(_current['cpu_percent']),
                                total: 100,
                                detail:
                                    '${_number(_current['cpu_percent']).toStringAsFixed(1)}%',
                                footer:
                                    'Load ${load.map((value) => value.toStringAsFixed(2)).join(' / ')}',
                              ),
                            ),
                            SizedBox(
                              width: metricWidth,
                              height: 168,
                              child: _ConsoleMetric(
                                label: 'Memory',
                                icon: Icons.dns_outlined,
                                value: _number(memory['used_bytes']),
                                total: _number(memory['total_bytes']),
                                detail:
                                    '${_bytes(memory['used_bytes'])} / ${_bytes(memory['total_bytes'])}',
                              ),
                            ),
                            SizedBox(
                              width: metricWidth,
                              height: 168,
                              child: _ConsoleMetric(
                                label: 'Swap',
                                icon: Icons.swap_horiz_outlined,
                                value: _number(swap['used_bytes']),
                                total: _number(swap['total_bytes']),
                                detail:
                                    '${_bytes(swap['used_bytes'])} / ${_bytes(swap['total_bytes'])}',
                                status: _statusForRatio(
                                  _number(swap['used_bytes']),
                                  _number(swap['total_bytes']),
                                ),
                                footer:
                                    '${_number(swap['total_bytes']) == 0 ? '0' : (100 * _number(swap['used_bytes']) / _number(swap['total_bytes'])).toStringAsFixed(0)}% used',
                              ),
                            ),
                            SizedBox(
                              width: metricWidth,
                              height: 168,
                              child: _ConsoleMetric(
                                label: 'Disk ${filesystem['mount'] ?? '/'}',
                                icon: Icons.storage_outlined,
                                value: _number(filesystem['used_bytes']),
                                total: _number(filesystem['total_bytes']),
                                detail:
                                    '${_bytes(filesystem['available_bytes'])} free of ${_bytes(filesystem['total_bytes'])}',
                                accent: Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            SizedBox(
                              width: chartWidth,
                              child: SizedBox(
                                height: 310,
                                child: _ConsolePanel(
                                  title: 'CPU usage',
                                  subtitle: 'Last ${history.length} samples',
                                  child: _HistoryLineChart(
                                    values: cpuValues,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    primaryLabel: 'CPU',
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: chartWidth,
                              child: SizedBox(
                                height: 310,
                                child: _ConsolePanel(
                                  title: 'Memory and swap',
                                  subtitle: 'Percent used',
                                  child: _HistoryLineChart(
                                    values: memoryValues,
                                    secondaryValues: swapValues,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    secondaryColor: Theme.of(
                                      context,
                                    ).colorScheme.tertiary,
                                    primaryLabel: 'Memory',
                                    secondaryLabel: 'Swap',
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: chartWidth,
                              child: SizedBox(
                                height: 310,
                                child: _ConsolePanel(
                                  title: 'Disk usage',
                                  subtitle: 'Percent used',
                                  child: _HistoryLineChart(
                                    values: diskValues,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.secondary,
                                    primaryLabel: 'Disk',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 7,
                                child: _networkPanel(context, networks),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 5,
                                child: _consoleSidePanel(
                                  context,
                                  disk,
                                  temperatures,
                                  _map('system'),
                                ),
                              ),
                            ],
                          )
                        else ...[
                          _networkPanel(context, networks),
                          const SizedBox(height: 12),
                          _consoleSidePanel(
                            context,
                            disk,
                            temperatures,
                            _map('system'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _networkPanel(
    BuildContext context,
    List<Map<String, dynamic>> networks,
  ) {
    final ordered = [...networks]
      ..sort(
        (left, right) =>
            (_number(right['received_bytes']) +
                    _number(right['transmitted_bytes']))
                .compareTo(
                  _number(left['received_bytes']) +
                      _number(left['transmitted_bytes']),
                ),
      );
    final visible = _showAllInterfaces ? ordered : ordered.take(8).toList();
    return _ConsolePanel(
      title: 'Network interfaces',
      subtitle: '${networks.length} reported',
      child: networks.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No network interfaces reported.'),
            )
          : Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 30,
                    dataRowMinHeight: 30,
                    dataRowMaxHeight: 30,
                    columns: const [
                      DataColumn(label: Text('Interface')),
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Received'), numeric: true),
                      DataColumn(label: Text('Sent'), numeric: true),
                      DataColumn(label: Text('Activity'), numeric: true),
                    ],
                    rows: [
                      for (final network in visible)
                        DataRow(
                          cells: [
                            DataCell(
                              Text(
                                network['name']?.toString() ?? 'interface',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            DataCell(
                              Text(
                                _interfaceKind(
                                  network['name']?.toString() ?? '',
                                ),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.circle,
                                    size: 6,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Up',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            DataCell(
                              _trafficValue(context, network['received_bytes']),
                            ),
                            DataCell(
                              _trafficValue(
                                context,
                                network['transmitted_bytes'],
                              ),
                            ),
                            DataCell(
                              _trafficValue(
                                context,
                                _number(network['received_bytes']) +
                                    _number(network['transmitted_bytes']),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (ordered.length > 10)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(
                        () => _showAllInterfaces = !_showAllInterfaces,
                      ),
                      child: Text(
                        _showAllInterfaces
                            ? 'Show fewer interfaces'
                            : 'Show all interfaces (${ordered.length})',
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  String _interfaceKind(String name) {
    if (name.startsWith('eth') || name.startsWith('en')) return 'Ethernet';
    if (name.startsWith('wg')) return 'WireGuard';
    if (name == 'docker0' || name.startsWith('br-')) return 'Bridge';
    if (name.startsWith('veth')) return 'Virtual';
    if (name.startsWith('can')) return 'CAN';
    return 'Other';
  }

  Widget _trafficValue(BuildContext context, Object? value) => Align(
    alignment: Alignment.centerRight,
    child: Text(
      _bytes(value),
      textAlign: TextAlign.right,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );

  Widget _consoleSidePanel(
    BuildContext context,
    Map<String, dynamic> disk,
    List<Map<String, dynamic>> temperatures,
    Map<String, dynamic> system,
  ) => Column(
    children: [
      _ConsolePanel(
        title: 'Cumulative I/O',
        child: Row(
          children: [
            Expanded(
              child: _ConsoleValue(
                label: 'Read',
                value: _bytes(disk['read_bytes']),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ConsoleValue(
                label: 'Written',
                value: _bytes(disk['written_bytes']),
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ),
          ],
        ),
      ),
      if (temperatures.isNotEmpty) ...[
        const SizedBox(height: 12),
        _ConsolePanel(
          title: 'Sensors',
          quiet: true,
          child: Column(
            children: [
              for (final temperature in temperatures)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(temperature['label']?.toString() ?? 'Sensor'),
                  trailing: Text(
                    '${_number(temperature['celsius']).toStringAsFixed(1)} C',
                  ),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      _ConsolePanel(
        title: 'System information',
        quiet: true,
        child: Column(
          children: [
            _systemInfoRow(
              'Uptime',
              _uptime(_number(_current['uptime_seconds']).toInt()),
            ),
            if (_knownSystemValue(system['hostname']))
              _systemInfoRow('Hostname', system['hostname'].toString()),
            if (_knownSystemValue(system['os_name']))
              _systemInfoRow('OS', system['os_name'].toString()),
            if (_knownSystemValue(system['architecture']))
              _systemInfoRow('Architecture', system['architecture'].toString()),
          ],
        ),
      ),
    ],
  );

  bool _knownSystemValue(Object? value) {
    final text = value?.toString().trim();
    return text != null && text.isNotEmpty && text.toLowerCase() != 'unknown';
  }

  Widget _systemInfoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ],
    ),
  );

  String _uptime(int seconds) {
    final days = seconds ~/ 86400;
    final hours = seconds % 86400 ~/ 3600;
    final minutes = seconds % 3600 ~/ 60;
    return days > 0
        ? '${days}d ${hours}h ${minutes}m'
        : '${hours}h ${minutes}m';
  }
}

enum _ConsoleMetricStatus { normal, warning, critical }

class _ConsoleMetric extends StatelessWidget {
  const _ConsoleMetric({
    required this.label,
    required this.icon,
    required this.value,
    required this.total,
    required this.detail,
    this.footer,
    this.accent,
    this.status = _ConsoleMetricStatus.normal,
  });

  final String label;
  final IconData icon;
  final double value;
  final double total;
  final String detail;
  final String? footer;
  final Color? accent;
  final _ConsoleMetricStatus status;

  @override
  Widget build(BuildContext context) {
    final fraction = total <= 0 ? 0.0 : (value / total).clamp(0.0, 1.0);
    final color = switch (status) {
      _ConsoleMetricStatus.normal =>
        accent ?? Theme.of(context).colorScheme.primary,
      _ConsoleMetricStatus.warning => const Color(0xfff0b84b),
      _ConsoleMetricStatus.critical => Theme.of(context).colorScheme.error,
    };
    final statusLabel = switch (status) {
      _ConsoleMetricStatus.normal => null,
      _ConsoleMetricStatus.warning => 'Warning',
      _ConsoleMetricStatus.critical => 'Critical',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: status == _ConsoleMetricStatus.critical
            ? color.withValues(alpha: 0.14)
            : Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: status == _ConsoleMetricStatus.critical
              ? color.withValues(alpha: 0.8)
              : Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.65),
          width: status == _ConsoleMetricStatus.critical ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (statusLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 7,
              color: color,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 8),
            Text(
              footer!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConsolePanel extends StatelessWidget {
  const _ConsolePanel({
    required this.title,
    required this.child,
    this.subtitle,
    this.quiet = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool quiet;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
    decoration: BoxDecoration(
      color: quiet
          ? Theme.of(
              context,
            ).colorScheme.surfaceContainerHigh.withValues(alpha: 0.3)
          : Theme.of(context).colorScheme.surface.withValues(alpha: 0.74),
      borderRadius: BorderRadius.circular(12),
      border: quiet
          ? null
          : Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.labelLarge),
            ),
            if (subtitle != null)
              Text(subtitle!, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

class _ConsoleValue extends StatelessWidget {
  const _ConsoleValue({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.36),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: color ?? Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

class _HistoryLineChart extends StatelessWidget {
  const _HistoryLineChart({
    required this.values,
    required this.color,
    required this.primaryLabel,
    this.secondaryValues,
    this.secondaryColor,
    this.secondaryLabel,
  });

  final List<double> values;
  final List<double>? secondaryValues;
  final Color color;
  final Color? secondaryColor;
  final String primaryLabel;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _ChartLegend(
              label: primaryLabel,
              value: _latest(values),
              color: color,
            ),
            if (secondaryValues != null &&
                secondaryColor != null &&
                secondaryLabel != null) ...[
              const SizedBox(width: 12),
              _ChartLegend(
                label: secondaryLabel!,
                value: _latest(secondaryValues!),
                color: secondaryColor!,
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 166,
          child: Row(
            children: [
              _ChartAxis(color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: CustomPaint(
                  painter: _HistoryLinePainter(
                    values: values,
                    color: color,
                    secondaryValues: secondaryValues,
                    secondaryColor: secondaryColor,
                    gridColor: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  String _latest(List<double> samples) =>
      samples.isEmpty ? '--' : '${samples.last.toStringAsFixed(1)}%';
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(width: 4),
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
    ],
  );
}

class _ChartAxis extends StatelessWidget {
  const _ChartAxis({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 26,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [_label('100%'), _label('50%'), _label('0%')],
    ),
  );

  Widget _label(String value) => Text(
    value,
    style: TextStyle(
      fontSize: 10,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

class _HistoryLinePainter extends CustomPainter {
  const _HistoryLinePainter({
    required this.values,
    required this.color,
    required this.gridColor,
    this.secondaryValues,
    this.secondaryColor,
  });

  final List<double> values;
  final Color color;
  final List<double>? secondaryValues;
  final Color? secondaryColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var row = 0; row <= 4; row++) {
      final y = size.height * row / 4;
      canvas.drawLine(Offset.zero.translate(0, y), Offset(size.width, y), grid);
    }
    _draw(canvas, size, values, color);
    if (secondaryValues != null && secondaryColor != null) {
      _draw(canvas, size, secondaryValues!, secondaryColor!);
    }
  }

  void _draw(Canvas canvas, Size size, List<double> samples, Color lineColor) {
    if (samples.length < 2) return;
    final path = Path();
    for (var index = 0; index < samples.length; index++) {
      final x = size.width * index / (samples.length - 1);
      final y = size.height * (1 - (samples[index].clamp(0, 100) / 100));
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_HistoryLinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.secondaryValues != secondaryValues;
}

class _OpenCodeModelPickerPage extends StatefulWidget {
  const _OpenCodeModelPickerPage({
    required this.models,
    required this.selectedModel,
  });

  final List<_OpenCodeModelChoice> models;
  final String? selectedModel;

  @override
  State<_OpenCodeModelPickerPage> createState() =>
      _OpenCodeModelPickerPageState();
}

class _OpenCodeModelPickerPageState extends State<_OpenCodeModelPickerPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final models = widget.models.where((model) {
      return query.isEmpty ||
          model.providerName.toLowerCase().contains(query) ||
          model.modelName.toLowerCase().contains(query) ||
          model.value.toLowerCase().contains(query);
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Select OpenCode model')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SearchBar(
              hintText: 'Search providers and models',
              leading: const Icon(Icons.search),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore_outlined),
            title: const Text('Server default'),
            subtitle: const Text('Use OpenCode’s configured default model'),
            trailing: widget.selectedModel == null
                ? const Icon(Icons.check)
                : null,
            onTap: () => Navigator.of(context).pop(''),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: models.length,
              itemBuilder: (context, index) {
                final model = models[index];
                final previous = index == 0 ? null : models[index - 1];
                final showProvider = previous?.providerId != model.providerId;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showProvider)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                        child: Text(
                          model.providerName,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    ListTile(
                      title: Text(model.modelName),
                      subtitle: Text(model.value),
                      trailing: widget.selectedModel == model.value
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.of(context).pop(model.value),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

enum _GitStatusFilter { all, staged, working, untracked }

class _GitStatusPage extends StatefulWidget {
  const _GitStatusPage({
    required this.result,
    required this.workdir,
    required this.onViewDiff,
    required this.onReadFile,
  });

  final GitStatusResult result;
  final String workdir;
  final Future<void> Function() onViewDiff;
  final Future<void> Function(String path) onReadFile;

  @override
  State<_GitStatusPage> createState() => _GitStatusPageState();
}

class _GitStatusPageState extends State<_GitStatusPage> {
  _GitStatusFilter _filter = _GitStatusFilter.all;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final files = widget.result.files.where((file) {
      return switch (_filter) {
        _GitStatusFilter.all => true,
        _GitStatusFilter.staged => file.staged,
        _GitStatusFilter.working => !file.staged && !file.untracked,
        _GitStatusFilter.untracked => file.untracked,
      };
    }).toList();
    final staged = widget.result.files.where((file) => file.staged).length;
    final untracked = widget.result.files
        .where((file) => file.untracked)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Changes'),
        actions: [
          IconButton(
            tooltip: 'View diff',
            onPressed: widget.result.files.isEmpty
                ? null
                : () {
                    Navigator.of(context).pop();
                    widget.onViewDiff();
                  },
            icon: const Icon(Icons.difference_outlined),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xff111816),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xff2b3935)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_tree_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.result.branch.isEmpty
                              ? 'Detached HEAD'
                              : widget.result.branch,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _CountPill(
                        label: widget.result.clean
                            ? 'Clean'
                            : '${widget.result.files.length} changed',
                        color: widget.result.clean
                            ? const Color(0xff3fb950)
                            : const Color(0xffd29922),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.workdir,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xff8b9a95),
                    ),
                  ),
                  if (widget.result.latestSubject.isNotEmpty) ...[
                    const Divider(height: 24),
                    Text(
                      '${widget.result.latestHash}  ${widget.result.latestSubject}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _StatusFilterChip(
                    label: 'All ${widget.result.files.length}',
                    selected: _filter == _GitStatusFilter.all,
                    onTap: () => setState(() => _filter = _GitStatusFilter.all),
                  ),
                  _StatusFilterChip(
                    label: 'Staged $staged',
                    selected: _filter == _GitStatusFilter.staged,
                    onTap: () =>
                        setState(() => _filter = _GitStatusFilter.staged),
                  ),
                  _StatusFilterChip(
                    label:
                        'Working ${widget.result.files.length - staged - untracked}',
                    selected: _filter == _GitStatusFilter.working,
                    onTap: () =>
                        setState(() => _filter = _GitStatusFilter.working),
                  ),
                  _StatusFilterChip(
                    label: 'Untracked $untracked',
                    selected: _filter == _GitStatusFilter.untracked,
                    onTap: () =>
                        setState(() => _filter = _GitStatusFilter.untracked),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          if (files.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('No files in this view')),
            )
          else
            SliverList.builder(
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: _FileStatusIcon(file: file),
                  title: Text(
                    file.path.split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    file.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: file.untracked
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          widget.onReadFile(file.path);
                        },
                );
              },
            ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  const _StatusFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _FileStatusIcon extends StatelessWidget {
  const _FileStatusIcon({required this.file});

  final GitFileStatus file;

  @override
  Widget build(BuildContext context) {
    final color = file.untracked
        ? const Color(0xff8b949e)
        : file.staged
        ? const Color(0xff3fb950)
        : const Color(0xffd29922);
    return Tooltip(
      message: file.statusLabel,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          file.untracked
              ? '?'
              : file.staged
              ? 'S'
              : 'M',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _DiffViewerPage extends StatefulWidget {
  const _DiffViewerPage({
    required this.result,
    required this.workdir,
    required this.onReadFile,
  });

  final DiffResult result;
  final String workdir;
  final Future<void> Function(String path) onReadFile;

  @override
  State<_DiffViewerPage> createState() => _DiffViewerPageState();
}

class _DiffViewerPageState extends State<_DiffViewerPage> {
  final _verticalController = ScrollController();
  final _horizontalController = ScrollController();
  int _selectedIndex = 0;

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  void _selectFile(int index) {
    setState(() => _selectedIndex = index);
    if (_verticalController.hasClients) _verticalController.jumpTo(0);
    if (_horizontalController.hasClients) _horizontalController.jumpTo(0);
  }

  Future<void> _showFilePicker() async {
    final index = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.result.files.length,
          itemBuilder: (context, index) {
            final file = widget.result.files[index];
            return ListTile(
              selected: index == _selectedIndex,
              leading: const Icon(Icons.description_outlined),
              title: Text(
                file.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text('+${file.additions}  -${file.deletions}'),
              onTap: () => Navigator.of(context).pop(index),
            );
          },
        ),
      ),
    );
    if (index != null) _selectFile(index);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.result.files.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Diff')),
        body: const Center(child: Text('No tracked changes')),
      );
    }
    final file = widget.result.files[_selectedIndex];
    final lines = _parsePatchLines(file.patch);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              file.path.split('/').last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${_selectedIndex + 1} of ${widget.result.files.length}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Open file',
            onPressed: () {
              Navigator.of(context).pop();
              widget.onReadFile(file.path);
            },
            icon: const Icon(Icons.open_in_new),
          ),
          IconButton(
            tooltip: 'Choose file',
            onPressed: _showFilePicker,
            icon: const Icon(Icons.list_alt),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: const BoxDecoration(
              color: Color(0xff111816),
              border: Border(bottom: BorderSide(color: Color(0xff2b3935))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    file.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Text(
                  '+${file.additions}',
                  style: const TextStyle(color: Color(0xff3fb950)),
                ),
                const SizedBox(width: 10),
                Text(
                  '-${file.deletions}',
                  style: const TextStyle(color: Color(0xfff85149)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _verticalController,
              child: SingleChildScrollView(
                controller: _verticalController,
                child: Scrollbar(
                  controller: _horizontalController,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _horizontalController,
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: MediaQuery.sizeOf(context).width,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final line in lines) _PatchLineRow(line: line),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Previous file',
                onPressed: _selectedIndex == 0
                    ? null
                    : () => _selectFile(_selectedIndex - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: _showFilePicker,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text('${widget.result.files.length} changed files'),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Next file',
                onPressed: _selectedIndex == widget.result.files.length - 1
                    ? null
                    : () => _selectFile(_selectedIndex + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatchDisplayLine {
  const _PatchDisplayLine({required this.text, this.oldLine, this.newLine});

  final String text;
  final int? oldLine;
  final int? newLine;
}

List<_PatchDisplayLine> _parsePatchLines(String patch) {
  var oldLine = 0;
  var newLine = 0;
  final output = <_PatchDisplayLine>[];
  final hunk = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@');
  for (final text in patch.split('\n')) {
    final match = hunk.firstMatch(text);
    if (match != null) {
      oldLine = int.parse(match.group(1)!);
      newLine = int.parse(match.group(2)!);
      output.add(_PatchDisplayLine(text: text));
    } else if (text.startsWith('+') && !text.startsWith('+++')) {
      output.add(_PatchDisplayLine(text: text, newLine: newLine++));
    } else if (text.startsWith('-') && !text.startsWith('---')) {
      output.add(_PatchDisplayLine(text: text, oldLine: oldLine++));
    } else if (text.startsWith(' ')) {
      output.add(
        _PatchDisplayLine(text: text, oldLine: oldLine++, newLine: newLine++),
      );
    } else {
      output.add(_PatchDisplayLine(text: text));
    }
  }
  return output;
}

class _PatchLineRow extends StatelessWidget {
  const _PatchLineRow({required this.line});

  final _PatchDisplayLine line;

  @override
  Widget build(BuildContext context) {
    final added = line.text.startsWith('+') && !line.text.startsWith('+++');
    final deleted = line.text.startsWith('-') && !line.text.startsWith('---');
    final hunk = line.text.startsWith('@@');
    final background = added
        ? const Color(0xff12261b)
        : deleted
        ? const Color(0xff2d1719)
        : hunk
        ? const Color(0xff17263a)
        : Colors.transparent;
    final foreground = added
        ? const Color(0xffaff5b4)
        : deleted
        ? const Color(0xffffb8b0)
        : hunk
        ? const Color(0xffa5d6ff)
        : const Color(0xffd7e0dc);
    return Container(
      color: background,
      constraints: const BoxConstraints(minHeight: 23),
      child: Row(
        children: [
          _LineNumber(value: line.oldLine),
          _LineNumber(value: line.newLine),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: SelectableText(
              line.text,
              style: TextStyle(fontSize: 12.5, color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineNumber extends StatelessWidget {
  const _LineNumber({required this.value});

  final int? value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 7),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xff27312e))),
      ),
      child: Text(
        value?.toString() ?? '',
        style: const TextStyle(color: Color(0xff6e7b77), fontSize: 11),
      ),
    );
  }
}

class _FileBrowserPage extends StatefulWidget {
  const _FileBrowserPage({
    required this.result,
    required this.workdir,
    required this.onReadFile,
    required this.onBrowseDirectory,
  });

  final FileBrowserResult result;
  final String workdir;
  final Future<void> Function(String path) onReadFile;
  final Future<void> Function(String path) onBrowseDirectory;

  @override
  State<_FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<_FileBrowserPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FileBrowserEntry> get _visibleEntries {
    final query = _query.trim().toLowerCase();
    final entries = widget.result.entries.where((entry) {
      return query.isEmpty || entry.path.toLowerCase().contains(query);
    }).toList();
    entries.sort((left, right) {
      if (left.isDirectory != right.isDirectory) {
        return left.isDirectory ? -1 : 1;
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _visibleEntries;
    final searching = _query.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a file'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(68),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close),
                      ),
                hintText: 'Search repository files',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (!searching)
            _FileBreadcrumbs(
              path: widget.result.directory,
              onOpen: (path) => unawaited(widget.onBrowseDirectory(path)),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xff111816),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    searching
                        ? '${entries.length} search results'
                        : entries.isEmpty
                        ? 'Empty folder'
                        : '${entries.length} items',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                if (widget.result.truncated)
                  const Tooltip(
                    message: 'Large repository: showing a relay-safe subset',
                    child: Icon(Icons.info_outline, size: 18),
                  ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          searching
                              ? Icons.search_off
                              : Icons.folder_off_outlined,
                          size: 44,
                          color: const Color(0xff71817b),
                        ),
                        const SizedBox(height: 12),
                        Text(searching ? 'No matching files' : 'No files here'),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 64),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return ListTile(
                        leading: _BrowserFileIcon(entry: entry),
                        title: Text(
                          searching ? entry.path : entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: searching && entry.path != entry.name
                            ? Text(
                                entry.isDirectory ? 'Folder' : 'File',
                                style: Theme.of(context).textTheme.labelSmall,
                              )
                            : null,
                        trailing: Icon(
                          entry.isDirectory
                              ? Icons.chevron_right
                              : Icons.open_in_new,
                          size: 20,
                        ),
                        onTap: entry.isDirectory
                            ? () => unawaited(
                                widget.onBrowseDirectory(entry.path),
                              )
                            : () => widget.onReadFile(entry.path),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FileBreadcrumbs extends StatelessWidget {
  const _FileBreadcrumbs({required this.path, required this.onOpen});

  final String path;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final parts = path.isEmpty ? const <String>[] : path.split('/');
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          TextButton.icon(
            onPressed: () => onOpen(''),
            icon: const Icon(Icons.account_tree_outlined, size: 18),
            label: const Text('Repo'),
          ),
          for (var index = 0; index < parts.length; index++) ...[
            const Icon(Icons.chevron_right, size: 18),
            TextButton(
              onPressed: () => onOpen(parts.take(index + 1).join('/')),
              child: Text(parts[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _BrowserFileIcon extends StatelessWidget {
  const _BrowserFileIcon({required this.entry});

  final FileBrowserEntry entry;

  @override
  Widget build(BuildContext context) {
    if (entry.isDirectory) {
      return const Icon(Icons.folder_outlined, color: Color(0xffd29922));
    }
    final extension = entry.name.contains('.')
        ? entry.name.split('.').last.toLowerCase()
        : '';
    final (icon, color) = switch (extension) {
      'dart' => (Icons.flutter_dash, const Color(0xff58a6ff)),
      'rs' => (Icons.settings_outlined, const Color(0xfff0883e)),
      'md' => (Icons.article_outlined, const Color(0xffa5d6ff)),
      'json' ||
      'yaml' ||
      'yml' ||
      'toml' => (Icons.data_object, const Color(0xffd2a8ff)),
      'png' ||
      'jpg' ||
      'jpeg' ||
      'webp' ||
      'svg' => (Icons.image_outlined, const Color(0xff3fb950)),
      _ => (Icons.description_outlined, const Color(0xff8b949e)),
    };
    return Icon(icon, color: color);
  }
}

class _FileViewerPage extends StatefulWidget {
  const _FileViewerPage({required this.result, required this.workdir});

  final FileContentResult result;
  final String workdir;

  @override
  State<_FileViewerPage> createState() => _FileViewerPageState();
}

class _FileViewerPageState extends State<_FileViewerPage> {
  static const _lineHeight = 23.0;
  final _searchController = TextEditingController();
  final _verticalController = ScrollController();
  final _horizontalController = ScrollController();
  late final List<String> _lines;
  List<int> _matches = const [];
  int _matchIndex = 0;

  @override
  void initState() {
    super.initState();
    _lines = widget.result.content.split('\n');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  void _search(String query) {
    final cleaned = query.toLowerCase();
    final matches = <int>[];
    if (cleaned.isNotEmpty) {
      for (var index = 0; index < _lines.length; index++) {
        if (_lines[index].toLowerCase().contains(cleaned)) matches.add(index);
      }
    }
    setState(() {
      _matches = matches;
      _matchIndex = 0;
    });
    if (matches.isNotEmpty) _jumpToMatch();
  }

  void _moveMatch(int direction) {
    if (_matches.isEmpty) return;
    setState(() {
      _matchIndex = (_matchIndex + direction) % _matches.length;
      if (_matchIndex < 0) _matchIndex += _matches.length;
    });
    _jumpToMatch();
  }

  void _jumpToMatch() {
    if (!_verticalController.hasClients || _matches.isEmpty) return;
    final offset = (_matches[_matchIndex] * _lineHeight).clamp(
      0.0,
      _verticalController.position.maxScrollExtent,
    );
    _verticalController.animateTo(
      offset,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final matchSet = _matches.toSet();
    final maxLineLength = _lines.fold<int>(
      0,
      (value, line) => math.max(value, line.length),
    );
    final contentWidth = math.max(
      MediaQuery.sizeOf(context).width,
      110 + maxLineLength * 7.7,
    );
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.result.path.split('/').last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${widget.result.lineCount} lines',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: const BoxDecoration(
              color: Color(0xff111816),
              border: Border(bottom: BorderSide(color: Color(0xff2b3935))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Find in file',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 58,
                  child: Text(
                    _matches.isEmpty
                        ? '0/0'
                        : '${_matchIndex + 1}/${_matches.length}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Previous match',
                  onPressed: _matches.isEmpty ? null : () => _moveMatch(-1),
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  tooltip: 'Next match',
                  onPressed: _matches.isEmpty ? null : () => _moveMatch(1),
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
              ],
            ),
          ),
          if (widget.result.truncated)
            const MaterialBanner(
              content: Text('Large file: showing the first 40,000 characters.'),
              actions: [SizedBox.shrink()],
            ),
          Expanded(
            child: Scrollbar(
              controller: _verticalController,
              child: SingleChildScrollView(
                controller: _verticalController,
                child: Scrollbar(
                  controller: _horizontalController,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _horizontalController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: contentWidth,
                      child: Column(
                        children: [
                          for (var index = 0; index < _lines.length; index++)
                            Container(
                              height: _lineHeight,
                              color: matchSet.contains(index)
                                  ? const Color(0xff342b10)
                                  : index.isEven
                                  ? const Color(0xff0d1311)
                                  : const Color(0xff0f1513),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 58,
                                    child: Text(
                                      '${index + 1}',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        color: Color(0xff687570),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: SelectableText(
                                      _lines[index],
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: Color(0xffd7e0dc),
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkingFolderSelection {
  const _WorkingFolderSelection({this.path, this.label});

  final String? path;
  final String? label;
}

class _WorkingFolderPickerPage extends StatefulWidget {
  const _WorkingFolderPickerPage({
    required this.initialChoices,
    required this.selectedPath,
    required this.onLoadFolders,
  });

  final List<RepoChoice> initialChoices;
  final String selectedPath;
  final Future<List<RepoChoice>> Function(String? path) onLoadFolders;

  @override
  State<_WorkingFolderPickerPage> createState() =>
      _WorkingFolderPickerPageState();
}

class _WorkingFolderPickerPageState extends State<_WorkingFolderPickerPage> {
  final _searchController = TextEditingController();
  bool _loadingFolders = false;
  String _searchQuery = '';
  String _currentPath = '';
  String? _selectedPath;
  List<RepoChoice> _choices = const [];

  @override
  void initState() {
    super.initState();
    _choices = widget.initialChoices;
    _selectedPath = widget.selectedPath.isEmpty ? null : widget.selectedPath;
    unawaited(_loadFolders());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFolders([String? path]) async {
    setState(() => _loadingFolders = true);
    try {
      final choices = await widget.onLoadFolders(path);
      if (!mounted) return;
      setState(() {
        _choices = choices;
        _currentPath = path ?? '';
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load folders: $error')));
    } finally {
      if (mounted) setState(() => _loadingFolders = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final visibleChoices = query.isEmpty
        ? _choices
        : _choices.where((choice) {
            return choice.displayName.toLowerCase().contains(query) ||
                choice.relativePath.toLowerCase().contains(query);
          }).toList();
    final selectedChoice = _choices.where(
      (choice) => choice.path == _selectedPath,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Working folder'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const _WorkingFolderSelection()),
            child: const Text('Worker default'),
          ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.settings_backup_restore_outlined),
            title: const Text('Worker default'),
            subtitle: const Text('No folder override for this agent'),
            selected: _selectedPath == null,
            onTap: () =>
                Navigator.pop(context, const _WorkingFolderSelection()),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search folders',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh folders',
                  onPressed: _loadingFolders
                      ? null
                      : () => _loadFolders(
                          _currentPath.isEmpty ? null : _currentPath,
                        ),
                  icon: _loadingFolders
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Up one folder',
                  onPressed: _currentPath.isEmpty || _loadingFolders
                      ? null
                      : () {
                          final parts = _currentPath.split('/');
                          parts.removeLast();
                          _loadFolders(parts.isEmpty ? null : parts.join('/'));
                        },
                  icon: const Icon(Icons.arrow_upward),
                ),
                Expanded(
                  child: Text(
                    _currentPath.isEmpty ? 'Worker root' : _currentPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loadingFolders && _choices.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : visibleChoices.isEmpty
                ? const Center(child: Text('No matching folders'))
                : RadioGroup<String>(
                    groupValue: _selectedPath,
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedPath = value);
                    },
                    child: ListView.separated(
                      itemCount: visibleChoices.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 64),
                      itemBuilder: (context, index) {
                        final choice = visibleChoices[index];
                        return ListTile(
                          selected: _selectedPath == choice.path,
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
                          subtitle: Text(
                            choice.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(),
                          ),
                          trailing: Radio<String>(value: choice.path),
                          onTap: () => _loadFolders(choice.relativePath),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: selectedChoice.isEmpty
                ? null
                : () {
                    final choice = selectedChoice.first;
                    Navigator.pop(
                      context,
                      _WorkingFolderSelection(
                        path: choice.path,
                        label: choice.displayName,
                      ),
                    );
                  },
            icon: const Icon(Icons.folder_open),
            label: const Text('Use folder'),
          ),
        ),
      ),
    );
  }
}

class _SpawnSessionPage extends StatefulWidget {
  const _SpawnSessionPage({
    required this.initialRepoChoices,
    required this.onLoadRepos,
  });

  final List<RepoChoice> initialRepoChoices;
  final Future<List<RepoChoice>> Function(String? path) onLoadRepos;

  @override
  State<_SpawnSessionPage> createState() => _SpawnSessionPageState();
}

class _SpawnSessionPageState extends State<_SpawnSessionPage> {
  final _pathController = TextEditingController();
  final _searchController = TextEditingController();
  bool _create = false;
  bool _loadingRepos = false;
  String _searchQuery = '';
  String _currentPath = '';
  String? _selectedPath;
  List<RepoChoice> _repoChoices = const [];

  @override
  void initState() {
    super.initState();
    _repoChoices = widget.initialRepoChoices;
    unawaited(_loadRepos());
  }

  @override
  void dispose() {
    _pathController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String? _validationError(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return 'Path is required';
    if (cleaned.contains('\x00')) return 'Path contains an invalid character';
    if (cleaned.split('/').any((part) => part == '..')) {
      return 'Folder name cannot contain ..';
    }
    return null;
  }

  Future<void> _loadRepos([String? path]) async {
    setState(() => _loadingRepos = true);
    try {
      final choices = await widget.onLoadRepos(path);
      if (!mounted) return;
      setState(() {
        _repoChoices = choices;
        _currentPath = path ?? '';
      });
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
    final query = _searchQuery.trim().toLowerCase();
    final visibleChoices = query.isEmpty
        ? _repoChoices
        : _repoChoices.where((choice) {
            return choice.displayName.toLowerCase().contains(query) ||
                choice.relativePath.toLowerCase().contains(query);
          }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Spawn session')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
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
                  final create = selection.first;
                  setState(() => _create = create);
                  if (!create && _repoChoices.isEmpty && !_loadingRepos) {
                    unawaited(_loadRepos());
                  }
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _pathController,
              autofocus: _create,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _selectedPath = null),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                helperText: _create
                    ? 'Created inside an allowed worker root'
                    : 'Select below or enter a nested allowed folder, e.g. buzz/buzz',
                labelText: _create ? 'New folder' : 'Selected folder',
                hintText: _create ? 'my-new-project' : 'buzz/buzz',
              ),
            ),
          ),
          if (_create)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.create_new_folder_outlined, size: 64),
                      SizedBox(height: 18),
                      Text(
                        'Create a new repo session',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'The worker creates the folder, starts a routed session, and sends this phone a target invite.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search folders',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh folders',
                    onPressed: _loadingRepos
                        ? null
                        : () => _loadRepos(
                            _currentPath.isEmpty ? null : _currentPath,
                          ),
                    icon: _loadingRepos
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Up one folder',
                    onPressed: _currentPath.isEmpty || _loadingRepos
                        ? null
                        : () {
                            final parts = _currentPath.split('/');
                            parts.removeLast();
                            _loadRepos(parts.isEmpty ? null : parts.join('/'));
                          },
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  Expanded(
                    child: Text(
                      _currentPath.isEmpty ? 'Worker root' : _currentPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loadingRepos && _repoChoices.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : visibleChoices.isEmpty
                  ? const Center(child: Text('No matching folders'))
                  : RadioGroup<String>(
                      groupValue: _selectedPath,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedPath = value;
                          _pathController.text = value;
                        });
                      },
                      child: ListView.separated(
                        itemCount: visibleChoices.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 64),
                        itemBuilder: (context, index) {
                          final choice = visibleChoices[index];
                          final selected = _selectedPath == choice.relativePath;
                          return ListTile(
                            selected: selected,
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
                            subtitle: Text(
                              choice.relativePath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(),
                            ),
                            trailing: Radio<String>(value: choice.relativePath),
                            onTap: () {
                              _loadRepos(choice.relativePath);
                            },
                          );
                        },
                      ),
                    ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _submit,
            icon: Icon(_create ? Icons.add : Icons.folder_open),
            label: Text(_create ? 'Create session' : 'Open session'),
          ),
        ),
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.theme,
    required this.repoTargets,
    required this.computerServiceTarget,
    required this.selectedRepoTargetId,
    required this.activeTargetName,
    required this.profileNameController,
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
    required this.workingAnimationSpeed,
    required this.recordingWaveformSensitivity,
    required this.recordingWaveformBars,
    required this.recordingWaveformDecay,
    required this.recordingWaveformCompression,
    required this.recordingWaveformDuration,
    required this.recordingWaveformRmsSmoothing,
    required this.hapticFeedbackEnabled,
    required this.receiveVibrationEnabled,
    required this.inactiveReplyPopupEnabled,
    required this.inactiveReplyAudioEnabled,
    required this.backgroundDeliveryEnabled,
    required this.language,
    required this.languages,
    required this.engine,
    required this.engines,
    required this.rate,
    required this.pitch,
    required this.volume,
    required this.checkingRelays,
    required this.relayResults,
    required this.messagesInActiveConversation,
    required this.onThemeChanged,
    required this.onTargetChanged,
    required this.onProfileNameChanged,
    required this.onSaveTarget,
    required this.onNewTarget,
    required this.onScanTarget,
    required this.onPasteTarget,
    required this.onEnterInviteCode,
    required this.onDeleteTarget,
    required this.onGenerateKey,
    required this.onSecretChanged,
    required this.onConnect,
    required this.onDisconnect,
    required this.onCheckRelayStatus,
    required this.onStop,
    required this.onReplay,
    required this.onAutoSpeakChanged,
    required this.onWorkingAnimationChanged,
    required this.onWorkingAnimationSpeedChanged,
    required this.onRecordingWaveformSensitivityChanged,
    required this.onRecordingWaveformBarsChanged,
    required this.onRecordingWaveformDecayChanged,
    required this.onRecordingWaveformCompressionChanged,
    required this.onRecordingWaveformDurationChanged,
    required this.onRecordingWaveformRmsSmoothingChanged,
    required this.onHapticFeedbackChanged,
    required this.onReceiveVibrationChanged,
    required this.onInactiveReplyPopupChanged,
    required this.onInactiveReplyAudioChanged,
    required this.onBackgroundDeliveryChanged,
    required this.onLanguageChanged,
    required this.onEngineChanged,
    required this.onRateChanged,
    required this.onPitchChanged,
    required this.onVolumeChanged,
    required this.onSliderChangeEnd,
    required this.onTest,
    required this.onExportProfile,
    required this.onImportProfile,
  });

  final AppTheme theme;
  final List<RepoTarget> repoTargets;
  final RepoTarget? computerServiceTarget;
  final String? selectedRepoTargetId;
  final String activeTargetName;
  final TextEditingController profileNameController;
  final TextEditingController targetNameController;
  final TextEditingController secretKeyController;
  final TextEditingController peerPubkeyController;
  final TextEditingController relayController;
  final TextEditingController blossomServerController;
  final List<BlossomPreset> blossomPresets;
  final String? ownPubkey;
  final bool connected;
  final bool connecting;
  final bool speaking;
  final bool hasReplay;
  final bool autoSpeak;
  final WorkingAnimationStyle workingAnimationStyle;
  final double workingAnimationSpeed;
  final double recordingWaveformSensitivity;
  final int recordingWaveformBars;
  final double recordingWaveformDecay;
  final double recordingWaveformCompression;
  final double recordingWaveformDuration;
  final double recordingWaveformRmsSmoothing;
  final bool hapticFeedbackEnabled;
  final bool receiveVibrationEnabled;
  final bool inactiveReplyPopupEnabled;
  final bool inactiveReplyAudioEnabled;
  final bool backgroundDeliveryEnabled;
  final String language;
  final List<String> languages;
  final String? engine;
  final List<String> engines;
  final double rate;
  final double pitch;
  final double volume;
  final bool checkingRelays;
  final List<_RelayProbeResult> relayResults;
  final int messagesInActiveConversation;
  final ValueChanged<AppTheme> onThemeChanged;
  final ValueChanged<String?> onTargetChanged;
  final ValueChanged<String> onProfileNameChanged;
  final VoidCallback onSaveTarget;
  final VoidCallback onNewTarget;
  final VoidCallback onScanTarget;
  final VoidCallback onPasteTarget;
  final VoidCallback onEnterInviteCode;
  final VoidCallback? onDeleteTarget;
  final VoidCallback onGenerateKey;
  final ValueChanged<String> onSecretChanged;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onCheckRelayStatus;
  final VoidCallback onStop;
  final VoidCallback onReplay;
  final ValueChanged<bool> onAutoSpeakChanged;
  final ValueChanged<WorkingAnimationStyle> onWorkingAnimationChanged;
  final ValueChanged<double> onWorkingAnimationSpeedChanged;
  final ValueChanged<double> onRecordingWaveformSensitivityChanged;
  final ValueChanged<double> onRecordingWaveformBarsChanged;
  final ValueChanged<double> onRecordingWaveformDecayChanged;
  final ValueChanged<double> onRecordingWaveformCompressionChanged;
  final ValueChanged<double> onRecordingWaveformDurationChanged;
  final ValueChanged<double> onRecordingWaveformRmsSmoothingChanged;
  final ValueChanged<bool> onHapticFeedbackChanged;
  final ValueChanged<bool> onReceiveVibrationChanged;
  final ValueChanged<bool> onInactiveReplyPopupChanged;
  final ValueChanged<bool> onInactiveReplyAudioChanged;
  final ValueChanged<bool> onBackgroundDeliveryChanged;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<String?> onEngineChanged;
  final ValueChanged<double> onRateChanged;
  final ValueChanged<double> onPitchChanged;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onSliderChangeEnd;
  final VoidCallback onTest;
  final VoidCallback onExportProfile;
  final VoidCallback onImportProfile;

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: profileNameController,
                textInputAction: TextInputAction.done,
                onSubmitted: onProfileNameChanged,
                decoration: InputDecoration(
                  labelText: 'Profile name',
                  hintText: 'How workspace members see you',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Save profile name',
                    icon: const Icon(Icons.save_outlined),
                    onPressed: () =>
                        onProfileNameChanged(profileNameController.text),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ThemeSettings(theme: theme, onChanged: onThemeChanged),
          const SizedBox(height: 16),
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
            checkingRelays: checkingRelays,
            relayResults: relayResults,
            onTargetChanged: onTargetChanged,
            onSaveTarget: onSaveTarget,
            onNewTarget: onNewTarget,
            onScanTarget: onScanTarget,
            onPasteTarget: onPasteTarget,
            onEnterInviteCode: onEnterInviteCode,
            onDeleteTarget: onDeleteTarget,
            onGenerateKey: onGenerateKey,
            onSecretChanged: onSecretChanged,
            onConnect: onConnect,
            onDisconnect: onDisconnect,
            onCheckRelayStatus: onCheckRelayStatus,
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
            initialSpeed: workingAnimationSpeed,
            onChanged: onWorkingAnimationChanged,
            onSpeedChanged: onWorkingAnimationSpeedChanged,
          ),
          const SizedBox(height: 16),
          _RecordingWaveformSettings(
            initialSensitivity: recordingWaveformSensitivity,
            initialBars: recordingWaveformBars,
            initialDecay: recordingWaveformDecay,
            initialCompression: recordingWaveformCompression,
            initialDuration: recordingWaveformDuration,
            initialRmsSmoothing: recordingWaveformRmsSmoothing,
            onSensitivityChanged: onRecordingWaveformSensitivityChanged,
            onBarsChanged: onRecordingWaveformBarsChanged,
            onDecayChanged: onRecordingWaveformDecayChanged,
            onCompressionChanged: onRecordingWaveformCompressionChanged,
            onDurationChanged: onRecordingWaveformDurationChanged,
            onRmsSmoothingChanged: onRecordingWaveformRmsSmoothingChanged,
          ),
          const SizedBox(height: 16),
          _HapticFeedbackSettings(
            initialEnabled: hapticFeedbackEnabled,
            initialReceiveVibrationEnabled: receiveVibrationEnabled,
            initialInactiveReplyPopupEnabled: inactiveReplyPopupEnabled,
            initialInactiveReplyAudioEnabled: inactiveReplyAudioEnabled,
            onChanged: onHapticFeedbackChanged,
            onReceiveVibrationChanged: onReceiveVibrationChanged,
            onInactiveReplyPopupChanged: onInactiveReplyPopupChanged,
            onInactiveReplyAudioChanged: onInactiveReplyAudioChanged,
          ),
          const SizedBox(height: 16),
          _BackgroundDeliverySettings(
            enabled: backgroundDeliveryEnabled,
            onChanged: onBackgroundDeliveryChanged,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('App info', style: materialTheme.textTheme.titleMedium),
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
                    Text('Local pubkey: ${compactIdentifier(ownPubkey!)}'),
                  if (ownPubkey == null || ownPubkey!.isEmpty)
                    const Text('Local pubkey not available'),
                  Text(
                    computerServiceTarget == null
                        ? 'Computer service: not saved'
                        : 'Computer service: ${computerServiceTarget!.displayName}',
                  ),
                  Text('Total saved sessions: ${repoTargets.length}'),
                  const Text('Version: $_appVersion'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onExportProfile,
                        icon: const Icon(Icons.file_upload_outlined),
                        label: const Text('Export profile'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onImportProfile,
                        icon: const Icon(Icons.file_download_outlined),
                        label: const Text('Import profile'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeSettings extends StatelessWidget {
  const _ThemeSettings({required this.theme, required this.onChanged});

  final AppTheme theme;
  final ValueChanged<AppTheme> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<_WorkspacePalette>()!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Choose the workspace color system.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            RadioGroup<AppTheme>(
              groupValue: theme,
              onChanged: (value) {
                if (value != null) onChanged(value);
              },
              child: Column(
                children: [
                  for (final option in AppTheme.values)
                    RadioListTile<AppTheme>(
                      contentPadding: EdgeInsets.zero,
                      value: option,
                      title: Text(option.label),
                      subtitle: Text(option.description),
                      secondary: _ThemeSwatch(theme: option),
                    ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              height: 1,
              color: palette.label.withValues(alpha: 0.25),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final ember = theme == AppTheme.ember;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: ember ? const Color(0xff161615) : const Color(0xff142321),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ember ? const Color(0xffffb74d) : const Color(0xff65d8b1),
        ),
      ),
      child: Center(
        child: Container(
          width: 14,
          height: 4,
          color: ember ? const Color(0xff56d8d2) : const Color(0xff9cc6bb),
        ),
      ),
    );
  }
}

class _BackgroundDeliverySettings extends StatefulWidget {
  const _BackgroundDeliverySettings({
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  State<_BackgroundDeliverySettings> createState() =>
      _BackgroundDeliverySettingsState();
}

class _BackgroundDeliverySettingsState
    extends State<_BackgroundDeliverySettings> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.enabled;
  }

  @override
  void didUpdateWidget(covariant _BackgroundDeliverySettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _enabled = widget.enabled;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        secondary: const Icon(Icons.cloud_sync_outlined),
        title: const Text('Background delivery'),
        subtitle: const Text(
          'Keep receiving replies while Ribbit is in the background. Android shows a persistent notification.',
        ),
        value: _enabled,
        onChanged: (enabled) {
          setState(() => _enabled = enabled);
          widget.onChanged(enabled);
        },
      ),
    );
  }
}

class _WorkingAnimationSettings extends StatefulWidget {
  const _WorkingAnimationSettings({
    required this.initialStyle,
    required this.initialSpeed,
    required this.onChanged,
    required this.onSpeedChanged,
  });

  final WorkingAnimationStyle initialStyle;
  final double initialSpeed;
  final ValueChanged<WorkingAnimationStyle> onChanged;
  final ValueChanged<double> onSpeedChanged;

  @override
  State<_WorkingAnimationSettings> createState() =>
      _WorkingAnimationSettingsState();
}

class _WorkingAnimationSettingsState extends State<_WorkingAnimationSettings> {
  late WorkingAnimationStyle _selectedStyle;
  late double _speed;

  @override
  void initState() {
    super.initState();
    _selectedStyle = widget.initialStyle;
    _speed = widget.initialSpeed;
  }

  @override
  void didUpdateWidget(covariant _WorkingAnimationSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStyle != widget.initialStyle) {
      _selectedStyle = widget.initialStyle;
    }
    if (oldWidget.initialSpeed != widget.initialSpeed) {
      _speed = widget.initialSpeed;
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
                  child: DropdownButtonFormField<WorkingAnimationStyle>(
                    initialValue: _selectedStyle,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Processing style',
                    ),
                    items: [
                      for (final style in WorkingAnimationStyle.values)
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
                        ? DigitalThinkingIndicator(
                            width: 64,
                            height: 28,
                            color: theme.colorScheme.primary,
                            style: _selectedStyle,
                            speed: _speed,
                          )
                        : Text('Off', style: theme.textTheme.labelMedium),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.speed, size: 20),
                const SizedBox(width: 8),
                Text('Speed', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text('${_speed.toStringAsFixed(1)}x'),
              ],
            ),
            Slider(
              min: 0.1,
              max: 5.0,
              divisions: 49,
              label: '${_speed.toStringAsFixed(1)}x',
              value: _speed,
              onChanged: _selectedStyle.enabled
                  ? (value) {
                      setState(() => _speed = value);
                      widget.onSpeedChanged(value);
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingWaveformSettings extends StatefulWidget {
  const _RecordingWaveformSettings({
    required this.initialSensitivity,
    required this.initialBars,
    required this.initialDecay,
    required this.initialCompression,
    required this.initialDuration,
    required this.initialRmsSmoothing,
    required this.onSensitivityChanged,
    required this.onBarsChanged,
    required this.onDecayChanged,
    required this.onCompressionChanged,
    required this.onDurationChanged,
    required this.onRmsSmoothingChanged,
  });

  final double initialSensitivity;
  final int initialBars;
  final double initialDecay;
  final double initialCompression;
  final double initialDuration;
  final double initialRmsSmoothing;
  final ValueChanged<double> onSensitivityChanged;
  final ValueChanged<double> onBarsChanged;
  final ValueChanged<double> onDecayChanged;
  final ValueChanged<double> onCompressionChanged;
  final ValueChanged<double> onDurationChanged;
  final ValueChanged<double> onRmsSmoothingChanged;

  @override
  State<_RecordingWaveformSettings> createState() =>
      _RecordingWaveformSettingsState();
}

class _RecordingWaveformSettingsState
    extends State<_RecordingWaveformSettings> {
  late double _sensitivity;
  late double _decay;
  late double _compression;
  late double _duration;
  late double _rmsSmoothing;

  @override
  void initState() {
    super.initState();
    _sensitivity = widget.initialSensitivity;
    _decay = widget.initialDecay;
    _compression = widget.initialCompression;
    _duration = widget.initialDuration;
    _rmsSmoothing = widget.initialRmsSmoothing;
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
            Text('Recording waveform', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Tune the live rolling waveform while recording.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _WaveformSlider(
              label: 'History and travel time',
              valueLabel: '${_duration.toStringAsFixed(1)} s',
              value: _duration,
              min: 0.1,
              max: 20,
              divisions: 199,
              onChanged: (value) {
                setState(() => _duration = value);
                widget.onDurationChanged(value);
              },
            ),
            _WaveformSlider(
              label: 'RMS averaging',
              valueLabel: _rmsSmoothing == 0
                  ? 'Off'
                  : '${(_rmsSmoothing * 1000).round()} ms',
              value: _rmsSmoothing,
              min: 0,
              max: 1,
              divisions: 20,
              onChanged: (value) {
                setState(() => _rmsSmoothing = value);
                widget.onRmsSmoothingChanged(value);
              },
            ),
            _WaveformSlider(
              label: 'Sensitivity',
              valueLabel: '${_sensitivity.toStringAsFixed(1)}x',
              value: _sensitivity,
              min: 0.5,
              max: 2.0,
              divisions: 15,
              onChanged: (value) {
                setState(() => _sensitivity = value);
                widget.onSensitivityChanged(value);
              },
            ),
            _WaveformSlider(
              label: 'Fade to silence',
              valueLabel: '${_decay.toStringAsFixed(1)}x',
              value: _decay,
              min: 0.1,
              max: 10.0,
              divisions: 99,
              onChanged: (value) {
                setState(() => _decay = value);
                widget.onDecayChanged(value);
              },
            ),
            _WaveformSlider(
              label: 'Compression',
              valueLabel: _compressionLabel,
              value: _compression,
              min: 0,
              max: 1,
              divisions: 20,
              onChanged: (value) {
                setState(() => _compression = value);
                widget.onCompressionChanged(value);
              },
            ),
          ],
        ),
      ),
    );
  }

  String get _compressionLabel {
    if (_compression < 0.45) {
      return 'Expand ${((0.5 - _compression) * 200).round()}%';
    }
    if (_compression > 0.55) {
      return 'Compress ${((_compression - 0.5) * 200).round()}%';
    }
    return 'Neutral';
  }
}

class _WaveformSlider extends StatelessWidget {
  const _WaveformSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            Text(valueLabel),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueLabel,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _HapticFeedbackSettings extends StatefulWidget {
  const _HapticFeedbackSettings({
    required this.initialEnabled,
    required this.initialReceiveVibrationEnabled,
    required this.initialInactiveReplyPopupEnabled,
    required this.initialInactiveReplyAudioEnabled,
    required this.onChanged,
    required this.onReceiveVibrationChanged,
    required this.onInactiveReplyPopupChanged,
    required this.onInactiveReplyAudioChanged,
  });

  final bool initialEnabled;
  final bool initialReceiveVibrationEnabled;
  final bool initialInactiveReplyPopupEnabled;
  final bool initialInactiveReplyAudioEnabled;
  final ValueChanged<bool> onChanged;
  final ValueChanged<bool> onReceiveVibrationChanged;
  final ValueChanged<bool> onInactiveReplyPopupChanged;
  final ValueChanged<bool> onInactiveReplyAudioChanged;

  @override
  State<_HapticFeedbackSettings> createState() =>
      _HapticFeedbackSettingsState();
}

class _HapticFeedbackSettingsState extends State<_HapticFeedbackSettings> {
  late bool _enabled;
  late bool _receiveVibrationEnabled;
  late bool _inactiveReplyPopupEnabled;
  late bool _inactiveReplyAudioEnabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.initialEnabled;
    _receiveVibrationEnabled = widget.initialReceiveVibrationEnabled;
    _inactiveReplyPopupEnabled = widget.initialInactiveReplyPopupEnabled;
    _inactiveReplyAudioEnabled = widget.initialInactiveReplyAudioEnabled;
  }

  @override
  void didUpdateWidget(covariant _HapticFeedbackSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialEnabled != widget.initialEnabled) {
      _enabled = widget.initialEnabled;
    }
    if (oldWidget.initialReceiveVibrationEnabled !=
        widget.initialReceiveVibrationEnabled) {
      _receiveVibrationEnabled = widget.initialReceiveVibrationEnabled;
    }
    if (oldWidget.initialInactiveReplyPopupEnabled !=
        widget.initialInactiveReplyPopupEnabled) {
      _inactiveReplyPopupEnabled = widget.initialInactiveReplyPopupEnabled;
    }
    if (oldWidget.initialInactiveReplyAudioEnabled !=
        widget.initialInactiveReplyAudioEnabled) {
      _inactiveReplyAudioEnabled = widget.initialInactiveReplyAudioEnabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Haptic feedback'),
            subtitle: const Text('Record start and send taps'),
            value: _enabled,
            onChanged: (enabled) {
              setState(() => _enabled = enabled);
              widget.onChanged(enabled);
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Vibrate on received messages'),
            subtitle: const Text('Live session replies and transcripts'),
            value: _receiveVibrationEnabled,
            onChanged: (enabled) {
              setState(() => _receiveVibrationEnabled = enabled);
              widget.onReceiveVibrationChanged(enabled);
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.mark_chat_unread_outlined),
            title: const Text('Show inactive session replies'),
            subtitle: const Text('Popup alert for live replies'),
            value: _inactiveReplyPopupEnabled,
            onChanged: (enabled) {
              setState(() => _inactiveReplyPopupEnabled = enabled);
              widget.onInactiveReplyPopupChanged(enabled);
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('Play inactive session alert'),
            subtitle: const Text('System sound for live replies'),
            value: _inactiveReplyAudioEnabled,
            onChanged: (enabled) {
              setState(() => _inactiveReplyAudioEnabled = enabled);
              widget.onInactiveReplyAudioChanged(enabled);
            },
          ),
        ],
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
    required this.checkingRelays,
    required this.relayResults,
    required this.onTargetChanged,
    required this.onSaveTarget,
    required this.onNewTarget,
    required this.onScanTarget,
    required this.onPasteTarget,
    required this.onEnterInviteCode,
    required this.onDeleteTarget,
    required this.onGenerateKey,
    required this.onSecretChanged,
    required this.onConnect,
    required this.onDisconnect,
    required this.onCheckRelayStatus,
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

  final List<RepoTarget> repoTargets;
  final String? selectedRepoTargetId;
  final String activeTargetName;
  final TextEditingController targetNameController;
  final TextEditingController secretKeyController;
  final TextEditingController peerPubkeyController;
  final TextEditingController relayController;
  final TextEditingController blossomServerController;
  final List<BlossomPreset> blossomPresets;
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
  final bool checkingRelays;
  final List<_RelayProbeResult> relayResults;
  final ValueChanged<String?> onTargetChanged;
  final VoidCallback onSaveTarget;
  final VoidCallback onNewTarget;
  final VoidCallback onScanTarget;
  final VoidCallback onPasteTarget;
  final VoidCallback onEnterInviteCode;
  final VoidCallback? onDeleteTarget;
  final VoidCallback onGenerateKey;
  final ValueChanged<String> onSecretChanged;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onCheckRelayStatus;
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
            Text('Settings', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Text('Repo target', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: targetValue,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Active worker target',
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
                if (_supportsCameraQrScan)
                  TextButton.icon(
                    onPressed: connecting ? null : onScanTarget,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan'),
                  ),
                TextButton.icon(
                  onPressed: connecting ? null : onPasteTarget,
                  icon: const Icon(Icons.content_paste_go_outlined),
                  label: const Text('Paste target'),
                ),
                IconButton(
                  tooltip: 'Delete target',
                  onPressed: connecting ? null : onDeleteTarget,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: connecting ? null : onEnterInviteCode,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Enter workspace invite code'),
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
                IconButton(
                  tooltip: 'Copy local pubkey',
                  onPressed: ownPubkey == null || ownPubkey!.isEmpty
                      ? null
                      : () => _copyOwnPubkey(context),
                  icon: const Icon(Icons.content_copy),
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
              enabled: !connecting,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Home npub',
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
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: checkingRelays ? null : onCheckRelayStatus,
              icon: checkingRelays
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check),
              label: Text(checkingRelays ? 'Checking relays' : 'Check relays'),
            ),
            if (relayResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final result in relayResults)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _relayProbeIcon(result),
                    color: _relayProbeColor(colorScheme, result),
                  ),
                  title: Text(
                    result.relay,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    result.error == null
                        ? result.label
                        : '${result.label}: ${result.error}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
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

  Future<void> _copyOwnPubkey(BuildContext context) async {
    final pubkey = ownPubkey;
    if (pubkey == null || pubkey.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: pubkey));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied local pubkey')));
  }
}

IconData _relayProbeIcon(_RelayProbeResult result) {
  return switch (result.strength) {
    _RelayProbeStrength.strong => Icons.check_circle,
    _RelayProbeStrength.fair => Icons.check_circle_outline,
    _RelayProbeStrength.weak => Icons.speed,
    _RelayProbeStrength.offline => Icons.error_outline,
  };
}

Color _relayProbeColor(ColorScheme colorScheme, _RelayProbeResult result) {
  return switch (result.strength) {
    _RelayProbeStrength.strong => colorScheme.primary,
    _RelayProbeStrength.fair => colorScheme.secondary,
    _RelayProbeStrength.weak => colorScheme.tertiary,
    _RelayProbeStrength.offline => colorScheme.error,
  };
}

class _SpeechSlider extends StatefulWidget {
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
  State<_SpeechSlider> createState() => _SpeechSliderState();
}

class _SpeechSliderState extends State<_SpeechSlider> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void didUpdateWidget(covariant _SpeechSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _value = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _value.clamp(widget.min, widget.max).toDouble();
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(widget.label)),
            Text(value.toStringAsFixed(2)),
          ],
        ),
        Slider(
          value: value,
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          label: value.toStringAsFixed(2),
          onChanged: (next) {
            setState(() => _value = next);
            widget.onChanged(next);
          },
          onChangeEnd: widget.onChangeEnd,
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

class _OpenCodeToolsPage extends StatelessWidget {
  const _OpenCodeToolsPage();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('OpenCode tools')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
              child: Text(
                'Control the active OpenCode session and repository workflow',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            _OpenCodeToolTile(
              icon: Icons.info_outline,
              title: 'Session status',
              subtitle: 'Inspect the active agent session',
              value: 'status',
            ),
            _OpenCodeToolTile(
              icon: Icons.stop_circle_outlined,
              title: 'Stop current task',
              subtitle: 'Cancel the active agent task',
              value: 'stop',
              destructive: true,
            ),
            _OpenCodeToolTile(
              icon: Icons.history,
              title: 'Task history',
              subtitle: 'Review recent agent activity',
              value: 'history',
            ),
            const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                'Repository tools',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            _OpenCodeToolTile(
              icon: Icons.account_tree_outlined,
              title: 'Git status',
              subtitle: 'Review changed files and repository state',
              value: 'git_status',
            ),
            _OpenCodeToolTile(
              icon: Icons.difference_outlined,
              title: 'File diff',
              subtitle: 'View pending source changes',
              value: 'diff',
            ),
            _OpenCodeToolTile(
              icon: Icons.description_outlined,
              title: 'Read file',
              subtitle: 'Browse and open repository files',
              value: 'file_browser',
            ),
            const Divider(height: 32),
            _OpenCodeToolTile(
              icon: Icons.commit,
              title: 'Commit prep',
              subtitle: 'Prepare a source-control commit',
              value: 'commit_help',
            ),
            _OpenCodeToolTile(
              icon: Icons.rocket_launch_outlined,
              title: 'Release workflow',
              subtitle: 'Review release steps and artifacts',
              value: 'release_help',
            ),
            const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                'OpenCode',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            _OpenCodeToolTile(
              icon: Icons.memory,
              title: 'Choose model',
              subtitle: 'Select a configured OpenCode model',
              value: 'model_config',
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenCodeToolTile extends StatelessWidget {
  const _OpenCodeToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = destructive ? colorScheme.error : colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pop(value),
      ),
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
    required this.transcribingAudio,
    required this.sendingMedia,
    required this.activeSendBlocked,
    required this.recording,
    required this.recordingWaveformLevel,
    required this.recordingWaveformBars,
    required this.recordingWaveformDecay,
    required this.recordingWaveformCompression,
    required this.recordingWaveformDuration,
    required this.recordingWaveformRmsSmoothing,
    required this.recordingDurationLabel,
    required this.voiceSendWipeDuration,
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
  final bool transcribingAudio;
  final bool sendingMedia;
  final bool activeSendBlocked;
  final bool recording;
  final ValueListenable<double> recordingWaveformLevel;
  final int recordingWaveformBars;
  final double recordingWaveformDecay;
  final double recordingWaveformCompression;
  final double recordingWaveformDuration;
  final double recordingWaveformRmsSmoothing;
  final ValueListenable<String> recordingDurationLabel;
  final Duration voiceSendWipeDuration;
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
  bool _voiceWipeVisible = false;
  bool _finishVoiceWipe = false;

  @override
  void didUpdateWidget(covariant _Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldShowWipe = widget.sendingAudio || widget.transcribingAudio;
    if (shouldShowWipe && !_voiceWipeVisible) {
      setState(() {
        _voiceWipeVisible = true;
        _finishVoiceWipe = false;
      });
    } else if (!shouldShowWipe && _voiceWipeVisible && !_finishVoiceWipe) {
      setState(() => _finishVoiceWipe = true);
    }
  }

  void _completeVoiceWipe() {
    if (!mounted) return;
    setState(() {
      _voiceWipeVisible = false;
      _finishVoiceWipe = false;
    });
  }

  void _cancelActiveComposerAction() {
    if (_voiceWipeVisible) {
      setState(() {
        _voiceWipeVisible = false;
        _finishVoiceWipe = false;
      });
    }
    widget.onCancelRecording();
  }

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
            widget.recording
                ? SizedBox(
                    height: 64,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.colorScheme.outline),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: _LiveRecordingWaveform(
                          level: widget.recordingWaveformLevel,
                          // 360 samples at 96 samples/sec cross in 3.75 seconds.
                          speed: 3.75 / widget.recordingWaveformDuration,
                          decay: widget.recordingWaveformDecay,
                          compression: widget.recordingWaveformCompression,
                          rmsSmoothing: widget.recordingWaveformRmsSmoothing,
                          color:
                              theme.textTheme.bodyLarge?.color ??
                              theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  )
                : TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    autofocus: false,
                    textCapitalization: TextCapitalization.sentences,
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
                final busy = widget.activeSendBlocked;
                final canUseMainAction = !busy;
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
                    ? _cancelActiveComposerAction
                    : widget.sendingMedia
                    ? _cancelActiveComposerAction
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
                final sendingAudioShell =
                    _voiceWipeVisible && !widget.recording;
                const recordingButtonColor = Color(0xffffb74d);
                const recordingButtonForeground = Color(0xff1c1408);
                final sentButtonColor = theme.colorScheme.primary;

                final icon = busy
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
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
                    ? 'Recording...'
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
                  backgroundColor: widget.recording
                      ? recordingButtonColor
                      : null,
                  foregroundColor: widget.recording
                      ? recordingButtonForeground
                      : null,
                );
                final mainButton = Tooltip(
                  message: tooltip,
                  child: FilledButton.icon(
                    style: sendingAudioShell
                        ? mainButtonStyle.copyWith(
                            backgroundColor: const WidgetStatePropertyAll(
                              Colors.transparent,
                            ),
                            foregroundColor: WidgetStatePropertyAll(
                              theme.colorScheme.onPrimary,
                            ),
                          )
                        : mainButtonStyle,
                    onPressed: onMainPressed,
                    icon: icon,
                    label: widget.recording
                        ? ValueListenableBuilder<String>(
                            valueListenable: widget.recordingDurationLabel,
                            builder: (context, duration, _) =>
                                Text('Recording... $duration'),
                          )
                        : Text(label),
                  ),
                );
                final actionButton = sendingAudioShell
                    ? _RecordingButton(
                        sendWipe: sendingAudioShell,
                        finishWipe: _finishVoiceWipe,
                        backgroundColor: recordingButtonColor,
                        foregroundColor: recordingButtonForeground,
                        wipeColor: sentButtonColor,
                        wipeDuration: widget.voiceSendWipeDuration,
                        onWipeComplete: _completeVoiceWipe,
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
  const _RecordingButton({
    required this.child,
    required this.sendWipe,
    required this.finishWipe,
    required this.backgroundColor,
    required this.wipeColor,
    this.foregroundColor = Colors.white,
    this.wipeDuration = const Duration(milliseconds: 1040),
    this.onWipeComplete,
  });

  final Widget child;
  final bool sendWipe;
  final bool finishWipe;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color wipeColor;
  final Duration wipeDuration;
  final VoidCallback? onWipeComplete;

  @override
  State<_RecordingButton> createState() => _RecordingButtonState();
}

class _RecordingButtonState extends State<_RecordingButton>
    with TickerProviderStateMixin {
  late final AnimationController _wipeController;
  late final Animation<double> _wipeAnimation;

  @override
  void initState() {
    super.initState();
    _wipeController = AnimationController(
      vsync: this,
      duration: widget.wipeDuration,
    );
    _wipeAnimation = CurvedAnimation(
      parent: _wipeController,
      curve: Curves.easeOutCubic,
    );
    if (widget.sendWipe) {
      _wipeController.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant _RecordingButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.wipeDuration != oldWidget.wipeDuration) {
      _wipeController.duration = widget.wipeDuration;
    }
    if (widget.sendWipe && !oldWidget.sendWipe) {
      _wipeController.forward(from: 0);
    } else if (widget.finishWipe && !oldWidget.finishWipe) {
      _wipeController.value = 1;
      widget.onWipeComplete?.call();
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
          Positioned.fill(child: ColoredBox(color: widget.backgroundColor)),
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
                    child: ColoredBox(color: widget.wipeColor),
                  ),
                );
              },
            ),
          ),
          FilledButtonTheme(
            data: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: widget.foregroundColor,
              ),
            ),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _RecordingWaveformPainter extends CustomPainter {
  const _RecordingWaveformPainter({
    required this.samples,
    required this.progress,
    required this.color,
  });

  final List<double> samples;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.62)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 1.8;
    canvas.drawPath(_recordingWaveformPath(size, samples, progress), paint);
  }

  @override
  bool shouldRepaint(covariant _RecordingWaveformPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.progress != progress ||
        oldDelegate.color != color;
  }
}

Path _recordingWaveformPath(Size size, List<double> samples, double progress) {
  final path = Path();
  final points = _recordingWaveformPoints(size, samples, progress);

  for (var i = 0; i < points.length; i++) {
    if (i == 0) {
      path.moveTo(points[i].dx, points[i].dy);
    } else {
      path.lineTo(points[i].dx, points[i].dy);
    }
  }

  return path;
}

List<Offset> _recordingWaveformPoints(
  Size size,
  List<double> samples,
  double progress,
) {
  final centerY = size.height / 2;
  final values = samples.isEmpty ? const [0.0] : samples;
  final step = values.length <= 1
      ? size.width
      : size.width / (values.length - 1);
  final scroll = progress * step;

  return List<Offset>.generate(values.length, (index) {
    final x = size.width - (values.length - 1 - index) * step - scroll;
    final y = centerY - values[index].clamp(-1.0, 1.0) * size.height * 0.36;
    return Offset(x, y);
  });
}

class _MessageTile extends StatefulWidget {
  const _MessageTile({
    required this.message,
    required this.showResend,
    required this.speaking,
    required this.workingAnimationStyle,
    required this.workingAnimationSpeed,
    required this.stopSpeakingOnTap,
    required this.onSpeak,
    required this.onStopSpeaking,
    required this.onResend,
    required this.onCancelPending,
  });

  final ConversationMessage message;
  final bool showResend;
  final bool speaking;
  final WorkingAnimationStyle workingAnimationStyle;
  final double workingAnimationSpeed;
  final bool stopSpeakingOnTap;
  final VoidCallback? onSpeak;
  final VoidCallback? onStopSpeaking;
  final VoidCallback? onResend;
  final VoidCallback? onCancelPending;

  @override
  State<_MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<_MessageTile>
    with TickerProviderStateMixin {
  bool _flash = false;
  bool _cancelHoldTriggered = false;
  Timer? _cancelHoldTimer;
  final Set<String> _downloadingAttachments = {};
  late final AnimationController _equalizerController;
  late final AnimationController _cancelHoldController;

  @override
  void initState() {
    super.initState();
    _equalizerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    );
    _cancelHoldController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _syncEqualizer();
  }

  @override
  void didUpdateWidget(covariant _MessageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speaking != widget.speaking) {
      _syncEqualizer();
    }
    if (oldWidget.message.eventId != widget.message.eventId ||
        oldWidget.onCancelPending != widget.onCancelPending) {
      _resetCancelHold();
    }
  }

  @override
  void dispose() {
    _cancelHoldTimer?.cancel();
    _cancelHoldController.dispose();
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

  void _startCancelHold() {
    if (widget.onCancelPending == null) return;
    _cancelHoldTimer?.cancel();
    _cancelHoldTriggered = false;
    _cancelHoldController.forward(from: 0);
    _cancelHoldTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _cancelHoldTriggered) return;
      _cancelHoldTimer = null;
      _cancelHoldTriggered = true;
      widget.onCancelPending?.call();
      _cancelHoldController.reset();
    });
  }

  void _stopCancelHold() {
    _cancelHoldTimer?.cancel();
    _cancelHoldTimer = null;
    if (!_cancelHoldTriggered) _cancelHoldController.reset();
  }

  void _handleCancelHoldMove(PointerMoveEvent event) {
    if (_cancelHoldTimer == null || _cancelHoldTriggered) return;
    final size = context.size;
    if (size == null) return;
    final bounds = Offset.zero & size;
    if (!bounds.contains(event.localPosition)) {
      _stopCancelHold();
    }
  }

  void _resetCancelHold() {
    _cancelHoldTimer?.cancel();
    _cancelHoldTimer = null;
    _cancelHoldTriggered = false;
    _cancelHoldController.reset();
  }

  Future<void> _downloadAndOpenAttachment(
    BridgeAudioReference attachment,
  ) async {
    final key = attachment.sha256;
    if (_downloadingAttachments.contains(key)) return;
    setState(() => _downloadingAttachments.add(key));
    try {
      final directory = await getApplicationDocumentsDirectory();
      final downloaded = await blossomDownloadAttachment(
        attachment: attachment,
        destinationDir: '${directory.path}${Platform.pathSeparator}attachments',
      );
      final result = await OpenFilex.open(
        downloaded.path,
        type: downloaded.mediaType,
      );
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded ${downloaded.name}: ${result.message}'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Attachment download failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingAttachments.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final incoming = widget.message.direction == MessageDirection.incoming;
    final transcript = widget.message.kind == 'transcript';
    final transcribing =
        widget.message.kind == 'transcribing' ||
        widget.message.kind == 'recording';
    final processing = widget.message.kind == 'processing';
    final userSide = !incoming || transcript;
    final canFlashOnTap = widget.stopSpeakingOnTap;
    final colorScheme = Theme.of(context).colorScheme;
    final outgoingBubbleColor = colorScheme.primaryContainer;
    final baseColor = userSide
        ? outgoingBubbleColor
        : colorScheme.surfaceContainerHigh;
    final flashColor = Color.lerp(baseColor, colorScheme.primary, 0.16)!;
    if (widget.message.kind == 'processing') {
      if (!widget.workingAnimationStyle.enabled) {
        return const SizedBox.shrink();
      }
      final bubble = Card(
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          width: 58,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _cancelHoldController,
                  builder: (context, _) {
                    final color = Color.lerp(
                      colorScheme.error.withValues(alpha: 0.18),
                      colorScheme.error.withValues(alpha: 0.68),
                      _cancelHoldController.value,
                    )!;
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: _cancelHoldController.value,
                        heightFactor: 1,
                        child: ColoredBox(color: color),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: DigitalThinkingIndicator(
                  width: 34,
                  height: 20,
                  color: colorScheme.primary,
                  style: widget.workingAnimationStyle,
                  speed: widget.workingAnimationSpeed,
                ),
              ),
            ],
          ),
        ),
      );
      if (widget.onCancelPending == null) return bubble;
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _startCancelHold(),
        onPointerMove: _handleCancelHoldMove,
        onPointerUp: (_) => _stopCancelHold(),
        onPointerCancel: (_) => _stopCancelHold(),
        child: bubble,
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
          if (!widget.speaking)
            SizedBox.square(
              dimension: 36,
              child: IconButton(
                tooltip: 'Read aloud',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: widget.onSpeak,
                icon: const Icon(Icons.volume_up_outlined),
              ),
            ),
          if (!widget.speaking) const SizedBox(width: 4),
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
                _messageIcon(incoming: incoming),
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
                                child: SpeakingEqualizer(
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
          if (widget.message.attachments.isNotEmpty) ...[
            for (final attachment in widget.message.attachments)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                  onPressed: _downloadingAttachments.contains(attachment.sha256)
                      ? null
                      : () => _downloadAndOpenAttachment(attachment),
                  icon: _downloadingAttachments.contains(attachment.sha256)
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                  label: Text(
                    _downloadingAttachments.contains(attachment.sha256)
                        ? 'Downloading ${attachment.name ?? 'attachment'}...'
                        : 'Download ${attachment.name ?? 'attachment'}',
                  ),
                ),
              ),
          ],
          if (transcribing)
            Align(
              alignment: Alignment.centerLeft,
              child: widget.workingAnimationStyle.enabled
                  ? DigitalThinkingIndicator(
                      width: 42,
                      height: 18,
                      color: colorScheme.onPrimaryContainer,
                      style: widget.workingAnimationStyle,
                      speed: widget.workingAnimationSpeed,
                    )
                  : const SizedBox(height: 18),
            )
          else if (processing)
            Row(
              children: [
                if (widget.workingAnimationStyle.enabled) ...[
                  DigitalThinkingIndicator(
                    width: 42,
                    height: 18,
                    color: userSide
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.primary,
                    style: widget.workingAnimationStyle,
                    speed: widget.workingAnimationSpeed,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: MarkdownBody(
                    data: widget.message.text,
                    imageBuilder: (uri, title, alt) =>
                        _buildMarkdownImage(context, uri, title, alt),
                    selectable: !widget.stopSpeakingOnTap,
                    softLineBreak: true,
                    onTapLink: incoming ? _openLink : null,
                  ),
                ),
              ],
            )
          else
            MarkdownBody(
              data: widget.message.text,
              imageBuilder: (uri, title, alt) =>
                  _buildMarkdownImage(context, uri, title, alt),
              selectable: !widget.stopSpeakingOnTap,
              softLineBreak: true,
              onTapLink: incoming ? _openLink : null,
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
        kind == 'processing' ||
        kind == 'cancelled') {
      return '';
    }
    return kind;
  }

  String _resendTooltip() {
    if (widget.message.kind == 'audio') return 'Resend voice note';
    if (widget.message.kind == 'transcript') return 'Send transcript as query';
    return 'Resend query';
  }

  Widget _buildMarkdownImage(
    BuildContext context,
    Uri uri,
    String? title,
    String? alt,
  ) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return _markdownImageFallback(context, title, alt);
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          uri.toString(),
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _markdownImagePlaceholder(context);
          },
          errorBuilder: (context, error, stackTrace) {
            return _markdownImageFallback(context, title, alt);
          },
        ),
      ),
    );
  }

  Widget _markdownImagePlaceholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colorScheme.primary,
        ),
      ),
    );
  }

  Widget _markdownImageFallback(
    BuildContext context,
    String? title,
    String? alt,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = title?.trim().isNotEmpty == true
        ? title!.trim()
        : alt?.trim().isNotEmpty == true
        ? alt!.trim()
        : 'Image unavailable';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyMessage(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.message.text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied')));
  }

  Future<void> _openLink(String text, String? href, String title) async {
    final value = href?.trim();
    if (value == null || value.isEmpty) return;

    final uri = Uri.tryParse(value);
    if (uri == null || !_allowedLinkSchemes.contains(uri.scheme)) {
      _showLinkError('Cannot open this link');
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _showLinkError('Could not open link');
  }

  void _showLinkError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  IconData _messageIcon({required bool incoming}) {
    return incoming ? Icons.call_received : Icons.call_made;
  }

  String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
