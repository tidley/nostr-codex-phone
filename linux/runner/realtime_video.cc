#include "realtime_video.h"

#include <algorithm>
#include <cerrno>
#include <fcntl.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <utility>

namespace {

constexpr uint32_t kWidth = 640;
constexpr uint32_t kHeight = 360;
constexpr size_t kPixelBytes = kWidth * kHeight * 4;
constexpr size_t kHeaderBytes = 10;
constexpr size_t kMaxFragmentBytes = 1190;
constexpr uint8_t kVideoVersion = 2;
constexpr uint8_t kKeyFrameFlag = 1;
constexpr uint8_t kEndOfFrameFlag = 2;

void RespondError(FlMethodCall* call, const char* code, const char* message) {
  g_autoptr(GError) error = nullptr;
  fl_method_call_respond_error(call, code, message, nullptr, &error);
  if (error != nullptr) g_warning("RealtimeVideo response failed: %s", error->message);
}

int SpawnFfmpeg(const std::vector<const char*>& arguments, int* input_fd,
                int* output_fd) {
  int input[2] = {-1, -1};
  int output[2] = {-1, -1};
  if (input_fd != nullptr && pipe(input) != 0) return -1;
  if (output_fd != nullptr && pipe(output) != 0) {
    if (input_fd != nullptr) {
      close(input[0]);
      close(input[1]);
    }
    return -1;
  }
  const pid_t pid = fork();
  if (pid == 0) {
    if (input_fd != nullptr) {
      dup2(input[0], STDIN_FILENO);
      close(input[0]);
      close(input[1]);
    }
    if (output_fd != nullptr) {
      dup2(output[1], STDOUT_FILENO);
      close(output[0]);
      close(output[1]);
    }
    const int null_fd = open("/dev/null", O_WRONLY);
    if (null_fd >= 0) {
      dup2(null_fd, STDERR_FILENO);
      close(null_fd);
    }
    std::vector<char*> argv;
    argv.reserve(arguments.size() + 1);
    for (const char* argument : arguments) argv.push_back(const_cast<char*>(argument));
    argv.push_back(nullptr);
    execvp(argv[0], argv.data());
    _exit(127);
  }
  if (pid < 0) {
    if (input_fd != nullptr) {
      close(input[0]);
      close(input[1]);
    }
    if (output_fd != nullptr) {
      close(output[0]);
      close(output[1]);
    }
    return -1;
  }
  if (input_fd != nullptr) {
    close(input[0]);
    *input_fd = input[1];
  }
  if (output_fd != nullptr) {
    close(output[1]);
    *output_fd = output[0];
  }
  return pid;
}

void StopFfmpeg(int* pid, int* input_fd, int* output_fd) {
  if (input_fd != nullptr && *input_fd >= 0) close(std::exchange(*input_fd, -1));
  if (output_fd != nullptr && *output_fd >= 0) close(std::exchange(*output_fd, -1));
  if (pid != nullptr && *pid >= 0) {
    kill(*pid, SIGTERM);
    while (waitpid(*pid, nullptr, 0) < 0 && errno == EINTR) {}
    *pid = -1;
  }
}

size_t StartCodeLength(const std::vector<uint8_t>& bytes, size_t offset) {
  if (offset + 3 <= bytes.size() && bytes[offset] == 0 && bytes[offset + 1] == 0 &&
      bytes[offset + 2] == 1) return 3;
  if (offset + 4 <= bytes.size() && bytes[offset] == 0 && bytes[offset + 1] == 0 &&
      bytes[offset + 2] == 0 && bytes[offset + 3] == 1) return 4;
  return 0;
}

size_t FindStartCode(const std::vector<uint8_t>& bytes, size_t offset) {
  for (size_t i = offset; i + 3 <= bytes.size(); ++i) {
    if (StartCodeLength(bytes, i) != 0) return i;
  }
  return bytes.size();
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
    g_warning("RealtimeVideo frame delivery failed: %s", error->message);
  }
  g_object_unref(frame->channel);
  return G_SOURCE_REMOVE;
}

}  // namespace

struct VideoTexture {
  FlPixelBufferTexture parent_instance;
  std::mutex mutex;
  std::vector<uint8_t> pixels = std::vector<uint8_t>(kPixelBytes);
};

struct VideoTextureClass {
  FlPixelBufferTextureClass parent_class;
};

G_DEFINE_TYPE(VideoTexture, video_texture, fl_pixel_buffer_texture_get_type())

static gboolean VideoTextureCopyPixels(FlPixelBufferTexture* texture,
                                       const uint8_t** buffer, uint32_t* width,
                                       uint32_t* height, GError**) {
  auto* video_texture = reinterpret_cast<VideoTexture*>(texture);
  std::lock_guard<std::mutex> lock(video_texture->mutex);
  *buffer = video_texture->pixels.data();
  *width = kWidth;
  *height = kHeight;
  return TRUE;
}

static void video_texture_class_init(VideoTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = VideoTextureCopyPixels;
}

static void video_texture_init(VideoTexture*) {}

class RealtimeVideo::Renderer {
 public:
  explicit Renderer(FlTextureRegistrar* registrar) : registrar_(registrar) {
    texture_ = reinterpret_cast<VideoTexture*>(g_object_new(video_texture_get_type(), nullptr));
  }

  ~Renderer() {
    Stop();
    if (registered_) fl_texture_registrar_unregister_texture(registrar_, FL_TEXTURE(texture_));
    g_object_unref(texture_);
  }

  bool Start(const char** error_message) {
    if (!fl_texture_registrar_register_texture(registrar_, FL_TEXTURE(texture_))) {
      *error_message = "Flutter could not register the video texture.";
      return false;
    }
    registered_ = true;
    pid_ = SpawnFfmpeg({"ffmpeg", "-loglevel", "error", "-f", "h264", "-i", "pipe:0",
                        "-an", "-pix_fmt", "rgba", "-vf", "scale=640:360", "-f",
                        "rawvideo", "pipe:1"},
                       &input_fd_, &output_fd_);
    if (pid_ < 0) {
      *error_message = "Could not start the installed ffmpeg H.264 decoder.";
      return false;
    }
    running_ = true;
    reader_ = std::thread(&Renderer::ReadLoop, this);
    return true;
  }

  int64_t id() const { return fl_texture_get_id(FL_TEXTURE(texture_)); }

  bool PushFragment(const uint8_t* fragment, size_t length) {
    const uint16_t received_sequence =
        (static_cast<uint16_t>(fragment[2]) << 8) | fragment[3];
    const uint16_t received_fragment =
        (static_cast<uint16_t>(fragment[4]) << 8) | fragment[5];
    if (received_sequence != sequence_) {
      sequence_ = received_sequence;
      expected_fragment_ = 0;
      frame_.clear();
    }
    if (received_fragment != expected_fragment_) {
      frame_.clear();
      expected_fragment_ = 0;
      return true;
    }
    frame_.insert(frame_.end(), fragment + kHeaderBytes, fragment + length);
    ++expected_fragment_;
    if ((fragment[1] & kEndOfFrameFlag) == 0) return true;
    const bool written = Push(frame_.data(), frame_.size());
    frame_.clear();
    expected_fragment_ = 0;
    return written;
  }

 private:
  bool Push(const uint8_t* bytes, size_t length) {
    std::lock_guard<std::mutex> lock(input_mutex_);
    size_t offset = 0;
    while (offset < length) {
      const ssize_t written = write(input_fd_, bytes + offset, length - offset);
      if (written <= 0) return false;
      offset += static_cast<size_t>(written);
    }
    return true;
  }

  void Stop() {
    running_ = false;
    StopFfmpeg(&pid_, &input_fd_, &output_fd_);
    if (reader_.joinable()) reader_.join();
  }

  void ReadLoop() {
    std::vector<uint8_t> frame(kPixelBytes);
    size_t offset = 0;
    while (running_) {
      const ssize_t count = read(output_fd_, frame.data() + offset, frame.size() - offset);
      if (count <= 0) break;
      offset += static_cast<size_t>(count);
      if (offset == frame.size()) {
        {
          std::lock_guard<std::mutex> lock(texture_->mutex);
          texture_->pixels = frame;
        }
        fl_texture_registrar_mark_texture_frame_available(registrar_, FL_TEXTURE(texture_));
        offset = 0;
      }
    }
  }

  FlTextureRegistrar* registrar_;
  VideoTexture* texture_;
  bool registered_ = false;
  std::atomic<bool> running_{false};
  int pid_ = -1;
  int input_fd_ = -1;
  int output_fd_ = -1;
  std::mutex input_mutex_;
  std::thread reader_;
  uint16_t sequence_ = 0;
  uint16_t expected_fragment_ = 0;
  std::vector<uint8_t> frame_;
};

RealtimeVideo::RealtimeVideo(FlBinaryMessenger* messenger, FlTextureRegistrar* textures)
    : textures_(textures) {
  g_autoptr(FlStandardMethodCodec) method_codec = fl_standard_method_codec_new();
  method_channel_ = fl_method_channel_new(
      messenger, "nostr_codex_phone/realtime_video", FL_METHOD_CODEC(method_codec));
  fl_method_channel_set_method_call_handler(method_channel_, MethodCall, this, nullptr);
  g_autoptr(FlStandardMethodCodec) frame_codec = fl_standard_method_codec_new();
  frame_channel_ = fl_event_channel_new(
      messenger, "nostr_codex_phone/realtime_video_frames", FL_METHOD_CODEC(frame_codec));
  fl_event_channel_set_stream_handlers(frame_channel_, Listen, Cancel, this, nullptr);
}

RealtimeVideo::~RealtimeVideo() {
  Dispose();
  g_clear_object(&method_channel_);
  g_clear_object(&frame_channel_);
}

void RealtimeVideo::Dispose() {
  StopCapture();
  std::lock_guard<std::mutex> lock(renderers_mutex_);
  renderers_.clear();
  listening_ = false;
  if (method_channel_ != nullptr)
    fl_method_channel_set_method_call_handler(method_channel_, nullptr, nullptr, nullptr);
  if (frame_channel_ != nullptr)
    fl_event_channel_set_stream_handlers(frame_channel_, nullptr, nullptr, nullptr, nullptr);
}

void RealtimeVideo::MethodCall(FlMethodChannel*, FlMethodCall* call, gpointer user_data) {
  auto* self = static_cast<RealtimeVideo*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  if (strcmp(method, "startCapture") == 0) {
    const char* error_message = nullptr;
    FlValue* args = fl_method_call_get_args(call);
    FlValue* source = args == nullptr ? nullptr : fl_value_lookup_string(args, "source");
    const char* capture_source = source == nullptr ? "camera" : fl_value_get_string(source);
    if (!self->StartCapture(capture_source, &error_message)) RespondError(call, "capture_init_failed", error_message);
    else fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (strcmp(method, "switchCapture") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    FlValue* source = args == nullptr ? nullptr : fl_value_lookup_string(args, "source");
    const char* capture_source = source == nullptr ? nullptr : fl_value_get_string(source);
    self->StopCapture();
    const char* error_message = nullptr;
    if (!self->StartCapture(capture_source, &error_message)) RespondError(call, "capture_init_failed", error_message);
    else fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (strcmp(method, "stopCapture") == 0) {
    self->StopCapture();
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (strcmp(method, "createRenderer") == 0) {
    const char* error_message = nullptr;
    const int64_t texture_id = self->CreateRenderer(&error_message);
    if (texture_id < 0) RespondError(call, "renderer_init_failed", error_message);
    else {
      g_autoptr(FlValue) result = fl_value_new_int(texture_id);
      fl_method_call_respond_success(call, result, nullptr);
    }
  } else if (strcmp(method, "releaseRenderer") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    FlValue* id = args == nullptr ? nullptr : fl_value_lookup_string(args, "textureId");
    if (id != nullptr) self->ReleaseRenderer(fl_value_get_int(id));
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (strcmp(method, "pushFragment") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    FlValue* id = args == nullptr ? nullptr : fl_value_lookup_string(args, "textureId");
    FlValue* fragment = args == nullptr ? nullptr : fl_value_lookup_string(args, "fragment");
    const char* error_message = nullptr;
    if (id == nullptr || fragment == nullptr ||
        fl_value_get_type(fragment) != FL_VALUE_TYPE_UINT8_LIST ||
        !self->PushFragment(fl_value_get_int(id), fl_value_get_uint8_list(fragment),
                            fl_value_get_length(fragment), &error_message)) {
      RespondError(call, "invalid_fragment", error_message == nullptr ? "Invalid video fragment." : error_message);
    } else {
      fl_method_call_respond_success(call, nullptr, nullptr);
    }
  } else if (strcmp(method, "dispose") == 0) {
    self->Dispose();
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

FlMethodErrorResponse* RealtimeVideo::Listen(FlEventChannel*, FlValue*, gpointer user_data) {
  static_cast<RealtimeVideo*>(user_data)->listening_ = true;
  return nullptr;
}

FlMethodErrorResponse* RealtimeVideo::Cancel(FlEventChannel*, FlValue*, gpointer user_data) {
  auto* self = static_cast<RealtimeVideo*>(user_data);
  self->listening_ = false;
  self->StopCapture();
  return nullptr;
}

bool RealtimeVideo::StartCapture(const char* source, const char** error_message) {
  if (capturing_) return true;
  if (!listening_) {
    *error_message = "Listen for video fragments before starting capture.";
    return false;
  }
  std::vector<const char*> arguments = {"ffmpeg", "-loglevel", "error"};
  if (strcmp(source, "camera") == 0) {
    const char* camera = std::getenv("NOSTR_CODEX_CAMERA");
    if (camera == nullptr || camera[0] == '\0') camera = "/dev/video0";
    if (access(camera, R_OK) != 0) {
      *error_message = "No readable V4L2 camera was found. Set NOSTR_CODEX_CAMERA to its device path.";
      return false;
    }
    arguments.insert(arguments.end(), {"-f", "v4l2", "-framerate", "10", "-i", camera});
  } else if (strcmp(source, "screen") == 0) {
    const char* display = std::getenv("DISPLAY");
    if (display == nullptr || display[0] == '\0') {
      *error_message = "Screen sharing requires an X11 DISPLAY. Wayland is not supported by this ffmpeg source.";
      return false;
    }
    screen_display_ = std::string(display) + "+0,0";
    arguments.insert(arguments.end(), {"-f", "x11grab", "-framerate", "10", "-i", screen_display_.c_str()});
  } else {
    *error_message = "Capture source must be camera or screen.";
    return false;
  }
  arguments.insert(arguments.end(), {"-an", "-vf", "scale=640:360", "-c:v", "libx264",
      "-preset", "ultrafast", "-tune", "zerolatency", "-pix_fmt", "yuv420p", "-g", "10",
      "-keyint_min", "10", "-x264-params", "repeat-headers=1:annexb=1:aud=1", "-f", "h264", "pipe:1"});
  capture_pid_ = SpawnFfmpeg(arguments, nullptr, &capture_output_fd_);
  if (capture_pid_ < 0) {
    *error_message = "Could not start the installed ffmpeg capture encoder.";
    return false;
  }
  capturing_ = true;
  capture_thread_ = std::thread(&RealtimeVideo::CaptureLoop, this, capture_output_fd_);
  return true;
}

void RealtimeVideo::StopCapture() {
  capturing_ = false;
  StopFfmpeg(&capture_pid_, nullptr, &capture_output_fd_);
  if (capture_thread_.joinable()) capture_thread_.join();
}

void RealtimeVideo::CaptureLoop(int output_fd) {
  std::vector<uint8_t> pending;
  std::vector<uint8_t> access_unit;
  uint8_t read_buffer[4096];
  while (capturing_) {
    const ssize_t count = read(output_fd, read_buffer, sizeof(read_buffer));
    if (count <= 0) break;
    pending.insert(pending.end(), read_buffer, read_buffer + count);
    size_t start = FindStartCode(pending, 0);
    if (start > 0 && start < pending.size()) pending.erase(pending.begin(), pending.begin() + start);
    while (true) {
      const size_t code_length = StartCodeLength(pending, 0);
      if (code_length == 0) break;
      const size_t next = FindStartCode(pending, code_length);
      if (next == pending.size()) break;
      const uint8_t type = pending[code_length] & 0x1f;
      if (type == 9 && !access_unit.empty()) {
        EmitAccessUnit(access_unit);
        access_unit.clear();
      }
      access_unit.insert(access_unit.end(), pending.begin(), pending.begin() + next);
      pending.erase(pending.begin(), pending.begin() + next);
    }
  }
}

void RealtimeVideo::EmitAccessUnit(const std::vector<uint8_t>& access_unit) {
  if (!listening_ || access_unit.empty()) return;
  bool key_frame = false;
  for (size_t offset = FindStartCode(access_unit, 0); offset < access_unit.size();) {
    const size_t code_length = StartCodeLength(access_unit, offset);
    if (code_length != 0 && offset + code_length < access_unit.size() &&
        (access_unit[offset + code_length] & 0x1f) == 5) key_frame = true;
    const size_t next = FindStartCode(access_unit, offset + code_length);
    if (next == access_unit.size()) break;
    offset = next;
  }
  const uint16_t sequence = frame_sequence_++;
  const uint32_t timestamp = static_cast<uint32_t>(std::chrono::duration_cast<std::chrono::microseconds>(
      std::chrono::steady_clock::now().time_since_epoch()).count());
  for (size_t offset = 0, fragment = 0; offset < access_unit.size(); ++fragment) {
    const size_t count = std::min(kMaxFragmentBytes, access_unit.size() - offset);
    std::vector<uint8_t> bytes(kHeaderBytes + count);
    bytes[0] = kVideoVersion;
    bytes[1] = (key_frame ? kKeyFrameFlag : 0) |
               (offset + count == access_unit.size() ? kEndOfFrameFlag : 0);
    bytes[2] = static_cast<uint8_t>(sequence >> 8);
    bytes[3] = static_cast<uint8_t>(sequence);
    bytes[4] = static_cast<uint8_t>(fragment >> 8);
    bytes[5] = static_cast<uint8_t>(fragment);
    bytes[6] = static_cast<uint8_t>(timestamp >> 24);
    bytes[7] = static_cast<uint8_t>(timestamp >> 16);
    bytes[8] = static_cast<uint8_t>(timestamp >> 8);
    bytes[9] = static_cast<uint8_t>(timestamp);
    std::memcpy(bytes.data() + kHeaderBytes, access_unit.data() + offset, count);
    auto* pending = new PendingFrame{FL_EVENT_CHANNEL(g_object_ref(frame_channel_)), std::move(bytes)};
    g_main_context_invoke(nullptr, SendFrame, pending);
    offset += count;
  }
}

int64_t RealtimeVideo::CreateRenderer(const char** error_message) {
  auto renderer = std::make_unique<Renderer>(textures_);
  if (!renderer->Start(error_message)) return -1;
  const int64_t id = renderer->id();
  std::lock_guard<std::mutex> lock(renderers_mutex_);
  renderers_[id] = std::move(renderer);
  return id;
}

bool RealtimeVideo::PushFragment(int64_t texture_id, const uint8_t* fragment, size_t length,
                                 const char** error_message) {
  if (length <= kHeaderBytes || fragment[0] != kVideoVersion) {
    *error_message = "Fragment does not use the H.264 video protocol.";
    return false;
  }
  std::lock_guard<std::mutex> lock(renderers_mutex_);
  const auto found = renderers_.find(texture_id);
  if (found == renderers_.end()) {
    *error_message = "Video renderer no longer exists.";
    return false;
  }
  const bool written = found->second->PushFragment(fragment, length);
  if (!written) *error_message = "The H.264 decoder stopped accepting frames.";
  return written;
}

void RealtimeVideo::ReleaseRenderer(int64_t texture_id) {
  std::lock_guard<std::mutex> lock(renderers_mutex_);
  renderers_.erase(texture_id);
}
