# JSON ABI

ChatGPT Loop stdout is the stable machine boundary for a runner.

## dispatchEnvelope

Required fields:

- `status`
- `stage`
- `tool`
- `arguments`
- `confirmationRequired`
- `mutation`

## dispatchResult

Accepted input options:

- `--dispatch-status`
- `--external-task-id`
- `--external-chat-id`
- `--external-target-id`

## resumeState

Required output fields:

- `status`
