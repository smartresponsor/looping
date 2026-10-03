# Console MCP Delegation

ChatGPT Loop owns product orchestration policy and delegates execution to Console MCP.

It must not duplicate browser, composer, answer capture, gateway, or engine-bank internals.

## Planning capabilities

- `read_.browser.chatgpt.entrypoint.plan`
- `write.browser.session.cmcp.go`

## Engine bank capabilities

- `write.engine.task.enqueue`
- `read_.engine.task.list`
- `read_.engine.task.status`
- `write.engine.worker.tick`

## Chat execution capabilities

- `write.engine.chat.bind`
- `write.engine.prompt.draft`
- `write.engine.prompt.submit`
- `write.engine.answer.capture`
- `write.engine.gateway.decide`
- `write.engine.reply.draft`
- `write.engine.reply.submit`

## Recovery capabilities

- `read_.browser.chatgpt.run.loop.recover.plan`
- `write.browser.session.run.loop.recover.step`
- `write.browser.session.run.loop.recover.prune.missing`

## Rule

The loop may select the next delegated capability.

The delegated capability performs the actual browser, engine, or gateway operation.
