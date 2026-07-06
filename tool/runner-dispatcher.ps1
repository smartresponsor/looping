param(
    [Parameter(Mandatory=$true)][string]$PayloadPath,
    [switch]$Simulate,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $PayloadPath)) { throw "payload file not found: $PayloadPath" }

$Payload = Get-Content -Raw -Path $PayloadPath | ConvertFrom-Json
$Plan = $Payload.runnerExecutionPlan

if (-not $Plan) { throw 'runnerExecutionPlan missing' }
if ($Plan.ok -ne $true) { throw "runnerExecutionPlan not ready: $($Plan.status)" }

$AllowedTools = @{
    'console.read_.browser.chatgpt.entrypoint.plan' = 'read_only'
    'console.write.engine.task.enqueue' = 'write'
    'console.write.engine.worker.tick' = 'write'
    'console.write.engine.chat.bind' = 'write'
    'console.write.engine.answer.capture' = 'write'
    'console.write.engine.gateway.decide' = 'write'
}

if (-not $AllowedTools.ContainsKey([string]$Plan.tool)) { throw "dispatcher tool not allowed: $($Plan.tool)" }
if ($Plan.allowedMode -ne $AllowedTools[[string]$Plan.tool]) { throw "dispatcher allowedMode mismatch: $($Plan.allowedMode)" }

$Boundary = [ordered]@{
    ok = $true
    status = 'DISPATCHER_BOUNDARY_READY'
    payloadPath = $PayloadPath
    tool = $Plan.tool
    arguments = $Plan.arguments
    allowedMode = $Plan.allowedMode
    mutation = $Plan.mutation
    confirmationGate = $Plan.confirmationGate
    dryRunOnly = $true
    realExecution = 'disabled'
    nextAction = 'dry_run_or_simulate_only'
}

if ($DryRun) {
    [pscustomobject]$Boundary | ConvertTo-Json -Depth 30
    exit 0
}

if (-not $Simulate) {
    [pscustomobject]@{
        ok = $false
        status = 'DISPATCHER_DRY_RUN_REQUIRED'
        tool = $Plan.tool
        arguments = $Plan.arguments
        allowedMode = $Plan.allowedMode
        mutation = $Plan.mutation
        confirmationGate = $Plan.confirmationGate
    } | ConvertTo-Json -Depth 30
    exit 0
}

[pscustomobject]@{
    ok = $true
    status = 'DISPATCHER_SIMULATED_RESULT'
    tool = $Plan.tool
    taskId = if ($Payload.taskId) { 'sim-' + $Payload.taskId } else { $null }
    chatId = if ($Payload.runId) { 'sim-chat-' + $Payload.runId } else { $null }
    targetId = if ($Payload.runId) { 'sim-target-' + $Payload.runId } else { $null }
    raw = @{ simulated = $true; allowedMode = $Plan.allowedMode }
} | ConvertTo-Json -Depth 30
