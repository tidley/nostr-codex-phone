import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crew/src/settings_storage.dart';

class _LockedSecureStorage implements SecureSettingsStorage {
  int readCalls = 0;
  int writeCalls = 0;
  int deleteCalls = 0;

  @override
  Future<void> delete({required String key}) async {
    deleteCalls++;
    throw PlatformException(code: 'KeyringLocked');
  }

  @override
  Future<String?> read({required String key}) async {
    readCalls++;
    throw PlatformException(code: 'KeyringLocked');
  }

  @override
  Future<void> write({required String key, required String? value}) async {
    writeCalls++;
    throw PlatformException(code: 'KeyringLocked');
  }
}

void main() {
  test('recognizes only the Linux Secret Service locked error', () {
    expect(
      isLinuxKeyringLocked(PlatformException(code: 'KeyringLocked')),
      isTrue,
    );
    expect(
      isLinuxKeyringLocked(PlatformException(code: 'UnexpectedError')),
      isFalse,
    );
    expect(isLinuxKeyringLocked(StateError('keyring locked')), isFalse);
  });

  test('recognizes only the unavailable macOS Keychain error', () {
    expect(
      isMacOSKeychainUnavailable(
        PlatformException(
          code: 'Unexpected security result code',
          details: -34018,
        ),
      ),
      isTrue,
    );
    expect(
      isMacOSKeychainUnavailable(PlatformException(code: 'UnexpectedError')),
      isFalse,
    );
  });

  test('uses the file fallback after a locked keyring read', () async {
    final directory = await Directory.systemTemp.createTemp(
      'settings-storage-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final secureStorage = _LockedSecureStorage();
    final storage = SettingsStorage(
      secureStorage: secureStorage,
      applicationSupportDirectory: () async => directory,
    );

    expect(await storage.read(key: 'secret'), isNull);
    expect(secureStorage.readCalls, 1);
  }, skip: !Platform.isLinux);

  test('uses the file fallback after a locked keyring write', () async {
    final directory = await Directory.systemTemp.createTemp(
      'settings-storage-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final secureStorage = _LockedSecureStorage();
    final storage = SettingsStorage(
      secureStorage: secureStorage,
      applicationSupportDirectory: () async => directory,
    );

    await storage.write(key: 'secret', value: 'generated-key');
    expect(await storage.read(key: 'secret'), 'generated-key');

    expect(secureStorage.writeCalls, 1);
    expect(secureStorage.readCalls, 0);
    expect(secureStorage.deleteCalls, 0);
  }, skip: !Platform.isLinux);

  test(
    'uses the file fallback after a locked keyring delete',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'settings-storage-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final fallbackDirectory = Directory(
        '${directory.path}/settings-fallback',
      );
      await fallbackDirectory.create();
      await File(
        '${fallbackDirectory.path}/settings.json',
      ).writeAsString('{"secret":"generated-key"}');
      final secureStorage = _LockedSecureStorage();
      final storage = SettingsStorage(
        secureStorage: secureStorage,
        applicationSupportDirectory: () async => directory,
      );

      await storage.delete(key: 'secret');
      expect(await storage.read(key: 'secret'), isNull);
      expect(secureStorage.deleteCalls, 1);
      expect(secureStorage.readCalls, 0);
    },
    skip: !Platform.isLinux,
  );

  test('serializes concurrent fallback writes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'settings-storage-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final storage = SettingsStorage(
      secureStorage: _LockedSecureStorage(),
      applicationSupportDirectory: () async => directory,
    );

    await Future.wait([
      storage.write(key: 'first', value: 'one'),
      storage.write(key: 'second', value: 'two'),
    ]);

    expect(await storage.read(key: 'first'), 'one');
    expect(await storage.read(key: 'second'), 'two');
  }, skip: !Platform.isLinux);
}
