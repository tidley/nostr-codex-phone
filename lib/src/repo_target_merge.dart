class RepoTargetMergeIdentity {
  const RepoTargetMergeIdentity({
    required this.id,
    required this.pubkey,
    this.workdir,
  });

  final String id;
  final String pubkey;
  final String? workdir;
}

int repoTargetMergeIndex(
  List<RepoTargetMergeIdentity> existing,
  RepoTargetMergeIdentity incoming,
) {
  final incomingId = incoming.id.trim();
  if (incomingId.isNotEmpty) {
    final idIndex = existing.indexWhere((target) => target.id == incomingId);
    if (idIndex >= 0) return idIndex;
  }

  final incomingWorkdir = incoming.workdir?.trim();
  if (incomingWorkdir != null && incomingWorkdir.isNotEmpty) {
    final workdirIndex = existing.indexWhere(
      (target) => target.workdir?.trim() == incomingWorkdir,
    );
    if (workdirIndex >= 0) return workdirIndex;
  }

  final incomingPubkey = incoming.pubkey.trim();
  if (incomingPubkey.isNotEmpty) {
    return existing.indexWhere((target) => target.pubkey == incomingPubkey);
  }

  return -1;
}
