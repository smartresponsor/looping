# Loop Budget

ChatGPT Loop supports explicit lifecycle distance control.

## Single step

Default mode. One safe step is allowed.

```powershell
php bin/console chatgpt-loop:run --task="cmcp go cataloging" --delegate=bounded_worker_tick
```

## Bounded iterations

Use a numeric limit for controlled multi-step trips.

```powershell
php bin/console chatgpt-loop:run --task="cmcp go cataloging" --delegate=bounded_worker_tick --max-iterations=7
```

Alias:

```text
--iterations=7
```

## Until RC

Use RC mode when the goal is full RC readiness rather than a numeric count.

```powershell
