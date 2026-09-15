# Orchestration Migration Ledger

This ledger is the cutover/de-orchestration checklist for moving lifecycle ownership from Console MCP into ChatGPT Loop without breaking the currently working runtime.

Status vocabulary:

- `COPIED` — behavior has an independent ChatGPT Loop implementation but is not connected to live execution.
- `SHADOW-WIRED` — live receipts are copied into ChatGPT Loop and evaluated without changing authoritative runtime behavior.
- `LEGACY-DELEGATED` — Console MCP still owns the live decision or lifecycle capability.
- `CUTOVER-DEBT` — work that must be completed and accepted before Console MCP orchestration can be removed/restarted in de-orchestrated form.

| Capability | Status | ChatGPT Loop implementation | Current authority | Remaining debt before Console cleanup |
| --- | --- | --- | --- | --- |
| stop/continue decision | SHADOW-WIRED | `ChatGptLoopShadowDecisionProjector` + live legacy decision receipt comparison | Console MCP | accumulate live parity evidence, then opt-in authority |
| task/chat state projection | COPIED | `ChatGptLoopShadowStateProjector` | Console MCP + task-bank compatibility state | broaden parity and prove restart parity |
| recovery classification | SHADOW-WIRED/PARTIAL | `ChatGptLoopShadowRecoveryProjector` + live submit/capture failure receipts | Console MCP | add authoritative recovery-result parity for rebind/rate-limit/orphan flows before opt-in authority |
| receipt normalization | SHADOW-WIRED | `ChatGptLoopOrchestrationReceiptNormalizer` | no authority; translation only | stabilize schema and version it |
| live parity evaluation | SHADOW-WIRED | `ChatGptLoopShadowParityEvaluator` + parity artifacts | Console MCP | accumulate live evidence with zero unexplained divergence |
| iteration budget | LEGACY-DELEGATED | task-bank has compatibility budget | mixed | make completion independent from budget exhaustion |
| completion verification | COPIED/PARTIAL | `ChatGptLoopCompletionVerificationContract` + capability-aware `ChatGptLoopCompletionVerificationPlanner` + `ChatGptLoopBehavioralEvidencePlanner` now mirror factual, applicability, reuse-first runtime, and fresh visual-evidence rules | Console MCP | `git_diff_check` is source-ready at `055d51a` but restart-pending; behavioral semantics are copied, while actual runner/runtime/gallery evidence collection must still be wired through atomic read capabilities before M5 |
| semantic progress/stall | COPIED | decision projector repeat-count logic | Console MCP | feed live progress fingerprints and compare decisions |
| browser answer readiness | SHADOW-WIRED/PARTIAL | `ChatGptLoopBrowserObservationProjector` compares copied watch/step receipts against legacy readiness booleans | Console MCP `watch/run-loop` interpretation | accumulate zero-divergence live evidence, then replace `run.loop.step.summary` with atomic observation receipts behind opt-in M5 |
| prompt/chat transport | COPIED/PARTIAL | exact `ChatGptLoopAtomicTransportPlan` + gate-closed `ChatGptLoopM5AtomicDispatchPlanner` | Console MCP `cmcp.go` compatibility path | planner can now emit exact atomic contracts but M5 bridge writes remain doubly gated and current transport is still legacy; after M4 READY, run explicit opt-in parity before removing high-level entrypoints |
| action-marker router | SHADOW-WIRED/PARTIAL | `ChatGptLoopActionMarkerRouter` drives shadow parity; `ChatGptLoopReplyBackPolicy` mirrors read-only and Git-operation guards | Console MCP | broaden live parity corpus and compare generated reply-back envelopes before M5 |
| acceptance | COPIED/PARTIAL | task-bank transport acceptance + `ChatGptLoopShadowAcceptanceProjector` | mixed | wire verified completion evidence; keep budget exhaustion non-terminal for task completion |
| cleanup signal | COPIED/PARTIAL | `ChatGptLoopCleanupSignalParser` projected in shadow state | Console-compatible physical cleanup | live parity and post-cutover atomic delete/close policy |
| bridge allowlist | LEGACY-DELEGATED/PARTIAL | bridge classifies `atomic` vs `legacy_orchestration` while preserving the same allowlist | mixed | remove legacy class only after M5/M6 rollback acceptance |

## Current legacy cleanup inventory

The expanded boundary meter currently records **133 legacy production references across 15 files**, with **0 new boundary violations**. These references are intentionally left executable until M5/M6 acceptance:

- `src/Service/ChatGptLoopChatResponseDispatchContract.php`
- `src/Service/ChatGptLoopDispatchEnvelopeBuilder.php`
- `src/Service/ChatGptLoopRunnerDispatcherContract.php`
- `src/Service/ChatGptLoopRunnerExecutionPlan.php`
- `tool/adopt-contract-regression.php`
- `tool/runner-adapter.ps1`
- `tool/runner-adopt-current-chat.ps1`
- `tool/runner-console-mcp-bridge.mjs`
- `tool/runner-dispatcher.ps1`
- `tool/runner-host-bridge.ps1`
- `tool/runner-repo-smoke-check.ps1`
- `tool/runner-repo-smoke.ps1`
- `tool/runner-runtime-smoke.ps1`
- `tool/runner-smoke.ps1`
- `tool/runner-task-bank-loop.ps1`

The count intentionally includes high-level `cmcp.go`, `ADOPT GO`, `watch.next`, run-loop, daemon, and engine surfaces. It is a debt inventory, not an instruction to remove them yet.

## Current M4 live evidence

Latest evidence summary: `M4_SHADOW_PARITY_EVIDENCE_INCOMPLETE` with 2 parity artifacts, 1 complete match, 1 partial match, and 0 unexplained divergences. Observed scenario coverage is currently `blocked` + `continue`; still missing `retry`, `rate_limit`, `orphan`, `human_decision`, `stall`, and `completion`.

A fresh read-only live run against a clean Console MCP target was blocked by the existing legacy transport before answer readiness at `CMCP_GO_CHAT_EXPERIENCE_BLOCKED`; the target repository remained clean. This does not count as browser-readiness parity evidence and must not advance M4.

## M5 bridge activation guard

The three future atomic browser write tools are present in the bridge as a separate gated set, not in the normal allowlist. They remain unavailable unless both `runnerExecutionPlan.authorityMode=m5_opt_in` and `CHATGPT_LOOP_M5_ATOMIC_TRANSPORT_ENABLED=1` are present. Current task-bank dispatches use the legacy authority mode, so this preparation does not expand the active production write surface.

## M5/M6 authority guard

`ChatGptLoopCutoverGate` is now the copied fail-closed authority-transition contract. It has no runtime effect. M5 opt-in eligibility requires complete zero-divergence M4 evidence plus a stable boundary with zero new violations. M6/default eligibility additionally requires a separately accepted M5 run and a tested rollback. Strict boundary completion remains a later Console-cleanup condition rather than a circular prerequisite for M5.

## Console MCP cleanup gate

Do **not** delete or weaken Console MCP orchestration while any row above is `LEGACY-DELEGATED`.

Before destructive Console cleanup:

1. M4 live shadow parity has zero unexplained divergences across representative success, blocked, retry, rate-limit, orphan, human-decision, stall, and completion runs. `pwsh -NoProfile -File tool/m4-parity-evidence-check.ps1` is the read-only accumulated evidence gate; it must report `M4_SHADOW_PARITY_EVIDENCE_READY`, not merely zero current divergences.
2. M5 opt-in ChatGPT Loop authority passes the same acceptance corpus while Console supplies only atomic capabilities.
3. Rollback to the legacy Console path is tested after opt-in cutover.
4. The strict boundary audit reports `ORCHESTRATION_SHADOW_MIGRATION_COMPLETE`.
5. Console MCP orchestration removal is committed separately from ChatGPT Loop cutover, followed by Console rebuild/restart and end-to-end acceptance.

## Current copied-but-not-authoritative rule

Every M4 artifact must remain observational. A parity failure may be logged and surfaced, but it must not change the current production next action, submit another prompt, mutate Console task state, or alter browser state.
