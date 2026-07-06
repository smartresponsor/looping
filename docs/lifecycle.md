# Lifecycle

The first lifecycle is deterministic and file-backed.

## Steps

1. Accept task text.
2. Parse optional task bang.
3. Create a lifecycle run id.
4. Create a prompt dispatch request.
5. Check backend configuration.
6. Produce a dispatch result.
7. Produce a deterministic next_action.
8. Persist state under `var/state`.
9. Persist transcript reference under `var/transcript`.
10. Print a JSON result.

## Backend status

When no dispatch backend is configured, the lifecycle returns:

```text
BACKEND_NOT_CONFIGURED
```

This is a closed status, not a fake success path.
