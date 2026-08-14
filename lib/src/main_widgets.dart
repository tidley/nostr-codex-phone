part of '../main.dart';

class _WorkspaceEntryPage extends StatefulWidget {
  const _WorkspaceEntryPage({
    required this.initialName,
    required this.canScan,
    required this.onCreate,
    required this.onPasteInvite,
    required this.onScanInvite,
    required this.onOpenSettings,
  });

  final String initialName;
  final bool canScan;
  final Future<void> Function(String name) onCreate;
  final Future<void> Function() onPasteInvite;
  final Future<void> Function() onScanInvite;
  final VoidCallback onOpenSettings;

  @override
  State<_WorkspaceEntryPage> createState() => _WorkspaceEntryPageState();
}

class _WorkspaceEntryPageState extends State<_WorkspaceEntryPage> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    await widget.onCreate(_name.text);
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _pasteInvite() async {
    await _saveName();
    if (mounted) await widget.onPasteInvite();
  }

  Future<void> _scanInvite() async {
    await _saveName();
    if (mounted) await widget.onScanInvite();
  }

  Future<void> _saveName() async {
    if (_name.text.trim().isEmpty) return;
    await _create();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<_WorkspacePalette>()!;
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/branding/ribbet-mark.png',
                      width: 112,
                      height: 112,
                      color: palette.brand,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Your team starts here.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Choose a name your colleagues will see',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _name,
                            autofocus: true,
                            textInputAction: TextInputAction.done,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) =>
                                _creating ? null : _pasteInvite(),
                            decoration: const InputDecoration(
                              hintText: 'Enter your name',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          if (_name.text.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _creating ? null : _pasteInvite,
                                    icon: const Icon(
                                      Icons.content_paste_go_outlined,
                                    ),
                                    label: Text(
                                      _creating
                                          ? 'Saving name...'
                                          : 'Paste workspace invite',
                                    ),
                                  ),
                                ),
                                if (widget.canScan) ...[
                                  const SizedBox(width: 10),
                                  FilledButton.icon(
                                    onPressed: _creating ? null : _scanInvite,
                                    icon: const Icon(Icons.qr_code_scanner),
                                    label: const Text('Scan QR'),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('OR'),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onOpenSettings,
                    child: const Text('Set up service instead'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
    required this.fipsAttachedTargetIds,
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
  final Set<String> fipsAttachedTargetIds;
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
                                  final fipsAttached = fipsAttachedTargetIds
                                      .contains(target.id);
                                  final statusColor = selected
                                      ? activeColor
                                      : fipsAttached
                                      ? const Color(0xff35d6a0)
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
                                          child: Row(
                                            children: [
                                              Flexible(
                                                child: _UnreadConversationLabel(
                                                  label: target.displayName,
                                                  unread: unreadCount > 0,
                                                  style: statusColor == null
                                                      ? null
                                                      : TextStyle(
                                                          color: statusColor,
                                                          fontWeight:
                                                              selected ||
                                                                  connected
                                                              ? FontWeight.bold
                                                              : FontWeight
                                                                    .normal,
                                                        ),
                                                ),
                                              ),
                                              if (unreadCount > 0) ...[
                                                const SizedBox(width: 6),
                                                Semantics(
                                                  label:
                                                      '$unreadCount unread messages',
                                                  child: ExcludeSemantics(
                                                    child: Text(
                                                      '$unreadCount',
                                                      style: theme
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            color: theme
                                                                .colorScheme
                                                                .primary,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
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
                                    trailing: menu,
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

enum _WorkspaceSection { threads, channel, direct, people, access }

class _WorkspaceDraft {
  _WorkspaceDraft(this.value, List<WorkspaceMention> mentions)
    : mentions = List.unmodifiable(mentions);

  final TextEditingValue value;
  final List<WorkspaceMention> mentions;
}

class _WorkspaceMentionTextEditingController extends TextEditingController {
  _WorkspaceMentionTextEditingController(this.mentions);

  final List<WorkspaceMention> mentions;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final labels = mentions.map((mention) => mention.label).toList()
      ..sort((left, right) => right.length.compareTo(left.length));
    if (labels.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final matches = RegExp(
      '(?<!\\w)@(?:${labels.map(RegExp.escape).join('|')})(?![\\w-])',
    ).allMatches(text);
    if (matches.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final mentionStyle = style?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.bold,
      decoration: TextDecoration.underline,
    );
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in matches) {
      if (match.start > offset) {
        spans.add(TextSpan(text: text.substring(offset, match.start)));
      }
      spans.add(TextSpan(text: match.group(0), style: mentionStyle));
      offset = match.end;
    }
    if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
    return TextSpan(style: style, children: spans);
  }
}

class _WorkspacePanelState {
  const _WorkspacePanelState({
    required this.threadId,
    required this.widthFraction,
    required this.sidebarCollapsed,
    required this.alsoSendToMain,
    required this.filesSelected,
    required this.threadFullWindow,
    this.fileBrowser,
    this.filePreview,
  });

  final String? threadId;
  final double widthFraction;
  final bool sidebarCollapsed;
  final bool alsoSendToMain;
  final bool filesSelected;
  final bool threadFullWindow;
  final FileBrowserResult? fileBrowser;
  final FileContentResult? filePreview;
}

class _TeamWorkspace extends StatefulWidget {
  const _TeamWorkspace({
    super.key,
    required this.sessions,
    required this.spaces,
    required this.activeSpace,
    required this.sidebarSections,
    required this.onSidebarSectionChanged,
    required this.hasUnreadOtherSpaces,
    required this.otherWorkspaceAttentionVersion,
    required this.canManageAgents,
    required this.canManageMembers,
    required this.canRemoveMembers,
    required this.onSwitchSpace,
    required this.onLeaveSpace,
    required this.onOpenSessions,
    required this.onOpenSettings,
    required this.onEnterInviteCode,
    required this.diagnostics,
    required this.fipsConnected,
    required this.fipsConnectedSpaceIds,
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
    required this.inviteCode,
    required this.memberStatus,
    required this.workspace,
    required this.conversationDrafts,
    required this.threadDrafts,
    required this.focusedConversationKey,
    required this.openThreadKey,
    required this.panelStates,
    required this.ownPubkey,
    required this.localSenderIds,
    required this.fipsConnectedPeers,
    required this.displayName,
    required this.memberAliases,
    required this.conversationPreferences,
    required this.localMessagePinIds,
    required this.memberNames,
    required this.unreadCounts,
    required this.threadUnreadCounts,
    required this.onDisplayNameChanged,
    required this.onMemberAliasChanged,
    required this.onConversationPreferenceChanged,
    required this.onToggleLocalMessagePin,
    required this.onRemoveMember,
    required this.onFocusConversation,
    required this.onOpenThread,
    required this.onCloseThread,
    required this.onRequest,
    required this.onLoadFolderChoices,
    required this.onTyping,
    required this.onAttach,
    required this.onSendLargeText,
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
    required this.dateFormat,
  });

  final List<RepoTarget> sessions;
  final List<RepoTarget> spaces;
  final RepoTarget? activeSpace;
  final Map<String, bool> sidebarSections;
  final void Function(String section, bool expanded) onSidebarSectionChanged;
  final bool hasUnreadOtherSpaces;
  final int otherWorkspaceAttentionVersion;
  final bool canManageAgents;
  final bool canManageMembers;
  final bool canRemoveMembers;
  final ValueChanged<RepoTarget> onSwitchSpace;
  final ValueChanged<RepoTarget> onLeaveSpace;
  final VoidCallback onOpenSessions;
  final VoidCallback onOpenSettings;
  final VoidCallback onEnterInviteCode;
  final ValueNotifier<List<String>> diagnostics;
  final bool fipsConnected;
  final Set<String> fipsConnectedSpaceIds;
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
  final String? inviteCode;
  final String memberStatus;
  final WorkspaceState workspace;
  final Map<String, _WorkspaceDraft> conversationDrafts;
  final Map<String, _WorkspaceDraft> threadDrafts;
  final String focusedConversationKey;
  final String? openThreadKey;
  final Map<String, _WorkspacePanelState> panelStates;
  final String ownPubkey;
  final Set<String> localSenderIds;
  final Set<String> fipsConnectedPeers;
  final String displayName;
  final Map<String, String> memberAliases;
  final Map<String, WorkspaceConversationPreference> conversationPreferences;
  final Set<String> localMessagePinIds;
  final Map<String, String> memberNames;
  final Map<String, int> unreadCounts;
  final Map<String, int> threadUnreadCounts;
  final ValueChanged<String> onDisplayNameChanged;
  final void Function(String pubkey, String alias) onMemberAliasChanged;
  final void Function(
    String conversationKey, {
    bool? pinned,
    bool? archived,
    bool? muted,
  })
  onConversationPreferenceChanged;
  final ValueChanged<String> onToggleLocalMessagePin;
  final Future<void> Function(String pubkey) onRemoveMember;
  final ValueChanged<String> onFocusConversation;
  final void Function(String conversationKey, String parentId) onOpenThread;
  final VoidCallback onCloseThread;
  final Future<void> Function(Map<String, Object?> request) onRequest;
  final Future<List<RepoChoice>> Function() onLoadFolderChoices;
  final Future<void> Function(Map<String, Object?> request) onTyping;
  final Future<bool> Function(Map<String, Object?> request) onAttach;
  final Future<bool> Function(String text, Map<String, Object?> request)
  onSendLargeText;
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
  final WorkspaceDateFormat dateFormat;

  @override
  State<_TeamWorkspace> createState() => _TeamWorkspaceState();
}

class _TeamWorkspaceState extends State<_TeamWorkspace> {
  static const _sidebarMinWidth = 220.0;
  static const _sidebarMaxWidth = 360.0;
  static const _threadPaneMinWidth = 360.0;
  static const _threadPaneMaxWidth = 1100.0;
  static const _conversationMinWidth = 360.0;
  late final _WorkspaceMentionTextEditingController _composer;
  final _composerFocus = FocusNode();
  final _selectedComposerMentions = <WorkspaceMention>[];
  late final _WorkspaceMentionTextEditingController _threadComposer;
  final _threadComposerFocus = FocusNode();
  final _selectedThreadMentions = <WorkspaceMention>[];
  Map<String, _WorkspaceDraft> get _conversationDrafts =>
      widget.conversationDrafts;
  Map<String, _WorkspaceDraft> get _threadDrafts => widget.threadDrafts;
  final _threadTopicOverrides = <String, ValueNotifier<String?>>{};
  final _emptyThreadTopicOverride = ValueNotifier<String?>(null);
  Map<String, _WorkspacePanelState> get _panelStates => widget.panelStates;
  final _conversationWidgetKey = GlobalKey<_WorkspaceConversationState>();
  final _voiceRecorder = AudioRecorder();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _voiceRecording = false;
  bool _voiceTranscribing = false;
  String? _voicePath;
  DateTime? _voiceStartedAt;
  TextEditingController? _voiceComposer;
  String? _voiceError;
  Timer? _voiceTimer;
  String _voiceDurationLabel = '00:00';
  Timer? _typingRefreshTimer;
  Timer? _typingExpiryTimer;
  var _showingMentionOptions = false;
  DateTime? _lastTypingLease;
  _WorkspaceSection _section = _WorkspaceSection.channel;
  String _active = '';
  WorkspaceMessage? _thread;
  String? _threadReplyTargetId;
  bool _alsoSendToMain = false;
  bool _filesSelected = false;
  bool _filesFullWindow = false;
  bool _threadFullWindow = false;
  bool _sidebarCollapsed = false;
  double _sidebarWidth = 280;
  double _threadPaneWidthFraction = 0.5;

  String? get _conversationKey => _conversationKeyFor(_section, _active);

  String? _conversationKeyFor(_WorkspaceSection section, String id) =>
      switch (section) {
        _WorkspaceSection.threads => null,
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

  WorkspaceMessage? _threadWithIdFor(
    _WorkspaceSection section,
    String id,
    String? threadId,
  ) {
    if (threadId == null) return null;
    final messages = section == _WorkspaceSection.channel
        ? widget.workspace.messages[id] ?? const <WorkspaceMessage>[]
        : widget.workspace.messages[WorkspaceState.directKey(
                widget.ownPubkey,
                id,
              )] ??
              const <WorkspaceMessage>[];
    return messages.where((message) => message.id == threadId).firstOrNull;
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
    _composer = _WorkspaceMentionTextEditingController(
      _selectedComposerMentions,
    );
    _threadComposer = _WorkspaceMentionTextEditingController(
      _selectedThreadMentions,
    );
    _restoreFocusedConversation();
    _restorePanelState();
    _restoreOpenThread();
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
  void didUpdateWidget(covariant _TeamWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusedConversationKey != widget.focusedConversationKey) {
      _restoreFocusedConversation();
      _restorePanelState();
    }
    if (oldWidget.openThreadKey != widget.openThreadKey || _thread == null) {
      _restoreOpenThread();
    }
  }

  void _restoreFocusedConversation() {
    final focused = widget.focusedConversationKey;
    if (widget.workspace.channels.any((channel) => channel.id == focused)) {
      _section = _WorkspaceSection.channel;
      _active = focused;
      return;
    }
    for (final peer in widget.workspace.directPeers(widget.ownPubkey)) {
      if (WorkspaceState.directKey(widget.ownPubkey, peer) == focused) {
        _section = _WorkspaceSection.direct;
        _active = peer;
        return;
      }
    }
    final firstChannel = widget.workspace.channels.firstOrNull;
    if (firstChannel != null) {
      _section = _WorkspaceSection.channel;
      _active = firstChannel.id;
      return;
    }
    final firstPeer = widget.workspace
        .directPeers(widget.ownPubkey)
        .firstOrNull;
    if (firstPeer != null) {
      _section = _WorkspaceSection.direct;
      _active = firstPeer;
    }
  }

  void _restoreOpenThread() {
    final conversationKey = _conversationKey;
    final openThreadKey = widget.openThreadKey;
    if (conversationKey == null ||
        openThreadKey == null ||
        !openThreadKey.startsWith('$conversationKey:')) {
      _thread = null;
      _threadFullWindow = false;
      _restoreThreadDraft();
      return;
    }
    _thread = _threadWithId(
      openThreadKey.substring(conversationKey.length + 1),
    );
    if (_thread == null) _threadFullWindow = false;
    _restoreThreadDraft();
  }

  void _restorePanelState() {
    final panel = _conversationKey == null
        ? null
        : _panelStates[_conversationKey!];
    if (panel == null) return;
    _threadPaneWidthFraction = panel.widthFraction;
    _sidebarCollapsed = panel.sidebarCollapsed;
    _alsoSendToMain = panel.alsoSendToMain;
    _filesSelected = panel.filesSelected;
    _threadFullWindow = panel.threadFullWindow;
    widget.fileBrowser.value = panel.fileBrowser;
    widget.filePreview.value = panel.filePreview;
  }

  void _savePanelState() {
    final key = _conversationKey;
    if (key == null) return;
    _panelStates[key] = _WorkspacePanelState(
      threadId: _thread?.id,
      widthFraction: _threadPaneWidthFraction,
      sidebarCollapsed: _sidebarCollapsed,
      alsoSendToMain: _alsoSendToMain,
      filesSelected: _filesSelected,
      threadFullWindow: _threadFullWindow,
      fileBrowser: widget.fileBrowser.value,
      filePreview: widget.filePreview.value,
    );
  }

  @override
  void dispose() {
    _saveMainDraft();
    _saveThreadDraft();
    _savePanelState();
    _composer.removeListener(_onComposerChanged);
    _composer.dispose();
    _composerFocus.removeListener(_onComposerChanged);
    _composerFocus.dispose();
    _threadComposer.removeListener(_onComposerChanged);
    _threadComposer.dispose();
    _threadComposerFocus.removeListener(_onComposerChanged);
    _threadComposerFocus.dispose();
    for (final topic in _threadTopicOverrides.values) {
      topic.dispose();
    }
    _emptyThreadTopicOverride.dispose();
    widget.voiceResult.removeListener(_onVoiceResult);
    widget.fileBrowser.removeListener(_onFileBrowserChanged);
    widget.filePreview.removeListener(_onFileBrowserChanged);
    unawaited(_voiceRecorder.dispose());
    final path = _voicePath;
    if (path != null) unawaited(_deleteVoiceFile(path));
    _voiceTimer?.cancel();
    _typingRefreshTimer?.cancel();
    _typingExpiryTimer?.cancel();
    super.dispose();
  }

  ValueNotifier<String?> _threadTopicOverrideFor(String threadId) {
    final conversationKey = _conversationKey ?? '';
    final key = '$conversationKey:$threadId';
    return _threadTopicOverrides.putIfAbsent(key, () {
      final override = ValueNotifier<String?>(null);
      override.addListener(() {
        if (mounted) setState(() {});
      });
      return override;
    });
  }

  void _onComposerChanged() {
    final showingMentionOptions =
        _mentionQueryFor(_composer) != null ||
        _mentionQueryFor(_threadComposer) != null;
    if (showingMentionOptions ||
        showingMentionOptions != _showingMentionOptions) {
      setState(() => _showingMentionOptions = showingMentionOptions);
    }
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
      _voiceTimer?.cancel();
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
              _voiceStartedAt = null;
              _voiceDurationLabel = '00:00';
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
          _voiceStartedAt = null;
          _voiceDurationLabel = '00:00';
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
            _voiceStartedAt = null;
            _voiceDurationLabel = '00:00';
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
          '${directory.path}/workspace_voice_${DateTime.now().millisecondsSinceEpoch}.ogg';
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
          _voiceDurationLabel = '00:00';
        });
        _voiceTimer?.cancel();
        _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted || !_voiceRecording || _voiceStartedAt == null) return;
          final elapsed = DateTime.now().difference(_voiceStartedAt!);
          setState(() {
            _voiceDurationLabel =
                '${elapsed.inMinutes.toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
          });
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _voiceError = 'Could not start recording: $error');
      }
    }
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_voiceRecording) return;
    final path = _voicePath;
    _voiceTimer?.cancel();
    try {
      await _voiceRecorder.stop();
    } catch (_) {
      // The recorder can already be stopped if the platform interrupted it.
    }
    if (path != null) unawaited(_deleteVoiceFile(path));
    if (!mounted) return;
    setState(() {
      _voiceRecording = false;
      _voicePath = null;
      _voiceStartedAt = null;
      _voiceComposer = null;
      _voiceDurationLabel = '00:00';
      _voiceError = null;
    });
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
    await deleteLocalFile(path);
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
      const Duration(seconds: 2),
      (_) => _sendTypingLease(),
    );
  }

  void _sendTypingLease() {
    if (!_canSendTyping) return;
    final now = DateTime.now();
    if (_lastTypingLease != null &&
        now.difference(_lastTypingLease!) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastTypingLease = now;
    final threadTyping = _threadComposerFocus.hasFocus && _thread != null;
    final draft = threadTyping ? _threadComposer.text : _composer.text;
    unawaited(
      widget.onTyping({
        'action': 'typing',
        if (_section == _WorkspaceSection.channel) 'channel_id': _active,
        if (_section == _WorkspaceSection.direct) 'recipient_pubkey': _active,
        if (threadTyping) 'parent_id': _thread!.id,
        'body': draft,
        'expires_in_seconds': 6,
      }),
    );
  }

  List<WorkspaceMention> _mentionOptionsFor(TextEditingController composer) {
    final options = <WorkspaceMention>[
      for (final member in _conversationMembers)
        if (member != widget.ownPubkey)
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
    return widget.workspace.channels
        .where((channel) => channel.id == _active)
        .expand((channel) => channel.members.map((member) => member.pubkey));
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
            .where(
              (message) =>
                  message.parentId == _thread!.id &&
                  !isWorkspaceThreadTopicRequest(message) &&
                  !isWorkspaceEmptyAgentMessage(message),
            )
            .toList(growable: false);

  String? _threadTopicFor(WorkspaceMessage message) {
    final override =
        _threadTopicOverrides['$_conversationKey:${message.id}']?.value;
    if (override?.trim().isNotEmpty == true) return override!.trim();
    return workspaceThreadTopic(
      _activeMessages.where((reply) => reply.parentId == message.id),
    );
  }

  Map<String, String> _threadTopicsForActiveConversation() {
    final topics = <String, String>{};
    for (final message in _activeMessages) {
      if (message.parentId != null) continue;
      final topic = _threadTopicFor(message);
      if (topic != null) topics[message.id] = topic;
    }
    return topics;
  }

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
      case _WorkspaceSection.threads:
        return 'Threads';
      case _WorkspaceSection.channel:
        return '# ${widget.workspace.channelName(_active) ?? _active}';
      case _WorkspaceSection.direct:
        return _memberLabel(_active);
      case _WorkspaceSection.people:
        return 'Members';
      case _WorkspaceSection.access:
        return 'Access';
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

  Future<void> _send({WorkspaceMessage? thread}) async {
    final composer = thread == null ? _composer : _threadComposer;
    final selectedMentions = thread == null
        ? _selectedComposerMentions
        : _selectedThreadMentions;
    final text = composer.text.trim();
    if (text.isEmpty) return;
    final draft = composer.value;
    final mentions = List<WorkspaceMention>.of(selectedMentions);
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
        thread: thread,
      ).map((mention) => mention.toJson()).toList(),
      if (thread != null) 'parent_id': thread.id,
      if (thread != null) 'also_send_to_main': _alsoSendToMain,
    };
    final largePaste = utf8.encode(text).length >= _largePasteThresholdBytes;
    composer.clear();
    selectedMentions.clear();
    if (thread == null) {
      _conversationDrafts.remove(_conversationKey);
    } else {
      _threadDrafts.remove(_threadDraftKey);
    }
    final sent = largePaste
        ? await widget.onSendLargeText(text, request)
        : await widget.onRequest(request).then((_) => true);
    if (sent || !mounted || composer.text.isNotEmpty) return;
    composer.value = draft;
    selectedMentions.addAll(mentions);
    if (thread == null) {
      _saveMainDraft();
    } else {
      _saveThreadDraft();
    }
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
        thread: thread,
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
    List<WorkspaceMention> selected, {
    WorkspaceMessage? thread,
  }) {
    final mentions = workspaceSelectedMentionsIn(text, selected).toList();
    // An explicit mention chooses the thread recipient. Only unaddressed
    // replies continue to the agent that last responded in the thread.
    if (thread != null && mentions.isNotEmpty) {
      return mentions;
    }
    final previous = thread == null
        ? null
        : _threadReplies.reversed
                  .where(
                    (message) => isWorkspaceAgentSender(message.senderPubkey),
                  )
                  .firstOrNull ??
              thread;
    if (previous == null || !isWorkspaceAgentSender(previous.senderPubkey)) {
      return mentions;
    }
    final agentId = previous.senderPubkey.substring('agent:'.length);
    final agent = _activeAgents
        .where((agent) => agent.id == agentId)
        .firstOrNull;
    if (agent == null || mentions.any((mention) => mention.id == agentId)) {
      return mentions;
    }
    return [
      ...mentions,
      WorkspaceMention(kind: 'agent', id: agentId, label: agent.name),
    ];
  }

  void _select(_WorkspaceSection section, String id) {
    _closeDrawer();
    final previousKey = _conversationKey;
    if (previousKey != null) {
      _saveMainDraft();
      _saveThreadDraft();
      _savePanelState();
    }
    final nextKey = _conversationKeyFor(section, id);
    final nextPanelState = nextKey == null ? null : _panelStates[nextKey];
    final nextThread = _threadWithIdFor(section, id, nextPanelState?.threadId);
    setState(() {
      _section = section;
      _active = id;
      _thread = nextThread;
      _threadPaneWidthFraction = nextPanelState?.widthFraction ?? 0.5;
      _sidebarCollapsed = nextPanelState?.sidebarCollapsed ?? false;
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

  void _showThreads() {
    _closeDrawer();
    final previousKey = _conversationKey;
    if (previousKey != null) {
      _saveMainDraft();
      _saveThreadDraft();
      _savePanelState();
    }
    setState(() {
      _section = _WorkspaceSection.threads;
      _active = '';
      _thread = null;
      _filesSelected = false;
      _filesFullWindow = false;
      _threadFullWindow = false;
    });
    widget.onCloseThread();
  }

  void _openSidebarThread(String conversationKey, String threadId) {
    if (widget.workspace.channels.any(
      (channel) => channel.id == conversationKey,
    )) {
      _select(_WorkspaceSection.channel, conversationKey);
    } else {
      final peer = widget.workspace
          .directPeers(widget.ownPubkey)
          .where(
            (peer) =>
                WorkspaceState.directKey(widget.ownPubkey, peer) ==
                conversationKey,
          )
          .firstOrNull;
      if (peer == null) return;
      _select(_WorkspaceSection.direct, peer);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final thread = _threadWithId(threadId);
      if (thread == null) return;
      setState(() => _thread = thread);
      widget.onOpenThread(conversationKey, threadId);
    });
  }

  void _openAgentLastResponse(WorkspaceMessage message) {
    if (message.channelId case final channelId?) {
      _select(_WorkspaceSection.channel, channelId);
    } else {
      final agentId = message.senderPubkey.startsWith('agent:')
          ? message.senderPubkey.substring('agent:'.length)
          : null;
      final membership = agentId == null
          ? null
          : widget.workspace.conversationAgents
                .where(
                  (membership) =>
                      membership.agentId == agentId &&
                      membership.channelId == null &&
                      (membership.memberPubkey == widget.ownPubkey ||
                          membership.peerPubkey == widget.ownPubkey),
                )
                .firstOrNull;
      final peer = membership?.memberPubkey == widget.ownPubkey
          ? membership?.peerPubkey
          : membership?.memberPubkey;
      if (peer == null) return;
      _select(_WorkspaceSection.direct, peer);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _conversationWidgetKey.currentState?._openSearchResult(message);
    });
  }

  void _closeDrawer() => _scaffoldKey.currentState?.closeDrawer();

  void _closeThread() {
    if (_thread == null) return;
    setState(() {
      _saveThreadDraft();
      _thread = null;
      _alsoSendToMain = false;
      _threadFullWindow = false;
      _filesSelected = widget.fileBrowser.value != null;
    });
    widget.onCloseThread();
  }

  void _toggleSidebarCollapsed() {
    setState(() {
      _sidebarCollapsed = !_sidebarCollapsed;
      _savePanelState();
    });
  }

  void _openMessageSearch() {
    _conversationWidgetKey.currentState?._openSearch();
  }

  @override
  Widget build(BuildContext context) {
    final typing = _activeTyping;
    final threadTyping = _activeThreadTyping;
    final toastTyping = [
      ...typing,
      for (final status in threadTyping)
        if (!typing.any(
          (active) =>
              active.senderPubkey == status.senderPubkey &&
              active.parentId == status.parentId,
        ))
          status,
    ];
    final activityLabels = _conversationActivityLabels();
    _scheduleTypingExpiry(widget.workspace.typing.values.toList());
    final medium = MediaQuery.sizeOf(context).width >= 720;
    final wide = medium;
    final sidebar = _WorkspaceSidebar(
      section: _section,
      selected: _section == _WorkspaceSection.channel ? _active : null,
      direct: _section == _WorkspaceSection.direct ? _active : null,
      sessions: widget.sessions,
      spaces: widget.spaces,
      activeSpace: widget.activeSpace,
      sidebarSections: widget.sidebarSections,
      onSidebarSectionChanged: widget.onSidebarSectionChanged,
      hasUnreadOtherSpaces: widget.hasUnreadOtherSpaces,
      otherWorkspaceAttentionVersion: widget.otherWorkspaceAttentionVersion,
      canManageAgents: widget.canManageAgents,
      onSwitchSpace: widget.onSwitchSpace,
      onLeaveSpace: widget.onLeaveSpace,
      channels: widget.workspace.channels,
      workspace: widget.workspace,
      members: widget.workspace.directPeers(widget.ownPubkey),
      ownPubkey: widget.ownPubkey,
      displayName: widget.displayName,
      memberAliases: widget.memberAliases,
      conversationPreferences: widget.conversationPreferences,
      memberNames: widget.memberNames,
      unreadCounts: widget.unreadCounts,
      threadUnreadCounts: widget.threadUnreadCounts,
      activityLabels: activityLabels,
      fipsConnected: widget.fipsConnected,
      fipsConnectedSpaceIds: widget.fipsConnectedSpaceIds,
      fipsConnectedPeers: widget.fipsConnectedPeers,
      onSelect: _select,
      onOpenThread: _openSidebarThread,
      threadsSelected: _section == _WorkspaceSection.threads,
      onShowThreads: _showThreads,
      onSessions: () {
        _closeDrawer();
        widget.onOpenSessions();
      },
      onSettings: () {
        _closeDrawer();
        widget.onOpenSettings();
      },
      onToggleCollapsed: _toggleSidebarCollapsed,
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
      onTogglePinConversation: (section, id) {
        final key = _conversationKeyFor(section, id);
        if (key == null) return;
        final preference =
            widget.conversationPreferences[key] ??
            const WorkspaceConversationPreference();
        widget.onConversationPreferenceChanged(key, pinned: !preference.pinned);
      },
      onToggleMuteConversation: (section, id) {
        final key = _conversationKeyFor(section, id);
        if (key == null) return;
        final preference =
            widget.conversationPreferences[key] ??
            const WorkspaceConversationPreference();
        widget.onConversationPreferenceChanged(key, muted: !preference.muted);
      },
      activeConversationMuted:
          _conversationKey != null &&
          widget.conversationPreferences[_conversationKey]?.muted == true,
      onToggleActiveConversationMuted: () {
        final key = _conversationKey;
        if (key == null) return;
        final preference =
            widget.conversationPreferences[key] ??
            const WorkspaceConversationPreference();
        widget.onConversationPreferenceChanged(key, muted: !preference.muted);
      },
    );
    final Widget conversation = _section == _WorkspaceSection.threads
        ? _WorkspaceThreadsView(
            workspace: widget.workspace,
            ownPubkey: widget.ownPubkey,
            memberNames: widget.memberNames,
            memberAliases: widget.memberAliases,
            drafts: _threadDrafts,
            threadUnreadCounts: widget.threadUnreadCounts,
            onOpenThread: _openSidebarThread,
            dateFormat: widget.dateFormat,
          )
        : ValueListenableBuilder<int>(
            valueListenable: widget.workspaceRevision,
            builder: (context, _, _) => _WorkspaceConversation(
              key: _conversationWidgetKey,
              title: _title,
              section: _section,
              channelId: _section == _WorkspaceSection.channel ? _active : null,
              directPeer: _section == _WorkspaceSection.direct ? _active : null,
              messages: _activeMessages
                  .where(
                    (message) =>
                        !isWorkspaceEmptyAgentMessage(message) &&
                        (message.parentId == null || message.alsoSendToMain),
                  )
                  .toList(growable: false),
              searchMessages: _activeMessages
                  .where((message) => !isWorkspaceEmptyAgentMessage(message))
                  .toList(growable: false),
              threadTopics: _threadTopicsForActiveConversation(),
              threadReplyCounts: {
                for (final message in _activeMessages.where(
                  (message) =>
                      message.parentId != null &&
                      !isWorkspaceEmptyAgentMessage(message),
                ))
                  message.parentId!: _activeMessages
                      .where(
                        (reply) =>
                            reply.parentId == message.parentId &&
                            !isWorkspaceEmptyAgentMessage(reply),
                      )
                      .length,
              },
              threadUnreadCounts: {
                for (final entry in widget.threadUnreadCounts.entries)
                  if (_conversationKey != null &&
                      entry.key.startsWith('$_conversationKey:'))
                    entry.key.substring(_conversationKey!.length + 1):
                        entry.value,
              },
              threadActivityLabels: _threadActivityLabels(typing),
              composer: _composer,
              composerFocus: _composerFocus,
              onSend: _send,
              onAttach: _attach,
              voiceRecording: _voiceRecording && _voiceComposer == _composer,
              voiceTranscribing:
                  _voiceTranscribing && _voiceComposer == _composer,
              voiceError: _voiceComposer == _composer ? _voiceError : null,
              onVoicePressed: () => unawaited(_toggleVoiceRecording()),
              voiceDurationLabel: _voiceDurationLabel,
              onCancelVoiceRecording: () => unawaited(_cancelVoiceRecording()),
              onOpenAttachment: widget.onOpenAttachment,
              onOpenAgentLastResponse: _openAgentLastResponse,
              onOpenThread: (message) {
                setState(() {
                  if (_thread?.id != message.id) {
                    _saveThreadDraft();
                    _thread = message;
                    _threadPaneWidthFraction = 0.5;
                    _restoreThreadDraft();
                  }
                  _alsoSendToMain = false;
                  _threadReplyTargetId = null;
                });
                final conversationKey = _conversationKey;
                if (conversationKey != null) {
                  widget.onOpenThread(conversationKey, message.id);
                }
              },
              onCloseThread: _closeThread,
              onOpenMessageReference: (message) {
                final thread = message.parentId == null
                    ? message
                    : _activeMessages
                              .where(
                                (candidate) => candidate.id == message.parentId,
                              )
                              .firstOrNull ??
                          message;
                setState(() {
                  if (_thread?.id != thread.id) {
                    _saveThreadDraft();
                    _thread = thread;
                    _threadPaneWidthFraction = 0.5;
                    _restoreThreadDraft();
                  }
                  _alsoSendToMain = false;
                  _threadReplyTargetId = message.parentId == null
                      ? null
                      : message.id;
                });
                final conversationKey = _conversationKey;
                if (conversationKey != null) {
                  widget.onOpenThread(conversationKey, thread.id);
                }
              },
              onToggleReaction: (message, emoji) => widget.onRequest({
                'action': 'toggle_reaction',
                'parent_id': message.id,
                'reaction': emoji,
              }),
              localMessagePinIds: widget.localMessagePinIds,
              onToggleLocalMessagePin: widget.onToggleLocalMessagePin,
              thread: _thread,
              alsoSendToMain: _alsoSendToMain,
              onAlsoSendToMainChanged: (value) =>
                  setState(() => _alsoSendToMain = value),
              onOpenSettings: widget.onOpenSettings,
              onEnterInviteCode: widget.onEnterInviteCode,
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
              conversationPreference: _conversationKey == null
                  ? const WorkspaceConversationPreference()
                  : widget.conversationPreferences[_conversationKey] ??
                        const WorkspaceConversationPreference(),
              onConversationPreferenceChanged: ({pinned, archived, muted}) {
                final conversationKey = _conversationKey;
                if (conversationKey != null) {
                  widget.onConversationPreferenceChanged(
                    conversationKey,
                    pinned: pinned,
                    archived: archived,
                    muted: muted,
                  );
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
                if (!mounted) return;
                final nextChannel = widget.workspace.channels
                    .where((channel) => channel.id != _active)
                    .firstOrNull;
                if (nextChannel != null) {
                  _select(_WorkspaceSection.channel, nextChannel.id);
                } else {
                  final nextPeer = widget.workspace
                      .directPeers(widget.ownPubkey)
                      .firstOrNull;
                  if (nextPeer != null) {
                    _select(_WorkspaceSection.direct, nextPeer);
                  }
                }
              },
              inviteCode: widget.inviteCode,
              canCreateInvite:
                  widget.canManageMembers || widget.memberStatus == 'Owner',
              memberStatus: widget.memberStatus,
              onCreateInvite: widget.onCreateInvite,
              members: widget.workspace.members,
              channelHumanMemberCount: _section == _WorkspaceSection.channel
                  ? widget.workspace.channelHumanMemberCount(_active)
                  : 0,
              ownPubkey: widget.ownPubkey,
              localSenderIds: widget.localSenderIds,
              fipsConnectedPeers: widget.fipsConnectedPeers,
              displayName: widget.displayName,
              memberAliases: widget.memberAliases,
              memberNames: widget.memberNames,
              memberAdmins: widget.workspace.memberAdmins,
              canManageMembers: widget.canManageMembers,
              canRemoveMembers: widget.canRemoveMembers,
              onSetMemberAdmin: (pubkey, isAdmin) => widget.onRequest({
                'action': 'set_member_admin',
                'member_pubkey': pubkey,
                'member_is_admin': isAdmin,
              }),
              onRemoveMember: widget.onRemoveMember,
              onOpenDirect: (pubkey) =>
                  _select(_WorkspaceSection.direct, pubkey),
              onDisplayNameChanged: widget.onDisplayNameChanged,
              onMemberAliasChanged: widget.onMemberAliasChanged,
              workspace: widget.workspace,
              workspaceRevision: widget.workspaceRevision,
              onRequest: widget.onRequest,
              onLoadOpenCodeModels: widget.onLoadOpenCodeModels,
              initialFolderChoices: widget.initialFolderChoices,
              onLoadFolders: widget.onLoadFolders,
              conversationPreprompt: widget.workspace.conversationPreprompt(
                channelId: _section == _WorkspaceSection.channel
                    ? _active
                    : null,
                ownPubkey: widget.ownPubkey,
                peerPubkey: _section == _WorkspaceSection.direct
                    ? _active
                    : null,
              ),
              conversationFolderScope: widget.workspace.conversationFolderScope(
                channelId: _section == _WorkspaceSection.channel
                    ? _active
                    : null,
                ownPubkey: widget.ownPubkey,
                peerPubkey: _section == _WorkspaceSection.direct
                    ? _active
                    : null,
              ),
              agents: _activeAgents,
              agentDirectory: widget.workspace.agents,
              onManageAgents:
                  widget.canManageAgents &&
                      _section == _WorkspaceSection.channel
                  ? () => _manageAgents(context)
                  : null,
              onEditConversationPreprompt: (value) => widget.onRequest({
                'action': 'set_conversation_preprompt',
                'body': value,
                if (_section == _WorkspaceSection.channel)
                  'channel_id': _active,
                if (_section == _WorkspaceSection.direct)
                  'recipient_pubkey': _active,
              }),
              onEditConversationFolder: (folders) => widget.onRequest({
                'action': 'set_conversation_preprompt',
                'body': widget.workspace.conversationPreprompt(
                  channelId: _section == _WorkspaceSection.channel
                      ? _active
                      : null,
                  ownPubkey: widget.ownPubkey,
                  peerPubkey: _section == _WorkspaceSection.direct
                      ? _active
                      : null,
                ),
                'folder_scope': folders,
                if (_section == _WorkspaceSection.channel)
                  'channel_id': _active,
                if (_section == _WorkspaceSection.direct)
                  'recipient_pubkey': _active,
              }),
              mentionOptions: _mentionOptionsFor(_composer),
              onMentionSelected: (mention) =>
                  _insertMention(_composer, _selectedComposerMentions, mention),
              typingStatuses: toastTyping,
              typingLabels: _typingLabels(toastTyping),
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
            ),
          );
    final conversationKey = _conversationKey;
    final fileBrowser = widget.fileBrowser.value;
    final contextPane = ValueListenableBuilder<int>(
      valueListenable: widget.workspaceRevision,
      builder: (context, _, _) => _WorkspaceContext(
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
        voiceDurationLabel: _voiceDurationLabel,
        onCancelVoiceRecording: () => unawaited(_cancelVoiceRecording()),
        alsoSendToMain: _alsoSendToMain,
        onAlsoSendToMainChanged: (value) =>
            setState(() => _alsoSendToMain = value),
        onClose: _closeThread,
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
        agentDirectory: widget.workspace.agents,
        typingStatuses: threadTyping,
        typingLabels: _typingLabels(threadTyping),
        onRequestTopic: () {
          final thread = _thread;
          final agentReply = _threadReplies.reversed
              .where((message) => isWorkspaceAgentSender(message.senderPubkey))
              .firstOrNull;
          if (thread == null || agentReply == null) return;
          final agentId = agentReply.senderPubkey.substring('agent:'.length);
          final agent = _activeAgents
              .where((candidate) => candidate.id == agentId)
              .firstOrNull;
          unawaited(
            widget.onRequest({
              'action': _section == _WorkspaceSection.channel
                  ? 'send_channel_message'
                  : 'send_direct_message',
              if (_section == _WorkspaceSection.channel) 'channel_id': _active,
              if (_section == _WorkspaceSection.direct)
                'recipient_pubkey': _active,
              'parent_id': thread.id,
              'body':
                  '[[THREAD_TOPIC_REQUEST]] Reply only with [[THREAD_TOPIC: one to three words]].',
              'mentions': [
                {
                  'kind': 'agent',
                  'id': agentId,
                  'label': agent?.name ?? 'Agent',
                },
              ],
            }),
          );
        },
        topicOverride: _thread == null
            ? _emptyThreadTopicOverride
            : _threadTopicOverrideFor(_thread!.id),
        threadTopic: _thread == null ? null : _threadTopicFor(_thread!),
        filesOpen: _filesSelected && fileBrowser != null,
        onShowFiles: () => setState(() {
          _filesSelected = true;
          _threadFullWindow = false;
        }),
        compactHeader: !medium,
        fullWindow: _threadFullWindow,
        onToggleFullWindow: () => setState(() {
          _threadFullWindow = !_threadFullWindow;
          _savePanelState();
        }),
        dateFormat: widget.dateFormat,
        replyTargetId: _threadReplyTargetId,
        onReplyTargetOpened: () => setState(() => _threadReplyTargetId = null),
      ),
    );
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
            onClose: () => setState(() {
              _filesSelected = false;
              _filesFullWindow = false;
              _savePanelState();
            }),
            hasThread: _thread != null,
            onShowThread: () => setState(() {
              _filesSelected = false;
              _filesFullWindow = false;
            }),
            onClosePreview: () => widget.filePreview.value = null,
            fullWindow: _filesFullWindow,
          );
    final showSidePane =
        _thread != null || (_filesSelected && filesPane != null);
    final showFiles = _filesSelected && filesPane != null;
    final fullSidePane = _filesFullWindow || _threadFullWindow;
    final windowWidth = MediaQuery.sizeOf(context).width;
    final persistentChromeWidth = wide
        ? (_sidebarCollapsed ? 56 : _sidebarWidth) + 1
        : 0;
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
    final availableMessageWidth = windowWidth - persistentChromeWidth - 10;
    final sidePaneWidth = (availableMessageWidth * _threadPaneWidthFraction)
        .clamp(_threadPaneMinWidth, maxSidePaneWidth);
    // Keep the active conversation readable. On a narrow window the detail
    // pane replaces it instead of squeezing both panes into unusable columns.
    final showSingleSidePane =
        showSidePane && !fullSidePane && !canShowInlineSidePane;
    final canDismissNarrowThread = showSingleSidePane && _thread != null;
    final mobileThreadView =
        !medium && _thread != null && (showSingleSidePane || _threadFullWindow);
    final sidePane = _WorkspaceSidePanel(
      thread: _thread != null ? contextPane : null,
      files: filesPane,
      showFiles: showFiles,
    );

    final narrowSidePane = canDismissNarrowThread && medium
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) > 300) _closeThread();
            },
            child: sidePane,
          )
        : sidePane;

    return Focus(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _openMessageSearch,
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              _openMessageSearch,
        },
        child: PopScope<void>(
          canPop: !canDismissNarrowThread,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && canDismissNarrowThread) _closeThread();
          },
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: Theme.of(
              context,
            ).extension<_WorkspacePalette>()!.background,
            appBar: wide
                ? null
                : mobileThreadView
                ? AppBar(
                    leading: IconButton(
                      onPressed: _closeThread,
                      icon: const Icon(Icons.close),
                      tooltip: 'Close thread',
                    ),
                    title: const Text('Thread'),
                  )
                : AppBar(
                    title: Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    actions: [
                      IconButton(
                        onPressed: () => unawaited(
                          _conversationWidgetKey.currentState
                              ?._showMobileConversationActions(),
                        ),
                        icon: const Icon(Icons.more_vert),
                        tooltip: 'Conversation actions',
                      ),
                    ],
                  ),
            drawer: wide ? null : Drawer(child: SafeArea(child: sidebar)),
            body: SafeArea(
              child: Row(
                children: [
                  if (wide)
                    SizedBox(
                      width: _sidebarCollapsed ? 56 : _sidebarWidth,
                      child: _sidebarCollapsed
                          ? ColoredBox(
                              color: Theme.of(
                                context,
                              ).extension<_WorkspacePalette>()!.sidebar,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: IconButton(
                                  onPressed: _toggleSidebarCollapsed,
                                  icon: const Icon(Icons.menu),
                                  tooltip: 'Expand sidebar',
                                ),
                              ),
                            )
                          : sidebar,
                    ),
                  if (wide && !_sidebarCollapsed)
                    SidebarPaneResizeHandle(
                      onResize: (delta) => setState(() {
                        _sidebarWidth = (_sidebarWidth + delta).clamp(
                          _sidebarMinWidth,
                          _sidebarMaxWidth,
                        );
                      }),
                    ),
                  Expanded(
                    child: fullSidePane
                        ? sidePane
                        : showSingleSidePane
                        ? narrowSidePane
                        : conversation,
                  ),
                  if (canShowInlineSidePane) ...[
                    ThreadPaneResizeHandle(
                      onResize: (delta) => setState(() {
                        _threadPaneWidthFraction =
                            ((sidePaneWidth + delta) / availableMessageWidth)
                                .clamp(0.0, 1.0);
                        _savePanelState();
                      }),
                    ),
                    SizedBox(width: sidePaneWidth, child: sidePane),
                  ],
                ],
              ),
            ),
          ),
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

  String _typingLabel(WorkspaceTyping status) {
    final name = status.agentName ?? _memberLabel(status.senderPubkey);
    if (status.agentId != null) {
      final stage = status.stage?.trim();
      return stage == null || stage.isEmpty
          ? '$name is working...'
          : '$name: $stage';
    }
    return '$name is typing...';
  }

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
    String? validationError;
    String? validate(String value) {
      final name = value.trim();
      if (name.isEmpty) return 'Enter a conversation name';
      if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(name)) {
        return 'Use letters, numbers, and hyphens only';
      }
      return null;
    }

    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New conversation'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (value) =>
                setDialogState(() => validationError = validate(value)),
            onSubmitted: (value) {
              final error = validate(value);
              if (error != null) {
                setDialogState(() => validationError = error);
                return;
              }
              Navigator.pop(context, value);
            },
            decoration: InputDecoration(
              hintText: 'engineering',
              errorText: validationError,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final error = validate(controller.text);
                if (error != null) {
                  setDialogState(() => validationError = error);
                  return;
                }
                Navigator.pop(context, controller.text);
              },
              child: const Text('Create'),
            ),
          ],
        ),
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
    final isChannel = _section == _WorkspaceSection.channel;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _ConversationAgentsPage(
          title: _title,
          workspace: widget.workspace,
          workspaceRevision: widget.workspaceRevision,
          channelId: isChannel ? _active : null,
          ownPubkey: widget.ownPubkey,
          peerPubkey: isChannel ? null : _active,
          onRequest: widget.onRequest,
          onLoadFolders: widget.onLoadFolders,
          onLoadOpenCodeModels: widget.onLoadOpenCodeModels,
          initialFolderChoices: widget.initialFolderChoices,
        ),
      ),
    );
  }
}

class _ConversationAgentsPage extends StatelessWidget {
  const _ConversationAgentsPage({
    required this.title,
    required this.workspace,
    required this.workspaceRevision,
    required this.channelId,
    required this.ownPubkey,
    required this.peerPubkey,
    required this.onRequest,
    required this.onLoadFolders,
    required this.onLoadOpenCodeModels,
    required this.initialFolderChoices,
  });

  final String title;
  final WorkspaceState workspace;
  final ValueListenable<int> workspaceRevision;
  final String? channelId;
  final String ownPubkey;
  final String? peerPubkey;
  final Future<void> Function(Map<String, Object?> request) onRequest;
  final Future<List<RepoChoice>> Function(String? path) onLoadFolders;
  final Future<List<_OpenCodeModelChoice>> Function() onLoadOpenCodeModels;
  final List<RepoChoice> initialFolderChoices;

  bool _matches(WorkspaceConversationAgent membership) {
    if (membership.channelId != null) return membership.channelId == channelId;
    final participants = [ownPubkey, peerPubkey ?? '']..sort();
    return channelId == null &&
        membership.memberPubkey == participants[0] &&
        membership.peerPubkey == participants[1];
  }

  Map<String, Object?> _request(String action, String agentId) => {
    'action': action,
    'agent_id': agentId,
    if (channelId != null) 'channel_id': channelId,
    if (channelId == null) 'recipient_pubkey': peerPubkey,
  };

  Future<void> _editFolder(
    BuildContext context,
    WorkspaceConversationAgent membership,
  ) async {
    final folders = await showDialog<List<String>>(
      context: context,
      builder: (_) => _FolderScopeDialog(
        initialSelected: membership.folderScope,
        initialChoices: initialFolderChoices,
        onLoadFolders: onLoadFolders,
      ),
    );
    if (folders != null) {
      await onRequest({
        ..._request('add_conversation_agent', membership.agentId),
        'folder_scope': folders,
      });
    }
  }

  Future<void> _createCustom(BuildContext context) async {
    final profile = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _AgentEditorDialog(
        onLoadOpenCodeModels: onLoadOpenCodeModels,
        initialFolderChoices: initialFolderChoices,
        onLoadFolders: onLoadFolders,
        conversationScoped: true,
      ),
    );
    if (profile == null || !context.mounted) return;
    await onRequest(
      {...profile, ..._request('create_conversation_agent', '')}
        ..remove('agent_id'),
    );
  }

  Future<void> _create(BuildContext context) => _createCustom(context);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Conversation agents'),
      actions: [
        IconButton(
          tooltip: 'Create conversation agent',
          onPressed: () => _create(context),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    ),
    body: ValueListenableBuilder<int>(
      valueListenable: workspaceRevision,
      builder: (context, _, _) {
        final memberships = workspace.conversationAgents
            .where(_matches)
            .toList();
        final agents = <WorkspaceAgent>[
          for (final membership in memberships)
            for (final agent in workspace.agents)
              if (agent.id == membership.agentId) agent,
        ];
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Agents created here are assigned only to this conversation.',
            ),
            const SizedBox(height: 24),
            if (agents.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(
                  child: Text('Create an agent to work in this conversation.'),
                ),
              ),
            for (final agent in agents)
              _conversationAgentCard(
                context,
                agent,
                memberships.firstWhere(
                  (membership) => membership.agentId == agent.id,
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _conversationAgentCard(
    BuildContext context,
    WorkspaceAgent agent,
    WorkspaceConversationAgent membership,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(child: Icon(Icons.smart_toy_outlined)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  agent.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Remove agent',
                onPressed: () =>
                    onRequest(_request('remove_conversation_agent', agent.id)),
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(agent.role),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Working folder'),
            subtitle: Text(
              membership.folderScope.isEmpty
                  ? 'Not configured'
                  : membership.folderScope.join(', '),
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editFolder(context, membership),
          ),
        ],
      ),
    ),
  );
}

class _FolderScopeDialog extends StatefulWidget {
  const _FolderScopeDialog({
    required this.initialChoices,
    required this.onLoadFolders,
    this.initialSelected = const [],
  });

  final List<RepoChoice> initialChoices;
  final Future<List<RepoChoice>> Function(String? path) onLoadFolders;
  final List<String> initialSelected;

  @override
  State<_FolderScopeDialog> createState() => _FolderScopeDialogState();
}

class _FolderScopeDialogState extends State<_FolderScopeDialog> {
  late final _selected = widget.initialSelected.take(1).toSet();

  Future<void> _chooseFolder() async {
    final selection = await Navigator.of(context).push<_WorkingFolderSelection>(
      MaterialPageRoute(
        builder: (_) => _WorkingFolderPickerPage(
          initialChoices: widget.initialChoices,
          selectedPath: _selected.firstOrNull ?? '',
          onLoadFolders: widget.onLoadFolders,
        ),
      ),
    );
    if (selection?.path == null || !mounted) return;
    setState(() {
      _selected
        ..clear()
        ..add(selection!.path!);
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Working folder'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select the folder where this conversation agent can work.',
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: Text(_selected.firstOrNull ?? 'Choose a folder'),
            subtitle: const Text('Open folders to choose a subfolder.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _chooseFolder,
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
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.pop(context, _selected.toList()),
        child: const Text('Save folder'),
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
        child: SizedBox(
          width: 12,
          height: double.infinity,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 1,
              height: double.infinity,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
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

class _WorkspaceThreadsView extends StatefulWidget {
  const _WorkspaceThreadsView({
    required this.workspace,
    required this.ownPubkey,
    required this.memberNames,
    required this.memberAliases,
    required this.drafts,
    required this.threadUnreadCounts,
    required this.onOpenThread,
    required this.dateFormat,
  });

  final WorkspaceState workspace;
  final String ownPubkey;
  final Map<String, String> memberNames;
  final Map<String, String> memberAliases;
  final Map<String, _WorkspaceDraft> drafts;
  final Map<String, int> threadUnreadCounts;
  final void Function(String conversationKey, String threadId) onOpenThread;
  final WorkspaceDateFormat dateFormat;

  @override
  State<_WorkspaceThreadsView> createState() => _WorkspaceThreadsViewState();
}

class _WorkspaceThreadsViewState extends State<_WorkspaceThreadsView> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  String _memberLabel(String pubkey) => pubkey == widget.ownPubkey
      ? widget.memberNames[pubkey] ?? 'You'
      : widget.memberAliases[pubkey] ??
            widget.memberNames[pubkey] ??
            compactIdentifier(pubkey);

  String _timeLabel(int timestamp) {
    final now = DateTime.now();
    final local = DateTime.fromMillisecondsSinceEpoch(
      timestamp * 1000,
    ).toLocal();
    if (now.difference(local).inDays == 0) {
      final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
      final minute = local.minute.toString().padLeft(2, '0');
      return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
    }
    if (now.difference(local).inDays == 1) return 'Yesterday';
    return widget.dateFormat == WorkspaceDateFormat.uk
        ? '${local.day}/${local.month}/${local.year}'
        : '${local.month}/${local.day}/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final threads = <String, WorkspaceMessage>{};
    for (final messages in widget.workspace.messages.values) {
      final byId = {for (final message in messages) message.id: message};
      for (final message in messages) {
        final isMentioned = message.mentions.any(
          (mention) =>
              mention.kind == 'member' && mention.id == widget.ownPubkey,
        );
        if (message.parentId == null && !isMentioned) continue;
        final source = message.parentId == null
            ? message
            : byId[message.parentId];
        if (source == null || isWorkspaceEmptyAgentMessage(source)) continue;
        final key =
            '${widget.workspace.conversationKeyForMessage(source)}:${source.id}';
        final current = threads[key];
        if (current == null || source.createdAt > current.createdAt) {
          threads[key] = source;
        }
      }
    }
    final ordered =
        (threads.values.toList()..sort((left, right) {
              final leftKey =
                  '${widget.workspace.conversationKeyForMessage(left)}:${left.id}';
              final rightKey =
                  '${widget.workspace.conversationKeyForMessage(right)}:${right.id}';
              final leftDraft =
                  widget.drafts[leftKey]?.value.text.trim().isNotEmpty == true;
              final rightDraft =
                  widget.drafts[rightKey]?.value.text.trim().isNotEmpty == true;
              if (leftDraft != rightDraft) return leftDraft ? -1 : 1;
              return right.createdAt.compareTo(left.createdAt);
            }))
            .where(_matchesSearch)
            .toList(growable: false);
    return ColoredBox(
      color: Theme.of(context).extension<_WorkspacePalette>()!.content,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 36),
        children: [
          Text(
            'Threads',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Search threads',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 20),
          if (ordered.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(
                child: Text(
                  _searchQuery.trim().isEmpty
                      ? 'No threads yet.'
                      : 'No matching threads.',
                ),
              ),
            ),
          for (final source in ordered) ...[
            Builder(
              builder: (context) {
                final conversationKey = widget.workspace
                    .conversationKeyForMessage(source);
                final replies =
                    (widget.workspace.messages[conversationKey] ??
                            const <WorkspaceMessage>[])
                        .where(
                          (message) =>
                              message.parentId == source.id &&
                              !isWorkspaceEmptyAgentMessage(message),
                        )
                        .toList();
                final draft = widget.drafts['$conversationKey:${source.id}'];
                final unreadCount =
                    widget
                        .threadUnreadCounts['$conversationKey:${source.id}'] ??
                    0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () =>
                          widget.onOpenThread(conversationKey, source.id),
                      child: Ink(
                        padding: const EdgeInsets.fromLTRB(18, 15, 18, 18),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  source.channelId == null
                                      ? Icons.person_outline
                                      : Icons.tag,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    widget.workspace.channelName(
                                          source.channelId ?? '',
                                        ) ??
                                        'Direct message',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${replies.length} ${replies.length == 1 ? 'reply' : 'replies'}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                    if (unreadCount > 0) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '$unreadCount new',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _ThreadPreviewMessage(
                              identity: source.senderPubkey,
                              author: _memberLabel(source.senderPubkey),
                              timestamp: _timeLabel(source.createdAt),
                              text: workspaceDisplayMessageText(source.body),
                            ),
                            for (final reply in replies.take(3)) ...[
                              const SizedBox(height: 14),
                              _ThreadPreviewMessage(
                                identity: reply.senderPubkey,
                                author: _memberLabel(reply.senderPubkey),
                                timestamp: _timeLabel(reply.createdAt),
                                text: workspaceDisplayMessageText(reply.body),
                              ),
                            ],
                            if (replies.length > 3)
                              Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Text(
                                  'Open thread to view ${replies.length - 3} more ${replies.length - 3 == 1 ? 'reply' : 'replies'}',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                ),
                              ),
                            if (draft?.value.text.trim().isNotEmpty ==
                                true) ...[
                              const SizedBox(height: 18),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(alpha: 0.32),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Draft reply',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(draft!.value.text.trim()),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  bool _matchesSearch(WorkspaceMessage source) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    final conversationKey = widget.workspace.conversationKeyForMessage(source);
    final replies =
        widget.workspace.messages[conversationKey] ??
        const <WorkspaceMessage>[];
    final channel =
        widget.workspace.channelName(source.channelId ?? '') ??
        'Direct message';
    return [
      channel,
      _memberLabel(source.senderPubkey),
      workspaceDisplayMessageText(source.body),
      ...replies
          .where((message) => message.parentId == source.id)
          .expand(
            (message) => [
              _memberLabel(message.senderPubkey),
              workspaceDisplayMessageText(message.body),
            ],
          ),
    ].any((value) => value.toLowerCase().contains(query));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _ThreadPreviewMessage extends StatelessWidget {
  const _ThreadPreviewMessage({
    required this.identity,
    required this.author,
    required this.timestamp,
    required this.text,
  });

  final String identity;
  final String author;
  final String timestamp;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _WorkspaceFrogAvatar(
        identity: identity,
        label: author,
        radius: 15,
        bot: isWorkspaceAgentSender(identity),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    author,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  timestamp,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(text),
          ],
        ),
      ),
    ],
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
    required this.sidebarSections,
    required this.onSidebarSectionChanged,
    required this.hasUnreadOtherSpaces,
    required this.otherWorkspaceAttentionVersion,
    required this.canManageAgents,
    required this.onSwitchSpace,
    required this.onLeaveSpace,
    required this.channels,
    required this.workspace,
    required this.members,
    required this.ownPubkey,
    required this.displayName,
    required this.memberAliases,
    required this.conversationPreferences,
    required this.memberNames,
    required this.unreadCounts,
    required this.threadUnreadCounts,
    required this.activityLabels,
    required this.fipsConnected,
    required this.fipsConnectedSpaceIds,
    required this.fipsConnectedPeers,
    required this.onSelect,
    required this.onOpenThread,
    required this.threadsSelected,
    required this.onShowThreads,
    required this.onSessions,
    required this.onSettings,
    required this.onToggleCollapsed,
    required this.onDiagnostics,
    required this.onWorkerConsole,
    required this.onRefresh,
    required this.onCreateChannel,
    required this.onCreateDirect,
    required this.onTogglePinConversation,
    required this.onToggleMuteConversation,
    required this.activeConversationMuted,
    required this.onToggleActiveConversationMuted,
  });
  final _WorkspaceSection section;
  final String? selected;
  final String? direct;
  final List<RepoTarget> sessions;
  final List<RepoTarget> spaces;
  final RepoTarget? activeSpace;
  final Map<String, bool> sidebarSections;
  final void Function(String section, bool expanded) onSidebarSectionChanged;
  final bool hasUnreadOtherSpaces;
  final int otherWorkspaceAttentionVersion;
  final bool canManageAgents;
  final ValueChanged<RepoTarget> onSwitchSpace;
  final ValueChanged<RepoTarget> onLeaveSpace;
  final List<WorkspaceChannel> channels;
  final WorkspaceState workspace;
  final List<String> members;
  final String ownPubkey;
  final String displayName;
  final Map<String, String> memberAliases;
  final Map<String, WorkspaceConversationPreference> conversationPreferences;
  final Map<String, String> memberNames;
  final Map<String, int> unreadCounts;
  final Map<String, int> threadUnreadCounts;
  final Map<String, String> activityLabels;
  final bool fipsConnected;
  final Set<String> fipsConnectedSpaceIds;
  final Set<String> fipsConnectedPeers;
  final void Function(_WorkspaceSection, String) onSelect;
  final void Function(String conversationKey, String threadId) onOpenThread;
  final bool threadsSelected;
  final VoidCallback onShowThreads;
  final VoidCallback onSessions;
  final VoidCallback onSettings;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onDiagnostics;
  final VoidCallback onWorkerConsole;
  final VoidCallback onRefresh;
  final VoidCallback onCreateChannel;
  final VoidCallback onCreateDirect;
  final void Function(_WorkspaceSection, String) onTogglePinConversation;
  final void Function(_WorkspaceSection, String) onToggleMuteConversation;
  final bool activeConversationMuted;
  final VoidCallback onToggleActiveConversationMuted;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<_WorkspacePalette>()!;
    String memberLabel(String pubkey) => pubkey == ownPubkey
        ? (memberNames[pubkey] ?? (displayName.isEmpty ? 'You' : displayName))
        : memberAliases[pubkey] ??
              memberNames[pubkey] ??
              compactIdentifier(pubkey);
    final sortedChannels = channels.toList()
      ..sort(
        (left, right) => _compareConversations(
          left.name,
          conversationPreferences[left.id],
          _latestMessageAt(left.id),
          right.name,
          conversationPreferences[right.id],
          _latestMessageAt(right.id),
        ),
      );
    final sortedMembers = members.toList()
      ..sort(
        (left, right) => _compareConversations(
          memberLabel(left),
          conversationPreferences[WorkspaceState.directKey(ownPubkey, left)],
          _latestMessageAt(WorkspaceState.directKey(ownPubkey, left)),
          memberLabel(right),
          conversationPreferences[WorkspaceState.directKey(ownPubkey, right)],
          _latestMessageAt(WorkspaceState.directKey(ownPubkey, right)),
        ),
      );
    final visibleChannels = sortedChannels
        .where(
          (channel) => conversationPreferences[channel.id]?.archived != true,
        )
        .toList(growable: false);
    final visibleMembers = sortedMembers
        .where(
          (member) =>
              conversationPreferences[WorkspaceState.directKey(
                    ownPubkey,
                    member,
                  )]
                  ?.archived !=
              true,
        )
        .toList(growable: false);
    final pinnedChannels = visibleChannels
        .where((channel) => conversationPreferences[channel.id]?.pinned == true)
        .toList(growable: false);
    final otherChannels = visibleChannels
        .where((channel) => conversationPreferences[channel.id]?.pinned != true)
        .toList(growable: false);
    final pinnedMembers = visibleMembers
        .where(
          (member) =>
              conversationPreferences[WorkspaceState.directKey(
                    ownPubkey,
                    member,
                  )]
                  ?.pinned ==
              true,
        )
        .toList(growable: false);
    final otherMembers = visibleMembers
        .where(
          (member) =>
              conversationPreferences[WorkspaceState.directKey(
                    ownPubkey,
                    member,
                  )]
                  ?.pinned !=
              true,
        )
        .toList(growable: false);
    final archivedChannels = sortedChannels
        .where(
          (channel) => conversationPreferences[channel.id]?.archived == true,
        )
        .toList(growable: false);
    final archivedMembers = sortedMembers
        .where(
          (member) =>
              conversationPreferences[WorkspaceState.directKey(
                    ownPubkey,
                    member,
                  )]
                  ?.archived ==
              true,
        )
        .toList(growable: false);
    final recentThreads =
        <String, WorkspaceMessage>{
          for (final messages in workspace.messages.values)
            for (final message in messages)
              if (message.parentId != null ||
                  message.mentions.any(
                    (mention) =>
                        mention.kind == 'member' && mention.id == ownPubkey,
                  ))
                '${workspace.conversationKeyForMessage(message)}:${message.parentId ?? message.id}':
                    message,
        }.values.toList()..sort(
          (left, right) => right.createdAt.compareTo(left.createdAt),
        );
    bool muted(String conversationKey) =>
        conversationPreferences[conversationKey]?.muted == true;
    int unreadCountForConversation(String conversationKey) =>
        (unreadCounts[conversationKey] ?? 0) +
        threadUnreadCounts.entries
            .where(
              (entry) =>
                  entry.value > 0 && entry.key.startsWith('$conversationKey:'),
            )
            .fold(0, (total, entry) => total + entry.value);
    bool hasUnreadActivity(String conversationKey) =>
        !muted(conversationKey) &&
        unreadCountForConversation(conversationKey) > 0;
    Widget item(
      IconData icon,
      String label, {
      bool selected = false,
      bool fipsConnected = false,
      VoidCallback? onTap,
      int unreadCount = 0,
      bool isMuted = false,
      String? count,
      String? activity,
      Widget? action,
      Widget? leading,
      bool reserveActivity = true,
    }) {
      Widget listItem({bool showAction = false}) => SizedBox(
        height: 42,
        child: Container(
          decoration: selected
              ? BoxDecoration(
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.38),
                  ),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: ListTile(
            dense: true,
            contentPadding: action == null || !showAction
                ? null
                : const EdgeInsetsDirectional.only(start: 16),
            selected: selected,
            selectedColor: palette.label,
            selectedTileColor: palette.selected,
            titleAlignment: ListTileTitleAlignment.center,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            leading:
                leading ??
                _UnreadConversationIcon(
                  icon: icon,
                  unread: unreadCount > 0 && !isMuted,
                ),
            title: Row(
              children: [
                Flexible(
                  child: _UnreadConversationLabel(
                    label: label,
                    unread: unreadCount > 0 && !isMuted,
                    style: fipsConnected
                        ? const TextStyle(color: Color(0xff35d6a0))
                        : null,
                  ),
                ),
                if (unreadCount > 0 && !isMuted) ...[
                  const SizedBox(width: 6),
                  Semantics(
                    label: '$unreadCount unread messages',
                    child: ExcludeSemantics(
                      child: Text(
                        '$unreadCount',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
                if (activity?.isNotEmpty == true) ...[
                  const SizedBox(width: 5),
                  _TypingDots(label: activity!),
                ],
              ],
            ),
            trailing: action != null && showAction
                ? SizedBox(width: 80, child: action)
                : count == null
                ? null
                : Text(count, style: Theme.of(context).textTheme.labelSmall),
            onTap: onTap,
          ),
        ),
      );
      if (action == null) return listItem();
      return _SidebarHoverActions(itemBuilder: listItem);
    }

    Widget conversationAction(
      _WorkspaceSection section,
      String id,
      bool pinned,
      bool isMuted,
    ) => Row(
      children: [
        IconButton(
          onPressed: () => onTogglePinConversation(section, id),
          icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
          tooltip: pinned ? 'Unpin conversation' : 'Pin conversation',
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          onPressed: () => onToggleMuteConversation(section, id),
          icon: Icon(
            isMuted
                ? Icons.notifications_off_outlined
                : Icons.notifications_none,
            size: 18,
          ),
          tooltip: isMuted ? 'Unmute conversation' : 'Mute conversation',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );

    return ColoredBox(
      color: palette.sidebar,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
            child: Row(
                  children: [
                    Expanded(
                      child: PopupMenuButton<String>(
                        tooltip: 'Switch workspace',
                        onSelected: (value) {
                          if (value == 'join') {
                            onSelect(_WorkspaceSection.access, 'access');
                            return;
                          }
                          if (value == 'leave') {
                            final activeSpace = this.activeSpace;
                            if (activeSpace != null) onLeaveSpace(activeSpace);
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
                              child: _UnreadConversationLabel(
                                label: space.displayName,
                                unread:
                                    space.id != activeSpace?.id &&
                                    hasUnreadOtherSpaces,
                                pulse: otherWorkspaceAttentionVersion,
                                attentionColor: const Color(0xff35d6a0),
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color:
                                          fipsConnectedSpaceIds.contains(
                                            space.id,
                                          )
                                          ? const Color(0xff35d6a0)
                                          : Colors.white,
                                    ),
                              ),
                            ),
                          if (activeSpace != null) ...[
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'leave',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.logout_outlined),
                                title: Text('Leave workspace'),
                              ),
                            ),
                          ],
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
                              child: _UnreadConversationLabel(
                                label:
                                    activeSpace?.displayName ??
                                    'Select workspace',
                                unread: hasUnreadOtherSpaces,
                                pulse: otherWorkspaceAttentionVersion,
                                attentionColor: const Color(0xff35d6a0),
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: fipsConnected
                                          ? const Color(0xff35d6a0)
                                          : null,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.expand_more, color: palette.label),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onToggleActiveConversationMuted,
                      icon: Icon(
                        activeConversationMuted
                            ? Icons.notifications_off_outlined
                            : Icons.notifications_none,
                      ),
                      tooltip: activeConversationMuted
                          ? 'Unmute conversation'
                          : 'Mute conversation',
                    ),
                    IconButton(
                      onPressed: onToggleCollapsed,
                      icon: const Icon(Icons.menu),
                      tooltip: 'Collapse sidebar',
                    ),
                  ],
                ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              children: [
                const SizedBox(height: 8),
                ListTile(
                  dense: true,
                  selected: threadsSelected,
                  leading: const Icon(Icons.forum_outlined, size: 19),
                  title: const Text('Threads'),
                  trailing: recentThreads.isEmpty
                      ? null
                      : Text(
                          '${recentThreads.length}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                  onTap: onShowThreads,
                ),
                const SizedBox(height: 16),
                _SidebarSection(
                  id: 'conversations',
                  expanded: sidebarSections['conversations'] ?? true,
                  onExpandedChanged: (expanded) =>
                      onSidebarSectionChanged('conversations', expanded),
                  title: 'Conversations',
                  icon: Icons.forum_outlined,
                  hasUnread: visibleChannels.any(
                    (channel) => hasUnreadActivity(channel.id),
                  ),
                  action: IconButton(
                    onPressed: onCreateChannel,
                    icon: const Icon(Icons.add, size: 18),
                    tooltip: 'Create channel',
                    visualDensity: VisualDensity.compact,
                  ),
                  children: [
                    if (pinnedChannels.isEmpty && otherChannels.isEmpty)
                      const ListTile(
                        dense: true,
                        title: Text('No channels yet'),
                      ),
                    for (final entry in pinnedChannels.indexed) ...[
                      item(
                        Icons.push_pin_outlined,
                        entry.$2.name,
                        selected: selected == entry.$2.id,
                        unreadCount: unreadCountForConversation(entry.$2.id),
                        isMuted: muted(entry.$2.id),
                        activity: activityLabels[entry.$2.id],
                        action: conversationAction(
                          _WorkspaceSection.channel,
                          entry.$2.id,
                          conversationPreferences[entry.$2.id]?.pinned == true,
                          muted(entry.$2.id),
                        ),
                        onTap: () =>
                            onSelect(_WorkspaceSection.channel, entry.$2.id),
                      ),
                      if (entry.$1 + 1 == pinnedChannels.length)
                        const Divider(height: 16, indent: 12, endIndent: 12),
                    ],
                    if (otherChannels.isNotEmpty)
                      _SidebarSection(
                        id: 'other-conversations',
                        expanded:
                            sidebarSections['other-conversations'] ?? false,
                        onExpandedChanged: (expanded) =>
                            onSidebarSectionChanged(
                              'other-conversations',
                              expanded,
                            ),
                        title: 'Other conversations',
                        icon: Icons.tag,
                        hasUnread: otherChannels.any(
                          (channel) => hasUnreadActivity(channel.id),
                        ),
                        children: [
                          for (final channel in otherChannels)
                            item(
                              Icons.tag,
                              channel.name,
                              selected: selected == channel.id,
                              unreadCount: unreadCountForConversation(
                                channel.id,
                              ),
                              isMuted: muted(channel.id),
                              activity: activityLabels[channel.id],
                              action: conversationAction(
                                _WorkspaceSection.channel,
                                channel.id,
                                false,
                                muted(channel.id),
                              ),
                              onTap: () => onSelect(
                                _WorkspaceSection.channel,
                                channel.id,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _SidebarSection(
                  id: 'direct-messages',
                  expanded: sidebarSections['direct-messages'] ?? true,
                  onExpandedChanged: (expanded) =>
                      onSidebarSectionChanged('direct-messages', expanded),
                  title: 'Direct messages',
                  icon: Icons.chat_bubble_outline,
                  hasUnread: visibleMembers.any(
                    (member) => hasUnreadActivity(
                      WorkspaceState.directKey(ownPubkey, member),
                    ),
                  ),
                  action: IconButton(
                    onPressed: onCreateDirect,
                    icon: const Icon(Icons.add, size: 18),
                    tooltip: 'New direct message',
                    visualDensity: VisualDensity.compact,
                  ),
                  children: [
                    if (pinnedMembers.isEmpty && otherMembers.isEmpty)
                      const ListTile(
                        dense: true,
                        title: Text('No direct messages yet'),
                      ),
                    for (final entry in pinnedMembers.indexed) ...[
                      item(
                        Icons.push_pin_outlined,
                        memberLabel(entry.$2),
                        leading: _WorkspaceFrogAvatar(
                          identity: entry.$2,
                          label: memberLabel(entry.$2),
                        ),
                        selected: direct == entry.$2,
                        fipsConnected: fipsConnectedPeers.contains(entry.$2),
                        unreadCount: unreadCountForConversation(
                          WorkspaceState.directKey(ownPubkey, entry.$2),
                        ),
                        isMuted: muted(
                          WorkspaceState.directKey(ownPubkey, entry.$2),
                        ),
                        activity:
                            activityLabels[WorkspaceState.directKey(
                              ownPubkey,
                              entry.$2,
                            )],
                        action: conversationAction(
                          _WorkspaceSection.direct,
                          entry.$2,
                          conversationPreferences[WorkspaceState.directKey(
                                    ownPubkey,
                                    entry.$2,
                                  )]
                                  ?.pinned ==
                              true,
                          muted(WorkspaceState.directKey(ownPubkey, entry.$2)),
                        ),
                        onTap: () =>
                            onSelect(_WorkspaceSection.direct, entry.$2),
                      ),
                      if (entry.$1 + 1 == pinnedMembers.length)
                        const Divider(height: 16, indent: 12, endIndent: 12),
                    ],
                    if (otherMembers.isNotEmpty)
                      _SidebarSection(
                        id: 'other-direct-messages',
                        expanded:
                            sidebarSections['other-direct-messages'] ?? false,
                        onExpandedChanged: (expanded) =>
                            onSidebarSectionChanged(
                              'other-direct-messages',
                              expanded,
                            ),
                        title: 'Other direct messages',
                        icon: Icons.chat_bubble_outline,
                        hasUnread: otherMembers.any(
                          (member) => hasUnreadActivity(
                            WorkspaceState.directKey(ownPubkey, member),
                          ),
                        ),
                        children: [
                          for (final member in otherMembers)
                            item(
                              Icons.chat_bubble_outline,
                              memberLabel(member),
                              leading: _WorkspaceFrogAvatar(
                                identity: member,
                                label: memberLabel(member),
                              ),
                              selected: direct == member,
                              fipsConnected: fipsConnectedPeers.contains(
                                member,
                              ),
                              unreadCount: unreadCountForConversation(
                                WorkspaceState.directKey(ownPubkey, member),
                              ),
                              isMuted: muted(
                                WorkspaceState.directKey(ownPubkey, member),
                              ),
                              activity:
                                  activityLabels[WorkspaceState.directKey(
                                    ownPubkey,
                                    member,
                                  )],
                              action: conversationAction(
                                _WorkspaceSection.direct,
                                member,
                                false,
                                muted(
                                  WorkspaceState.directKey(ownPubkey, member),
                                ),
                              ),
                              onTap: () =>
                                  onSelect(_WorkspaceSection.direct, member),
                            ),
                        ],
                      ),
                  ],
                ),
                if (archivedChannels.isNotEmpty ||
                    archivedMembers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SidebarSection(
                    id: 'archived',
                    expanded: sidebarSections['archived'] ?? true,
                    onExpandedChanged: (expanded) =>
                        onSidebarSectionChanged('archived', expanded),
                    title: 'Archived',
                    icon: Icons.inventory_2_outlined,
                    hasUnread:
                        archivedChannels.any(
                          (channel) => hasUnreadActivity(channel.id),
                        ) ||
                        archivedMembers.any(
                          (member) => hasUnreadActivity(
                            WorkspaceState.directKey(ownPubkey, member),
                          ),
                        ),
                    children: [
                      for (final channel in archivedChannels)
                        item(
                          Icons.inventory_2_outlined,
                          channel.name,
                          selected: selected == channel.id,
                          unreadCount: unreadCountForConversation(channel.id),
                          isMuted: muted(channel.id),
                          activity: activityLabels[channel.id],
                          action: conversationAction(
                            _WorkspaceSection.channel,
                            channel.id,
                            conversationPreferences[channel.id]?.pinned == true,
                            muted(channel.id),
                          ),
                          onTap: () =>
                              onSelect(_WorkspaceSection.channel, channel.id),
                        ),
                      for (final member in archivedMembers)
                        item(
                          Icons.inventory_2_outlined,
                          memberLabel(member),
                          leading: _WorkspaceFrogAvatar(
                            identity: member,
                            label: memberLabel(member),
                          ),
                          selected: direct == member,
                          unreadCount: unreadCountForConversation(
                            WorkspaceState.directKey(ownPubkey, member),
                          ),
                          isMuted: muted(
                            WorkspaceState.directKey(ownPubkey, member),
                          ),
                          activity:
                              activityLabels[WorkspaceState.directKey(
                                ownPubkey,
                                member,
                              )],
                          action: conversationAction(
                            _WorkspaceSection.direct,
                            member,
                            conversationPreferences[WorkspaceState.directKey(
                                      ownPubkey,
                                      member,
                                    )]
                                    ?.pinned ==
                                true,
                            muted(WorkspaceState.directKey(ownPubkey, member)),
                          ),
                          onTap: () =>
                              onSelect(_WorkspaceSection.direct, member),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                if (canManageAgents) ...[
                  _SidebarSection(
                    id: 'sessions',
                    expanded: sidebarSections['sessions'] ?? true,
                    onExpandedChanged: (expanded) =>
                        onSidebarSectionChanged('sessions', expanded),
                    title: 'Sessions',
                    icon: Icons.terminal_outlined,
                    children: [
                      for (final session in sessions.take(3))
                        item(
                          Icons.terminal_outlined,
                          session.displayName,
                          reserveActivity: false,
                          onTap: onSessions,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                _SidebarSection(
                  id: 'workspace',
                  expanded: sidebarSections['workspace'] ?? true,
                  onExpandedChanged: (expanded) =>
                      onSidebarSectionChanged('workspace', expanded),
                  title: 'Workspace',
                  icon: Icons.workspaces_outline,
                  children: [
                    item(
                      Icons.people_outline,
                      'Members',
                      reserveActivity: false,
                      selected: section == _WorkspaceSection.people,
                      onTap: () => onSelect(_WorkspaceSection.people, 'people'),
                    ),
                    item(
                      Icons.admin_panel_settings_outlined,
                      'Access',
                      reserveActivity: false,
                      selected: section == _WorkspaceSection.access,
                      onTap: () => onSelect(_WorkspaceSection.access, 'access'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SidebarSection(
                  id: 'maintenance',
                  expanded: sidebarSections['maintenance'] ?? true,
                  onExpandedChanged: (expanded) =>
                      onSidebarSectionChanged('maintenance', expanded),
                  title: 'Maintenance',
                  icon: Icons.build_outlined,
                  children: [
                    item(
                      Icons.monitor_heart_outlined,
                      'Host',
                      reserveActivity: false,
                      onTap: onWorkerConsole,
                    ),
                    item(
                      Icons.bug_report_outlined,
                      'Network',
                      reserveActivity: false,
                      onTap: onDiagnostics,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 18, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: onSettings,
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                ),
                const SizedBox(width: 4),
                Text(
                  'Ribbit $_appVersion',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: palette.label),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static int _compareConversations(
    String leftLabel,
    WorkspaceConversationPreference? left,
    int leftLatestMessageAt,
    String rightLabel,
    WorkspaceConversationPreference? right,
    int rightLatestMessageAt,
  ) {
    final pinOrder = (right?.pinned == true ? 1 : 0).compareTo(
      left?.pinned == true ? 1 : 0,
    );
    if (pinOrder != 0) return pinOrder;
    if (left?.pinned == true) {
      final recencyOrder = rightLatestMessageAt.compareTo(leftLatestMessageAt);
      if (recencyOrder != 0) return recencyOrder;
    }
    return leftLabel.toLowerCase().compareTo(rightLabel.toLowerCase());
  }

  int _latestMessageAt(String conversationKey) =>
      workspace.messages[conversationKey]?.fold<int>(
        0,
        (latest, message) =>
            latest > message.createdAt ? latest : message.createdAt,
      ) ??
      0;
}

class _SidebarHoverActions extends StatefulWidget {
  const _SidebarHoverActions({required this.itemBuilder});

  final Widget Function({bool showAction}) itemBuilder;

  @override
  State<_SidebarHoverActions> createState() => _SidebarHoverActionsState();
}

class _SidebarHoverActionsState extends State<_SidebarHoverActions> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: widget.itemBuilder(showAction: _hovered),
  );
}

class _UnreadConversationLabel extends StatefulWidget {
  const _UnreadConversationLabel({
    required this.label,
    required this.unread,
    this.style,
    this.attentionColor,
    this.pulse = 0,
  });

  final String label;
  final bool unread;
  final TextStyle? style;
  final Color? attentionColor;
  final int pulse;

  @override
  State<_UnreadConversationLabel> createState() =>
      _UnreadConversationLabelState();
}

class _UnreadConversationLabelState extends State<_UnreadConversationLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  void _syncAnimation() {
    if (widget.unread && !MediaQuery.disableAnimationsOf(context)) {
      _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _UnreadConversationLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unread != widget.unread) {
      _syncAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final attentionColor = widget.attentionColor ?? const Color(0xff35d6a0);
      final baseColor =
          widget.style?.color ?? Theme.of(context).colorScheme.onSurface;
      final color = widget.unread
          ? Color.lerp(attentionColor, Colors.white, _controller.value)!
          : baseColor;
      final style = (widget.style ?? const TextStyle()).copyWith(color: color);
      return Text(
        widget.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    },
  );
}

class _UnreadConversationIcon extends StatefulWidget {
  const _UnreadConversationIcon({required this.icon, required this.unread});

  final IconData icon;
  final bool unread;

  @override
  State<_UnreadConversationIcon> createState() =>
      _UnreadConversationIconState();
}

class _UnreadConversationIconState extends State<_UnreadConversationIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  void _syncAnimation() {
    if (widget.unread && !MediaQuery.disableAnimationsOf(context)) {
      _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _UnreadConversationIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unread != widget.unread) _syncAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Icon(
      widget.icon,
      size: 19,
      color: widget.unread
          ? Color.lerp(const Color(0xff35d6a0), Colors.white, _controller.value)
          : null,
    ),
  );
}

class _SidebarSection extends StatefulWidget {
  const _SidebarSection({
    required this.id,
    required this.expanded,
    required this.onExpandedChanged,
    required this.title,
    required this.icon,
    required this.children,
    this.hasUnread = false,
    this.action,
  });

  final String id;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool hasUnread;
  final Widget? action;

  @override
  State<_SidebarSection> createState() => _SidebarSectionState();
}

class _SidebarSectionState extends State<_SidebarSection> {
  var _hovered = false;

  void _toggle() => widget.onExpandedChanged(!widget.expanded);

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<_WorkspacePalette>()!;
    final showUnreadAttention = !widget.expanded && widget.hasUnread;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 40,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    if (_hovered)
                      Icon(
                        widget.expanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        size: 18,
                        color: palette.label,
                      )
                    else
                      _UnreadConversationIcon(
                        icon: widget.icon,
                        unread: showUnreadAttention,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _UnreadConversationLabel(
                        label: widget.title,
                        unread: showUnreadAttention,
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: palette.label),
                      ),
                    ),
                    if (widget.action != null) widget.action!,
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.expanded) ...[const SizedBox(height: 6), ...widget.children],
      ],
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
    required this.searchMessages,
    required this.threadTopics,
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
    required this.voiceDurationLabel,
    required this.onCancelVoiceRecording,
    required this.onOpenAttachment,
    required this.onOpenAgentLastResponse,
    required this.onOpenThread,
    required this.onCloseThread,
    required this.onOpenMessageReference,
    required this.onToggleReaction,
    required this.localMessagePinIds,
    required this.onToggleLocalMessagePin,
    required this.thread,
    required this.alsoSendToMain,
    required this.onAlsoSendToMainChanged,
    required this.onOpenSettings,
    required this.onReload,
    required this.onOpenFiles,
    required this.onRenameConversation,
    required this.onDeleteConversation,
    required this.conversationPreference,
    required this.onConversationPreferenceChanged,
    required this.inviteCode,
    required this.canCreateInvite,
    required this.memberStatus,
    required this.onCreateInvite,
    required this.onEnterInviteCode,
    required this.members,
    required this.channelHumanMemberCount,
    required this.ownPubkey,
    required this.localSenderIds,
    required this.fipsConnectedPeers,
    required this.displayName,
    required this.memberAliases,
    required this.memberNames,
    required this.memberAdmins,
    required this.canManageMembers,
    required this.canRemoveMembers,
    required this.onSetMemberAdmin,
    required this.onRemoveMember,
    required this.onOpenDirect,
    required this.onDisplayNameChanged,
    required this.onMemberAliasChanged,
    required this.workspace,
    required this.workspaceRevision,
    required this.onRequest,
    required this.onLoadOpenCodeModels,
    required this.initialFolderChoices,
    required this.onLoadFolders,
    required this.conversationPreprompt,
    required this.conversationFolderScope,
    required this.agents,
    required this.agentDirectory,
    required this.onManageAgents,
    required this.onEditConversationPreprompt,
    required this.onEditConversationFolder,
    required this.mentionOptions,
    required this.onMentionSelected,
    required this.typingStatuses,
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
  final List<WorkspaceMessage> searchMessages;
  final Map<String, String> threadTopics;
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
  final String voiceDurationLabel;
  final VoidCallback onCancelVoiceRecording;
  final Future<void> Function(BridgeAudioReference attachment) onOpenAttachment;
  final ValueChanged<WorkspaceMessage> onOpenAgentLastResponse;
  final ValueChanged<WorkspaceMessage> onOpenThread;
  final VoidCallback onCloseThread;
  final ValueChanged<WorkspaceMessage> onOpenMessageReference;
  final Future<void> Function(WorkspaceMessage message, String emoji)
  onToggleReaction;
  final Set<String> localMessagePinIds;
  final ValueChanged<String> onToggleLocalMessagePin;
  final WorkspaceMessage? thread;
  final bool alsoSendToMain;
  final ValueChanged<bool> onAlsoSendToMainChanged;
  final VoidCallback onOpenSettings;
  final VoidCallback onReload;
  final Future<void> Function() onOpenFiles;
  final Future<void> Function(String name) onRenameConversation;
  final Future<void> Function() onDeleteConversation;
  final WorkspaceConversationPreference conversationPreference;
  final void Function({bool? pinned, bool? archived, bool? muted})
  onConversationPreferenceChanged;
  final String? inviteCode;
  final bool canCreateInvite;
  final String memberStatus;
  final Future<void> Function() onCreateInvite;
  final VoidCallback onEnterInviteCode;
  final List<String> members;
  final int channelHumanMemberCount;
  final String ownPubkey;
  final Set<String> localSenderIds;
  final Set<String> fipsConnectedPeers;
  final String displayName;
  final Map<String, String> memberAliases;
  final Map<String, String> memberNames;
  final Set<String> memberAdmins;
  final bool canManageMembers;
  final bool canRemoveMembers;
  final Future<void> Function(String pubkey, bool isAdmin) onSetMemberAdmin;
  final Future<void> Function(String pubkey) onRemoveMember;
  final ValueChanged<String> onOpenDirect;
  final ValueChanged<String> onDisplayNameChanged;
  final void Function(String pubkey, String alias) onMemberAliasChanged;
  final WorkspaceState workspace;
  final ValueListenable<int> workspaceRevision;
  final Future<void> Function(Map<String, Object?> request) onRequest;
  final Future<List<_OpenCodeModelChoice>> Function() onLoadOpenCodeModels;
  final List<RepoChoice> initialFolderChoices;
  final Future<List<RepoChoice>> Function(String? path) onLoadFolders;
  final String conversationPreprompt;
  final List<String> conversationFolderScope;
  final List<WorkspaceAgent> agents;
  final List<WorkspaceAgent> agentDirectory;
  final VoidCallback? onManageAgents;
  final Future<void> Function(String value) onEditConversationPreprompt;
  final Future<void> Function(List<String> folders) onEditConversationFolder;
  final List<WorkspaceMention> mentionOptions;
  final ValueChanged<WorkspaceMention> onMentionSelected;
  final List<WorkspaceTyping> typingStatuses;
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
  final _searchFocus = FocusNode();
  String? _lastMessageId;
  double? _lastViewportHeight;
  bool _scrollQueued = false;
  bool _historyDateQueued = false;
  bool _searchOpen = false;
  String _searchQuery = '';
  String? _visibleHistoryDate;
  final _messageKeys = <String, GlobalKey>{};

  Future<void> _cancelAgentTask(String agentId) async {
    _cancellingAgentIds.add(agentId);
    setState(() {});
    try {
      await widget.onRequest({
        'action': 'abort_agent_task',
        'agent_id': agentId,
      });
    } catch (_) {
      if (mounted) {
        _cancellingAgentIds.remove(agentId);
        setState(() {});
      }
      rethrow;
    }
  }

  void _showMentionDetails(WorkspaceMention mention) {
    final agent = mention.kind == 'agent'
        ? widget.workspace.agents
              .where((agent) => agent.id == mention.id)
              .firstOrNull
        : null;
    final lastResponse = agent == null ? null : _lastResponseFor(agent);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _WorkspaceMentionDetails(
        mention: mention,
        workspace: widget.workspace,
        ownPubkey: widget.ownPubkey,
        displayName: widget.displayName,
        memberNames: widget.memberNames,
        memberAliases: widget.memberAliases,
        onOpenLastResponse: lastResponse == null
            ? null
            : () {
                Navigator.of(context).pop();
                widget.onOpenAgentLastResponse(lastResponse);
              },
        onOpenDirect: mention.kind == 'member' && mention.id != widget.ownPubkey
            ? () {
                Navigator.of(context).pop();
                widget.onOpenDirect(mention.id);
              }
            : null,
      ),
    );
  }

  WorkspaceMessage? _lastResponseFor(WorkspaceAgent agent) => widget
      .workspace
      .messages
      .values
      .expand((messages) => messages)
      .where((message) => message.senderPubkey == 'agent:${agent.id}')
      .fold<WorkspaceMessage?>(
        null,
        (latest, message) =>
            latest == null || message.createdAt > latest.createdAt
            ? message
            : latest,
      );

  void _updateCancelledAgents() {
    final activeAgentIds = widget.typingStatuses
        .map((status) => status.agentId)
        .whereType<String>()
        .toSet();
    final stoppedAgentIds = _cancellingAgentIds
        .where((agentId) => !activeAgentIds.contains(agentId))
        .toList(growable: false);
    if (stoppedAgentIds.isEmpty) return;
    _cancellingAgentIds.removeAll(stoppedAgentIds);
    _cancelledAgentIds.addAll(stoppedAgentIds);
    for (final agentId in stoppedAgentIds) {
      _cancelledAgentTimers[agentId]?.cancel();
      _cancelledAgentTimers[agentId] = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _cancelledAgentIds.remove(agentId));
        _cancelledAgentTimers.remove(agentId);
      });
    }
  }

  final _cancellingAgentIds = <String>{};
  final _cancelledAgentIds = <String>{};
  final _cancelledAgentTimers = <String, Timer>{};

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

  Future<void> _editConversationFolder() async {
    final folders = await showDialog<List<String>>(
      context: context,
      builder: (_) => _FolderScopeDialog(
        initialSelected: widget.conversationFolderScope,
        initialChoices: widget.initialFolderChoices,
        onLoadFolders: widget.onLoadFolders,
      ),
    );
    if (folders != null) await widget.onEditConversationFolder(folders);
  }

  @override
  void initState() {
    super.initState();
    _lastMessageId = _latestMessageId;
    _queueScrollToLatest();
    _queueVisibleHistoryDateUpdate();
  }

  @override
  void didUpdateWidget(covariant _WorkspaceConversation oldWidget) {
    super.didUpdateWidget(oldWidget);
    final conversationChanged =
        oldWidget.section != widget.section ||
        oldWidget.channelId != widget.channelId ||
        oldWidget.directPeer != widget.directPeer;
    if (conversationChanged) {
      for (final timer in _cancelledAgentTimers.values) {
        timer.cancel();
      }
      _cancellingAgentIds.clear();
      _cancelledAgentIds.clear();
      _cancelledAgentTimers.clear();
      _searchController.clear();
      _searchQuery = '';
      _searchOpen = false;
      _lastMessageId = _latestMessageId;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      return;
    }
    _updateCancelledAgents();
    if (_lastMessageId != _latestMessageId) {
      _lastMessageId = _latestMessageId;
      _queueScrollToLatest();
    }
  }

  @override
  void dispose() {
    for (final timer in _cancelledAgentTimers.values) {
      timer.cancel();
    }
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? get _latestMessageId =>
      widget.messages.isEmpty ? null : widget.messages.last.id;

  int get _humanCount => widget.section == _WorkspaceSection.channel
      ? widget.channelHumanMemberCount
      : {widget.ownPubkey, ?widget.directPeer}.length;

  String _historyDateLabel(int seconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
    final today = DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    if (day == todayDay) return 'Today';
    if (day == todayDay.subtract(const Duration(days: 1))) return 'Yesterday';
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  void _queueVisibleHistoryDateUpdate() {
    if (_historyDateQueued) return;
    _historyDateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historyDateQueued = false;
      if (!mounted) return;
      final viewport = context.findRenderObject() as RenderBox?;
      if (viewport == null || !viewport.hasSize) return;
      final viewportTop = viewport.localToGlobal(Offset.zero).dy;
      WorkspaceMessage? firstVisible;
      var firstVisibleTop = double.infinity;
      for (final message in _visibleMessages) {
        final box =
            _messageKeys[message.id]?.currentContext?.findRenderObject()
                as RenderBox?;
        if (box == null || !box.hasSize) continue;
        final top = box.localToGlobal(Offset.zero).dy;
        if (top + box.size.height > viewportTop && top < firstVisibleTop) {
          firstVisible = message;
          firstVisibleTop = top;
        }
      }
      if (firstVisible == null) return;
      final label = _historyDateLabel(firstVisible.createdAt);
      if (_visibleHistoryDate != label) {
        setState(() => _visibleHistoryDate = label);
      }
    });
  }

  int get _unreadThreadReplyCount =>
      widget.threadUnreadCounts.values.fold(0, (total, count) => total + count);

  List<WorkspaceMessage> get _unreadThreadSources => widget.messages
      .where((message) => (widget.threadUnreadCounts[message.id] ?? 0) > 0)
      .toList(growable: false);

  bool _showsMainLiveMessage(WorkspaceTyping status) =>
      status.agentId == null && status.parentId == null;

  List<WorkspaceMessage> get _visibleMessages {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return widget.messages;
    return widget.searchMessages
        .where(
          (message) =>
              message.body.toLowerCase().contains(query) ||
              _memberLabel(message.senderPubkey).toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  List<WorkspaceMessage> get _sharedPinnedMessages =>
      widget.searchMessages
          .where((message) => message.pinned)
          .toList(growable: false)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<WorkspaceMessage> get _savedMessages =>
      widget.searchMessages
          .where((message) => widget.localMessagePinIds.contains(message.id))
          .toList(growable: false)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  WorkspaceMessage _threadSourceFor(WorkspaceMessage message) {
    final parentId = message.parentId;
    if (parentId == null) return message;
    return widget.searchMessages.firstWhere(
      (candidate) => candidate.id == parentId,
      orElse: () => message,
    );
  }

  WorkspaceMessage? _threadSourceForId(String parentId) => widget.searchMessages
      .where((message) => message.id == parentId)
      .firstOrNull;

  void _openMessageReference(String messageId) {
    final message = widget.searchMessages
        .where((candidate) => candidate.id == messageId)
        .firstOrNull;
    if (message != null) widget.onOpenMessageReference(message);
  }

  VoidCallback? _typingThreadOpener(WorkspaceTyping status) {
    final parentId = status.parentId;
    final source = parentId == null ? null : _threadSourceForId(parentId);
    return source == null ? null : () => widget.onOpenThread(source);
  }

  void _openSearchResult(WorkspaceMessage message) {
    _clearSearch();
    final parentId = message.parentId;
    if (parentId != null) {
      final source = _threadSourceForId(parentId);
      if (source != null) widget.onOpenThread(source);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _messageKeys[message.id]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: 0.5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _showPinnedMessages(
    BuildContext context, {
    required String title,
    required List<WorkspaceMessage> messages,
  }) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: _PinnedMessagesPanel(
        title: title,
        messages: messages,
        memberLabel: _memberLabel,
        isLocallyPinned: (message) =>
            widget.localMessagePinIds.contains(message.id),
        onOpen: (message) {
          Navigator.pop(sheetContext);
          _openSearchResult(message);
        },
      ),
    ),
  );

  void _resetSearchView() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _clearSearch() {
    final hadQuery = _searchQuery.trim().isNotEmpty;
    setState(() {
      _searchController.clear();
      _searchQuery = '';
    });
    if (hadQuery) _resetSearchView();
  }

  void _onSearchChanged(String value) {
    final hadQuery = _searchQuery.trim().isNotEmpty;
    setState(() => _searchQuery = value);
    if (hadQuery && value.trim().isEmpty) _resetSearchView();
  }

  void _toggleSearch() {
    if (_searchOpen) {
      _closeSearch();
      return;
    }
    _openSearch();
  }

  void _closeSearch() {
    if (!_searchOpen) return;
    _searchFocus.unfocus();
    setState(() => _searchOpen = false);
    _clearSearch();
  }

  void _openSearch() {
    if (_searchOpen) {
      _searchFocus.requestFocus();
      return;
    }
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
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

  Future<void> _showConversationActions([BuildContext? anchorContext]) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final anchor = anchorContext?.findRenderObject() as RenderBox?;
    final position = anchor == null
        ? RelativeRect.fromLTRB(0, kToolbarHeight, 16, 0)
        : RelativeRect.fromRect(
            anchor.localToGlobal(Offset.zero, ancestor: overlay) & anchor.size,
            Offset.zero & overlay.size,
          );
    final action = await showMenu<String>(
      context: context,
      position: position,
      items: [
        if (widget.onManageAgents != null)
          const PopupMenuItem(
            value: 'agents',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.person_add_alt_1_outlined),
              title: Text('Manage agents'),
            ),
          ),
        if (widget.section == _WorkspaceSection.channel)
          PopupMenuItem(
            value: 'folder',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Edit default repository'),
              subtitle: Text(
                widget.conversationFolderScope.isEmpty
                    ? 'Current workspace directory'
                    : widget.conversationFolderScope.join(', '),
              ),
            ),
          ),
        const PopupMenuItem(
          value: 'rename',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined),
            title: Text('Rename conversation'),
          ),
        ),
        PopupMenuItem(
          value: 'pin',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              widget.conversationPreference.pinned
                  ? Icons.push_pin_outlined
                  : Icons.push_pin,
            ),
            title: Text(
              widget.conversationPreference.pinned
                  ? 'Unpin conversation'
                  : 'Pin conversation',
            ),
          ),
        ),
        PopupMenuItem(
          value: 'mute',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              widget.conversationPreference.muted
                  ? Icons.notifications_none
                  : Icons.notifications_off_outlined,
            ),
            title: Text(
              widget.conversationPreference.muted
                  ? 'Unmute conversation'
                  : 'Mute conversation',
            ),
          ),
        ),
        PopupMenuItem(
          value: 'archive',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              widget.conversationPreference.archived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
            ),
            title: Text(
              widget.conversationPreference.archived
                  ? 'Unarchive conversation'
                  : 'Archive conversation',
            ),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Delete conversation',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'agents') {
      widget.onManageAgents?.call();
    } else if (action == 'folder') {
      await _editConversationFolder();
    } else if (action == 'rename') {
      await _renameConversation();
    } else if (action == 'pin') {
      widget.onConversationPreferenceChanged(
        pinned: !widget.conversationPreference.pinned,
      );
    } else if (action == 'mute') {
      widget.onConversationPreferenceChanged(
        muted: !widget.conversationPreference.muted,
      );
    } else if (action == 'archive') {
      widget.onConversationPreferenceChanged(
        archived: !widget.conversationPreference.archived,
      );
    } else {
      await _deleteConversation();
    }
  }

  Future<void> _showMobileConversationActions() async {
    final directCall = widget.section == _WorkspaceSection.direct;
    final channelCall = widget.section == _WorkspaceSection.channel;
    final callPhase = directCall
        ? widget.callPeerPubkey == null ||
                  widget.callPeerPubkey == widget.directPeer
              ? widget.callPhase
              : _CallPhase.idle
        : widget.groupCallChannelId == null ||
              widget.groupCallChannelId == widget.channelId
        ? widget.groupCallPhase
        : _CallPhase.idle;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onManageAgents != null)
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_outlined),
                title: const Text('Manage agents'),
                onTap: () => Navigator.pop(context, 'agents'),
              ),
            ListTile(
              leading: Icon(
                _searchOpen ? Icons.search_off_outlined : Icons.search,
              ),
              title: Text(_searchOpen ? 'Close search' : 'Search messages'),
              onTap: () => Navigator.pop(context, 'search'),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward_outlined),
              title: const Text('Reload last messages'),
              onTap: () => Navigator.pop(context, 'reload'),
            ),
            if (channelCall || directCall)
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('Browse repository files'),
                onTap: () => Navigator.pop(context, 'files'),
              ),
            if (channelCall)
              ListTile(
                leading: const Icon(Icons.edit_note_outlined),
                title: const Text('Edit agent brief'),
                onTap: () => Navigator.pop(context, 'brief'),
              ),
            if (channelCall)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Edit default repository'),
                onTap: () => Navigator.pop(context, 'folder'),
              ),
            if (_supportsLiveCalls && (directCall || channelCall)) ...[
              const Divider(height: 1),
              if (callPhase == _CallPhase.idle)
                ListTile(
                  leading: const Icon(Icons.call_outlined),
                  title: const Text('Start call'),
                  onTap: () => Navigator.pop(context, 'call'),
                ),
              if (callPhase == _CallPhase.incoming) ...[
                ListTile(
                  leading: const Icon(Icons.call_outlined),
                  title: const Text('Answer call'),
                  onTap: () => Navigator.pop(context, 'answer'),
                ),
                ListTile(
                  leading: const Icon(Icons.call_end_outlined),
                  title: const Text('Reject call'),
                  onTap: () => Navigator.pop(context, 'reject'),
                ),
              ],
              if (callPhase == _CallPhase.outgoing ||
                  callPhase == _CallPhase.connecting ||
                  callPhase == _CallPhase.active)
                ListTile(
                  leading: const Icon(Icons.call_end_outlined),
                  title: const Text('Hang up'),
                  onTap: () => Navigator.pop(context, 'hangup'),
                ),
              if (callPhase == _CallPhase.active) ...[
                ListTile(
                  leading: const Icon(Icons.volume_up_outlined),
                  title: const Text('Audio only'),
                  onTap: () => Navigator.pop(context, 'audio'),
                ),
                ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: const Text('Use camera'),
                  onTap: () => Navigator.pop(context, 'camera'),
                ),
                ListTile(
                  leading: const Icon(Icons.screen_share_outlined),
                  title: const Text('Share screen'),
                  onTap: () => Navigator.pop(context, 'screen'),
                ),
              ],
            ],
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: const Text('Settings'),
              onTap: () => Navigator.pop(context, 'settings'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'agents':
        widget.onManageAgents?.call();
        break;
      case 'search':
        _toggleSearch();
        break;
      case 'reload':
        widget.onReload();
        break;
      case 'files':
        await widget.onOpenFiles();
        break;
      case 'brief':
        await _editConversationPreprompt();
        break;
      case 'folder':
        await _editConversationFolder();
        break;
      case 'call':
        if (directCall) {
          widget.onStartCall(widget.directPeer!);
        } else {
          await widget.onStartChannelCall(widget.channelId!);
        }
        break;
      case 'answer':
        directCall ? widget.onAcceptCall() : widget.onAcceptGroupCall();
        break;
      case 'reject':
        directCall ? widget.onRejectCall() : widget.onRejectGroupCall();
        break;
      case 'hangup':
        directCall ? widget.onHangupCall() : widget.onHangupGroupCall();
        break;
      case 'audio':
        widget.onMediaSourceChanged(_CallMediaSource.audioOnly);
        break;
      case 'camera':
        widget.onMediaSourceChanged(_CallMediaSource.camera);
        break;
      case 'screen':
        widget.onMediaSourceChanged(_CallMediaSource.screen);
        break;
      case 'settings':
        widget.onOpenSettings();
        break;
    }
  }

  void _queueScrollToLatest() {
    if (_scrollQueued) return;
    _scrollQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollQueued = false;
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
      // Rich text and attachment controls can increase height after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
        _queueVisibleHistoryDateUpdate();
      });
    });
  }

  String _memberLabel(String pubkey) {
    if (pubkey.startsWith('agent:')) {
      final id = pubkey.substring('agent:'.length);
      for (final agent in widget.agentDirectory) {
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

  Future<void> _showConversationMembers() async {
    final channel = widget.workspace.channels
        .where((channel) => channel.id == widget.channelId)
        .firstOrNull;
    final configuredMembers =
        channel?.members ?? const <WorkspaceChannelMember>[];
    final creatorIsAdmin = channel?.createdBy == widget.ownPubkey;
    final members = widget.section == _WorkspaceSection.channel
        ? configuredMembers.isNotEmpty
              ? configuredMembers
              : {
                  if (creatorIsAdmin)
                    widget.ownPubkey: WorkspaceChannelMember(
                      pubkey: widget.ownPubkey,
                      isAdmin: true,
                    ),
                  for (final message in widget.searchMessages)
                    if (message.senderPubkey.isNotEmpty &&
                        !isWorkspaceAgentSender(message.senderPubkey) &&
                        message.senderPubkey != widget.ownPubkey)
                      message.senderPubkey: WorkspaceChannelMember(
                        pubkey: message.senderPubkey,
                      ),
                }.values.toList(growable: false)
        : [
            WorkspaceChannelMember(pubkey: widget.ownPubkey),
            if (widget.directPeer != null)
              WorkspaceChannelMember(pubkey: widget.directPeer!),
          ];
    await showDialog<void>(
      context: context,
      builder: (context) => _ConversationMembersDialog(
        members: members,
        agents: widget.agents,
        workspaceMembers: widget.members,
        canManage:
            creatorIsAdmin ||
            (channel?.members.any(
                  (member) =>
                      member.pubkey == widget.ownPubkey && member.isAdmin,
                ) ??
                false),
        memberLabel: _memberLabel,
        onAdd: channel == null
            ? null
            : (pubkey) => widget.onRequest({
                'action': 'add_channel_member',
                'channel_id': channel.id,
                'member_pubkey': pubkey,
              }),
        onRemove: channel == null
            ? null
            : (pubkey) => widget.onRequest({
                'action': 'remove_channel_member',
                'channel_id': channel.id,
                'member_pubkey': pubkey,
              }),
      ),
    );
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
        memberAdmins: widget.memberAdmins,
        canManageMembers: widget.canManageMembers,
        canRemoveMembers: widget.canRemoveMembers,
        onSetMemberAdmin: widget.onSetMemberAdmin,
        onRemoveMember: widget.onRemoveMember,
        onOpenDirect: widget.onOpenDirect,
        onDisplayNameChanged: widget.onDisplayNameChanged,
        onMemberAliasChanged: widget.onMemberAliasChanged,
      );
    }
    if (widget.section == _WorkspaceSection.access) {
      return _WorkspaceAccessPage(
        memberStatus: widget.memberStatus,
        canCreateInvite: widget.canCreateInvite,
        inviteCode: widget.inviteCode,
        onEnterInviteCode: widget.onEnterInviteCode,
        onCreateInvite: widget.onCreateInvite,
      );
    }
    final palette = Theme.of(context).extension<_WorkspacePalette>()!;
    final visibleMessages = _visibleMessages;
    final sharedPinnedMessages = _sharedPinnedMessages;
    final savedMessages = _savedMessages;
    final searching = _searchQuery.trim().isNotEmpty;
    final compactHeader = MediaQuery.sizeOf(context).width < 720;
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final isSearchShortcut =
            event.logicalKey == LogicalKeyboardKey.keyF &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed);
        if (event.logicalKey == LogicalKeyboardKey.escape && _searchOpen ||
            isSearchShortcut) {
          _toggleSearch();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _toggleSearch,
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              _toggleSearch,
          const SingleActivator(LogicalKeyboardKey.escape): _closeSearch,
        },
        child: ColoredBox(
          color: palette.content,
          child: Column(
            children: [
              if (!compactHeader)
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
                                TextButton(
                                  onPressed: _showConversationMembers,
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    alignment: Alignment.centerLeft,
                                  ),
                                  child: Text(
                                    '$_humanCount humans - ${widget.agents.length} agents',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
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
                            onPressed: _toggleSearch,
                            icon: Icon(
                              _searchOpen
                                  ? Icons.search_off_outlined
                                  : Icons.search,
                            ),
                            tooltip: _searchOpen
                                ? 'Close search'
                                : 'Search messages',
                          ),
                          IconButton(
                            onPressed: widget.onReload,
                            icon: const Icon(Icons.arrow_upward_outlined),
                            tooltip: 'Reload last messages',
                          ),
                          if (widget.section == _WorkspaceSection.channel ||
                              widget.section == _WorkspaceSection.direct)
                            IconButton(
                              onPressed: () => unawaited(widget.onOpenFiles()),
                              icon: const Icon(Icons.folder_open_outlined),
                              tooltip: 'Browse repository files',
                            ),
                          if (widget.section == _WorkspaceSection.channel)
                            IconButton(
                              onPressed: _editConversationPreprompt,
                              icon: const Icon(Icons.edit_note_outlined),
                              tooltip: 'Edit agent brief',
                            ),
                          if (widget.section == _WorkspaceSection.channel)
                            Builder(
                              builder: (anchorContext) => IconButton(
                                onPressed: () => unawaited(
                                  _showConversationActions(anchorContext),
                                ),
                                icon: const Icon(Icons.more_horiz),
                                tooltip: 'Conversation options',
                              ),
                            ),
                          if (_supportsLiveCalls &&
                              widget.section == _WorkspaceSection.direct)
                            _CallControl(
                              phase:
                                  widget.callPeerPubkey == null ||
                                      widget.callPeerPubkey == widget.directPeer
                                  ? widget.callPhase
                                  : _CallPhase.idle,
                              onStart: () =>
                                  widget.onStartCall(widget.directPeer!),
                              onAccept: widget.onAcceptCall,
                              onReject: widget.onRejectCall,
                              onHangup: widget.onHangupCall,
                              mediaSource: widget.mediaSource,
                              onMediaSourceChanged: widget.onMediaSourceChanged,
                            ),
                          if (_supportsLiveCalls &&
                              widget.section == _WorkspaceSection.channel)
                            _CallControl(
                              phase:
                                  widget.groupCallChannelId == null ||
                                      widget.groupCallChannelId ==
                                          widget.channelId
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
                          focusNode: _searchFocus,
                          autofocus: true,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            isDense: true,
                            prefixIcon: const Icon(Icons.search),
                            hintText: 'Search messages and people',
                            suffixIcon: _searchQuery.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: _clearSearch,
                                    icon: const Icon(Icons.close),
                                  ),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (!compactHeader) const Divider(height: 1),
              if (compactHeader && _searchOpen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    autofocus: true,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search messages and people',
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: _clearSearch,
                              icon: const Icon(Icons.close),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              if (sharedPinnedMessages.isNotEmpty || savedMessages.isNotEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compactHeader ? 16 : 24,
                    8,
                    compactHeader ? 16 : 24,
                    0,
                  ),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      if (sharedPinnedMessages.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _showPinnedMessages(
                            context,
                            title: 'Pins',
                            messages: sharedPinnedMessages,
                          ),
                          icon: const Icon(Icons.push_pin_outlined, size: 18),
                          label: const Text('Pins'),
                        ),
                      if (savedMessages.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _showPinnedMessages(
                            context,
                            title: 'Saved',
                            messages: savedMessages,
                          ),
                          icon: const Icon(Icons.bookmark_outline, size: 18),
                          label: const Text('Saved'),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollUpdateNotification ||
                            notification is ScrollEndNotification) {
                          _queueVisibleHistoryDateUpdate();
                        }
                        return false;
                      },
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (_lastViewportHeight != constraints.maxHeight) {
                            _lastViewportHeight = constraints.maxHeight;
                            _queueScrollToLatest();
                          }
                          if (searching && visibleMessages.isEmpty) {
                            return const Center(
                              child: Text(
                                'No messages or people match this search.',
                              ),
                            );
                          }
                          return ListView.builder(
                            controller: _scrollController,
                            reverse: true,
                            padding: EdgeInsets.fromLTRB(
                              compactHeader ? 16 : 24,
                              20,
                              compactHeader ? 16 : 24,
                              6,
                            ),
                            itemCount: visibleMessages.length + 1,
                            itemBuilder: (context, index) {
                              if (index == visibleMessages.length) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (widget.conversationPreprompt.isEmpty &&
                                        widget.section ==
                                            _WorkspaceSection.channel)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 16,
                                        ),
                                        child: TextButton.icon(
                                          onPressed: _editConversationPreprompt,
                                          icon: const Icon(
                                            Icons.edit_note_outlined,
                                          ),
                                          label: const Text(
                                            'Add an agent brief',
                                          ),
                                        ),
                                      )
                                    else if (widget
                                        .conversationPreprompt
                                        .isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 20,
                                        ),
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: palette.sidebar.withValues(
                                            alpha: 0.55,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Agent brief',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.labelLarge,
                                            ),
                                            const SizedBox(height: 5),
                                            Text(widget.conversationPreprompt),
                                          ],
                                        ),
                                      ),
                                  ],
                                );
                              }
                              final messageIndex =
                                  visibleMessages.length - index - 1;
                              final m = visibleMessages[messageIndex];
                              final previous = messageIndex == 0
                                  ? null
                                  : visibleMessages[messageIndex - 1];
                              // A reply thread makes its source a distinct
                              // conversation turn, even if its author repeats.
                              final grouped =
                                  isWorkspaceMessageGroupedWithPrevious(
                                    m,
                                    previous,
                                  ) &&
                                  (previous == null ||
                                      (widget.threadReplyCounts[previous.id] ??
                                              0) ==
                                          0);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: KeyedSubtree(
                                  key: _messageKeys.putIfAbsent(
                                    m.id,
                                    GlobalKey.new,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: m.parentId == null
                                        ? CrossAxisAlignment.stretch
                                        : CrossAxisAlignment.start,
                                    children: [
                                      _WorkspaceMessageRow(
                                        message: m,
                                        authorName: _memberLabel(
                                          m.senderPubkey,
                                        ),
                                        groupedWithPrevious: grouped,
                                        isLocalSender: isWorkspaceLocalSender(
                                          m.senderPubkey,
                                          widget.localSenderIds,
                                        ),
                                        fipsConnected: widget.fipsConnectedPeers
                                            .contains(m.senderPubkey),
                                        onThread: () => widget.onOpenThread(
                                          _threadSourceFor(m),
                                        ),
                                        threadReplyCount:
                                            widget.threadReplyCounts[m.id] ?? 0,
                                        threadUnreadCount:
                                            widget.threadUnreadCounts[m.id] ??
                                            0,
                                        threadActivityLabel:
                                            widget.threadActivityLabels[m.id],
                                        threadTopic: widget.threadTopics[m.id],
                                        isThreadSource:
                                            widget.thread?.id == m.id,
                                        onOpenMessageReference:
                                            _openMessageReference,
                                        onOpenMention: _showMentionDetails,
                                        onReact: (emoji) => unawaited(
                                          widget.onToggleReaction(m, emoji),
                                        ),
                                        isLocallyPinned: widget
                                            .localMessagePinIds
                                            .contains(m.id),
                                        onToggleLocalPin: () => widget
                                            .onToggleLocalMessagePin(m.id),
                                        onToggleSharedPin: () => unawaited(
                                          widget.onRequest({
                                            'action': 'toggle_pin',
                                            'parent_id': m.id,
                                          }),
                                        ),
                                        onOpenAttachment:
                                            widget.onOpenAttachment,
                                        searchQuery: _searchQuery,
                                      ),
                                      if (searching)
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton.icon(
                                            onPressed: () =>
                                                _openSearchResult(m),
                                            icon: const Icon(
                                              Icons.my_location_outlined,
                                              size: 16,
                                            ),
                                            label: const Text('Open here'),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    if (_visibleHistoryDate != null)
                      Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: Container(
                                key: ValueKey(_visibleHistoryDate),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.sidebar.withValues(
                                    alpha: 0.92,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: palette.label.withValues(
                                      alpha: 0.22,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _visibleHistoryDate!,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              for (final status in widget.typingStatuses)
                if (_showsMainLiveMessage(status))
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      compactHeader ? 16 : 24,
                      0,
                      compactHeader ? 16 : 24,
                      8,
                    ),
                    child: _WorkspaceLiveMessageRow(
                      status: status,
                      authorName: _memberLabel(status.senderPubkey),
                    ),
                  ),
              SizedBox(
                height: 20,
                child:
                    _unreadThreadReplyCount > 0 ||
                        widget.typingStatuses.any(
                          (status) => !_showsMainLiveMessage(status),
                        ) ||
                        _cancelledAgentIds.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: LayoutBuilder(
                          builder: (context, constraints) => SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_unreadThreadReplyCount > 0)
                                      _UnreadRepliesButton(
                                        count: _unreadThreadReplyCount,
                                        onPressed: _unreadThreadSources.isEmpty
                                            ? null
                                            : () => widget.onOpenThread(
                                                _unreadThreadSources.first,
                                              ),
                                      ),
                                    for (
                                      var index = 0;
                                      index < widget.typingStatuses.length;
                                      index++
                                    )
                                      if (!_showsMainLiveMessage(
                                        widget.typingStatuses[index],
                                      ))
                                        if (widget.typingStatuses[index].agentId
                                            case final agentId?)
                                          _HoldToCancelAgentTask(
                                            key: ValueKey(
                                              'cancel-agent-$agentId-${widget.typingStatuses[index].parentId ?? ''}',
                                            ),
                                            label: widget.typingLabels[index],
                                            onTap: _typingThreadOpener(
                                              widget.typingStatuses[index],
                                            ),
                                            onCancel: () =>
                                                _cancelAgentTask(agentId),
                                          )
                                        else
                                          TextButton(
                                            onPressed: _typingThreadOpener(
                                              widget.typingStatuses[index],
                                            ),
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              minimumSize: const Size(0, 28),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            child: Text(
                                              widget.typingLabels[index],
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                    if (_cancelledAgentIds.isNotEmpty)
                                      const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        child: Text('Cancelled', maxLines: 1),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                      voiceDurationLabel: widget.voiceDurationLabel,
                      onCancelVoiceRecording: widget.onCancelVoiceRecording,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnreadRepliesButton extends StatefulWidget {
  const _UnreadRepliesButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback? onPressed;

  @override
  State<_UnreadRepliesButton> createState() => _UnreadRepliesButtonState();
}

class _UnreadRepliesButtonState extends State<_UnreadRepliesButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: TextButton.icon(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: widget.onPressed,
      icon: const Icon(Icons.forum_outlined, size: 16),
      label: Text(
        _hovered
            ? 'Read first'
            : '${widget.count} new ${widget.count == 1 ? 'reply' : 'replies'}',
      ),
    ),
  );
}

class _HoldToCancelAgentTask extends StatefulWidget {
  const _HoldToCancelAgentTask({
    super.key,
    required this.label,
    this.onTap,
    required this.onCancel,
  });

  final String label;
  final VoidCallback? onTap;
  final Future<void> Function() onCancel;

  @override
  State<_HoldToCancelAgentTask> createState() => _HoldToCancelAgentTaskState();
}

class _HoldToCancelAgentTaskState extends State<_HoldToCancelAgentTask> {
  Timer? _holdTimer;
  int? _secondsRemaining;
  bool _cancelling = false;

  void _startHold() {
    if (_cancelling || _holdTimer != null) return;
    _holdTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final seconds = 5 - timer.tick;
      if (seconds == 0) {
        timer.cancel();
        _holdTimer = null;
        setState(() {
          _secondsRemaining = null;
          _cancelling = true;
        });
        unawaited(widget.onCancel());
      } else {
        setState(() => _secondsRemaining = seconds);
      }
    });
  }

  void _stopHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (_secondsRemaining != null && mounted) {
      setState(() => _secondsRemaining = null);
    }
  }

  void _handleTap() {
    if (!_cancelling) widget.onTap?.call();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _startHold(),
    onTapUp: (_) => _stopHold(),
    onTapCancel: _stopHold,
    onTap: _handleTap,
    child: Semantics(
      button: true,
      label: widget.onTap == null
          ? 'Hold for five seconds to cancel ${widget.label}'
          : 'Tap to open the active thread, or hold for five seconds to cancel ${widget.label}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          _cancelling
              ? 'Cancelling...'
              : _secondsRemaining == null
              ? widget.label
              : 'Cancel in $_secondsRemaining...',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
        ),
      ),
    ),
  );
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

class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.label});

  final String label;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    child: ExcludeSemantics(
      child: SizedBox(
        width: 18,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Text(
            '.' * (_controller.value * 4).floor(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    ),
  );
}

class _WorkspaceLiveMessageRow extends StatelessWidget {
  const _WorkspaceLiveMessageRow({
    required this.status,
    required this.authorName,
  });

  final WorkspaceTyping status;
  final String authorName;

  @override
  Widget build(BuildContext context) {
    final isAgent = status.agentId != null;
    final text = status.stage?.trim();
    final body = text == null || text.isEmpty
        ? (isAgent ? 'Working' : 'Typing')
        : text;
    return LayoutBuilder(
      builder: (context, constraints) {
        final minimumBubbleWidth = MediaQuery.sizeOf(context).width < 720
            ? 144.0
            : 300.0;
        final maximumBubbleWidth = math
            .max(minimumBubbleWidth, math.min(constraints.maxWidth, 820))
            .toDouble();
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: maximumBubbleWidth,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isAgent
                    ? const Color(0xff12332d)
                    : Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    child: _WorkspaceFrogAvatar(
                      identity: status.senderPubkey,
                      label: authorName,
                      radius: 16,
                      bot: isAgent,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 44, top: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                authorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            _TypingDots(label: '$authorName is active'),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(body),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WorkspaceMessageRow extends StatefulWidget {
  const _WorkspaceMessageRow({
    required this.message,
    required this.authorName,
    required this.groupedWithPrevious,
    required this.isLocalSender,
    required this.fipsConnected,
    required this.onThread,
    required this.onReact,
    required this.onOpenMessageReference,
    this.onOpenMention,
    this.isLocallyPinned = false,
    this.onToggleLocalPin,
    this.onToggleSharedPin,
    required this.threadReplyCount,
    required this.threadUnreadCount,
    required this.onOpenAttachment,
    this.threadActivityLabel,
    this.threadTopic,
    this.showThreadAction = true,
    this.isThreadSource = false,
    this.searchQuery = '',
    this.showDate = false,
    this.dateFormat = WorkspaceDateFormat.uk,
  });
  final WorkspaceMessage message;
  final String authorName;
  final bool groupedWithPrevious;
  final bool isLocalSender;
  final bool fipsConnected;
  final VoidCallback onThread;
  final ValueChanged<String> onReact;
  final ValueChanged<String> onOpenMessageReference;
  final ValueChanged<WorkspaceMention>? onOpenMention;
  final bool isLocallyPinned;
  final VoidCallback? onToggleLocalPin;
  final VoidCallback? onToggleSharedPin;
  final int threadReplyCount;
  final int threadUnreadCount;
  final Future<void> Function(BridgeAudioReference attachment) onOpenAttachment;
  final String? threadActivityLabel;
  final String? threadTopic;
  final bool showThreadAction;
  final bool isThreadSource;
  final String searchQuery;
  final bool showDate;
  final WorkspaceDateFormat dateFormat;
  @override
  State<_WorkspaceMessageRow> createState() => _WorkspaceMessageRowState();
}

class _WorkspaceMessageRowState extends State<_WorkspaceMessageRow>
    with SingleTickerProviderStateMixin {
  static const _reactions = ['👍', '❤️', '👀'];
  bool _hovered = false;
  late final AnimationController _outlineController;
  Timer? _timestampTimer;

  bool get _hasThreadWork => widget.threadActivityLabel != null;
  bool get _hasNewThreadReply => widget.threadUnreadCount > 0;

  void _updateOutlineAnimation() {
    if (_hasThreadWork || _hasNewThreadReply) {
      _outlineController.repeat();
    } else {
      _outlineController
        ..stop()
        ..value = 0;
    }
  }

  void _scheduleTimestampRefresh() {
    _timestampTimer?.cancel();
    if (!widget.showDate) return;

    final now = DateTime.now();
    final messageTime = DateTime.fromMillisecondsSinceEpoch(
      widget.message.createdAt * 1000,
    ).toLocal();
    final justNowEnds = messageTime.add(const Duration(minutes: 1));
    final isToday =
        messageTime.year == now.year &&
        messageTime.month == now.month &&
        messageTime.day == now.day;
    if (!justNowEnds.isAfter(now) && !isToday) return;
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final refreshAt =
        justNowEnds.isAfter(now) && justNowEnds.isBefore(nextMidnight)
        ? justNowEnds
        : nextMidnight;
    _timestampTimer = Timer(refreshAt.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _scheduleTimestampRefresh();
    });
  }

  @override
  void initState() {
    super.initState();
    _outlineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _updateOutlineAnimation();
    _scheduleTimestampRefresh();
  }

  @override
  void didUpdateWidget(covariant _WorkspaceMessageRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadUnreadCount != widget.threadUnreadCount ||
        oldWidget.threadActivityLabel != widget.threadActivityLabel) {
      _updateOutlineAnimation();
    }
    if (oldWidget.showDate != widget.showDate ||
        oldWidget.message.createdAt != widget.message.createdAt) {
      _scheduleTimestampRefresh();
    }
  }

  @override
  void dispose() {
    _timestampTimer?.cancel();
    _outlineController.dispose();
    super.dispose();
  }

  IconData? _reactionIcon(String reaction) => switch (reaction) {
    '👍' => Icons.thumb_up_alt_outlined,
    '❤️' => Icons.favorite_border,
    '👀' => Icons.visibility_outlined,
    _ => null,
  };

  String _reactionLabel(String reaction) => switch (reaction) {
    '👍' => 'Like',
    '❤️' => 'Love',
    '👀' => 'Seen',
    _ => reaction,
  };

  Color _reactionColor(BuildContext context, String reaction) {
    final colors = Theme.of(context).colorScheme;
    return switch (reaction) {
      '👍' => colors.primary,
      '❤️' => colors.error,
      '👀' => colors.tertiary,
      _ => colors.onSurfaceVariant,
    };
  }

  Widget _reactionVisual(
    BuildContext context,
    String reaction, {
    double size = 18,
  }) => switch (_reactionIcon(reaction)) {
    final icon? => Icon(
      icon,
      size: size,
      color: _reactionColor(context, reaction),
    ),
    null => Text(reaction, style: TextStyle(fontSize: size)),
  };

  List<PopupMenuEntry<String>> _reactionMenuItems(BuildContext context) => [
    for (final reaction in _reactions)
      PopupMenuItem(
        value: reaction,
        child: Row(
          children: [
            _reactionVisual(context, reaction),
            const SizedBox(width: 12),
            Text(_reactionLabel(reaction)),
          ],
        ),
      ),
  ];

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
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: const Text('Copy message reference'),
              onTap: () => Navigator.pop(context, 'copy-reference'),
            ),
            if (widget.showThreadAction)
              ListTile(
                leading: const Icon(Icons.reply_outlined),
                title: const Text('Reply in thread'),
                onTap: () => Navigator.pop(context, 'thread'),
              ),
            if (widget.onToggleSharedPin != null)
              ListTile(
                leading: Icon(
                  widget.message.pinned
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                ),
                title: Text(
                  widget.message.pinned
                      ? 'Unpin for everyone'
                      : 'Pin for everyone',
                ),
                onTap: () => Navigator.pop(context, 'shared-pin'),
              ),
            if (widget.onToggleLocalPin != null)
              ListTile(
                leading: Icon(
                  widget.isLocallyPinned
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                ),
                title: Text(
                  widget.isLocallyPinned ? 'Unpin for me' : 'Pin for me',
                ),
                onTap: () => Navigator.pop(context, 'local-pin'),
              ),
            const Divider(height: 1),
            for (final emoji in _reactions)
              ListTile(
                leading: _reactionVisual(context, emoji, size: 22),
                title: Text('React with ${_reactionLabel(emoji)}'),
                onTap: () => Navigator.pop(context, 'reaction:$emoji'),
              ),
          ],
        ),
      ),
    );
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: _messageText));
    } else if (action == 'copy-reference') {
      await Clipboard.setData(
        ClipboardData(text: '[[message:${widget.message.id}]]'),
      );
    } else if (action == 'thread') {
      widget.onThread();
    } else if (action == 'shared-pin') {
      widget.onToggleSharedPin?.call();
    } else if (action == 'local-pin') {
      widget.onToggleLocalPin?.call();
    } else if (action?.startsWith('reaction:') == true) {
      widget.onReact(action!.substring('reaction:'.length));
    }
  }

  String get _messageText => isWorkspaceAgentSender(widget.message.senderPubkey)
      ? trimTrailingLineWhitespace(
          workspaceDisplayMessageText(widget.message.body),
        )
      : widget.message.body;

  Future<void> _showWorkHistory(
    BuildContext context,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      var cumulativeSeconds = 0;
      final items = <_WorkHistoryItem>[];
      for (var index = 0; index < widget.message.workHistory.length; index++) {
        final value = widget.message.workHistory[index];
        cumulativeSeconds += _WorkHistoryItem.durationSeconds(value);
        items.add(
          _WorkHistoryItem(
            index: index + 1,
            value: value,
            cumulativeSeconds: cumulativeSeconds,
          ),
        );
      }
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('Work history'),
              trailing: Text(
                'Total ${_WorkHistoryItem.formatDuration(cumulativeSeconds)}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            ...items,
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final isAgent = isWorkspaceAgentSender(widget.message.senderPubkey);
    final avatar = Semantics(
      label: isAgent ? '${widget.authorName}, agent' : widget.authorName,
      child: _WorkspaceFrogAvatar(
        identity: widget.message.senderPubkey,
        label: widget.authorName,
        radius: 16,
        bot: isAgent,
      ),
    );
    final oneLineBodyWidth = math
        .max(0, math.min(MediaQuery.sizeOf(context).width, 820) - 64)
        .toDouble();
    final bodyOverflows =
        (TextPainter(
          text: TextSpan(
            text: _messageText,
            style: DefaultTextStyle.of(context).style,
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: oneLineBodyWidth)).computeLineMetrics().length >
        1;
    final messageContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.groupedWithPrevious)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  if (widget.threadTopic case final topic?) ...[
                    Flexible(child: _threadTopicTag(context, topic)),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
        if (!widget.groupedWithPrevious)
          Padding(
            padding: const EdgeInsets.only(left: 44, top: 4),
            child: Row(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    widget.authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: widget.fipsConnected
                          ? const Color(0xff35d6a0)
                          : null,
                    ),
                  ),
                ),
                if (isAgent && widget.message.workHistory.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _showWorkButton(context),
                ],
                const SizedBox(width: 8),
                if (widget.threadTopic case final topic?) ...[
                  Flexible(
                    fit: FlexFit.loose,
                    child: _threadTopicTag(context, topic),
                  ),
                ],
              ],
            ),
          ),
        if (!widget.groupedWithPrevious)
          SizedBox(height: bodyOverflows ? 14 : 3),
        if (widget.message.pinned || widget.isLocallyPinned)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.message.pinned) const Icon(Icons.push_pin, size: 14),
                if (widget.message.pinned && widget.isLocallyPinned)
                  const SizedBox(width: 4),
                if (widget.isLocallyPinned)
                  const Icon(Icons.bookmark, size: 14),
                const SizedBox(width: 5),
                Text(
                  widget.message.pinned ? 'Pinned' : 'Pinned for you',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        if (_messageText.isNotEmpty)
          Padding(
            padding: !widget.groupedWithPrevious && !bodyOverflows
                ? const EdgeInsets.only(left: 44)
                : EdgeInsets.zero,
            child: _WorkspaceMessageBody(
              text: _messageText,
              mentions: widget.message.mentions,
              onOpenMessageReference: widget.onOpenMessageReference,
              onOpenMention: widget.onOpenMention,
              searchQuery: widget.searchQuery,
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
                  avatar: _reactionVisual(context, emoji, size: 16),
                  backgroundColor: _reactionColor(
                    context,
                    emoji,
                  ).withValues(alpha: 0.12),
                  side: BorderSide(
                    color: _reactionColor(
                      context,
                      emoji,
                    ).withValues(alpha: 0.38),
                  ),
                  label: Text(
                    '${_reactionLabel(emoji)} ${widget.message.reactions.where((reaction) => reaction.emoji == emoji).length}',
                  ),
                  onPressed: () => widget.onReact(emoji),
                ),
            ],
          ),
        for (final attachment in widget.message.attachments)
          TextButton.icon(
            onPressed: () => unawaited(widget.onOpenAttachment(attachment)),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: Text(attachment.name ?? 'Attachment'),
          ),
      ],
    );
    final row = Stack(
      children: [
        if (!widget.groupedWithPrevious)
          Positioned(top: 0, left: 0, child: avatar),
        messageContent,
        Positioned(
          top: 0,
          right: 0,
          child: _timestamp(context, grouped: widget.groupedWithPrevious),
        ),
      ],
    );
    final replyControls =
        widget.threadReplyCount > 0 || widget.threadActivityLabel != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.threadReplyCount > 0)
                TextButton.icon(
                  onPressed: widget.onThread,
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size(48, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.forum_outlined, size: 16),
                  label: Text(
                    '${widget.threadReplyCount} ${widget.threadReplyCount == 1 ? 'reply' : 'replies'}${widget.threadUnreadCount > 0 ? ' · ${widget.threadUnreadCount} new' : ''}',
                    style: widget.threadUnreadCount == 0
                        ? const TextStyle(color: Colors.white)
                        : null,
                  ),
                ),
              if (widget.threadReplyCount > 0 &&
                  widget.threadActivityLabel != null)
                const SizedBox(width: 4),
              if (widget.threadActivityLabel case final label?)
                Flexible(
                  child: TextButton.icon(
                    onPressed: widget.onThread,
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      minimumSize: const Size(48, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    icon: _ThreadWorkingDots(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    label: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          )
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final minimumBubbleWidth = MediaQuery.sizeOf(context).width < 720
            ? 144.0
            : 300.0;
        final availableBubbleWidth = math
            .min(constraints.maxWidth, 820)
            .toDouble();
        final maxBubbleWidth = math
            .max(minimumBubbleWidth, availableBubbleWidth)
            .toDouble();
        final leadingWidth = 0.0;
        final maxContentWidth = math
            .max(0, maxBubbleWidth - leadingWidth - 20)
            .toDouble();
        final timestampWidth = (TextPainter(
          text: TextSpan(
            text: _timestampLabel(),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontSize: 10),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout()).width;
        final bodyWidth = (TextPainter(
          text: TextSpan(
            text: _messageText,
            style: DefaultTextStyle.of(context).style,
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: maxContentWidth)).width;
        final authorWidth = !widget.groupedWithPrevious
            ? (TextPainter(
                text: TextSpan(
                  text: widget.authorName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(maxWidth: maxContentWidth)).width
            : 0.0;
        final threadTopicWidth = widget.threadTopic == null
            ? 0.0
            : (TextPainter(
                    text: TextSpan(
                      text: widget.threadTopic,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                  )..layout(maxWidth: maxContentWidth)).width +
                  14;
        final bodyIndent = !widget.groupedWithPrevious && !bodyOverflows
            ? 44.0
            : 0.0;
        final headerWidth = widget.groupedWithPrevious
            ? threadTopicWidth
            : bodyIndent +
                  authorWidth +
                  (isAgent && widget.message.workHistory.isNotEmpty ? 92 : 0) +
                  threadTopicWidth;
        final contentWidth = math
            .max(
              math.max(bodyWidth + bodyIndent, headerWidth) +
                  timestampWidth +
                  8,
              48.0,
            )
            .toDouble();
        final minBubbleWidth = minimumBubbleWidth;
        final bubbleWidth = math
            .min(
              maxBubbleWidth,
              math.max(minBubbleWidth, leadingWidth + contentWidth + 20),
            )
            .toDouble();
        final bubble = SizedBox(
          width: bubbleWidth,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onLongPress: () => unawaited(_showMessageActions(context)),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedBuilder(
                    animation: _outlineController,
                    builder: (context, child) {
                      final threadIndicator =
                          widget.isThreadSource || _hasNewThreadReply;
                      final primary = Theme.of(context).colorScheme.primary;
                      final bubble = Container(
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
                        child: child,
                      );
                      if (threadIndicator) {
                        return CustomPaint(
                          foregroundPainter: _ThreadOutlinePainter(
                            color: primary,
                            phase: _outlineController.value,
                          ),
                          child: bubble,
                        );
                      }
                      return bubble;
                    },
                    child: row,
                  ),
                  if (_hovered)
                    Positioned(
                      top: -4,
                      right: 0,
                      child: Material(
                        elevation: 3,
                        borderRadius: BorderRadius.circular(10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Copy text',
                              icon: const Icon(Icons.copy_outlined, size: 18),
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: _messageText),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy message reference',
                              icon: const Icon(Icons.link_outlined, size: 18),
                              onPressed: () => Clipboard.setData(
                                ClipboardData(
                                  text: '[[message:${widget.message.id}]]',
                                ),
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
                            if (widget.onToggleSharedPin != null)
                              IconButton(
                                tooltip: widget.message.pinned
                                    ? 'Unpin for everyone'
                                    : 'Pin for everyone',
                                icon: Icon(
                                  widget.message.pinned
                                      ? Icons.push_pin
                                      : Icons.push_pin_outlined,
                                  size: 18,
                                ),
                                onPressed: widget.onToggleSharedPin,
                              ),
                            if (widget.onToggleLocalPin != null)
                              IconButton(
                                tooltip: widget.isLocallyPinned
                                    ? 'Unpin for me'
                                    : 'Pin for me',
                                icon: Icon(
                                  widget.isLocallyPinned
                                      ? Icons.bookmark
                                      : Icons.bookmark_border,
                                  size: 18,
                                ),
                                onPressed: widget.onToggleLocalPin,
                              ),
                            PopupMenuButton<String>(
                              tooltip: 'React',
                              padding: EdgeInsets.zero,
                              splashRadius: 18,
                              icon: const Icon(
                                Icons.add_reaction_outlined,
                                size: 18,
                              ),
                              onSelected: widget.onReact,
                              itemBuilder: _reactionMenuItems,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
        return Align(
          alignment: Alignment.centerLeft,
          heightFactor: 1,
          child: SizedBox(
            width: bubbleWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                bubble,
                if (replyControls != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 4),
                    child: replyControls,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _timestamp(BuildContext context, {bool grouped = false}) {
    return Text(
      _timestampLabel(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontSize: 10,
        color: Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: grouped ? 0.42 : 0.52),
      ),
    );
  }

  String _timestampLabel() {
    final date = DateTime.fromMillisecondsSinceEpoch(
      widget.message.createdAt * 1000,
    ).toLocal();
    final now = DateTime.now();
    if (widget.showDate &&
        !date.isAfter(now) &&
        now.difference(date) < const Duration(minutes: 1)) {
      return 'Just now';
    }
    final time =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final day = widget.dateFormat == WorkspaceDateFormat.uk
        ? '${date.day}/${date.month}/${date.year}'
        : '${date.month}/${date.day}/${date.year}';
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    return widget.showDate && !isToday ? '$day $time' : time;
  }

  Widget _showWorkButton(BuildContext context) => TextButton.icon(
    onPressed: () => _showWorkHistory(context),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      minimumSize: const Size(0, 24),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: const Icon(Icons.list_alt_outlined, size: 14),
    label: const Text('Show work'),
  );

  Widget _threadTopicTag(BuildContext context, String topic) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Text(
        topic,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _ThreadOutlinePainter extends CustomPainter {
  const _ThreadOutlinePainter({required this.color, required this.phase});

  final Color color;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final opacity = 0.3 + (math.sin(phase * math.pi * 2) + 1) * 0.25;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(11)),
      Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ThreadOutlinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.phase != phase;
}

class _ThreadWorkingDots extends StatefulWidget {
  const _ThreadWorkingDots({required this.color});

  final Color color;

  @override
  State<_ThreadWorkingDots> createState() => _ThreadWorkingDotsState();
}

class _ThreadWorkingDotsState extends State<_ThreadWorkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        final phase = (_controller.value - (index * 0.18)) % 1;
        final opacity = MediaQuery.disableAnimationsOf(context)
            ? 1.0
            : 0.35 + (0.65 * (1 - (phase - 0.5).abs() * 2));
        return Padding(
          padding: EdgeInsets.only(right: index == 2 ? 0 : 3),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: opacity),
              shape: BoxShape.circle,
            ),
            child: const SizedBox.square(dimension: 5),
          ),
        );
      }),
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
    (Color(0xff7dd3fc), Color(0xff0c4a6e)), // Sky
    (Color(0xfffcd34d), Color(0xff78350f)), // Amber
    (Color(0xfffda4af), Color(0xff881337)), // Rose
    (Color(0xff86efac), Color(0xff14532d)), // Emerald
    (Color(0xffc4b5fd), Color(0xff4c1d95)), // Violet
    (Color(0xfff0abfc), Color(0xff86198f)), // Fuchsia
    (Color(0xff5eead4), Color(0xff134e4a)), // Teal
    (Color(0xfffdba74), Color(0xff7c2d12)), // Orange
    (Color(0xffbef264), Color(0xff365314)), // Lime
    (Color(0xffa5b4fc), Color(0xff312e81)), // Indigo
    (Color(0xfffde68a), Color(0xff713f12)), // Yellow
    (Color(0xfffca5a5), Color(0xff7f1d1d)), // Red
  ];

  @override
  Widget build(BuildContext context) {
    final circleRadius = radius - 2;
    final colors =
        _colors[workspaceAvatarColorIndex(identity, label, _colors.length)];
    return CircleAvatar(
      radius: circleRadius,
      backgroundColor: colors.$1,
      child: bot
          ? CustomPaint(
              size: Size.square(circleRadius * 1.75),
              painter: _WorkspaceBotAvatarPainter(colors.$2),
            )
          : ColorFiltered(
              colorFilter: ColorFilter.mode(colors.$2, BlendMode.srcIn),
              child: Image.asset(
                'assets/branding/ribbet-mark.png',
                width: circleRadius * 2.2,
                height: circleRadius * 2.2,
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

class _WorkHistoryItem extends StatelessWidget {
  const _WorkHistoryItem({
    required this.index,
    required this.value,
    required this.cumulativeSeconds,
  });

  final int index;
  final String value;
  final int cumulativeSeconds;

  static int durationSeconds(String value) {
    final duration = value.split('\t').first;
    var seconds = 0;
    for (final match in RegExp(r'(\d+)([hms])').allMatches(duration)) {
      final amount = int.tryParse(match.group(1)!) ?? 0;
      seconds +=
          amount *
          switch (match.group(2)) {
            'h' => 3600,
            'm' => 60,
            _ => 1,
          };
    }
    return seconds;
  }

  static String formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;
    if (hours > 0) return '${hours}h ${minutes}m ${remainingSeconds}s';
    if (minutes > 0) return '${minutes}m ${remainingSeconds}s';
    return '${remainingSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final parts = value.split('\t');
    final hasDuration = parts.length == 2;
    final duration = hasDuration ? parts.first : null;
    final text = hasDuration ? parts.last : value;
    return ListTile(
      leading: Text('$index'),
      title: Text(text),
      trailing: duration == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  duration,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Elapsed ${formatDuration(cumulativeSeconds)}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w400),
                ),
              ],
            ),
    );
  }
}

class _WorkspaceMessageBody extends StatefulWidget {
  const _WorkspaceMessageBody({
    required this.text,
    required this.mentions,
    required this.onOpenMessageReference,
    this.onOpenMention,
    this.searchQuery = '',
  });
  final String text;
  final List<WorkspaceMention> mentions;
  final ValueChanged<String> onOpenMessageReference;
  final ValueChanged<WorkspaceMention>? onOpenMention;
  final String searchQuery;

  @override
  State<_WorkspaceMessageBody> createState() => _WorkspaceMessageBodyState();
}

class _WorkspaceMessageBodyState extends State<_WorkspaceMessageBody> {
  static const _previewLines = 10;
  static const _expandThresholdLines = 15;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Code blocks render outside the plain-text layout measured below, so the
      // raw Markdown line count can claim a fully visible message is truncated.
      final hasCodeBlock = RegExp(r'```[\s\S]*?```').hasMatch(widget.text);
      final style = DefaultTextStyle.of(context).style;
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: _expandThresholdLines,
      )..layout(maxWidth: constraints.maxWidth);
      final truncated = !hasCodeBlock && painter.didExceedMaxLines;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WorkspaceMessageText(
            text: widget.text,
            mentions: widget.mentions,
            onOpenMessageReference: widget.onOpenMessageReference,
            onOpenMention: widget.onOpenMention,
            searchQuery: widget.searchQuery,
            maxLines: truncated && !_expanded ? _previewLines : null,
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
    required this.onOpenMessageReference,
    this.onOpenMention,
    this.maxLines,
    this.searchQuery = '',
  });
  final String text;
  final List<WorkspaceMention> mentions;
  final ValueChanged<String> onOpenMessageReference;
  final ValueChanged<WorkspaceMention>? onOpenMention;
  final int? maxLines;
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    final blocks = RegExp(r'```[^\r\n]*\r?\n([\s\S]*?)```').allMatches(text);
    if (blocks.isEmpty) return _buildPlainText(context, text, maxLines);

    final children = <Widget>[];
    var offset = 0;
    for (final block in blocks) {
      final before = text.substring(offset, block.start).trim();
      if (before.isNotEmpty) {
        children.add(_buildPlainText(context, before, null));
        children.add(const SizedBox(height: 8));
      }
      children.add(_WorkspaceCodeBlock(code: block.group(1)!.trimRight()));
      offset = block.end;
    }
    final after = text.substring(offset).trim();
    if (after.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(_buildPlainText(context, after, null));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildPlainText(BuildContext context, String value, int? maxLines) {
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
      r'\[\[message:([^\]\r\n]+)\]\]',
      r'(?<!\w)(?:[~\w.-]+/)+[~\w.-]+',
      if (labels.isNotEmpty)
        '(?<!\\w)@(?:${labels.map(RegExp.escape).join('|')})(?![\\w-])',
    ];
    final matches = RegExp(patterns.join('|')).allMatches(value);
    if (matches.isEmpty) {
      final span = TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: _highlightedTextSpans(context, value),
      );
      return maxLines == null
          ? SelectableText.rich(span)
          : RichText(
              text: span,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            );
    }
    final style = DefaultTextStyle.of(context).style;
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in matches) {
      if (match.start > offset) {
        spans.addAll(
          _highlightedTextSpans(context, value.substring(offset, match.start)),
        );
      }
      final mention = match.group(1);
      final token = match.group(0)!;
      if (token.startsWith('[[message:')) {
        final messageId = token
            .substring('[[message:'.length, token.length - 2)
            .trim();
        if (messageId.isEmpty) {
          spans.add(TextSpan(text: token));
          offset = match.end;
          continue;
        }
        spans.add(
          TextSpan(
            text: 'message reference',
            style: style.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => onOpenMessageReference(messageId),
          ),
        );
        offset = match.end;
        continue;
      }
      final recognizedMention = mention == null
          ? (token.startsWith('@')
                ? recognizedMentions[token.substring(1)]
                : null)
          : _linkedMention(mention);
      if (recognizedMention != null) {
        spans.add(
          TextSpan(
            text: '@${recognizedMention.label}',
            style: style.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = onOpenMention == null
                  ? null
                  : () => onOpenMention!(recognizedMention),
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
    if (offset < value.length) {
      spans.addAll(_highlightedTextSpans(context, value.substring(offset)));
    }
    final span = TextSpan(style: style, children: spans);
    return maxLines == null
        ? SelectableText.rich(span)
        : RichText(
            text: span,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          );
  }

  WorkspaceMention? _linkedMention(String value) {
    final match = RegExp(
      r'^@\[([^\]\r\n]+)\]\((member|agent):([^\)\s]+)\)$',
    ).firstMatch(value);
    if (match == null) return null;
    return WorkspaceMention(
      kind: match.group(2)!,
      id: match.group(3)!,
      label: match.group(1)!,
    );
  }

  List<InlineSpan> _highlightedTextSpans(BuildContext context, String value) {
    final query = searchQuery.trim();
    if (query.isEmpty) return [TextSpan(text: value)];
    final matches = RegExp(
      RegExp.escape(query),
      caseSensitive: false,
    ).allMatches(value).toList();
    if (matches.isEmpty) return [TextSpan(text: value)];
    final highlight = Theme.of(
      context,
    ).colorScheme.primary.withValues(alpha: 0.24);
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in matches) {
      if (match.start > offset) {
        spans.add(TextSpan(text: value.substring(offset, match.start)));
      }
      spans.add(
        TextSpan(
          text: value.substring(match.start, match.end),
          style: TextStyle(backgroundColor: highlight),
        ),
      );
      offset = match.end;
    }
    if (offset < value.length)
      spans.add(TextSpan(text: value.substring(offset)));
    return spans;
  }
}

class _WorkspaceCodeBlock extends StatefulWidget {
  const _WorkspaceCodeBlock({required this.code});
  final String code;

  @override
  State<_WorkspaceCodeBlock> createState() => _WorkspaceCodeBlockState();
}

class _WorkspaceCodeBlockState extends State<_WorkspaceCodeBlock> {
  var _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xff102b25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 44, 10),
            child: SelectableText(
              widget.code,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xffd5ffec),
                fontFamily: 'monospace',
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              tooltip: _copied ? 'Copied' : 'Copy code',
              onPressed: _copy,
              visualDensity: VisualDensity.compact,
              icon: Icon(_copied ? Icons.check : Icons.copy_outlined, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceMentionDetails extends StatelessWidget {
  const _WorkspaceMentionDetails({
    required this.mention,
    required this.workspace,
    required this.ownPubkey,
    required this.displayName,
    required this.memberNames,
    required this.memberAliases,
    this.onOpenLastResponse,
    this.onOpenDirect,
  });

  final WorkspaceMention mention;
  final WorkspaceState workspace;
  final String ownPubkey;
  final String displayName;
  final Map<String, String> memberNames;
  final Map<String, String> memberAliases;
  final VoidCallback? onOpenLastResponse;
  final VoidCallback? onOpenDirect;

  @override
  Widget build(BuildContext context) {
    final agent = mention.kind == 'agent'
        ? workspace.agents.where((agent) => agent.id == mention.id).firstOrNull
        : null;
    final title = agent?.name ?? _memberLabel();
    final subtitle = agent == null
        ? (workspace.memberAdmins.contains(mention.id)
              ? 'Workspace admin'
              : 'Member')
        : agent.role;
    final conversationLabels = agent == null
        ? _sharedChannels()
        : _agentConversations(agent);
    final lastResponse = agent == null
        ? null
        : workspace.messages.values
              .expand((messages) => messages)
              .where((message) => message.senderPubkey == 'agent:${agent.id}')
              .fold<WorkspaceMessage?>(
                null,
                (latest, message) =>
                    latest == null || message.createdAt > latest.createdAt
                    ? message
                    : latest,
              );

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _WorkspaceFrogAvatar(
                identity: agent == null ? mention.id : 'agent:${agent.id}',
                label: title,
                radius: 24,
                bot: agent != null,
              ),
              title: Text(title, style: Theme.of(context).textTheme.titleLarge),
              subtitle: Text(subtitle),
            ),
            const SizedBox(height: 12),
            if (agent != null)
              ..._agentDetails(
                context,
                agent,
                conversationLabels,
                lastResponse,
              ),
            if (agent == null) ..._memberDetails(context, conversationLabels),
          ],
        ),
      ),
    );
  }

  List<Widget> _agentDetails(
    BuildContext context,
    WorkspaceAgent agent,
    List<String> conversations,
    WorkspaceMessage? lastResponse,
  ) => [
    if (agent.openCodeModelName?.isNotEmpty == true)
      _detailRow(context, 'Model', agent.openCodeModelName!),
    if (agent.createdAt > 0)
      _detailRow(
        context,
        'Birthday',
        '${_dateLabel(agent.createdAt)} (${_ageLabel(agent.createdAt)})',
      ),
    if (agent.role.isNotEmpty) _detailRow(context, 'Description', agent.role),
    if (agent.inputTokens != null || agent.outputTokens != null)
      _detailRow(
        context,
        'Tokens',
        '${_count(agent.inputTokens)} in / ${_count(agent.outputTokens)} out',
      ),
    if (agent.workdir?.isNotEmpty == true)
      _detailRow(context, 'Working directory', agent.workdir!),
    if (agent.traits.isNotEmpty)
      _detailRow(context, 'Agent instructions', agent.traits),
    if (_visibleDirectories(agent).isNotEmpty)
      _detailRow(
        context,
        'Visible directories',
        _visibleDirectories(agent).join('\n'),
      ),
    _conversationSection(context, conversations),
    if (lastResponse != null && lastResponse.body.trim().isNotEmpty)
      _detailRow(
        context,
        'Last task',
        workspaceDisplayMessageText(lastResponse.body).trim(),
      ),
    if (lastResponse != null && lastResponse.workHistory.isNotEmpty) ...[
      const SizedBox(height: 16),
      Text('Latest steps', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      for (final step in lastResponse.workHistory.reversed.take(20))
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(step, style: Theme.of(context).textTheme.bodySmall),
        ),
    ],
    if (_agentBriefs(agent).isNotEmpty)
      _detailRow(context, 'Agent brief', _agentBriefs(agent).join('\n\n')),
    if (onOpenLastResponse != null)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: FilledButton.icon(
          onPressed: onOpenLastResponse,
          icon: const Icon(Icons.reply_outlined),
          label: const Text('Open last response'),
        ),
      ),
  ];

  List<Widget> _memberDetails(
    BuildContext context,
    List<String> conversations,
  ) => [
    if (workspace.memberJoinedAt[mention.id] case final joinedAt?
        when joinedAt > 0)
      _detailRow(context, 'Added to workspace', _dateLabel(joinedAt)),
    _detailRow(context, 'Identity', compactIdentifier(mention.id)),
    _conversationSection(context, conversations),
    if (onOpenDirect != null)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: FilledButton.icon(
          onPressed: onOpenDirect,
          icon: const Icon(Icons.chat_outlined),
          label: const Text('Open direct messages'),
        ),
      ),
  ];

  Widget _conversationSection(
    BuildContext context,
    List<String> conversations,
  ) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Conversations', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
          conversations.isEmpty
              ? 'No assigned conversations'
              : conversations.join('\n'),
        ),
      ],
    ),
  );

  Widget _detailRow(BuildContext context, String label, String value) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              child: Text(label, style: Theme.of(context).textTheme.labelLarge),
            ),
            Expanded(child: SelectableText(value)),
          ],
        ),
      );

  List<String> _sharedChannels() => workspace.channels
      .where(
        (channel) =>
            channel.members.any((member) => member.pubkey == ownPubkey) &&
            channel.members.any((member) => member.pubkey == mention.id),
      )
      .map((channel) => '# ${channel.name}')
      .toList(growable: false);

  List<String> _agentConversations(WorkspaceAgent agent) => workspace
      .conversationAgents
      .where((membership) => membership.agentId == agent.id)
      .map((membership) {
        if (membership.channelId case final channelId?) {
          return '# ${workspace.channelName(channelId) ?? channelId}';
        }
        return 'Direct message';
      })
      .toSet()
      .toList(growable: false);

  List<String> _visibleDirectories(WorkspaceAgent agent) => workspace
      .conversationAgents
      .where((membership) => membership.agentId == agent.id)
      .expand((membership) => membership.folderScope)
      .toSet()
      .toList(growable: false);

  List<String> _agentBriefs(WorkspaceAgent agent) => workspace
      .conversationPreprompts
      .where(
        (brief) => workspace.conversationAgents.any(
          (membership) =>
              membership.agentId == agent.id &&
              ((brief.channelId != null &&
                      brief.channelId == membership.channelId) ||
                  (brief.channelId == null &&
                      membership.channelId == null &&
                      {
                        brief.memberPubkey,
                        brief.peerPubkey,
                      }.contains(membership.memberPubkey) &&
                      {
                        brief.memberPubkey,
                        brief.peerPubkey,
                      }.contains(membership.peerPubkey))),
        ),
      )
      .map((brief) => brief.preprompt)
      .where((brief) => brief.isNotEmpty)
      .toSet()
      .toList(growable: false);

  String _memberLabel() => mention.id == ownPubkey
      ? (displayName.isEmpty ? 'You' : displayName)
      : memberAliases[mention.id] ?? memberNames[mention.id] ?? mention.label;

  String _dateLabel(int seconds) => DateTime.fromMillisecondsSinceEpoch(
    seconds * 1000,
    isUtc: true,
  ).toLocal().toString().split('.').first;

  String _ageLabel(int seconds) {
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
    );
    if (age.inDays > 0) return '${age.inDays}d old';
    if (age.inHours > 0) return '${age.inHours}h old';
    if (age.inMinutes > 0) return '${age.inMinutes}m old';
    return 'just now';
  }

  String _count(int? value) => value == null ? 'Unknown' : value.toString();
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

class _ThreadTopicActions extends StatefulWidget {
  const _ThreadTopicActions({
    required this.onRequestTopic,
    required this.onEditTopic,
    required this.child,
  });

  final VoidCallback onRequestTopic;
  final VoidCallback onEditTopic;
  final Widget child;

  @override
  State<_ThreadTopicActions> createState() => _ThreadTopicActionsState();
}

class _ThreadTopicActionsState extends State<_ThreadTopicActions> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: Row(
      children: [
        Flexible(fit: FlexFit.loose, child: widget.child),
        if (_hovered)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Request thread topic',
                onPressed: widget.onRequestTopic,
                icon: const Icon(Icons.auto_awesome_outlined),
              ),
              IconButton(
                tooltip: 'Edit thread topic',
                onPressed: widget.onEditTopic,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
      ],
    ),
  );
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
    required this.voiceDurationLabel,
    required this.onCancelVoiceRecording,
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
    required this.agentDirectory,
    required this.typingStatuses,
    required this.typingLabels,
    required this.onRequestTopic,
    required this.topicOverride,
    this.threadTopic,
    this.filesOpen = false,
    this.onShowFiles,
    required this.compactHeader,
    required this.fullWindow,
    required this.onToggleFullWindow,
    required this.dateFormat,
    this.replyTargetId,
    required this.onReplyTargetOpened,
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
  final String voiceDurationLabel;
  final VoidCallback onCancelVoiceRecording;
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
  final List<WorkspaceAgent> agentDirectory;
  final List<WorkspaceTyping> typingStatuses;
  final List<String> typingLabels;
  final VoidCallback onRequestTopic;
  final ValueNotifier<String?> topicOverride;
  final String? threadTopic;
  final bool filesOpen;
  final VoidCallback? onShowFiles;
  final bool compactHeader;
  final bool fullWindow;
  final VoidCallback onToggleFullWindow;
  final WorkspaceDateFormat dateFormat;
  final String? replyTargetId;
  final VoidCallback onReplyTargetOpened;

  String _memberLabel(String pubkey) {
    if (pubkey.startsWith('agent:')) {
      final id = pubkey.substring('agent:'.length);
      for (final agent in agentDirectory) {
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

  String _threadTitle(String? override) => override?.trim().isNotEmpty == true
      ? override!.trim()
      : threadTopic?.trim().isNotEmpty == true
      ? threadTopic!.trim()
      : message == null
      ? 'Thread'
      : workspaceThreadTopic(replies) ?? 'Thread';

  Future<void> _editThreadTopic(BuildContext context) async {
    final controller = TextEditingController(
      text: _threadTitle(topicOverride.value),
    );
    final topic = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thread topic'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 72,
          decoration: const InputDecoration(hintText: 'Short topic'),
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
    if (topic != null) topicOverride.value = topic.trim();
  }

  Widget _messageRow(
    WorkspaceMessage message, {
    required bool groupedWithPrevious,
  }) => _WorkspaceMessageRow(
    message: message,
    authorName: _memberLabel(message.senderPubkey),
    groupedWithPrevious: groupedWithPrevious,
    isLocalSender: isWorkspaceLocalSender(message.senderPubkey, localSenderIds),
    fipsConnected: false,
    onThread: () {},
    onReact: (emoji) => unawaited(onToggleReaction(message, emoji)),
    onOpenMessageReference: (_) {},
    threadReplyCount: 0,
    threadUnreadCount: 0,
    onOpenAttachment: onOpenAttachment,
    showThreadAction: false,
    showDate: true,
    dateFormat: dateFormat,
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
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
                'Workspace members appear in Members',
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
              if (!compactHeader) ...[
                Row(
                  children: [
                    Expanded(
                      child: _ThreadTopicActions(
                        onRequestTopic: onRequestTopic,
                        onEditTopic: () => unawaited(_editThreadTopic(context)),
                        child: ValueListenableBuilder<String?>(
                          valueListenable: topicOverride,
                          builder: (context, override, _) => Text(
                            _threadTitle(override),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    if (filesOpen)
                      TextButton.icon(
                        onPressed: onShowFiles,
                        icon: const Icon(Icons.folder_open_outlined, size: 18),
                        label: const Text('Files'),
                      ),
                    IconButton(
                      tooltip: fullWindow
                          ? 'Return to conversation'
                          : 'Open thread full-window',
                      onPressed: onToggleFullWindow,
                      icon: Icon(
                        fullWindow
                            ? Icons.close_fullscreen
                            : Icons.open_in_full,
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
              ],
              if (compactHeader) ...[
                Row(
                  children: [
                    Expanded(
                      child: ValueListenableBuilder<String?>(
                        valueListenable: topicOverride,
                        builder: (context, override, _) => Text(
                          _threadTitle(override),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Request thread topic',
                      onPressed: onRequestTopic,
                      icon: const Icon(Icons.auto_awesome_outlined),
                    ),
                    IconButton(
                      tooltip: 'Edit thread topic',
                      onPressed: () => unawaited(_editThreadTopic(context)),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 12),
              ],
              Expanded(
                child: _ThreadMessageList(
                  message: message!,
                  replies: replies,
                  messageBuilder: (message, groupedWithPrevious) => _messageRow(
                    message,
                    groupedWithPrevious: groupedWithPrevious,
                  ),
                  replyTargetId: replyTargetId,
                  onReplyTargetOpened: onReplyTargetOpened,
                ),
              ),
              for (final status in typingStatuses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _WorkspaceLiveMessageRow(
                    status: status,
                    authorName: _memberLabel(status.senderPubkey),
                  ),
                ),
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    const Spacer(),
                    Checkbox(
                      value: alsoSendToMain,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onChanged: (value) =>
                          onAlsoSendToMainChanged(value ?? false),
                    ),
                    GestureDetector(
                      onTap: () => onAlsoSendToMainChanged(!alsoSendToMain),
                      child: Text(
                        'main',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
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
                voiceDurationLabel: voiceDurationLabel,
                onCancelVoiceRecording: onCancelVoiceRecording,
              ),
            ],
          ),
  );
}

class _ThreadMessageList extends StatefulWidget {
  const _ThreadMessageList({
    required this.message,
    required this.replies,
    required this.messageBuilder,
    this.replyTargetId,
    required this.onReplyTargetOpened,
  });

  final WorkspaceMessage message;
  final List<WorkspaceMessage> replies;
  final Widget Function(WorkspaceMessage message, bool groupedWithPrevious)
  messageBuilder;
  final String? replyTargetId;
  final VoidCallback onReplyTargetOpened;

  @override
  State<_ThreadMessageList> createState() => _ThreadMessageListState();
}

class _ThreadMessageListState extends State<_ThreadMessageList> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _messageKeys = <String, GlobalKey>{};
  String? _lastReplyId;
  String _searchQuery = '';
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    _lastReplyId = _latestReplyId;
    if (widget.replyTargetId case final replyId?) _scrollToReply(replyId);
  }

  @override
  void didUpdateWidget(covariant _ThreadMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replyTargetId != widget.replyTargetId &&
        widget.replyTargetId != null) {
      _scrollToReply(widget.replyTargetId!);
    }
    if (_lastReplyId == _latestReplyId || widget.replyTargetId != null) return;
    _lastReplyId = _latestReplyId;
    _scrollToLatestReply();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _searchOpen = false;
      _searchQuery = '';
    });
  }

  String? get _latestReplyId =>
      widget.replies.isEmpty ? null : widget.replies.last.id;

  void _scrollToLatestReply() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    });
  }

  void _scrollToReply(String replyId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _messageKeys[replyId]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: 0.35,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
      widget.onReplyTargetOpened();
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final matchingReplies = query.isEmpty
        ? widget.replies
        : widget.replies
              .where(
                (message) => workspaceDisplayMessageText(
                  message.body,
                ).toLowerCase().contains(query),
              )
              .toList(growable: false);
    final sourceMatches =
        query.isEmpty ||
        workspaceDisplayMessageText(
          widget.message.body,
        ).toLowerCase().contains(query);
    return Column(
      children: [
        if (!_searchOpen)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Search this thread',
              onPressed: _openSearch,
              icon: const Icon(Icons.search),
            ),
          )
        else ...[
          TextField(
            controller: _searchController,
            focusNode: _searchFocus,
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Search this thread',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Close search',
                icon: const Icon(Icons.close),
                onPressed: _closeSearch,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: ListView(
            controller: _scrollController,
            reverse: true,
            padding: EdgeInsets.zero,
            children: [
              for (var index = matchingReplies.length - 1; index >= 0; index--)
                KeyedSubtree(
                  key: _messageKeys.putIfAbsent(
                    matchingReplies[index].id,
                    GlobalKey.new,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: widget.messageBuilder(
                      matchingReplies[index],
                      index > 0 &&
                          isWorkspaceMessageGroupedWithPrevious(
                            matchingReplies[index],
                            matchingReplies[index - 1],
                          ),
                    ),
                  ),
                ),
              if (query.isNotEmpty && matchingReplies.isEmpty && !sourceMatches)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Center(
                    child: Text('No matching messages in this thread.'),
                  ),
                ),
              if (sourceMatches) ...[
                const SizedBox(height: 8),
                Text(
                  '${matchingReplies.length} ${matchingReplies.length == 1 ? 'reply' : 'replies'}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 16),
                widget.messageBuilder(widget.message, false),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WorkspaceSidePanel extends StatelessWidget {
  const _WorkspaceSidePanel({
    required this.thread,
    required this.files,
    required this.showFiles,
  });

  final Widget? thread;
  final Widget? files;
  final bool showFiles;

  @override
  Widget build(BuildContext context) {
    final content = showFiles && files != null ? files! : thread!;
    return content;
  }
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
    required this.onClose,
    required this.hasThread,
    required this.onShowThread,
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
  final VoidCallback onClose;
  final bool hasThread;
  final VoidCallback onShowThread;
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
              child: Row(
                children: [
                  if (hasThread)
                    TextButton.icon(
                      onPressed: onShowThread,
                      icon: const Icon(Icons.forum_outlined, size: 18),
                      label: const Text('Thread'),
                    ),
                  if (hasThread) const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('Files'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                    ),
                  ),
                  if (result.directory.isNotEmpty || preview != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        preview?.path ?? result.directory,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ],
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
              tooltip: 'Close files',
              onPressed: onClose,
              icon: const Icon(Icons.close),
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
            width: double.infinity,
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
    this.voiceDurationLabel = '00:00',
    this.onCancelVoiceRecording,
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
  final String voiceDurationLabel;
  final VoidCallback? onCancelVoiceRecording;

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
                  readOnly: voiceRecording || voiceTranscribing,
                  decoration: InputDecoration(
                    hintText: voiceRecording
                        ? 'Recording $voiceDurationLabel'
                        : hintText,
                    filled: true,
                    fillColor:
                        Theme.of(
                          context,
                        ).extension<_WorkspacePalette>()?.composer ??
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    prefixIcon: IconButton(
                      tooltip: voiceRecording
                          ? 'Cancel recording'
                          : 'Attach file',
                      onPressed: voiceRecording
                          ? onCancelVoiceRecording
                          : () => unawaited(onAttach()),
                      icon: Icon(
                        voiceRecording ? Icons.close : Icons.attach_file,
                        color: voiceRecording
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (voiceTranscribing)
                          IconButton(
                            tooltip: 'Transcribing voice',
                            onPressed: null,
                            icon: const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        if (voiceRecording || canSend)
                          IconButton(
                            tooltip: voiceRecording
                                ? 'Send recording'
                                : desktop
                                ? 'Send message (Enter)'
                                : 'Send message',
                            onPressed: voiceRecording ? onVoicePressed : onSend,
                            icon: const Icon(Icons.send),
                          )
                        else if (onVoicePressed != null)
                          IconButton(
                            tooltip: 'Record voice to text',
                            onPressed: onVoicePressed,
                            icon: const Icon(Icons.mic_none_outlined),
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

class _PinnedMessagesPanel extends StatelessWidget {
  const _PinnedMessagesPanel({
    required this.title,
    required this.messages,
    required this.memberLabel,
    required this.isLocallyPinned,
    required this.onOpen,
  });

  final String title;
  final List<WorkspaceMessage> messages;
  final String Function(String pubkey) memberLabel;
  final bool Function(WorkspaceMessage message) isLocallyPinned;
  final ValueChanged<WorkspaceMessage> onOpen;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        for (final message in messages)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              message.pinned || !isLocallyPinned(message)
                  ? Icons.push_pin_outlined
                  : Icons.bookmark_outline,
              size: 18,
            ),
            title: Text(
              memberLabel(message.senderPubkey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              workspaceDisplayMessageText(message.body),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onOpen(message),
          ),
      ],
    ),
  );
}

class _AgentsPage extends StatefulWidget {
  const _AgentsPage({
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
      });
  Future<void> _createCustom() async {
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _AgentEditorDialog(
        onLoadOpenCodeModels: widget.onLoadOpenCodeModels,
        initialFolderChoices: widget.initialFolderChoices,
        onLoadFolders: widget.onLoadFolders,
        conversationScoped: false,
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
        initialChoices: widget.initialFolderChoices,
        onLoadFolders: widget.onLoadFolders,
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
        if (agent.traits.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Description', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(agent.traits),
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
    required this.conversationScoped,
  });
  final Future<List<_OpenCodeModelChoice>> Function() onLoadOpenCodeModels;
  final List<RepoChoice> initialFolderChoices;
  final Future<List<RepoChoice>> Function(String? path) onLoadFolders;
  final bool conversationScoped;
  @override
  State<_AgentEditorDialog> createState() => _AgentEditorDialogState();
}

class _AgentEditorDialogState extends State<_AgentEditorDialog> {
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _instructions = TextEditingController();
  final _modelFieldsKey = GlobalKey<_OpenCodeProfileFieldsState>();
  final _unusedOpenCodeAgent = TextEditingController();
  final _unusedWorkdir = TextEditingController();
  String? _workingFolder;
  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _instructions.dispose();
    _unusedOpenCodeAgent.dispose();
    _unusedWorkdir.dispose();
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
            decoration: InputDecoration(
              labelText: 'Description',
              hintText: 'Describe what this agent does',
            ),
          ),
          TextField(
            controller: _instructions,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Agent-specific instructions (optional)',
              hintText: 'For example: use two agents to review code changes.',
            ),
          ),
          const SizedBox(height: 16),
          _OpenCodeProfileFields(
            key: _modelFieldsKey,
            showIntro: false,
            modelOnly: true,
            onLoadOpenCodeModels: widget.onLoadOpenCodeModels,
            initialFolderChoices: widget.initialFolderChoices,
            onLoadFolders: widget.onLoadFolders,
            openCodeAgent: _unusedOpenCodeAgent,
            workdir: _unusedWorkdir,
            restartOnFailure: true,
            onRestartOnFailureChanged: (_) {},
          ),
          DropdownButtonFormField<String>(
            initialValue: _workingFolder ?? '',
            isExpanded: true,
            decoration: InputDecoration(
              labelText: widget.conversationScoped
                  ? 'Visible directory'
                  : 'Working directory',
              helperText: widget.conversationScoped
                  ? 'Choose what this conversation agent can access.'
                  : 'Choose where this agent can read and write.',
              prefixIcon: Icon(Icons.folder_outlined),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('Worker default')),
              for (final folder in widget.initialFolderChoices)
                DropdownMenuItem(
                  value: folder.path,
                  child: Text(
                    folder.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (path) => setState(() {
              _workingFolder = path?.isEmpty ?? true ? null : path;
            }),
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
            if (_instructions.text.trim().isNotEmpty)
              'agent_traits': _instructions.text.trim(),
            if (_modelFieldsKey.currentState?.selectedModel case final model?)
              'opencode_provider_id': model.providerId,
            if (_modelFieldsKey.currentState?.selectedModel case final model?)
              'opencode_provider_name': model.providerName,
            if (_modelFieldsKey.currentState?.selectedModel case final model?)
              'opencode_model_id': model.modelId,
            if (_modelFieldsKey.currentState?.selectedModel case final model?)
              'opencode_model_name': model.modelName,
            if (widget.conversationScoped) 'folder_scope': [?_workingFolder],
            if (!widget.conversationScoped && _workingFolder != null)
              'agent_workdir': _workingFolder,
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
    this.modelOnly = false,
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
  final bool modelOnly;
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
      if (!widget.modelOnly) ...[
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
    required this.memberAdmins,
    required this.canManageMembers,
    required this.canRemoveMembers,
    required this.onSetMemberAdmin,
    required this.onRemoveMember,
    required this.onOpenDirect,
    required this.onDisplayNameChanged,
    required this.onMemberAliasChanged,
  });
  final List<String> members;
  final String ownPubkey;
  final String displayName;
  final Map<String, String> memberAliases;
  final Map<String, String> memberNames;
  final Set<String> memberAdmins;
  final bool canManageMembers;
  final bool canRemoveMembers;
  final Future<void> Function(String pubkey, bool isAdmin) onSetMemberAdmin;
  final Future<void> Function(String pubkey) onRemoveMember;
  final ValueChanged<String> onOpenDirect;
  final ValueChanged<String> onDisplayNameChanged;
  final void Function(String pubkey, String alias) onMemberAliasChanged;
  @override
  State<_PeopleDirectory> createState() => _PeopleDirectoryState();
}

class _ConversationMembersDialog extends StatelessWidget {
  const _ConversationMembersDialog({
    required this.members,
    required this.agents,
    required this.workspaceMembers,
    required this.canManage,
    required this.memberLabel,
    required this.onAdd,
    required this.onRemove,
  });

  final List<WorkspaceChannelMember> members;
  final List<WorkspaceAgent> agents;
  final List<String> workspaceMembers;
  final bool canManage;
  final String Function(String pubkey) memberLabel;
  final Future<void> Function(String pubkey)? onAdd;
  final Future<void> Function(String pubkey)? onRemove;

  Future<void> _addMember(BuildContext context) async {
    final memberIds = members.map((member) => member.pubkey).toSet();
    final candidates = workspaceMembers
        .where((pubkey) => !memberIds.contains(pubkey))
        .toList(growable: false);
    if (candidates.isEmpty) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add member'),
        children: [
          for (final pubkey in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, pubkey),
              child: Text(memberLabel(pubkey)),
            ),
        ],
      ),
    );
    if (selected == null || onAdd == null) return;
    await onAdd!(selected);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _removeMember(BuildContext context, String pubkey) async {
    if (onRemove == null) return;
    await onRemove!(pubkey);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Conversation members'),
    content: SizedBox(
      width: 420,
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text('People'),
          const SizedBox(height: 8),
          for (final member in members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _WorkspaceFrogAvatar(
                identity: member.pubkey,
                label: memberLabel(member.pubkey),
              ),
              title: Text(memberLabel(member.pubkey)),
              subtitle: member.isAdmin
                  ? const Text('Conversation admin')
                  : null,
              trailing: canManage && !member.isAdmin
                  ? IconButton(
                      tooltip: 'Remove from conversation',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () =>
                          unawaited(_removeMember(context, member.pubkey)),
                    )
                  : null,
            ),
          const SizedBox(height: 16),
          const Text('Agents'),
          const SizedBox(height: 8),
          if (agents.isEmpty)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('No agents in this conversation'),
            ),
          for (final agent in agents)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _WorkspaceFrogAvatar(
                identity: agent.id,
                label: agent.name,
                bot: true,
              ),
              title: Text(agent.name),
              subtitle: Text(agent.role),
            ),
        ],
      ),
    ),
    actions: [
      if (canManage && onAdd != null)
        TextButton.icon(
          onPressed: () => unawaited(_addMember(context)),
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Add member'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
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

  Future<void> _removeMember(String pubkey) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text(
          '${_memberLabel(pubkey)} will lose access to this workspace.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (shouldRemove == true) await widget.onRemoveMember(pubkey);
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.members;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Members',
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
            leading: _WorkspaceFrogAvatar(
              identity: person,
              label: _memberLabel(person),
            ),
            title: Text(_memberLabel(person)),
            subtitle: Text(
              person == widget.ownPubkey
                  ? 'You${widget.memberAdmins.contains(person) ? ' · Admin' : ''}'
                  : widget.memberAdmins.contains(person)
                  ? 'Admin'
                  : 'Member',
            ),
            trailing: person == widget.ownPubkey
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.canManageMembers &&
                          !person.startsWith('agent:'))
                        Switch.adaptive(
                          value: widget.memberAdmins.contains(person),
                          onChanged: (isAdmin) => unawaited(
                            widget.onSetMemberAdmin(person, isAdmin),
                          ),
                        ),
                      if (widget.canRemoveMembers &&
                          !person.startsWith('agent:'))
                        IconButton(
                          icon: const Icon(Icons.person_remove_outlined),
                          tooltip: 'Remove member',
                          onPressed: () => unawaited(_removeMember(person)),
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Set local name',
                        onPressed: () => _editAlias(person),
                      ),
                    ],
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
    required this.memberStatus,
    required this.canCreateInvite,
    required this.inviteCode,
    required this.onEnterInviteCode,
    required this.onCreateInvite,
  });

  final String memberStatus;
  final bool canCreateInvite;
  final String? inviteCode;
  final VoidCallback onEnterInviteCode;
  final Future<void> Function() onCreateInvite;

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
        const Divider(height: 40),
        if (canCreateInvite) ...[
          Text('Invite people', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onCreateInvite,
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
              subtitle: const Text(
                'Scan this code or copy the invite payload.',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: inviteCode!)),
                tooltip: 'Copy invite code',
              ),
            ),
          ],
          const Divider(height: 40),
        ],
        Text('Join workspace', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'Use an invite code to confirm access to another workspace.',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onEnterInviteCode,
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
    required this.fipsPeers,
    required this.fipsPeerNpub,
    required this.contactNameForPubkey,
    required this.onRefreshWorkspace,
    required this.onRefreshFipsMesh,
    required this.onFipsEnabledChanged,
  });

  final ValueNotifier<List<String>> diagnostics;
  final ValueNotifier<bool> fipsEnabled;
  final ValueNotifier<_WorkspaceFipsHeartbeat> fipsHeartbeat;
  final ValueNotifier<List<String>> fipsPeers;
  final String fipsPeerNpub;
  final String Function(String pubkey) contactNameForPubkey;
  final Future<void> Function() onRefreshWorkspace;
  final Future<void> Function() onRefreshFipsMesh;
  final ValueChanged<bool> onFipsEnabledChanged;

  @override
  State<_ClientDiagnosticsPage> createState() => _ClientDiagnosticsPageState();
}

class _ClientDiagnosticsPageState extends State<_ClientDiagnosticsPage> {
  _DiagnosticFilter _filter = _DiagnosticFilter.all;
  bool _refreshingFipsMesh = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshFipsMesh());
  }

  Future<void> _refreshFipsMesh() async {
    if (_refreshingFipsMesh) return;
    setState(() => _refreshingFipsMesh = true);
    try {
      await widget.onRefreshFipsMesh();
    } finally {
      if (mounted) setState(() => _refreshingFipsMesh = false);
    }
  }

  Future<void> _copyDiagnostics() => Clipboard.setData(
    ClipboardData(
      text: [
        'FIPS enabled: ${widget.fipsEnabled.value}',
        'FIPS connection: ${widget.fipsHeartbeat.value.connectionState}',
        'FIPS connected at: ${widget.fipsHeartbeat.value.connectedAt?.toIso8601String() ?? 'never'}',
        'FIPS last heartbeat: ${widget.fipsHeartbeat.value.lastHeartbeatAt?.toIso8601String() ?? 'never'}',
        'FIPS heartbeats received: ${widget.fipsHeartbeat.value.count}',
        'FIPS direct peer: ${widget.fipsPeerNpub.isEmpty ? 'none' : widget.fipsPeerNpub}',
        'FIPS topology: direct client-to-worker route; clients are not a full mesh',
        '',
        ...widget.diagnostics.value,
      ].join('\n'),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Network'),
      actions: [
        IconButton(
          onPressed: () => unawaited(widget.onRefreshWorkspace()),
          icon: const Icon(Icons.refresh_outlined),
          tooltip: 'Refresh workspace',
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
          final liveFor = heartbeat.connectedAt == null
              ? null
              : now.difference(heartbeat.connectedAt!);
          final lastHeartbeat = heartbeat.lastHeartbeatAt == null
              ? null
              : now.difference(heartbeat.lastHeartbeatAt!);
          final connectionTime =
              heartbeat.connectedAt == null ||
                  heartbeat.connectionStartedAt == null
              ? null
              : heartbeat.connectedAt!.difference(
                  heartbeat.connectionStartedAt!,
                );
          final events = _groupDiagnosticEvents(
            entries,
            connectionTime: connectionTime,
          );
          final visibleEvents = events
              .where((event) => _filter.includes(event.category))
              .toList();
          final warnings = events.where((event) => event.isWarning).length;
          final errors = events.where((event) => event.isError).length;
          final active = heartbeat.connectionState == 'active';
          final stateColor = active
              ? const Color(0xff35d6a0)
              : heartbeat.connectionState == 'disabled'
              ? theme.colorScheme.onSurfaceVariant
              : heartbeat.connectionState == 'reconnecting' ||
                    heartbeat.connectionState == 'fallback'
              ? const Color(0xffffb547)
              : theme.colorScheme.error;
          final stateLabel = switch (heartbeat.connectionState) {
            'active' => 'Connected',
            'connected' => 'Connected',
            'connecting' => 'Connecting',
            'reconnecting' => 'Reconnecting',
            'fallback' => 'Nostr fallback',
            'disabled' => 'Nostr only',
            _ => 'Disconnected',
          };
          final contentWidth = ((MediaQuery.sizeOf(context).width - 960) / 2)
              .clamp(16.0, double.infinity)
              .toDouble();
          final transportPanel = _DiagnosticPanel(
            title: 'Transport',
            child: ValueListenableBuilder<bool>(
              valueListenable: widget.fipsEnabled,
              builder: (context, enabled, _) => Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          enabled ? 'FIPS preferred' : 'Nostr only',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          enabled
                              ? 'Direct route to worker with Nostr fallback'
                              : 'Nostr messages only',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: enabled,
                    onChanged: widget.onFipsEnabledChanged,
                  ),
                ],
              ),
            ),
          );
          final topologyPanel = _DiagnosticPanel(
            title: 'FIPS topology',
            child: ValueListenableBuilder<List<String>>(
              valueListenable: widget.fipsPeers,
              builder: (context, peers, _) => _FipsMeshMap(
                worker: widget.fipsPeerNpub,
                peers: peers,
                contactNameForPubkey: widget.contactNameForPubkey,
                active: active,
                lastHeartbeat: lastHeartbeat,
                onRefresh: _refreshFipsMesh,
                refreshing: _refreshingFipsMesh,
              ),
            ),
          );
          final connectionPanel = _DiagnosticPanel(
            title: 'Connection',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final status = _DiagnosticConnectionStatus(
                  stateLabel: stateLabel,
                  stateColor: stateColor,
                  active: active,
                  liveFor: liveFor,
                );
                final metrics = _DiagnosticMetrics(
                  liveFor: liveFor,
                  lastHeartbeat: lastHeartbeat,
                  heartbeatCount: heartbeat.count,
                  transport: active ? 'FIPS' : 'Nostr',
                );
                return constraints.maxWidth < 560
                    ? Column(
                        children: [status, const SizedBox(height: 18), metrics],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: status),
                          const SizedBox(width: 28),
                          Expanded(child: metrics),
                        ],
                      );
              },
            ),
          );
          return ListView(
            padding: EdgeInsets.fromLTRB(contentWidth, 16, contentWidth, 32),
            children: [
              LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth < 720
                    ? Column(
                        children: [
                          transportPanel,
                          const SizedBox(height: 28),
                          topologyPanel,
                          const SizedBox(height: 28),
                          connectionPanel,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: connectionPanel),
                          const SizedBox(width: 48),
                          Expanded(
                            child: Column(
                              children: [
                                transportPanel,
                                const SizedBox(height: 28),
                                topologyPanel,
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 28),
              _DiagnosticPanel(
                title: 'Activity',
                action: Wrap(
                  spacing: 4,
                  children: [
                    Tooltip(
                      message: 'Copy diagnostics',
                      child: TextButton.icon(
                        onPressed: _copyDiagnostics,
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        label: const Text('Copy'),
                      ),
                    ),
                    Tooltip(
                      message: 'Clear diagnostics',
                      child: TextButton.icon(
                        onPressed: () => widget.diagnostics.value = const [],
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Clear'),
                      ),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$warnings warnings  /  $errors errors  /  ${events.length} events',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: _DiagnosticFilter.values
                          .map(
                            (filter) => ChoiceChip(
                              label: Text(filter.label),
                              selected: _filter == filter,
                              onSelected: (_) =>
                                  setState(() => _filter = filter),
                              visualDensity: const VisualDensity(
                                horizontal: -4,
                                vertical: -4,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    if (visibleEvents.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text(
                            entries.isEmpty
                                ? 'No connection events yet.'
                                : 'No events match this filter.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    else
                      for (var index = 0; index < visibleEvents.length; index++)
                        _DiagnosticEvent(
                          key: ValueKey(
                            '${visibleEvents[index].timestamp}:${visibleEvents[index].raw}',
                          ),
                          event: visibleEvents[index],
                          isLast: index == visibleEvents.length - 1,
                          isNewest: index == 0,
                        ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _DiagnosticPanel extends StatelessWidget {
  const _DiagnosticPanel({
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final panelAction = action;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            panelAction ?? const SizedBox.shrink(),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _FipsMeshMap extends StatelessWidget {
  const _FipsMeshMap({
    required this.worker,
    required this.peers,
    required this.contactNameForPubkey,
    required this.active,
    required this.lastHeartbeat,
    required this.onRefresh,
    required this.refreshing,
  });

  final String worker;
  final List<String> peers;
  final String Function(String pubkey) contactNameForPubkey;
  final bool active;
  final Duration? lastHeartbeat;
  final Future<void> Function() onRefresh;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkColor = active
        ? const Color(0xff35d6a0)
        : theme.colorScheme.outlineVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.hub_outlined, color: linkColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Worker ${contactNameForPubkey(worker)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh topology',
              onPressed: refreshing ? null : () => unawaited(onRefresh()),
              icon: refreshing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_outlined),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          peers.isEmpty
              ? 'No live FIPS routes reported by the worker.'
              : '${peers.length} live direct route${peers.length == 1 ? '' : 's'}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        for (final peer in peers)
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 7),
            child: Row(
              children: [
                Container(width: 1, height: 24, color: linkColor),
                const SizedBox(width: 12),
                Icon(Icons.devices_other_outlined, size: 18, color: linkColor),
                const SizedBox(width: 8),
                Text(contactNameForPubkey(peer)),
                const SizedBox(width: 8),
                Text(
                  lastHeartbeat == null
                      ? 'connected'
                      : 'heartbeat ${_formatFipsDuration(lastHeartbeat!)} ago',
                  style: theme.textTheme.labelSmall?.copyWith(color: linkColor),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DiagnosticConnectionStatus extends StatelessWidget {
  const _DiagnosticConnectionStatus({
    required this.stateLabel,
    required this.stateColor,
    required this.active,
    required this.liveFor,
  });

  final String stateLabel;
  final Color stateColor;
  final bool active;
  final Duration? liveFor;

  @override
  Widget build(BuildContext context) => Column(
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
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: stateColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            liveFor == null
                ? stateLabel
                : 'Connected for ${_formatFipsDuration(liveFor!)}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: stateColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        active
            ? 'Heartbeat channel is active and receiving updates.'
            : 'Connection lifecycle is being monitored.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _DiagnosticMetrics extends StatelessWidget {
  const _DiagnosticMetrics({
    required this.liveFor,
    required this.lastHeartbeat,
    required this.heartbeatCount,
    required this.transport,
  });

  final Duration? liveFor;
  final Duration? lastHeartbeat;
  final int heartbeatCount;
  final String transport;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _DiagnosticStat(
        label: 'Duration',
        value: liveFor == null
            ? 'Not connected'
            : _formatFipsDuration(liveFor!),
      ),
      _DiagnosticStat(
        label: 'Last heartbeat',
        value: lastHeartbeat == null
            ? 'Waiting'
            : '${_formatFipsDuration(lastHeartbeat!)} ago',
      ),
      _DiagnosticStat(label: 'Heartbeats received', value: '$heartbeatCount'),
      _DiagnosticStat(label: 'Transport', value: transport, isLast: true),
    ],
  );
}

class _DiagnosticStat extends StatelessWidget {
  const _DiagnosticStat({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticEvent extends StatefulWidget {
  const _DiagnosticEvent({
    super.key,
    required this.event,
    required this.isLast,
    required this.isNewest,
  });

  final _DiagnosticEventData event;
  final bool isLast;
  final bool isNewest;

  @override
  State<_DiagnosticEvent> createState() => _DiagnosticEventState();
}

class _DiagnosticEventState extends State<_DiagnosticEvent> {
  var _expanded = false;
  var _highlightNewest = true;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    if (widget.isNewest) {
      _highlightTimer = Timer(const Duration(milliseconds: 2400), () {
        if (mounted) setState(() => _highlightNewest = false);
      });
    } else {
      _highlightNewest = false;
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = widget.event;
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
    return Semantics(
      button: true,
      expanded: _expanded,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _highlightNewest
                ? color.withValues(alpha: 0.08)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 17, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.count > 1
                              ? '${event.title} (${event.count})'
                              : event.title,
                          maxLines: _expanded ? null : 1,
                          overflow: _expanded ? null : TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (event.detail != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            event.detail!,
                            maxLines: _expanded ? null : 1,
                            overflow: _expanded ? null : TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    event.timestamp,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 9),
                Padding(
                  padding: const EdgeInsets.only(left: 27),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(9),
                    color: theme.colorScheme.surfaceContainerLow,
                    child: SelectableText(
                      event.raw,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _DiagnosticFilter { all, issues }

extension on _DiagnosticFilter {
  String get label => switch (this) {
    _DiagnosticFilter.all => 'All',
    _DiagnosticFilter.issues => 'Issues',
  };

  bool includes(_DiagnosticCategory category) => switch (this) {
    _DiagnosticFilter.all => true,
    _DiagnosticFilter.issues =>
      category == _DiagnosticCategory.warning ||
          category == _DiagnosticCategory.error,
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
    required this.raw,
    this.detail,
    this.count = 1,
  });

  final String timestamp;
  final _DiagnosticCategory category;
  final String title;
  final String raw;
  final String? detail;
  final int count;

  bool get isWarning => category == _DiagnosticCategory.warning;
  bool get isError => category == _DiagnosticCategory.error;

  String get metadata => switch (category) {
    _DiagnosticCategory.snapshot when count > 1 => '$count events',
    _DiagnosticCategory.warning => 'Nostr fallback',
    _DiagnosticCategory.error => 'Review',
    _DiagnosticCategory.connection => 'FIPS',
    _ => '',
  };

  _DiagnosticEventData copyWith({
    String? title,
    String? detail,
    bool clearDetail = false,
    int? count,
  }) => _DiagnosticEventData(
    timestamp: timestamp,
    category: category,
    title: title ?? this.title,
    raw: raw,
    detail: clearDetail ? null : detail ?? this.detail,
    count: count ?? this.count,
  );
}

List<_DiagnosticEventData> _groupDiagnosticEvents(
  List<String> entries, {
  Duration? connectionTime,
}) {
  final grouped = <_DiagnosticEventData>[];
  for (final entry in entries.reversed.take(80)) {
    final event = _diagnosticEvent(entry);
    if (event.raw.toLowerCase().contains('connection: active')) continue;
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
    grouped.add(
      event.category == _DiagnosticCategory.connection &&
              event.title == 'Connected' &&
              connectionTime != null
          ? event.copyWith(
              title: 'Connected in ${_formatFipsDuration(connectionTime)}',
              clearDetail: true,
            )
          : event,
    );
  }
  return grouped;
}

_DiagnosticEventData _diagnosticEvent(String entry) {
  final match = RegExp(r'^(\d{2}:\d{2}:\d{2})\s{2}(.*)$').firstMatch(entry);
  final timestamp = match?.group(1) ?? '';
  final raw = match?.group(2) ?? entry;
  final value = _diagnosticSummary(raw);
  final lower = raw.toLowerCase();

  if (lower.contains('offer timed out') ||
      lower.contains('fallback') ||
      lower.contains('retrying') ||
      lower.contains('reconnecting')) {
    return _DiagnosticEventData(
      timestamp: timestamp,
      category: _DiagnosticCategory.warning,
      title: lower.contains('fallback')
          ? 'Fallback activated'
          : lower.contains('reconnecting')
          ? 'Retrying connection'
          : 'Retrying snapshot',
      raw: raw,
      detail: lower.contains('fallback')
          ? 'Using Nostr fallback.'
          : lower.contains(' in ')
          ? value
          : 'Snapshot exchange is retrying.',
    );
  }
  if (lower.contains('failed') || lower.contains('timed out')) {
    final heartbeat = lower.contains('heartbeat');
    return _DiagnosticEventData(
      timestamp: timestamp,
      category: _DiagnosticCategory.error,
      title: 'Session failed',
      raw: raw,
      detail: heartbeat
          ? 'Heartbeat timed out. Switched to Nostr fallback.'
          : 'Switched to Nostr fallback.',
    );
  }
  if (lower == 'fips workspace connection: active' ||
      lower == 'fips workspace connection: connected' ||
      lower == 'connected') {
    return _DiagnosticEventData(
      timestamp: timestamp,
      category: _DiagnosticCategory.connection,
      title: value.replaceFirst('Connection ', ''),
      raw: raw,
    );
  }
  if (lower.contains('connection:') || lower.contains('snapshot')) {
    return _DiagnosticEventData(
      timestamp: timestamp,
      category: _DiagnosticCategory.info,
      title: value,
      raw: raw,
    );
  }
  if (lower.contains('fips') || lower.contains('nostr')) {
    return _DiagnosticEventData(
      timestamp: timestamp,
      category: _DiagnosticCategory.transport,
      title: value,
      raw: raw,
    );
  }
  return _DiagnosticEventData(
    timestamp: timestamp,
    category: _DiagnosticCategory.info,
    title: value,
    raw: raw,
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
        title: const Text('Host'),
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
            ? color.withValues(alpha: 0.10)
            : Theme.of(context).colorScheme.surfaceContainerLow,
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
          : Theme.of(context).colorScheme.surfaceContainerLow,
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
                child: SizedBox.expand(
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
      ..color = gridColor.withValues(alpha: 0.24)
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
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.18),
            lineColor.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
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
  String? _currentFolderPath;
  String? _selectedPath;
  String? _selectedLabel;
  List<RepoChoice> _choices = const [];

  @override
  void initState() {
    super.initState();
    _choices = widget.initialChoices;
    _selectedPath = widget.selectedPath.isEmpty ? null : widget.selectedPath;
    _selectedLabel = _selectedPath;
    if (_choices.isEmpty) unawaited(_loadFolders());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFolders([String? path, String? folderPath]) async {
    setState(() => _loadingFolders = true);
    try {
      final choices = await widget.onLoadFolders(path);
      if (!mounted) return;
      setState(() {
        _choices = choices;
        _currentPath = path ?? '';
        _currentFolderPath = folderPath;
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
    final canUseSelectedFolder = _selectedPath != null;

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
                          _loadFolders(
                            parts.isEmpty ? null : parts.join('/'),
                            _parentFolderPath(_currentFolderPath),
                          );
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
                if (_currentFolderPath != null)
                  TextButton(
                    onPressed: _loadingFolders
                        ? null
                        : () => setState(() {
                            _selectedPath = _currentFolderPath;
                            _selectedLabel = _currentPath;
                          }),
                    child: const Text('Select this folder'),
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Radio<String>(value: choice.path),
                              IconButton(
                                tooltip: 'Open folder',
                                onPressed: _loadingFolders
                                    ? null
                                    : () => _loadFolders(
                                        choice.relativePath,
                                        choice.path,
                                      ),
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                          onTap: () => setState(() {
                            _selectedPath = choice.path;
                            _selectedLabel = choice.displayName;
                          }),
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
            onPressed: !canUseSelectedFolder
                ? null
                : () {
                    Navigator.pop(
                      context,
                      _WorkingFolderSelection(
                        path: _selectedPath,
                        label: _selectedLabel ?? _selectedPath,
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

  String? _parentFolderPath(String? path) {
    if (path == null) return null;
    final slash = path.lastIndexOf('/');
    return slash <= 0 ? null : path.substring(0, slash);
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
    required this.showRepoTarget,
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
    required this.dateFormat,
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
    required this.onDateFormatChanged,
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
  final bool showRepoTarget;
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
  final WorkspaceDateFormat dateFormat;
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
  final ValueChanged<WorkspaceDateFormat> onDateFormatChanged;
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
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Date format'),
              trailing: DropdownButton<WorkspaceDateFormat>(
                value: dateFormat,
                underline: const SizedBox.shrink(),
                onChanged: (value) {
                  if (value != null) onDateFormatChanged(value);
                },
                items: [
                  for (final option in WorkspaceDateFormat.values)
                    DropdownMenuItem(value: option, child: Text(option.label)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ConnectionPanel(
            repoTargets: repoTargets,
            showRepoTarget: showRepoTarget,
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
                  Text('Version: $_appVersion'),
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
    required this.showRepoTarget,
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
  final bool showRepoTarget;
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
            OutlinedButton.icon(
              onPressed: connecting ? null : onEnterInviteCode,
              icon: const Icon(Icons.content_paste_go_outlined),
              label: const Text('Paste workspace invite'),
            ),
            const SizedBox(height: 12),
            if (showRepoTarget) ...[
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
              const Divider(height: 28),
            ],
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
    super.key,
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
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attachment downloads are unavailable in the browser.'),
        ),
      );
      return;
    }
    final key = attachment.sha256;
    if (_downloadingAttachments.contains(key)) return;
    setState(() => _downloadingAttachments.add(key));
    try {
      final directory = await getApplicationDocumentsDirectory();
      final downloaded = await blossomDownloadAttachment(
        attachment: attachment,
        destinationDir: '${directory.path}/attachments',
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
          else if (processing || widget.message.kind == 'status')
            Row(
              children: [
                if (processing && widget.workingAnimationStyle.enabled) ...[
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
                  child: widget.message.kind == 'status'
                      ? _WorkerStatusText(
                          text: widget.message.text,
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      : MarkdownBody(
                          data: widget.message.text,
                          styleSheet: _markdownStyleSheet(context, userSide),
                          builders: _markdownBuilders(context, userSide),
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
              styleSheet: _markdownStyleSheet(context, userSide),
              builders: _markdownBuilders(context, userSide),
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

  MarkdownStyleSheet _markdownStyleSheet(BuildContext context, bool userSide) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final quoteColor = userSide
        ? colors.onPrimaryContainer.withValues(alpha: 0.10)
        : colors.surfaceContainerHighest;
    final quoteTextColor = userSide
        ? colors.onPrimaryContainer
        : colors.onSurface;
    final codeBackground = userSide
        ? colors.onPrimaryContainer.withValues(alpha: 0.14)
        : const Color(0xff102b25);
    final codeTextColor = userSide
        ? colors.onPrimaryContainer
        : const Color(0xffd5ffec);

    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      blockquote: theme.textTheme.bodyMedium?.copyWith(color: quoteTextColor),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      blockquoteDecoration: BoxDecoration(
        color: quoteColor,
        borderRadius: BorderRadius.circular(10),
      ),
      codeblockPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      codeblockDecoration: BoxDecoration(
        color: codeBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      code: theme.textTheme.bodyMedium?.copyWith(
        color: codeTextColor,
        fontFamily: 'monospace',
        fontSize: 14,
        height: 1.55,
      ),
    );
  }

  Map<String, MarkdownElementBuilder> _markdownBuilders(
    BuildContext context,
    bool userSide,
  ) => {'pre': _CodeBlockBuilder(userSide)};

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

class _WorkerStatusText extends StatefulWidget {
  const _WorkerStatusText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_WorkerStatusText> createState() => _WorkerStatusTextState();
}

class _WorkerStatusTextState extends State<_WorkerStatusText>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 360);

  late final AnimationController _controller;
  String? _previousText;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
  }

  @override
  void didUpdateWidget(covariant _WorkerStatusText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text) return;
    _previousText = oldWidget.text;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final previousText = _previousText;
    if (previousText == null || reduceMotion) {
      return Text(widget.text, style: widget.style);
    }
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = Curves.easeOutCubic.transform(_controller.value);
          return Stack(
            children: [
              FractionalTranslation(
                translation: Offset(-progress, 0),
                child: Opacity(
                  opacity: 1 - progress,
                  child: Text(previousText, style: widget.style),
                ),
              ),
              FractionalTranslation(
                translation: Offset(1 - progress, 0),
                child: Opacity(
                  opacity: progress,
                  child: Text(widget.text, style: widget.style),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder(this.userSide);

  final bool userSide;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.textContent.trimRight();
    if (code.isEmpty) return null;

    final colors = Theme.of(context).colorScheme;
    final background = userSide
        ? colors.onPrimaryContainer.withValues(alpha: 0.14)
        : const Color(0xff102b25);
    final foreground = userSide
        ? colors.onPrimaryContainer
        : const Color(0xffd5ffec);

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Copy code',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(content: Text('Code copied')));
              },
              icon: const Icon(Icons.content_copy_outlined),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SelectableText(
              code,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: foreground,
                fontFamily: 'monospace',
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
