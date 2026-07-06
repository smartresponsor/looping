# Delegate Executor Contract

ChatGPT Loop can now describe how a selected product stage should be executed by the outer orchestration layer.

It still does not call Console MCP directly.

## Contract fields

- `capability`: semantic Console MCP capability label
- `mutation`: expected mutation class
- `confirmation`: whether explicit confirmation is required
- `arguments`: expected argument shape
- `execution`: always `external_console_mcp_required`

## Example

```powershell
php bin/console chatgpt-loop:run --task="cmcp go cataloging" --mode=repo_rc_implementation --delegate=entrypoint_plan
```

The output includes:

```text
delegateRequest.contract.status = DELEGATE_CONTRACT_READY
delegateRequest.contract.contract.capability = browser.chatgpt.entrypoint.plan
delegateRequest.contract.arguments.workspacePath = D:\PhpstormProjects\www\cataloging
```

## Boundary

The contract is descriptive. Actual execution belongs to Console MCP or a launcher/orchestrator layer.
