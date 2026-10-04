# Looping

Repository name: `Looping`. The CLI/service compatibility identifier remains `chatgpt-loop`.

ChatGPT Loop is the ChatGPT-specific consumer/product lifecycle layer.

It owns task intake, task bang interpretation, prompt dispatch modeling, workflow state, transcript references, result interpretation, and deterministic `next_action` production.

It is not Server Core, Launcher, Cloudflare Ask, or raw browser automation.

## Boundary

- Server Core manages services, ports, processes, PID files, logs, health, restart modes, and local endpoint state.
- Launcher assembles a concrete stack for a lifecycle run.
- Cloudflare Ask is a reusable low-cost AI gateway.
- Console MCP remains the current execution backend for local MCP, browser, and tool operations.
- ChatGPT Loop models and runs the ChatGPT consumer workflow.

## Current dependency direction

`chatgpt-loop` may call or describe capabilities from `console-mcp` and `cloudflare-ask`.

`console-mcp` and `cloudflare-ask` must not depend on ChatGPT Loop.

## Orchestration migration safety

Console MCP remains the authoritative runtime while orchestration is migrated into ChatGPT Loop in shadow mode. Existing `cmcp go` and `ADOPT GO` paths stay unchanged until parity, opt-in cutover, rollback, and strict boundary gates pass.

The phased migration contract is documented in `docs/milestone-shadow-orchestration-migration.md`. Run `composer run orchestration:boundary` to enforce the current boundary ratchet. `composer run orchestration:boundary:strict` is the eventual cutover gate and is expected to fail while legacy Console orchestration dependencies remain.

M2 shadow-state parity is intentionally read-only: captured Console receipts are projected into independent ChatGPT Loop state and parity artifacts without browser mutation, prompt submission, or writes to authoritative Console runtime state.

## Clone portability

A normal clone is supported on Windows and Ubuntu/Linux. PHP 8.3+ and `pwsh` are required for the current regression/orchestration helpers.

The canonical workspace root is derived from the repository layout (`<workspace>/mcp/Looping`) instead of a hard-coded Windows path. Set `CHATGPT_LOOP_WORKSPACE_ROOT` only when the clone is intentionally placed outside that canonical layout.

## First RC behavior

The first slice is intentionally closed and deterministic:

```powershell
php bin/console chatgpt-loop:run --task="!diagnose check lifecycle boundary" --mode=diagnostic
```

When no real ChatGPT dispatch backend is configured, the command returns `BACKEND_NOT_CONFIGURED` and still writes state and transcript reference files.

This keeps the lifecycle safe, repeatable, and observable without pretending that browser dispatch has already been extracted.

## Current-chat adoption execution surface

`chatgpt-loop` owns the bounded adoption lifecycle while Console MCP resolves one existing location into a ChatGPT conversation. The same location may match the existing title-token registry, a visible chat title, or existing message content. Full ChatGPT URLs and conversation UUIDs remain supported.

```powershell
php bin/console chatgpt-loop:adopt-current-chat --component=Carting --location=@carting-investigation --max-auto-iterations=13
```

A non-mutating contract check is available through:

```powershell
composer run chatgpt-loop:adopt-plan
```

The execution surface validates component identity, URL-shaped references, and iteration budget before delegating to `tool/runner-adopt-current-chat.ps1`. Console MCP resolves registry, title, and body matches, rejects ambiguity, blocks an already active task for the same chat/component/workspace, and permits a new bounded task after the previous task becomes terminal.
M3 recovery/terminal semantics are replayed only in shadow mode from sanitized receipts; they do not execute browser or Console mutations.

The replay corpus lives in `fixtures/orchestration-replay-corpus.json` and is executed by `tool/orchestration-replay-regression.php`.
