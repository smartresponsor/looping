# Dispatch Result Intake

Dispatch Result Intake records the result returned by an external Console MCP orchestrator.

It does not execute Console MCP tools.

## Options

- `--dispatch-status=ok`
- `--dispatch-status=blocked`
- `--dispatch-status=failed`
- `--external-task-id=<id>`
- `--external-chat-id=<id>`
- `--external-target-id=<id>`

The CLI persists `dispatchResult` into state, transcript, and stdout.

