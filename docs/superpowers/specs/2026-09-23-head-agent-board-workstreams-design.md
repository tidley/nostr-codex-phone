# Head-Agent Board Workstreams Design

## Goal

Make each existing board task one durable agent workstream. The workstream has
a linked task thread and a read-only OpenCode session. One private head session
per conversation is the only session that can modify the conversation's
repository.

## Scope

This design extends the shipped board-task Kanban. It does not depend on the
unshipped general-card UI described in `2026-09-23-general-workspace-board-design.md`.

Every top-level human message creates a durable read-only thread-agent session,
whether it is a task or casual chat. Replies in that thread resume its session.
The private head session supplies initial context and remains the only writable
session. A board task links to its existing root-thread workstream when one is
available; it does not create a second worker for the same thread.

Each board task stores a durable link to one root task-thread message and one
read-only thread-agent record. Creating a task creates the root message and
the task agent. The task agent uses the thread and board timeline to research,
make a proposal, and report blockers. It cannot modify the repository.

Each target conversation has one private head-agent OpenCode session. The head
does not send messages to channels, direct conversations, or task threads. It
accepts proposed task work one at a time, changes the repository, validates the
result, and records its outcome on the board. Ribbit then sends that result to
the linked thread agent, which writes the visible task-thread response.

## Session And Process Model

Ribbit starts a persistent `opencode serve` process per workspace access mode:

- The head server has a read-write workspace mount.
- The worker server has a read-only workspace mount.

OpenCode sessions are created through the server HTTP API and persisted in the
workspace database. Prompts use the server API and server-sent events provide
progress and completion. Worker restarts reconnect to the server when it is
healthy, or start a replacement server and resume the persisted session IDs.

The conversation session currently used for native replies becomes the private
head session. It is not prompted for ordinary chat replies. The task-agent
record owns the linked thread session.

## Data Flow

1. An administrator creates a board task for a conversation and folder scope.
2. The worker validates the scope, creates a root task message, provisions a
   read-only task-agent session, and stores the task-to-thread and task-to-agent
   links atomically.
3. The task agent receives the task instruction and thread context. It posts
   user-facing research and questions in the linked thread, and records
   proposal or blocker progress in the board timeline.
4. A completed proposal is queued for that conversation's head agent.
5. The head agent processes one queued proposal at a time. It reads the current
   working tree, applies only the accepted work, runs the requested validation,
   and records completion, conflict, or failure on the board.
6. The task agent receives the head result and posts the visible final response
   to its linked thread.

## Safety And Recovery

The sandbox wrapper mounts the project workdir read-only for task agents and
read-write only for head agents. Task agents cannot run dependency installs,
tests, or other commands that write workspace artifacts.

The head serializes repository mutations by conversation. Before applying a
proposal, it checks current worktree state and reports conflicts rather than
resetting, cleaning, switching branches, or overwriting user changes.

Cancelling a task aborts its task-agent session turn and removes any queued head
integration. Existing task/thread/session records remain for audit and reopen.
After a process restart, incomplete task turns are marked interrupted; the user
can resume the task from its linked thread or board card.

## Verification

Tests cover durable task-to-thread and task-to-agent links, automatic thread
creation, read-only sandbox selection, serialized head queueing, cancellation,
restart recovery, and suppression of head-agent chat replies. Transport tests
cover OpenCode server session creation, prompt submission, event completion,
and abort handling. Widget tests cover opening a board task's linked thread.
