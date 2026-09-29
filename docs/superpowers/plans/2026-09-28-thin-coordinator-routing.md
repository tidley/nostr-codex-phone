# Thin Coordinator Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route each workspace thread to a native OpenCode session while a visible, single coordinator session serializes repository changes after explicit in-thread mentions.

**Architecture:** The worker keeps only authenticated delivery, conversation/thread-to-session mappings, and a one-turn coordinator gate. Thread agents and the coordinator are native OpenCode sessions. An explicit coordinator mention is the only integration trigger; the coordinator responds in the originating thread.

**Tech Stack:** Rust, SQLite workspace store, OpenCode CLI/HTTP sessions, Nostr and FIPS transport.

---

### Task 1: Define Explicit Coordinator Routing

**Files:**
- Modify: `rust/src/bin/nostr_codex_server.rs`
- Test: `rust/src/bin/nostr_codex_server.rs`

- [ ] Add failing unit tests for explicit coordinator mentions routing only to the conversation coordinator and preserving the triggering thread ID.
- [ ] Run: `cargo test --manifest-path rust/Cargo.toml --bin nostr-codex-server explicit_coordinator`
- [ ] Implement the minimal routing predicate and pass the original parent ID to the coordinator turn.
- [ ] Re-run the focused test.

### Task 2: Serialize Coordinator Turns

**Files:**
- Modify: `rust/src/bin/nostr_codex_server.rs`
- Test: `rust/src/bin/nostr_codex_server.rs`

- [ ] Add a failing test that a second explicit coordinator mention waits while the first coordinator turn is active.
- [ ] Run: `cargo test --manifest-path rust/Cargo.toml --bin nostr-codex-server coordinator_turn`
- [ ] Add one coordinator queue per conversation; do not add board scheduling or automatic proposal detection.
- [ ] Re-run the focused test.

### Task 3: Make Coordinator Replies Visible

**Files:**
- Modify: `rust/src/bin/nostr_codex_server.rs`
- Test: `rust/src/bin/nostr_codex_server.rs`

- [ ] Add a failing test that the coordinator response is stored and broadcast as a reply in the triggering thread.
- [ ] Run: `cargo test --manifest-path rust/Cargo.toml --bin nostr-codex-server coordinator_reply`
- [ ] Persist and broadcast the coordinator response with the source thread parent ID.
- [ ] Re-run the focused test.

### Task 4: Remove Implicit Integration Paths

**Files:**
- Modify: `rust/src/bin/nostr_codex_server.rs`
- Test: `rust/src/bin/nostr_codex_server.rs`

- [ ] Add failing tests that unmentioned thread messages neither queue nor invoke the coordinator.
- [ ] Run: `cargo test --manifest-path rust/Cargo.toml --bin nostr-codex-server unmentioned_coordinator`
- [ ] Remove automatic coordinator dispatch paths while retaining independent thread sessions.
- [ ] Re-run the focused test.

### Task 5: Verify And Deliver

**Files:**
- Test: `rust/src/bin/nostr_codex_server.rs`

- [ ] Run focused coordinator tests, `cargo test --manifest-path rust/Cargo.toml --bin nostr-codex-server`, and `git diff --check`.
- [ ] Request independent correctness and regression reviews; fix demonstrated findings.
- [ ] Stage, commit, and push the reviewed implementation.
