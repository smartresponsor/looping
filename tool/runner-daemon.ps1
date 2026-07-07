param(
    [Parameter(Mandatory=$true)][string]$Task,
    [int]$MaxIterations = 1,
    [int]$RetryAttempt = 0,
    [switch]$UntilRc,
    [switch]$NextDispatchExecuteReal
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$RunnerLockPath = $null
trap {
    if ($RunnerLockPath -and (Test-Path $RunnerLockPath)) { Remove-Item -Path $RunnerLockPath -Force }
    throw $_
}
$Runner = Join-Path $Root 'tool/runner-adapter.ps1'
$StatePath = Join-Path $Root 'var/runner/state/latest.json'

function Enter-RunnerLock {
    param([Parameter(Mandatory=$true)][string]$Owner)
    $LockDir = Join-Path $Root 'var/runner/lock'
    if (-not (Test-Path $LockDir)) { New-Item -ItemType Directory -Path $LockDir | Out-Null }
    $LockPath = Join-Path $LockDir 'runner.lock'
    if (Test-Path $LockPath) {
        $Lock = Get-Content -Raw -Path $LockPath | ConvertFrom-Json
        $AgeMinutes = ((Get-Date).ToUniversalTime() - ([datetime]$Lock.acquiredAt)).TotalMinutes
        if ($AgeMinutes -lt 30) {
            [pscustomobject]@{ ok = $false; status = 'RUNNER_LOCK_BUSY'; lockPath = $LockPath; owner = $Lock.owner; acquiredAt = $Lock.acquiredAt; nextAction = 'retry_later' } | ConvertTo-Json -Depth 20
            exit 0
        }
    }
    [pscustomobject]@{ owner = $Owner; pid = $PID; acquiredAt = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Depth 20 | Set-Content -Path $LockPath -Encoding UTF8
    return $LockPath
}

function Exit-RunnerLock {
    param([string]$LockPath)
    if ($LockPath -and (Test-Path $LockPath)) { Remove-Item -Path $LockPath -Force }
}

function Write-RunnerJournalEvent {
    param([Parameter(Mandatory=$true)]$Event)
    $JournalDir = Join-Path $Root 'var/runner/journal'
    if (-not (Test-Path $JournalDir)) { New-Item -ItemType Directory -Path $JournalDir | Out-Null }
    $JournalPath = Join-Path $JournalDir 'runner.ndjson'
    $Event | Add-Member -NotePropertyName writtenAt -NotePropertyValue (Get-Date).ToUniversalTime().ToString('o') -Force
    ([pscustomobject]$Event | ConvertTo-Json -Depth 40 -Compress) + "`n" | Add-Content -Path $JournalPath -Encoding UTF8
    return $JournalPath
}

$RunnerLockPath = Enter-RunnerLock -Owner 'runner-daemon'

if (-not (Test-Path $StatePath)) {
    $StartArgs = @('-Task', $Task, '-MaxIterations', $MaxIterations)
    if ($UntilRc) { $StartArgs += '-UntilRc' }
    if ($NextDispatchExecuteReal) { $StartArgs += '-NextDispatchExecuteReal' }
    $StartRaw = & $Runner @StartArgs 2>&1
    $StartPayload = $StartRaw | ConvertFrom-Json
    Exit-RunnerLock -LockPath $RunnerLockPath
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
    Exit-RunnerLock -LockPath $RunnerLockPath
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
    Exit-RunnerLock -LockPath $RunnerLockPath
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
$Runbook = @(
    [ordered]@{ step = 1; action = 'invoke_tool_call'; toolCall = ([pscustomobject]$ToolCall); outputPath = $ExpectedResultPath }
    [ordered]@{ step = 2; action = 'write_executor_result'; path = $ExpectedResultPath; requiredFields = @('ok', 'tool', 'status') }
    [ordered]@{ step = 3; action = 'run_transport_adapter'; command = $AdapterCommand }
    [ordered]@{ step = 4; action = 'run_daemon_again'; command = @('tool/runner-daemon.ps1', '-Task', $Task, '-MaxIterations', [string]$MaxIterations) }
)
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
    runbook = $Runbook
    nextAction = 'invoke_tool_call_write_result_then_run_adapter'
}
[pscustomobject]$Handoff | ConvertTo-Json -Depth 40 | Set-Content -Path $HandoffPath -Encoding UTF8
$JournalPath = Write-RunnerJournalEvent ([ordered]@{ component = 'runner-daemon'; status = 'RUNNER_DAEMON_DISPATCH_READY'; action = 'handoff_ready'; task = $Task; dispatchTool = $FirstPayload.tool; dispatchPayloadPath = $FirstPayload.path; handoffPath = $HandoffPath; expectedResultPath = $ExpectedResultPath })
$CleanupRaw = & (Join-Path $Root 'tool/runner-cleanup.ps1') -KeepFiles 200 -KeepJournalLines 2000 2>&1
$CleanupPayload = $CleanupRaw | ConvertFrom-Json
Exit-RunnerLock -LockPath $RunnerLockPath
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
    journalPath = $JournalPath
    nextDispatchPayload = $Payload.nextDispatchPayload
    nextDispatchBoundary = $Payload.nextDispatchBoundary
    nextAction = 'invoke_console_mcp_tool_call_then_feed_transport_result'
} | ConvertTo-Json -Depth 40
