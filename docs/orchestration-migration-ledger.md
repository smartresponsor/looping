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
| completion verification | COPIED/PARTIAL | `ChatGptLoopCompletionVerificationContract` mirrors factual/gate/runtime/evidence requirements | Console MCP | feed real completion receipts into shadow parity, then implement atomic verification execution before opt-in authority |
| semantic progress/stall | COPIED | decision projector repeat-count logic | Console MCP | feed live progress fingerprints and compare decisions |
| browser answer readiness | LEGACY-DELEGATED | none authoritative | Console MCP `watch/run-loop` interpretation | replace high-level run-loop interpretation with atomic observation receipts |
| prompt/chat transport | COPIED/PARTIAL | task-bank scheduling + `ChatGptLoopAtomicTransportPlan` | Console MCP `cmcp.go` compatibility path | implement the atomic plan behind an opt-in flag, prove parity, then remove internal high-level entrypoint use |
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

## Console MCP cleanup gate

Do **not** delete or weaken Console MCP orchestration while any row above is `LEGACY-DELEGATED`.

Before destructive Console cleanup:

1. M4 live shadow parity has zero unexplained divergences across representative success, blocked, retry, rate-limit, orphan, human-decision, stall, and completion runs.
2. M5 opt-in ChatGPT Loop authority passes the same acceptance corpus while Console supplies only atomic capabilities.
3. Rollback to the legacy Console path is tested after opt-in cutover.
4. The strict boundary audit reports `ORCHESTRATION_SHADOW_MIGRATION_COMPLETE`.
5. Console MCP orchestration removal is committed separately from ChatGPT Loop cutover, followed by Console rebuild/restart and end-to-end acceptance.

## Current copied-but-not-authoritative rule

Every M4 artifact must remain observational. A parity failure may be logged and surfaced, but it must not change the current production next action, submit another prompt, mutate Console task state, or alter browser state.
