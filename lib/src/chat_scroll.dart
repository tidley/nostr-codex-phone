const chatBottomThreshold = 24.0;

bool isChatAtBottom({required double pixels, required double maxScrollExtent}) {
  return maxScrollExtent - pixels <= chatBottomThreshold;
}

bool shouldScrollChatToLatest({required bool isAtBottom, bool force = false}) {
  return force || isAtBottom;
}
