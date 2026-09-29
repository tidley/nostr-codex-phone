# Coordinator Handoff And Cancellation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reliably run the conversation Coordinator after an agent-authored `@Coordinator` handoff, including process recovery and retry, and clear accepted cancellations from the typing UI immediately.

**Architecture:** Persist the agent reply and one durable outbox entry for every structured agent mention before notifying the runtime. The runtime owns agent queues, submits pending entries at startup and on a short retry tick, and marks an entry delivered only after its targeted job succeeds. The job reuses its persisted reply as the trigger, so Coordinator routing uses the established queue, conversation scope, and parent-thread behavior without recursive async routing. Use the existing typing wire update with an expired lease to clear a cancelled agent while the OpenCode task unwinds.

**Tech Stack:** Rust, Tokio, SQLite workspace store, Flutter/Dart, `cargo test`, Flutter test.

---

### Task 1: Route Persisted Coordinator Handoffs

**Files:**
- Modify: `rust/src/bin/nostr_codex_server.rs:8452-8589`
- Test: `rust/src/bin/nostr_codex_server.rs`

- [ ] **Step 1: Write the failing handoff-notification test**

Add a `WorkspaceAgentHandoff` value type near `WorkspaceAgentJob` with a conversation, persisted reply ID, and target agent ID. Add a pure helper that selects only agent IDs from structured mentions. Test that it selects exactly the Coordinator mention:

```rust
#[test]
fn workspace_agent_handoff_targets_only_structured_agent_mentions() {
    let mentions = vec![WorkspaceMentionPayload {
        kind: "agent".to_string(),
        id: "coordinator".to_string(),
        label: "Coordinator".to_string(),
    }];
    assert_eq!(
        workspace_agent_handoff_targets(&mentions),
        vec!["coordinator".to_string()]
    );
}
```

- [ ] **Step 2: Run the test and verify it fails because the handoff API is absent**

Run: `cargo test --manifest-path rust/Cargo.toml --bin nostr-codex-server agent_reply_handoff_selects_only_targeted_agents`

Expected: FAIL with an unresolved `WorkspaceAgentHandoff` or `workspace_agent_handoff_targets` symbol.

- [ ] **Step 3: Add runtime-owned handoff delivery**

Add an `mpsc::UnboundedSender<WorkspaceAgentHandoff>` and matching receiver to `WorkspaceAgentQueues`, mirroring the existing board-integration channel. Pass a clone of the sender into `workspace_agent_queue_worker` and then `process_workspace_agent_job` and `route_conversation_agents`.

After a reply is persisted, queue one workspace-store handoff outbox entry for every agent mention before sending the in-memory notification. The handoff must contain the reply's `WorkspaceConversation`, persisted reply ID, and target agent ID. Do not call `route_conversation_agents` recursively.

```rust
workspace.queue_agent_handoffs(&message_id, &handoff_mentions)?;
for agent_id in workspace_agent_handoff_targets(&handoff_mentions) {
    handoff_sender.send(WorkspaceAgentHandoff {
        conversation: workspace_conversation(channel_id, member, peer)
            .context("workspace agent reply is missing a conversation")?,
        persisted_reply_id: message_id.clone(),
        agent_id,
    })?;
}
```

- [ ] **Step 4: Consume, recover, and retry durable handoffs in the runtime loop**

Add a `tokio::select!` branch beside `board_integration_results.recv()` in `run_worker_runtime`. For each received handoff, enqueue its target once using the handoff conversation and persisted reply ID. Before the receive loop, submit all pending handoff entries from the workspace store; add a periodic retry tick that submits pending entries again. Use an in-memory `(reply_id, agent_id)` claim while a job is queued, release it when enqueue fails, and mark the outbox entry delivered only after that targeted job succeeds. The coordinator job will then load the reply, retain its parent ID, and route only its structured mention through the existing routing predicate.

- [ ] **Step 5: Run the focused test and confirm it passes**

Run: `cargo test --manifest-path rust/Cargo.toml --bin nostr-codex-server workspace_agent_handoff_targets_only_structured_agent_mentions`

Expected: PASS.

- [ ] **Step 6: Add durable recovery and no-handoff regression tests**

Add tests that reopen pending channel and direct handoffs from the workspace store, select them on the retry tick, and mark an entry delivered only after the queued job succeeds. Also test that `workspace_agent_handoff_targets` returns an empty list for empty mentions. This proves process interruption cannot discard a handoff and ordinary agent replies cannot schedule the Coordinator.

- [ ] **Step 7: Run both routing tests**

Run: `cargo test --manifest-path rust/Cargo.toml --bin nostr-codex-server handoff`

Expected: PASS.

### Task 2: Make Cancellation Clear Typing Immediately

**Files:**
- Modify: `rust/src/bin/nostr_codex_server.rs:4601-4629`
- Test: `rust/src/bin/nostr_codex_server.rs`

- [ ] **Step 1: Write the failing typing-clear payload test**

Extract the `WorkspaceTypingPayload` construction from `send_agent_typing` into a pure `agent_typing_payload` helper. Add a test that creates an agent and a channel conversation and verifies the clear payload has an empty stage and an expiration of zero:

```rust
#[test]
fn cancelled_agent_typing_payload_clears_the_active_lease() {
    let payload = agent_typing_payload(
        &agent,
        Some("engineering"),
        None,
        None,
        Some("thread-root"),
        Some(""),
        &[],
        None,
        None,
    );
    assert_eq!(payload.stage.as_deref(), Some(""));
    assert_eq!(payload.expires_at, 0);
}
```

- [ ] **Step 2: Run the cancellation tests and verify they fail**

Run: `cargo test --manifest-path rust/Cargo.toml --bin nostr-codex-server cancelled_agent_typing_payload_clears_the_active_lease`

Expected: FAIL because `agent_typing_payload` does not yet exist.

- [ ] **Step 3: Write the failing accepted-abort context test**

Add a server test that creates an active Coordinator turn in the `engineering`
channel with parent `thread-root`, cancels it through the active-turn abort
selection, and asserts the resulting clear payload has agent ID `coordinator`,
channel ID `engineering`, parent ID `thread-root`, an empty stage, and zero
expiration. The test must use the real active-turn map and cancellation token;
do not add mocks.

- [ ] **Step 4: Implement the minimal immediate clear**

Refactor `send_agent_typing` to use `agent_typing_payload`, retaining its existing recipients and transport behavior. In `abort_agent_task`, select and cancel the matching `ActiveTurnKey`, then build the clear payload from that selected key and active-turn data. Resolve the selected agent record and send the payload with `stage: Some("")`, empty history, and an expired lease. Log delivery failures but return success because the cancellation already succeeded. Do not send this update when no token matched.

- [ ] **Step 5: Run the cancellation tests and confirm they pass**

Run: `cargo test --manifest-path rust/Cargo.toml --bin nostr-codex-server abort`

Expected: PASS.

### Task 3: Verify Coordinator Mention Visibility

**Files:**
- Test: `test/workspace_models_test.dart`
- Inspect: `rust/src/workspace.rs:2785-2794`
- Inspect: `lib/src/main_widgets.dart:2687-2740`

- [ ] **Step 1: Add a model regression test for Coordinator membership**

Add a test that decodes a `WorkspaceState` snapshot with a Coordinator `WorkspaceConversationAgent` membership and an `A0` Task coordinator profile, then asserts the assigned agent has the public `Coordinator` display label.

```dart
test('conversation coordinator remains available as a public mention', () {
  // Decode Coordinator agent and conversation membership from snapshot JSON.
  // Assert the matching agent displayLabel is 'Coordinator'.
});
```

- [ ] **Step 2: Run the Flutter model test and confirm it passes**

Run: `flutter test test/workspace_models_test.dart --plain-name "conversation coordinator remains available as a public mention"`

Expected: PASS. The workspace store already unions coordinator membership into `conversation_agents`, and `_mentionOptionsFor` converts that agent ID to the public Coordinator mention. If this test fails, make the minimal snapshot/model fix; do not add duplicate Coordinator state.

### Task 4: Full Verification And Review

**Files:**
- Verify: `rust/src/bin/nostr_codex_server.rs`
- Verify: `test/workspace_models_test.dart`

- [ ] **Step 1: Format changed code**

Run: `cargo fmt --manifest-path rust/Cargo.toml --check`

Expected: PASS. If it reports formatting changes, run `cargo fmt --manifest-path rust/Cargo.toml` and repeat the check.

- [ ] **Step 2: Run focused backend tests**

Run: `cargo test --manifest-path rust/Cargo.toml --bin nostr-codex-server handoff`

Expected: PASS.

Run: `cargo test --manifest-path rust/Cargo.toml --bin nostr-codex-server abort`

Expected: PASS.

- [ ] **Step 3: Run client regression tests**

Run: `flutter test test/workspace_models_test.dart`

Expected: PASS.

- [ ] **Step 4: Run repository checks**

Run: `git diff --check`

Expected: PASS with no whitespace errors.

- [ ] **Step 5: Request two independent read-only reviews**

Request one review for routing correctness, conversation/thread preservation, cancellation, security, and compatibility. Request a separate review for regression coverage, scope, complexity, and test quality. Fix demonstrated findings, then repeat the relevant checks.
