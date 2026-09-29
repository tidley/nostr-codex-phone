# Shared Workspace Kanban Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an admin-managed shared board that schedules native conversation-agent work and reports compact progress to all workspace clients.

**Architecture:** Extend the existing workspace SQLite store with board tables and typed board payloads in the normal workspace request and update messages. Add the board fields to every `WorkspaceUpdate` constructor. Run a scheduler in the existing worker process and route each claimed task into the conversation's native serial queue. Add a top-level Board section that reads the typed snapshot data and sends admin board actions through the current request path.

**Tech Stack:** Rust, Tokio, rusqlite, serde, Flutter, Dart, existing Nostr and FIPS workspace transport.

---

## File Map

- `rust/src/workspace.rs`: board records, schema migration, schedule calculation, atomic run claims, and snapshot access.
- `rust/src/protocol.rs`: typed board request, task, timeline, and snapshot payloads.
- `rust/src/bin/nostr_codex_server.rs`: authorise board actions, run the scheduler, enqueue native turns, and publish updates.
- `lib/src/workspace_models.dart`: decode and retain board snapshots.
- `lib/src/main_widgets.dart`: top-level Board section and admin-only controls.
- `test/workspace_models_test.dart`: client board decoding and revision tests.
- `rust/src/workspace.rs` tests: schedule, state, access, and duplicate-claim tests.

### Task 1: Add Durable Board Records

**Files:**
- Modify: `rust/src/workspace.rs`

- [ ] **Step 1: Write failing store tests**

Add tests near the existing `WorkspaceStore` tests. Verify a created one-time task returns in a board snapshot. Verify a claimed due run cannot be claimed twice. Verify a failed run changes the task state to `blocked`.

```rust
assert_eq!(store.board_tasks().unwrap()[0].state, "scheduled");
assert!(store.claim_due_board_task(task_id, now).unwrap().is_some());
assert!(store.claim_due_board_task(task_id, now).unwrap().is_none());
```

- [ ] **Step 2: Run the store tests**

Run: `cargo test --manifest-path rust/Cargo.toml workspace::tests`

Expected: FAIL because board store methods and tables do not exist.

- [ ] **Step 3: Add board types and schema migration**

Add `WorkspaceBoardTask`, `WorkspaceBoardRun`, and `WorkspaceBoardTimelineEntry` types. Add tables for tasks, runs, and timeline entries. Store conversation target, instruction, scope JSON, schedule JSON, state, next run time, and timestamps.

Create the run and state change in one SQLite transaction. Use a unique task/run timestamp key to prevent duplicate starts after a restart.

- [ ] **Step 4: Add schedule calculation and state methods**

Support one-time, daily, weekdays, weekly, and monthly rules. Add methods to create, update, cancel, retry, claim, start, complete, and block tasks. A recurring task returns to `scheduled` after completion. A one-time task moves to `done`.

- [ ] **Step 5: Run the store tests**

Run: `cargo test --manifest-path rust/Cargo.toml workspace::tests`

Expected: PASS.

### Task 2: Extend the Workspace Wire Format

**Files:**
- Modify: `rust/src/protocol.rs`
- Modify: `rust/src/workspace.rs`

- [ ] **Step 1: Write failing protocol tests**

Add a parse test for a `create_board_task` request with a task title, conversation target, instruction, scope, and schedule. Add a serialisation test that retains board tasks and timeline entries in `WorkspaceUpdate`.

- [ ] **Step 2: Run the protocol tests**

Run: `cargo test --manifest-path rust/Cargo.toml protocol::tests`

Expected: FAIL because board request and update fields do not exist.

- [ ] **Step 3: Add request and update payloads**

Add `WorkspaceBoardTaskPayload` and `WorkspaceBoardTimelinePayload`. Add a typed optional `board_task` to `WorkspaceRequest`. Add `board_tasks` and `board_timeline_entries` to `WorkspaceUpdate`. Add empty board collections to every existing `WorkspaceUpdate` struct literal.

- [ ] **Step 4: Add workspace payload conversion**

Convert store records to protocol payloads in the existing workspace snapshot path. Preserve empty defaults so older clients can parse updates.

- [ ] **Step 5: Run the protocol tests**

Run: `cargo test --manifest-path rust/Cargo.toml protocol::tests`

Expected: PASS.

### Task 3: Authorise Board Actions and Schedule Runs

**Files:**
- Modify: `rust/src/bin/nostr_codex_server.rs`
- Modify: `rust/src/workspace.rs`

- [ ] **Step 1: Write failing worker tests**

Test that a non-admin `create_board_task` request fails. Test that an admin task for a busy conversation stays queued. Test that a failed native turn changes its task to blocked.

- [ ] **Step 2: Run the focused worker tests**

Run: `cargo test --manifest-path rust/Cargo.toml --bin nostr_codex_server board`

Expected: FAIL because board request handling and scheduling do not exist.

- [ ] **Step 3: Add admin request handling**

Add board mutation actions to `workspace_action_requires_admin`. Validate target conversations and declared folder scope before task creation. Use the existing workspace update publishing function after each mutation.

- [ ] **Step 4: Add the in-process scheduler**

Start one Tokio interval in `run_worker_runtime`. On startup and each tick, atomically claim due tasks. If the target native queue is busy, mark the task queued. Otherwise create the durable native turn and enqueue it through `WorkspaceAgentQueues::enqueue_native`.

- [ ] **Step 5: Connect native turn lifecycle to board state**

When a board turn starts, append a Started entry and mark it Running. Forward bounded work-history events as Working entries. On successful completion, mark the run complete. On any worker error, mark the task Blocked and append the error.

- [ ] **Step 6: Run focused worker tests**

Run: `cargo test --manifest-path rust/Cargo.toml --bin nostr_codex_server board`

Expected: PASS.

### Task 4: Decode Board Snapshots in Flutter

**Files:**
- Modify: `lib/src/workspace_models.dart`
- Modify: `test/workspace_models_test.dart`

- [ ] **Step 1: Write failing Dart tests**

Add a snapshot with one running board task and timeline entry. Assert that `WorkspaceState.apply` stores both. Add an update with a later revision and assert it replaces the task state.

- [ ] **Step 2: Run the Dart test**

Run: `flutter test test/workspace_models_test.dart`

Expected: FAIL because the board fields are ignored.

- [ ] **Step 3: Add immutable board model classes**

Add `WorkspaceBoardTask` and `WorkspaceBoardTimelineEntry`. Decode the typed `board_tasks` and `board_timeline_entries` fields from each workspace update. Retain them in `WorkspaceState` and cached snapshots.

- [ ] **Step 4: Run the Dart test**

Run: `flutter test test/workspace_models_test.dart`

Expected: PASS.

### Task 5: Add the Top-Level Board UI

**Files:**
- Modify: `lib/src/main_widgets.dart`
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Write failing widget tests**

Add an admin workspace fixture with one blocked task. Assert that the Board section shows the task and Retry control. Add a member fixture and assert that Retry is absent.

- [ ] **Step 2: Run the focused widget test**

Run: `flutter test test/widget_test.dart --plain-name "workspace board"`

Expected: FAIL because the Board section does not exist.

- [ ] **Step 3: Add Board navigation and columns**

Add Board as a top-level workspace section. Group tasks into Scheduled, Queued, Running, Blocked, and Done. Show title, target conversation, next run, and latest timeline entry on every card.

- [ ] **Step 4: Add task details and admin controls**

Open a compact timeline when the user selects a card. Add a conversation link. Show create, edit, retry, cancel, and move controls only when the current member is an admin. Send actions through the existing `onRequest` callback.

- [ ] **Step 5: Run the focused widget test**

Run: `flutter test test/widget_test.dart --plain-name "workspace board"`

Expected: PASS.

### Task 6: Run End-to-End Verification

**Files:**
- Modify: only files required by test failures from Tasks 1 to 5.

- [ ] **Step 1: Format Rust and Dart code**

Run: `cargo fmt --manifest-path rust/Cargo.toml --check`

Run: `dart format --set-exit-if-changed lib/src/workspace_models.dart lib/src/main_widgets.dart test/workspace_models_test.dart test/widget_test.dart`

- [ ] **Step 2: Run Rust verification**

Run: `cargo test --manifest-path rust/Cargo.toml`

Expected: PASS.

- [ ] **Step 3: Run Flutter verification**

Run: `flutter test test/workspace_models_test.dart test/widget_test.dart`

Expected: PASS, or report pre-existing unrelated failures separately.

- [ ] **Step 4: Inspect the final change set**

Run: `git diff --check`

Expected: no output.
