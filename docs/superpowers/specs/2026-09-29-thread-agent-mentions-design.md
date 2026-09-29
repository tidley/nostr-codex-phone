# Thread Agent Mentions Design

## Goal

Let users and Coordinators address the ThreadAgent assigned to a thread without
exposing internal worker identities or allowing cross-thread routing.

## Visibility

The composer shows `@ThreadAgent` only when it is editing a thread with an
assigned conversation worker. The mention has that worker's real agent ID and
the public label `ThreadAgent`.

The main conversation composer and threads without an assigned worker do not
show this option. Numbered names and generic `@Agent` options remain hidden.
`@Coordinator` stays available for the conversation Coordinator.

## Routing

An explicit `@ThreadAgent` mention from a user or Coordinator targets the
worker assigned to the current thread. The worker receives the originating
thread context and replies there. A ThreadAgent `@Coordinator` mention and a
Coordinator `@ThreadAgent` mention therefore form a thread-local handoff loop.

## Tests

Model or widget tests will verify that ThreadAgent appears only for its assigned
thread and emits the assigned agent ID. Worker tests will verify Coordinator
handoffs to `@ThreadAgent` retain the thread parent and do not resolve a worker
from another thread.
