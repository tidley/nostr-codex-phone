import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'workspace_models.dart';

/// Stores durable workspace data locally so relay availability is not required
/// to reopen a conversation after an application restart.
class WorkspaceCache {
  static const _schemaVersion = 1;

  Future<WorkspaceState?> load({
    required String localPubkey,
    required String servicePubkey,
  }) async {
    Database? database;
    try {
      database = await _open();
      final rows = database.select(
        'SELECT snapshot_json FROM workspace_cache WHERE cache_key = ?',
        [_cacheKey(localPubkey, servicePubkey)],
      );
      if (rows.isEmpty) return null;
      final decoded = jsonDecode(rows.single['snapshot_json'] as String);
      if (decoded is! Map) {
        throw const FormatException('Invalid workspace cache');
      }
      return WorkspaceState()
        ..apply({'workspace_update': Map<String, dynamic>.from(decoded)});
    } catch (_) {
      try {
        database?.execute('DELETE FROM workspace_cache WHERE cache_key = ?', [
          _cacheKey(localPubkey, servicePubkey),
        ]);
      } catch (_) {
        // A broken cache must not block connection or workspace startup.
      }
      return null;
    } finally {
      database?.dispose();
    }
  }

  Future<void> save({
    required String localPubkey,
    required String servicePubkey,
    required WorkspaceState workspace,
  }) async {
    final database = await _open();
    try {
      database.execute(
        '''INSERT INTO workspace_cache
          (cache_key, schema_version, snapshot_json, updated_at)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(cache_key) DO UPDATE SET
            schema_version = excluded.schema_version,
            snapshot_json = excluded.snapshot_json,
            updated_at = excluded.updated_at''',
        [
          _cacheKey(localPubkey, servicePubkey),
          _schemaVersion,
          jsonEncode(workspace.toSnapshotJson()),
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
    } finally {
      database.dispose();
    }
  }

  Future<Database> _open() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final databaseFile = File(
      '${directory.path}${Platform.pathSeparator}workspace-cache.sqlite',
    );
    final existed = await databaseFile.exists();
    final database = sqlite3.open(databaseFile.path);
    database.execute('PRAGMA journal_mode=WAL');
    database.execute('PRAGMA busy_timeout=3000');
    database.execute('''CREATE TABLE IF NOT EXISTS workspace_cache (
      cache_key TEXT PRIMARY KEY,
      schema_version INTEGER NOT NULL,
      snapshot_json TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )''');
    if (Platform.isLinux && !existed) {
      await Process.run('/bin/chmod', ['600', databaseFile.path]);
    }
    return database;
  }

  String _cacheKey(String localPubkey, String servicePubkey) =>
      '${localPubkey.trim().toLowerCase()}:${servicePubkey.trim().toLowerCase()}';
}
