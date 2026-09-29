# Head-Agent Board Workstreams Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn each existing board task into a durable read-only task-agent workstream integrated by a private writable head agent.

**Architecture:** Reuse the shipped `workspace_board_tasks` Kanban as the card surface. Persist a root-thread and task-agent mapping for each task, use a private conversation head for serialized integration, and run OpenCode through persistent sandboxed server instances for each access mode.

**Tech Stack:** Rust, SQLite/rusqlite, Tokio, OpenCode HTTP/SSE API, Bubblewrap, Flutter.

---

### Task 1: Persist Board Workstream Ownership

**Files:**
- Modify: `rust/src/workspace.rs`
- Test: `rust/src/workspace.rs`

- [ ] Add a `workspace_board_task_workstreams` table with unique `task_id`,
  `root_message_id`, and `agent_id` columns, foreign keys to board tasks,
  messages, and agents.
- [ ] Add `WorkspaceBoardTaskWorkstream`, plus store methods to atomically link
  a task, root message, and agent; retrieve a task workstream; and delete a
  queued integration when a task is cancelled.
- [ ] Write store tests that prove a task cannot receive a second thread or
  agent, and that the persisted mapping survives reopening the SQLite store.
- [ ] Run `cargo test workspace::tests --lib` and confirm the new tests fail
  before the store implementation, then pass after it.

### Task 2: Create And Route Task Threads

**Files:**
- Modify: `rust/src/bin/nostr_codex_server.rs`
- Modify: `rust/src/protocol.rs`
- Modify: `lib/src/workspace_models.dart`
- Modify: `lib/src/main_widgets.dart`
- Test: `rust/src/bin/nostr_codex_server.rs`
- Test: `test/widget_test.dart`

- [ ] Extend board-task snapshot payloads with the optional linked root message
  ID and task-agent ID.
- [ ] When a board task is created, create one root message in its configured
  conversation, provision a task-agent session, persist its workstream link,
  and broadcast both the message and board update.
- [ ] Route task-thread messages only to the linked task agent. Do not queue
  them to the native conversation session.
- [ ] Make the Board details link open the stored task thread, not merely its
  parent conversation.
- [ ] Write a failing server test for one created task yielding one linked root
  and one task agent, then implement it and run the focused Rust test. Write a
  failing widget test for opening the linked task thread, then implement and
  run `flutter test test/widget_test.dart`.

### Task 3: Enforce Head And Task-Agent Access

**Files:**
- Modify: `rust/src/codex.rs`
- Modify: `rust/src/bin/nostr_codex_server.rs`
- Modify: `scripts/opencode-workdir-sandbox.sh`
- Test: `rust/src/codex.rs`
- Test: `test/install_worker_space_test.sh`

- [ ] Add an OpenCode workspace access enum to `CodexConfig`; propagate it to
  child commands as `OPENCODE_WORKSPACE_ACCESS`.
- [ ] Update the sandbox wrapper to bind the workdir read-only when access is
  `read-only` and read-write when access is `read-write`; reject unknown values.
- [ ] Configure the private conversation head as read-write and every board
  task agent as read-only.
- [ ] Write failing unit tests for access-mode command environments and shell
  tests for the wrapper's read-only bind. Implement only the required command
  and wrapper changes, then run the focused tests.

### Task 4: Use Persistent OpenCode Servers

**Files:**
- Modify: `rust/src/codex.rs`
- Test: `rust/src/codex.rs`

- [ ] Add a server manager keyed by workspace directory and access mode. It
  starts `opencode serve` through the sandbox wrapper, waits for
  `/global/health`, and retains the process handle until worker shutdown.
- [ ] Replace per-turn `opencode run` invocation with HTTP session creation,
  prompt submission, SSE event consumption, completion detection, and
  `/abort` cancellation. Keep persisted session IDs and existing retry rules.
- [ ] Write tests for request construction, session creation parsing, event
  filtering, completion, and abort URLs. Run `cargo test codex::tests --lib`.

### Task 5: Serialize Head Integration

**Files:**
- Modify: `rust/src/workspace.rs`
- Modify: `rust/src/bin/nostr_codex_server.rs`
- Test: `rust/src/workspace.rs`
- Test: `rust/src/bin/nostr_codex_server.rs`

- [ ] Add durable per-conversation integration queue records that reference a
  board task and proposal message.
- [ ] Have a task agent mark a proposal ready by writing a board timeline entry
  and enqueueing exactly one head integration request.
- [ ] Have the head process one request per conversation, update the task state
  and timeline, and notify the task agent with structured integration results.
  Do not insert a message authored by the head.
- [ ] On cancellation, remove queued requests and abort active task turns. On
  restart, mark an active integration blocked with an interrupted reason.
- [ ] Write failing tests for FIFO integration, cancellation, and no head chat
  message. Implement the queue and run the focused Rust tests.

### Task 6: Full Verification And Reviews

**Files:**
- Verify: `rust/src/codex.rs`
- Verify: `rust/src/workspace.rs`
- Verify: `rust/src/bin/nostr_codex_server.rs`
- Verify: `scripts/opencode-workdir-sandbox.sh`
- Verify: `lib/src/workspace_models.dart`
- Verify: `lib/src/main_widgets.dart`

- [ ] Run `cargo test` from `rust/`.
- [ ] Run `flutter test` from the repository root.
- [ ] Run `bash test/install_worker_space_test.sh`.
- [ ] Request two independent read-only reviews: one for correctness, state,
  errors, security, and compatibility; one for tests, regressions, complexity,
  and scope. Fix demonstrated findings and rerun the affected tests.
