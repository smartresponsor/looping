# Architecture

ChatGPT Loop is a consumer-side lifecycle layer.

It is responsible for the product workflow around ChatGPT, not for low-level service management.

## Runtime roles

```text
server-core     = service/process lifecycle
launcher        = stack/lifecycle assembly
console-mcp     = local execution backend
cloudflare-ask  = reusable AI advisory gateway
chatgpt-loop    = ChatGPT product workflow lifecycle
```

## Owned concerns

ChatGPT Loop owns:

- task text intake
- task bang parsing
- lifecycle run identity
- prompt dispatch request modeling
- backend capability status
- transcript references
- workflow state persistence
- deterministic next_action production

## Non-owned concerns

ChatGPT Loop does not own:

- ports
- process supervision
- PID files
- raw browser control
- local MCP endpoint management
- Cloudflare Ask internals
- Codex bearer validation
- generic launcher stack assembly

## First implementation slice

The first implementation slice writes state locally and produces deterministic output. Real ChatGPT browser dispatch remains an external backend capability.
