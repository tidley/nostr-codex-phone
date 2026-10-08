# Unified Herdr Runtime Design

## Goal

Run the Linux Nostr/FIPS worker and Herdr agent-terminal runtime in one process.
Nostr direct messages and FIPS requests must call typed Rust interfaces directly,
not a local NDJSON socket API. Keep standalone Herdr available as a separate
terminal application that uses the same runtime library.

## Non-goals

- Merge the phone and Herdr repositories.
- Move Nostr identity, authorization, message storage, search, or delivery into
  Herdr.
- Remove Herdr's standalone executable or TUI clients.
- Change the user-visible Nostr conversation or thread model.
- Preserve the worker-to-Herdr Unix-socket protocol as the primary execution
  path after migration.

## Architecture

Extract Herdr's reusable server functionality into a `herdr-runtime` Cargo
library. The library owns terminal workspaces, tabs, panes, PTYs, managed agent
sessions, typed turns, typed cancellation, persistence, and runtime lifecycle
events. It does not parse command-line arguments, install signals, construct a
Tokio runtime, or own a process exit policy.

Two thin hosts use that library:

- The `herdr` executable builds the standalone terminal application. It owns
  CLI parsing, local sockets for external clients, signal handling, standalone
  update/handoff, and calls `herdr-runtime` for terminal operations.
- The Linux Nostr worker starts `herdr-runtime` inside its existing Tokio
  process. It owns Nostr/FIPS networking, authorization, SQLite conversation
  data, message delivery, and worker shutdown. It calls the runtime through
  typed Rust APIs and subscribes to typed events directly.

The embedded worker host must not start Herdr's standalone client sockets,
signal handlers, self-update, or executable handoff path. Those remain in the
standalone host only.

## Runtime API

`herdr-runtime` exposes a narrow async handle. API request and response types
are Rust types shared by both hosts, not JSON-RPC structures:

- `start(config) -> RuntimeHandle`
- `create_or_open_conversation_space(conversation_id) -> Space`
- `create_or_open_thread_tab(conversation_id, thread_id) -> Tab`
- `start_agent(target, configuration) -> AgentSession`
- `submit_turn(session, turn_id, text, deadline) -> TurnResult`
- `interrupt_turn(session, turn_id) -> TurnResult`
- `subscribe() -> RuntimeEventStream`
- `close_thread(thread_id)` and `shutdown()`

`turn_id` is supplied by the worker and must be unique for each persisted
message delivery attempt. Replays of the same delivery reuse that ID; repeated
user text creates a new ID. Results are typed as completed, interrupted,
failed, unavailable, or timed out. Agent output is accepted only through the
reported typed OpenCode completion path; terminal scraping is not a result
source.

The standalone socket API becomes an adapter over this API. It remains useful
for external Herdr clients, but the embedded worker never calls it.

## Ownership And Persistence

The worker remains the source of truth for conversation, thread, user,
authorization, inbound message, outbound reply, and retry records. It owns the
stable `turn_id` assigned to a message attempt.

Herdr remains the source of truth for terminal workspace, tab, pane, PTY,
agent-session, and runtime state. The worker stores only logical bindings:
conversation ID to runtime space and thread ID to runtime tab. It must not
persist socket paths or remote pane/session identifiers.

At startup, the worker asks the runtime to open or recreate each required
logical space. The runtime publishes lifecycle events directly. If a pane,
agent session, or terminal child is lost, the worker receives a typed event,
marks the binding unavailable, and recreates it before the next turn. This
removes snapshot polling and stale cross-process mappings.

Thread expiry remains seven days. The worker schedules expiry, requests runtime
tab closure, and marks its logical binding closed only after the runtime confirms
closure.

## Lifecycle And Failure Handling

The worker starts the runtime as a child subsystem using its existing Tokio
runtime and passes a cancellation token. Worker shutdown first stops new Nostr
turn intake, waits for or interrupts active turns according to the existing
delivery policy, shuts down Herdr PTYs, then completes Nostr shutdown.

Herdr runtime failure must be contained. A failed start or a terminal failure
returns a typed unavailable or failed result to the worker. The worker can use
its existing direct OpenCode executor only while the embedded runtime is not
available. A successful embedded runtime turn is always preferred.

The standalone host retains independent signal handling and executable handoff.
The embedded runtime does not attempt a standalone update/handoff because a
partial process replacement would violate worker ownership.

## Migration

1. Extract a compile-tested runtime library from Herdr without changing the
   standalone binary behaviour.
2. Port Herdr's socket server to a thin adapter around the runtime API.
3. Add the runtime as a path/git dependency of the phone Rust workspace.
4. Add an embedded runtime host to the worker behind a configuration flag.
5. Change worker routing to use the typed in-process API by default and retain
   the socket connector only as a temporary fallback during rollout.
6. Migrate persisted worker bindings from physical Herdr IDs to logical
   conversation/thread bindings. Treat old physical mappings as invalid and
   recreate runtime resources safely.
7. Validate an embedded deployment, remove the worker socket connector, and
   delete the temporary compatibility mapping fields.

Each stage must preserve a runnable standalone Herdr and a worker fallback path
until the embedded path has passed live validation.

## Tests And Acceptance Criteria

- Unit test runtime lifecycle, workspace/tab reuse, typed turn completion,
  interruption, timeout, duplicate `turn_id`, repeated identical prompt text,
  session loss, and shutdown.
- Test both hosts against the same runtime contract: standalone socket adapter
  and embedded worker host.
- Integration test a Nostr/FIPS request through the embedded worker to a typed
  OpenCode result, with no Unix socket connection attempted.
- Integration test runtime restart or pane loss: the next request recreates the
  logical resource and does not reuse a stale pane ID.
- Test cancellation: a successful interrupt yields one typed interrupted result;
  an interrupt transport/runtime error yields an explicit failure and never
  persists a normal reply.
- Verify worker restart closes embedded terminal resources and does not leave a
  standalone server or socket behind.
- Verify the standalone Herdr executable retains its existing local client and
  update/handoff behaviour.

## Rollout Decision

The embedded runtime is ready to become the only worker execution path when the
acceptance tests pass, the worker can recover a lost agent session without a
restart, and one live Nostr/FIPS request and cancellation have completed through
the embedded runtime. Only then remove the worker's Unix-socket Herdr connector.
