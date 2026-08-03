import 'dart:async';
import 'package:flutter/services.dart';

/// Android- and Linux-native H.264 capture and Flutter texture decode bridge.
class RealtimeVideo {
  RealtimeVideo._();

  static final instance = RealtimeVideo._();
  static const _methods = MethodChannel('nostr_codex_phone/realtime_video');
  static const _frames = EventChannel(
    'nostr_codex_phone/realtime_video_frames',
  );

  Stream<Uint8List>? _frameStream;
  Stream<Uint8List> get frames => _frameStream ??= _frames
      .receiveBroadcastStream()
      .where((event) => event != null)
      .map((event) => Uint8List.fromList(event as Uint8List));

  Future<void> startCapture() => _methods.invokeMethod<void>('startCapture');
  Future<void> stopCapture() => _methods.invokeMethod<void>('stopCapture');
  Future<int> createRenderer() async =>
      (await _methods.invokeMethod<num>('createRenderer'))!.toInt();
  Future<void> releaseRenderer(int textureId) =>
      _methods.invokeMethod<void>('releaseRenderer', {'textureId': textureId});
  Future<void> pushFragment(int textureId, Uint8List fragment) =>
      _methods.invokeMethod<void>('pushFragment', {
        'textureId': textureId,
        'fragment': fragment,
      });
  Future<void> dispose() => _methods.invokeMethod<void>('dispose');
}
