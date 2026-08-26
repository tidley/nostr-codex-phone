# Transcription benchmark

Use real voice recordings from the same phone for every CPU and GPU run. Do
not use synthetic speech or silent media for the latency baseline.

## Capture the application path

Send recordings of about 5, 10, 20, and optionally 60 seconds through Code
Call. The worker writes these structured log events for each successful run:

- `download_audio`: HTTPS download, decryption, and temporary-file write.
- `preprocess_audio`: WAV pass-through, pure-Rust conversion, or FFmpeg fallback.
- `transcribe_audio`: audio duration, process spawn, Whisper execution, transcript-file read, total transcription time, and `whisper_rtf`.
- `audio_end_to_end` or `workspace_voice_end_to_end`: download through transcript availability.
- `whisper_cpp_output`: unmodified Whisper.cpp stderr, including its timing summary.

For the main worker, inspect a test window with:

```bash
journalctl --user -u nostr-codex-server.service --since '10 minutes ago' --no-pager --grep='transcription_timing\|whisper_cpp_output'
```

Use the equivalent `nostr-codex-space-<name>.service` unit for a registered
workspace worker.

Record this row for every clip:

| Audio duration | Download/write | Preprocess | Whisper spawn | Whisper wall | Whisper internal total | Transcript read | Application total | RTF |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |

`whisper_rtf` is Whisper wall time divided by the prepared audio duration. It
includes model loading because the worker starts a new Whisper.cpp process for
each transcription request.

## Run Whisper.cpp directly

Use the same configured command for a 10 to 20 second WAV recording:

```bash
time /home/tom/.local/bin/whisper-cpp \
  -m /home/tom/code/phone/models/ggml-base.en.bin \
  -f test.wav \
  -otxt \
  -of /tmp/transcript \
  -nt
```

Keep the complete stderr output. The `whisper_print_timings` section reports
model loading, mel processing, encoding, decoding/sampling, and total time.

## GPU comparison

After building Whisper.cpp with CUDA support, repeat the same recordings and
application total with the Whisper wall and internal timings to separate CUDA
benefit from download, preprocessing, and file overhead.
