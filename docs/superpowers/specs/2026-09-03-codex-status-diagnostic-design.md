# Codex Status Diagnostic Design

## Goal

When a Codex request produces no output for 60 seconds, check the public
OpenAI Statuspage API before reporting a possible Codex service issue.

## Scope

- Apply only to Codex requests managed by the worker.
- Make at most one status request per stalled agent request.
- Use `https://status.openai.com/api/v2/summary.json` with a short timeout.
- Treat a non-operational component whose name contains `Codex`, or an active
  incident whose name or update text contains `Codex`, as a reported Codex
  service issue.
- Send one suitable status message to the conversation when an issue is found.
- Do not report an outage when the status API cannot be reached or its payload
  cannot be parsed.

## Flow

1. Start a 60-second silence timer when the worker starts a Codex request.
2. Reset or cancel the timer when Codex emits output or the request completes.
3. When the timer fires, fetch the Statuspage summary once.
4. If the summary confirms an active Codex issue, send: `Codex appears to have
   a reported service issue. Your request is still pending; try again shortly.`
5. Continue the original request. Its existing timeout and error handling stay
   unchanged.

## Error Handling

- A status request timeout, transport failure, non-success response, or invalid
  JSON is ignored.
- The status result is advisory. It does not cancel, retry, or otherwise alter
  the Codex request.
- A successful request that later emits output does not send a recovery notice.

## Tests

- Unit tests cover an operational summary, a degraded Codex component, an
  incident that mentions Codex, malformed data, and status-request failure.
- An async request test verifies that silence triggers at most one diagnostic
  and output prevents it.
