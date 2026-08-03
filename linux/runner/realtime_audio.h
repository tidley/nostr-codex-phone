#ifndef RUNNER_REALTIME_AUDIO_H_
#define RUNNER_REALTIME_AUDIO_H_

#include <flutter_linux/flutter_linux.h>

#include <atomic>
#include <thread>

struct _snd_pcm;
typedef struct _snd_pcm snd_pcm_t;

class RealtimeAudio {
 public:
  explicit RealtimeAudio(FlBinaryMessenger* messenger);
  ~RealtimeAudio();

  RealtimeAudio(const RealtimeAudio&) = delete;
  RealtimeAudio& operator=(const RealtimeAudio&) = delete;

  void Dispose();

 private:
  static void MethodCall(FlMethodChannel* channel,
                         FlMethodCall* method_call,
                         gpointer user_data);
  static FlMethodErrorResponse* Listen(FlEventChannel* channel,
                                        FlValue* args,
                                        gpointer user_data);
  static FlMethodErrorResponse* Cancel(FlEventChannel* channel,
                                        FlValue* args,
                                        gpointer user_data);

  bool StartCapture(const char** error_message);
  void StopCapture();
  void CaptureLoop(snd_pcm_t* capture);
  int PlayPcm(const uint8_t* pcm, size_t length, const char** error_message);
  void StopPlayback();

  FlMethodChannel* method_channel_ = nullptr;
  FlEventChannel* frame_channel_ = nullptr;
  std::atomic<bool> listening_{false};
  std::atomic<bool> capturing_{false};
  snd_pcm_t* capture_ = nullptr;
  std::thread capture_thread_;
  snd_pcm_t* playback_ = nullptr;
};

#endif  // RUNNER_REALTIME_AUDIO_H_
