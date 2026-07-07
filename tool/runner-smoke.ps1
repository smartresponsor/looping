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
if ($AdapterHostResultPayload.nextDispatchStatus -ne 'NEXT_DISPATCH_BOUNDARY_READY') { throw "next dispatch boundary was not ready" }
if ($AdapterHostResultPayload.nextDispatchBoundary[0].status -ne 'DISPATCHER_BOUNDARY_READY') { throw "next dispatch boundary result was not ready" }
if (-not (Test-Path $AdapterHostResultPayload.nextDispatchPayload[0].path)) { throw "next dispatch payload path does not exist" }

$NextDispatchBlockedRaw = & $Runner -Task $Task -MaxIterations 1 -AutoFinalAction -AskVerdict revise -AskMessageToChat 'Please revise before continuing.' -ResponseTaskId 'smoke-engine-task' -ResponseTargetId 'smoke-target-response' -HostBridgeResultPath $HostResultPath -NextDispatchExecuteReal 2>&1
$NextDispatchBlockedPayload = $NextDispatchBlockedRaw | ConvertFrom-Json
if ($NextDispatchBlockedPayload.nextDispatchStatus -ne 'NEXT_DISPATCH_REAL_ENV_REQUIRED') { throw "next dispatch real env guard did not block" }
if ($NextDispatchBlockedPayload.nextDispatchBoundary[0].status -ne 'DISPATCHER_REAL_EXECUTION_ENV_REQUIRED') { throw "next dispatch dispatcher env guard mismatch" }

$PreviousNextDispatchEnv = $env:CHATGPT_LOOP_REAL_EXECUTION
try {
    $env:CHATGPT_LOOP_REAL_EXECUTION = '1'
    $NextDispatchReadyRaw = & $Runner -Task $Task -MaxIterations 1 -AutoFinalAction -AskVerdict revise -AskMessageToChat 'Please revise before continuing.' -ResponseTaskId 'smoke-engine-task' -ResponseTargetId 'smoke-target-response' -HostBridgeResultPath $HostResultPath -NextDispatchExecuteReal 2>&1
    $NextDispatchReadyPayload = $NextDispatchReadyRaw | ConvertFrom-Json
} finally {
    $env:CHATGPT_LOOP_REAL_EXECUTION = $PreviousNextDispatchEnv
}
if ($NextDispatchReadyPayload.nextDispatchStatus -ne 'NEXT_DISPATCH_REAL_ADAPTER_READY') { throw "next dispatch real adapter was not ready" }
if ($NextDispatchReadyPayload.nextDispatchBoundary[0].toolCall.name -ne 'console.write.engine.answer.capture') { throw "next dispatch toolCall was not answer capture" }

$TransportResultPath = Join-Path $Root 'var/runner/transport-result-smoke.json'
[pscustomobject]@{ ok = $true; tool = 'console.write.engine.answer.capture'; status = 'ENGINE_ANSWER_CAPTURED'; task_id = 'smoke-engine-task' } | ConvertTo-Json -Depth 20 | Set-Content -Path $TransportResultPath -Encoding UTF8
$Dispatcher = Join-Path $Root 'tool/runner-dispatcher.ps1'
$TransportResultRaw = & $Dispatcher -PayloadPath $NextDispatchReadyPayload.nextDispatchPayload[0].path -ResultPath $TransportResultPath 2>&1
$TransportResultPayload = $TransportResultRaw | ConvertFrom-Json
if ($TransportResultPayload.status -ne 'DISPATCHER_TRANSPORT_RESULT_ACCEPTED') { throw "transport result was not accepted" }
if ($TransportResultPayload.nextAction -ne 'feed_result_to_runner_intake') { throw "transport result next action mismatch" }

$TransportFeedRaw = & $Runner -Task $Task -MaxIterations 1 -ResponseTaskId 'smoke-engine-task' -TransportResultPath $TransportResultPath 2>&1
$TransportFeedPayload = $TransportFeedRaw | ConvertFrom-Json
if ($TransportFeedPayload.runnerMode -ne 'transport_result') { throw "runner did not enter transport result mode" }
if ($TransportFeedPayload.finalActionResult.status -ne 'FINAL_ACTION_TRANSPORT_RESULT_FED') { throw "transport result was not fed to runner intake" }
if ($TransportFeedPayload.transportIntakePayload.runnerMode -ne 'answer_capture_result') { throw "transport result did not route to answer capture intake" }
if ($TransportFeedPayload.transportIntakePayload.finalActionResult.status -ne 'FINAL_ACTION_ANSWER_CAPTURED') { throw "transport answer capture intake did not complete" }

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
if ($AnswerNotReadyPayload.retryPolicy.action -ne 'retry_answer_capture') { throw "answer capture wait retry policy mismatch" }
if ($AnswerNotReadyPayload.retryPolicy.strategy -ne 'bounded_retry') { throw "answer capture wait retry strategy mismatch" }
if ($AnswerNotReadyPayload.retryPolicy.attempt -ne 0) { throw "answer capture retry attempt mismatch" }
if ($AnswerNotReadyPayload.retryPolicy.nextAttempt -ne 1) { throw "answer capture retry next attempt mismatch" }

$AnswerRetryExhaustedRaw = & $Runner -Task $Task -MaxIterations 1 -RetryAttempt 5 -ResponseTaskId 'smoke-engine-task' -AnswerCaptureResultPath $AnswerNotReadyPath 2>&1
$AnswerRetryExhaustedPayload = $AnswerRetryExhaustedRaw | ConvertFrom-Json
if ($AnswerRetryExhaustedPayload.finalActionResult.status -ne 'FINAL_ACTION_RETRY_EXHAUSTED') { throw "answer capture retry exhaustion final action mismatch" }
if ($AnswerRetryExhaustedPayload.retryPolicy.status -ne 'RETRY_POLICY_EXHAUSTED') { throw "answer capture retry policy was not exhausted" }
if ($AnswerRetryExhaustedPayload.retryPolicy.attempt -ne 5) { throw "answer capture exhausted attempt mismatch" }
if ($AnswerRetryExhaustedPayload.recoveryPlan.action -ne 'recover_browser_target') { throw "answer capture recovery plan mismatch" }
if ($AnswerRetryExhaustedPayload.finalActionResult.action -ne 'recover_browser_target') { throw "answer capture final recovery action mismatch" }
if ($AnswerRetryExhaustedPayload.recoveryPlan.dispatchContract.tool -ne 'console.write.engine.chat.bind') { throw "answer capture recovery dispatch contract mismatch" }
if ($AnswerRetryExhaustedPayload.nextDispatchContract.tool -ne 'console.write.engine.chat.bind') { throw "answer capture recovery next dispatch mismatch" }
if ($AnswerRetryExhaustedPayload.nextDispatchStatus -ne 'NEXT_DISPATCH_BOUNDARY_READY') { throw "answer capture recovery next dispatch boundary not ready" }

$RecoveryTransportPath = Join-Path $Root 'var/runner/recovery-transport-smoke.json'
[pscustomobject]@{
    ok = $true
    status = 'DISPATCHER_TRANSPORT_RESULT_ACCEPTED'
    tool = 'console.write.engine.chat.bind'
    result = @{ ok = $true; tool = 'console.write.engine.chat.bind'; status = 'ENGINE_CHAT_BIND_RECOVERED'; task_id = 'smoke-engine-task'; chat_id = 'smoke-chat-recovered' }
} | ConvertTo-Json -Depth 20 | Set-Content -Path $RecoveryTransportPath -Encoding UTF8
$RecoveryResultRaw = & $Runner -Task $Task -MaxIterations 1 -RetryAttempt 5 -ResponseTaskId 'smoke-engine-task' -TransportResultPath $RecoveryTransportPath 2>&1
$RecoveryResultPayload = $RecoveryResultRaw | ConvertFrom-Json
if ($RecoveryResultPayload.finalActionResult.status -ne 'FINAL_ACTION_RECOVERY_RESULT_ACCEPTED') { throw "recovery result final action mismatch" }
if ($RecoveryResultPayload.nextDispatchContract.tool -ne 'console.write.engine.answer.capture') { throw "recovery result did not continue to answer capture" }
if ($RecoveryResultPayload.nextDispatchContract.arguments.retryAttempt -ne 0) { throw "recovery result did not reset retry attempt" }
if ($RecoveryResultPayload.nextDispatchStatus -ne 'NEXT_DISPATCH_BOUNDARY_READY') { throw "recovery result next dispatch boundary not ready" }

$TransportAdapterResultPath = Join-Path $Root 'var/runner/transport-adapter-result-smoke.json'
[pscustomobject]@{ ok = $true; tool = 'console.write.engine.chat.bind'; status = 'ENGINE_CHAT_BIND_RECOVERED'; task_id = 'smoke-engine-task'; chat_id = 'smoke-chat-adapter' } | ConvertTo-Json -Depth 20 | Set-Content -Path $TransportAdapterResultPath -Encoding UTF8
$TransportAdapterRaw = & (Join-Path $Root 'tool/runner-transport-adapter.ps1') -Task $Task -MaxIterations 1 -PayloadPath $AnswerRetryExhaustedPayload.nextDispatchPayload[0].path -ResultPath $TransportAdapterResultPath 2>&1
$TransportAdapterPayload = $TransportAdapterRaw | ConvertFrom-Json
if ($TransportAdapterPayload.status -ne 'RUNNER_TRANSPORT_ADAPTER_FED') { throw "transport adapter did not feed result" }
if ($TransportAdapterPayload.feed.finalActionResult.status -ne 'FINAL_ACTION_RECOVERY_RESULT_ACCEPTED') { throw "transport adapter feed final action mismatch" }
if ($TransportAdapterPayload.feed.nextDispatchContract.tool -ne 'console.write.engine.answer.capture') { throw "transport adapter feed next dispatch mismatch" }
$TransportJournalPath = Join-Path $Root 'var/runner/journal/runner.ndjson'
if (-not (Test-Path $TransportJournalPath)) { throw "transport adapter journal file missing" }
$TransportJournalRaw = Get-Content -Raw -Path $TransportJournalPath
if ($TransportJournalRaw -notlike '*RUNNER_TRANSPORT_ADAPTER_FED*') { throw "transport adapter journal fed event missing" }
$JournalInspectRaw = & (Join-Path $Root 'tool/runner-journal-inspect.ps1') -Tail 5 2>&1
$JournalInspectPayload = $JournalInspectRaw | ConvertFrom-Json
if ($JournalInspectPayload.status -ne 'RUNNER_JOURNAL_INSPECTED') { throw "runner journal inspect status mismatch" }
if ($JournalInspectPayload.totalEvents -lt 1) { throw "runner journal inspect total event mismatch" }
if (@($JournalInspectPayload.summary).Count -lt 1) { throw "runner journal inspect summary missing" }

$InvalidTransportResultPath = Join-Path $Root 'var/runner/transport-adapter-invalid-smoke.json'
[pscustomobject]@{ ok = $true; status = 'ENGINE_CHAT_BIND_RECOVERED' } | ConvertTo-Json -Depth 20 | Set-Content -Path $InvalidTransportResultPath -Encoding UTF8
$InvalidTransportRaw = & (Join-Path $Root 'tool/runner-transport-adapter.ps1') -Task $Task -MaxIterations 1 -PayloadPath $AnswerRetryExhaustedPayload.nextDispatchPayload[0].path -ResultPath $InvalidTransportResultPath 2>&1
$InvalidTransportPayload = $InvalidTransportRaw | ConvertFrom-Json
if ($InvalidTransportPayload.status -ne 'RUNNER_TRANSPORT_RESULT_CONTRACT_INVALID') { throw "transport adapter invalid contract was not rejected" }
if (@($InvalidTransportPayload.missingFields) -notcontains 'tool') { throw "transport adapter invalid contract did not report missing tool" }

$MismatchTransportResultPath = Join-Path $Root 'var/runner/transport-adapter-mismatch-smoke.json'
[pscustomobject]@{ ok = $true; tool = 'console.write.engine.worker.tick'; status = 'ENGINE_WORKER_TICK_ACCEPTED' } | ConvertTo-Json -Depth 20 | Set-Content -Path $MismatchTransportResultPath -Encoding UTF8
$MismatchTransportRaw = & (Join-Path $Root 'tool/runner-transport-adapter.ps1') -Task $Task -MaxIterations 1 -PayloadPath $AnswerRetryExhaustedPayload.nextDispatchPayload[0].path -ResultPath $MismatchTransportResultPath 2>&1
$MismatchTransportPayload = $MismatchTransportRaw | ConvertFrom-Json
if ($MismatchTransportPayload.status -ne 'RUNNER_TRANSPORT_RESULT_TOOL_MISMATCH') { throw "transport adapter tool mismatch was not rejected" }
$StaleLockPath = Join-Path $Root 'var/runner/lock/runner.lock'
[pscustomobject]@{ owner = 'stale-smoke'; pid = 0; acquiredAt = (Get-Date).AddMinutes(-31).ToUniversalTime().ToString('o') } | ConvertTo-Json -Depth 20 | Set-Content -Path $StaleLockPath -Encoding UTF8
$StaleLockRaw = & (Join-Path $Root 'tool/runner-daemon.ps1') -Task $Task -MaxIterations 1 2>&1
$StaleLockPayload = $StaleLockRaw | ConvertFrom-Json
if ($StaleLockPayload.status -eq 'RUNNER_LOCK_BUSY') { throw "runner stale lock was not replaced" }
if (Test-Path $StaleLockPath) { throw "runner stale lock was not cleaned" }

$WorkerRecoveryTransportPath = Join-Path $Root 'var/runner/worker-recovery-transport-smoke.json'
[pscustomobject]@{
    ok = $true
    status = 'DISPATCHER_TRANSPORT_RESULT_ACCEPTED'
    tool = 'console.write.engine.worker.tick'
    result = @{ ok = $true; tool = 'console.write.engine.worker.tick'; status = 'ENGINE_WORKER_TICK_ACCEPTED'; task_id = 'smoke-engine-task'; recoveryMode = 'worker_state' }
} | ConvertTo-Json -Depth 20 | Set-Content -Path $WorkerRecoveryTransportPath -Encoding UTF8
$WorkerRecoveryRaw = & $Runner -Task $Task -MaxIterations 2 -RetryAttempt 3 -ResponseTaskId 'smoke-engine-task' -TransportResultPath $WorkerRecoveryTransportPath 2>&1
$WorkerRecoveryPayload = $WorkerRecoveryRaw | ConvertFrom-Json
if ($WorkerRecoveryPayload.finalActionResult.status -ne 'FINAL_ACTION_TRANSPORT_RESULT_FED') { throw "worker recovery transport was not fed" }
if ($WorkerRecoveryPayload.transportIntakePayload.runnerMode -ne 'worker_tick_result') { throw "worker recovery did not route to worker intake" }
if ($WorkerRecoveryPayload.transportIntakePayload.finalActionResult.status -ne 'FINAL_ACTION_WORKER_CONTINUE') { throw "worker recovery intake did not continue" }
if ($WorkerRecoveryPayload.transportIntakePayload.retryPolicy) { throw "worker recovery intake should reset retry policy on successful continue" }

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
if ($GatewayReplyPayload.nextDispatchBoundary.Count -ne 2) { throw "reply-back next dispatch boundary count mismatch" }
if ($GatewayReplyPayload.nextDispatchBoundary[0].tool -ne 'console.write.engine.reply.draft') { throw "reply-back next dispatch draft boundary mismatch" }
if ($GatewayReplyPayload.nextDispatchBoundary[1].tool -ne 'console.write.engine.reply.submit') { throw "reply-back next dispatch submit boundary mismatch" }

$ReplySequenceResultPath = Join-Path $Root 'var/runner/reply-sequence-result-smoke.json'
[pscustomobject]@{
    results = @(
        @{ ok = $true; tool = 'console.write.engine.reply.draft'; status = 'ENGINE_REPLY_BACK_DRAFTED'; task_id = 'smoke-engine-task'; target_id = 'smoke-target-response' },
        @{ ok = $true; tool = 'console.write.engine.reply.submit'; status = 'ENGINE_REPLY_BACK_SUBMITTED'; task_id = 'smoke-engine-task'; target_id = 'smoke-target-response' }
    )
} | ConvertTo-Json -Depth 20 | Set-Content -Path $ReplySequenceResultPath -Encoding UTF8
$ReplySequenceRaw = & $Runner -Task $Task -MaxIterations 1 -ResponseTaskId 'smoke-engine-task' -ResponseTargetId 'smoke-target-response' -ReplySequenceResultPath $ReplySequenceResultPath 2>&1
$ReplySequencePayload = $ReplySequenceRaw | ConvertFrom-Json
if ($ReplySequencePayload.runnerMode -ne 'reply_sequence_result') { throw "runner did not enter reply sequence result mode" }
if ($ReplySequencePayload.finalActionResult.status -ne 'FINAL_ACTION_REPLY_SEQUENCE_ACCEPTED') { throw "reply sequence was not accepted" }
if ($ReplySequencePayload.nextDispatchContract.tool -ne 'console.write.engine.answer.capture') { throw "reply sequence did not advance to answer capture" }
if ($ReplySequencePayload.nextDispatchStatus -ne 'NEXT_DISPATCH_BOUNDARY_READY') { throw "reply sequence next dispatch boundary was not ready" }

$ResumeRaw = & $Runner -Task $Task -MaxIterations 1 -ResumeLatest 2>&1
$ResumePayload = $ResumeRaw | ConvertFrom-Json
if ($ResumePayload.runnerMode -ne 'resume_latest') { throw "runner did not enter resume latest mode" }
if ($ResumePayload.finalActionResult.status -ne 'FINAL_ACTION_RESUME_LATEST') { throw "resume latest final action mismatch" }
if ($ResumePayload.nextDispatchContract.tool -ne 'console.write.engine.answer.capture') { throw "resume latest did not restore answer capture next dispatch" }
if ($ResumePayload.nextDispatchStatus -ne 'NEXT_DISPATCH_BOUNDARY_READY') { throw "resume latest next dispatch boundary was not ready" }
if (-not $ResumePayload.budget) { throw "resume latest budget cursor missing" }
if ($ResumePayload.budget.remaining -ne 1) { throw "resume latest budget remaining mismatch" }
if ($ResumePayload.budget.mode -ne 'steps') { throw "resume latest budget mode mismatch" }
if ($ResumePayload.resumeState.schemaVersion -ne 2) { throw "resume latest schema version mismatch" }
if ($ResumePayload.resumeState.runtimeVersion -ne '2026.07.runner-loop') { throw "resume latest runtime version mismatch" }
if ($ResumePayload.resumeState.capabilities.recoveryResult -ne $true) { throw "resume latest capabilities missing recovery result" }

$DaemonRaw = & (Join-Path $Root 'tool/runner-daemon.ps1') -Task $Task -MaxIterations 1 2>&1
$DaemonPayload = $DaemonRaw | ConvertFrom-Json
if ($DaemonPayload.status -ne 'RUNNER_DAEMON_DISPATCH_READY') { throw "runner daemon dispatch was not ready" }
if (-not $DaemonPayload.dispatchPayloadPath) { throw "runner daemon dispatch payload path missing" }
if (-not $DaemonPayload.dispatchTool) { throw "runner daemon dispatch tool missing" }
$LockDir = Join-Path $Root 'var/runner/lock'
if (-not (Test-Path $LockDir)) { New-Item -ItemType Directory -Path $LockDir | Out-Null }
$LockPath = Join-Path $LockDir 'runner.lock'
[pscustomobject]@{ owner = 'smoke-lock'; pid = 0; acquiredAt = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Depth 20 | Set-Content -Path $LockPath -Encoding UTF8
$DaemonBusyRaw = & (Join-Path $Root 'tool/runner-daemon.ps1') -Task $Task -MaxIterations 1 2>&1
$DaemonBusyPayload = $DaemonBusyRaw | ConvertFrom-Json
if ($DaemonBusyPayload.status -ne 'RUNNER_LOCK_BUSY') { throw "runner daemon lock busy guard mismatch" }
Remove-Item -Path $LockPath -Force
if ($DaemonPayload.toolCall.name -ne $DaemonPayload.dispatchTool) { throw "runner daemon tool call name mismatch" }
if (-not $DaemonPayload.toolCall.arguments) { throw "runner daemon tool call arguments missing" }
if (-not $DaemonPayload.expectedResultPath) { throw "runner daemon expected result path missing" }
if (@($DaemonPayload.adapterCommand).Count -lt 8) { throw "runner daemon adapter command too short" }
if (-not (Test-Path $DaemonPayload.handoffPath)) { throw "runner daemon handoff manifest missing" }
$DaemonHandoff = Get-Content -Raw -Path $DaemonPayload.handoffPath | ConvertFrom-Json
if ($DaemonHandoff.status -ne 'RUNNER_EXECUTOR_HANDOFF_READY') { throw "runner daemon handoff status mismatch" }
if ($DaemonHandoff.toolCall.name -ne $DaemonPayload.toolCall.name) { throw "runner daemon handoff tool call mismatch" }
if (@($DaemonHandoff.adapterCommand).Count -lt 8) { throw "runner daemon handoff adapter command too short" }
if (@($DaemonHandoff.runbook).Count -ne 4) { throw "runner daemon handoff runbook count mismatch" }
if ($DaemonHandoff.runbook[0].action -ne 'invoke_tool_call') { throw "runner daemon runbook step 1 mismatch" }
if (@($DaemonHandoff.runbook[1].requiredFields) -notcontains 'tool') { throw "runner daemon runbook required fields mismatch" }
if ($DaemonHandoff.runbook[2].action -ne 'run_transport_adapter') { throw "runner daemon runbook step 3 mismatch" }
if (-not (Test-Path $DaemonPayload.journalPath)) { throw "runner daemon journal file missing" }
$RunnerJournalRaw = Get-Content -Raw -Path $DaemonPayload.journalPath
if ($RunnerJournalRaw -notlike '*RUNNER_DAEMON_DISPATCH_READY*') { throw "runner daemon journal dispatch event missing" }

$GatewayWaitPath = Join-Path $Root 'var/runner/gateway-wait-smoke.json'
[pscustomobject]@{ ok = $true; status = 'ENGINE_GATEWAY_DECISION_RECORDED'; decision_status = 'WAIT'; task_id = 'smoke-engine-task' } | ConvertTo-Json -Depth 20 | Set-Content -Path $GatewayWaitPath -Encoding UTF8
$GatewayWaitRaw = & $Runner -Task $Task -MaxIterations 1 -ResponseTaskId 'smoke-engine-task' -GatewayDecisionResultPath $GatewayWaitPath 2>&1
$GatewayWaitPayload = $GatewayWaitRaw | ConvertFrom-Json

if ($GatewayWaitPayload.finalActionResult.status -ne 'FINAL_ACTION_GATEWAY_WAIT') { throw "gateway wait final action mismatch" }
if ($GatewayWaitPayload.gatewayWaitPlan.status -ne 'GATEWAY_WAIT_PLAN_READY') { throw "gateway wait plan was not ready" }
if ($GatewayWaitPayload.retryPolicy.action -ne 'retry_gateway_decision') { throw "gateway wait retry policy mismatch" }

$WorkerContinuePath = Join-Path $Root 'var/runner/worker-continue-smoke.json'
[pscustomobject]@{ ok = $true; status = 'ENGINE_WORKER_TICK_CONTINUE'; task_id = 'smoke-engine-task' } | ConvertTo-Json -Depth 20 | Set-Content -Path $WorkerContinuePath -Encoding UTF8
$WorkerContinueRaw = & $Runner -Task $Task -MaxIterations 1 -ResponseTaskId 'smoke-engine-task' -WorkerTickResultPath $WorkerContinuePath 2>&1
$WorkerContinuePayload = $WorkerContinueRaw | ConvertFrom-Json

if ($WorkerContinuePayload.runnerMode -ne 'worker_tick_result') { throw "runner did not enter worker tick result mode" }
if ($WorkerContinuePayload.finalActionResult.status -ne 'FINAL_ACTION_BUDGET_EXHAUSTED') { throw "worker continue did not exhaust one-step budget" }
if ($WorkerContinuePayload.budget.remaining -ne 0) { throw "worker continue budget did not decrement to zero" }
if ($WorkerContinuePayload.retryPolicy.strategy -ne 'terminal') { throw "budget exhausted retry policy was not terminal" }

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

$WorkerRcPath = Join-Path $Root 'var/runner/worker-rc-smoke.json'
[pscustomobject]@{ ok = $true; status = 'ENGINE_WORKER_TICK_RC_REACHED'; task_id = 'smoke-engine-task' } | ConvertTo-Json -Depth 20 | Set-Content -Path $WorkerRcPath -Encoding UTF8
$WorkerRcRaw = & $Runner -Task $Task -UntilRc -ResponseTaskId 'smoke-engine-task' -WorkerTickResultPath $WorkerRcPath 2>&1
$WorkerRcPayload = $WorkerRcRaw | ConvertFrom-Json
if ($WorkerRcPayload.finalActionResult.status -ne 'FINAL_ACTION_RC_REACHED') { throw "until-rc worker signal did not stop as RC reached" }
if ($WorkerRcPayload.nextDispatchContract) { throw "RC reached should not produce next dispatch contract" }
if ($WorkerRcPayload.retryPolicy.strategy -ne 'terminal') { throw "RC reached retry policy was not terminal" }

$ClosedFlow = @(
    @{ step = 'reply_back'; status = $HostResultPayload.status; next = $AdapterHostResultPayload.nextDispatchContract.tool },
    @{ step = 'answer_capture'; status = $AnswerCapturedPayload.finalActionResult.status; next = $AnswerCapturedPayload.nextDispatchContract.tool },
    @{ step = 'gateway_decide'; status = $GatewayContinuePayload.finalActionResult.status; next = $GatewayContinuePayload.nextDispatchContract.tool },
    @{ step = 'worker_tick'; status = $WorkerStopPayload.finalActionResult.status; next = $WorkerStopPayload.workerStopPlan.nextAction }
)

if ($ClosedFlow[0].next -ne 'console.write.engine.answer.capture') { throw "closed flow did not advance from reply to answer capture" }
if ($ClosedFlow[1].next -ne 'console.write.engine.gateway.decide') { throw "closed flow did not advance from answer capture to gateway decision" }
if ($ClosedFlow[2].next -ne 'console.write.engine.worker.tick') { throw "closed flow did not advance from gateway continue to worker tick" }
if ($ClosedFlow[3].next -ne 'stop_loop') { throw "closed flow did not stop on worker idle" }

[pscustomobject]@{
    ok = $true
    status = 'RUNNER_SMOKE_PASSED'
    task = $Task
    continueRunId = $Payload.continuePayload.runId
    responseRunId = $ResponsePayload.runId
    responseDispatchStatus = $ResponsePayload.responseDispatcherPayload.status
    closedFlow = $ClosedFlow
} | ConvertTo-Json -Depth 20
