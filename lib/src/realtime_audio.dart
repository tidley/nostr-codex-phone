import 'dart:async';

import 'package:flutter/services.dart';

/// Android- and Linux-native 48 kHz mono PCM transport for future realtime calls.
///
/// Subscribe to [frames] before calling [startCapture]. Every emitted frame is
/// signed 16-bit little-endian PCM containing exactly 20 ms of microphone audio.
class RealtimeAudio {
  RealtimeAudio._();

  static final instance = RealtimeAudio._();

  static const sampleRate = 48000;
  static const frameDuration = Duration(milliseconds: 20);
  static const frameBytes = 1920;

  static const _methods = MethodChannel('nostr_codex_phone/realtime_audio');
  static const _frames = EventChannel(
    'nostr_codex_phone/realtime_audio_frames',
  );

  Stream<Uint8List>? _frameStream;

  Stream<Uint8List> get frames => _frameStream ??= _frames
      .receiveBroadcastStream()
      .map((event) => Uint8List.fromList(event as Uint8List));

  Future<void> startCapture() => _methods.invokeMethod<void>('startCapture');

  Future<void> stopCapture() => _methods.invokeMethod<void>('stopCapture');

  /// Queues signed 16-bit little-endian mono PCM for immediate playback.
  Future<int> playPcm(Uint8List pcm) async =>
      await _methods.invokeMethod<int>('playPcm', {'pcm': pcm}) ?? 0;

  Future<void> stopPlayback() => _methods.invokeMethod<void>('stopPlayback');

  Future<void> dispose() => _methods.invokeMethod<void>('dispose');
}
