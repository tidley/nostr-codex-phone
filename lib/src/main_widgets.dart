part of '../main.dart';

const _recordingButtonColor = Color(0xffc96b14);

class _SessionDrawer extends StatelessWidget {
  const _SessionDrawer({
    required this.targets,
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
    required this.onRestartTarget,
    required this.onRenameTarget,
    required this.onOpenSettings,
    required this.onDeleteTarget,
  });

  final List<RepoTarget> targets;
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
  final ValueChanged<RepoTarget> onRestartTarget;
  final ValueChanged<RepoTarget> onRenameTarget;
  final VoidCallback onOpenSettings;
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
                                            ? DigitalThinkingIndicator(
                                                width: 28,
                                                height: 16,
                                                color:
                                                    statusColor ?? loadedColor,
                                                style: workingAnimationStyle,
                                                speed: workingAnimationSpeed,
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
                                : compactIdentifier(target.pubkey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: unreadCount > 0
                              ? Badge(label: Text('$unreadCount'), child: menu)
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

  final List<RepoChoice> initialRepoChoices;
  final Future<List<RepoChoice>> Function() onLoadRepos;

  @override
  State<_SpawnSessionDialog> createState() => _SpawnSessionDialogState();
}

class _SpawnSessionDialogState extends State<_SpawnSessionDialog> {
  final _pathController = TextEditingController();
  bool _create = true;
  bool _loadingRepos = false;
  List<RepoChoice> _repoChoices = const [];

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
      return 'Use a folder name under the worker root';
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
                  helperText: 'Under worker root',
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
    required this.hapticFeedbackEnabled,
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
    required this.onHapticFeedbackChanged,
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
  final bool hapticFeedbackEnabled;
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
  final ValueChanged<bool> onHapticFeedbackChanged;
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

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.connected,
    required this.connecting,
    required this.sending,
    required this.sendingAudio,
    required this.sendingMedia,
    required this.activeSendBlocked,
    required this.recording,
    required this.recordingWaveformLevel,
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
  final bool sendingMedia;
  final bool activeSendBlocked;
  final bool recording;
  final double recordingWaveformLevel;
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
                          backgroundColor: Colors.transparent,
                          wipeColor: Colors.transparent,
                          waveformColor:
                              theme.textTheme.bodyLarge?.color ??
                              theme.colorScheme.onSurface,
                          waveformLevel: widget.recordingWaveformLevel,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  )
                : TextField(
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
                    widget.sendingAudio && !widget.recording;
                final sentButtonColor = theme.colorScheme.primaryContainer;

                final icon = busy
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: sendingAudioShell
                              ? Colors.white
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
                              Colors.white,
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
                        backgroundColor: sentButtonColor,
                        wipeColor: _recordingButtonColor,
                        wipeDuration: widget.voiceSendWipeDuration,
                        showWaveform: false,
                        waveformLevel: 0,
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
    required this.backgroundColor,
    required this.wipeColor,
    this.wipeDuration = const Duration(milliseconds: 1040),
    this.waveformColor = Colors.white,
    required this.waveformLevel,
    this.showWaveform = true,
  });

  final Widget child;
  final bool sendWipe;
  final Color backgroundColor;
  final Color wipeColor;
  final Duration wipeDuration;
  final Color waveformColor;
  final double waveformLevel;
  final bool showWaveform;

  @override
  State<_RecordingButton> createState() => _RecordingButtonState();
}

class _RecordingButtonState extends State<_RecordingButton>
    with TickerProviderStateMixin {
  static const _waveSampleRate = 96.0;
  static const _waveSampleCount = 360;

  late final AnimationController _wipeController;
  late final Animation<double> _wipeAnimation;
  late final AnimationController _waveController;
  final _waveRandom = math.Random();
  final _waveSamples = List<double>.filled(_waveSampleCount, 0, growable: true);
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
      _wipeController.value = 1;
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
    } else if (!widget.sendWipe && oldWidget.sendWipe) {
      _wipeController.value = 0;
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
    final responsiveLevel = math.pow(level, 0.55).toDouble();
    _smoothedWaveLevel += (responsiveLevel - _smoothedWaveLevel) * 0.5;
    final envelope = 0.05 + _smoothedWaveLevel * 0.95;
    final previous = _waveSamples.isEmpty ? 0.0 : _waveSamples.last;
    final noise = _waveRandom.nextDouble() * 2 - 1;
    _waveSamples.add((previous * 0.28 + noise * 0.72) * envelope);
    if (_waveSamples.length > _waveSampleCount) {
      _waveSamples.removeRange(0, _waveSamples.length - _waveSampleCount);
    }
  }

  void _seedWaveSamples() {
    _waveSamples
      ..clear()
      ..addAll(
        List<double>.generate(_waveSampleCount, (_) {
          return (_waveRandom.nextDouble() * 2 - 1) * 0.04;
        }),
      );
  }

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
                      progress: _waveController.value,
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
                foregroundColor: Colors.white,
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
    final point = points[i];
    if (i == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
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
  final width = size.width;
  final values = samples.isEmpty ? const [0.0] : samples;
  final sampleCount = values.length;
  final step = sampleCount <= 1 ? width : width / (sampleCount - 1);
  final amplitude = size.height * 0.36;
  final scroll = progress * step;
  final points = <Offset>[];

  for (var i = 0; i < sampleCount; i++) {
    final x = width - (sampleCount - 1 - i) * step - scroll;
    final y = centerY - values[i].clamp(-1.0, 1.0) * amplitude;
    points.add(Offset(x, y));
  }

  return points;
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
    final transcribingLabel = widget.message.text.trim().isEmpty
        ? 'Transcribing'
        : widget.message.text.trim();

    if (transcribing) {
      return SizedBox(
        height: 48,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: outgoingBubbleColor,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Center(
            child: Text(
              transcribingLabel,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

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
            color: outgoingBubbleColor,
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
                  color: colorScheme.onPrimaryContainer,
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
          if (processing)
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
