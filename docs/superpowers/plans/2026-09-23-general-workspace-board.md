# General Workspace Board Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the scheduler-only board with a general Kanban board that supports human and agent work, configurable workflow, planning metadata, views, and delivery metrics.

**Architecture:** Replace the board-task records with durable board columns, cards, relations, activity, saved views, and optional automation records. The server keeps its existing native-turn scheduler but reads optional automation from a card and appends execution events to card activity. Flutter decodes complete board snapshots and renders configurable drag-and-drop columns, card details, filters, views, archive, and metrics.

**Tech Stack:** Rust, Tokio, rusqlite, serde, Flutter, Dart, existing Nostr/FIPS workspace transport.

---

## File Map

- `rust/src/workspace.rs`: schema, records, transactions, ranking, card activity, automation, and metric queries.
- `rust/src/protocol.rs`: board request and snapshot payloads.
- `rust/src/bin/nostr_codex_server.rs`: authorization, mutation dispatch, automation scheduling, and snapshot publication.
- `lib/src/workspace_models.dart`: immutable Dart board records and request/snapshot decoding.
- `lib/src/main_widgets.dart`: board UI, card editor, drag-and-drop, filters, saved views, archive, and metrics.
- `test/workspace_models_test.dart`: board snapshot and model tests.
- `test/widget_test.dart`: board interaction and permission tests.

### Task 1: Replace Store Records and Schema

**Files:**
- Modify: `rust/src/workspace.rs:139-328`
- Test: `rust/src/workspace.rs:3453-3643`

- [ ] **Step 1: Write failing store tests**

Add tests that create a board with default columns, create a card with member and agent assignees, move it between columns, archive and restore it, and assert activity is retained.

```rust
let board = store.workspace_board().unwrap();
assert_eq!(board.columns[0].name, "Backlog");
let card = store.create_board_card(&create).unwrap();
store.move_board_card(&card.id, &review_column, None).unwrap();
assert_eq!(store.board_card(&card.id).unwrap().column_id, review_column);
```

- [ ] **Step 2: Run the store test**

Run: `cargo test --manifest-path rust/Cargo.toml workspace::tests::board_card`

Expected: FAIL because card records and methods do not exist.

- [ ] **Step 3: Add the board schema and records**

Replace `workspace_board_tasks`, `workspace_board_runs`, `workspace_board_timeline`, and `workspace_board_turns` with `workspace_board_columns`, `workspace_board_cards`, `workspace_board_assignees`, `workspace_board_labels`, `workspace_board_card_labels`, `workspace_board_dependencies`, `workspace_board_activity`, `workspace_board_views`, `workspace_board_automation`, `workspace_board_automation_runs`, and `workspace_board_turns`. Drop the proof-of-concept tables during initialization because no persisted users exist.

Define `WorkspaceBoard`, `WorkspaceBoardColumn`, `WorkspaceBoardCard`, `WorkspaceBoardActivity`, `WorkspaceBoardAutomation`, and `WorkspaceBoardAutomationRun`. Store all changes and their revision updates in SQLite transactions.

- [ ] **Step 4: Add card lifecycle methods**

Implement `workspace_board`, `create_board_card`, `update_board_card`, `move_board_card`, `archive_board_card`, `restore_board_card`, and `delete_board_card`. Make card rank a `REAL`; choose the midpoint between neighboring cards and renormalize ranks to integer multiples of 1024 in one transaction when no representable midpoint remains. Append activity for every create, edit, move, archive, restore, and delete operation.

- [ ] **Step 5: Run the store test**

Run: `cargo test --manifest-path rust/Cargo.toml workspace::tests::board_card`

Expected: PASS.

### Task 2: Add Workflow and Planning Configuration

**Files:**
- Modify: `rust/src/workspace.rs`
- Test: `rust/src/workspace.rs`

- [ ] **Step 1: Write failing configuration tests**

Test column creation, rename, reorder, WIP limits, labels, card priority, estimate, due date, dependencies, and an overloaded-column query.

```rust
store.set_board_column_wip_limit(&column_id, Some(1)).unwrap();
store.move_board_card(&second.id, &column_id, None).unwrap();
assert!(store.workspace_board().unwrap().overloaded_column_ids.contains(&column_id));
```

- [ ] **Step 2: Run the configuration test**

Run: `cargo test --manifest-path rust/Cargo.toml workspace::tests::board_column`

Expected: FAIL because workflow configuration methods do not exist.

- [ ] **Step 3: Implement configuration and metadata mutations**

Implement create, update, reorder, and archive column operations; create and update labels; update card title, description, priority, estimate, due date, assignees, labels, and dependencies. Reject self-dependencies, duplicate dependencies, cycles, references outside the workspace, and assignment references that do not identify a member or configured agent.

- [ ] **Step 4: Run the configuration test**

Run: `cargo test --manifest-path rust/Cargo.toml workspace::tests::board_column`

Expected: PASS.

### Task 3: Move Automation to Optional Card Data

**Files:**
- Modify: `rust/src/workspace.rs`
- Modify: `rust/src/bin/nostr_codex_server.rs:2317-2663,6500-6647,7147-7165`
- Test: `rust/src/workspace.rs`
- Test: `rust/src/bin/nostr_codex_server.rs:13717-13757`

- [ ] **Step 1: Write failing automation tests**

Test that a card can have no automation, that an immediate automation run does not move its card column, and that a failed run is recorded as blocked without changing card workflow state.

```rust
let card = store.create_board_card(&create).unwrap();
store.set_board_card_automation(&card.id, &automation).unwrap();
store.block_board_automation_run(&run.id, "scope invalid").unwrap();
assert_eq!(store.board_card(&card.id).unwrap().column_id, ready_column);
```

- [ ] **Step 2: Run the automation test**

Run: `cargo test --manifest-path rust/Cargo.toml board_automation`

Expected: FAIL because automation is coupled to board-task state.

- [ ] **Step 3: Adapt scheduler and turn linkage**

Replace board-task lookups with automation-run lookups. Keep schedule validation, scope validation, native queueing, scoped cancellation, and single-active-turn-per-conversation behavior. Write queued, running, completed, blocked, failed, and cancelled automation events into card activity. Publish a full board snapshot after each state change.

- [ ] **Step 4: Run the automation test**

Run: `cargo test --manifest-path rust/Cargo.toml board_automation`

Expected: PASS.

### Task 4: Replace Board Wire Protocol

**Files:**
- Modify: `rust/src/protocol.rs:231-406,1533-1605,1973-2003,2421-2438,2607-2616`
- Modify: `rust/src/bin/nostr_codex_server.rs`
- Test: `rust/src/protocol.rs`

- [ ] **Step 1: Write failing protocol tests**

Cover create-card, move-card, configure-column, save-view, archive-card, and automation requests plus a snapshot containing columns, cards, relations, activity, views, and runs.

```rust
assert_eq!(request.action, "move_board_card");
assert_eq!(update.board.columns.len(), 5);
assert_eq!(update.board.cards[0].priority, "high");
```

- [ ] **Step 2: Run protocol tests**

Run: `cargo test --manifest-path rust/Cargo.toml protocol::tests::board`

Expected: FAIL because the legacy board payload is the only accepted format.

- [ ] **Step 3: Add typed card-board payloads and actions**

Replace `board_task` and flat task/timeline update fields with `board: WorkspaceBoardPayload`. Define request payloads for columns, cards, moves, labels, views, archive operations, and automation. Validate enum values, IDs, required fields, ranks, priorities, schedules, and filter values before dispatch.

- [ ] **Step 4: Dispatch authorized operations**

Allow members to create, edit, move, archive, restore, and save personal views. Require admin access for shared views, board configuration, label configuration, permanent deletion, and all automation changes. Publish the snapshot through the current revision and transport path.

- [ ] **Step 5: Run protocol tests**

Run: `cargo test --manifest-path rust/Cargo.toml protocol::tests::board`

Expected: PASS.

### Task 5: Add Views and Metrics

**Files:**
- Modify: `rust/src/workspace.rs`
- Test: `rust/src/workspace.rs`

- [ ] **Step 1: Write failing metrics tests**

Build a card history with creation, first active-column entry, and Done move. Assert lead time, cycle time, daily throughput, age for unfinished cards, and cumulative column counts at two timestamps.

```rust
assert_eq!(metrics.completed_throughput[0].count, 1);
assert_eq!(metrics.cards[0].cycle_time_seconds, Some(3600));
```

- [ ] **Step 2: Run metrics tests**

Run: `cargo test --manifest-path rust/Cargo.toml workspace::tests::board_metrics`

Expected: FAIL because board metrics are unavailable.

- [ ] **Step 3: Implement saved views and metric queries**

Store per-user and shared views with filters, sort field, sort direction, and swimlane. Add deterministic query helpers for search, assignee, label, priority, due date, automation state, archive state, and all supported sort/swinlane modes. Compute lead time, cycle time, throughput, ageing, and cumulative flow from activity timestamps for a requested inclusive date range.

- [ ] **Step 4: Run metrics tests**

Run: `cargo test --manifest-path rust/Cargo.toml workspace::tests::board_metrics`

Expected: PASS.

### Task 6: Decode the Replacement Board Model

**Files:**
- Modify: `lib/src/workspace_models.dart:935-1019`
- Modify: `test/workspace_models_test.dart`

- [ ] **Step 1: Write failing model tests**

Create a snapshot with custom columns, a card, people and agent assignees, label, dependency, automation run, activity, and saved view. Assert a newer `board_updated` snapshot replaces each collection.

```dart
expect(state.board.cards.single.assigneeIds, ['member:alice', 'agent:build']);
expect(state.board.columns.single.wipLimit, 2);
```

- [ ] **Step 2: Run model tests**

Run: `flutter test test/workspace_models_test.dart --plain-name "workspace board"`

Expected: FAIL because the client only decodes scheduled tasks.

- [ ] **Step 3: Add immutable models and snapshot replacement**

Replace `WorkspaceBoardTask` and `WorkspaceBoardTimelineEntry` with immutable board, column, card, relation, activity, automation, run, view, and metrics models. Decode `WorkspaceUpdate.board`, retain it in `WorkspaceState`, cache it, and replace it only when the incoming workspace revision is newer.

- [ ] **Step 4: Run model tests**

Run: `flutter test test/workspace_models_test.dart --plain-name "workspace board"`

Expected: PASS.

### Task 7: Implement the Board MVP UI

**Files:**
- Modify: `lib/src/main_widgets.dart:810-1257`
- Modify: `test/widget_test.dart:194-344`

- [ ] **Step 1: Write failing widget tests**

Add an admin fixture with custom columns and an overloaded column. Assert cards display metadata and WIP warning, a member can move a card but cannot configure a column, and an archived card is absent until archive view is selected.

```dart
expect(find.text('WIP limit exceeded'), findsOneWidget);
expect(find.text('Configure board'), findsNothing);
```

- [ ] **Step 2: Run widget tests**

Run: `flutter test test/widget_test.dart --plain-name "workspace board"

Expected: FAIL because fixed execution-state columns render instead.

- [ ] **Step 3: Render columns, cards, and editing**

Replace fixed columns with snapshot columns. Use Flutter drag targets and draggable cards to emit `move_board_card` with neighboring-card position. Provide card create/edit details for title, description, assignees, priority, labels, estimate, due date, dependencies, and optional automation. Add archive, restore, and admin-only board configuration flows.

- [ ] **Step 4: Add discovery and reporting controls**

Add search, multi-field filters, sorting, saved views, swimlane grouping, archive selection, metrics range selection, metric summaries, and a cumulative-flow chart made from standard Flutter paint primitives. Keep board cards usable in narrow mobile widths and horizontally scrollable columns on desktop.

- [ ] **Step 5: Run widget tests**

Run: `flutter test test/widget_test.dart --plain-name "workspace board"

Expected: PASS.

### Task 8: Verify the Complete Replacement

**Files:**
- Modify: only files required by test failures.

- [ ] **Step 1: Format source**

Run: `cargo fmt --manifest-path rust/Cargo.toml --check`

Run: `dart format --set-exit-if-changed lib/src/workspace_models.dart lib/src/main_widgets.dart test/workspace_models_test.dart test/widget_test.dart`

- [ ] **Step 2: Run Rust tests**

Run: `cargo test --manifest-path rust/Cargo.toml`

Expected: PASS.

- [ ] **Step 3: Run Flutter tests**

Run: `flutter test`

Expected: PASS.

- [ ] **Step 4: Inspect the final change set**

Run: `git diff --check`

Expected: no output.
