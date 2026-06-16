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

## Multi-Repo Command And Control

The phone can store multiple repo targets. Each target is a named Nostr peer
pubkey plus relay list, so the same mobile key can quickly switch between
separate repo services. Each repo service has its own Nostr identity and
therefore its own npub. The phone sends DMs to the selected target only.

From any repo folder, start a foreground worker by downloading the release
binary only if a local worker executable is not already present:

```bash
worker=./nostr-codex-worker-linux-x64; ca="${CODEX_ARGS:-}"; ta="${TRANSCRIBE_ARGS:-}"; if [ -z "$ca" ]; then ca='--ask-for-approval never --sandbox danger-full-access -c model_reasoning_effort=medium exec --skip-git-repo-check'; fi; if [ -z "$ta" ]; then ta='-m /home/tom/code/phone/models/ggml-base.en.bin -f {audio} -otxt -of {output_dir}/transcript -nt'; fi; if [ ! -x "$worker" ] && [ ! -x ./nostr-codex-worker ]; then curl -fsSL -o "$worker" https://github.com/tidley/nostr-codex-phone/releases/latest/download/nostr-codex-worker-linux-x64 && chmod +x "$worker"; fi; if [ ! -x "$worker" ] && [ -x ./nostr-codex-worker ]; then worker=./nostr-codex-worker; fi; if [ -x "$worker" ]; then RUST_LOG="${RUST_LOG:-info,nostr_codex_server=debug,nostr_sdk=info,nostr=info}" NOSTR_RELAYS="${NOSTR_RELAYS:-wss://relay.damus.io,wss://nos.lol,wss://nostr.mom}" NOSTR_CODEX_ENV_FILE="${NOSTR_CODEX_ENV_FILE:-$PWD/.env.server}" CODEX_WORKDIR="$PWD" CODEX_MEMORY_DB="${CODEX_MEMORY_DB:-$PWD/.nostr-codex-memory.sqlite3}" CODEX_BIN="${CODEX_BIN:-/home/tom/.nvm/versions/node/v24.12.0/bin/codex}" CODEX_ARGS="$ca" TRANSCRIBE_BIN="${TRANSCRIBE_BIN:-/home/tom/.local/bin/whisper-cpp}" TRANSCRIBE_ARGS="$ta" "$worker"; else echo 'Nostr Codex worker executable not found after download.' >&2; exit 1; fi
```

The worker writes `.env.server` in that repo if needed, generates and saves a
repo-local `NOSTR_SECRET_KEY` when one is not already configured, prints/saves
the QR target, and listens for DMs. If `NOSTR_PEER_PUBKEY` is not configured,
the first phone key that sends a DM becomes the saved owner for that worker.
Set `NOSTR_PEER_PUBKEY=npub...` before the command when you want to pre-lock a
worker to a specific phone.

Generate a fresh server key for a repo service:

```bash
cargo run --manifest-path /home/tom/code/phone/rust/Cargo.toml --bin nostr-keygen
```

Create a per-repo env file such as `/path/to/repo/.env.server`:

```bash
NOSTR_SECRET_KEY='nsec...from nostr-keygen, optional...'
NOSTR_PEER_PUBKEY='npub...mobile public key, optional...'
NOSTR_RELAYS='wss://relay.damus.io,wss://nos.lol,wss://nostr.mom'
CODEX_BIN='/home/tom/.nvm/versions/node/v24.12.0/bin/codex'
CODEX_ARGS='--ask-for-approval never --sandbox danger-full-access -c model_reasoning_effort=medium exec --skip-git-repo-check'
TRANSCRIBE_BIN='/home/tom/.local/bin/whisper-cpp'
TRANSCRIBE_ARGS='-m /home/tom/code/phone/models/ggml-base.en.bin -f {audio} -otxt -of {output_dir}/transcript -nt'
```

Install a user systemd service for that repo:

```bash
/home/tom/code/phone/scripts/install-repo-service.sh /path/to/repo nostr-codex-myrepo /path/to/repo/.env.server
```

The installer uses this project’s `nostr-codex-server` binary, sets
`CODEX_WORKDIR` to the target repo, enables user lingering, and enables the
service at boot. The service npub printed in `journalctl --user -u
nostr-codex-myrepo` is the pubkey to add as a target in the phone app. If the
env file is empty or missing, the service creates it and saves its generated
Nostr identity there on first start.

On startup each repo service also prints a QR code and saves an SVG target card
to `.nostr-codex-target.svg` in its `CODEX_WORKDIR`. The QR payload is plain
JSON:

```json
{
  "type": "nostr_codex_target",
  "version": 1,
  "name": "repo-folder",
  "pubkey": "npub...",
  "pubkey_hex": "hex...",
  "workdir": "/path/to/repo",
  "relays": ["wss://relay.damus.io"]
}
```

Set `NOSTR_CODEX_QR_PRINT=0` to stop printing the terminal QR, set
`NOSTR_CODEX_QR_PATH=/path/to/target.svg` to change where it is saved, or set
`NOSTR_CODEX_QR_OPEN=1` to best-effort open the SVG with `xdg-open`.

If the phone has no stored Codex session for a repo service yet, the server
looks in `CODEX_SESSIONS_DIR` or `~/.codex/sessions` and adopts the newest
Codex session whose `session_meta.payload.cwd` matches `CODEX_WORKDIR`. This
uses the same session files as `~/code/tooling/codex-sessions.sh`. Disable it
with `CODEX_RESUME_LATEST_BY_WORKDIR=0`.

Manual environment:

```bash
export NOSTR_SECRET_KEY='nsec...' # optional; generated and saved if omitted
export NOSTR_PEER_PUBKEY='npub...' # optional; first DM sender is saved if omitted
export NOSTR_RELAYS='wss://relay.damus.io,wss://nos.lol,wss://nostr.mom'
```

`NOSTR_PEER_PUBKEY` is optional for the server. If omitted, the server subscribes
to its own GiftWrap inbox and saves the first valid DM sender as the owner in
`NOSTR_CODEX_ENV_FILE` or `.env.server`. Set it when you want to restrict
processing to one phone key before first contact:

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

The Flutter app stores the local `nsec`, repo targets, relay lists, and Blossom
selection in `flutter_secure_storage`. A repo target is a display name, a service
npub/hex pubkey, and the relays used by that service. Switching targets while
connected disconnects from the current repo service, reconnects to the selected
one, and keeps on-screen message history separated per target for the current
app session.

When adding a repo target, tap `Scan` and point the camera at the worker QR
printed or saved by the repo service. The app imports the service pubkey, relays,
and folder-derived target name.

The mic button records an Opus/Ogg file by default, encrypts it locally, uploads
the ciphertext with a Nostr-signed BUD-11 authorization token, and sends the
returned URL/hash plus decryption metadata over an encrypted Nostr DM. If the
server sends `audio_retry`, the next recording is sent as WAV and then the app
returns to Opus/Ogg. The main composer button says `Record` when the query box
is empty, changes to `Send` while recording, and sends typed text when text is
present. The cancel button discards a recording locally without uploading.
Message actions allow copying incoming text and resending typed queries,
uploaded audio references, or returned transcripts. Returned transcripts are
styled as user-side speech bubbles next to the audio message, while Codex
responses remain visually distinct.

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

Use the app to generate or paste the mobile key, copy the displayed mobile
public key into each repo service's `NOSTR_PEER_PUBKEY`, add each service npub
as a named repo target in the app, and use the same relay list on both sides of
each target.

Android permissions include internet, microphone, and camera access.

## Verification

```bash
cargo test --manifest-path rust/Cargo.toml
flutter analyze
flutter test
flutter build apk --debug
```
