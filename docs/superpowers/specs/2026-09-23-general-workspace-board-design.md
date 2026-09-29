# General Workspace Board Design

## Goal

Replace the proof-of-concept scheduling board with a general shared Kanban
board for human and agent work. Automation is optional card data, not the
board workflow.

## Scope

Each workspace has one board with configurable columns. A board column has a
name, rank, optional work-in-progress limit, and archive state. New workspaces
start with Backlog, Ready, In Progress, Review, and Done columns. Admins can
create, rename, reorder, limit, and archive columns.

A card has a title, description, board column, rank, priority, labels,
estimate, due date, assignees, dependencies, creator, creation time, update
time, and archive time. Assignees can be workspace members or configured
agents. Cards can have no assignee. A card may depend on other cards in the
same workspace.

Users drag cards between columns and reorder cards inside a column. Each move
updates a durable rank and writes a card-history event. A WIP limit displays an
overload warning but does not prevent a move. Archiving hides a card from
normal board views and retains its history.

## Automation

A card may include one optional automation configuration. It declares an
agent, target conversation, instruction, allowed folder scope, and a run
schedule. Schedules support immediate, one-time, daily, weekdays, weekly, and
monthly runs.

Automation execution has its own states: scheduled, queued, running, blocked,
completed, cancelled, and failed. The state is independent from the card's
column. Runs, progress entries, errors, and cancellations are stored in card
history. The existing worker queue still allows one active native task per
conversation and concurrent work in different conversations.

## Views and Navigation

The Board section includes search plus filters for assignee, label, priority,
due date, automation state, and archived cards. Users can sort by rank,
priority, due date, creation time, update time, or card age. A saved view
stores its filters, sort order, and optional swimlane. Swimlanes group cards by
assignee, priority, or label.

Selecting a card opens details with its fields, dependencies, activity history,
automation runs, and a link to the target conversation when automation is
configured. The archive is a board view that supports restore and permanent
deletion for admins.

## Metrics

The Board section provides a metrics view for the selected date range. It
shows lead time from creation to Done, cycle time from first entry into an
active column to Done, completed-card throughput, card ageing, and a
cumulative-flow chart. Metrics use durable card history events and exclude
archived cards only when the selected view excludes them.

## Access Control

All workspace members can view cards, activity, views, metrics, and automation
history. Members can create and edit ordinary cards and move cards. Admins
configure board columns, WIP limits, labels, saved shared views, archive
retention, and all automation. Only admins can start, edit, retry, or cancel
agent automation.

## Storage and Transport

Replace the current board-task schema with board, column, card, card-assignee,
card-label, dependency, saved-view, history-event, automation, and automation-
run records in `workspace.sqlite3`. Store ranks as ordered numeric values and
renormalize a column transactionally when its available rank range is
exhausted.

The normal workspace snapshot carries board configuration, cards, relations,
views, histories, and automation data. Board mutations use typed workspace
requests and publish a new workspace revision. There is no compatibility path
for the proof-of-concept board data because it has no production users.

## Error Handling

The worker blocks automation when its card, target conversation, agent, or
scope is invalid, then records the reason. Cancelling queued work prevents its
start. Cancelling running work uses the existing scoped native-turn cancellation
route. Invalid board mutations fail without changing ranks, relations, or
history.

## Verification

Tests must cover:

- Board and column configuration, ordering, WIP warnings, archive, and restore.
- Card creation, metadata, people and agent assignment, labels, dependencies,
  ranking, and transactional drag-and-drop moves.
- Search, filtering, sorting, saved views, and all swimlane modes.
- Admin-only board configuration and automation operations.
- Immediate, one-time, and recurring automation with independent execution
  states, queueing, cancellation, retry, and failure handling.
- Snapshot and request serialization for the replacement board model.
- Lead time, cycle time, throughput, ageing, and cumulative-flow calculations.
- Responsive Flutter board rendering and member/admin controls.
