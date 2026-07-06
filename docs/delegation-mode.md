# Delegation Mode

ChatGPT Loop supports safe modes before direct execution exists.

## Plan only

Use `--plan-only=1` to return `PLAN_ONLY_READY` and persist the product plan.

## Delegate request

Use `--delegate=entrypoint_plan` to return `DELEGATE_READY` when the requested stage exists in the product plan.

The command records a delegate request for the outer orchestration layer.

It does not call Console MCP directly.

## Boundary

ChatGPT Loop chooses the product stage.

Console MCP executes the stage.
