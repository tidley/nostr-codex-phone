import 'package:nostr_codex_phone/src/compact_identifier.dart';

class RepoTarget {
  const RepoTarget({
    required this.id,
    required this.name,
    required this.pubkey,
    required this.relays,
    this.workdir,
    this.parentPubkey,
    this.parentRelays,
    this.parentWorkdir,
    this.parentName,
    this.pairingSecret,
    this.isMasterSession = false,
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
  final String? pairingSecret;
  final bool isMasterSession;

  String get displayName {
    final cleaned = name.trim();
    if (cleaned.isNotEmpty) return cleaned;
    return compactIdentifier(pubkey);
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
    if (pairingSecret != null && pairingSecret!.trim().isNotEmpty)
      'pairing_secret': pairingSecret,
    if (isMasterSession) 'is_master_session': true,
  };

  RepoTarget copyWith({
    String? id,
    String? name,
    String? pubkey,
    List<String>? relays,
    String? workdir,
    String? parentPubkey,
    List<String>? parentRelays,
    String? parentWorkdir,
    String? parentName,
    String? pairingSecret,
    bool? isMasterSession,
    bool clearPairingSecret = false,
  }) {
    return RepoTarget(
      id: id ?? this.id,
      name: name ?? this.name,
      pubkey: pubkey ?? this.pubkey,
      relays: relays ?? this.relays,
      workdir: workdir ?? this.workdir,
      parentPubkey: parentPubkey ?? this.parentPubkey,
      parentRelays: parentRelays ?? this.parentRelays,
      parentWorkdir: parentWorkdir ?? this.parentWorkdir,
      parentName: parentName ?? this.parentName,
      pairingSecret: clearPairingSecret
          ? null
          : pairingSecret ?? this.pairingSecret,
      isMasterSession: isMasterSession ?? this.isMasterSession,
    );
  }

  static RepoTarget? fromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id']?.toString().trim() ?? '';
    final name = raw['name']?.toString().trim() ?? '';
    final pubkey = raw['pubkey']?.toString().trim() ?? '';
    final workdir = raw['workdir']?.toString().trim();
    final parentPubkey = raw['parent_pubkey']?.toString().trim();
    final parentWorkdir = raw['parent_workdir']?.toString().trim();
    final parentName = raw['parent_name']?.toString().trim();
    final pairingSecret = raw['pairing_secret']?.toString().trim();
    final isMasterSession = raw['is_master_session'] == true;
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
    return RepoTarget(
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
      pairingSecret: pairingSecret == null || pairingSecret.isEmpty
          ? null
          : pairingSecret,
      isMasterSession: isMasterSession,
    );
  }
}
