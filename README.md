# ChatGPT Loop

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

## First RC behavior

The first slice is intentionally closed and deterministic:

```powershell
php bin/console chatgpt-loop:run --task="!diagnose check lifecycle boundary" --mode=diagnostic
```

When no real ChatGPT dispatch backend is configured, the command returns `BACKEND_NOT_CONFIGURED` and still writes state and transcript reference files.

This keeps the lifecycle safe, repeatable, and observable without pretending that browser dispatch has already been extracted.

## Current-chat adoption execution surface

`chatgpt-loop` owns the deterministic adoption entrypoint. The caller must provide the exact URL of the invoking ChatGPT conversation; the loop never guesses "this chat" from browser inventory.

```powershell
php bin/console chatgpt-loop:adopt-current-chat --component=Carting --current-chat-url=https://chatgpt.com/c/00000000-0000-0000-0000-000000000000 --max-auto-iterations=13
```

A non-mutating contract check is available through:

```powershell
composer run chatgpt-loop:adopt-plan
```

The execution surface validates component identity, ChatGPT host, conversation UUID, and iteration budget before delegating to `tool/runner-adopt-current-chat.ps1`. A future ChatGPT Loop connector should map `Adopt this chat with M1/M13` to this command and inject the exact current conversation URL.
