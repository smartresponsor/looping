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
- Validate against a real blocked Console task snapshot; preserve `cycle_checkpoint_stop_reason` when no round envelope is present.

### M3 shadow recovery and replay

- Added `ChatGptLoopShadowRecoveryProjector` for blocked, runtime-wait, human-decision, rate-limit, orphaned-answer, and bound-task recovery classification.
- Added `fixtures/orchestration-replay-corpus.json` with two sanitized live blocked receipts plus deterministic rate-limit, orphaned-answer, human-decision, and verified-completion cases.
- Added replay regression to normal Composer verification.
- All M3 projections remain `authoritative=false` and execute no Console/browser mutation.

### Diagnostic side effect

One diagnostic call against legacy task `engine-20260913142412-accessing-b12d99` unexpectedly executed a single `chat_bind` stage even though `confirmRun=false`. No prompt was drafted or submitted. The old task changed from `blocked` to `executing` and received a blank ChatGPT root binding. No further mutating recovery was attempted; subsequent M3 corpus collection used read-only tools only.

### Cleanup signal ownership

- Added `ChatGptLoopCleanupSignalParser` as the lifecycle-owned parser for the single final-line `ready_to_delete` boolean.
- Parsing is intentionally literal-only: only the exact canonical `true`/`false` JSON lines are accepted; malformed, fenced, extended, or prose-wrapped variants resolve to `null`.
- Shadow state now projects `cleanup.readyToDelete` from raw assistant text when available, with the Console task boolean accepted only as a temporary compatibility source during migration.
- No browser tab or conversation deletion is executed by ChatGPT Loop in shadow mode; physical cleanup remains an atomic Console MCP capability invoked by an outer runner after cutover/policy wiring.

## 2026-09-14 — M4 live shadow parity wiring

- Added `ChatGptLoopOrchestrationReceiptNormalizer` so Console-style snake_case receipts and ChatGPT Loop camelCase task-bank snapshots project into one explicit schema.
- Added `ChatGptLoopShadowParityEvaluator` with broader lifecycle/checkpoint/decision/recovery comparison fields.
- Added live parity artifact capture to `runner-task-bank-loop.ps1` after successful answer capture.
- Live parity remains strictly non-authoritative: capture failure is journaled and does not change current runtime decisions, browser state, submit behavior, or Console task state.
- Added `docs/orchestration-migration-ledger.md` with `COPIED`, `SHADOW-WIRED`, `LEGACY-DELEGATED`, and `CUTOVER-DEBT` tracking plus the required Console cleanup/restart gate.
- Added M4 regression coverage to the normal Composer test suite and expanded replay coverage for continuation, unverified completion, semantic stall, and budget exhaustion.
- Live parity now compares the copied projector against the already-selected legacy `continue`/`terminal` decision; parity remains post-decision and non-authoritative.
- Added `ChatGptLoopShadowAcceptanceProjector`: transport-cycle success is modeled separately from verified task completion, and budget exhaustion is explicitly not completion.
- Added `ChatGptLoopSemanticDecisionRouter` as a copied structured `DONE` / `ACTION_REQUESTED` / human-decision / blocked / refusal router; it is not live-authoritative yet.
- Split the bridge inventory into `atomic` and `legacy_orchestration` capability classes without removing any currently allowed tool.
- Expanded the boundary debt meter to include `cmcp.go`, `ADOPT GO`, and `watch.next`; current debt is 133 production references across 15 frozen legacy files with 0 new boundary violations.
- Console MCP source/runtime remains unchanged in this pass.

## 2026-09-14 — M4 recovery and completion contract copy

- Read the current Console `engine-cycle-browser.ts` completion/recovery semantics directly and copied the factual acceptance contract into `ChatGptLoopCompletionVerificationContract`; the copy executes no checks and has no authority.
- Added `ChatGptLoopAtomicTransportPlan` describing the target bind/preflight/draft/submit/watch/settle/capture sequence without switching away from the current `cmcp.go` compatibility transport.
- Added live shadow recovery artifacts for current submit failures, stale capture/binding, answer-watch exhaustion, and rejected/empty answer capture. These artifacts cannot retry, rebind, submit, or alter task state.
- Added `config/orchestration-cutover-manifest.json`; it explicitly keeps `consoleAuthority=true`, `chatGptLoopAuthority=false`, M5/M6 disabled, and `consoleCleanupAllowed=false`.
- The migration ledger now distinguishes copied completion/transport contracts from remaining execution debt.

## 2026-09-14 — M4 action-marker parity copy

- Added `ChatGptLoopActionMarkerRouter` as a non-authoritative PHP port of the current Console signal classifier for fail/blocker/gate/dirty/commit/clean/green/next/question/human/done semantics.
- Added resolved-failure suppression coverage so historical/fixed failures do not force a false fail route in shadow classification.
- Switched only `live-shadow-parity-capture.php` to this router; the Console gateway remains authoritative and no production next action is selected by the copied router.
- Added regression coverage and kept the boundary stable at 133 legacy production references with 0 new violations.

## 2026-09-14 — M4 accumulated parity evidence gate

- Added `ChatGptLoopShadowParityEvidence` and `tool/live-shadow-parity-summary.php` to summarize accumulated live parity artifacts without participating in runtime decisions.
- Historical representation-only `decisionStatus` differences such as `ANSWER_STABLE` vs `answer stable` are canonicalized; semantic differences remain divergences.
- M4 readiness now requires both zero unexplained divergences and representative coverage for continue, blocked, retry, rate-limit, orphan, human-decision, stall, and completion.
- Current live evidence has one canonical match and zero unexplained divergences, but representative coverage is incomplete, so M5 remains blocked.
- Added `ChatGptLoopReplyBackPolicy` as a non-authoritative copy of Console read-only and Git-operation guards; current live reply drafting/submission remains delegated to Console.
- Added `ChatGptLoopBrowserObservationProjector` and live readiness parity artifacts that compare copied readiness interpretation against already-computed legacy `readyForCapture` / `quietEmptyBinding` booleans. The comparison cannot trigger settle, capture, rebind, or any browser mutation.
- Completed `ChatGptLoopShadowParityEvidence` as a fail-closed M4 evidence collector requiring scenario coverage for continue, blocked, retry, rate-limit, orphan, human-decision, stall, and completion before it can report READY.
- Current live evidence is INCOMPLETE: 2 artifacts, 1 full match, 1 partial match, 0 unexplained divergences; only blocked + continue are covered.
- A fresh read-only target run against clean Console MCP stopped in the unchanged legacy transport at `CMCP_GO_CHAT_EXPERIENCE_BLOCKED` before readiness parity could be exercised; Console MCP remained clean.
- Added `ChatGptLoopCutoverGate` as a non-authoritative, fail-closed M5/M6 eligibility contract. M5 requires M4 READY + stable zero-new-violation boundary; M6 additionally requires accepted M5 evidence + tested rollback. It cannot switch authority or clean Console MCP.
- Replaced conceptual names in `ChatGptLoopAtomicTransportPlan` with the exact existing Console tools. The three required atomic write tools (`session.open`, `session.input.draft`, `session.submit`) remain intentionally blocked by the current bridge and are now explicit M5 debt rather than silently implied capability.
- Prepared those three tools in a separate bridge set guarded by both `authorityMode=m5_opt_in` and `CHATGPT_LOOP_M5_ATOMIC_TRANSPORT_ENABLED=1`; neither condition is used by the current runtime, so the active bridge allowlist remains unchanged by default.
- Tightened `ChatGptLoopCutoverGate`: even complete M4 evidence cannot make M5 eligible until the exact atomic transport reports no bridge blockers and no longer requires the legacy high-level entrypoint.
- Added `ChatGptLoopM5AtomicDispatchPlanner`, which emits exact `runnerExecutionPlan` contracts for open/preflight/draft/submit/watch/settle/capture only when supplied an already-eligible M5 cutover receipt. It performs no bridge call and has no runtime effect.
- Added `ChatGptLoopCompletionVerificationPlanner` over existing read-only workspace/branch/implementation-capture capabilities. It intentionally reports `atomic_git_diff_check_missing` and behavioral/visual execution debt rather than fabricating completion evidence.
- Tightened M5 eligibility again: complete M4 evidence and atomic transport are insufficient until factual completion execution is blocker-free.
