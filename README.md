# Nostr Codex Phone

Bidirectional voice query client and Rust server over encrypted Nostr GiftWrapped DMs.

## Message Contract

Both peers send NIP-17/NIP-59 GiftWrapped private direct messages whose decrypted content is one of:

```json
{ "query": "text" }
```

```json
{ "response": "text" }
```

```json
{ "error": "text" }
```

Malformed JSON from the trusted peer is surfaced as an `invalid` message on mobile and answered by the server with `{ "error": "..." }`.

## Server

The server listens for `{ "query": "..." }`, runs Codex non-interactively, and replies with `{ "response": "..." }` or `{ "error": "..." }`.

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

Run:

```bash
cargo run --manifest-path rust/Cargo.toml --bin nostr-codex-server
```

`codex exec` must be installed and authenticated on the server. If it is missing or fails, the peer receives a JSON error DM instead of the server crashing.

## Mobile

The Flutter app stores the local `nsec`, peer pubkey, and relay list in `flutter_secure_storage`.

Run:

```bash
flutter run
```

Use the app to generate or paste the mobile key, copy the displayed mobile public key into `NOSTR_PEER_PUBKEY` on the server, paste the server public key into the app, and use the same relay list on both sides.

Android permissions include internet and microphone access. iOS includes microphone and speech recognition usage descriptions.

## Verification

```bash
cargo test --manifest-path rust/Cargo.toml
flutter analyze
flutter test
flutter build apk --debug
```
