part of '../main.dart';

const _recordingButtonColor = Color(0xffffc078);
const _recordingButtonForegroundColor = Colors.black;

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
    required this.onRestartTarget,
    required this.onRenameTarget,
    required this.onTogglePinTarget,
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
  final ValueChanged<RepoTarget> onRestartTarget;
  final ValueChanged<RepoTarget> onRenameTarget;
  final ValueChanged<RepoTarget> onTogglePinTarget;
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
              child: ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.of(context).pop();
                  onOpenSettings();
                },
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

enum _SessionDrawerAction { pin, restart, rename, delete }

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
  final Future<List<RepoChoice>> Function() onLoadRepos;

  @override
  State<_SpawnSessionPage> createState() => _SpawnSessionPageState();
}

class _SpawnSessionPageState extends State<_SpawnSessionPage> {
  final _pathController = TextEditingController();
  final _searchController = TextEditingController();
  bool _create = true;
  bool _loadingRepos = false;
  String _searchQuery = '';
  List<RepoChoice> _repoChoices = const [];

  @override
  void initState() {
    super.initState();
    _repoChoices = widget.initialRepoChoices;
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
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                helperText: _create
                    ? 'Created inside an allowed worker root'
                    : 'Select below or enter an allowed path',
                labelText: _create ? 'New folder' : 'Selected folder',
                hintText: _create ? 'my-new-project' : 'phone',
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
                    onPressed: _loadingRepos ? null : _loadRepos,
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
            Expanded(
              child: _loadingRepos && _repoChoices.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : visibleChoices.isEmpty
                  ? const Center(child: Text('No matching folders'))
                  : ListView.separated(
                      itemCount: visibleChoices.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 64),
                      itemBuilder: (context, index) {
                        final choice = visibleChoices[index];
                        final selected =
                            _pathController.text == choice.relativePath;
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
                          trailing: selected
                              ? const Icon(Icons.check_circle)
                              : const Icon(Icons.chevron_right),
                          onTap: () {
                            setState(
                              () => _pathController.text = choice.relativePath,
                            );
                          },
                        );
                      },
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
    required this.repoTargets,
    required this.computerServiceTarget,
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
    required this.workingAnimationSpeed,
    required this.recordingWaveformHistorySeconds,
    required this.recordingWaveformSensitivity,
    required this.recordingWaveformDecay,
    required this.hapticFeedbackEnabled,
    required this.receiveVibrationEnabled,
    required this.inactiveReplyPopupEnabled,
    required this.inactiveReplyAudioEnabled,
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
    required this.onTargetChanged,
    required this.onSaveTarget,
    required this.onNewTarget,
    required this.onScanTarget,
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
    required this.onRecordingWaveformHistoryChanged,
    required this.onRecordingWaveformSensitivityChanged,
    required this.onRecordingWaveformDecayChanged,
    required this.onHapticFeedbackChanged,
    required this.onReceiveVibrationChanged,
    required this.onInactiveReplyPopupChanged,
    required this.onInactiveReplyAudioChanged,
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

  final List<RepoTarget> repoTargets;
  final RepoTarget? computerServiceTarget;
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
  final WorkingAnimationStyle workingAnimationStyle;
  final double workingAnimationSpeed;
  final double recordingWaveformHistorySeconds;
  final double recordingWaveformSensitivity;
  final double recordingWaveformDecay;
  final bool hapticFeedbackEnabled;
  final bool receiveVibrationEnabled;
  final bool inactiveReplyPopupEnabled;
  final bool inactiveReplyAudioEnabled;
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
  final ValueChanged<String?> onTargetChanged;
  final VoidCallback onSaveTarget;
  final VoidCallback onNewTarget;
  final VoidCallback onScanTarget;
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
  final ValueChanged<double> onRecordingWaveformHistoryChanged;
  final ValueChanged<double> onRecordingWaveformSensitivityChanged;
  final ValueChanged<double> onRecordingWaveformDecayChanged;
  final ValueChanged<bool> onHapticFeedbackChanged;
  final ValueChanged<bool> onReceiveVibrationChanged;
  final ValueChanged<bool> onInactiveReplyPopupChanged;
  final ValueChanged<bool> onInactiveReplyAudioChanged;
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
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
            checkingRelays: checkingRelays,
            relayResults: relayResults,
            onTargetChanged: onTargetChanged,
            onSaveTarget: onSaveTarget,
            onNewTarget: onNewTarget,
            onScanTarget: onScanTarget,
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
            initialHistorySeconds: recordingWaveformHistorySeconds,
            initialSensitivity: recordingWaveformSensitivity,
            initialDecay: recordingWaveformDecay,
            onHistoryChanged: onRecordingWaveformHistoryChanged,
            onSensitivityChanged: onRecordingWaveformSensitivityChanged,
            onDecayChanged: onRecordingWaveformDecayChanged,
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
    required this.initialHistorySeconds,
    required this.initialSensitivity,
    required this.initialDecay,
    required this.onHistoryChanged,
    required this.onSensitivityChanged,
    required this.onDecayChanged,
  });

  final double initialHistorySeconds;
  final double initialSensitivity;
  final double initialDecay;
  final ValueChanged<double> onHistoryChanged;
  final ValueChanged<double> onSensitivityChanged;
  final ValueChanged<double> onDecayChanged;

  @override
  State<_RecordingWaveformSettings> createState() =>
      _RecordingWaveformSettingsState();
}

class _RecordingWaveformSettingsState
    extends State<_RecordingWaveformSettings> {
  late double _historySeconds;
  late double _sensitivity;
  late double _decay;

  @override
  void initState() {
    super.initState();
    _historySeconds = widget.initialHistorySeconds;
    _sensitivity = widget.initialSensitivity;
    _decay = widget.initialDecay;
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
              'Tune the live equalizer while recording.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _WaveformSlider(
              label: 'History',
              valueLabel: '${_historySeconds.toStringAsFixed(2)} s',
              value: _historySeconds,
              min: 0.25,
              max: 2.0,
              divisions: 7,
              onChanged: (value) {
                setState(() => _historySeconds = value);
                widget.onHistoryChanged(value);
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
              label: 'Silence fade',
              valueLabel: '${_decay.toStringAsFixed(1)}x',
              value: _decay,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              onChanged: (value) {
                setState(() => _decay = value);
                widget.onDecayChanged(value);
              },
            ),
          ],
        ),
      ),
    );
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
    required this.recordingWaveformHistorySeconds,
    required this.recordingWaveformDecay,
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
  final double recordingWaveformLevel;
  final double recordingWaveformHistorySeconds;
  final double recordingWaveformDecay;
  final String recordingDurationLabel;
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
                        child: _RecordingButton(
                          sendWipe: false,
                          finishWipe: false,
                          backgroundColor: Colors.transparent,
                          wipeColor: Colors.transparent,
                          waveformColor:
                              theme.textTheme.bodyLarge?.color ??
                              theme.colorScheme.onSurface,
                          waveformLevel: widget.recordingWaveformLevel,
                          waveformHistorySeconds:
                              widget.recordingWaveformHistorySeconds,
                          waveformDecay: widget.recordingWaveformDecay,
                          child: const SizedBox.expand(),
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
                final sendingAudioShell =
                    _voiceWipeVisible && !widget.recording;
                final sentButtonColor = theme.colorScheme.primary;

                final icon = busy
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: sendingAudioShell
                              ? _recordingButtonForegroundColor
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
                    style: sendingAudioShell
                        ? mainButtonStyle.copyWith(
                            backgroundColor: const WidgetStatePropertyAll(
                              Colors.transparent,
                            ),
                            foregroundColor: const WidgetStatePropertyAll(
                              _recordingButtonForegroundColor,
                            ),
                          )
                        : mainButtonStyle,
                    onPressed: onMainPressed,
                    icon: icon,
                    label: Text(label),
                  ),
                );
                final actionButton = (widget.recording || sendingAudioShell)
                    ? _RecordingButton(
                        sendWipe: sendingAudioShell,
                        finishWipe: _finishVoiceWipe,
                        backgroundColor: _recordingButtonColor,
                        foregroundColor: _recordingButtonForegroundColor,
                        wipeColor: sentButtonColor,
                        wipeDuration: widget.voiceSendWipeDuration,
                        showWaveform: false,
                        waveformLevel: 0,
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
    this.waveformColor = Colors.white,
    required this.waveformLevel,
    this.waveformHistorySeconds = 1.0,
    this.waveformDecay = 0.6,
    this.showWaveform = true,
    this.onWipeComplete,
  });

  final Widget child;
  final bool sendWipe;
  final bool finishWipe;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color wipeColor;
  final Duration wipeDuration;
  final Color waveformColor;
  final double waveformLevel;
  final double waveformHistorySeconds;
  final double waveformDecay;
  final bool showWaveform;
  final VoidCallback? onWipeComplete;

  @override
  State<_RecordingButton> createState() => _RecordingButtonState();
}

class _RecordingButtonState extends State<_RecordingButton>
    with TickerProviderStateMixin {
  static const _waveSampleRate = 30.0;

  late final AnimationController _wipeController;
  late final Animation<double> _wipeAnimation;
  late final AnimationController _waveController;
  final _waveRandom = math.Random();
  final _waveSamples = <double>[];
  double _lastWaveProgress = 0;
  double _waveSampleCarry = 0;
  double _smoothedWaveLevel = 0;

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
    _waveController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 1450),
          )
          ..addListener(_advanceWaveform)
          ..repeat();
    if (widget.sendWipe) {
      _wipeController.forward(from: 0);
    } else {
      _seedWaveSamples();
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
      _wipeController
          .animateTo(
            1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => widget.onWipeComplete?.call());
    } else if (!widget.sendWipe && oldWidget.sendWipe) {
      _wipeController.value = 0;
      _seedWaveSamples();
    }
    if (widget.waveformHistorySeconds != oldWidget.waveformHistorySeconds) {
      _seedWaveSamples();
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _wipeController.dispose();
    super.dispose();
  }

  void _advanceWaveform() {
    if (widget.sendWipe) {
      _lastWaveProgress = _waveController.value;
      return;
    }

    final progress = _waveController.value;
    var delta = progress - _lastWaveProgress;
    if (delta < 0) delta += 1;
    _lastWaveProgress = progress;

    _waveSampleCarry += delta * _waveSampleRate;
    while (_waveSampleCarry >= 1) {
      _waveSampleCarry -= 1;
      _pushWaveSample();
    }
  }

  void _pushWaveSample() {
    final level = widget.waveformLevel.clamp(0.0, 1.0);
    final responsiveLevel = math.pow(level, 0.7).toDouble();
    final smoothing = responsiveLevel < _smoothedWaveLevel
        ? widget.waveformDecay
        : 0.9;
    _smoothedWaveLevel += (responsiveLevel - _smoothedWaveLevel) * smoothing;
    if (_smoothedWaveLevel < 0.015) {
      _smoothedWaveLevel = 0;
      _waveSamples.add(0);
    } else {
      final previous = _waveSamples.isEmpty ? 0.0 : _waveSamples.last;
      final noise = _waveRandom.nextDouble() * 2 - 1;
      _waveSamples.add((previous * 0.15 + noise * 0.85) * _smoothedWaveLevel);
    }
    if (_waveSamples.length > _waveSampleCount) {
      _waveSamples.removeRange(0, _waveSamples.length - _waveSampleCount);
    }
  }

  void _seedWaveSamples() {
    _waveSamples
      ..clear()
      ..addAll(List<double>.filled(_waveSampleCount, 0));
  }

  int get _waveSampleCount =>
      (widget.waveformHistorySeconds.clamp(0.25, 2.0) * _waveSampleRate)
          .round();

  @override
  Widget build(BuildContext context) {
    final showWaveform = widget.showWaveform && !widget.sendWipe;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(child: ColoredBox(color: widget.backgroundColor)),
          if (showWaveform)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _waveController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _RecordingWaveformPainter(
                      samples: List<double>.of(_waveSamples),
                      color: widget.waveformColor,
                    ),
                  );
                },
              ),
            ),
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
  const _RecordingWaveformPainter({required this.samples, required this.color});

  final List<double> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.62)
      ..style = PaintingStyle.fill;
    final values = samples.isEmpty ? const [0.0] : samples;
    final gap = 2.0;
    final barWidth = math.max(
      1.0,
      (size.width - gap * (values.length - 1)) / values.length,
    );
    final centerY = size.height / 2;

    for (var i = 0; i < values.length; i++) {
      final level = values[i].abs().clamp(0.0, 1.0);
      final barHeight = math.max(1.0, level * size.height * 0.78);
      final left = i * (barWidth + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, centerY - barHeight / 2, barWidth, barHeight),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RecordingWaveformPainter oldDelegate) {
    return oldDelegate.samples != samples || oldDelegate.color != color;
  }
}

class _MessageTile extends StatefulWidget {
  const _MessageTile({
    required this.message,
    required this.showResend,
    required this.speaking,
    required this.workingAnimationStyle,
    required this.workingAnimationSpeed,
    required this.recordingWaveformLevel,
    required this.recording,
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
  final double recordingWaveformLevel;
  final bool recording;
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
