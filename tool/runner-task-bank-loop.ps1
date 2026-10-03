param(
    [Parameter(Mandatory=$true)][string]$TargetRepo,
    [Parameter(Mandatory=$true)][int]$MaxIterations,
    [Parameter(Mandatory=$true)][string]$Name,
    [string]$InitialPrompt,
    [string]$ContinuePrompt,
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
$TransportAdapter = Join-Path $Root 'tool/runner-transport-adapter.ps1'
$RunnerAdapter = Join-Path $Root 'tool/runner-adapter.ps1'
$Bridge = Join-Path $Root 'tool/runner-console-mcp-bridge.ps1'
$RunnerStateDir = Join-Path $Root 'var/runner/state'
$RunnerStatePath = Join-Path $RunnerStateDir 'latest.json'
$TaskBankRoot = Join-Path $Root 'var/runner/task-bank'
$TaskDir = Join-Path $TaskBankRoot 'tasks'
$JournalDir = Join-Path $TaskBankRoot 'journal'
$AnswerDir = Join-Path $TaskBankRoot 'answers'
$BridgeDir = Join-Path $TaskBankRoot 'bridge'
$AcceptanceDir = Join-Path $TaskBankRoot 'acceptance'
$ParityDir = Join-Path $TaskBankRoot 'parity'
$ChatBankRoot = Join-Path $Root 'var/runner/chat-bank'
$ChatDir = Join-Path $ChatBankRoot 'chats'

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function Read-JsonFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    Get-Content -Raw -Path $Path | ConvertFrom-Json
}

function Write-JsonFile {
    param([Parameter(Mandatory=$true)]$Value, [Parameter(Mandatory=$true)][string]$Path)
    $Value | ConvertTo-Json -Depth 100 | Set-Content -Path $Path -Encoding UTF8
}

function Get-IsoNow { (Get-Date).ToUniversalTime().ToString('o') }

function Get-Hash {
    param([string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $Hash = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    ([System.BitConverter]::ToString($Hash)).Replace('-', '').ToLowerInvariant()
}

function Get-OptionalProperty {
    param($InputObject, [string]$Name)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject.PSObject.Properties.Name -contains $Name) { return $InputObject.$Name }
    return $null
}

function Get-FirstValue {
    param([object[]]$Values)
    foreach ($Value in $Values) {
        if ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)) {
            return [string]$Value
        }
    }
    return $null
}

function Append-Journal {
    param([string]$TaskId, [string]$Event, $Data)
    $Path = Join-Path $JournalDir ($TaskId + '.ndjson')
    $Line = [ordered]@{ at = Get-IsoNow; event = $Event; data = $Data }
    ($Line | ConvertTo-Json -Depth 80 -Compress) | Add-Content -Path $Path -Encoding UTF8
}

function Normalize-ChatId {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $Trimmed = $Value.Trim()
    if ($Trimmed -match 'https://chatgpt\.com/c/([0-9a-fA-F-]{36})') { return $Matches[1].ToLowerInvariant() }
    if ($Trimmed -match '^/c/([0-9a-fA-F-]{36})$') { return $Matches[1].ToLowerInvariant() }
    if ($Trimmed -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { return $Trimmed.ToLowerInvariant() }
    throw "invalid AdoptChatId: $Value"
}

function New-CmcpDispatchContract {
    param([string]$RawCommand, [string]$ChatId, [string]$EffectivePromptMode)
    $Arguments = [ordered]@{
        rawCommand = $RawCommand
        workspacePath = $TargetRepo
        componentName = $Name
        maxAutoIterations = $MaxIterations
        activate = $true
        confirmGo = $true
        allowOverwrite = $false
        promptMode = $EffectivePromptMode
        executorMode = 'browser'
        manageLoop = $false
        initialReasoningModel = $InitialReasoningModel
        continuationReasoningModel = $ContinueReasoningModel
        initialReasoningEffort = $InitialReasoningEffort
        continuationReasoningEffort = $ContinueReasoningEffort
        reasoningEnforcement = $ReasoningEnforcement
        timeoutMs = 30000
    }
    if ($ChatId) { $Arguments.url = "https://chatgpt.com/c/$ChatId" }
    [ordered]@{
        ok = $true
        status = 'TASK_BANK_UI_INTERACTION_CONTRACT_READY'
        stage = 'ui_interaction_submit'
        tool = 'write.browser.session.cmcp.go'
        arguments = $Arguments
        mutation = 'write'
        confirmationRequired = $false
        execution = 'external_console_mcp_required'
        nextAction = 'dispatch_ui_interaction_submit'
    }
}

function Get-SubmitChatId {
    param($SubmitResult)

    $Trace = Get-OptionalProperty -InputObject $SubmitResult -Name 'cmcp_go_trace'
    $Submitted = Get-OptionalProperty -InputObject $SubmitResult -Name 'submitted'
    return Get-FirstValue -Values @(
        (Get-OptionalProperty -InputObject $SubmitResult -Name 'chatId'),
        (Get-OptionalProperty -InputObject $SubmitResult -Name 'chat_id'),
        (Get-OptionalProperty -InputObject $SubmitResult -Name 'opened_chat_id'),
        (Get-OptionalProperty -InputObject $Trace -Name 'opened_chat_id'),
        (Get-OptionalProperty -InputObject $Submitted -Name 'chatId'),
        (Get-OptionalProperty -InputObject $Submitted -Name 'chat_id')
    )
}

function Get-SubmitTargetId {
    param($SubmitResult)

    $Trace = Get-OptionalProperty -InputObject $SubmitResult -Name 'cmcp_go_trace'
    $Submitted = Get-OptionalProperty -InputObject $SubmitResult -Name 'submitted'
    return Get-FirstValue -Values @(
        (Get-OptionalProperty -InputObject $SubmitResult -Name 'targetId'),
        (Get-OptionalProperty -InputObject $SubmitResult -Name 'target_id'),
        (Get-OptionalProperty -InputObject $SubmitResult -Name 'opened_target_id'),
        (Get-OptionalProperty -InputObject $Trace -Name 'opened_target_id'),
        (Get-OptionalProperty -InputObject $Submitted -Name 'targetId'),
        (Get-OptionalProperty -InputObject $Submitted -Name 'target_id')
    )
}

function Invoke-BridgeTool {
    param([Parameter(Mandatory=$true)][string]$Tool, [Parameter(Mandatory=$true)]$Arguments, [Parameter(Mandatory=$true)][string]$TaskId)
    Ensure-Dir $BridgeDir
    $Id = [guid]::NewGuid().ToString('N')
    $PayloadPath = Join-Path $BridgeDir ($Id + '.payload.json')
    $ResultPath = Join-Path $BridgeDir ($Id + '.result.json')
    $Payload = [ordered]@{
        runnerExecutionPlan = [ordered]@{
            tool = $Tool
            arguments = $Arguments
        }
    }
    Write-JsonFile -Value $Payload -Path $PayloadPath
    $Raw = & $Bridge -PayloadPath $PayloadPath -ResultPath $ResultPath 2>&1
    $BridgePayload = $Raw | ConvertFrom-Json
    $Result = Read-JsonFile -Path $ResultPath
    Append-Journal -TaskId $TaskId -Event 'bridgeTool' -Data ([ordered]@{ tool = $Tool; bridgeStatus = $BridgePayload.status; resultStatus = $Result.status })
    [pscustomobject]@{ bridge = $BridgePayload; result = $Result; resultPath = $ResultPath; payloadPath = $PayloadPath }
}

function Invoke-RunnerDispatch {
    param([Parameter(Mandatory=$true)]$Contract, [Parameter(Mandatory=$true)][string]$Task, [Parameter(Mandatory=$true)][string]$TaskId)
    Ensure-Dir $RunnerStateDir
    $RunId = 'task-bank-' + ([guid]::NewGuid().ToString('N'))
    $Seed = [ordered]@{
        ok = $true
        status = 'RUNNER_STATE_PERSISTED'
        schemaVersion = 2
        runtimeVersion = '2026.07.task-bank-loop'
        runId = $RunId
        taskId = $Task
        runnerMode = 'task_bank_loop'
        finalActionSelected = 'seed_task_bank_dispatch'
        finalActionResult = [ordered]@{ ok = $true; status = 'FINAL_ACTION_RESUME_LATEST'; action = 'resume_latest'; nextAction = 'dispatch_next_from_state' }
        nextDispatchContract = $Contract
        budget = [ordered]@{ mode = 'interactions'; remaining = $MaxIterations; untilRc = $false }
        retryPolicy = $null
        retryAttempt = 0
        recoveryPlan = $null
        updatedAt = Get-IsoNow
    }
    Write-JsonFile -Value ([pscustomobject]$Seed) -Path $RunnerStatePath
    $DaemonRaw = & $Daemon -Task $Task -MaxIterations $MaxIterations 2>&1
    $DaemonPayload = $DaemonRaw | ConvertFrom-Json
    if ($DaemonPayload.status -ne 'RUNNER_DAEMON_DISPATCH_READY') { throw "runner daemon did not select dispatch: $($DaemonPayload.status)" }
    $Tool = [string]$DaemonPayload.dispatchTool
    if ($Tool -ne 'write.browser.session.cmcp.go') { throw "task-bank UI submit expected cmcp.go, got $Tool" }
    $BridgeRaw = & $Bridge -PayloadPath $DaemonPayload.dispatchPayloadPath -ResultPath $DaemonPayload.expectedResultPath 2>&1
    $BridgePayload = $BridgeRaw | ConvertFrom-Json
    $Result = Read-JsonFile -Path $DaemonPayload.expectedResultPath
    $AdapterRaw = & $TransportAdapter -Task $Task -MaxIterations $MaxIterations -PayloadPath $DaemonPayload.dispatchPayloadPath -ResultPath $DaemonPayload.expectedResultPath 2>&1
    $AdapterPayload = $AdapterRaw | ConvertFrom-Json
    Append-Journal -TaskId $TaskId -Event 'uiSubmit' -Data ([ordered]@{ tool = $Tool; dispatchStatus = $DaemonPayload.status; bridgeStatus = $BridgePayload.status; resultStatus = $Result.status; adapterStatus = $AdapterPayload.status; payloadPath = $DaemonPayload.dispatchPayloadPath; resultPath = $DaemonPayload.expectedResultPath })
    [pscustomobject]@{ tool = $Tool; daemon = $DaemonPayload; bridge = $BridgePayload; result = $Result; adapter = $AdapterPayload; payloadPath = $DaemonPayload.dispatchPayloadPath; resultPath = $DaemonPayload.expectedResultPath }
}

function Get-AssistantJson {
    param([string]$Text)
    if (-not $Text) { return $null }
    $Trimmed = $Text.Trim()
    if (-not ($Trimmed.StartsWith('{') -or $Trimmed.StartsWith('['))) { return $null }
    try { return ($Trimmed | ConvertFrom-Json) } catch { return $null }
}

function Get-SemanticStatus {
    param($AssistantJson, [string]$AssistantText, [string]$AssistantStatus)
    $Text = if ($AssistantText) { $AssistantText } else { '' }
    if ($Text -match 'TOOL_CALL_BLOCKED|tool call blocked|blocked tool') { return 'TOOL_CALL_BLOCKED' }
    if ($Text -match '\brefus(e|al|ed)\b|I can.t help') { return 'REFUSAL' }
    if ($AssistantJson -and $AssistantJson.status) { return [string]$AssistantJson.status }
    if ($AssistantStatus) { return $AssistantStatus }
    return 'ASSISTANT_TEXT_CAPTURED'
}

function Get-ReadyToDeleteSignal {
    param([AllowNull()][string]$AssistantText)
    if ([string]::IsNullOrEmpty($AssistantText)) { return $null }
    $VisibleLines = @()
    $InsideFence = $false
    foreach ($Line in @($AssistantText -split '\r?\n|\r')) {
        $Trimmed = ([string]$Line).Trim()
        if ($Trimmed.StartsWith('```')) { $InsideFence = -not $InsideFence; continue }
        if (-not $InsideFence -and $Trimmed -ne '') { $VisibleLines += $Trimmed }
    }
    $Tail = @($VisibleLines | Select-Object -Last 5)
    $HasTrue = @($Tail | Where-Object { $_ -ceq '{"ready_to_delete":true}' }).Count -gt 0
    $HasFalse = @($Tail | Where-Object { $_ -ceq '{"ready_to_delete":false}' }).Count -gt 0
    if ($HasTrue -eq $HasFalse) { return $null }
    return $HasTrue
}

function ConvertTo-NormalizedAnswer {
    param($Settled, [string]$TaskId, [string]$ChatId, [string]$TargetId)
    $Latest = $Settled.latest_assistant
    $Text = if ($Latest -and $Latest.text) { [string]$Latest.text } else { '' }
    $Json = Get-AssistantJson -Text $Text
    $AssistantStatus = [string]$Settled.status
    $SemanticStatus = Get-SemanticStatus -AssistantJson $Json -AssistantText $Text -AssistantStatus $AssistantStatus
    $Captured = ($Text.Length -gt 0 -and $AssistantStatus -ne 'OBSERVATION_WINDOW_EXPIRED')
    [ordered]@{
        ok = ($Settled.ok -eq $true)
        status = 'ENGINE_ANSWER_CAPTURED'
        task_id = $TaskId
        assistantCaptured = $Captured
        assistantText = $Text
        assistantJson = $Json
        assistantOk = ($Settled.ok -eq $true)
        assistantStatus = $AssistantStatus
        semanticStatus = $SemanticStatus
        semanticNextAction = if ($SemanticStatus -eq 'REFUSAL') { 'stop_loop' } else { 'continue_or_stop_by_budget' }
        chatId = $ChatId
        targetId = $TargetId
        capturedAt = Get-IsoNow
        latestAssistantHash = if ($Latest -and $Latest.hash) { [string]$Latest.hash } else { Get-Hash $Text }
        latestAssistantTextLength = $Text.Length
        rawSettleStatus = $Settled.status
    }
}

function Update-TaskAndChatFromProbe {
    param($Task, $Chat, $Probe)
    if ($Probe.context_update) {
        if ($Probe.context_update.chatId) { $Task.chatId = [string]$Probe.context_update.chatId; $Chat.chatId = [string]$Probe.context_update.chatId }
        if ($Probe.context_update.lastSeenAssistantHash) { $Task.lastSeenTailHash = [string]$Probe.context_update.lastSeenTailHash; $Task.lastAssistantHash = [string]$Probe.context_update.lastSeenAssistantHash }
        if ($null -ne $Probe.context_update.lastSeenTextLength) { $Task.lastAssistantTextLength = [int]$Probe.context_update.lastSeenTextLength }
        if ($Probe.context_update.lastSeenOutlineHash) { $Task.lastSeenOutlineHash = [string]$Probe.context_update.lastSeenOutlineHash }
        if ($null -ne $Probe.context_update.lastSeenScrollHeight) { $Task.lastSeenScrollHeight = [int]$Probe.context_update.lastSeenScrollHeight }
        if ($Probe.context_update.lastProgressAt) { $Task.lastProgressAt = [string]$Probe.context_update.lastProgressAt }
        if ($null -ne $Probe.context_update.attempt) { $Task.attempt = [int]$Probe.context_update.attempt }
    }
    if ($Probe.probe) { $Chat.composerState = $Probe.probe.composer_action_mode }
    $Chat.lastProbeAt = Get-IsoNow
}

function Test-CaptureReady {
    param($ProbeResult, $StepResult)

    $ProbeDecision = Get-OptionalProperty -InputObject $ProbeResult -Name 'decision'
    $ProbeNextAction = Get-FirstValue -Values @(
        (Get-OptionalProperty -InputObject $ProbeDecision -Name 'next_action'),
        (Get-OptionalProperty -InputObject $ProbeDecision -Name 'nextAction'),
        (Get-OptionalProperty -InputObject $ProbeResult -Name 'next_action'),
        (Get-OptionalProperty -InputObject $ProbeResult -Name 'nextAction')
    )
    $StepNextAction = Get-FirstValue -Values @(
        (Get-OptionalProperty -InputObject $StepResult -Name 'next_action'),
        (Get-OptionalProperty -InputObject $StepResult -Name 'nextAction')
    )
    $ProbeStatus = Get-OptionalProperty -InputObject $ProbeResult -Name 'status'
    $StepStatus = Get-OptionalProperty -InputObject $StepResult -Name 'status'

    return ($ProbeNextAction -eq 'RUN_STABLE_CAPTURE' -or
        $StepNextAction -eq 'RUN_STABLE_CAPTURE' -or
        $ProbeStatus -eq 'READY_FOR_STABLE_CAPTURE' -or
        $StepStatus -eq 'READY_FOR_STABLE_CAPTURE')
}

function Test-QuietEmptyCaptureBinding {
    param($ProbeResult, $StepResult)

    $ProbePayload = Get-OptionalProperty -InputObject $ProbeResult -Name 'probe'
    $Messages = Get-OptionalProperty -InputObject $ProbeResult -Name 'messages'
    if ($null -eq $Messages -and $ProbePayload) { $Messages = Get-OptionalProperty -InputObject $ProbePayload -Name 'messages' }
    $LatestAssistant = Get-OptionalProperty -InputObject $ProbeResult -Name 'latest_assistant'
    if ($null -eq $LatestAssistant -and $ProbePayload) { $LatestAssistant = Get-OptionalProperty -InputObject $ProbePayload -Name 'latest_assistant' }
    $Busy = Get-OptionalProperty -InputObject $ProbePayload -Name 'busy'
    $ComposerStopMode = Get-OptionalProperty -InputObject $ProbePayload -Name 'composer_stop_control_mode'
    $ComposerActionMode = Get-OptionalProperty -InputObject $ProbePayload -Name 'composer_action_mode'
    $MessageCount = if ($null -eq $Messages) { 0 } else { @($Messages).Count }
    $ProbeStatus = [string](Get-OptionalProperty -InputObject $ProbeResult -Name 'status')
    $StepStatus = [string](Get-OptionalProperty -InputObject $StepResult -Name 'status')

    return (($ProbeStatus -in @('LIKELY_STABLE','READY_FOR_STABLE_CAPTURE') -or $StepStatus -eq 'READY_FOR_STABLE_CAPTURE') -and
        ($Busy -eq $false -or $null -eq $Busy) -and
        ($ComposerStopMode -eq 'not_found' -or $null -eq $ComposerStopMode) -and
        ($ComposerActionMode -eq 'disabled' -or $ComposerActionMode -eq 'send' -or $null -eq $ComposerActionMode) -and
        $MessageCount -eq 0 -and
        $null -eq $LatestAssistant)
}

function New-TaskRecord {
    param([string]$TaskId)
    $Now = Get-IsoNow
    [pscustomobject]@{
        taskId = $TaskId
        name = $Name
        component = $Name
        workspacePath = $TargetRepo
        maxInteractions = $MaxIterations
        interactionCount = 0
        status = 'created'
        chatId = $AdoptedChatId
        targetId = $null
        lockedChatId = $AdoptedChatId
        lastAssistantHash = $null
        lastAssistantTextLength = 0
        lastSeenTailHash = $null
        lastSeenOutlineHash = $null
        lastSeenScrollHeight = 0
        sentAt = $null
        lastProgressAt = $null
        nextPollAt = $Now
        attempt = 0
        decisionState = [pscustomobject]@{ status = 'created'; nextDispatchContract = $null; semanticStatus = $null; nextAction = 'submit_initial_prompt' }
        runnerStatePath = $RunnerStatePath
        createdAt = $Now
        updatedAt = $Now
    }
}

function New-ChatRecord {
    param([string]$TaskId)
    [pscustomobject]@{
        chatId = $AdoptedChatId
        targetId = $null
        taskId = $TaskId
        url = if ($AdoptedChatId) { "https://chatgpt.com/c/$AdoptedChatId" } else { $null }
        status = if ($AdoptedChatId) { 'adopted' } else { 'created' }
        lastBindAt = if ($AdoptedChatId) { Get-IsoNow } else { $null }
        lastProbeAt = $null
        composerState = $null
        lastAssistantHash = $null
        lastAssistantCapturedAt = $null
        recoveryAttempt = 0
    }
}

function Get-RepoCleanStatus {
    param([Parameter(Mandatory=$true)][string]$Path)

    $Git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $Git -or -not (Test-Path -LiteralPath (Join-Path $Path '.git'))) {
        return [pscustomobject]@{ checked = $false; clean = $false; status = 'GIT_STATUS_UNAVAILABLE'; details = @() }
    }

    $Raw = & $Git.Source -C $Path status --short 2>&1
    if ($LASTEXITCODE -ne 0) {
        return [pscustomobject]@{ checked = $true; clean = $false; status = 'GIT_STATUS_FAILED'; details = @($Raw) }
    }

    $Items = @($Raw | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    return [pscustomobject]@{ checked = $true; clean = ($Items.Count -eq 0); status = if ($Items.Count -eq 0) { 'GIT_STATUS_CLEAN' } else { 'GIT_STATUS_DIRTY' }; details = $Items }
}

function Write-AcceptanceArtifact {
    param(
        [Parameter(Mandatory=$true)]$Task,
        [Parameter(Mandatory=$true)]$Chat,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Answers,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$ObservedChatIds,
        [Parameter(Mandatory=$true)][int]$SubmittedCount,
        [Parameter(Mandatory=$true)][int]$AssistantCapturedCount,
        [Parameter(Mandatory=$true)][int]$InternalStepCount,
        [Parameter(Mandatory=$true)][string]$FinalStatus
    )

    Ensure-Dir $AcceptanceDir
    $RepoStatus = Get-RepoCleanStatus -Path $TargetRepo
    $DistinctChatIds = @($ObservedChatIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    $AnswerRows = @($Answers | ForEach-Object {
        [ordered]@{
            path = $_.path
            assistantStatus = $_.assistantStatus
            semanticStatus = $_.semanticStatus
            textLength = [int]$_.textLength
            chatId = $_.chatId
            captured = [bool]$_.captured
        }
    })
    $Failures = @()
    $ReadyToDeleteComplete = ((Get-OptionalProperty -InputObject $Task -Name 'readyToDelete') -eq $true)
    if (-not $ReadyToDeleteComplete -and [int]$Task.interactionCount -ne $MaxIterations) { $Failures += 'interactionCycleCount_mismatch' }
    if (-not $ReadyToDeleteComplete -and $SubmittedCount -ne $MaxIterations) { $Failures += 'submittedCount_mismatch' }
    if (-not $ReadyToDeleteComplete -and $AssistantCapturedCount -ne $MaxIterations) { $Failures += 'assistantCapturedCount_mismatch' }
    if ($ReadyToDeleteComplete -and ([int]$Task.interactionCount -lt 1 -or $SubmittedCount -ne [int]$Task.interactionCount -or $AssistantCapturedCount -ne [int]$Task.interactionCount)) { $Failures += 'ready_to_delete_capture_count_mismatch' }
    if (@($AnswerRows | Where-Object { $_.textLength -le 0 -or -not $_.captured }).Count -gt 0) { $Failures += 'empty_answer_capture' }
    if (@($AnswerRows | Where-Object { $_.assistantStatus -eq 'OBSERVATION_WINDOW_EXPIRED' }).Count -gt 0) { $Failures += 'observation_window_expired' }
    if (@($AnswerRows | Where-Object { $_.semanticStatus -eq 'REFUSAL' }).Count -gt 0) { $Failures += 'semantic_refusal' }
    if ($DistinctChatIds.Count -ne 1 -or ($Task.lockedChatId -and $DistinctChatIds[0] -ne $Task.lockedChatId)) { $Failures += 'unstable_chatId' }
    if (-not $RepoStatus.clean) { $Failures += 'target_repo_not_clean' }

    $Status = if ($Failures.Count -eq 0) { 'M3_ACCEPTANCE_PASS' } else { 'M3_ACCEPTANCE_FAIL' }
    $Artifact = [ordered]@{
        ok = ($Failures.Count -eq 0)
        status = $Status
        failures = @($Failures)
        targetRepo = $TargetRepo
        maxIterations = $MaxIterations
        interactionCycleCount = [int]$Task.interactionCount
        internalStepCount = $InternalStepCount
        submittedCount = $SubmittedCount
        assistantCapturedCount = $AssistantCapturedCount
        chatId = $Task.chatId
        lockedChatId = $Task.lockedChatId
        observedChatIds = @($DistinctChatIds)
        targetId = $Task.targetId
        finalStatus = $FinalStatus
        answerChecks = @($AnswerRows)
        repoStatus = $RepoStatus
        taskPath = $TaskPath
        chatPath = $ChatPath
        createdAt = Get-IsoNow
    }
    $Path = Join-Path $AcceptanceDir ($Task.taskId + '-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '.acceptance.json')
    Write-JsonFile -Value ([pscustomobject]$Artifact) -Path $Path
    return [pscustomobject]@{ path = $Path; artifact = ([pscustomobject]$Artifact) }
}

function Write-LiveShadowParityArtifact {
    param(
        [Parameter(Mandatory=$true)]$Task,
        [Parameter(Mandatory=$true)]$Answer,
        [Parameter(Mandatory=$true)]$Authoritative,
        [Parameter(Mandatory=$true)][string]$TaskId
    )

    Ensure-Dir $ParityDir
    $Id = [guid]::NewGuid().ToString('N')
    $InputPath = Join-Path $ParityDir ($TaskId + '-' + $Id + '.input.json')
    $OutputPath = Join-Path $ParityDir ($TaskId + '-' + $Id + '.parity.json')
    $CaptureScript = Join-Path $Root 'tool/live-shadow-parity-capture.php'
    $Payload = [ordered]@{
        snapshot = [ordered]@{
            task = $Task
            completion_verified = $false
            assistant_text = $Answer.assistantText
            captured_answer = [ordered]@{
                assistantStatus = $Answer.assistantStatus
                semanticStatus = $Answer.semanticStatus
                latestAssistantHash = $Answer.latestAssistantHash
                latestAssistantTextLength = $Answer.latestAssistantTextLength
            }
        }
        authoritative = $Authoritative
        provenance = [ordered]@{
            origin = 'live_task_bank'
            immutableReceipt = $true
            sourceTaskId = $TaskId
        }
    }
    Write-JsonFile -Value ([pscustomobject]$Payload) -Path $InputPath

    try {
        $Raw = & php $CaptureScript "--input=$InputPath" "--output=$OutputPath" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "live shadow parity capture exit code $LASTEXITCODE`: $Raw" }
        $Result = $Raw | ConvertFrom-Json
        Append-Journal -TaskId $TaskId -Event 'liveShadowParity' -Data ([ordered]@{ status = $Result.artifactStatus; outputPath = $OutputPath; authoritative = $false })
        return [pscustomobject]@{ ok = $true; status = [string]$Result.artifactStatus; path = $OutputPath }
    } catch {
        Append-Journal -TaskId $TaskId -Event 'liveShadowParityDiagnosticFailure' -Data ([ordered]@{ status = 'LIVE_SHADOW_PARITY_CAPTURE_FAILED_NON_AUTHORITATIVE'; error = $_.Exception.Message; authoritative = $false })
        return [pscustomobject]@{ ok = $false; status = 'LIVE_SHADOW_PARITY_CAPTURE_FAILED_NON_AUTHORITATIVE'; path = $null }
    }
}

function Write-LiveShadowBrowserObservationArtifact {
    param(
        [Parameter(Mandatory=$true)][string]$TaskId,
        [Parameter(Mandatory=$true)]$Probe,
        [Parameter(Mandatory=$true)]$Step,
        [Parameter(Mandatory=$true)]$Authoritative
    )

    Ensure-Dir $ParityDir
    $Id = [guid]::NewGuid().ToString('N')
    $InputPath = Join-Path $ParityDir ($TaskId + '-' + $Id + '.browser-observation.input.json')
    $OutputPath = Join-Path $ParityDir ($TaskId + '-' + $Id + '.browser-observation.parity.json')
    $CaptureScript = Join-Path $Root 'tool/browser-observation-shadow-capture.php'
    Write-JsonFile -Value ([pscustomobject][ordered]@{ probe = $Probe; step = $Step; authoritative = $Authoritative }) -Path $InputPath

    try {
        $Raw = & php $CaptureScript "--input=$InputPath" "--output=$OutputPath" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "browser observation shadow capture exit code $LASTEXITCODE`: $Raw" }
        $Result = $Raw | ConvertFrom-Json
        Append-Journal -TaskId $TaskId -Event 'liveShadowBrowserObservation' -Data ([ordered]@{ status = $Result.parityStatus; projectionStatus = $Result.status; state = $Result.state; outputPath = $OutputPath; authoritative = $false })
        return [pscustomobject]@{ ok = $true; status = [string]$Result.parityStatus; state = [string]$Result.state; path = $OutputPath }
    } catch {
        Append-Journal -TaskId $TaskId -Event 'liveShadowBrowserObservationDiagnosticFailure' -Data ([ordered]@{ status = 'SHADOW_BROWSER_OBSERVATION_CAPTURE_FAILED_NON_AUTHORITATIVE'; error = $_.Exception.Message; authoritative = $false })
        return [pscustomobject]@{ ok = $false; status = 'SHADOW_BROWSER_OBSERVATION_CAPTURE_FAILED_NON_AUTHORITATIVE'; state = 'unknown'; path = $null }
    }
}

function Write-LiveShadowRecoveryArtifact {
    param(
        [Parameter(Mandatory=$true)]$Task,
        [Parameter(Mandatory=$true)][string]$TaskId,
        [Parameter(Mandatory=$true)][string]$Stage,
        [Parameter(Mandatory=$true)][string]$Reason,
        $Receipt
    )

    Ensure-Dir $ParityDir
    $Id = [guid]::NewGuid().ToString('N')
    $InputPath = Join-Path $ParityDir ($TaskId + '-' + $Id + '.recovery.input.json')
    $OutputPath = Join-Path $ParityDir ($TaskId + '-' + $Id + '.recovery.parity.json')
    $CaptureScript = Join-Path $Root 'tool/live-shadow-parity-capture.php'
    $ShadowTask = [ordered]@{
        task_id = $Task.taskId
        component = $Task.component
        workspace_path = $Task.workspacePath
        chat_id = $Task.chatId
        target_id = $Task.targetId
        status = 'blocked'
        auto_iteration_count = [int]$Task.interactionCount
        max_auto_iterations = [int]$Task.maxInteractions
        retry_attempt = [int]$Task.attempt
        execution_blocked_stage = $Stage
        execution_blocked_reason = $Reason
        execution_blocked_receipt = if ($null -ne $Receipt) { $Receipt } else { [ordered]@{} }
    }
    Write-JsonFile -Value ([pscustomobject][ordered]@{ snapshot = [ordered]@{ task = $ShadowTask }; authoritative = [ordered]@{} }) -Path $InputPath

    try {
        $Raw = & php $CaptureScript "--input=$InputPath" "--output=$OutputPath" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "live shadow recovery capture exit code $LASTEXITCODE`: $Raw" }
        $Result = $Raw | ConvertFrom-Json
        Append-Journal -TaskId $TaskId -Event 'liveShadowRecovery' -Data ([ordered]@{ stage = $Stage; reason = $Reason; status = $Result.artifactStatus; outputPath = $OutputPath; authoritative = $false })
        return [pscustomobject]@{ ok = $true; status = [string]$Result.artifactStatus; path = $OutputPath }
    } catch {
        Append-Journal -TaskId $TaskId -Event 'liveShadowRecoveryDiagnosticFailure' -Data ([ordered]@{ stage = $Stage; reason = $Reason; status = 'LIVE_SHADOW_RECOVERY_CAPTURE_FAILED_NON_AUTHORITATIVE'; error = $_.Exception.Message; authoritative = $false })
        return [pscustomobject]@{ ok = $false; status = 'LIVE_SHADOW_RECOVERY_CAPTURE_FAILED_NON_AUTHORITATIVE'; path = $null }
    }
}

Ensure-Dir $TaskDir
Ensure-Dir $JournalDir
Ensure-Dir $AnswerDir
Ensure-Dir $BridgeDir
Ensure-Dir $AcceptanceDir
Ensure-Dir $ParityDir
Ensure-Dir $ChatDir
Ensure-Dir $RunnerStateDir

$AdoptedChatId = Normalize-ChatId -Value $AdoptChatId
$TaskId = 'repo-smoke-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss') + '-' + (Get-Hash ($TargetRepo.ToLowerInvariant() + '|' + $Name + '|' + [guid]::NewGuid().ToString('N'))).Substring(0, 10)
$TaskPath = Join-Path $TaskDir ($TaskId + '.json')
$ChatPath = Join-Path $ChatDir ($TaskId + '.json')
$Task = New-TaskRecord -TaskId $TaskId
$Chat = New-ChatRecord -TaskId $TaskId
$TaskTaskText = "Task-bank product loop. Name: $Name. Target workspace: $TargetRepo. Goal: read-only repository loop smoke; avoid file changes; avoid commits."
if ([string]::IsNullOrWhiteSpace($InitialPromptMode)) { $InitialPromptMode = $PromptMode }
if ([string]::IsNullOrWhiteSpace($ContinuePromptMode)) { $ContinuePromptMode = 'raw' }
if ([string]::IsNullOrWhiteSpace($InitialPrompt)) {
    $InitialPrompt = "Run a read-only repository loop smoke for workspace $TargetRepo. Use only safe inspection. Do not edit files. Do not commit. Return strict JSON with ok, status, tool, workspacePath, and summary."
}
if ([string]::IsNullOrWhiteSpace($ContinuePrompt)) {
    $ContinuePrompt = "Continue the read-only repository loop smoke for workspace $TargetRepo based on the captured assistant answer. Do not edit files. Do not commit. Return strict JSON with ok, status, tool, workspacePath, summary, and nextAction."
}
$SubmittedCount = 0
$AssistantCapturedCount = 0
$InternalStepCount = 0
$AnswerRecords = @()
$ObservedChatIds = @()
$ToolsUsed = @()
$DecisionStages = @('task-bank', 'chat-bank', 'round-robin-scheduler')
$LastAssistantStatus = $null
$LastSemanticStatus = $null
$FinalStatus = 'TASK_BANK_LOOP_STARTED'
$StartedAt = Get-Date
$PollIntervalSeconds = 3
$PollIntervalMs = $PollIntervalSeconds * 1000
$MaxInternalStepsPerInteraction = 120

Write-JsonFile -Value $Task -Path $TaskPath
Write-JsonFile -Value $Chat -Path $ChatPath
Append-Journal -TaskId $TaskId -Event 'taskCreated' -Data ([ordered]@{ taskPath = $TaskPath; chatPath = $ChatPath; adoptedChatId = $AdoptedChatId })
Write-Host ("progress " + ([ordered]@{ event = 'taskCreated'; taskId = $TaskId; taskBankPath = $TaskPath; chatBankPath = $ChatPath; adoptedChatId = $AdoptedChatId } | ConvertTo-Json -Depth 20 -Compress))

while ($true) {
    if ($Task.interactionCount -ge $Task.maxInteractions) {
        $Task.status = 'interaction_budget_exhausted'
        $FinalStatus = 'TASK_BANK_INTERACTION_BUDGET_EXHAUSTED'
        break
    }
    if ($Task.status -in @('terminal_success','terminal_failed','semantic_blocked')) { break }

    if ($Task.status -in @('created','ready_next_interaction')) {
        if ($Task.lockedChatId -and $Task.chatId -and $Task.chatId -ne $Task.lockedChatId) {
            $Task.status = 'terminal_failed'
            $FinalStatus = 'SINGLE_CHAT_REBIND_FAILED'
            $Task | Add-Member -NotePropertyName lastFailure -NotePropertyValue ([pscustomobject][ordered]@{ status = $FinalStatus; expectedChatId = $Task.lockedChatId; actualChatId = $Task.chatId; capturedAt = Get-IsoNow }) -Force
            Write-JsonFile -Value $Task -Path $TaskPath
            break
        }

        if ($Task.targetId) {
            $PreflightArgs = [ordered]@{ expectedTargetId = $Task.targetId; timeoutMs = 5000 }
            $Preflight = Invoke-BridgeTool -Tool 'read_.browser.chatgpt.composer.preflight' -Arguments $PreflightArgs -TaskId $TaskId
            $ToolsUsed += 'read_.browser.chatgpt.composer.preflight'
            $InternalStepCount++
            Write-Host ("progress " + ([ordered]@{ event = 'internalPoll'; tool = 'read_.browser.chatgpt.composer.preflight'; status = $Preflight.result.status; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))
        } elseif ($Task.lockedChatId) {
            $Task.chatId = [string]$Task.lockedChatId
            $Chat.chatId = [string]$Task.lockedChatId
            $Chat.url = "https://chatgpt.com/c/$($Task.lockedChatId)"
            $Chat.recoveryAttempt = [int]$Chat.recoveryAttempt + 1
            $Chat.lastBindAt = Get-IsoNow
            Write-JsonFile -Value $Task -Path $TaskPath
            Write-JsonFile -Value $Chat -Path $ChatPath
            Write-Host ("progress " + ([ordered]@{ event = 'chatRebindScheduled'; chatId = $Task.lockedChatId; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))
        } elseif ($Task.interactionCount -gt 0) {
            $Task.status = 'terminal_failed'
            $FinalStatus = 'SINGLE_CHAT_REBIND_FAILED'
            $Task | Add-Member -NotePropertyName lastFailure -NotePropertyValue ([pscustomobject][ordered]@{ status = $FinalStatus; reason = 'target_and_locked_chat_missing'; capturedAt = Get-IsoNow }) -Force
            Write-JsonFile -Value $Task -Path $TaskPath
            break
        }
        $UseInitialPrompt = ($Task.interactionCount -eq 0 -and -not $AdoptedChatId)
        $RawCommand = if ($UseInitialPrompt) { $InitialPrompt } else { $ContinuePrompt }
        $EffectivePromptMode = if ($UseInitialPrompt) { $InitialPromptMode } else { $ContinuePromptMode }
        $Contract = New-CmcpDispatchContract -RawCommand $RawCommand -ChatId $Task.chatId -EffectivePromptMode $EffectivePromptMode
        $Task.decisionState = [pscustomobject]@{ status = 'next_interaction_selected'; nextDispatchContract = $Contract; semanticStatus = $LastSemanticStatus; nextAction = 'dispatch_ui_interaction_submit' }
        $Task | Add-Member -NotePropertyName currentCycleBaselineAssistantHash -NotePropertyValue $Task.lastAssistantHash -Force
        $Task.updatedAt = Get-IsoNow
        Write-JsonFile -Value $Task -Path $TaskPath

        $Submit = Invoke-RunnerDispatch -Contract $Contract -Task $TaskTaskText -TaskId $TaskId
        $ToolsUsed += $Submit.tool
        $DecisionStages += @('runner-daemon','runner-dispatcher','runner-transport-adapter','runner-adapter')
        $InternalStepCount++
        $SubmitResult = Get-OptionalProperty -InputObject $Submit -Name 'result'
        $SubmitSubmitted = Get-OptionalProperty -InputObject $SubmitResult -Name 'submitted'
        $SubmitTrace = Get-OptionalProperty -InputObject $SubmitResult -Name 'cmcp_go_trace'
        $TraceSubmitted = Get-OptionalProperty -InputObject $SubmitTrace -Name 'submitted'
        $TraceSubmittedStatus = Get-OptionalProperty -InputObject $SubmitTrace -Name 'submitted_status'
        $NestedSubmitted = Get-OptionalProperty -InputObject $SubmitSubmitted -Name 'submitted'
        $Submitted = ($SubmitSubmitted -eq $true -or $NestedSubmitted -eq $true -or $TraceSubmitted -eq $true -or $TraceSubmittedStatus -eq 'BROWSER_SESSION_SUBMITTED')
        if (-not $Submitted) {
            $Task.status = 'submit_failed'
            $SubmitStatus = Get-OptionalProperty -InputObject $SubmitResult -Name 'status'
            $FinalStatus = if ($SubmitStatus) { [string]$SubmitStatus } else { 'CMCP_GO_SUBMIT_NOT_CONFIRMED' }
            $Task | Add-Member -NotePropertyName lastFailure -NotePropertyValue ([pscustomobject][ordered]@{ status = $FinalStatus; tool = $Submit.tool; payloadPath = $Submit.payloadPath; resultPath = $Submit.resultPath; adapterStatus = $Submit.adapter.status; bridgeStatus = $Submit.bridge.status; capturedAt = Get-IsoNow }) -Force
            Append-Journal -TaskId $TaskId -Event 'uiSubmitRejected' -Data ([ordered]@{ tool = $Submit.tool; finalStatus = $FinalStatus; payloadPath = $Submit.payloadPath; resultPath = $Submit.resultPath; adapterStatus = $Submit.adapter.status; bridgeStatus = $Submit.bridge.status })
            $null = Write-LiveShadowRecoveryArtifact -Task $Task -TaskId $TaskId -Stage 'prompt_submit' -Reason $FinalStatus -Receipt $SubmitResult
            Write-JsonFile -Value $Task -Path $TaskPath
            break
        }
        $SubmittedCount++
        $Task.status = 'waiting_answer'
        $Task.sentAt = Get-IsoNow
        $Task | Add-Member -NotePropertyName currentInteractionStartStep -NotePropertyValue $InternalStepCount -Force
        $SubmittedChatId = Get-SubmitChatId -SubmitResult $Submit.result
        $SubmittedTargetId = Get-SubmitTargetId -SubmitResult $Submit.result
        if ($SubmittedTargetId) { $Task.targetId = $SubmittedTargetId }
        if ($SubmittedChatId) { $Task.chatId = $SubmittedChatId }
        if ($Task.chatId) {
            $SubmittedChatIsProvisional = ([string]$Task.chatId).StartsWith('WEB:', [System.StringComparison]::OrdinalIgnoreCase)
            if (-not $Task.lockedChatId -and -not $SubmittedChatIsProvisional) {
                $Task.lockedChatId = [string]$Task.chatId
            } elseif ($Task.lockedChatId -and $Task.chatId -ne $Task.lockedChatId) {
                $Task.status = 'terminal_failed'
                $FinalStatus = 'SINGLE_CHAT_REBIND_FAILED'
                $Task | Add-Member -NotePropertyName lastFailure -NotePropertyValue ([pscustomobject][ordered]@{ status = $FinalStatus; expectedChatId = $Task.lockedChatId; actualChatId = $Task.chatId; resultPath = $Submit.resultPath; capturedAt = Get-IsoNow }) -Force
                Append-Journal -TaskId $TaskId -Event 'singleChatViolation' -Data ([ordered]@{ expectedChatId = $Task.lockedChatId; actualChatId = $Task.chatId; resultPath = $Submit.resultPath })
                Write-JsonFile -Value $Task -Path $TaskPath
                Write-JsonFile -Value $Chat -Path $ChatPath
                break
            }
            if (-not $SubmittedChatIsProvisional) {
                $ObservedChatIds += [string]$Task.chatId
            }
        }
        $Chat.targetId = $Task.targetId
        $Chat.chatId = $Task.chatId
        $Chat.url = if ($Task.chatId) { "https://chatgpt.com/c/$($Task.chatId)" } else { 'https://chatgpt.com/' }
        $Chat.status = 'waiting_answer'
        $Chat.lastBindAt = Get-IsoNow
        $Task.nextPollAt = (Get-Date).AddSeconds($PollIntervalSeconds).ToUniversalTime().ToString('o')
        $Task.updatedAt = Get-IsoNow
        Write-JsonFile -Value $Task -Path $TaskPath
        Write-JsonFile -Value $Chat -Path $ChatPath
        Write-Host ("progress " + ([ordered]@{ event = 'uiSubmit'; submitted = $true; submittedCount = $SubmittedCount; chatId = $Task.chatId; targetId = $Task.targetId; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))
    }

    if ($Task.status -eq 'waiting_answer') {
        $Now = Get-Date
        $Due = [datetime]::Parse($Task.nextPollAt).ToUniversalTime()
        if ($Now.ToUniversalTime() -lt $Due) {
            $SleepSeconds = [Math]::Min($PollIntervalSeconds, [Math]::Max(1, [int][Math]::Ceiling(($Due - $Now.ToUniversalTime()).TotalSeconds)))
            Write-Host ("progress " + ([ordered]@{ event = 'answerWaiting'; sleepSeconds = $SleepSeconds; nextPollAt = $Task.nextPollAt; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))
            Start-Sleep -Seconds $SleepSeconds
        }

        $ProbeArgs = [ordered]@{
            expectedTargetId = $Task.targetId
            requireChatId = $false
            maxMessages = 40
            timeoutMs = 5000
            phase = 'reply_watch'
            taskClass = 'normal_answer'
            sentAt = $Task.sentAt
            attempt = [int]$Task.attempt
        }
        if ($Task.lastAssistantHash) { $ProbeArgs.previousAssistantHash = $Task.lastAssistantHash }
        if ($Task.lastAssistantTextLength -gt 0) { $ProbeArgs.previousTextLength = [int]$Task.lastAssistantTextLength }
        if ($Task.lastSeenTailHash) { $ProbeArgs.previousTailHash = $Task.lastSeenTailHash }
        if ($Task.lastSeenOutlineHash) { $ProbeArgs.previousOutlineHash = $Task.lastSeenOutlineHash }
        if ($Task.lastSeenScrollHeight -gt 0) { $ProbeArgs.previousScrollHeight = [int]$Task.lastSeenScrollHeight }
        if ($Task.lastProgressAt) { $ProbeArgs.lastProgressAt = $Task.lastProgressAt }
        $Probe = Invoke-BridgeTool -Tool 'read_.browser.chatgpt.watch.probe' -Arguments $ProbeArgs -TaskId $TaskId
        $ToolsUsed += 'read_.browser.chatgpt.watch.probe'
        $InternalStepCount++
        Update-TaskAndChatFromProbe -Task $Task -Chat $Chat -Probe $Probe.result
        Write-Host ("progress " + ([ordered]@{ event = 'internalPoll'; tool = 'read_.browser.chatgpt.watch.probe'; status = $Probe.result.status; watchNextAction = $Probe.result.decision.next_action; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 30 -Compress))

        $StepArgs = [ordered]@{
            workspacePath = $TargetRepo
            preferredChatId = $Task.chatId
            requireChatId = $false
            maxMessages = 40
            timeoutMs = 5000
            phase = 'reply_watch'
            taskClass = 'normal_answer'
            iteration = [int]$Task.interactionCount
            maxIterations = $MaxIterations
            sentAt = $Task.sentAt
            attempt = [int]$Task.attempt
            executePreAsk = $false
        }
        if (-not $Task.chatId) { $StepArgs.Remove('preferredChatId') }
        $StepSummary = Invoke-BridgeTool -Tool 'read_.browser.chatgpt.run.loop.step.summary' -Arguments $StepArgs -TaskId $TaskId
        $ToolsUsed += 'read_.browser.chatgpt.run.loop.step.summary'
        $InternalStepCount++
        Write-Host ("progress " + ([ordered]@{ event = 'internalPoll'; tool = 'read_.browser.chatgpt.run.loop.step.summary'; status = $StepSummary.result.status; nextAction = $StepSummary.result.next_action; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))
        $Ready = Test-CaptureReady -ProbeResult $Probe.result -StepResult $StepSummary.result
        $QuietEmptyBinding = Test-QuietEmptyCaptureBinding -ProbeResult $Probe.result -StepResult $StepSummary.result
        $ShadowObservation = Write-LiveShadowBrowserObservationArtifact -TaskId $TaskId -Probe $Probe.result -Step $StepSummary.result -Authoritative ([ordered]@{ readyForCapture = [bool]$Ready; quietEmptyBinding = [bool]$QuietEmptyBinding })
        Write-Host ("progress " + ([ordered]@{ event = 'liveShadowBrowserObservation'; status = $ShadowObservation.status; state = $ShadowObservation.state; authoritative = $false; artifactPath = $ShadowObservation.path; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))
        $InteractionStepStart = if ($null -ne (Get-OptionalProperty -InputObject $Task -Name 'currentInteractionStartStep')) { [int]$Task.currentInteractionStartStep } else { 0 }
        $InteractionStepCount = $InternalStepCount - $InteractionStepStart
        if (-not $Ready -and $QuietEmptyBinding) {
            $Task.status = 'terminal_failed'
            $FinalStatus = 'CAPTURE_SELECTOR_EMPTY_OR_BINDING_STALE'
            $Task | Add-Member -NotePropertyName lastFailure -NotePropertyValue ([pscustomobject][ordered]@{ status = $FinalStatus; probeStatus = $Probe.result.status; stepStatus = $StepSummary.result.status; chatId = $Task.chatId; targetId = $Task.targetId; capturedAt = Get-IsoNow }) -Force
            Append-Journal -TaskId $TaskId -Event 'captureSelectorEmptyOrBindingStale' -Data ([ordered]@{ finalStatus = $FinalStatus; probeStatus = $Probe.result.status; stepStatus = $StepSummary.result.status; chatId = $Task.chatId; targetId = $Task.targetId })
            $null = Write-LiveShadowRecoveryArtifact -Task $Task -TaskId $TaskId -Stage 'answer_capture' -Reason $FinalStatus -Receipt ([ordered]@{ probe = $Probe.result; step = $StepSummary.result })
            Write-JsonFile -Value $Task -Path $TaskPath
            Write-JsonFile -Value $Chat -Path $ChatPath
            Write-Host ("progress " + ([ordered]@{ event = 'captureSelectorEmptyOrBindingStale'; finalStatus = $FinalStatus; probeStatus = $Probe.result.status; stepStatus = $StepSummary.result.status; chatId = $Task.chatId; targetId = $Task.targetId; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))
            break
        }
        if (-not $Ready -and $InteractionStepCount -ge $MaxInternalStepsPerInteraction) {
            $Task.status = 'terminal_failed'
            $FinalStatus = 'ANSWER_WATCH_INTERNAL_STEP_LIMIT_EXCEEDED'
            $Task | Add-Member -NotePropertyName lastFailure -NotePropertyValue ([pscustomobject][ordered]@{ status = $FinalStatus; interactionStepCount = $InteractionStepCount; maxInternalStepsPerInteraction = $MaxInternalStepsPerInteraction; probeStatus = $Probe.result.status; stepStatus = $StepSummary.result.status; stepNextAction = $StepSummary.result.next_action; capturedAt = Get-IsoNow }) -Force
            Append-Journal -TaskId $TaskId -Event 'answerWatchStepLimitExceeded' -Data ([ordered]@{ finalStatus = $FinalStatus; interactionStepCount = $InteractionStepCount; maxInternalStepsPerInteraction = $MaxInternalStepsPerInteraction; probeStatus = $Probe.result.status; stepStatus = $StepSummary.result.status; stepNextAction = $StepSummary.result.next_action })
            $null = Write-LiveShadowRecoveryArtifact -Task $Task -TaskId $TaskId -Stage 'answer_capture' -Reason $FinalStatus -Receipt ([ordered]@{ probe = $Probe.result; step = $StepSummary.result })
            Write-JsonFile -Value $Task -Path $TaskPath
            Write-JsonFile -Value $Chat -Path $ChatPath
            Write-Host ("progress " + ([ordered]@{ event = 'answerWatchStepLimitExceeded'; finalStatus = $FinalStatus; interactionStepCount = $InteractionStepCount; maxInternalStepsPerInteraction = $MaxInternalStepsPerInteraction; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))
            break
        }
        if (-not $Ready) {
            $NextMs = if ($Probe.result.decision.next_probe_after_ms) { [int]$Probe.result.decision.next_probe_after_ms } else { $PollIntervalMs }
            $ClampedNextMs = [Math]::Min([Math]::Max(1000, $NextMs), $PollIntervalMs)
            $Task.nextPollAt = (Get-Date).AddMilliseconds($ClampedNextMs).ToUniversalTime().ToString('o')
            $Task.updatedAt = Get-IsoNow
            Write-JsonFile -Value $Task -Path $TaskPath
            Write-JsonFile -Value $Chat -Path $ChatPath
            continue
        }

        Write-Host ("progress " + ([ordered]@{ event = 'answerReady'; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount; assistantHash = $Task.lastAssistantHash; readySource = 'capture_ready_or_status' } | ConvertTo-Json -Depth 20 -Compress))
        $SettleArgs = [ordered]@{
            expectedTargetId = $Task.targetId
            requireChatId = $false
            maxMessages = 40
            timeoutMs = 5000
            readinessProfile = 'rc_gate'
            maxWaitMs = 120000
            observationBudgetMs = 45000
            pollMs = 2000
            requireComposerSendMode = $false
        }
        if ($Task.chatId) { $SettleArgs.preferredChatId = $Task.chatId }
        if ($Task.currentCycleBaselineAssistantHash) { $SettleArgs.baselineAssistantHash = $Task.currentCycleBaselineAssistantHash }
        $Settled = Invoke-BridgeTool -Tool 'read_.browser.chatgpt.answer.settle' -Arguments $SettleArgs -TaskId $TaskId
        $ToolsUsed += 'read_.browser.chatgpt.answer.settle'
        $InternalStepCount++
        if ($Settled.result.selected -and $Settled.result.selected.chat_id) {
            $SelectedChatId = [string]$Settled.result.selected.chat_id
            if (-not $Task.lockedChatId) {
                $Task.lockedChatId = $SelectedChatId
            } elseif ($SelectedChatId -ne $Task.lockedChatId) {
                $Task.status = 'terminal_failed'
                $FinalStatus = 'SINGLE_CHAT_REBIND_FAILED'
                $Task | Add-Member -NotePropertyName lastFailure -NotePropertyValue ([pscustomobject][ordered]@{ status = $FinalStatus; expectedChatId = $Task.lockedChatId; actualChatId = $SelectedChatId; resultPath = $Settled.resultPath; capturedAt = Get-IsoNow }) -Force
                Append-Journal -TaskId $TaskId -Event 'singleChatViolation' -Data ([ordered]@{ expectedChatId = $Task.lockedChatId; actualChatId = $SelectedChatId; resultPath = $Settled.resultPath })
                Write-JsonFile -Value $Task -Path $TaskPath
                Write-JsonFile -Value $Chat -Path $ChatPath
                break
            }
            $Task.chatId = $SelectedChatId
            $Chat.chatId = $Task.chatId
            $Chat.url = "https://chatgpt.com/c/$SelectedChatId"
            $ObservedChatIds += $SelectedChatId
        }
        if ($Settled.result.selected -and $Settled.result.selected.id) { $Task.targetId = [string]$Settled.result.selected.id; $Chat.targetId = $Task.targetId }

        $Answer = ConvertTo-NormalizedAnswer -Settled $Settled.result -TaskId $TaskId -ChatId $Task.chatId -TargetId $Task.targetId
        $AnswerPath = Join-Path $AnswerDir ($TaskId + '-' + ([guid]::NewGuid().ToString('N')) + '.answer.json')
        Write-JsonFile -Value ([pscustomobject]$Answer) -Path $AnswerPath
        $AnswerRecords += [pscustomobject]@{
            path = $AnswerPath
            assistantStatus = [string]$Answer.assistantStatus
            semanticStatus = [string]$Answer.semanticStatus
            textLength = [int]$Answer.latestAssistantTextLength
            chatId = $Task.chatId
            captured = [bool]$Answer.assistantCaptured
        }
        $LastAssistantStatus = [string]$Answer.assistantStatus
        $LastSemanticStatus = [string]$Answer.semanticStatus
        $ReadyToDelete = Get-ReadyToDeleteSignal -AssistantText ([string]$Answer.assistantText)
        $Task | Add-Member -NotePropertyName readyToDelete -NotePropertyValue $ReadyToDelete -Force
        if (-not $Answer.assistantCaptured) {
            $Task.status = 'terminal_failed'
            $FinalStatus = if ($LastAssistantStatus -eq 'OBSERVATION_WINDOW_EXPIRED') { 'ANSWER_CAPTURE_OBSERVATION_WINDOW_EXPIRED' } else { 'ANSWER_CAPTURE_EMPTY_TEXT' }
            $Task | Add-Member -NotePropertyName lastFailure -NotePropertyValue ([pscustomobject][ordered]@{ status = $FinalStatus; assistantStatus = $LastAssistantStatus; textLength = [int]$Answer.latestAssistantTextLength; answerPath = $AnswerPath; capturedAt = Get-IsoNow }) -Force
            Append-Journal -TaskId $TaskId -Event 'answerCaptureRejected' -Data ([ordered]@{ finalStatus = $FinalStatus; assistantStatus = $LastAssistantStatus; textLength = [int]$Answer.latestAssistantTextLength; answerPath = $AnswerPath })
            $null = Write-LiveShadowRecoveryArtifact -Task $Task -TaskId $TaskId -Stage 'answer_capture' -Reason $FinalStatus -Receipt ([ordered]@{ assistantStatus = $LastAssistantStatus; semanticStatus = $LastSemanticStatus; answerPath = $AnswerPath })
            Write-JsonFile -Value $Task -Path $TaskPath
            Write-JsonFile -Value $Chat -Path $ChatPath
            Write-Host ("progress " + ([ordered]@{ event = 'answerCaptureRejected'; assistantStatus = $LastAssistantStatus; semanticStatus = $LastSemanticStatus; finalStatus = $FinalStatus; answerPath = $AnswerPath; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))
            break
        }
        $AssistantCapturedCount++
        $Task.lastAssistantHash = [string]$Answer.latestAssistantHash
        $Task.lastAssistantTextLength = [int]$Answer.latestAssistantTextLength
        $Task.lastProgressAt = Get-IsoNow
        $Chat.lastAssistantHash = $Task.lastAssistantHash
        $Chat.lastAssistantCapturedAt = Get-IsoNow
        Write-Host ("progress " + ([ordered]@{ event = 'answerCaptured'; assistantStatus = $LastAssistantStatus; semanticStatus = $LastSemanticStatus; answerPath = $AnswerPath; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))

        $AdapterRaw = & $RunnerAdapter -Task $TaskTaskText -MaxIterations $MaxIterations -AnswerCaptureResultPath $AnswerPath -ResponseTaskId $TaskId -ResponseChatId $Task.chatId -ResponseTargetId $Task.targetId 2>&1
        $AdapterResult = $AdapterRaw | ConvertFrom-Json
        $DecisionStages += @('runner-adapter','answer-capture-intake')
        $InternalStepCount++
        $Task.interactionCount = [int]$Task.interactionCount + 1
        $DecisionNextAction = if ($ReadyToDelete -eq $true) { 'stop_loop' } elseif ($Task.interactionCount -ge $Task.maxInteractions) { 'stop_loop' } elseif ($LastSemanticStatus -eq 'REFUSAL') { 'stop_loop' } else { 'dispatch_next_ui_interaction' }
        $Task.decisionState = [pscustomobject]@{
            status = if ($DecisionNextAction -eq 'stop_loop') { 'terminal_or_budget' } else { 'next_interaction_ready' }
            adapterStatus = $AdapterResult.finalActionResult.status
            semanticStatus = $LastSemanticStatus
            nextAction = $DecisionNextAction
            nextDispatchContract = if ($DecisionNextAction -eq 'dispatch_next_ui_interaction') { New-CmcpDispatchContract -RawCommand $ContinuePrompt -ChatId $Task.chatId -EffectivePromptMode $ContinuePromptMode } else { $null }
        }
        $Task.status = if ($DecisionNextAction -eq 'stop_loop') { if ($LastSemanticStatus -eq 'REFUSAL') { 'semantic_refused' } else { 'terminal_success' } } else { 'ready_next_interaction' }
        $LegacyDecisionStatus = if ($DecisionNextAction -eq 'dispatch_next_ui_interaction') { 'continue' } elseif ($LastSemanticStatus -eq 'REFUSAL') { 'refusal' } else { $null }
        $LegacyStopReason = if ($Task.interactionCount -ge $Task.maxInteractions) { 'max_rounds' } elseif ($LastSemanticStatus -eq 'REFUSAL') { 'refusal' } else { $null }
        $LegacyDecisionReceipt = [ordered]@{
            continue = ($DecisionNextAction -eq 'dispatch_next_ui_interaction')
            terminal = ($DecisionNextAction -eq 'stop_loop')
            decisionStatus = $LegacyDecisionStatus
            stopReason = $LegacyStopReason
        }
        $Parity = Write-LiveShadowParityArtifact -Task $Task -Answer ([pscustomobject]$Answer) -Authoritative $LegacyDecisionReceipt -TaskId $TaskId
        Write-Host ("progress " + ([ordered]@{ event = 'liveShadowParity'; status = $Parity.status; authoritative = $false; artifactPath = $Parity.path; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))
        $Chat.status = $Task.status
        $Task.updatedAt = Get-IsoNow
        Write-JsonFile -Value $Task -Path $TaskPath
        Write-JsonFile -Value $Chat -Path $ChatPath
        Write-Host ("progress " + ([ordered]@{ event = 'decisionApplied'; adapterStatus = $AdapterResult.finalActionResult.status; semanticStatus = $LastSemanticStatus; nextAction = $DecisionNextAction; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 30 -Compress))
        if ($DecisionNextAction -eq 'dispatch_next_ui_interaction') {
            Write-Host ("progress " + ([ordered]@{ event = 'nextInteractionScheduled'; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))
        } else {
            $CleanupResult = $null
            if ($ReadyToDelete -eq $true -and $Task.chatId -and -not ([string]$Task.chatId).StartsWith('WEB:', [System.StringComparison]::OrdinalIgnoreCase)) {
                $DeleteArgs = [ordered]@{
                    expectedChatId = [string]$Task.chatId
                    authorizationMode = 'lifecycle_ready_to_delete'
                    readyToDelete = $true
                    closeTarget = $true
                    timeoutMs = 5000
                }
                for ($CleanupAttempt = 1; $CleanupAttempt -le 3; $CleanupAttempt++) {
                    $Cleanup = Invoke-BridgeTool -Tool 'write.browser.chatgpt.chat.delete.execute' -Arguments $DeleteArgs -TaskId $TaskId
                    $ToolsUsed += 'write.browser.chatgpt.chat.delete.execute'
                    $InternalStepCount++
                    $CleanupResult = $Cleanup.result
                    if ($CleanupResult.ok -eq $true) { break }
                    if ($CleanupAttempt -lt 3) { Start-Sleep -Seconds 2 }
                }
                $Task | Add-Member -NotePropertyName cleanupResult -NotePropertyValue $CleanupResult -Force
                Append-Journal -TaskId $TaskId -Event 'conversationCleanup' -Data ([ordered]@{ readyToDelete = $true; chatId = $Task.chatId; cleanupStatus = if ($CleanupResult) { [string]$CleanupResult.status } else { 'not_run' }; cleanupOk = ($CleanupResult -and $CleanupResult.ok -eq $true) })
                Write-Host ("progress " + ([ordered]@{ event = 'conversationCleanup'; chatId = $Task.chatId; cleanupStatus = if ($CleanupResult) { [string]$CleanupResult.status } else { 'not_run' }; cleanupOk = ($CleanupResult -and $CleanupResult.ok -eq $true); interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))
            }
            $FinalStatus = if ($ReadyToDelete -eq $true) { 'TASK_BANK_TASK_COMPLETE_READY_TO_DELETE' } elseif ($Task.interactionCount -ge $Task.maxInteractions) { 'TASK_BANK_INTERACTION_BUDGET_EXHAUSTED' } else { 'TASK_BANK_TASK_TERMINAL' }
            Write-Host ("progress " + ([ordered]@{ event = 'taskTerminal'; finalStatus = $FinalStatus; readyToDelete = $ReadyToDelete; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))
            break
        }
    }
}

$Task.updatedAt = Get-IsoNow
Write-JsonFile -Value $Task -Path $TaskPath
Write-JsonFile -Value $Chat -Path $ChatPath
$ActiveTasks = @($Task | Where-Object { $_.status -notin @('terminal_success','terminal_failed','semantic_blocked','interaction_budget_exhausted') })
$CompletedTasks = @($Task | Where-Object { $_.status -in @('terminal_success','interaction_budget_exhausted') })
$SemanticFailed = $LastSemanticStatus -eq 'REFUSAL'
$Acceptance = Write-AcceptanceArtifact -Task $Task -Chat $Chat -Answers $AnswerRecords -ObservedChatIds $ObservedChatIds -SubmittedCount $SubmittedCount -AssistantCapturedCount $AssistantCapturedCount -InternalStepCount $InternalStepCount -FinalStatus $FinalStatus
$AcceptanceArtifact = $Acceptance.artifact
$AcceptancePath = $Acceptance.path
$ShadowAcceptanceInputPath = Join-Path $AcceptanceDir ($Task.taskId + '-shadow-input.json')
$ShadowAcceptancePath = Join-Path $AcceptanceDir ($Task.taskId + '-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '.shadow-acceptance.json')
$ShadowStopReason = if ($FinalStatus -eq 'TASK_BANK_INTERACTION_BUDGET_EXHAUSTED') { 'max_rounds' } elseif ($LastSemanticStatus -eq 'REFUSAL') { 'refusal' } else { $null }
$ShadowAcceptanceInput = [ordered]@{
    interactionCount = [int]$Task.interactionCount
    maxInteractions = $MaxIterations
    submittedCount = [int]$SubmittedCount
    assistantCapturedCount = [int]$AssistantCapturedCount
    stopReason = $ShadowStopReason
    completionVerified = $false
    repositoryVerified = $false
}
Write-JsonFile -Value ([pscustomobject]$ShadowAcceptanceInput) -Path $ShadowAcceptanceInputPath
try {
    $ShadowAcceptanceRaw = & php (Join-Path $Root 'tool/shadow-acceptance-capture.php') "--input=$ShadowAcceptanceInputPath" "--output=$ShadowAcceptancePath" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "shadow acceptance capture exit code $LASTEXITCODE`: $ShadowAcceptanceRaw" }
    $ShadowAcceptanceResult = $ShadowAcceptanceRaw | ConvertFrom-Json
    $ShadowAcceptanceArtifact = Read-JsonFile -Path $ShadowAcceptancePath
} catch {
    $ShadowAcceptanceResult = [pscustomobject]@{ ok = $false; status = 'SHADOW_ACCEPTANCE_CAPTURE_FAILED_NON_AUTHORITATIVE'; taskComplete = $false }
    $ShadowAcceptanceArtifact = [pscustomobject]@{ taskAcceptance = [pscustomobject]@{ complete = $false }; status = 'SHADOW_ACCEPTANCE_CAPTURE_FAILED_NON_AUTHORITATIVE' }
    Append-Journal -TaskId $TaskId -Event 'shadowAcceptanceDiagnosticFailure' -Data ([ordered]@{ error = $_.Exception.Message; authoritative = $false })
}
$Ok = [bool]$AcceptanceArtifact.ok
$OutputStatus = if ($Ok) { 'TASK_BANK_LOOP_COMPLETED' } else { 'TASK_BANK_LOOP_FAILED' }
$OutputFinalStatus = if ($Ok) {
    'M3_ACCEPTANCE_PASS'
} elseif ($LastSemanticStatus -eq 'REFUSAL') {
    $LastSemanticStatus
} elseif ($FinalStatus -and $FinalStatus -notin @('TASK_BANK_LOOP_STARTED','TASK_BANK_INTERACTION_BUDGET_EXHAUSTED','TASK_BANK_TASK_TERMINAL')) {
    $FinalStatus
} elseif (@($AcceptanceArtifact.failures) -contains 'empty_answer_capture') {
    'ANSWER_CAPTURE_EMPTY_TEXT'
} elseif (@($AcceptanceArtifact.failures) -contains 'observation_window_expired') {
    'ANSWER_CAPTURE_OBSERVATION_WINDOW_EXPIRED'
} else {
    [string]$AcceptanceArtifact.status
}

[pscustomobject]@{
    ok = [bool]$Ok
    status = $OutputStatus
    targetRepo = $TargetRepo
    maxIterations = $MaxIterations
    interactionCycleCount = [int]$Task.interactionCount
    internalStepCount = [int]$InternalStepCount
    taskCount = 1
    activeTaskCount = @($ActiveTasks).Count
    completedTaskCount = @($CompletedTasks).Count
    chatId = $Task.chatId
    targetId = $Task.targetId
    submittedCount = [int]$SubmittedCount
    assistantCapturedCount = [int]$AssistantCapturedCount
    lastAssistantStatus = $LastAssistantStatus
    lastSemanticStatus = $LastSemanticStatus
    decisionStagesUsed = @($DecisionStages | Select-Object -Unique)
    toolsUsed = @($ToolsUsed | Select-Object -Unique)
    finalStatus = $OutputFinalStatus
    acceptanceStatus = [string]$AcceptanceArtifact.status
    acceptanceFailures = @($AcceptanceArtifact.failures)
    acceptanceArtifactPath = $AcceptancePath
    taskBankPath = $TaskBankRoot
    chatBankPath = $ChatBankRoot
    runnerStatePath = $RunnerStatePath
    readyToDelete = if ($Task.PSObject.Properties.Name -contains 'readyToDelete') { $Task.readyToDelete } else { $null }
    cleanupStatus = if ($Task.PSObject.Properties.Name -contains 'cleanupResult' -and $Task.cleanupResult) { [string]$Task.cleanupResult.status } else { $null }
    nextAction = if ($Ok) { 'task_bank_loop_completed' } else { 'inspect_acceptance_artifact' }
} | ConvertTo-Json -Depth 100
