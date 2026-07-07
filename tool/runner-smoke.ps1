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

$ResponseRaw = & $Runner -Task $Task -MaxIterations 1 -AutoFinalAction -AskVerdict revise -AskMessageToChat 'Please revise before continuing.' -ResponseChatId 'smoke-chat-response' -ResponseTargetId 'smoke-target-response' 2>&1
$ResponsePayload = $ResponseRaw | ConvertFrom-Json

if ($ResponsePayload.runnerMode -ne 'auto_final_action') { throw "runner did not use auto final action mode: $($ResponsePayload.runnerMode)" }
if ($ResponsePayload.finalActionSelected -ne 'dispatch_chat_response') { throw "final action did not select response dispatch: $($ResponsePayload.finalActionSelected)" }
if (-not $ResponsePayload.chatResponsePayload) { throw 'chatResponsePayload missing' }
if ($ResponsePayload.chatResponsePayload.shouldSend -ne $true) { throw 'chatResponsePayload shouldSend was not true' }
if (-not $ResponsePayload.chatResponseDispatchContract) { throw 'chatResponseDispatchContract missing' }
if ($ResponsePayload.chatResponseDispatchContract.status -ne 'CHAT_RESPONSE_DISPATCH_CONTRACT_READY') { throw "chat response dispatch contract was not ready: $($ResponsePayload.chatResponseDispatchContract.status)" }
if (-not $ResponsePayload.responseDispatcherPayload) { throw 'responseDispatcherPayload missing' }
if ($ResponsePayload.responseDispatcherPayload.status -ne 'DISPATCHER_BOUNDARY_READY') { throw "response dispatcher boundary was not ready: $($ResponsePayload.responseDispatcherPayload.status)" }
if ($ResponsePayload.responseDispatcherPayload.tool -ne 'console.write.engine.reply.draft_submit') { throw "unexpected response dispatch tool: $($ResponsePayload.responseDispatcherPayload.tool)" }
if ($ResponsePayload.responseDispatcherPayload.realExecution -ne 'disabled') { throw "response dispatch real execution is not disabled: $($ResponsePayload.responseDispatcherPayload.realExecution)" }

$RealBlockedRaw = & $Runner -Task $Task -MaxIterations 1 -AutoFinalAction -ExecuteReal -AskVerdict revise -AskMessageToChat 'Please revise before continuing.' -ResponseChatId 'smoke-chat-response' -ResponseTargetId 'smoke-target-response' 2>&1
$RealBlockedPayload = $RealBlockedRaw | ConvertFrom-Json

if (-not $RealBlockedPayload.responseDispatcherPayload) { throw 'real blocked responseDispatcherPayload missing' }
if ($RealBlockedPayload.responseDispatcherPayload.status -ne 'DISPATCHER_REAL_EXECUTION_ENV_REQUIRED') { throw "real execution did not require env guard: $($RealBlockedPayload.responseDispatcherPayload.status)" }
if ($RealBlockedPayload.responseDispatcherPayload.realExecution -ne 'blocked') { throw "real execution was not blocked: $($RealBlockedPayload.responseDispatcherPayload.realExecution)" }

[pscustomobject]@{
    ok = $true
    status = 'RUNNER_SMOKE_PASSED'
    task = $Task
    continueRunId = $Payload.continuePayload.runId
    responseRunId = $ResponsePayload.runId
    responseDispatchStatus = $ResponsePayload.responseDispatcherPayload.status
} | ConvertTo-Json -Depth 10
