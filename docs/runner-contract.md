# Runner Contract

ChatGPT Loop does not execute Console MCP directly.

## Boundary

- ChatGPT Loop plans, routes, delegates, and resumes.
- Runner dispatches envelopes to an executor.
- Console MCP executes tools and returns results.

## Command

```powershell
php bin/console chatgpt-loop:contract
```

## Cycle

1. Read `dispatchEnvelope` from ChatGPT Loop stdout.
2. Execute `dispatchEnvelope.tool` with `dispatchEnvelope.arguments`.
3. Call ChatGPT Loop again with dispatch result ids.
