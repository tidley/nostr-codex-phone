import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'workspace_models.dart';

/// Stores workspace snapshots in origin-scoped browser storage.
class WorkspaceCache {
  static const _storage = FlutterSecureStorage();
  static const _prefix = 'workspace_cache:';

  Future<WorkspaceState?> load({
    required String localPubkey,
    required String servicePubkey,
  }) async {
    final key = _key(localPubkey, servicePubkey);
    try {
      final raw = await _storage.read(key: key);
      if (raw == null) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map)
        throw const FormatException('Invalid workspace cache');
      return WorkspaceState()
        ..apply({'workspace_update': Map<String, dynamic>.from(decoded)});
    } catch (_) {
      await _storage.delete(key: key);
      return null;
    }
  }

  Future<void> save({
    required String localPubkey,
    required String servicePubkey,
    required WorkspaceState workspace,
  }) => _storage.write(
    key: _key(localPubkey, servicePubkey),
    value: jsonEncode(workspace.toSnapshotJson()),
  );

  String _key(String localPubkey, String servicePubkey) =>
      '$_prefix${localPubkey.trim().toLowerCase()}:${servicePubkey.trim().toLowerCase()}';
}
