param(
    [string]$Task = 'cmcp go cataloging',
    [int]$MaxIterations = 3
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Runner = Join-Path $Root 'tool/runner-adapter.ps1'

$Raw = & $Runner -Task $Task -MaxIterations $MaxIterations -Dispatch -SimulateHost 2>&1
$Payload = $Raw | ConvertFrom-Json

if (-not $Payload.dispatcherPayload) { throw 'dispatcherPayload missing' }
if ($Payload.dispatcherPayload.status -ne 'DISPATCHER_SIMULATED_RESULT') { throw "dispatcher did not simulate result: $($Payload.dispatcherPayload.status)" }
if (-not $Payload.dispatchedHostPayload) { throw 'dispatchedHostPayload missing' }
if (-not $Payload.continuePayload) { throw 'continuePayload missing' }
if ($Payload.continuePayload.dispatchResult.status -ne 'DISPATCH_RESULT_ACCEPTED') { throw "dispatch result was not accepted: $($Payload.continuePayload.dispatchResult.status)" }
if ($Payload.continuePayload.resumeState.status -ne 'RESUME_STATE_ADVANCED') { throw "resume state did not advance: $($Payload.continuePayload.resumeState.status)" }

$ResponseRaw = & $Runner -Task $Task -MaxIterations 1 -AutoFinalAction -AskVerdict revise -AskMessageToChat 'Please revise before continuing.' -ResponseTaskId 'smoke-engine-task' -ResponseTargetId 'smoke-target-response' 2>&1
$ResponsePayload = $ResponseRaw | ConvertFrom-Json

if ($ResponsePayload.runnerMode -ne 'auto_final_action') { throw "runner did not use auto final action mode: $($ResponsePayload.runnerMode)" }
if ($ResponsePayload.finalActionSelected -ne 'dispatch_chat_response') { throw "final action did not select response dispatch: $($ResponsePayload.finalActionSelected)" }
if (-not $ResponsePayload.chatResponsePayload) { throw 'chatResponsePayload missing' }
if ($ResponsePayload.chatResponsePayload.shouldSend -ne $true) { throw 'chatResponsePayload shouldSend was not true' }
if (-not $ResponsePayload.chatResponseDispatchContract) { throw 'chatResponseDispatchContract missing' }
if ($ResponsePayload.chatResponseDispatchContract.status -ne 'CHAT_RESPONSE_DISPATCH_CONTRACT_READY') { throw "chat response dispatch contract was not ready: $($ResponsePayload.chatResponseDispatchContract.status)" }
if (-not $ResponsePayload.responseDispatcherPayload) { throw 'responseDispatcherPayload missing' }
if ($ResponsePayload.responseDispatcherPayload[0].status -ne 'DISPATCHER_BOUNDARY_READY') { throw "response draft boundary was not ready" }
if ($ResponsePayload.responseDispatcherPayload[1].status -ne 'DISPATCHER_BOUNDARY_READY') { throw "response submit boundary was not ready" }
if ($ResponsePayload.responseDispatcherPayload[0].tool -ne 'console.write.engine.reply.draft') { throw "unexpected response draft tool" }
if ($ResponsePayload.responseDispatcherPayload[1].tool -ne 'console.write.engine.reply.submit') { throw "unexpected response submit tool" }
if ($ResponsePayload.responseDispatcherPayload[0].realExecution -ne 'disabled') { throw "response dispatch real execution is not disabled: $($ResponsePayload.responseDispatcherPayload[0].realExecution)" }

$RealBlockedRaw = & $Runner -Task $Task -MaxIterations 1 -AutoFinalAction -ExecuteReal -AskVerdict revise -AskMessageToChat 'Please revise before continuing.' -ResponseTaskId 'smoke-engine-task' -ResponseTargetId 'smoke-target-response' 2>&1
$RealBlockedPayload = $RealBlockedRaw | ConvertFrom-Json

if (-not $RealBlockedPayload.responseDispatcherPayload) { throw 'real blocked responseDispatcherPayload missing' }
if ($RealBlockedPayload.responseDispatcherPayload[0].status -ne 'DISPATCHER_REAL_EXECUTION_ENV_REQUIRED') { throw "real execution did not require env guard: $($RealBlockedPayload.responseDispatcherPayload[0].status)" }
if ($RealBlockedPayload.responseDispatcherPayload[0].realExecution -ne 'blocked') { throw "real execution was not blocked: $($RealBlockedPayload.responseDispatcherPayload[0].realExecution)" }

$PreviousRealExecutionEnv = $env:CHATGPT_LOOP_REAL_EXECUTION
try {
    $env:CHATGPT_LOOP_REAL_EXECUTION = '1'
    $RealReadyRaw = & $Runner -Task $Task -MaxIterations 1 -AutoFinalAction -ExecuteReal -AskVerdict revise -AskMessageToChat 'Please revise before continuing.' -ResponseTaskId 'smoke-engine-task' -ResponseTargetId 'smoke-target-response' 2>&1
    $RealReadyPayload = $RealReadyRaw | ConvertFrom-Json
} finally {
    $env:CHATGPT_LOOP_REAL_EXECUTION = $PreviousRealExecutionEnv
}

if (-not $RealReadyPayload.responseDispatcherPayload) { throw 'real ready responseDispatcherPayload missing' }
if ($RealReadyPayload.responseDispatcherPayload[0].status -ne 'DISPATCHER_REAL_EXECUTION_ADAPTER_READY') { throw "real execution adapter was not ready" }
if ($RealReadyPayload.responseDispatcherPayload[0].toolCall.name -ne 'console.write.engine.reply.draft') { throw "real draft tool call was not canonical" }
if ($RealReadyPayload.responseDispatcherPayload[1].toolCall.name -ne 'console.write.engine.reply.submit') { throw "real submit tool call was not canonical" }

$HostBridge = Join-Path $Root 'tool/runner-host-bridge.ps1'
$HostPayloadPath = Join-Path $Root 'var/runner/host-bridge-smoke.json'
$RealReadyPayload | ConvertTo-Json -Depth 40 | Set-Content -Path $HostPayloadPath -Encoding UTF8
$HostBridgeRaw = & $HostBridge -PayloadPath $HostPayloadPath -DryRun 2>&1
$HostBridgePayload = $HostBridgeRaw | ConvertFrom-Json

if ($HostBridgePayload.status -ne 'HOST_BRIDGE_INVOCATION_PLAN_READY') { throw "host bridge plan was not ready" }
if ($HostBridgePayload.invocationCount -ne 2) { throw "host bridge invocation count mismatch" }
if ($HostBridgePayload.invocations[0].tool -ne 'console.write.engine.reply.draft') { throw "host bridge draft invocation was not canonical" }
if ($HostBridgePayload.invocations[1].tool -ne 'console.write.engine.reply.submit') { throw "host bridge submit invocation was not canonical" }

$HostResultPath = Join-Path $Root 'var/runner/host-bridge-result-smoke.json'
[pscustomobject]@{
    results = @(
        @{ ok = $true; tool = 'console.write.engine.reply.draft'; status = 'ENGINE_REPLY_BACK_DRAFTED' },
        @{ ok = $true; tool = 'console.write.engine.reply.submit'; status = 'ENGINE_REPLY_BACK_SUBMITTED' }
    )
} | ConvertTo-Json -Depth 20 | Set-Content -Path $HostResultPath -Encoding UTF8
$HostResultRaw = & $HostBridge -PayloadPath $HostPayloadPath -ResultPath $HostResultPath 2>&1
$HostResultPayload = $HostResultRaw | ConvertFrom-Json

if ($HostResultPayload.status -ne 'HOST_BRIDGE_RESULT_ACCEPTED') { throw "host bridge result was not accepted" }
if ($HostResultPayload.nextAction -ne 'continue_after_host_invocation') { throw "host bridge did not continue after host invocation" }

$AdapterHostResultRaw = & $Runner -Task $Task -MaxIterations 1 -AutoFinalAction -ExecuteReal -AskVerdict revise -AskMessageToChat 'Please revise before continuing.' -ResponseTaskId 'smoke-engine-task' -ResponseTargetId 'smoke-target-response' -HostBridgeResultPath $HostResultPath 2>&1
$AdapterHostResultPayload = $AdapterHostResultRaw | ConvertFrom-Json

if ($AdapterHostResultPayload.runnerMode -ne 'host_bridge_result') { throw "runner did not enter host bridge result mode" }
if ($AdapterHostResultPayload.finalActionResult.status -ne 'FINAL_ACTION_HOST_RESULT_ACCEPTED') { throw "runner did not accept host bridge result" }
if ($AdapterHostResultPayload.hostBridgeResult.status -ne 'HOST_BRIDGE_RESULT_ACCEPTED') { throw "runner host bridge result was not accepted" }
if ($AdapterHostResultPayload.nextLoopTickPlan.status -ne 'NEXT_LOOP_TICK_PLAN_READY') { throw "next loop tick plan was not ready" }
if ($AdapterHostResultPayload.nextLoopTickPlan.stage -ne 'answer_capture') { throw "next loop tick stage was not answer_capture" }
if ($AdapterHostResultPayload.nextLoopTickPlan.phase -ne 'reply_watch') { throw "next loop tick phase was not reply_watch" }
if ($AdapterHostResultPayload.nextLoopTickPlan.action -ne 'capture_next_answer') { throw "next loop tick action was not capture_next_answer" }
if ($AdapterHostResultPayload.nextLoopTickContract.status -ne 'NEXT_LOOP_TICK_CONTRACT_READY') { throw "next loop tick contract was not ready" }
if ($AdapterHostResultPayload.nextLoopTickContract.tool -ne 'console.write.engine.answer.capture') { throw "next loop tick contract tool was not answer capture" }
if ($AdapterHostResultPayload.nextLoopTickContract.arguments.taskId -ne 'smoke-engine-task') { throw "next loop tick contract task id mismatch" }
if ($AdapterHostResultPayload.nextLoopTickContract.arguments.confirmCapture -ne $true) { throw "next loop tick contract confirmCapture was not true" }
if ($AdapterHostResultPayload.nextDispatchContract.tool -ne 'console.write.engine.answer.capture') { throw "next dispatch contract did not expose answer capture" }
if ($AdapterHostResultPayload.runnerStateStatus -ne 'RUNNER_STATE_PERSISTED') { throw "runner state was not persisted" }
if (-not (Test-Path $AdapterHostResultPayload.runnerStatePath)) { throw "runner state path does not exist" }

$AnswerCapturedPath = Join-Path $Root 'var/runner/answer-captured-smoke.json'
[pscustomobject]@{ ok = $true; status = 'ENGINE_ANSWER_CAPTURED'; task_id = 'smoke-engine-task' } | ConvertTo-Json -Depth 20 | Set-Content -Path $AnswerCapturedPath -Encoding UTF8
$AnswerCapturedRaw = & $Runner -Task $Task -MaxIterations 1 -ResponseTaskId 'smoke-engine-task' -AnswerCaptureResultPath $AnswerCapturedPath 2>&1
$AnswerCapturedPayload = $AnswerCapturedRaw | ConvertFrom-Json

if ($AnswerCapturedPayload.runnerMode -ne 'answer_capture_result') { throw "runner did not enter answer capture result mode" }
if ($AnswerCapturedPayload.finalActionResult.status -ne 'FINAL_ACTION_ANSWER_CAPTURED') { throw "answer capture final action was not captured" }
if ($AnswerCapturedPayload.gatewayDecisionContract.status -ne 'GATEWAY_DECISION_CONTRACT_READY') { throw "gateway decision contract was not ready" }
if ($AnswerCapturedPayload.gatewayDecisionContract.tool -ne 'console.write.engine.gateway.decide') { throw "gateway decision contract tool mismatch" }
if ($AnswerCapturedPayload.gatewayDecisionContract.arguments.confirmDecision -ne $true) { throw "gateway decision confirmDecision was not true" }
if ($AnswerCapturedPayload.nextDispatchContract.tool -ne 'console.write.engine.gateway.decide') { throw "next dispatch contract did not expose gateway decision" }

$AnswerNotReadyPath = Join-Path $Root 'var/runner/answer-not-ready-smoke.json'
[pscustomobject]@{ ok = $false; status = 'ENGINE_ANSWER_CAPTURE_NOT_READY'; task_id = 'smoke-engine-task' } | ConvertTo-Json -Depth 20 | Set-Content -Path $AnswerNotReadyPath -Encoding UTF8
$AnswerNotReadyRaw = & $Runner -Task $Task -MaxIterations 1 -ResponseTaskId 'smoke-engine-task' -AnswerCaptureResultPath $AnswerNotReadyPath 2>&1
$AnswerNotReadyPayload = $AnswerNotReadyRaw | ConvertFrom-Json

if ($AnswerNotReadyPayload.finalActionResult.status -ne 'FINAL_ACTION_ANSWER_CAPTURE_WAIT') { throw "answer capture wait final action mismatch" }
if ($AnswerNotReadyPayload.answerCaptureWaitPlan.status -ne 'ANSWER_CAPTURE_WAIT_PLAN_READY') { throw "answer capture wait plan was not ready" }

$GatewayContinuePath = Join-Path $Root 'var/runner/gateway-continue-smoke.json'
[pscustomobject]@{ ok = $true; status = 'ENGINE_GATEWAY_DECISION_RECORDED'; decision_status = 'CONTINUE'; task_id = 'smoke-engine-task' } | ConvertTo-Json -Depth 20 | Set-Content -Path $GatewayContinuePath -Encoding UTF8
$GatewayContinueRaw = & $Runner -Task $Task -MaxIterations 1 -ResponseTaskId 'smoke-engine-task' -GatewayDecisionResultPath $GatewayContinuePath 2>&1
$GatewayContinuePayload = $GatewayContinueRaw | ConvertFrom-Json

if ($GatewayContinuePayload.runnerMode -ne 'gateway_decision_result') { throw "runner did not enter gateway decision result mode" }
if ($GatewayContinuePayload.finalActionResult.status -ne 'FINAL_ACTION_GATEWAY_CONTINUE') { throw "gateway continue final action mismatch" }
if ($GatewayContinuePayload.gatewayContinuePlan.status -ne 'GATEWAY_CONTINUE_PLAN_READY') { throw "gateway continue plan was not ready" }
if ($GatewayContinuePayload.gatewayContinueContract.status -ne 'GATEWAY_CONTINUE_CONTRACT_READY') { throw "gateway continue contract was not ready" }
if ($GatewayContinuePayload.gatewayContinueContract.tool -ne 'console.write.engine.worker.tick') { throw "gateway continue contract tool mismatch" }
if ($GatewayContinuePayload.gatewayContinueContract.arguments.maxTicks -ne 1) { throw "gateway continue maxTicks mismatch" }
if ($GatewayContinuePayload.nextDispatchContract.tool -ne 'console.write.engine.worker.tick') { throw "next dispatch contract did not expose worker tick" }

$GatewayReplyPath = Join-Path $Root 'var/runner/gateway-reply-smoke.json'
[pscustomobject]@{ ok = $true; status = 'ENGINE_GATEWAY_DECISION_RECORDED'; decision_status = 'REVISE'; task_id = 'smoke-engine-task' } | ConvertTo-Json -Depth 20 | Set-Content -Path $GatewayReplyPath -Encoding UTF8
$GatewayReplyRaw = & $Runner -Task $Task -MaxIterations 1 -ResponseTaskId 'smoke-engine-task' -GatewayDecisionResultPath $GatewayReplyPath 2>&1
$GatewayReplyPayload = $GatewayReplyRaw | ConvertFrom-Json

if ($GatewayReplyPayload.finalActionResult.status -ne 'FINAL_ACTION_GATEWAY_REPLY_BACK') { throw "gateway reply-back final action mismatch" }
if ($GatewayReplyPayload.gatewayReplyBackPlan.status -ne 'GATEWAY_REPLY_BACK_PLAN_READY') { throw "gateway reply-back plan was not ready" }
if ($GatewayReplyPayload.gatewayReplyBackContract.status -ne 'GATEWAY_REPLY_BACK_CONTRACT_READY') { throw "gateway reply-back contract was not ready" }
if ($GatewayReplyPayload.gatewayReplyBackContract.sequence[0].tool -ne 'console.write.engine.reply.draft') { throw "gateway reply-back draft tool mismatch" }
if ($GatewayReplyPayload.gatewayReplyBackContract.sequence[1].tool -ne 'console.write.engine.reply.submit') { throw "gateway reply-back submit tool mismatch" }
if ($GatewayReplyPayload.gatewayReplyBackContract.sequence[0].arguments.taskId -ne 'smoke-engine-task') { throw "gateway reply-back task id mismatch" }
if ($GatewayReplyPayload.nextDispatchContract.sequence[0].tool -ne 'console.write.engine.reply.draft') { throw "next dispatch contract did not expose reply draft" }
if ($GatewayReplyPayload.nextDispatchContract.sequence[1].tool -ne 'console.write.engine.reply.submit') { throw "next dispatch contract did not expose reply submit" }

$GatewayWaitPath = Join-Path $Root 'var/runner/gateway-wait-smoke.json'
[pscustomobject]@{ ok = $true; status = 'ENGINE_GATEWAY_DECISION_RECORDED'; decision_status = 'WAIT'; task_id = 'smoke-engine-task' } | ConvertTo-Json -Depth 20 | Set-Content -Path $GatewayWaitPath -Encoding UTF8
$GatewayWaitRaw = & $Runner -Task $Task -MaxIterations 1 -ResponseTaskId 'smoke-engine-task' -GatewayDecisionResultPath $GatewayWaitPath 2>&1
$GatewayWaitPayload = $GatewayWaitRaw | ConvertFrom-Json

if ($GatewayWaitPayload.finalActionResult.status -ne 'FINAL_ACTION_GATEWAY_WAIT') { throw "gateway wait final action mismatch" }
if ($GatewayWaitPayload.gatewayWaitPlan.status -ne 'GATEWAY_WAIT_PLAN_READY') { throw "gateway wait plan was not ready" }

$WorkerContinuePath = Join-Path $Root 'var/runner/worker-continue-smoke.json'
[pscustomobject]@{ ok = $true; status = 'ENGINE_WORKER_TICK_CONTINUE'; task_id = 'smoke-engine-task' } | ConvertTo-Json -Depth 20 | Set-Content -Path $WorkerContinuePath -Encoding UTF8
$WorkerContinueRaw = & $Runner -Task $Task -MaxIterations 1 -ResponseTaskId 'smoke-engine-task' -WorkerTickResultPath $WorkerContinuePath 2>&1
$WorkerContinuePayload = $WorkerContinueRaw | ConvertFrom-Json

if ($WorkerContinuePayload.runnerMode -ne 'worker_tick_result') { throw "runner did not enter worker tick result mode" }
if ($WorkerContinuePayload.finalActionResult.status -ne 'FINAL_ACTION_WORKER_CONTINUE') { throw "worker continue final action mismatch" }
if ($WorkerContinuePayload.workerContinuePlan.status -ne 'WORKER_TICK_CONTINUE_PLAN_READY') { throw "worker continue plan was not ready" }

$WorkerWaitPath = Join-Path $Root 'var/runner/worker-wait-smoke.json'
[pscustomobject]@{ ok = $true; status = 'ENGINE_WORKER_TICK_WAITING_USER'; task_id = 'smoke-engine-task' } | ConvertTo-Json -Depth 20 | Set-Content -Path $WorkerWaitPath -Encoding UTF8
$WorkerWaitRaw = & $Runner -Task $Task -MaxIterations 1 -ResponseTaskId 'smoke-engine-task' -WorkerTickResultPath $WorkerWaitPath 2>&1
$WorkerWaitPayload = $WorkerWaitRaw | ConvertFrom-Json

if ($WorkerWaitPayload.finalActionResult.status -ne 'FINAL_ACTION_WORKER_WAITING_USER') { throw "worker waiting-user final action mismatch" }
if ($WorkerWaitPayload.workerWaitPlan.status -ne 'WORKER_TICK_WAITING_USER_PLAN_READY') { throw "worker wait plan was not ready" }

$WorkerStopPath = Join-Path $Root 'var/runner/worker-stop-smoke.json'
[pscustomobject]@{ ok = $true; status = 'ENGINE_WORKER_TICK_IDLE'; task_id = 'smoke-engine-task' } | ConvertTo-Json -Depth 20 | Set-Content -Path $WorkerStopPath -Encoding UTF8
$WorkerStopRaw = & $Runner -Task $Task -MaxIterations 1 -ResponseTaskId 'smoke-engine-task' -WorkerTickResultPath $WorkerStopPath 2>&1
$WorkerStopPayload = $WorkerStopRaw | ConvertFrom-Json

if ($WorkerStopPayload.finalActionResult.status -ne 'FINAL_ACTION_WORKER_STOP') { throw "worker stop final action mismatch" }
if ($WorkerStopPayload.workerStopPlan.status -ne 'WORKER_TICK_STOP_PLAN_READY') { throw "worker stop plan was not ready" }

[pscustomobject]@{
    ok = $true
    status = 'RUNNER_SMOKE_PASSED'
    task = $Task
    continueRunId = $Payload.continuePayload.runId
    responseRunId = $ResponsePayload.runId
    responseDispatchStatus = $ResponsePayload.responseDispatcherPayload.status
} | ConvertTo-Json -Depth 10
