# Dispatch Envelope

Dispatch Envelope is the bridge between ChatGPT Loop and an external Console MCP orchestrator.

It is descriptive and does not execute tools.

## Fields

- `stage`: selected product stage
- `capability`: semantic capability label
- `tool`: concrete Console MCP tool name when known
- `arguments`: expected argument shape
- `confirmationRequired`: explicit confirmation boundary
- `mutation`: expected mutation class
- `execution`: always `external_console_mcp_required`

## Example

For `entrypoint_plan`, the envelope contains:

```text
tool = read_.browser.chatgpt.entrypoint.plan
mutation = none
confirmationRequired = false
```

## Boundary

The launcher or another outer orchestrator consumes the envelope and calls Console MCP.
