import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Browser settings are retained by the browser's origin-scoped storage.
class SettingsStorage {
  static const _storage = FlutterSecureStorage();

  Future<String?> read({required String key}) => _storage.read(key: key);

  Future<void> write({required String key, required String? value}) =>
      _storage.write(key: key, value: value);

  Future<void> delete({required String key}) => _storage.delete(key: key);
}
