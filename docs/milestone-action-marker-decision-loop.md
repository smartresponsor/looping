# Milestone: Action Marker Decision Loop

## Purpose

Replace color-style or stop-style decision handling with action-marker routing.

The loop must not treat an executor-reported fail as a terminal task. A fail is a routing signal: return a corrective instruction to the same ChatGPT executor, require the fail to be fixed and verified, then continue the original task while iteration budget remains.

The decision layer is not a new heavy code engine. The intended model is orchestration:

1. Capture the executor answer.
2. Extract the executor answer body and known task context.
3. Send that material to Ask for cheap model review.
4. Normalize the Ask result into a finite action-marker vocabulary.
5. Draft/submit the action-marker reply-back to the executor.
6. Continue the bounded loop unless the marker is terminal or budget is exhausted.

## Current implementation inventory

### Already present

#### `console-mcp`

- Captures stable ChatGPT executor answers in `recordEngineAnswerCapture()`.
- Calls local Ask through `executeAsk()` and records a decision in `recordEngineGatewayDecision()`.
- Has `console.write.engine.cycle.run_n`, which can run multiple full ChatGPT rounds within a bounded budget.
- Has round reset via `resetEngineCycleRoundState()` after a full reply-back cycle.
- Has generic reply-back drafting via `buildReplyBackText()`.
- Has Ask transcript persistence under `var/transcript`.

#### `chatgpt-loop`

- Has a runner/budget state in `tool/runner-adapter.ps1`.
- Has `ChatGptLoopAskGatewayIntentContract`, which already models Ask as an advisory review layer.
- Has `ChatGptLoopAskGatewayDecisionBuilder`, which already consumes Ask-style verdicts.
- Has `ChatGptLoopFinalActionResolver`, which already turns loop decisions into final runner actions.
- Has budget decrement and stop-on-budget-exhausted logic in `Update-RunnerBudget`.
- Has docs that define the boundary: Cloudflare Ask is advisory; ChatGPT Loop owns workflow routing.

### Missing or incomplete

#### 1. No canonical action-marker vocabulary

The current code still uses statuses/actions such as:

- `GREEN`
- `RED`
- `CONTINUE`
- `CORRECT_AND_CONTINUE`
- `return_to_chat`
- `return_revision_request_to_chat`
- `stop`
- `stop_blocked_by_policy`

These do not express the actual user-level command clearly enough.

Required marker vocabulary:

- `continue`
- `next`
- `go`
- `commit`
- `commit and continue`
- `commit and next`
- `fix fail and continue`
- `fix fail and commit`
- `fix fail, commit and continue`
- `fix blocker and continue`
- `recheck and continue`
- `done`

Only `done` is terminal. Budget exhaustion is also terminal, but it is a budget stop, not a decision-layer stop.

#### 2. Fail is still routed as a recovery/stop-style condition

In `console-mcp/src/engine/engine-cycle-browser.ts`, `runEngineCycleRounds()` stops when the recorded decision status is not in the old continue set:

```text
decision_recovery_required:<status>
```

This is the wrong user-case for executor-reported QA fail. A fail should map to a corrective marker such as:

```text
fix fail and continue
```

and the loop should continue while budget remains.

#### 3. Green/local pass can still be interpreted as complete

`GREEN`, `COMPLETE`, and `COMPLETED` are treated as full task completion in `ENGINE_CYCLE_COMPLETE_DECISION_STATUSES`.

This is unsafe because local green after a fail fix is not necessarily full task done.

The loop should terminate only on:

- `done`, where Ask/normalizer says the original specification is fully complete;
- budget exhausted;
- hard runtime block such as auth/rate-limit/binding/orphan that cannot be handled as a normal reply-back marker.

#### 4. Ask prompt still asks for color/status-style decision

`buildGatewayDecisionPrompt()` asks for this shape:

```json
{"status":"GREEN|CONTINUE|CORRECT_AND_CONTINUE|ATTENTION|RECHECK|GO_NEXT|DO_FIX"}
```

This should be replaced with an action-marker review prompt:

```text
Choose exactly one marker from the allowed list.
Treat reported fail as non-terminal corrective routing.
Use done only when the original task is fully complete.
```

#### 5. Fallback parser is unsafe

`console-mcp/src/tool/ask.ts` has `buildSemanticAskFallback()` and `extractPromptList()`.

It can parse `Findings:` from arbitrary prompt text. This caused instruction prose to become fake evidence.

Fallback must not semantically review the prompt. It should report transport/Ask degradation and let the loop use a safe marker such as `recheck and continue` or `fix fail and continue` only when deterministic extraction found a fail in the executor answer.

#### 6. Reply-back text is too generic

`buildReplyBackText()` currently emits:

```text
Engine decision for <task>: <status>.
Next action: <next>
Preserve useful repository progress...
```

It should emit action-marker language:

```text
Decision: fix fail and continue.

Reported fail:
<fail summary>

Fix the fail, run relevant verification until green, create a coherent commit if files changed, then continue the original execution specification with the next unfinished bounded step while budget remains.
```

#### 7. `chatgpt-loop` Ask decision builder is too coarse

`ChatGptLoopAskGatewayDecisionBuilder` currently maps Ask verdicts to:

- `continue`
- `return_warning_then_continue`
- `return_revision_request_to_chat`
- `stop_blocked_by_policy`

It should map Ask analysis to the same finite marker vocabulary and avoid terminal stop for ordinary executor fail.

#### 8. Runner adapter handles gateway decision statuses as old status codes

In `tool/runner-adapter.ps1`, gateway decision intake treats only `CONTINUE`/`ALLOW` as continue, `WAIT`/`RETRY` as retry, and everything else as reply-back.

It must understand action markers and route every non-terminal marker to reply-back followed by answer capture, not to final stop.
