# Code Call

Phone remote for OpenCode over encrypted Nostr GiftWrapped DMs.

## Message Contract

Both peers send NIP-17/NIP-59 GiftWrapped private direct messages whose decrypted content is one of:

```json
{ "query": "text" }
```

```json
{
  "media_bundle": {
    "query": "analyze this file",
    "attachments": [
      {
        "url": "https://blossom.example/sha256.bin",
        "sha256": "ciphertext-sha256-hex",
        "size": 12345,
        "type": "application/pdf",
        "name": "notes.pdf",
        "encryption": {
          "algorithm": "xchacha20poly1305",
          "key": "base64url-32-byte-key",
          "nonce": "base64url-24-byte-nonce",
          "plaintext_sha256": "plaintext-sha256-hex",
          "plaintext_size": 11895,
          "plaintext_type": "application/pdf"
        }
      }
    ]
  }
}
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
{
  "target_invite": {
    "type": "nostr_codex_target",
    "version": 1,
    "name": "repo-folder",
    "pubkey": "npub...",
    "pubkey_hex": "hex...",
    "workdir": "/path/to/repo",
    "relays": ["wss://relay.damus.io"]
  }
}
```

```json
{ "error": "text" }
```

Malformed JSON from the trusted peer is surfaced as an `invalid` message on mobile and answered by the server with `{ "error": "..." }`.

All JSON messages are inside encrypted GiftWrapped DMs. Relays should not see
query text, transcripts, responses, attachment URLs, or blob decryption keys.
Blossom uploads are public blobs, so mobile uploads encrypt the payload with
XChaCha20-Poly1305 before upload and use `application/octet-stream` as the
upload content type. The Blossom `sha256` and `size` fields refer to the
ciphertext; the original MIME type, random decryption key, nonce, plaintext
hash, and plaintext size are inside the encrypted Nostr DM only.

Audio DMs contain a Blossom blob reference only. The server downloads the URL,
verifies the ciphertext hash, decrypts and verifies the plaintext hash,
transcribes the audio locally, sends the transcript back as a non-spoken
`transcript` DM, then treats the transcript like a text query. If compressed
audio cannot be decoded or transcribed after all server-side fallbacks, the
server sends `audio_retry` and the phone records the next voice note as WAV.

GrapheneOS/Android local speech-to-text is not required and is not the primary
path. The phone records push-to-talk audio, encrypts it, uploads it to Blossom,
and lets the server run Whisper. Android-local STT can be added later as an
optional fast path, but server-side STT is the reliable default.

## Server

The server listens for `{ "query": "..." }`, `{ "audio": { ... } }`, and
`{ "media_bundle": { ... } }` (one or more encrypted attachments),
sends prompts to OpenCode's HTTP server, and replies with `{ "response": "..." }` or
`{ "error": "..." }`. For compressed audio transcription failures, it can also
reply with `{ "audio_retry": { "format": "wav", "reason": "..." } }`. When a
root worker opens another repo session, it sends `{ "target_invite": { ... } }`
so the phone can add the new routed workdir as a selectable session.

Both server and mobile dedupe incoming GiftWrapped DMs by event ID so the same
event delivered by multiple relays is only processed once per session.

## Multi-Repo Command And Control

The phone can store multiple repo targets. Each target is a named session with
a Nostr service pubkey, relay list, and optional workdir route, so the same
mobile key can quickly switch between repo sessions while still DMing one
service npub. The selected workdir route is carried inside the encrypted
GiftWrapped DM payload.

The phone session drawer includes **Spawn on computer**. It sends a
`spawn_session` request to the computer service. The worker treats its startup
directory as the root, so Create and Open only need a folder name such as
`my-new-project`, `phone`, or `pave/website`. In **Open** mode, the dialog asks
the worker for folders under that root and its `pave` subfolder and fills the
field from that list. If the spawn succeeds, the service sends a target invite
DM back to the phone and records the routed session in
`.nostr-codex/workers.json` under the worker root. Accepting the invite adds it
as a saved phone session.

The same workflow can be driven by text:

```text
/spawn --create my-new-project
/spawn existing-repo
start worker in existing-repo
```

Use `/workers` or `/sessions` to list spawned sessions known by the computer
service. Use `/shutdown`, `/quit`, or `/exit` from the computer service to stop
the worker process.

Only the root worker should be installed as a persistent machine service. Repo
sessions are routed workdirs under that worker.

Start a foreground worker with one command from the directory you want to use as
the worker root:

```bash
curl -fsSL https://raw.githubusercontent.com/tidley/nostr-codex-phone/main/scripts/bootstrap-worker.sh | bash
```

The bootstrap script checks for `.nostr-codex/nostr-codex-worker-linux-x64` or
`.nostr-codex/nostr-codex-worker` first, with the old root-level names as a
fallback. If neither exists, it downloads
`nostr-codex-worker-linux-x64` from the latest GitHub release, makes it
executable, and starts it. The worker writes generated state under
`.nostr-codex/`, including `.env.server`, `memory.sqlite3`, `target.svg`,
`target.txt`, `workers.json`, and `worker.lock`. If `NOSTR_PEER_PUBKEY` is not
configured, the first phone key that sends a DM becomes the saved owner for that
worker. Set `NOSTR_PEER_PUBKEY=npub...` before the command when you want to
pre-lock a worker to a specific phone.

Install or refresh the user systemd service from the directory you want as the
worker root:

```bash
/path/to/nostr-codex-phone/scripts/install-worker-service.sh
```

The generated unit records the current directory as `WorkingDirectory`, because
systemd services do not inherit the shell's later `PWD` on restart.

Generate a fresh worker key:

```bash
cargo run --manifest-path /home/tom/code/phone/rust/Cargo.toml --bin nostr-keygen
```

Create a per-repo env file such as `/path/to/repo/.nostr-codex/.env.server`:

```bash
NOSTR_SECRET_KEY='nsec...from nostr-keygen, optional...'
NOSTR_PEER_PUBKEY='npub...mobile public key, optional...'
NOSTR_RELAYS='wss://relay.damus.io,wss://nos.lol,wss://nostr.mom'
AGENT_BACKEND='opencode'
OPENCODE_URL='http://127.0.0.1:4096'
OPENCODE_BIN='opencode'
OPENCODE_AGENT='build'
AGENT_WORKDIR='/path/to/repo'
TRANSCRIBE_BIN='/home/tom/.local/bin/whisper-cpp'
TRANSCRIBE_ARGS='-m /home/tom/code/phone/models/ggml-base.en.bin -f {audio} -otxt -of {output_dir}/transcript -nt'
```

With the default local `OPENCODE_URL`, the worker starts `opencode serve
--hostname 127.0.0.1 --port 4096` if it is not already running. For a different
URL, start OpenCode yourself. Set `OPENCODE_SERVER_PASSWORD` on both the worker
and OpenCode server when exposing the server beyond localhost.

On startup the worker also prints a QR code, saves an SVG target card to
`.nostr-codex/target.svg`, and writes the raw target payload to
`.nostr-codex/target.txt` in its worker root. The QR payload is plain JSON:

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
`NOSTR_CODEX_QR_PATH=/path/to/target.svg` to change where the SVG is saved, set
`NOSTR_CODEX_TARGET_PAYLOAD_PATH=/path/to/target.txt` to change where the raw
payload is saved, or set `NOSTR_CODEX_QR_OPEN=1` to best-effort open the SVG
with `xdg-open`.

The worker asks OpenCode for sessions in the routed workdir. Follow-up turns
adopt the latest OpenCode session for that directory unless the phone sends a
specific `session_id` from the OpenCode session picker. If OpenCode has no
session for that directory yet, the worker creates one.

Manual environment:

```bash
export NOSTR_SECRET_KEY='nsec...' # optional; generated and saved if omitted
export NOSTR_PEER_PUBKEY='npub...' # optional; first DM sender is saved if omitted
export NOSTR_RELAYS='wss://relay.damus.io,wss://nos.lol,wss://nostr.mom'
```

`NOSTR_PEER_PUBKEY` is optional for the server. If omitted, the server subscribes
to its own GiftWrap inbox and saves the first valid DM sender as the owner in
`NOSTR_CODEX_ENV_FILE` or `.nostr-codex/.env.server`. Set it when you want to
restrict processing to one phone key before first contact:

```bash
export NOSTR_PEER_PUBKEY='npub...'
```

Optional OpenCode configuration:

```bash
export AGENT_BACKEND='opencode'
export OPENCODE_URL='http://127.0.0.1:4096'
export OPENCODE_BIN='opencode'
export OPENCODE_AGENT='build'
export OPENCODE_MODEL='anthropic/claude-sonnet-4-5'
export OPENCODE_AUTO_START=1
export AGENT_WORKDIR="$PWD"
export AGENT_TIMEOUT_SECS=180
```

OpenCode's `build` agent can edit files, run builds, commit, and push according
to your OpenCode permissions and config. Use this bridge only with a trusted
`NOSTR_PEER_PUBKEY` and relays you are comfortable using for this control path.

Codex is still available during the transition with `AGENT_BACKEND=codex` and
the old `CODEX_BIN`/`CODEX_ARGS` settings.

Optional SQLite memory configuration:

```bash
export CODEX_MEMORY=1
export CODEX_MEMORY_DB="$PWD/.nostr-codex/memory.sqlite3"
export CODEX_MEMORY_RECENT_MESSAGES=12
export CODEX_MEMORY_COMPACT_AFTER_MESSAGES=16
export CODEX_MEMORY_SUMMARY_MAX_CHARS=5000
export CODEX_MEMORY_COMPACTION_MAX_CHARS=12000
```

SQLite memory is off by default for OpenCode and still defaults on for the
legacy Codex backend. When enabled, it stores per-peer message history, Codex
session ids, lightweight topic metadata, and compact summaries. OpenCode session
ids and audio transcripts are not cached in SQLite. The database contains
decrypted queries, transcripts, responses, and Codex session ids, so keep it
local; the default hidden database path is gitignored.

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

`opencode` and the configured transcriber must be installed and authenticated
on the server. If either is missing or fails, the peer receives a JSON error DM
instead of the server crashing.

## Mobile

The Flutter app stores the local `nsec`, repo targets, relay lists, and Blossom
selection in `flutter_secure_storage`. A repo target is a display name, a worker
npub/hex pubkey, and the relays used by that worker. Switching targets while
connected disconnects from the current worker, reconnects to the selected
one, and keeps on-screen message history separated per target for the current
app session.

When adding a repo target, tap `Scan` and point the camera at the worker QR
printed or saved by the worker. The app imports the worker pubkey, relays,
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
styled as user-side speech bubbles next to the audio message, while agent
responses remain visually distinct.

After connecting, the relay/key setup panel collapses into a compact expandable
header so the conversation controls stay near the top of the screen.

Incoming response bodies render as GitHub-style Markdown, so agent output such
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

The server handles local/no-heavy-agent requests directly, including `/summary`,
`/memory`, `/forget`, `repeat last`, `status`, and `what repo am I in?`. It also
routes obvious no-op filler such as "thanks" without invoking the agent.

Incoming Nostr DMs are dispatched to per-peer worker queues. The relay listener
keeps receiving while Whisper/agent work runs, and each peer's messages are still
processed in order.

Run:

```bash
flutter run
```

Use the app to generate or paste the mobile key, copy the displayed mobile
public key into the computer service's `NOSTR_PEER_PUBKEY`, add the service npub
as a named target in the app, and use the same relay list on both sides.

Android permissions include internet, microphone, and camera access.

## Verification

```bash
cargo test --manifest-path rust/Cargo.toml
flutter analyze
flutter test
flutter build apk --debug
```

Release assets are packaged with:

```bash
flutter build apk --release
cargo build --release --manifest-path rust/Cargo.toml --bin nostr-codex-server
scripts/package-release-assets.sh
```

The packaging script strips the Linux worker binary before writing
`build/release-assets/v*/nostr-codex-worker-linux-x64`.
