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

  Future<void> startCapture([String source = 'camera']) =>
      _methods.invokeMethod<void>('startCapture', {'source': source});

  /// Replaces the encoder input without changing the FIPS call or audio stream.
  Future<void> switchCapture(String source) =>
      _methods.invokeMethod<void>('switchCapture', {'source': source});
  Future<void> stopCapture() => _methods.invokeMethod<void>('stopCapture');
  Future<int> createRenderer() async =>
      (await _methods.invokeMethod<num>('createRenderer'))!.toInt();
  Future<void> releaseRenderer(int textureId) =>
      _methods.invokeMethod<void>('releaseRenderer', {'textureId': textureId});

  /// Returns true when a fragment loss requires the sender to emit a keyframe.
  Future<bool> pushFragment(int textureId, Uint8List fragment) async =>
      await _methods.invokeMethod<bool>('pushFragment', {
        'textureId': textureId,
        'fragment': fragment,
      }) ??
      false;
  Future<void> requestKeyFrame() =>
      _methods.invokeMethod<void>('requestKeyFrame');
  Future<void> dispose() => _methods.invokeMethod<void>('dispose');
}
