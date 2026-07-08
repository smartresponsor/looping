param(
    [Parameter(Mandatory=$true)][string]$TargetRepo,
    [int]$MaxIterations = 3,
    [string]$Name = 'repo-smoke',
    [string]$CaptureResultPath,
    [switch]$Chain,
    [switch]$EngineExecutor
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Daemon = Join-Path $Root 'tool/runner-daemon.ps1'
$StateDir = Join-Path $Root 'var/runner/state'
$StatePath = Join-Path $StateDir 'latest.json'

if (-not (Test-Path $TargetRepo)) {
    [pscustomobject]@{
        ok = $false
        status = 'RUNNER_REPO_SMOKE_TARGET_NOT_FOUND'
        targetRepo = $TargetRepo
        nextAction = 'provide_existing_target_repo_path'
    } | ConvertTo-Json -Depth 20
    exit 0
}

$Task = "Repo loop test. Name: $Name. Target workspace: $TargetRepo. Goal: inspect repo context only; avoid file changes; avoid commits; stop after $MaxIterations loop steps."
$RunId = 'repo-smoke-' + ([guid]::NewGuid().ToString('N'))
if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir | Out-Null }
$EngineRawCommand = "Run a read-only repository loop smoke for workspace $TargetRepo. Use only safe inspection. Do not edit files. Do not commit. Return strict JSON with ok, status, tool, workspacePath, and summary."
$InitialDispatchContract = if ($EngineExecutor) {
    [ordered]@{ ok = $true; status = 'ENGINE_EXECUTOR_CONTRACT_READY'; stage = 'engine_executor'; tool = 'console.write.browser.chatgpt.chat.create.send'; arguments = [ordered]@{ prompt = $EngineRawCommand; component = $Name; taskId = $Task; promptId = $RunId; activate = $true; confirmSend = $false; allowOverwrite = $false }; mutation = 'write'; confirmationRequired = $false; execution = 'external_console_mcp_required'; nextAction = 'dispatch_engine_executor_send' }
} else {
    [ordered]@{ ok = $true; status = 'REPO_CONTEXT_CAPTURE_CONTRACT_READY'; stage = 'repo_context'; tool = 'console.read_.repo.context.capture'; arguments = [ordered]@{ workspacePath = $TargetRepo }; mutation = 'read_only'; confirmationRequired = $false; execution = 'external_console_mcp_required'; nextAction = 'dispatch_repo_context_capture' }
}
$Seed = [ordered]@{ ok = $true; status = 'RUNNER_STATE_PERSISTED'; schemaVersion = 2; runtimeVersion = '2026.07.runner-loop'; runId = $RunId; taskId = $Task; runnerMode = 'repo_smoke_seed'; finalActionSelected = 'repo_context_capture'; finalActionResult = [ordered]@{ ok = $true; status = 'FINAL_ACTION_RESUME_LATEST'; action = 'resume_latest'; nextAction = 'dispatch_next_from_state' }; nextDispatchContract = $InitialDispatchContract; budget = [ordered]@{ mode = 'steps'; remaining = $MaxIterations; untilRc = $false }; retryPolicy = $null; retryAttempt = 0; recoveryPlan = $null; updatedAt = (Get-Date).ToUniversalTime().ToString('o') }
[pscustomobject]$Seed | ConvertTo-Json -Depth 40 | Set-Content -Path $StatePath -Encoding UTF8
$Raw = & $Daemon -Task $Task -MaxIterations $MaxIterations 2>&1
$Payload = $Raw | ConvertFrom-Json
$Adapter = Join-Path $Root 'tool/runner-transport-adapter.ps1'
$AdapterPayload = $null
$Steps = @()
$Limit = if ($Chain) { $MaxIterations } else { 1 }
for ($Index = 0; $Index -lt $Limit; $Index++) {
    if ($Payload.status -ne 'RUNNER_DAEMON_DISPATCH_READY') { break }
    $Tool = [string]$Payload.dispatchTool
    if ($Tool -eq 'console.read_.repo.context.capture') {
        $CapturePayload = if ($CaptureResultPath -and (Test-Path $CaptureResultPath)) { Get-Content -Raw -Path $CaptureResultPath | ConvertFrom-Json } else { $null }
        $CaptureMode = if ($CapturePayload) { 'external' } else { 'synthetic' }
        $Result = [pscustomobject]@{ ok = $true; tool = $Tool; status = 'REPO_CONTEXT_CAPTURED'; workspacePath = $TargetRepo; mode = 'read_only'; captureMode = $CaptureMode; capturedAt = (Get-Date).ToUniversalTime().ToString('o'); capture = $CapturePayload }
    } elseif ($Tool -eq 'console.read_.repo.workspace.status') {
        $Result = [pscustomobject]@{ ok = $true; tool = $Tool; status = 'REPO_WORKSPACE_STATUS_CAPTURED'; workspacePath = $TargetRepo; workspace_path = $TargetRepo; status_line_count = 0; status_lines = @(); mode = 'read_only'; capturedAt = (Get-Date).ToUniversalTime().ToString('o') }
    } elseif ($Tool -eq 'console.read_.repo.memory.graph.plan') {
        $Result = [pscustomobject]@{ ok = $true; tool = $Tool; status = 'REPO_MEMORY_GRAPH_PLAN_CAPTURED'; workspacePath = $TargetRepo; operation = 'search_graph'; implementationFlow = $true; mode = 'read_only'; capturedAt = (Get-Date).ToUniversalTime().ToString('o') }
    } else { break }
    $Result | ConvertTo-Json -Depth 80 | Set-Content -Path $Payload.expectedResultPath -Encoding UTF8
    $AdapterRaw = & $Adapter -Task $Task -MaxIterations $MaxIterations -PayloadPath $Payload.dispatchPayloadPath -ResultPath $Payload.expectedResultPath 2>&1
    $AdapterPayload = $AdapterRaw | ConvertFrom-Json
    $Steps += [pscustomobject]@{ index = $Index; tool = $Tool; adapterStatus = $AdapterPayload.status; adapterNextAction = $AdapterPayload.nextAction }
    if (-not $Chain -or $AdapterPayload.nextAction -eq 'stop_loop') { break }
    $Raw = & $Daemon -Task $Task -MaxIterations $MaxIterations 2>&1
    $Payload = $Raw | ConvertFrom-Json
}

$ToolName = if ($Payload.toolCall) { [string]$Payload.toolCall.name } else { $null }
$ArgumentsText = if ($Payload.toolCall) { ($Payload.toolCall.arguments | ConvertTo-Json -Depth 20 -Compress) } else { '' }
$TaskText = if ($Payload.handoff) { [string]$Payload.handoff.task } else { [string]$Payload.requestedTaskId }
$RuntimeLeak = ($TaskText -match 'runtime-smoke') -or ($ArgumentsText -match 'runtime-smoke') -or ([string]$Payload.dispatchPayloadPath -match 'runtime-smoke')
$TargetMissing = ($TaskText -notmatch [regex]::Escape($TargetRepo))

$Status = 'RUNNER_REPO_SMOKE_READY'
$Ok = $true
$NextAction = 'feed_executor_result_or_continue_boundary'
if ($Payload.status -eq 'RUNNER_DAEMON_STATE_TASK_MISMATCH') {
    $Status = 'RUNNER_REPO_SMOKE_TASK_MISMATCH'
    $Ok = $false
    $NextAction = 'rerun_with_reset_state'
} elseif ($RuntimeLeak) {
    $Status = 'RUNNER_REPO_SMOKE_RUNTIME_LEAK_DETECTED'
    $Ok = $false
    $NextAction = 'inspect_runner_state_reset'
} elseif ($TargetMissing) {
    $Status = 'RUNNER_REPO_SMOKE_TARGET_NOT_BOUND'
    $Ok = $false
    $NextAction = 'inspect_initial_runner_task_binding'
} elseif ($Payload.status -notin @('RUNNER_DAEMON_DISPATCH_READY','RUNNER_DAEMON_STARTED','RUNNER_DAEMON_WAITING','RUNNER_DAEMON_TERMINAL')) {
    $Status = 'RUNNER_REPO_SMOKE_UNEXPECTED_DAEMON_STATUS'
    $Ok = $false
    $NextAction = 'inspect_daemon_payload'
}

[pscustomobject]@{
    ok = $Ok
    status = $Status
    targetRepo = $TargetRepo
    maxIterations = $MaxIterations
    daemonStatus = $Payload.status
    dispatchTool = if ($Payload.dispatchTool) { [string]$Payload.dispatchTool } else { $ToolName }
    runtimeLeakDetected = $RuntimeLeak
    targetBound = (-not $TargetMissing)
    handoffPath = $Payload.handoffPath
    expectedResultPath = $Payload.expectedResultPath
    adapterStatus = if ($AdapterPayload) { [string]$AdapterPayload.status } else { $null }
    adapterNextAction = if ($AdapterPayload) { [string]$AdapterPayload.nextAction } else { $null }
    autoFed = [bool]$AdapterPayload
    chain = [bool]$Chain
    engineExecutor = [bool]$EngineExecutor
    stepCount = @($Steps).Count
    steps = $Steps
    tools = @($Steps | ForEach-Object { $_.tool })
    captureMode = if ($CaptureResultPath) { 'external_or_requested' } else { 'synthetic' }
    nextAction = if ($Chain -and $AdapterPayload -and $AdapterPayload.nextAction -eq 'stop_loop') { 'repo_chain_smoke_completed' } elseif ($AdapterPayload) { 'repo_context_capture_auto_fed' } else { $NextAction }
} | ConvertTo-Json -Depth 40
