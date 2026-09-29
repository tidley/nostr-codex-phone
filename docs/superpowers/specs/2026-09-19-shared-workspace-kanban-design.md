# Shared Workspace Kanban Design

## Goal

Add one shared Kanban board to each workspace. The board schedules and tracks
automated work that uses each conversation's native master agent.

The feature runs inside the existing Phone worker. It does not use Hermes, a
local HTTP service, or another daemon.

## Scope

The first release supports one-time and recurring tasks. Recurring schedules
use daily, weekdays, weekly, or monthly rules at a selected time. The first
release does not support cron expressions.

The board has these states:

- Scheduled
- Queued
- Running
- Blocked
- Done

## Access Control

The board is shared by all workspace members.

Only workspace admins can create, edit, schedule, assign, move, retry, or
cancel a task. Other members can view the board and its task timelines.

A task declares its target conversation, instruction, allowed repository or
folder scope, and schedule. Admin creation of the task gives standing approval
for actions in that declared scope. The worker requests approval for actions
outside that scope.

## Scheduling and Execution

The existing worker process runs a small scheduler. It checks due tasks at
startup and after each board change.

The worker routes a due task to its target conversation's existing native-agent
queue. Each conversation has one active task. Different conversations can run
tasks at the same time.

If a conversation is busy, the worker stores the due task in Queued. The
worker starts it after the active conversation work ends.

One-time tasks move to Done after a successful run. Recurring tasks store the
completed run and return to Scheduled with their next run time.

If a run fails, the worker moves the task to Blocked and records the failure.
The worker does not retry it automatically. An admin can retry or change the
task.

## Storage and Transport

The existing `workspace.sqlite3` file stores board tasks, schedules, task runs,
and timeline entries. The store must make run claim and state changes atomic so
a worker restart cannot start the same due run twice.

The normal workspace snapshot includes board data. Existing workspace revision
and transport paths distribute updates to mobile and desktop clients. Existing
workspace cache paths store the snapshot locally.

The board uses normal workspace request and update messages. The worker checks
admin access before it changes board state.

## Client Design

The workspace UI has a top-level Board section on mobile and desktop.

The Board section shows columns for Scheduled, Queued, Running, Blocked, and
Done. Each task card shows its title, target conversation, next run time,
current state, and latest timeline entry.

Selecting a task shows a compact worker-generated timeline. The timeline can
show Queued, Started, Working, Completed, and Blocked entries. It does not show
the full conversation transcript.

The task details include a link to the target conversation. Users use that
conversation to inspect full agent output.

Admins see controls to create, edit, retry, cancel, and move tasks. Members
only see current board data and task timelines.

## Error Handling

The worker moves a task to Blocked if its target conversation is missing, its
declared scope is invalid, or its agent run fails. The timeline records the
reason.

Cancelling a queued task prevents it from starting. Cancelling a running task
uses the existing cancel route.

## Verification

Tests must cover:

- Admin-only task mutation.
- One-time and recurring schedule calculation.
- One active task for each conversation.
- Concurrent tasks for different conversations.
- Queueing while a conversation is busy.
- Restart recovery and duplicate-run prevention.
- Blocked state after invalid task data or agent failure.
- Board request and update protocol parsing.
- Board state rendering and member read-only controls.
