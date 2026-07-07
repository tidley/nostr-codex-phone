import 'package:record/record.dart';

enum VoiceFormat { opus, wav }

class VoiceRecordingFormat {
  const VoiceRecordingFormat({
    required this.format,
    required this.extension,
    required this.contentType,
    required this.encoder,
    required this.bitRate,
  });

  final VoiceFormat format;
  final String extension;
  final String contentType;
  final AudioEncoder encoder;
  final int bitRate;
}

const opusVoiceFormat = VoiceRecordingFormat(
  format: VoiceFormat.opus,
  extension: 'ogg',
  contentType: 'audio/ogg',
  encoder: AudioEncoder.opus,
  bitRate: 32000,
);

const wavVoiceFormat = VoiceRecordingFormat(
  format: VoiceFormat.wav,
  extension: 'wav',
  contentType: 'audio/wav',
  encoder: AudioEncoder.wav,
  bitRate: 256000,
);

const minimumVoiceRecordingDuration = Duration(seconds: 1);
const defaultVoiceTranscriptionEstimate = Duration(seconds: 8);

Duration estimateVoiceTranscriptionDuration(Duration? audioDuration) {
  if (audioDuration == null) return defaultVoiceTranscriptionEstimate;
  final seconds = audioDuration.inMilliseconds / 1000;
  final estimatedSeconds = 4 + seconds * 0.8 + seconds * seconds * 0.004;
  final clampedMilliseconds = (estimatedSeconds * 1000).round().clamp(
    4000,
    90000,
  );
  return Duration(milliseconds: clampedMilliseconds);
}
