# Boundary

```text
Server Core != Launcher != Cloudflare Ask != ChatGPT Loop
```

## Server Core

Server Core answers: can the local service live and be managed?

It handles ports, processes, PID files, logs, health checks, restart modes, secrets lookup, transcripts, policy catalogs, tool registry, and local MCP endpoints.

## Launcher

Launcher answers: is the required stack ready for this lifecycle?

It can check ChatGPT MCP, Codex bearer, Cloudflare Ask, browser availability, diagnostic lifecycle readiness, state dumps, and next stack action.

## Cloudflare Ask

Cloudflare Ask answers: can we get a cheap reusable AI advisory decision?

It is a reusable AI Gateway Service for semantic review, risk classification, remediation prioritization, lifecycle advisory, and diagnostics.

## ChatGPT Loop

ChatGPT Loop answers: how do we run a ChatGPT-specific product workflow?

It owns the consumer lifecycle around ChatGPT tasks, prompts, state, transcript references, result interpretation, and next_action generation.
