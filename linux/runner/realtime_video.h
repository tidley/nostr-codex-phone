#ifndef RUNNER_REALTIME_VIDEO_H_
#define RUNNER_REALTIME_VIDEO_H_

#include <flutter_linux/flutter_linux.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <thread>
#include <string>
#include <unordered_map>
#include <vector>

class RealtimeVideo {
 public:
  RealtimeVideo(FlBinaryMessenger* messenger, FlTextureRegistrar* textures);
  ~RealtimeVideo();

  RealtimeVideo(const RealtimeVideo&) = delete;
  RealtimeVideo& operator=(const RealtimeVideo&) = delete;

  void Dispose();

 private:
  class Renderer;

  static void MethodCall(FlMethodChannel* channel,
                         FlMethodCall* method_call,
                         gpointer user_data);
  static FlMethodErrorResponse* Listen(FlEventChannel* channel,
                                        FlValue* args,
                                        gpointer user_data);
  static FlMethodErrorResponse* Cancel(FlEventChannel* channel,
                                        FlValue* args,
                                        gpointer user_data);

  bool StartCapture(const char* source, const char** error_message);
  void StopCapture();
  void CaptureLoop(int output_fd);
  void EmitAccessUnit(const std::vector<uint8_t>& access_unit);
  int64_t CreateRenderer(const char** error_message);
  bool PushFragment(int64_t texture_id, const uint8_t* fragment, size_t length,
                    const char** error_message);
  void ReleaseRenderer(int64_t texture_id);

  FlMethodChannel* method_channel_ = nullptr;
  FlEventChannel* frame_channel_ = nullptr;
  FlTextureRegistrar* textures_ = nullptr;
  std::atomic<bool> listening_{false};
  std::atomic<bool> capturing_{false};
  int capture_pid_ = -1;
  int capture_output_fd_ = -1;
  std::string screen_display_;
  std::thread capture_thread_;
  uint16_t frame_sequence_ = 0;
  std::mutex renderers_mutex_;
  std::unordered_map<int64_t, std::unique_ptr<Renderer>> renderers_;
};

#endif  // RUNNER_REALTIME_VIDEO_H_
