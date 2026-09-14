# Milestone: Shadow Orchestration Migration

## Goal

Move orchestration ownership from Console MCP into ChatGPT Loop without changing the currently working runtime until behavioral parity is proven.

The architectural divergence point is Console MCP commit `f45d5ac` (`Add deterministic engine runtime`). The current behavior baseline is the hardened Console MCP engine lineage through `ffae5d7` plus later capability-only fixes.

## Runtime safety rule

During shadow migration:

1. Existing `cmcp go` and `ADOPT GO` execution paths remain unchanged.
2. Console MCP engine and run-loop tools remain available and are not weakened.
3. ChatGPT Loop shadow decisions are explicitly non-authoritative and never submit an extra prompt.
4. Cutover is forbidden until strict parity acceptance passes.
5. Console MCP cleanup happens only after cutover and rollback validation.

## Ownership target

ChatGPT Loop owns task/chat lifecycle state, phase progression, iteration budgets, continuation/fix/done decisions, retry/recovery policy, action-marker interpretation, task reuse/adoption policy, checkpoints, cleanup policy, and terminal acceptance.

Console MCP keeps atomic browser, repository, Git, package, filesystem, process, and diagnostic capabilities.

## Gates

### M1 — Boundary freeze

Record current dependencies on Console-owned orchestration and reject any expansion into new production files.

Acceptance: `composer run orchestration:boundary` returns `ORCHESTRATION_SHADOW_BOUNDARY_STABLE`.

### M2 — Shadow state parity

ChatGPT Loop independently projects task/chat state, phase, budget, retry cursor, checkpoints, and stop/continue state from the same receipts while Console remains authoritative.

Implementation rule: shadow state is derived from immutable captured receipts and written only to ChatGPT Loop parity artifacts. It must never update Console task files, browser state, or authoritative runner state.

### M3 — Shadow decision parity

Move action-marker, continuation, retry, recovery, stall, human-decision, and completion-candidate logic into ChatGPT Loop with deterministic fixture/replay tests.

### M4 — Live dual-run parity

For selected non-destructive runs, Console remains authoritative while ChatGPT Loop computes and persists a shadow decision from the same receipts. No duplicate browser mutation is permitted.

### M5 — Opt-in cutover

Add an explicit opt-in mode where ChatGPT Loop is authoritative and Console MCP supplies only atomic capabilities. The default remains legacy until acceptance passes.

### M6 — Default cutover with rollback

Switch the default to ChatGPT Loop orchestration while keeping an explicit legacy rollback mode for one stabilization window.

### M7 — Console MCP de-orchestration

Only after M6, deprecate/remove Console-owned engine/run-loop orchestration.

Acceptance: `composer run orchestration:boundary:strict` returns `ORCHESTRATION_SHADOW_MIGRATION_COMPLETE` before any destructive Console cleanup.

## Current copied slice

`ChatGptLoopShadowDecisionProjector` is the first non-authoritative copy of Console engine round-control semantics. It projects stop/continue outcomes for continuing markers, human decisions, completion candidates, repeated-progress stalls, iteration exhaustion, and unresolved decisions without calling Console engine tools or mutating runtime.

## Current debt

The repository still has legacy production references to `console.write.engine.*`, `console.read_.browser.chatgpt.run.loop.*`, and the run-loop daemon surface. They are intentionally preserved during M1–M4 to protect the working runtime.
