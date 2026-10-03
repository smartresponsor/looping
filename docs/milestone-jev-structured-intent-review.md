# Milestone: Jev Structured Intent Review

Status: planned after Console MCP shadow validation

Canonical cross-repository milestone:

`D:\PhpstormProjects\www\aigateway\docs\ai\AI_JEV_STRUCTURED_DECISION_MILESTONE.md`

Console MCP integration contract:

`D:\PhpstormProjects\www\mcp\console-mcp\docs\agents\jev-structured-decision-shadow.md`

## Why ChatGPT Loop is a second target

The current loop already reduces intent review to a finite verdict:

`allow | warn | revise | block`

That shape is a strong fit for Jev Choice evaluation, but this repository must not be the first promotion target. Engine shadow parity should establish transport reliability, semantic accuracy, confidence behavior, and rollback first.

## Boundary

Jev may classify intent risk.

ChatGPT Loop remains authoritative for:

- workflow routing;
- reply-back construction and dispatch;
- budget lifecycle;
- runner state;
- stop/continue semantics.

Jev must not execute tools or mutate repository state.

## Candidate contract

State should contain only bounded task/evidence/feedback material already represented by `ChatGptLoopAskGatewayIntentContract`.

Questions:

```text
verdict: choice
  allow
  warn
  revise
  block

policy_risk: score
  low
  material
  blocking

human_review_required: noul
```

The existing deterministic decision builder remains responsible for mapping structured evidence into loop actions.

## Promotion prerequisites

Do not implement authoritative Jev routing here until:

1. Console MCP J0/J1 shadow transport is stable;
2. a representative decision corpus exists;
3. confidence thresholds are evidence-based;
4. transport failure is proven non-blocking;
5. rollback is explicit and immediate.

## Future implementation checklist

- add Jev result intake separate from generative Ask result intake;
- preserve existing Ask path as fallback during canary;
- record parity between Jev verdict and current Ask/deterministic outcome;
- keep `block` and human-review semantics fail-closed;
- promote only bounded ambiguous intent reviews.
