# Pixel FIPS Call Harness

`fips-call-harness` validates a direct FIPS call from a desktop to a real Pixel.
It does not emulate Android or run an in-memory peer.

The harness sends deterministic 20 ms, 48 kHz mono PCM frames encoded as Opus
QUIC datagrams. Packet flag `0x80` is reserved for the harness. The existing
Pixel FIPS receive path returns flagged packets unchanged before audio playback.
This proves the actual FIPS traversal, identity verification, QUIC datagram,
Opus packet, and Pixel-to-desktop return path without recording a microphone.

## Run Against A Pixel

1. Build and install this app revision on the Pixel. It must include the
   flagged-packet echo path; a released build without it cannot run this test.
2. On the Pixel, configure the same Nostr relays as the desktop command and
   note the account `npub` from the app settings.
3. Keep the app unlocked and in the foreground. The Pixel must be able to
   receive the call invite and display the incoming-call control.
4. Set `DESKTOP_NSEC` to a real workspace identity and `PIXEL_NPUB` to the
   Pixel account identity, then run this command on the computer:

```bash
./scripts/fips-call-harness.sh connect \
  --secret "$DESKTOP_NSEC" \
  --peer "$PIXEL_NPUB" \
  --relay wss://relay.damus.io \
  --relay wss://nos.lol \
  --stun stun:stun.l.google.com:19302 \
  --nostr-control \
  --frames 50 \
  --timeout-seconds 45
```

5. Tap **Answer** on the Pixel and leave the call active until the desktop
   command exits. Do not start microphone capture manually. The Pixel returns
   only harness-flagged datagrams before they reach the speaker.

`--nostr-control` sends the existing `call_invite` and, after the test,
`call_hangup` Nostr controls. FIPS owns candidate exchange, UDP punching,
certificate authentication, and media.

The command emits exactly one JSON object to standard output and exits zero
only when every check passes. `traversal` and `identity` pass only after the
FIPS session reports `Connected`; FIPS reaches that state only after direct
Nostr/STUN traversal and certificate-bound peer authentication. `datagram`
requires negotiated QUIC datagrams. `frame`, `loss`, and `jitter` measure the
returned flagged Opus frames. Every returned packet must match one sent
deterministic packet byte-for-byte, including its Opus payload and sequence.
`hangup` records Nostr hangup delivery when `--nostr-control` is set.

Example result shape:

```json
{"pass":true,"role":"connect","traversal":{"pass":true},"identity":{"pass":true},"datagram":{"pass":true},"frame":{"sent":50,"received":50,"decoded":50,"pass":true},"loss":{"lost":0,"percent":0.0,"pass":true},"jitter":{"max_ms":1.2,"pass":true},"hangup":{"pass":true}}
```

## Two Desktop Peers

Use this only to diagnose infrastructure before testing the Pixel. It is still
two real FIPS processes, not a mock. Start the accepting peer first and copy
its `npub` from `cargo run --bin nostr-keygen` if needed.

```bash
./scripts/fips-call-harness.sh accept --secret "$SECOND_NSEC" --relay wss://relay.damus.io --stun stun:stun.l.google.com:19302 --frames 50
./scripts/fips-call-harness.sh connect --secret "$FIRST_NSEC" --peer "$SECOND_NPUB" --relay wss://relay.damus.io --stun stun:stun.l.google.com:19302 --frames 50
```

Accept mode returns each received harness datagram unchanged. It does not
pretend to be a Pixel. Limits can be adjusted with `--max-loss-percent` and
`--max-jitter-ms`; defaults are 5 percent and 40 ms.
