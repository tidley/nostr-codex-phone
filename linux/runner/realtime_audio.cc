#include "realtime_audio.h"

#include <alsa/asoundlib.h>

#include <cerrno>
#include <cstring>
#include <memory>
#include <vector>

namespace {

constexpr unsigned int kSampleRate = 48000;
constexpr snd_pcm_uframes_t kFrameSamples = kSampleRate / 50;
constexpr size_t kFrameBytes = kFrameSamples * sizeof(int16_t);

void RespondError(FlMethodCall* call, const char* code, const char* message) {
  g_autoptr(GError) error = nullptr;
  fl_method_call_respond_error(call, code, message, nullptr, &error);
  if (error != nullptr) g_warning("RealtimeAudio response failed: %s", error->message);
}

bool ConfigurePcm(snd_pcm_t* pcm) {
  return snd_pcm_set_params(pcm, SND_PCM_FORMAT_S16_LE,
                            SND_PCM_ACCESS_RW_INTERLEAVED, 1, kSampleRate, 1,
                            80000) == 0;
}

struct PendingFrame {
  FlEventChannel* channel;
  std::vector<uint8_t> bytes;
};

gboolean SendFrame(gpointer user_data) {
  std::unique_ptr<PendingFrame> frame(static_cast<PendingFrame*>(user_data));
  g_autoptr(FlValue) value =
      fl_value_new_uint8_list(frame->bytes.data(), frame->bytes.size());
  g_autoptr(GError) error = nullptr;
  if (!fl_event_channel_send(frame->channel, value, nullptr, &error)) {
    g_warning("RealtimeAudio frame delivery failed: %s", error->message);
  }
  g_object_unref(frame->channel);
  return G_SOURCE_REMOVE;
}

}  // namespace

RealtimeAudio::RealtimeAudio(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) method_codec = fl_standard_method_codec_new();
  method_channel_ = fl_method_channel_new(
      messenger, "nostr_codex_phone/realtime_audio", FL_METHOD_CODEC(method_codec));
  fl_method_channel_set_method_call_handler(method_channel_, MethodCall, this, nullptr);

  g_autoptr(FlStandardMethodCodec) frame_codec = fl_standard_method_codec_new();
  frame_channel_ = fl_event_channel_new(
      messenger, "nostr_codex_phone/realtime_audio_frames", FL_METHOD_CODEC(frame_codec));
  fl_event_channel_set_stream_handlers(frame_channel_, Listen, Cancel, this, nullptr);
}

RealtimeAudio::~RealtimeAudio() {
  Dispose();
  g_clear_object(&method_channel_);
  g_clear_object(&frame_channel_);
}

void RealtimeAudio::Dispose() {
  StopCapture();
  StopPlayback();
  listening_ = false;
  if (method_channel_ != nullptr) {
    fl_method_channel_set_method_call_handler(method_channel_, nullptr, nullptr, nullptr);
  }
  if (frame_channel_ != nullptr) {
    fl_event_channel_set_stream_handlers(frame_channel_, nullptr, nullptr, nullptr, nullptr);
  }
}

void RealtimeAudio::MethodCall(FlMethodChannel*, FlMethodCall* call,
                               gpointer user_data) {
  auto* self = static_cast<RealtimeAudio*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  if (strcmp(method, "startCapture") == 0) {
    const char* error_message = nullptr;
    if (!self->StartCapture(&error_message)) {
      RespondError(call, self->listening_ ? "capture_init_failed" : "no_frame_listener",
                   error_message);
      return;
    }
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (strcmp(method, "stopCapture") == 0) {
    self->StopCapture();
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (strcmp(method, "playPcm") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    FlValue* pcm = args == nullptr ? nullptr : fl_value_lookup_string(args, "pcm");
    if (pcm == nullptr || fl_value_get_type(pcm) != FL_VALUE_TYPE_UINT8_LIST ||
        fl_value_get_length(pcm) == 0 || fl_value_get_length(pcm) % sizeof(int16_t) != 0) {
      RespondError(call, "invalid_pcm", "pcm must contain complete signed-16-bit samples.");
      return;
    }
    const char* error_message = nullptr;
    int written = self->PlayPcm(fl_value_get_uint8_list(pcm), fl_value_get_length(pcm),
                                &error_message);
    if (written < 0) {
      RespondError(call, "playback_write_failed", error_message);
      return;
    }
    g_autoptr(FlValue) result = fl_value_new_int(written);
    fl_method_call_respond_success(call, result, nullptr);
  } else if (strcmp(method, "stopPlayback") == 0) {
    self->StopPlayback();
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (strcmp(method, "dispose") == 0) {
    self->Dispose();
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

FlMethodErrorResponse* RealtimeAudio::Listen(FlEventChannel*, FlValue*, gpointer user_data) {
  static_cast<RealtimeAudio*>(user_data)->listening_ = true;
  return nullptr;
}

FlMethodErrorResponse* RealtimeAudio::Cancel(FlEventChannel*, FlValue*, gpointer user_data) {
  auto* self = static_cast<RealtimeAudio*>(user_data);
  self->listening_ = false;
  self->StopCapture();
  return nullptr;
}

bool RealtimeAudio::StartCapture(const char** error_message) {
  if (capturing_) return true;
  if (!listening_) {
    *error_message = "Listen for PCM frames before starting capture.";
    return false;
  }
  snd_pcm_t* capture = nullptr;
  int result = snd_pcm_open(&capture, "default", SND_PCM_STREAM_CAPTURE, 0);
  if (result < 0 || !ConfigurePcm(capture)) {
    if (capture != nullptr) snd_pcm_close(capture);
    *error_message = "ALSA could not initialize 48 kHz mono PCM capture.";
    return false;
  }
  capture_ = capture;
  capturing_ = true;
  capture_thread_ = std::thread(&RealtimeAudio::CaptureLoop, this, capture);
  return true;
}

void RealtimeAudio::StopCapture() {
  capturing_ = false;
  if (capture_ != nullptr) snd_pcm_drop(capture_);
  if (capture_thread_.joinable()) capture_thread_.join();
  if (capture_ != nullptr) {
    snd_pcm_close(capture_);
    capture_ = nullptr;
  }
}

void RealtimeAudio::CaptureLoop(snd_pcm_t* capture) {
  std::vector<uint8_t> frame(kFrameBytes);
  while (capturing_) {
    snd_pcm_sframes_t read = snd_pcm_readi(capture, frame.data(), kFrameSamples);
    if (read == static_cast<snd_pcm_sframes_t>(kFrameSamples)) {
      if (listening_) {
        auto* pending = new PendingFrame{FL_EVENT_CHANNEL(g_object_ref(frame_channel_)), frame};
        g_main_context_invoke(nullptr, SendFrame, pending);
      }
    } else if (read < 0 && read != -EPIPE && capturing_) {
      snd_pcm_recover(capture, static_cast<int>(read), 1);
    }
  }
}

int RealtimeAudio::PlayPcm(const uint8_t* pcm, size_t length, const char** error_message) {
  if (playback_ == nullptr) {
    int result = snd_pcm_open(&playback_, "default", SND_PCM_STREAM_PLAYBACK, 0);
    if (result < 0 || !ConfigurePcm(playback_)) {
      if (playback_ != nullptr) snd_pcm_close(playback_);
      playback_ = nullptr;
      *error_message = "ALSA could not initialize 48 kHz mono PCM playback.";
      return -1;
    }
  }
  snd_pcm_sframes_t written = snd_pcm_writei(playback_, pcm, length / sizeof(int16_t));
  if (written < 0) {
    written = snd_pcm_recover(playback_, static_cast<int>(written), 1);
    if (written >= 0) written = snd_pcm_writei(playback_, pcm, length / sizeof(int16_t));
  }
  if (written < 0) {
    *error_message = snd_strerror(static_cast<int>(written));
    return -1;
  }
  return static_cast<int>(written * sizeof(int16_t));
}

void RealtimeAudio::StopPlayback() {
  if (playback_ == nullptr) return;
  snd_pcm_drop(playback_);
  snd_pcm_close(playback_);
  playback_ = nullptr;
}
