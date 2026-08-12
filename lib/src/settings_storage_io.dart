import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

bool isLinuxKeyringLocked(Object error) =>
    error is PlatformException && error.code == 'KeyringLocked';

abstract interface class SecureSettingsStorage {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String? value});
  Future<void> delete({required String key});
}

class _FlutterSecureSettingsStorage implements SecureSettingsStorage {
  const _FlutterSecureSettingsStorage();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String? value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// Uses Secret Service normally, with a user-only file fallback if it is locked.
class SettingsStorage {
  factory SettingsStorage({
    SecureSettingsStorage? secureStorage,
    Future<Directory> Function()? applicationSupportDirectory,
  }) {
    if (secureStorage == null && applicationSupportDirectory == null) {
      return _shared;
    }
    return SettingsStorage._(
      secureStorage: secureStorage ?? const _FlutterSecureSettingsStorage(),
      applicationSupportDirectory:
          applicationSupportDirectory ?? getApplicationSupportDirectory,
    );
  }

  SettingsStorage._({
    required SecureSettingsStorage secureStorage,
    required Future<Directory> Function() applicationSupportDirectory,
  }) : _secureStorage = secureStorage,
       _applicationSupportDirectory = applicationSupportDirectory;

  static final _shared = SettingsStorage._(
    secureStorage: const _FlutterSecureSettingsStorage(),
    applicationSupportDirectory: getApplicationSupportDirectory,
  );

  final SecureSettingsStorage _secureStorage;
  final Future<Directory> Function() _applicationSupportDirectory;
  bool _useLinuxFallback = false;
  Future<void> _fallbackOperations = Future.value();
  Future<void> _operations = Future.value();
  final Map<String, String?> _knownValues = {};

  Future<String?> read({required String key}) => _serialize(() async {
    final value = await _run(
      () => _secureStorage.read(key: key),
      () async => (await _readFallback())[key],
    );
    _knownValues[key] = value;
    return value;
  });

  Future<void> write({required String key, required String? value}) =>
      _serialize(() async {
        if (_knownValues[key] == value && _knownValues.containsKey(key)) return;
        await _run(
          () => _secureStorage.write(key: key, value: value),
          () async {
            final values = await _readFallback();
            if (value == null) {
              values.remove(key);
            } else {
              values[key] = value;
            }
            await _writeFallback(values);
          },
        );
        _knownValues[key] = value;
      });

  Future<void> delete({required String key}) => _serialize(() async {
    if (_knownValues[key] == null && _knownValues.containsKey(key)) return;
    await _run(() => _secureStorage.delete(key: key), () async {
      final values = await _readFallback();
      values.remove(key);
      await _writeFallback(values);
    });
    _knownValues[key] = null;
  });

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<T> _run<T>(
    Future<T> Function() secureOperation,
    Future<T> Function() fallbackOperation,
  ) async {
    if (_useLinuxFallback) return _runFallback(fallbackOperation);
    try {
      return await secureOperation();
    } on PlatformException catch (error) {
      if (!Platform.isLinux || !isLinuxKeyringLocked(error)) rethrow;
      _useLinuxFallback = true;
      return _runFallback(fallbackOperation);
    }
  }

  Future<T> _runFallback<T>(Future<T> Function() operation) {
    final result = _fallbackOperations.then((_) => operation());
    _fallbackOperations = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<File> _fallbackFile() async {
    final supportDirectory = await _applicationSupportDirectory();
    final directory = Directory('${supportDirectory.path}/settings-fallback');
    await directory.create(recursive: true);
    await _setPermissions(directory.path, '700');
    return File('${directory.path}/settings.json');
  }

  Future<Map<String, String>> _readFallback() async {
    final file = await _fallbackFile();
    if (!await file.exists()) return {};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return {};
    return {
      for (final entry in decoded.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  Future<void> _writeFallback(Map<String, String> values) async {
    final file = await _fallbackFile();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(values), flush: true);
    await _setPermissions(temporary.path, '600');
    await temporary.rename(file.path);
  }

  Future<void> _setPermissions(String path, String mode) async {
    final result = await Process.run('/bin/chmod', [mode, path]);
    if (result.exitCode != 0) {
      throw FileSystemException('Could not secure fallback settings', path);
    }
  }
}
