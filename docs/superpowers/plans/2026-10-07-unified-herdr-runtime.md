# Unified Herdr Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run Herdr terminal and agent execution in the Linux Nostr/FIPS worker process through a typed Rust API, while retaining standalone Herdr.

**Architecture:** Extract a `herdr-runtime` library from Herdr. The existing Herdr executable hosts that library behind its client sockets; the worker embeds the same library and calls it directly. Nostr remains the owner of authorization, delivery, and message persistence; Herdr owns terminals and agent execution.

**Tech Stack:** Rust, Tokio, SQLite/rusqlite, Herdr PTY runtime, OpenCode typed completion plugin, Nostr/FIPS worker.

---

## File Structure

- `/home/tom/code/herdr/Cargo.toml`: add the runtime library target and keep the executable target.
- `/home/tom/code/herdr/src/lib.rs`: define the public runtime boundary and re-export only supported types.
- `/home/tom/code/herdr/src/runtime.rs`: own embedded-safe startup, command dispatch, event subscription, and shutdown.
- `/home/tom/code/herdr/src/runtime/types.rs`: typed configuration, logical target, turn, result, and lifecycle event contracts.
- `/home/tom/code/herdr/src/server/headless/bootstrap.rs`: reduce to standalone process/bootstrap policy and construct the runtime host.
- `/home/tom/code/herdr/src/api/server.rs`: translate socket JSON requests into runtime calls, retaining standalone compatibility.
- `/home/tom/code/herdr/src/server/headless.rs`: move only host-independent lifecycle operations behind the runtime facade; preserve standalone rendering/client policy.
- `/home/tom/code/phone/rust/Cargo.toml`: depend on the reviewed Herdr runtime revision.
- `/home/tom/code/phone/rust/src/herdr_runtime.rs`: phone-owned adapter from runtime types to Nostr worker semantics.
- `/home/tom/code/phone/rust/src/workspace.rs`: persist logical conversation/thread bindings and durable worker turn IDs, not pane/socket/session IDs.
- `/home/tom/code/phone/rust/src/bin/nostr_codex_server.rs`: start/shut down the embedded runtime, route provisioning and turns through the adapter, and remove the connector after rollout.

### Task 1: Define The Embedded-Safe Herdr Runtime Contract

**Files:**
- Create: `/home/tom/code/herdr/src/lib.rs`
- Create: `/home/tom/code/herdr/src/runtime.rs`
- Create: `/home/tom/code/herdr/src/runtime/types.rs`
- Modify: `/home/tom/code/herdr/Cargo.toml`
- Test: `/home/tom/code/herdr/src/runtime.rs`

- [ ] **Step 1: Write contract tests before implementation.**

```rust
#[tokio::test]
async fn repeated_text_with_distinct_turn_ids_starts_distinct_turns() {
    let runtime = test_runtime().await;
    let session = runtime.open_agent(LogicalTarget::thread("c", "t")).await.unwrap();
    runtime.submit_turn(&session, TurnId::new("delivery-1"), "same").await.unwrap();
    runtime.submit_turn(&session, TurnId::new("delivery-2"), "same").await.unwrap();
    assert_eq!(runtime.started_turn_count(&session).await, 2);
}
```

- [ ] **Step 2: Run the new test and verify it fails because no runtime library exists.**

Run: `cargo test runtime::tests::repeated_text_with_distinct_turn_ids_starts_distinct_turns`

Expected: compile failure for missing `runtime` module.

- [ ] **Step 3: Add the public types and runtime handle.**

```rust
pub struct RuntimeHandle { inner: Arc<RuntimeInner> }
pub enum LogicalTarget { Conversation { conversation_id: String }, Thread { conversation_id: String, thread_id: String } }
pub struct TurnId(String);
pub enum TurnResult { Completed { text: String }, Interrupted, Failed { message: String }, Unavailable, TimedOut }
pub enum RuntimeEvent { TargetLost(LogicalTarget), AgentLost(LogicalTarget), TurnFinished { turn_id: TurnId, result: TurnResult } }

impl RuntimeHandle {
    pub async fn start(config: RuntimeConfig) -> Result<Self, RuntimeError>;
    pub async fn open_agent(&self, target: LogicalTarget) -> Result<AgentSession, RuntimeError>;
    pub async fn submit_turn(&self, session: &AgentSession, turn_id: TurnId, text: String, deadline: Duration) -> TurnResult;
    pub async fn interrupt_turn(&self, session: &AgentSession, turn_id: &TurnId) -> TurnResult;
    pub fn subscribe(&self) -> broadcast::Receiver<RuntimeEvent>;
    pub async fn shutdown(&self) -> Result<(), RuntimeError>;
}
```

`RuntimeConfig` must accept state/data paths, a cancellation token, and terminal/OpenCode configuration. It must not accept process arguments or install signals.

- [ ] **Step 4: Run focused contract tests.**

Run: `cargo test runtime::tests -- --test-threads=1`

Expected: PASS.

- [ ] **Step 5: Commit the contract-only extraction.**

```bash
git add Cargo.toml Cargo.lock src/lib.rs src/runtime.rs src/runtime/types.rs
git commit -m "feat: add embeddable Herdr runtime contract"
```

### Task 2: Adapt Herdr Terminal Ownership To The Runtime Contract

**Files:**
- Modify: `/home/tom/code/herdr/src/app/mod.rs`
- Modify: `/home/tom/code/herdr/src/app/api/agents.rs`
- Modify: `/home/tom/code/herdr/src/terminal/state.rs`
- Modify: `/home/tom/code/herdr/src/server/headless.rs`
- Modify: `/home/tom/code/herdr/src/runtime.rs`
- Test: `/home/tom/code/herdr/src/runtime.rs`

- [ ] **Step 1: Add failing runtime tests for logical resource reuse, interruption, target loss, and shutdown.**

```rust
#[tokio::test]
async fn lost_target_is_recreated_for_the_next_turn() { /* emit TargetLost; assert a new pane/session is used */ }
#[tokio::test]
async fn interrupt_returns_one_interrupted_result_and_never_a_completion() { /* start, interrupt, assert one result */ }
#[tokio::test]
async fn shutdown_closes_owned_terminal_children() { /* start pane, shutdown, assert child exit */ }
```

- [ ] **Step 2: Run the tests and verify missing behavior.**

Run: `cargo test runtime::tests -- --test-threads=1`

Expected: FAIL on the new assertions.

- [ ] **Step 3: Implement runtime-owned logical target registry.**

Map each `LogicalTarget` to the current workspace/tab/pane/agent session inside `RuntimeInner`. Reuse existing terminal and agent-turn state machinery; only the mapping becomes private runtime state. On pane/session loss, remove the mapping and publish `RuntimeEvent::TargetLost`. Associate settled results with `(session, TurnId)`, retaining results only for exact retry IDs.

- [ ] **Step 4: Run runtime tests and the existing Herdr agent tests.**

Run: `cargo test runtime::tests && cargo test agent --lib`

Expected: PASS.

- [ ] **Step 5: Commit terminal-runtime integration.**

```bash
git add src/app/mod.rs src/app/api/agents.rs src/terminal/state.rs src/server/headless.rs src/runtime.rs
git commit -m "feat: run Herdr agents through runtime handle"
```

### Task 3: Keep Standalone Herdr As A Socket Adapter

**Files:**
- Modify: `/home/tom/code/herdr/src/server/headless/bootstrap.rs`
- Modify: `/home/tom/code/herdr/src/api/server.rs`
- Modify: `/home/tom/code/herdr/src/api/schema.rs`
- Modify: `/home/tom/code/herdr/src/api/wait.rs`
- Test: `/home/tom/code/herdr/src/api/server/subscription_socket_tests.rs`
- Test: `/home/tom/code/herdr/src/server/headless/tests/mod.rs`

- [ ] **Step 1: Add socket-adapter parity tests.**

Test `agent.turn`, `agent.interrupt`, `session.snapshot`, and subscription requests against a runtime-backed standalone server. Assert the adapter returns the exact typed runtime outcome and that a repeated request ID returns the retained result.

- [ ] **Step 2: Run parity tests and verify the pre-extraction adapter does not use `RuntimeHandle`.**

Run: `cargo test subscription_socket_tests -- --test-threads=1`

Expected: FAIL until the adapter delegates to the runtime.

- [ ] **Step 3: Convert standalone bootstrap and socket dispatch.**

Start `RuntimeHandle` from `run_server`, pass it to the JSON API and binary-client adapters, and keep CLI parsing, local sockets, signals, and live-handoff policy in the executable host. Do not create a Tokio runtime within `herdr-runtime`; `run_server` retains that responsibility for standalone mode.

- [ ] **Step 4: Run standalone regression tests.**

Run: `cargo test subscription_socket_tests && cargo test headless --lib && cargo check --all-targets`

Expected: PASS.

- [ ] **Step 5: Commit the adapter conversion.**

```bash
git add src/server/headless/bootstrap.rs src/api/server.rs src/api/schema.rs src/api/wait.rs src/server/headless/tests src/api/server/subscription_socket_tests.rs
git commit -m "refactor: host standalone Herdr through runtime"
```

### Task 4: Add Embedded Runtime Dependency And Logical Worker State

**Files:**
- Modify: `/home/tom/code/phone/rust/Cargo.toml`
- Modify: `/home/tom/code/phone/rust/Cargo.lock`
- Create: `/home/tom/code/phone/rust/src/herdr_runtime.rs`
- Modify: `/home/tom/code/phone/rust/src/lib.rs`
- Modify: `/home/tom/code/phone/rust/src/workspace.rs`
- Test: `/home/tom/code/phone/rust/src/workspace.rs`
- Test: `/home/tom/code/phone/rust/src/herdr_runtime.rs`

- [ ] **Step 1: Add failing tests for logical bindings and durable worker turn IDs.**

```rust
#[test]
fn same_delivery_reuses_turn_id_but_same_text_in_two_messages_does_not() { /* persist two message ids with same body */ }
#[test]
fn legacy_physical_mapping_is_not_used_as_an_embedded_target() { /* migrate old rows and assert logical binding is unready */ }
```

- [ ] **Step 2: Run the tests and verify they fail.**

Run: `cargo test --lib workspace::tests::same_delivery_reuses_turn_id_but_same_text_in_two_messages_does_not`

Expected: FAIL until logical binding schema exists.

- [ ] **Step 3: Add the reviewed Herdr runtime revision and phone adapter.**

The adapter must expose `open_conversation`, `open_thread`, `submit_turn`, `interrupt_turn`, `subscribe`, and `shutdown`. Convert runtime results to the worker's existing response/cancellation types. It must not open a Unix socket or retain pane IDs.

- [ ] **Step 4: Migrate workspace persistence.**

Add a schema migration with tables keyed by conversation/thread IDs plus `ready`, `closed_at`, and worker-owned `turn_id`. Preserve old physical mapping rows only for socket-fallback rollout; embedded routing must ignore them.

- [ ] **Step 5: Run adapter and persistence tests.**

Run: `cargo test --lib herdr_runtime && cargo test --lib workspace`

Expected: PASS.

- [ ] **Step 6: Commit phone dependency and logical state.**

```bash
git add rust/Cargo.toml rust/Cargo.lock rust/src/herdr_runtime.rs rust/src/lib.rs rust/src/workspace.rs
git commit -m "feat: add embedded Herdr runtime adapter"
```

### Task 5: Route The Worker Through The Embedded Runtime

**Files:**
- Modify: `/home/tom/code/phone/rust/src/bin/nostr_codex_server.rs`
- Modify: `/home/tom/code/phone/rust/src/herdr.rs`
- Test: `/home/tom/code/phone/rust/src/bin/nostr_codex_server.rs`

- [ ] **Step 1: Add worker routing tests.**

```rust
#[tokio::test]
async fn embedded_runtime_is_preferred_without_opening_a_unix_socket() { /* fake runtime; assert direct executor unused */ }
#[tokio::test]
async fn repeated_prompt_text_gets_a_new_turn_id_for_a_new_delivery() { /* two stored messages; assert IDs differ */ }
#[tokio::test]
async fn runtime_loss_reopens_logical_target_on_next_request() { /* emit loss; assert reopen then submit */ }
```

- [ ] **Step 2: Run the tests and verify failure under socket routing.**

Run: `cargo test --bin nostr-codex-server embedded_runtime -- --test-threads=1`

Expected: FAIL until the embedded route is selected.

- [ ] **Step 3: Start one runtime in `run_worker_runtime`.**

Construct the phone adapter using the existing worker cancellation control. Pass it explicitly through worker state; do not add a global registry. Start an event subscriber task owned by worker shutdown that invalidates logical bindings on loss events. Schedule expiry through `close_thread` and mark rows closed only after it succeeds.

- [ ] **Step 4: Replace provisioning and turn routing.**

Replace `HERDR_SOCKET_PATH` provisioning and `HerdrClient::agent_turn` use with adapter calls. Use a durable message-delivery ID for `TurnId`, not a prompt hash. On successful interrupt, await the typed interrupted result; on interrupt error, propagate failure and never persist a normal reply. Use direct OpenCode only when runtime startup or a runtime request explicitly returns unavailable.

- [ ] **Step 5: Make shutdown cooperative.**

Replace the root `std::process::exit(0)` path with worker shutdown coordination: stop intake, settle or interrupt active turns, await runtime shutdown, stop owned tasks, then close Nostr resources.

- [ ] **Step 6: Run focused worker tests.**

Run: `cargo test --bin nostr-codex-server embedded_runtime && cargo test --bin nostr-codex-server cancellation && cargo test --lib`

Expected: PASS.

- [ ] **Step 7: Commit embedded routing.**

```bash
git add rust/src/bin/nostr_codex_server.rs rust/src/herdr.rs rust/src/herdr_runtime.rs rust/src/workspace.rs
git commit -m "feat: route worker turns through embedded Herdr"
```

### Task 6: Validate, Roll Out, And Remove The Worker Socket Connector

**Files:**
- Delete: `/home/tom/code/phone/rust/src/herdr.rs` socket connector portions after live rollout
- Modify: `/home/tom/code/phone/rust/src/workspace.rs`
- Modify: `/home/tom/code/phone/rust/src/bin/nostr_codex_server.rs`
- Test: `/home/tom/code/phone/rust/src/bin/nostr_codex_server.rs`

- [ ] **Step 1: Add removal-gate tests.**

Assert the worker embedded configuration has no `HERDR_SOCKET_PATH` read, no `UnixStream` connection, and no physical pane ID lookup for a turn. Keep standalone Herdr socket tests in the Herdr repository.

- [ ] **Step 2: Run full local verification before a live test.**

Run: `cargo test --lib && cargo test --bin nostr-codex-server --no-run && cargo check --all-targets`

Expected: PASS, except documented pre-existing environment-only failures.

- [ ] **Step 3: Run live acceptance checks.**

Use one Nostr DM and one FIPS request through the embedded worker. Verify a typed completion, a cancellation with no reply persistence, pane/session loss followed by recreation, worker shutdown with child cleanup, and standalone Herdr client operation.

- [ ] **Step 4: Delete worker-only compatibility paths only after recorded acceptance success.**

Remove socket connector/reconnect/snapshot code and physical mapping compatibility reads from the worker. Do not remove the Herdr standalone socket adapter.

- [ ] **Step 5: Run final verification and two independent reviews.**

Run: `cargo test --lib && cargo test --bin nostr-codex-server --no-run && git diff --check`

Expected: PASS. Request one correctness review and one scope/regression review before release.

- [ ] **Step 6: Commit the completed migration.**

```bash
git add rust/src/bin/nostr_codex_server.rs rust/src/workspace.rs rust/src/herdr_runtime.rs rust/src/herdr.rs rust/src/lib.rs
git commit -m "refactor: remove worker Herdr socket integration"
```

## Plan Review

- Spec coverage: tasks 1-3 preserve standalone Herdr while extracting the typed runtime; tasks 4-5 embed it, migrate logical persistence, route direct turns, handle failure and orderly shutdown; task 6 validates and removes compatibility code.
- Scope: the plan deliberately excludes client/TUI redesign, Nostr ownership changes, and repository merging.
- Consistency: `RuntimeHandle`, `LogicalTarget`, and `TurnId` are defined in task 1 and used by all later tasks. The worker owns durable delivery turn IDs; the runtime owns physical terminal IDs.
