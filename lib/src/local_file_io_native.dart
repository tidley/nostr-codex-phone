import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readLocalFileBytes(String path) => File(path).readAsBytes();

Future<void> deleteLocalFile(String path) async {
  try {
    await File(path).delete();
  } catch (_) {}
}

Future<void> writeLocalTextFile(String path, String contents) =>
    File(path).writeAsString(contents);

Future<Duration> probeWebSocketRelay(String relay) async {
  final stopwatch = Stopwatch()..start();
  final socket = await WebSocket.connect(relay);
  await socket.close(WebSocketStatus.normalClosure, 'relay probe complete');
  stopwatch.stop();
  return stopwatch.elapsed;
}
