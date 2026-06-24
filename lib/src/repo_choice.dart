class RepoChoice {
  const RepoChoice({
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

  static RepoChoice? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final name = raw['name']?.toString().trim() ?? '';
    final path = raw['path']?.toString().trim() ?? '';
    final relativePath = raw['relative_path']?.toString().trim() ?? '';
    if (name.isEmpty || path.isEmpty || relativePath.isEmpty) return null;
    return RepoChoice(
      name: name,
      path: path,
      relativePath: relativePath,
      isGitRepo: raw['is_git_repo'] == true,
    );
  }
}
