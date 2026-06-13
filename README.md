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
    "url": "https://blossom.example/sha256.wav",
    "sha256": "ciphertext-sha256-hex",
    "size": 12345,
    "type": "audio/wav",
    "name": "voice.wav",
    "encryption": {
      "algorithm": "xchacha20poly1305",
      "key": "base64url-32-byte-key",
      "nonce": "base64url-24-byte-nonce",
      "plaintext_sha256": "plaintext-sha256-hex",
      "plaintext_size": 12329,
      "plaintext_type": "audio/wav"
    }
  }
}
```

```json
{ "response": "text" }
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
locally, then treats the transcript like a text query.

## Server

The server listens for `{ "query": "..." }` and `{ "audio": { ... } }`, runs
Codex non-interactively, and replies with `{ "response": "..." }` or
`{ "error": "..." }`.

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
export CODEX_ARGS='--ask-for-approval never --sandbox read-only exec --ephemeral --skip-git-repo-check'
export CODEX_WORKDIR="$PWD"
export CODEX_TIMEOUT_SECS=180
```

Optional audio transcription configuration:

```bash
export TRANSCRIBE_BIN='/home/tom/.local/bin/whisper-cpp'
export TRANSCRIBE_ARGS='-m /path/to/ggml-base.en.bin -f {audio} -otxt -of {output_dir}/transcript -nt'
export TRANSCRIBE_TIMEOUT_SECS=300
export AUDIO_MAX_BYTES=52428800
```

`{audio}` is replaced with the verified downloaded audio file path and
`{output_dir}` is replaced with a temporary transcript directory. If
`TRANSCRIBE_ARGS` is not set, the server defaults to the Python `whisper` CLI
style arguments.

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
selection in `flutter_secure_storage`. The mic button records a WAV file,
encrypts it locally, uploads the ciphertext with a Nostr-signed BUD-11
authorization token, and sends the returned URL/hash plus decryption metadata
over an encrypted Nostr DM.

Incoming response bodies render as GitHub-style Markdown, so Codex output such
as `**bold**`, lists, and code blocks is formatted on screen. Auto-speak strips
Markdown markers before sending text to TTS, and the playback bar can stop or
replay the last spoken response.

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
