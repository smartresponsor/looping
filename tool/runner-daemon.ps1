param(
    [Parameter(Mandatory=$true)][string]$Task,
    [int]$MaxIterations = 1,
    [int]$RetryAttempt = 0,
    [switch]$UntilRc,
    [switch]$NextDispatchExecuteReal
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Runner = Join-Path $Root 'tool/runner-adapter.ps1'
$StatePath = Join-Path $Root 'var/runner/state/latest.json'

if (-not (Test-Path $StatePath)) {
    $StartArgs = @('-Task', $Task, '-MaxIterations', $MaxIterations)
    if ($UntilRc) { $StartArgs += '-UntilRc' }
    if ($NextDispatchExecuteReal) { $StartArgs += '-NextDispatchExecuteReal' }
    $StartRaw = & $Runner @StartArgs 2>&1
    $StartPayload = $StartRaw | ConvertFrom-Json
    [pscustomobject]@{
        ok = $true
        status = 'RUNNER_DAEMON_STARTED'
        action = 'dispatch_next_from_started_state'
        statePath = $StartPayload.runnerStatePath
        nextDispatchStatus = $StartPayload.nextDispatchStatus
        nextDispatchPayload = $StartPayload.nextDispatchPayload
        nextDispatchBoundary = $StartPayload.nextDispatchBoundary
        nextAction = 'invoke_next_dispatch_payload'
    } | ConvertTo-Json -Depth 40
    exit 0
}

$ResumeArgs = @('-Task', $Task, '-MaxIterations', $MaxIterations, '-RetryAttempt', $RetryAttempt, '-ResumeLatest')
if ($UntilRc) { $ResumeArgs += '-UntilRc' }
if ($NextDispatchExecuteReal) { $ResumeArgs += '-NextDispatchExecuteReal' }
$ResumeRaw = & $Runner @ResumeArgs 2>&1
$Payload = $ResumeRaw | ConvertFrom-Json

if ($Payload.finalActionResult -and [string]$Payload.finalActionResult.nextAction -in @('stop_loop', 'stop_hard')) {
    [pscustomobject]@{
        ok = $true
        status = 'RUNNER_DAEMON_TERMINAL'
        action = [string]$Payload.finalActionResult.action
        statePath = $Payload.runnerStatePath
        finalActionResult = $Payload.finalActionResult
        retryPolicy = $Payload.retryPolicy
        nextAction = 'stop'
    } | ConvertTo-Json -Depth 40
    exit 0
}

if (-not $Payload.nextDispatchPayload) {
    [pscustomobject]@{
        ok = $true
        status = 'RUNNER_DAEMON_WAITING'
        action = if ($Payload.finalActionResult) { [string]$Payload.finalActionResult.action } else { 'wait' }
        statePath = $Payload.runnerStatePath
        finalActionResult = $Payload.finalActionResult
        retryPolicy = $Payload.retryPolicy
        nextAction = 'wait_or_review'
    } | ConvertTo-Json -Depth 40
    exit 0
}

$FirstPayload = @($Payload.nextDispatchPayload)[0]
$FirstBoundary = @($Payload.nextDispatchBoundary)[0]
$DispatchPayload = Get-Content -Raw -Path $FirstPayload.path | ConvertFrom-Json
$ToolCall = [ordered]@{
    name = $DispatchPayload.runnerExecutionPlan.tool
    arguments = $DispatchPayload.runnerExecutionPlan.arguments
}
$ExpectedResultPath = Join-Path (Split-Path -Parent $FirstPayload.path) ((Split-Path -Leaf $FirstPayload.path) + '.result.json')
$AdapterCommand = @(
    'tool/runner-transport-adapter.ps1',
    '-Task',
    $Task,
    '-MaxIterations',
    [string]$MaxIterations,
    '-RetryAttempt',
    [string]$RetryAttempt,
    '-PayloadPath',
    $FirstPayload.path,
    '-ResultPath',
    $ExpectedResultPath
)
if ($UntilRc) { $AdapterCommand += '-UntilRc' }
$HandoffPath = $FirstPayload.path + '.handoff.json'
$Handoff = [ordered]@{
    ok = $true
    status = 'RUNNER_EXECUTOR_HANDOFF_READY'
    task = $Task
    statePath = $Payload.runnerStatePath
    dispatchPayloadPath = $FirstPayload.path
    dispatchTool = $FirstPayload.tool
    toolCall = ([pscustomobject]$ToolCall)
    expectedResultPath = $ExpectedResultPath
    adapterCommand = $AdapterCommand
    nextAction = 'invoke_tool_call_write_result_then_run_adapter'
}
[pscustomobject]$Handoff | ConvertTo-Json -Depth 40 | Set-Content -Path $HandoffPath -Encoding UTF8
[pscustomobject]@{
    ok = $true
    status = 'RUNNER_DAEMON_DISPATCH_READY'
    action = 'invoke_next_dispatch_payload'
    statePath = $Payload.runnerStatePath
    schemaVersion = if ($Payload.resumeState) { $Payload.resumeState.schemaVersion } else { $null }
    runtimeVersion = if ($Payload.resumeState) { $Payload.resumeState.runtimeVersion } else { $null }
    dispatchPayloadPath = $FirstPayload.path
    dispatchTool = $FirstPayload.tool
    dispatchBoundary = $FirstBoundary
    toolCall = ([pscustomobject]$ToolCall)
    expectedResultPath = $ExpectedResultPath
    adapterCommand = $AdapterCommand
    handoffPath = $HandoffPath
    handoff = ([pscustomobject]$Handoff)
    nextDispatchPayload = $Payload.nextDispatchPayload
    nextDispatchBoundary = $Payload.nextDispatchBoundary
    nextAction = 'invoke_console_mcp_tool_call_then_feed_transport_result'
} | ConvertTo-Json -Depth 40
