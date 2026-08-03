# FIPS Call Transport

## Scope

Code Call uses FIPS for encrypted peer transport. Nostr relays only advertise
availability and carry encrypted traversal signaling. STUN discovers each
peer's reflexive UDP address. Neither system carries call media.

TURN is intentionally out of scope. A call can fail when a direct UDP path is
not possible, including symmetric NAT and networks that block UDP.

## Identity

Code Call uses the existing Nostr `nsec` as its FIPS identity. A FIPS QUIC
certificate is bound to that identity, so a connected peer is authenticated as
the workspace member selected in the UI.

## Direct Conversation Calls

1. The caller creates an ephemeral call ID and sends a workspace call invite.
2. Both peers use the same Nostr identities to start FIPS Nostr discovery.
3. FIPS uses a new UDP socket for that peer and attempt, performs STUN on that
   socket, exchanges encrypted NIP-59/NIP-44 signaling, and sends coordinated
   UDP punches.
4. FIPS adopts the successful UDP socket into an identity-verified persistent
   QUIC connection.
5. The application opens separate logical control and media paths on that
   connection. Ending a call closes the paths and stops discovery.

The call invite is application state only. FIPS owns NAT candidate handling,
signaling expiry, punching, and certificate verification.

## Workspace Huddles

The always-on workspace worker advertises its FIPS endpoint. Each participant
establishes one independent FIPS QUIC connection to the worker. The worker is
the huddle coordinator and media distribution hub, not a TURN server and not a
UDP relay:

- membership, mute state, speaker state, and screen-share ownership use the
  reliable control path;
- a participant sends each media unit once to the worker;
- the worker forwards that unit to the other active participant connections;
- the worker does not decrypt FIPS transport, but it must receive application
  media frames to forward them. End-to-end group-media encryption is a future
  layer if the worker must not access decoded media.

This topology limits group NAT traversal to the worker's stable endpoint and
does not require every huddle member to punch every other member.

## Realtime Requirement

`fips-mobile` currently exposes framed bidirectional QUIC streams. Streams are
correct for signaling, presence, chat, file transfer, and reliable screen-share
chunks. They are not sufficient as the final audio/video transport because a
lost packet can block later stream data.

Before live audio/video implementation, FIPS needs an app-facing bounded QUIC
datagram API, or Code Call needs a documented media pacing/drop policy on
separate streams. The preferred direction is QUIC datagrams:

- audio: small, timestamped, lossy Opus frames;
- video: timestamped, lossy encoded frames with keyframe recovery;
- screen share: reliable control/keyframes and lossy delta frames where the
  encoder permits it.

Until that API exists, Code Call must only expose FIPS call setup and reliable
control diagnostics, not a misleading live-call button.

## Integration Boundary

The Rust bridge owns FIPS sessions and exposes only lifecycle operations to
Flutter: start, invite/connect, status, send/receive control frames, and stop.
It must not expose raw sockets or secret keys to Dart. The worker uses the same
FIPS crate and starts its advertised endpoint while the workspace service is
online.

The dependency is pinned to a FIPS commit so Code Call release builds do not
change transport behavior through an unreviewed upstream update.
