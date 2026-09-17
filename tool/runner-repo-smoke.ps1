param(
    [Parameter(Mandatory=$true)][string]$TargetRepo,
    [int]$MaxIterations = 3,
    [string]$Name = 'repo-smoke',
    [string]$CaptureResultPath,
    [switch]$Chain,
    [switch]$EngineExecutor,
    [string]$RawCommand,
    [string]$ContinueCommand,
    [ValidateSet('raw','enriched')][string]$PromptMode = 'raw',
    [ValidateSet('raw','enriched')][string]$InitialPromptMode = '',
    [ValidateSet('raw','enriched')][string]$ContinuePromptMode = '',
    [ValidateSet('gpt-5.5')][string]$InitialReasoningModel = 'gpt-5.5',
    [ValidateSet('gpt-5.5')][string]$ContinueReasoningModel = 'gpt-5.5',
    [ValidateSet('medium','high')][string]$InitialReasoningEffort = 'medium',
    [ValidateSet('medium','high')][string]$ContinueReasoningEffort = 'medium',
    [ValidateSet('observe','require','set_if_needed','set_and_require')][string]$ReasoningEnforcement = 'observe',
    [string]$AdoptChatId
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Daemon = Join-Path $Root 'tool/runner-daemon.ps1'
$Adapter = Join-Path $Root 'tool/runner-transport-adapter.ps1'
$Bridge = Join-Path $Root 'tool/runner-console-mcp-bridge.ps1'
$StateDir = Join-Path $Root 'var/runner/state'
$StatePath = Join-Path $StateDir 'latest.json'

function Read-JsonFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    Get-Content -Raw -Path $Path | ConvertFrom-Json
}

function Get-FirstValue {
    param($Payload, [string[]]$Names)
    foreach ($Name in $Names) {
        if ($Payload -and $Payload.PSObject.Properties.Name -contains $Name -and $null -ne $Payload.$Name -and [string]$Payload.$Name -ne '') {
            return $Payload.$Name
        }
    }
    return $null
}

function Get-Submitted {
    param($Payload)
    if (-not $Payload) { return $false }
    if ($Payload.submitted -eq $true) { return $true }
    if ($Payload.submitted -and $Payload.submitted.submitted -eq $true) { return $true }
    if ($Payload.submitted_at) { return $true }
    if ($Payload.submitted_count -and [int]$Payload.submitted_count -gt 0) { return $true }
    if ($Payload.assistant_hash -or $Payload.assistant_captured_count -and [int]$Payload.assistant_captured_count -gt 0) { return $true }
    if ($Payload.execution_completed_at) { return $true }
    if ($Payload.status -in @('completed','ENGINE_CYCLE_RUN_N_COMPLETE','RUNNER_REPO_SMOKE_LOOP_COMPLETED')) { return $true }
    if ($Payload.final_status -in @('completed','ENGINE_CYCLE_RUN_N_COMPLETE','RUNNER_REPO_SMOKE_LOOP_COMPLETED')) { return $true }
    if ($Payload.cmcp_go_trace -and $Payload.cmcp_go_trace.submitted_status -eq 'BROWSER_SESSION_SUBMITTED') { return $true }
    return $false
}

function Get-RemainingBudget {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $State = Read-JsonFile -Path $Path
    if ($State.budget -and $null -ne $State.budget.remaining) { return [int]$State.budget.remaining }
    return $null
}

function New-EngineDispatchContract {
    param([string]$RawCommand)
    [ordered]@{
        ok = $true
        status = 'ENGINE_EXECUTOR_CONTRACT_READY'
        stage = 'engine_executor'
        tool = 'console.write.browser.session.cmcp.go'
        arguments = [ordered]@{
            rawCommand = $RawCommand
            workspacePath = $TargetRepo
            componentName = $Name
            maxAutoIterations = $MaxIterations
            activate = $true
            confirmGo = $true
            allowOverwrite = $true
            promptMode = $PromptMode
            executorMode = 'browser'
            manageLoop = $false
            initialReasoningModel = $InitialReasoningModel
            continuationReasoningModel = $ContinueReasoningModel
            initialReasoningEffort = $InitialReasoningEffort
            continuationReasoningEffort = $ContinueReasoningEffort
            reasoningEnforcement = $ReasoningEnforcement
            timeoutMs = 30000
        }
        mutation = 'write'
        confirmationRequired = $false
        execution = 'external_console_mcp_required'
        nextAction = 'dispatch_engine_executor_send'
    }
}

if (-not (Test-Path $TargetRepo)) {
    [pscustomobject]@{
        ok = $false
        status = 'RUNNER_REPO_SMOKE_TARGET_NOT_FOUND'
        targetRepo = $TargetRepo
        maxIterations = $MaxIterations
        stepCount = 0
        tools = @()
        decisionStagesUsed = @()
        chatId = $null
        targetId = $null
        submitted = $false
        adapterStatus = $null
        adapterNextAction = $null
        finalStatus = 'target_not_found'
        runnerStatePath = $StatePath
        nextAction = 'provide_existing_target_repo_path'
    } | ConvertTo-Json -Depth 40
    exit 0
}

if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir | Out-Null }

$Task = "Repo loop test. Name: $Name. Target workspace: $TargetRepo. Goal: inspect repo context only; avoid file changes; avoid commits; stop after $MaxIterations loop steps."
$RunId = 'repo-smoke-' + ([guid]::NewGuid().ToString('N'))
$EngineRawCommand = if (-not [string]::IsNullOrWhiteSpace($RawCommand)) { $RawCommand } else { "cmcp $Name M$MaxIterations" }
$InitialDispatchContract = if ($EngineExecutor) {
    New-EngineDispatchContract -RawCommand $EngineRawCommand
} else {
    [ordered]@{
        ok = $true
        status = 'REPO_CONTEXT_CAPTURE_CONTRACT_READY'
        stage = 'repo_context'
        tool = 'console.read_.repo.context.capture'
        arguments = [ordered]@{ workspacePath = $TargetRepo }
        mutation = 'read_only'
        confirmationRequired = $false
        execution = 'external_console_mcp_required'
        nextAction = 'dispatch_repo_context_capture'
    }
}

$Seed = [ordered]@{
    ok = $true
    status = 'RUNNER_STATE_PERSISTED'
    schemaVersion = 2
    runtimeVersion = '2026.07.runner-loop'
    runId = $RunId
    taskId = $Task
    runnerMode = 'repo_smoke_seed'
    finalActionSelected = 'seed_runner_state'
    finalActionResult = [ordered]@{ ok = $true; status = 'FINAL_ACTION_RESUME_LATEST'; action = 'resume_latest'; nextAction = 'dispatch_next_from_state' }
    nextDispatchContract = $InitialDispatchContract
    budget = [ordered]@{ mode = 'steps'; remaining = $MaxIterations; untilRc = $false }
    retryPolicy = $null
    retryAttempt = 0
    recoveryPlan = $null
    updatedAt = (Get-Date).ToUniversalTime().ToString('o')
}
[pscustomobject]$Seed | ConvertTo-Json -Depth 60 | Set-Content -Path $StatePath -Encoding UTF8

$Limit = 1
$Steps = @()
$Tools = @()
$DecisionStages = @('runner_state_seed')
$LastPayload = $null
$LastAdapter = $null
$LastResult = $null
$ChatId = $null
$TargetId = $null
$Submitted = $false
$FinalStatus = 'not_started'

for ($Index = 0; $Index -lt $Limit; $Index++) {
    $Raw = & $Daemon -Task $Task -MaxIterations $MaxIterations 2>&1
    $Payload = $Raw | ConvertFrom-Json
    $LastPayload = $Payload

    if ($Payload.status -ne 'RUNNER_DAEMON_DISPATCH_READY') {
        $FinalStatus = [string]$Payload.status
        break
    }

    $Tool = [string]$Payload.dispatchTool
    $DispatchStatus = if ($Payload.dispatchBoundary) { [string](@($Payload.dispatchBoundary)[0].status) } else { $null }
    $DecisionStages += @('runner-daemon', 'runner-dispatcher')
    $Tools += $Tool

    if ($EngineExecutor -and $Tool -eq 'console.write.browser.chatgpt.chat.create.send') {
        throw 'legacy fallback tool is not allowed in engine executor chain'
    }
    if ($EngineExecutor -and $Chain -and $Tool -ne 'console.write.browser.session.cmcp.go' -and $Tool -ne 'console.write.browser.session.title.prefix' -and $Tool -notin @('console.read_.repo.context.capture','console.read_.repo.workspace.status','console.read_.repo.memory.graph.plan','console.write.engine.task.enqueue','console.write.engine.worker.tick','console.write.engine.chat.bind','console.write.engine.answer.capture','console.write.engine.gateway.decide','console.write.engine.reply.draft','console.write.engine.reply.submit')) {
        throw "selected tool is not supported by runner bridge: $Tool"
    }

    $ExecuteStatus = 'not_started'
    $BridgePayload = $null
    if ($Tool -eq 'console.read_.repo.context.capture' -and $CaptureResultPath -and (Test-Path $CaptureResultPath) -and -not $EngineExecutor) {
        Copy-Item -Path $CaptureResultPath -Destination $Payload.expectedResultPath -Force
        $Capture = Read-JsonFile -Path $Payload.expectedResultPath
        if (-not $Capture.tool) { $Capture | Add-Member -NotePropertyName tool -NotePropertyValue $Tool -Force }
        if ($null -eq $Capture.ok) { $Capture | Add-Member -NotePropertyName ok -NotePropertyValue $true -Force }
        if (-not $Capture.status) { $Capture | Add-Member -NotePropertyName status -NotePropertyValue 'REPO_CONTEXT_CAPTURED' -Force }
        $Capture | ConvertTo-Json -Depth 80 | Set-Content -Path $Payload.expectedResultPath -Encoding UTF8
        $LastResult = $Capture
        $ExecuteStatus = 'EXTERNAL_CAPTURE_RESULT_COPIED'
    } else {
        $BridgeRaw = & $Bridge -PayloadPath $Payload.dispatchPayloadPath -ResultPath $Payload.expectedResultPath 2>&1
        $BridgePayload = $BridgeRaw | ConvertFrom-Json
        $ExecuteStatus = [string]$BridgePayload.status
        $LastResult = Read-JsonFile -Path $Payload.expectedResultPath
    }

    $Submitted = $Submitted -or (Get-Submitted -Payload $LastResult)
    $MaybeChatId = Get-FirstValue -Payload $LastResult -Names @('chatId','chat_id')
    if (-not $MaybeChatId -and $LastResult.cmcp_go_trace) { $MaybeChatId = $LastResult.cmcp_go_trace.opened_chat_id }
    if ($MaybeChatId) { $ChatId = [string]$MaybeChatId }
    $MaybeTargetId = Get-FirstValue -Payload $LastResult -Names @('targetId','target_id')
    if (-not $MaybeTargetId -and $LastResult.cmcp_go_trace) { $MaybeTargetId = $LastResult.cmcp_go_trace.opened_target_id }
    if ($MaybeTargetId) { $TargetId = [string]$MaybeTargetId }

    $AdapterRaw = & $Adapter -Task $Task -MaxIterations $MaxIterations -PayloadPath $Payload.dispatchPayloadPath -ResultPath $Payload.expectedResultPath 2>&1
    $AdapterPayload = $AdapterRaw | ConvertFrom-Json
    $LastAdapter = $AdapterPayload
    $DecisionStages += @('runner-transport-adapter', 'runner-adapter')
    $RemainingBudget = Get-RemainingBudget -Path $StatePath

    $Step = [pscustomobject]@{
        iteration = $Index + 1
        selectedTool = $Tool
        dispatchStatus = $DispatchStatus
        executeStatus = $ExecuteStatus
        submitted = [bool]$Submitted
        chatId = $ChatId
        targetId = $TargetId
        adapterStatus = [string]$AdapterPayload.status
        adapterNextAction = [string]$AdapterPayload.nextAction
        remainingBudget = $RemainingBudget
    }
    $Steps += $Step
    Write-Host ("progress " + ($Step | ConvertTo-Json -Depth 20 -Compress))

    if ([string]$AdapterPayload.status -ne 'RUNNER_TRANSPORT_ADAPTER_FED') {
        $FinalStatus = if ($LastResult -and $LastResult.status) { [string]$LastResult.status } else { [string]$AdapterPayload.status }
        break
    }

    if (-not $Chain -or [string]$AdapterPayload.nextAction -eq 'stop_loop') {
        $FinalStatus = if ($AdapterPayload.feed -and $AdapterPayload.feed.finalActionResult) { [string]$AdapterPayload.feed.finalActionResult.status } else { [string]$AdapterPayload.nextAction }
        break
    }

    $FinalStatus = if ($AdapterPayload.feed -and $AdapterPayload.feed.finalActionResult) { [string]$AdapterPayload.feed.finalActionResult.status } else { [string]$AdapterPayload.status }
}

$State = if (Test-Path $StatePath) { Read-JsonFile -Path $StatePath } else { $null }
if ($LastAdapter -and [string]$LastAdapter.status -ne 'RUNNER_TRANSPORT_ADAPTER_FED' -and $LastResult -and $LastResult.status) {
    $FinalStatus = [string]$LastResult.status
} elseif ($State -and $State.finalActionResult -and $State.finalActionResult.status) {
    $FinalStatus = [string]$State.finalActionResult.status
}

$UniqueDecisionStages = @($DecisionStages | Select-Object -Unique)
$FallbackUsed = @($Tools | Where-Object { $_ -eq 'console.write.browser.chatgpt.chat.create.send' }).Count -gt 0
$SyntheticUsed = $false
$Ok = (-not $FallbackUsed) -and (-not ($EngineExecutor -and $Chain -and $SyntheticUsed)) -and (@($Steps).Count -eq $Limit)
if ($EngineExecutor -and $Chain) {
    $Ok = $Ok -and $Submitted -and (@($Tools | Where-Object { $_ -eq 'console.write.browser.session.cmcp.go' }).Count -ge 1)
}

$BlockedStage = Get-FirstValue -Payload $LastResult -Names @('blockedStage','blocked_stage','executionBlockedStage','execution_blocked_stage')
$BlockedReason = Get-FirstValue -Payload $LastResult -Names @('blockedReason','blocked_reason','executionBlockedReason','execution_blocked_reason')
$ResultNextAction = Get-FirstValue -Payload $LastResult -Names @('nextAction','next_action')
$EffectiveNextAction = if ($Ok) {
    'repo_chain_smoke_completed'
} elseif ($FallbackUsed) {
    'remove_legacy_fallback_dispatch'
} elseif ($ResultNextAction) {
    [string]$ResultNextAction
} elseif ($EngineExecutor -and $Chain -and -not $Submitted) {
    'inspect_browser_executor_submit_result'
} else {
    'inspect_runner_loop_progress'
}

[pscustomobject]@{
    ok = [bool]$Ok
    status = if ($Ok) { 'RUNNER_REPO_SMOKE_LOOP_COMPLETED' } else { 'RUNNER_REPO_SMOKE_LOOP_FAILED' }
    targetRepo = $TargetRepo
    maxIterations = $MaxIterations
    stepCount = @($Steps).Count
    tools = @($Tools)
    decisionStagesUsed = $UniqueDecisionStages
    chatId = $ChatId
    targetId = $TargetId
    submitted = [bool]$Submitted
    adapterStatus = if ($LastAdapter) { [string]$LastAdapter.status } else { $null }
    adapterNextAction = if ($LastAdapter) { [string]$LastAdapter.nextAction } else { $null }
    finalStatus = $FinalStatus
    blockedStage = if ($BlockedStage) { [string]$BlockedStage } else { $null }
    blockedReason = if ($BlockedReason) { [string]$BlockedReason } else { $null }
    runnerStatePath = $StatePath
    nextAction = $EffectiveNextAction
} | ConvertTo-Json -Depth 80
