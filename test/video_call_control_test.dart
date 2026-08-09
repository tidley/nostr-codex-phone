import 'package:crew/src/video_call_control.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encodes a bounded keyframe request for its call', () {
    expect(
      videoKeyFrameRequest('call-123'),
      '{"action":"video_keyframe_request","call_id":"call-123"}',
    );
  });

  test('recognizes only a keyframe request for the active call', () {
    expect(
      isVideoKeyFrameRequest(
        '{"action":"video_keyframe_request","call_id":"call-123"}',
        'call-123',
      ),
      isTrue,
    );
    expect(
      isVideoKeyFrameRequest(
        '{"action":"video_keyframe_request","call_id":"other"}',
        'call-123',
      ),
      isFalse,
    );
    expect(isVideoKeyFrameRequest('not-json', 'call-123'), isFalse);
  });
}
