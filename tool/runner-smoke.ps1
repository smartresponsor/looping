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

[pscustomobject]@{
    ok = $true
    status = 'RUNNER_SMOKE_PASSED'
    task = $Task
    continueRunId = $Payload.continuePayload.runId
    responseRunId = $ResponsePayload.runId
    responseDispatchStatus = $ResponsePayload.responseDispatcherPayload.status
} | ConvertTo-Json -Depth 10
