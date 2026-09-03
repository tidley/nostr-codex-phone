# Codex Status Diagnostic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notify a conversation when a silent Codex request coincides with a reported Codex service issue.

**Architecture:** Keep the diagnostic in `nostr_codex_server.rs`, where streamed agent events already become conversation status messages. Race the Codex run against a 60-second timer once; on timer expiry, fetch Statuspage JSON with `reqwest`, inspect only Codex components/incidents, and send an advisory status without changing the running request.

**Tech Stack:** Rust, Tokio, reqwest, serde_json, existing Nostr status messenger.

---

### Task 1: Statuspage parser and fetcher

**Files:**
- Modify: `rust/src/bin/nostr_codex_server.rs` near `run_codex_session_with_status`
- Test: `rust/src/bin/nostr_codex_server.rs` existing `#[cfg(test)]` module

- [ ] **Step 1: Write failing parser tests**

Add tests for an operational Codex component, a `degraded_performance` Codex component, an active incident named `Elevated errors across ChatGPT and Codex`, and malformed JSON. Assert only the latter two produce `true`.

- [ ] **Step 2: Run the focused tests**

Run: `cargo test --bin nostr_codex_server codex_status`

Expected: FAIL because the parser does not exist.

- [ ] **Step 3: Add minimal status helpers**

Add constants and helpers:

```rust
const OPENAI_STATUS_SUMMARY_URL: &str = "https://status.openai.com/api/v2/summary.json";
const OPENAI_STATUS_TIMEOUT: Duration = Duration::from_secs(5);

fn statuspage_reports_codex_issue(summary: &Value) -> bool {
    // A component is unhealthy unless its status is exactly "operational".
    // Incidents are active unless their status is "resolved".
}

async fn openai_reports_codex_issue(client: &reqwest::Client) -> bool {
    // Return false for all request, response, and JSON failures.
}
```

Use case-insensitive matching on `Codex`; inspect component `name` and `status`, and incident `name`, `status`, plus every update `body`.

- [ ] **Step 4: Run the focused tests**

Run: `cargo test --bin nostr_codex_server codex_status`

Expected: PASS.

### Task 2: Silence-timer integration

**Files:**
- Modify: `rust/src/bin/nostr_codex_server.rs:11966-12008`
- Test: `rust/src/bin/nostr_codex_server.rs` existing `#[cfg(test)]` module

- [ ] **Step 1: Write a deterministic timer-state test**

Extract the timer decision into a small pure helper and test that it permits one check after 60 seconds, suppresses subsequent checks, and disables the check for `AgentBackend::OpenCode`.

- [ ] **Step 2: Run the focused test**

Run: `cargo test --bin nostr_codex_server codex_silence`

Expected: FAIL because the timer state is absent.

- [ ] **Step 3: Race the Codex run with one status check**

In `run_codex_session_with_status`, create a `sleep(Duration::from_secs(60))` only when `codex_config.backend == AgentBackend::Codex`. Add a `tokio::select!` branch that awaits the timer once, calls `openai_reports_codex_issue`, and sends exactly this existing-style status message when it returns true:

```rust
"Codex appears to have a reported service issue. Your request is still pending; try again shortly."
```

Set the timer option to `None` after it fires. Keep the existing event and completion branches unchanged. Do not cancel, retry, or alter the original run.

- [ ] **Step 4: Run focused tests**

Run: `cargo test --bin nostr_codex_server codex_silence codex_status`

Expected: PASS.

### Task 3: Verify worker build

**Files:**
- Modify: none

- [ ] **Step 1: Format Rust code**

Run: `cargo fmt --check`

Expected: PASS. Run `cargo fmt` if it reports formatting changes, then rerun the check.

- [ ] **Step 2: Run worker tests**

Run: `cargo test --bin nostr_codex_server`

Expected: PASS, or record the unrelated failure with its exact cause.

- [ ] **Step 3: Inspect the patch**

Run: `git diff --check`

Expected: no output and exit code 0.
