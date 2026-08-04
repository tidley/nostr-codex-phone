import 'package:flutter/widgets.dart';

const chatBottomThreshold = 24.0;

bool isChatAtBottom({required double pixels, required double maxScrollExtent}) {
  return maxScrollExtent - pixels <= chatBottomThreshold;
}

bool shouldScrollChatToLatest({required bool isAtBottom, bool force = false}) {
  return force || isAtBottom;
}

Future<void> scrollChatToLatestAfterLayout(
  ScrollController controller, {
  Duration duration = const Duration(milliseconds: 220),
}) async {
  await WidgetsBinding.instance.endOfFrame;
  if (!controller.hasClients) return;

  await controller.animateTo(
    controller.position.maxScrollExtent,
    duration: duration,
    curve: Curves.easeOut,
  );

  // History rows can change the extent while the first animation is running.
  await WidgetsBinding.instance.endOfFrame;
  if (!controller.hasClients) return;
  if (controller.position.pixels >= controller.position.maxScrollExtent) {
    return;
  }
  await controller.animateTo(
    controller.position.maxScrollExtent,
    duration: duration,
    curve: Curves.easeOut,
  );
}
