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
    required this.onOpenCodeSessions,
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
  final VoidCallback onOpenCodeSessions;
  final ValueChanged<RepoTarget> onCatchUpTarget;
  final ValueChanged<RepoTarget> onRestartTarget;
  final ValueChanged<RepoTarget> onRenameTarget;
  final ValueChanged<RepoTarget> onTogglePinTarget;
  final VoidCallback onOpenWorkers;
  final VoidCallback onOpenSettings;
  final ValueChanged<String> onDeleteTarget;

  @override
  Widget build(BuildContext context) {
    RepoTarget? selectedTarget;
    for (final target in targets) {
      if (target.id == selectedTargetId) {
        selectedTarget = target;
        break;
      }
    }
    final canOpenCodeSessions =
        canSelectTargets && selectedTarget?.workdir?.trim().isNotEmpty == true;
    final selectedOpenCodeSession = selectedTarget?.opencodeSessionTitle
        ?.trim();
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
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: const Text('OpenCode sessions'),
              subtitle:
                  selectedOpenCodeSession != null &&
                      selectedOpenCodeSession.isNotEmpty
                  ? Text(
                      selectedOpenCodeSession,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
              onTap: canOpenCodeSessions
                  ? () {
                      Navigator.of(context).pop();
                      onOpenCodeSessions();
                    }
                  : null,
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
                                                        ? FontWeight.w700
                                                        : FontWeight.w600,
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

enum _WorkspaceSection { channel, direct, people, sessions }

class _TeamWorkspace extends StatefulWidget {
  const _TeamWorkspace({
    required this.sessions,
    required this.onOpenSessions,
    required this.onOpenSettings,
    required this.onOpenAgents,
    required this.inviteCode,
    required this.memberStatus,
    required this.workspace,
    required this.ownPubkey,
    required this.displayName,
    required this.memberAliases,
    required this.memberNames,
    required this.onDisplayNameChanged,
    required this.onMemberAliasChanged,
    required this.onRequest,
    required this.onTyping,
    required this.onAttach,
    required this.onOpenAttachment,
    required this.onCreateInvite,
    required this.callPhase,
    required this.callPeerPubkey,
    required this.incomingCallReady,
    required this.onStartCall,
    required this.onAcceptCall,
    required this.onRejectCall,
    required this.onHangupCall,
  });

  final List<RepoTarget> sessions;
  final VoidCallback onOpenSessions;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAgents;
  final String? inviteCode;
  final String memberStatus;
  final WorkspaceState workspace;
  final String ownPubkey;
  final String displayName;
  final Map<String, String> memberAliases;
  final Map<String, String> memberNames;
  final ValueChanged<String> onDisplayNameChanged;
  final void Function(String pubkey, String alias) onMemberAliasChanged;
  final Future<void> Function(Map<String, Object?> request) onRequest;
  final Future<void> Function(Map<String, Object?> request) onTyping;
  final Future<bool> Function(Map<String, Object?> request) onAttach;
  final Future<void> Function(BridgeAudioReference attachment) onOpenAttachment;
  final Future<void> Function() onCreateInvite;
  final _CallPhase callPhase;
  final String? callPeerPubkey;
  final bool incomingCallReady;
  final ValueChanged<String> onStartCall;
  final VoidCallback onAcceptCall;
  final VoidCallback onRejectCall;
  final VoidCallback onHangupCall;

  @override
  State<_TeamWorkspace> createState() => _TeamWorkspaceState();
}

class _TeamWorkspaceState extends State<_TeamWorkspace> {
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  Timer? _typingRefreshTimer;
  Timer? _typingExpiryTimer;
  _WorkspaceSection _section = _WorkspaceSection.channel;
  String _active = 'workspace';
  WorkspaceMessage? _thread;
  bool _alsoSendToMain = false;

  @override
  void initState() {
    super.initState();
    _composer.addListener(_onComposerChanged);
    _composerFocus.addListener(_onComposerChanged);
    unawaited(widget.onRequest({'action': 'list'}));
  }

  @override
  void dispose() {
    _composer.removeListener(_onComposerChanged);
    _composer.dispose();
    _composerFocus.removeListener(_onComposerChanged);
    _composerFocus.dispose();
    _typingRefreshTimer?.cancel();
    _typingExpiryTimer?.cancel();
    super.dispose();
  }

  void _onComposerChanged() {
    setState(() {});
    _syncTypingLease();
  }

  bool get _canSendTyping =>
      (_section == _WorkspaceSection.channel ||
          _section == _WorkspaceSection.direct) &&
      _composerFocus.hasFocus &&
      _composer.text.trim().isNotEmpty;

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
    unawaited(
      widget.onTyping({
        'action': 'typing',
        if (_section == _WorkspaceSection.channel) 'channel_id': _active,
        if (_section == _WorkspaceSection.direct) 'recipient_pubkey': _active,
        'expires_in_seconds': 4,
      }),
    );
  }

  List<WorkspaceMention> get _mentionOptions {
    final options = <WorkspaceMention>[
      for (final member in widget.workspace.members)
        WorkspaceMention(
          kind: 'member',
          id: member,
          label: _memberLabel(member),
        ),
      for (final agent in _activeAgents)
        WorkspaceMention(kind: 'agent', id: agent.id, label: agent.name),
    ];
    final query = _mentionQuery;
    if (query == null) return const [];
    final normalized = query.toLowerCase();
    return options
        .where((option) => option.label.toLowerCase().contains(normalized))
        .toList(growable: false);
  }

  String? get _mentionQuery {
    final selection = _composer.selection;
    final cursor = selection.isValid ? selection.start : _composer.text.length;
    final prefix = _composer.text.substring(
      0,
      cursor.clamp(0, _composer.text.length),
    );
    final start = prefix.lastIndexOf('@');
    if (start < 0 || prefix.substring(start).contains(RegExp(r'\s'))) {
      return null;
    }
    return prefix.substring(start + 1);
  }

  void _insertMention(WorkspaceMention mention) {
    final selection = _composer.selection;
    final cursor = selection.isValid ? selection.start : _composer.text.length;
    final text = _composer.text;
    final start = text
        .substring(0, cursor.clamp(0, text.length))
        .lastIndexOf('@');
    if (start < 0) return;
    final replacement = '${workspaceMentionSyntax(mention)} ';
    _composer.value = TextEditingValue(
      text: text.replaceRange(start, cursor, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
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
        return 'People & agents';
      case _WorkspaceSection.sessions:
        return 'Sessions';
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

  void _send() {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    final request = <String, Object?>{
      'action': _section == _WorkspaceSection.channel
          ? 'send_channel_message'
          : 'send_direct_message',
      if (_section == _WorkspaceSection.channel) 'channel_id': _active,
      if (_section == _WorkspaceSection.direct) 'recipient_pubkey': _active,
      'body': text,
      'mentions': workspaceMentionsIn(
        text,
      ).map((mention) => mention.toJson()).toList(),
      if (_thread != null) 'parent_id': _thread!.id,
      if (_thread != null) 'also_send_to_main': _alsoSendToMain,
    };
    _composer.clear();
    unawaited(widget.onRequest(request));
  }

  Future<void> _attach() async {
    final sent = await widget.onAttach({
      'action': _section == _WorkspaceSection.channel
          ? 'send_channel_message'
          : 'send_direct_message',
      if (_section == _WorkspaceSection.channel) 'channel_id': _active,
      if (_section == _WorkspaceSection.direct) 'recipient_pubkey': _active,
      'body': _composer.text.trim(),
      'mentions': workspaceMentionsIn(
        _composer.text,
      ).map((mention) => mention.toJson()).toList(),
      if (_thread != null) 'parent_id': _thread!.id,
      if (_thread != null) 'also_send_to_main': _alsoSendToMain,
    });
    if (sent && mounted) _composer.clear();
  }

  void _select(_WorkspaceSection section, String id) {
    setState(() {
      _section = section;
      _active = id;
      _thread = null;
      _alsoSendToMain = false;
    });
    _syncTypingLease();
    if (section == _WorkspaceSection.channel) {
      unawaited(
        widget.onRequest({'action': 'list_channel_messages', 'channel_id': id}),
      );
    } else if (section == _WorkspaceSection.direct) {
      unawaited(
        widget.onRequest({
          'action': 'list_direct_messages',
          'recipient_pubkey': id,
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final typing = _activeTyping;
    _scheduleTypingExpiry(typing);
    final wide = MediaQuery.sizeOf(context).width >= 1080;
    final medium = MediaQuery.sizeOf(context).width >= 720;
    final sidebar = _WorkspaceSidebar(
      selected: _section == _WorkspaceSection.channel ? _active : null,
      direct: _section == _WorkspaceSection.direct ? _active : null,
      sessions: widget.sessions,
      channels: widget.workspace.channels,
      members: widget.workspace.members,
      ownPubkey: widget.ownPubkey,
      displayName: widget.displayName,
      memberAliases: widget.memberAliases,
      memberNames: widget.memberNames,
      onSelect: _select,
      onSessions: widget.onOpenSessions,
      onSettings: widget.onOpenSettings,
      onOpenAgents: widget.onOpenAgents,
      onCreateChannel: () => _createChannel(context),
    );
    final conversation = _WorkspaceConversation(
      title: _title,
      section: _section,
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
      composer: _composer,
      composerFocus: _composerFocus,
      onSend: _send,
      onAttach: _attach,
      onOpenAttachment: widget.onOpenAttachment,
      onOpenThread: (message) => setState(() {
        _thread = message;
        _alsoSendToMain = false;
      }),
      onCloseThread: () => setState(() {
        _thread = null;
        _alsoSendToMain = false;
      }),
      onToggleReaction: (message, emoji) => widget.onRequest({
        'action': 'toggle_reaction',
        'parent_id': message.id,
        'reaction': emoji,
      }),
      thread: _thread,
      alsoSendToMain: _alsoSendToMain,
      onAlsoSendToMainChanged: (value) =>
          setState(() => _alsoSendToMain = value),
      onOpenSessions: widget.onOpenSessions,
      onOpenSettings: widget.onOpenSettings,
      inviteCode: widget.inviteCode,
      memberStatus: widget.memberStatus,
      onCreateInvite: widget.onCreateInvite,
      members: widget.workspace.members,
      ownPubkey: widget.ownPubkey,
      displayName: widget.displayName,
      memberAliases: widget.memberAliases,
      memberNames: widget.memberNames,
      onOpenDirect: (pubkey) => _select(_WorkspaceSection.direct, pubkey),
      onDisplayNameChanged: widget.onDisplayNameChanged,
      onMemberAliasChanged: widget.onMemberAliasChanged,
      agents: _activeAgents,
      onManageAgents:
          _section == _WorkspaceSection.channel ||
              _section == _WorkspaceSection.direct
          ? () => _manageAgents(context)
          : null,
      mentionOptions: _mentionOptions,
      onMentionSelected: _insertMention,
      typingLabels: typing
          .map(
            (status) => status.agentName ?? _memberLabel(status.senderPubkey),
          )
          .toList(),
      callPhase: widget.callPhase,
      callPeerPubkey: widget.callPeerPubkey,
      incomingCallReady: widget.incomingCallReady,
      onStartCall: widget.onStartCall,
      onAcceptCall: widget.onAcceptCall,
      onRejectCall: widget.onRejectCall,
      onHangupCall: widget.onHangupCall,
    );
    final contextPane = _WorkspaceContext(
      message: _thread,
      replies: _threadReplies,
      title: _title,
      onClose: () => setState(() {
        _thread = null;
        _alsoSendToMain = false;
      }),
    );

    return Scaffold(
      backgroundColor: Theme.of(
        context,
      ).extension<_WorkspacePalette>()!.background,
      appBar: wide
          ? null
          : AppBar(
              title: const Text('Code Call'),
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
            if (wide) SizedBox(width: 280, child: sidebar),
            if (wide) const VerticalDivider(width: 1),
            Expanded(child: conversation),
            if (medium) ...[
              const VerticalDivider(width: 1),
              SizedBox(width: wide ? 340 : 300, child: contextPane),
            ],
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _section.index.clamp(0, 2),
              onDestinationSelected: (index) {
                if (index == 0) {
                  _select(_WorkspaceSection.channel, 'workspace');
                }
                if (index == 1) _select(_WorkspaceSection.direct, 'messages');
                if (index == 2) _select(_WorkspaceSection.people, 'people');
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.forum_outlined),
                  selectedIcon: Icon(Icons.forum),
                  label: 'Channels',
                ),
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  selectedIcon: Icon(Icons.chat_bubble),
                  label: 'Messages',
                ),
                NavigationDestination(
                  icon: Icon(Icons.groups_outlined),
                  selectedIcon: Icon(Icons.groups),
                  label: 'People',
                ),
              ],
            ),
    );
  }

  List<WorkspaceTyping> get _activeTyping => widget.workspace.activeTyping(
    channelId: _section == _WorkspaceSection.channel ? _active : null,
    ownPubkey: widget.ownPubkey,
    peerPubkey: _section == _WorkspaceSection.direct ? _active : null,
    nowSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );

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
                onChanged: (_) {
                  final action = attached.contains(agent.id)
                      ? 'remove_conversation_agent'
                      : 'add_conversation_agent';
                  unawaited(
                    widget.onRequest({
                      'action': action,
                      'agent_id': agent.id,
                      if (_section == _WorkspaceSection.channel)
                        'channel_id': _active,
                      if (_section == _WorkspaceSection.direct)
                        'recipient_pubkey': _active,
                    }),
                  );
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceSidebar extends StatelessWidget {
  const _WorkspaceSidebar({
    required this.selected,
    required this.direct,
    required this.sessions,
    required this.channels,
    required this.members,
    required this.ownPubkey,
    required this.displayName,
    required this.memberAliases,
    required this.memberNames,
    required this.onSelect,
    required this.onSessions,
    required this.onSettings,
    required this.onOpenAgents,
    required this.onCreateChannel,
  });
  final String? selected;
  final String? direct;
  final List<RepoTarget> sessions;
  final List<WorkspaceChannel> channels;
  final List<String> members;
  final String ownPubkey;
  final String displayName;
  final Map<String, String> memberAliases;
  final Map<String, String> memberNames;
  final void Function(_WorkspaceSection, String) onSelect;
  final VoidCallback onSessions;
  final VoidCallback onSettings;
  final VoidCallback onOpenAgents;
  final VoidCallback onCreateChannel;

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
      String? badge,
    }) => ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: palette.selected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(icon, size: 19),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: badge == null
          ? null
          : Text(badge, style: Theme.of(context).textTheme.labelSmall),
      onTap: onTap,
    );
    return ColoredBox(
      color: palette.sidebar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: palette.brand,
                child: Icon(Icons.bolt, color: palette.brandForeground),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Code Call',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'TEAM WORKSPACE',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.1,
                        color: palette.label,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onSettings,
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Conversations',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: palette.label),
          ),
          const SizedBox(height: 6),
          if (channels.isEmpty)
            const ListTile(dense: true, title: Text('No channels yet')),
          for (final channel in channels)
            item(
              Icons.tag,
              channel.name,
              selected: selected == channel.id,
              onTap: () => onSelect(_WorkspaceSection.channel, channel.id),
            ),
          item(
            Icons.add_circle_outline,
            'Create channel',
            onTap: onCreateChannel,
          ),
          const SizedBox(height: 18),
          Text(
            'Direct messages',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: palette.label),
          ),
          const SizedBox(height: 6),
          if (members.where((member) => member != ownPubkey).isEmpty)
            const ListTile(dense: true, title: Text('No direct messages yet')),
          for (final member in members.where((member) => member != ownPubkey))
            item(
              Icons.chat_bubble_outline,
              memberLabel(member),
              selected: direct == member,
              onTap: () => onSelect(_WorkspaceSection.direct, member),
            ),
          item(
            Icons.people_outline,
            'People & agents',
            onTap: () => onSelect(_WorkspaceSection.people, 'people'),
          ),
          item(Icons.smart_toy_outlined, 'Agents', onTap: onOpenAgents),
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
            badge: sessions.isEmpty ? null : '${sessions.length}',
            onTap: onSessions,
          ),
          for (final session in sessions.take(3))
            item(
              Icons.terminal_outlined,
              session.displayName,
              onTap: onSessions,
            ),
        ],
      ),
    );
  }
}

class _WorkspaceConversation extends StatefulWidget {
  const _WorkspaceConversation({
    required this.title,
    required this.section,
    required this.directPeer,
    required this.messages,
    required this.threadReplyCounts,
    required this.composer,
    required this.composerFocus,
    required this.onSend,
    required this.onAttach,
    required this.onOpenAttachment,
    required this.onOpenThread,
    required this.onCloseThread,
    required this.onToggleReaction,
    required this.thread,
    required this.alsoSendToMain,
    required this.onAlsoSendToMainChanged,
    required this.onOpenSessions,
    required this.onOpenSettings,
    required this.inviteCode,
    required this.memberStatus,
    required this.onCreateInvite,
    required this.members,
    required this.ownPubkey,
    required this.displayName,
    required this.memberAliases,
    required this.memberNames,
    required this.onOpenDirect,
    required this.onDisplayNameChanged,
    required this.onMemberAliasChanged,
    required this.agents,
    required this.onManageAgents,
    required this.mentionOptions,
    required this.onMentionSelected,
    required this.typingLabels,
    required this.callPhase,
    required this.callPeerPubkey,
    required this.incomingCallReady,
    required this.onStartCall,
    required this.onAcceptCall,
    required this.onRejectCall,
    required this.onHangupCall,
  });
  final String title;
  final _WorkspaceSection section;
  final String? directPeer;
  final List<WorkspaceMessage> messages;
  final Map<String, int> threadReplyCounts;
  final TextEditingController composer;
  final FocusNode composerFocus;
  final VoidCallback onSend;
  final Future<void> Function() onAttach;
  final Future<void> Function(BridgeAudioReference attachment) onOpenAttachment;
  final ValueChanged<WorkspaceMessage> onOpenThread;
  final VoidCallback onCloseThread;
  final Future<void> Function(WorkspaceMessage message, String emoji)
  onToggleReaction;
  final WorkspaceMessage? thread;
  final bool alsoSendToMain;
  final ValueChanged<bool> onAlsoSendToMainChanged;
  final VoidCallback onOpenSessions;
  final VoidCallback onOpenSettings;
  final String? inviteCode;
  final String memberStatus;
  final Future<void> Function() onCreateInvite;
  final List<String> members;
  final String ownPubkey;
  final String displayName;
  final Map<String, String> memberAliases;
  final Map<String, String> memberNames;
  final ValueChanged<String> onOpenDirect;
  final ValueChanged<String> onDisplayNameChanged;
  final void Function(String pubkey, String alias) onMemberAliasChanged;
  final List<WorkspaceAgent> agents;
  final VoidCallback? onManageAgents;
  final List<WorkspaceMention> mentionOptions;
  final ValueChanged<WorkspaceMention> onMentionSelected;
  final List<String> typingLabels;
  final _CallPhase callPhase;
  final String? callPeerPubkey;
  final bool incomingCallReady;
  final ValueChanged<String> onStartCall;
  final VoidCallback onAcceptCall;
  final VoidCallback onRejectCall;
  final VoidCallback onHangupCall;

  @override
  State<_WorkspaceConversation> createState() => _WorkspaceConversationState();
}

class _WorkspaceConversationState extends State<_WorkspaceConversation> {
  final _scrollController = ScrollController();
  final _latestMessageKey = GlobalKey();
  String? _lastMessageId;
  double? _lastViewportHeight;
  bool _scrollQueued = false;

  @override
  void initState() {
    super.initState();
    _lastMessageId = _latestMessageId;
    _queueScrollToLatest();
  }

  @override
  void didUpdateWidget(covariant _WorkspaceConversation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastMessageId != _latestMessageId) {
      _lastMessageId = _latestMessageId;
      _queueScrollToLatest();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String? get _latestMessageId =>
      widget.messages.isEmpty ? null : widget.messages.last.id;

  void _queueScrollToLatest() {
    if (_scrollQueued) return;
    _scrollQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollQueued = false;
      final target = _latestMessageKey.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
      // Rich text and attachment controls can increase height after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _latestMessageKey.currentContext != null) {
          Scrollable.ensureVisible(
            _latestMessageKey.currentContext!,
            alignment: 1,
            duration: Duration.zero,
          );
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
        onOpenSessions: widget.onOpenSessions,
        onOpenSettings: widget.onOpenSettings,
        inviteCode: widget.inviteCode,
        memberStatus: widget.memberStatus,
        members: widget.members,
        ownPubkey: widget.ownPubkey,
        displayName: widget.displayName,
        memberAliases: widget.memberAliases,
        memberNames: widget.memberNames,
        onOpenDirect: widget.onOpenDirect,
        onDisplayNameChanged: widget.onDisplayNameChanged,
        onMemberAliasChanged: widget.onMemberAliasChanged,
        onCreateInvite: widget.onCreateInvite,
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 20, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.section == _WorkspaceSection.channel ? '${widget.members.length} member${widget.members.length == 1 ? '' : 's'}' : 'Direct message'}${widget.agents.isEmpty ? '' : ' · ${widget.agents.map((agent) => agent.name).join(', ')}'}',
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
              if (widget.section == _WorkspaceSection.direct)
                _CallControl(
                  phase:
                      widget.callPeerPubkey == null ||
                          widget.callPeerPubkey == widget.directPeer
                      ? widget.callPhase
                      : _CallPhase.idle,
                  incomingCallReady: widget.incomingCallReady,
                  onStart: () => widget.onStartCall(widget.directPeer!),
                  onAccept: widget.onAcceptCall,
                  onReject: widget.onRejectCall,
                  onHangup: widget.onHangupCall,
                ),
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
              return widget.messages.isEmpty
                  ? const Center(child: Text('Start the conversation.'))
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                      itemCount: widget.messages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 18),
                      itemBuilder: (context, index) {
                        final m = widget.messages[index];
                        return KeyedSubtree(
                          key: index == widget.messages.length - 1
                              ? _latestMessageKey
                              : ValueKey(m.id),
                          child: _WorkspaceMessageRow(
                            message: m,
                            authorName: _memberLabel(m.senderPubkey),
                            onThread: () => widget.onOpenThread(m),
                            threadReplyCount:
                                widget.threadReplyCounts[m.id] ?? 0,
                            onReact: (emoji) =>
                                unawaited(widget.onToggleReaction(m, emoji)),
                            onOpenAttachment: widget.onOpenAttachment,
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
                    '${widget.typingLabels.join(', ')} ${widget.typingLabels.length == 1 ? 'is' : 'are'} typing...',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (widget.thread != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Close thread',
                        onPressed: widget.onCloseThread,
                        icon: const Icon(Icons.forum_outlined, size: 18),
                      ),
                      Expanded(
                        child: Text(
                          'Replying in thread',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Checkbox(
                        value: widget.alsoSendToMain,
                        onChanged: (value) =>
                            widget.onAlsoSendToMainChanged(value ?? false),
                      ),
                      const Text('Also send to main'),
                    ],
                  ),
                ),
              if (widget.mentionOptions.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 176),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final mention in widget.mentionOptions)
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
                              onTap: () => widget.onMentionSelected(mention),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter):
                      widget.onSend,
                },
                child: TextField(
                  controller: widget.composer,
                  focusNode: widget.composerFocus,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Message ${widget.title}',
                    prefixIcon: IconButton(
                      tooltip: 'Attach file',
                      onPressed: () => unawaited(widget.onAttach()),
                      icon: const Icon(Icons.attach_file),
                    ),
                    suffixIcon: IconButton(
                      onPressed: widget.onSend,
                      icon: const Icon(Icons.send),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.phase,
    required this.incomingCallReady,
    required this.onStart,
    required this.onAccept,
    required this.onReject,
    required this.onHangup,
  });

  final _CallPhase phase;
  final bool incomingCallReady;
  final VoidCallback onStart;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangup;

  @override
  Widget build(BuildContext context) => switch (phase) {
    _CallPhase.idle => IconButton(
      tooltip: 'Start call',
      onPressed: onStart,
      icon: const Icon(Icons.call_outlined),
    ),
    _CallPhase.incoming => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(onPressed: onReject, child: const Text('Reject')),
        FilledButton(
          onPressed: incomingCallReady ? onAccept : null,
          child: Text(incomingCallReady ? 'Answer' : 'Preparing...'),
        ),
      ],
    ),
    _CallPhase.outgoing || _CallPhase.connecting => TextButton.icon(
      onPressed: onHangup,
      icon: const Icon(Icons.call_end_outlined),
      label: const Text('Connecting...'),
    ),
    _CallPhase.active => TextButton.icon(
      onPressed: onHangup,
      icon: const Icon(Icons.call_end),
      label: const Text('Call active'),
    ),
  };
}

class _WorkspaceMessageRow extends StatefulWidget {
  const _WorkspaceMessageRow({
    required this.message,
    required this.authorName,
    required this.onThread,
    required this.onReact,
    required this.threadReplyCount,
    required this.onOpenAttachment,
  });
  final WorkspaceMessage message;
  final String authorName;
  final VoidCallback onThread;
  final ValueChanged<String> onReact;
  final int threadReplyCount;
  final Future<void> Function(BridgeAudioReference attachment) onOpenAttachment;
  @override
  State<_WorkspaceMessageRow> createState() => _WorkspaceMessageRowState();
}

class _WorkspaceMessageRowState extends State<_WorkspaceMessageRow> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              child: const Icon(Icons.person, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.authorName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        DateTime.fromMillisecondsSinceEpoch(
                          widget.message.createdAt * 1000,
                        ).toLocal().toString().substring(11, 16),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (widget.message.body.isNotEmpty)
                    _WorkspaceMessageBody(widget.message.body),
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
                        '${widget.threadReplyCount} ${widget.threadReplyCount == 1 ? 'reply' : 'replies'}',
                      ),
                    ),
                  for (final attachment in widget.message.attachments)
                    TextButton.icon(
                      onPressed: () =>
                          unawaited(widget.onOpenAttachment(attachment)),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: Text(attachment.name ?? 'Attachment'),
                    ),
                ],
              ),
            ),
          ],
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
                      ClipboardData(text: widget.message.body),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reply in thread',
                    icon: const Icon(Icons.reply_outlined, size: 18),
                    onPressed: widget.onThread,
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'React',
                    icon: const Icon(Icons.add_reaction_outlined, size: 18),
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
                          ClipboardData(text: widget.message.body),
                        );
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'copy', child: Text('Copy text')),
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

class _WorkspaceMessageBody extends StatelessWidget {
  const _WorkspaceMessageBody(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final matches = RegExp(
      r'@\[([^\]\r\n]+)\]\((?:member|agent):[^\)\s]+\)',
    ).allMatches(text);
    if (matches.isEmpty) return SelectionArea(child: Text(text));
    final style = DefaultTextStyle.of(context).style;
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in matches) {
      if (match.start > offset) {
        spans.add(TextSpan(text: text.substring(offset, match.start)));
      }
      spans.add(
        TextSpan(
          text: '@${match.group(1)}',
          style: style.copyWith(
            color: Theme.of(context).extension<_WorkspacePalette>()!.label,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      offset = match.end;
    }
    if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
    return SelectionArea(
      child: RichText(
        text: TextSpan(style: style, children: spans),
      ),
    );
  }
}

class _WorkspaceContext extends StatelessWidget {
  const _WorkspaceContext({
    required this.message,
    required this.replies,
    required this.title,
    required this.onClose,
  });
  final WorkspaceMessage? message;
  final List<WorkspaceMessage> replies;
  final String title;
  final VoidCallback onClose;
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
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
                ],
              ),
              const Divider(),
              const SizedBox(height: 12),
              SelectionArea(
                child: Text(
                  message!.body,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${replies.length} ${replies.length == 1 ? 'reply' : 'replies'}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              for (final reply in replies)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SelectionArea(child: Text(reply.body)),
                ),
              const Spacer(),
              const Text(
                'Reply from the composer. Enable Also send to main to show the reply in the conversation.',
              ),
            ],
          ),
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
    required this.workspace,
    required this.workspaceRevision,
    required this.onRequest,
    required this.onLoadOpenCodeModels,
    required this.onOpenConversation,
  });
  final WorkspaceState workspace;
  final ValueListenable<int> workspaceRevision;
  final Future<void> Function(Map<String, Object?> request) onRequest;
  final Future<List<_OpenCodeModelChoice>> Function() onLoadOpenCodeModels;
  final Future<void> Function(WorkspaceAgent agent) onOpenConversation;
  @override
  State<_AgentsPage> createState() => _AgentsPageState();
}

class _AgentsPageState extends State<_AgentsPage> {
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
      builder: (_) =>
          _AgentEditorDialog(onLoadOpenCodeModels: widget.onLoadOpenCodeModels),
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

  Future<void> _editOpenCodeProfile(WorkspaceAgent agent) async {
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _AgentOpenCodeProfileDialog(
        agent: agent,
        onLoadOpenCodeModels: widget.onLoadOpenCodeModels,
      ),
    );
    if (result != null) {
      await widget.onRequest({
        'action': 'update_agent_profile',
        'agent_id': agent.id,
        ...result,
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Agents')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _createCustom,
      icon: const Icon(Icons.add),
      label: const Text('Custom agent'),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        Text(
          'START WITH A ROLE',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            letterSpacing: 1.2,
            color: Theme.of(context).extension<_WorkspacePalette>()!.label,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Agents receive a dedicated OpenCode session in this workspace when created.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
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
        Text(
          'YOUR AGENTS',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            letterSpacing: 1.2,
            color: Theme.of(context).extension<_WorkspacePalette>()!.label,
          ),
        ),
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
    ),
  );

  Widget _agentCard(WorkspaceAgent agent) => Card(
    child: ListTile(
      leading: CircleAvatar(
        child: Icon(
          agent.preset == 'reviewer'
              ? Icons.fact_check
              : Icons.smart_toy_outlined,
        ),
      ),
      title: Text(agent.name),
      subtitle: Text(
        '${agent.role}\n${agent.sessionStatus == 'ready' ? 'OpenCode ready' : agent.sessionError ?? 'OpenCode provisioning failed'}\n${_profileSummary(agent)}',
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (action) => switch (action) {
          'rename' => _renameAgent(agent),
          'profile' => _editOpenCodeProfile(agent),
          'restart' => widget.onRequest({
            'action': 'restart_agent_session',
            'agent_id': agent.id,
          }),
          'delete' => _deleteAgent(agent),
          _ => null,
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'profile', child: Text('OpenCode profile')),
          PopupMenuItem(value: 'restart', child: Text('Restart session')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: () => widget.onOpenConversation(agent),
    ),
  );

  String _profileSummary(WorkspaceAgent agent) {
    final model =
        agent.openCodeProviderId == null || agent.openCodeModelId == null
        ? 'Model: worker default'
        : 'Model: ${agent.openCodeProviderName ?? agent.openCodeProviderId} / ${agent.openCodeModelName ?? agent.openCodeModelId}';
    final openCodeAgent = agent.openCodeAgent == null
        ? 'Agent: worker default'
        : 'Agent: ${agent.openCodeAgent}';
    final workdir = agent.workdir == null
        ? 'Folder: worker default'
        : 'Folder: ${agent.workdir}';
    return '$model · $openCodeAgent\n$workdir';
  }
}

class _AgentEditorDialog extends StatefulWidget {
  const _AgentEditorDialog({required this.onLoadOpenCodeModels});
  final Future<List<_OpenCodeModelChoice>> Function() onLoadOpenCodeModels;
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
  });
  final WorkspaceAgent agent;
  final Future<List<_OpenCodeModelChoice>> Function() onLoadOpenCodeModels;

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
    required this.onLoadOpenCodeModels,
    required this.openCodeAgent,
    required this.workdir,
    required this.restartOnFailure,
    required this.onRestartOnFailureChanged,
  });

  final _OpenCodeModelChoice? initialModel;
  final Future<List<_OpenCodeModelChoice>> Function() onLoadOpenCodeModels;
  final TextEditingController openCodeAgent;
  final TextEditingController workdir;
  final bool restartOnFailure;
  final ValueChanged<bool> onRestartOnFailureChanged;

  @override
  State<_OpenCodeProfileFields> createState() => _OpenCodeProfileFieldsState();
}

class _OpenCodeProfileFieldsState extends State<_OpenCodeProfileFields> {
  late _OpenCodeModelChoice? selectedModel = widget.initialModel;

  Future<void> _chooseModel() async {
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
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('OpenCode overrides', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 4),
      const Text('Choose a configured model or use the worker default.'),
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
        trailing: const Icon(Icons.chevron_right),
        onTap: _chooseModel,
      ),
      TextField(
        controller: widget.openCodeAgent,
        maxLength: 100,
        decoration: const InputDecoration(labelText: 'OpenCode agent'),
      ),
      TextField(
        controller: widget.workdir,
        maxLength: 1000,
        decoration: const InputDecoration(
          labelText: 'Working folder',
          helperText: 'Must be inside a worker allowed folder.',
        ),
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
    required this.onOpenSessions,
    required this.onOpenSettings,
    required this.inviteCode,
    required this.memberStatus,
    required this.onCreateInvite,
    required this.members,
    required this.ownPubkey,
    required this.displayName,
    required this.memberAliases,
    required this.memberNames,
    required this.onOpenDirect,
    required this.onDisplayNameChanged,
    required this.onMemberAliasChanged,
  });
  final VoidCallback onOpenSessions;
  final VoidCallback onOpenSettings;
  final String? inviteCode;
  final String memberStatus;
  final Future<void> Function() onCreateInvite;
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
          'People & access',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text('Workspace status: ${widget.memberStatus}'),
        const SizedBox(height: 18),
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
            subtitle: Text(
              person == widget.ownPubkey
                  ? '${widget.memberStatus} (you)'
                  : 'Member',
            ),
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
        const Divider(height: 36),
        Text('Invite member', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => widget.onCreateInvite(),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Generate workspace invite code'),
        ),
        if (widget.inviteCode != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: SelectableText(
              widget.inviteCode!,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: widget.inviteCode!)),
              tooltip: 'Copy code',
            ),
          ),
        const Divider(height: 36),
        Text('Join workspace', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Status: ${widget.memberStatus}'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: widget.onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Join with invite code'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.workspaces_outline),
          title: const Text('Open focused sessions'),
          onTap: widget.onOpenSessions,
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
                            fontWeight: FontWeight.w700,
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
                      style: const TextStyle(fontFamily: 'monospace'),
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
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
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
          fontWeight: FontWeight.w700,
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
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
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
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
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
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                color: foreground,
              ),
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
        style: const TextStyle(
          color: Color(0xff6e7b77),
          fontFamily: 'monospace',
          fontSize: 11,
        ),
      ),
    );
  }
}

class _FileBrowserPage extends StatefulWidget {
  const _FileBrowserPage({
    required this.result,
    required this.workdir,
    required this.onReadFile,
  });

  final FileBrowserResult result;
  final String workdir;
  final Future<void> Function(String path) onReadFile;

  @override
  State<_FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<_FileBrowserPage> {
  final _searchController = TextEditingController();
  String _directory = '';
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FileBrowserEntry> get _visibleEntries {
    final query = _query.trim().toLowerCase();
    final entries = query.isNotEmpty
        ? widget.result.entries.where((entry) {
            return entry.path.toLowerCase().contains(query);
          }).toList()
        : widget.result.entries.where((entry) {
            final parent = entry.path.contains('/')
                ? entry.path.substring(0, entry.path.lastIndexOf('/'))
                : '';
            return parent == _directory;
          }).toList();
    entries.sort((left, right) {
      if (left.isDirectory != right.isDirectory) {
        return left.isDirectory ? -1 : 1;
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return entries;
  }

  void _openDirectory(String path) {
    setState(() {
      _directory = path;
      _query = '';
      _searchController.clear();
    });
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
            _FileBreadcrumbs(path: _directory, onOpen: _openDirectory),
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
                            ? () => _openDirectory(entry.path)
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
                                        fontFamily: 'monospace',
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
                                        fontFamily: 'monospace',
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
                          fontWeight: FontWeight.w700,
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
                              style: const TextStyle(fontFamily: 'monospace'),
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
          'Keep receiving replies while Code Call is in the background. Android shows a persistent notification.',
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
