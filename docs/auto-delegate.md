# Auto Delegate

ChatGPT Loop can select a delegate stage automatically from the route plan.

## Explicit delegate

`--delegate=<stage>` always wins.

## Automatic delegate

When `--delegate` is omitted, the CLI uses `routePlan.nextDelegateStage`.

This makes the short command useful:

```powershell
php bin/console chatgpt-loop:run --task="cmcp go cataloging" --max-iterations=3
```

## Plan-only exception

When `--plan-only=1` is used, no delegate request is created.

The route plan is still returned.
