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
