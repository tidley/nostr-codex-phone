# Nostr Codex Phone

Bidirectional voice query client and Rust server over encrypted Nostr GiftWrapped DMs.

## Message Contract

Both peers send NIP-17/NIP-59 GiftWrapped private direct messages whose decrypted content is one of:

```json
{ "query": "text" }
```

```json
{
  "audio": {
    "url": "https://blossom.example/sha256.ogg",
    "sha256": "ciphertext-sha256-hex",
    "size": 12345,
    "type": "audio/ogg",
    "name": "voice.ogg",
    "encryption": {
      "algorithm": "xchacha20poly1305",
      "key": "base64url-32-byte-key",
      "nonce": "base64url-24-byte-nonce",
      "plaintext_sha256": "plaintext-sha256-hex",
      "plaintext_size": 12329,
      "plaintext_type": "audio/ogg"
    }
  }
}
```

```json
{ "response": "text" }
```

```json
{ "transcript": "text heard from audio" }
```

```json
{
  "audio_retry": {
    "format": "wav",
    "reason": "Compressed voice audio could not be decoded or transcribed. Please retry; the phone will send the next recording as WAV."
  }
}
```

```json
{ "error": "text" }
```

Malformed JSON from the trusted peer is surfaced as an `invalid` message on mobile and answered by the server with `{ "error": "..." }`.

Audio DMs contain a Blossom blob reference only. New mobile uploads encrypt the
audio payload with XChaCha20-Poly1305 before upload. The Blossom `sha256` and
`size` fields refer to the ciphertext; the random decryption key and nonce are
inside the encrypted Nostr DM only. The server downloads the URL, verifies the
ciphertext hash, decrypts and verifies the plaintext hash, transcribes the audio
locally, sends the transcript back as a non-spoken `transcript` DM, then treats
the transcript like a text query. If compressed audio cannot be decoded or
transcribed after all server-side fallbacks, the server sends `audio_retry` and
the phone records the next voice note as WAV.

GrapheneOS/Android local speech-to-text is not required and is not the primary
path. The phone records push-to-talk audio, encrypts it, uploads it to Blossom,
and lets the server run Whisper. Android-local STT can be added later as an
optional fast path, but server-side STT is the reliable default.

## Server

The server listens for `{ "query": "..." }` and `{ "audio": { ... } }`, runs
Codex non-interactively, and replies with `{ "response": "..." }` or
`{ "error": "..." }`. For compressed audio transcription failures, it can also
reply with `{ "audio_retry": { "format": "wav", "reason": "..." } }`.

Both server and mobile dedupe incoming GiftWrapped DMs by event ID so the same
event delivered by multiple relays is only processed once per session.

Required environment:

```bash
export NOSTR_SECRET_KEY='nsec...'
export NOSTR_PEER_PUBKEY='npub...' # mobile public key
export NOSTR_RELAYS='wss://relay.damus.io,wss://nos.lol,wss://nostr.mom'
```

`NOSTR_PEER_PUBKEY` is optional for the server. If omitted, the server subscribes
to its own GiftWrap inbox and replies to the sender of each valid query. Set it
when you want to restrict processing to one phone key:

```bash
export NOSTR_PEER_PUBKEY='npub...'
```

Optional Codex configuration:

```bash
export CODEX_BIN='/home/tom/.nvm/versions/node/v24.12.0/bin/codex'
export CODEX_ARGS='--ask-for-approval never --sandbox danger-full-access -c model_reasoning_effort=medium exec --skip-git-repo-check'
export CODEX_WORKDIR="$PWD"
export CODEX_TIMEOUT_SECS=180
export CODEX_PERSIST_SESSIONS=1
```

`danger-full-access` lets the DM-driven Codex session edit files, run builds,
commit, and push. Use it only with a trusted `NOSTR_PEER_PUBKEY` and relays you
are comfortable using for this control path. Switch the sandbox back to
`read-only` when you only want remote inspection.

For user turns, the server uses `codex exec --json` and stores the returned
Codex `thread_id` in SQLite per phone peer and workdir. Follow-up turns resume
that session with `codex exec resume <thread_id>` instead of rebuilding the full
prompt every time. If a stored session cannot be resumed, it is cleared and the
turn is retried once as a fresh session. Existing `--ephemeral` entries in
`CODEX_ARGS` are stripped for session-backed user turns.

Optional SQLite memory configuration:

```bash
export CODEX_MEMORY=1
export CODEX_MEMORY_DB="$PWD/.nostr-codex-memory.sqlite3"
export CODEX_MEMORY_RECENT_MESSAGES=12
export CODEX_MEMORY_COMPACT_AFTER_MESSAGES=16
export CODEX_MEMORY_SUMMARY_MAX_CHARS=5000
export CODEX_MEMORY_COMPACTION_MAX_CHARS=12000
```

Memory is enabled by default. The server stores per-peer message history in
SQLite, stores the Codex session id per peer/workdir, caches transcripts by
audio hash, adds lightweight topic metadata, and injects selectively retrieved
memory only when a fresh Codex session needs fallback context. It periodically
compacts older turns into a summary in the background. The database contains
decrypted queries, transcripts, responses, and session ids, so keep it local; the
default hidden database path is gitignored.

Send `/memory` or `/summary` from the phone to inspect the current compact
summary. Send `/forget`, `/reset`, or `/reset memory` to clear memory for that
phone key.

Optional audio transcription configuration:

```bash
export TRANSCRIBE_BIN='/home/tom/.local/bin/whisper-cpp'
export TRANSCRIBE_ARGS='-m /path/to/ggml-base.en.bin -f {audio} -otxt -of {output_dir}/transcript -nt'
export TRANSCRIBE_TIMEOUT_SECS=300
export FFMPEG_BIN='ffmpeg' # optional fallback for unsupported compressed audio
export AUDIO_TRANSCODE_TIMEOUT_SECS=60
export AUDIO_MAX_BYTES=52428800
```

`{audio}` is replaced with the verified downloaded audio file path and
`{output_dir}` is replaced with a temporary transcript directory. Compressed
phone audio is prepared as 16 kHz mono WAV before invoking Whisper. Opus/Ogg is
decoded in-process with pure Rust `ogg` + `opus-decoder` for mono/stereo Opus
streams, and AAC/M4A is decoded in-process with pure Rust Symphonia/Hound.
`ffmpeg` is only used as an optional fallback for unsupported containers,
channel mappings, or decoder failures. If `TRANSCRIBE_ARGS` is not set, the
server defaults to the Python `whisper` CLI style arguments.

Run:

```bash
cargo run --manifest-path rust/Cargo.toml --bin nostr-codex-server
```

Send a one-off response DM from the local machine to the configured phone peer:

```bash
printf 'This is a local-machine test reply.' \
  | cargo run --manifest-path rust/Cargo.toml --bin nostr-send-response
```

The phone receives that as `{ "response": "..." }`, so Auto speak reads it
through TTS.

`codex exec` and the configured transcriber must be installed and authenticated
on the server. If either is missing or fails, the peer receives a JSON error DM
instead of the server crashing.

## Mobile

The Flutter app stores the local `nsec`, peer pubkey, relay list, and Blossom
selection in `flutter_secure_storage`. The mic button records an Opus/Ogg file
by default, encrypts it locally, uploads the ciphertext with a Nostr-signed
BUD-11 authorization token, and sends the returned URL/hash plus decryption
metadata over an encrypted Nostr DM. If the server sends `audio_retry`, the next
recording is sent as WAV and then the app returns to Opus/Ogg. The main composer
button records when the query box is empty, sends typed text when text is present,
and changes to send the voice note while recording. The cancel button discards a
recording locally without uploading. Message actions allow copying incoming text
and resending typed queries, uploaded audio references, or returned transcripts.
Returned transcripts are styled as user-side speech bubbles next to the audio
message, while Codex responses remain visually distinct.

After connecting, the relay/key setup panel collapses into a compact expandable
header so the conversation controls stay near the top of the screen.

Incoming response bodies render as GitHub-style Markdown, so Codex output such
as `**bold**`, lists, and code blocks is formatted on screen. Auto-speak strips
Markdown markers before sending text to TTS, and the playback bar can stop or
replay the last spoken response.

The expandable Speech bar controls TTS language, Android engine, rate, pitch,
and volume, and includes a test button. On GrapheneOS/Android, install TTS
engines through your app store, then change system defaults under Settings ->
System -> Languages & input -> Text-to-speech output; the app also lists
installed engines when Android exposes them.

The Blossom field accepts a custom server URL or `auto`. Auto-select tries these
public free/free-tier servers in order until one accepts the upload:

```text
https://blossom.nostr.build
https://blossom.primal.net
https://cdn.nostrcheck.me
```

For a more Nostr-native media setup, clients can also publish and read
`kind:10063` Blossom server lists. This app keeps a curated fallback list for
voice-note uploads so a missing or failing default server does not block the
query path.

The server handles local/no-heavy-Codex requests directly, including `/summary`,
`/memory`, `/forget`, `repeat last`, `status`, and `what repo am I in?`. It also
routes obvious no-op filler such as "thanks" without invoking Codex.

Incoming Nostr DMs are dispatched to per-peer worker queues. The relay listener
keeps receiving while Whisper/Codex work runs, and each peer's messages are still
processed in order.

Run:

```bash
flutter run
```

Use the app to generate or paste the mobile key, copy the displayed mobile public key into `NOSTR_PEER_PUBKEY` on the server, paste the server public key into the app, and use the same relay list on both sides.

Android permissions include internet and microphone access.

## Verification

```bash
cargo test --manifest-path rust/Cargo.toml
flutter analyze
flutter test
flutter build apk --debug
```
