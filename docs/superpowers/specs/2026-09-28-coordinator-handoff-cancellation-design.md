# Coordinator Handoff And Cancellation Design

## Goal

Start the conversation Coordinator automatically when an agent reply explicitly
contains `@Coordinator`, make the Coordinator selectable in the composer, and
clear its typing indicator immediately when a cancellation request is accepted.

## Routing

When an agent turn completes, the worker converts public handoff tokens into
structured mentions, persists its reply, and records one durable handoff-outbox
entry per mentioned target agent in the same workspace store. The runtime then
submits each entry as a detached targeted job. The job uses the persisted reply
as its trigger, so it retains the reply's conversation and parent-thread
identifiers and routes the Coordinator in the originating thread.

The durable outbox is the minimal recovery boundary: pending entries are
submitted at startup and retried on the runtime's periodic handoff tick. An
entry is marked delivered only after its targeted job succeeds; a process stop,
enqueue failure, or unavailable target leaves it pending for recovery. An
in-memory claim prevents concurrent duplicate submissions in one runtime. The
runtime never recursively calls routing from an active routing call, and no
automatic routing for unmentioned messages is added.

## Composer Mentions

The composer builds agent mentions from the agents assigned to the conversation
and also includes that conversation's Coordinator. Internal numbered agents stay
hidden. The visible Coordinator label produces a structured mention for the
actual Coordinator agent ID.

## Cancellation

When `abort_agent_task` finds and cancels an active turn, it also publishes a
typing update that removes that same agent's active typing state in the relevant
conversation. It does not emit a clear update when no active turn exists.

## Tests

Worker tests will prove that an agent-authored Coordinator handoff persists,
recovers, retries, and completes its durable outbox entry only after the
targeted job succeeds. They will also prove that unmentioned replies do not
schedule it. Client tests will prove Coordinator is available as a mention.
Cancellation tests will prove an accepted abort selects its active turn and
clears typing with that turn's agent, conversation, and parent identifier.
