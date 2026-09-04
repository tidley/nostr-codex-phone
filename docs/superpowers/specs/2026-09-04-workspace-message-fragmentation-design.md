# Workspace Message Fragmentation Design

## Goal

Deliver complete workspace history and snapshots when one logical message is
larger than either the FIPS application-frame or Nostr wrapped-DM limit.

## Scope

- Fragment only oversized `WorkspaceMessagePayload` values.
- Preserve the message ID, all metadata, attachments, reactions, and body
  exactly after reassembly.
- Support both FIPS and Nostr transport limits.
- Keep existing history-transfer behavior for ordinary messages.
- Improve worker diagnostics for OpenCode runs that exit successfully without
  producing a visible text event.

## Wire Format

Add an optional `message_fragments` collection to `WorkspaceUpdate`. Each
fragment contains:

- A unique transfer ID.
- The original workspace message ID.
- Zero-based fragment sequence and total count.
- The JSON bytes of the serialized message, encoded as text-safe base64.

The sender adds fragments to `history_transfer:v2` update frames. A frame
contains either complete messages or fragments, never a partial message in its
`messages` collection.

## Sending

1. Serialize each message before transfer.
2. If its normal update frame fits the active transport ceiling, retain the
   existing message chunking path.
3. If it does not fit, divide the serialized bytes into base64-safe fragments
   whose enclosing update frames fit the active transport ceiling.
4. Include all fragment frames in the same ordered history transfer as normal
   chunks, with conservative metadata-width budgeting.
5. Use the FIPS ceiling for FIPS frames and the existing Nostr transfer ceiling
   for Nostr frames. If a fragment cannot fit an otherwise empty frame, return a
   transport error rather than silently dropping content.

## Receiving

1. Store fragment frames by transfer ID and message ID without applying them to
   workspace state.
2. Accept fragments in any order and ignore duplicate sequence numbers with the
   same bytes.
3. Once every sequence is present, concatenate, base64-decode, deserialize the
   original payload, and add it to the pending transfer update.
4. Apply the complete history transfer atomically only after every expected
   frame and every fragmented message is complete.
5. Reject malformed, conflicting, or oversized reconstructed payloads. They do
   not alter workspace state and are discarded when the pending transfer
   expires.

## Compatibility

- Each client advertises `message_fragmentation_v2` in workspace requests.
- The worker records this capability per member.
- Fragment-aware peers receive `history_transfer:v2` when needed; all normal
  transfers retain the existing `history_transfer:v1` format.
- Peers without the capability receive the existing v1 transfer. If a v1
  response contains an oversized item, the worker returns a clear update
  requirement rather than an incomplete history.
- New clients continue to accept v1 transfers from an older worker.

## OpenCode Diagnostics

When the final retry exits successfully with no visible text, log the session
ID, process status, stderr byte count, and the distinct JSONL event types. Do
not log prompt text, generated content, or full model output.

## Tests

- Rust unit tests prove oversized message serialization produces frames within
  both transport ceilings and preserves byte-for-byte payload reconstruction.
- Rust tests cover exact-boundary messages, malformed fragment metadata, and
  an impossible single-frame fragment.
- Dart tests cover out-of-order fragments, duplicate fragments, missing
  fragments, malformed payloads, and atomic application with normal history
  frames.
- Existing normal history-transfer tests continue to pass unchanged.
