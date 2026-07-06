# Console MCP Delegation

ChatGPT Loop owns product orchestration policy and delegates execution to Console MCP.

It must not duplicate browser, composer, answer capture, gateway, or engine-bank internals.

## Planning capabilities

- `console.read_.browser.chatgpt.entrypoint.plan`
- `console.write.browser.session.cmcp.go`

## Engine bank capabilities

- `console.write.engine.task.enqueue`
- `console.read_.engine.task.list`
- `console.read_.engine.task.status`
- `console.write.engine.worker.tick`

## Chat execution capabilities

- `console.write.engine.chat.bind`
- `console.write.engine.prompt.draft`
- `console.write.engine.prompt.submit`
- `console.write.engine.answer.capture`
- `console.write.engine.gateway.decide`
- `console.write.engine.reply.draft`
- `console.write.engine.reply.submit`
- `console.write.engine.reply.draft_submit`

## Recovery capabilities

- `console.read_.browser.chatgpt.run.loop.recover.plan`
- `console.write.browser.session.run.loop.recover.step`
- `console.write.browser.session.run.loop.recover.prune.missing`

## Rule

The loop may select the next delegated capability.

The delegated capability performs the actual browser, engine, or gateway operation.
