# CMCP Change Journal

## 2026-09-14 — Shadow orchestration migration baseline

### Baseline

Console MCP commit `f45d5ac` is the architectural divergence point where Console acquired a durable task/phase engine. The hardened Console engine through `ffae5d7` is treated as the behavioral baseline that must be preserved during migration.

ChatGPT Loop already owns task-bank/chat-bank state and runner retry/recovery logic, but production code still delegates substantial orchestration to Console MCP through `console.write.engine.*`, `console.read_.browser.chatgpt.run.loop.*`, and the run-loop daemon surface.

### Work completed

- Added a ratcheting orchestration-boundary baseline and audit.
- Added a strict cutover gate that intentionally fails while Console orchestration dependencies remain.
- Added the first non-authoritative shadow copy of cycle stop/continue semantics in `ChatGptLoopShadowDecisionProjector`.
- Added deterministic shadow decision regression fixtures.
- Added the phased M1–M7 migration milestone.
- Added the non-strict boundary guard to the normal Composer test suite.

### Runtime safety

- Existing `cmcp go` and `ADOPT GO` production paths were not modified.
- No Console MCP source or runtime configuration was changed.
- Shadow decisions are explicitly non-authoritative and perform no browser mutation or prompt submission.
- Console MCP remains the authoritative runtime until parity and cutover gates pass.

### Verification

- `composer run test`: PASS.
- `tool/runner-repo-smoke-check.ps1`: PASS.
- non-strict boundary audit: `ORCHESTRATION_SHADOW_BOUNDARY_STABLE`.
- strict boundary audit: expected block `ORCHESTRATION_CUTOVER_NOT_READY`.
- remaining Console-owned production orchestration references: 114 across 13 legacy files.
- new boundary violations: 0.

### M2 implementation in progress

- Add an independent shadow state projector that consumes Console task snapshots/receipts as immutable input.
- Persist parity artifacts separately from authoritative runner state.
- Compare externally meaningful lifecycle fields only; never replay browser mutations.
- Keep the shadow projector free of Console tool names so the boundary ratchet cannot be bypassed by copying orchestration APIs into new production files.
