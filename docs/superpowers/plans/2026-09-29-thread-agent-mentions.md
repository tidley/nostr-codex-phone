# Thread Agent Mentions Implementation Plan

**Goal:** Expose the assigned ThreadAgent in its thread and retain durable, thread-local handoffs.

**Architecture:** Use the existing conversation membership payload and durable handoff outbox. Add the assignment parent to membership exports. Select public mentions by conversation and composer thread identity.

**Tech Stack:** Flutter/Dart, Rust, SQLite.

- [x] Add model and real-composer regression tests for channel/direct scope, controller identity, and stable agent IDs. Run Flutter tests before the fix.
- [x] Add store/server regression tests for membership exports, lazy profiles, exact mention tokens, self-routing, and durable handoffs in both directions. Attempt fresh Cargo tests before the fix.
- [x] Extend the existing membership payload with `parent_id`. Publish the Coordinator profile with lazy allocation.
- [x] Update composer mention selection and exact-token handoff parsing, preserving the existing queues and Coordinator continuation changes.
- [x] Run Flutter tests and fresh Cargo tests. Request two independent read-only reviews and address demonstrated findings.

No commit or deployment. Preserve unrelated dirty changes, including known `workspace.rs` compile blockers.

## Verification

- Model tests failed on the missing ThreadAgent option before the implementation.
- Real-composer tests failed on the missing ThreadAgent and direct Coordinator options before the wiring fix.
- The final targeted Flutter run passed all 141 tests in `thread_agent_composer_test.dart`, `workspace_models_test.dart`, and `widget_test.dart`.
- The full Flutter run passed 212 tests. The unrelated Android release registrant test failed because its Gradle hook was absent.
- Initial Cargo runs stopped at the existing board compile errors. Those source errors changed during the session without edits from this task.
- A fresh build passed all 184 server tests, including the durable handoff regression and existing Coordinator continuation tests.
- The Rust library run passed 202 tests. The unrelated board snapshot test failed because its expected JSON omitted `board_column`.
- A mutation run without the hyphen guard failed on `@ThreadAgent-based`. The restored guard passed the full server suite.
- Two independent read-only reviews identified the hyphen boundary and lazy-profile coverage gaps. Both reviewers confirmed their findings were resolved.
- The scoped `git diff --check` passed.
