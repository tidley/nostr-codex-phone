class ToolResultPayload {
  const ToolResultPayload({
    required this.tool,
    required this.requestId,
    required this.workdir,
    required this.data,
  });

  final String tool;
  final String requestId;
  final String workdir;
  final Map<String, dynamic> data;

  String? get error {
    final value = data['error']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  static ToolResultPayload? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final tool = raw['tool']?.toString().trim() ?? '';
    final requestId = raw['request_id']?.toString().trim() ?? '';
    final workdir = raw['workdir']?.toString().trim() ?? '';
    final dataRaw = raw['data'];
    if (tool.isEmpty || requestId.isEmpty || dataRaw is! Map) return null;
    return ToolResultPayload(
      tool: tool,
      requestId: requestId,
      workdir: workdir,
      data: Map<String, dynamic>.from(dataRaw),
    );
  }
}

class GitFileStatus {
  const GitFileStatus({
    required this.path,
    required this.indexStatus,
    required this.worktreeStatus,
    required this.staged,
    required this.untracked,
  });

  final String path;
  final String indexStatus;
  final String worktreeStatus;
  final bool staged;
  final bool untracked;

  String get statusLabel {
    if (untracked) return 'Untracked';
    if (indexStatus == 'A') return 'Added';
    if (indexStatus == 'D' || worktreeStatus == 'D') return 'Deleted';
    if (indexStatus == 'R') return 'Renamed';
    if (staged && worktreeStatus != ' ') return 'Staged + modified';
    if (staged) return 'Staged';
    return 'Modified';
  }

  static GitFileStatus? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final path = raw['path']?.toString().trim() ?? '';
    if (path.isEmpty) return null;
    return GitFileStatus(
      path: path,
      indexStatus: raw['index_status']?.toString() ?? ' ',
      worktreeStatus: raw['worktree_status']?.toString() ?? ' ',
      staged: raw['staged'] == true,
      untracked: raw['untracked'] == true,
    );
  }
}

class GitStatusResult {
  const GitStatusResult({
    required this.branch,
    required this.clean,
    required this.latestHash,
    required this.latestSubject,
    required this.files,
  });

  final String branch;
  final bool clean;
  final String latestHash;
  final String latestSubject;
  final List<GitFileStatus> files;

  factory GitStatusResult.fromPayload(ToolResultPayload payload) {
    final latest = payload.data['latest'];
    final rawFiles = payload.data['files'];
    return GitStatusResult(
      branch: payload.data['branch']?.toString().trim() ?? '',
      clean: payload.data['clean'] == true,
      latestHash: latest is Map ? latest['hash']?.toString() ?? '' : '',
      latestSubject: latest is Map ? latest['subject']?.toString() ?? '' : '',
      files: rawFiles is Iterable
          ? rawFiles
                .map(GitFileStatus.fromJson)
                .whereType<GitFileStatus>()
                .toList()
          : const [],
    );
  }
}

class DiffFileResult {
  const DiffFileResult({
    required this.path,
    required this.status,
    required this.additions,
    required this.deletions,
    required this.patch,
  });

  final String path;
  final String status;
  final String additions;
  final String deletions;
  final String patch;

  static DiffFileResult? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final path = raw['path']?.toString().trim() ?? '';
    if (path.isEmpty) return null;
    return DiffFileResult(
      path: path,
      status: raw['status']?.toString() ?? 'M',
      additions: raw['additions']?.toString() ?? '0',
      deletions: raw['deletions']?.toString() ?? '0',
      patch: raw['patch']?.toString() ?? '',
    );
  }
}

class DiffResult {
  const DiffResult(this.files);

  final List<DiffFileResult> files;

  factory DiffResult.fromPayload(ToolResultPayload payload) {
    final rawFiles = payload.data['files'];
    return DiffResult(
      rawFiles is Iterable
          ? rawFiles
                .map(DiffFileResult.fromJson)
                .whereType<DiffFileResult>()
                .toList()
          : const [],
    );
  }
}

class FileContentResult {
  const FileContentResult({
    required this.path,
    required this.content,
    required this.lineCount,
    required this.truncated,
  });

  final String path;
  final String content;
  final int lineCount;
  final bool truncated;

  factory FileContentResult.fromPayload(ToolResultPayload payload) {
    return FileContentResult(
      path: payload.data['path']?.toString() ?? '',
      content: payload.data['content']?.toString() ?? '',
      lineCount:
          int.tryParse(payload.data['line_count']?.toString() ?? '') ?? 0,
      truncated: payload.data['truncated'] == true,
    );
  }
}
