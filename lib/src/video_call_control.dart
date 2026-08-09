import 'dart:convert';

String videoKeyFrameRequest(String callId) =>
    jsonEncode({'action': 'video_keyframe_request', 'call_id': callId});

bool isVideoKeyFrameRequest(String? frame, String callId) {
  if (frame == null) return false;
  try {
    final value = jsonDecode(frame);
    return value is Map<String, dynamic> &&
        value['action'] == 'video_keyframe_request' &&
        value['call_id'] == callId;
  } catch (_) {
    return false;
  }
}
