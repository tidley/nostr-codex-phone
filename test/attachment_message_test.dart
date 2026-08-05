import 'package:flutter_test/flutter_test.dart';
import 'package:crew/src/conversation_message.dart';

void main() {
  test('extracts direct audio attachment metadata', () {
    final attachments = attachmentsFromWireJson(
      'audio',
      '{"audio":{"url":"https://cdn.example/audio","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":4,"type":"audio/wav","name":"voice.wav"}}',
    );

    expect(attachments, hasLength(1));
    expect(attachments.single.name, 'voice.wav');
  });

  test('extracts generic media bundle attachments', () {
    final attachments = attachmentsFromWireJson(
      'media_bundle',
      '{"media_bundle":{"attachments":[{"url":"https://cdn.example/doc","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","size":4,"type":"application/pdf","name":"report.pdf"}]}}',
    );

    expect(attachments.single.mediaType, 'application/pdf');
  });

  test('ignores malformed attachment metadata', () {
    expect(attachmentsFromWireJson('audio', '{not json}'), isEmpty);
  });
}
