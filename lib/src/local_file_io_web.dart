import 'dart:typed_data';

Future<Uint8List> readLocalFileBytes(String path) =>
    Future.error(UnsupportedError('Browser file paths are not readable'));

Future<void> deleteLocalFile(String path) async {}

Future<void> writeLocalTextFile(String path, String contents) =>
    Future.error(UnsupportedError('Browser file paths are not writable'));

Future<Duration> probeWebSocketRelay(String relay) => Future.error(
  UnsupportedError('Relay probes are unavailable in the browser'),
);
