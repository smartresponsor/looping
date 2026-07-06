# Task Bang

Task bang is the first token of a task when it starts with `!`.

## Syntax

```text
!diagnose inspect lifecycle boundary
!dispatch prepare product loop
!review classify latest result
```

## Fields

- `bang`: the token without `!`
- `body`: the remaining task text
- `mode`: command mode, defaulting to `diagnostic`

## First supported bangs

- `diagnose`
- `dispatch`
- `review`

Unknown bangs are accepted as task metadata and produce a safe next_action.
