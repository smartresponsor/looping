param(
    [Parameter(Mandatory=$true)][string]$TargetRepo,
    [Parameter(Mandatory=$true)][int]$MaxIterations,
    [Parameter(Mandatory=$true)][string]$Name
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

function Append-Journal {
    param([string]$TaskId, [string]$Event, $Data)
    $Path = Join-Path $JournalDir ($TaskId + '.ndjson')
    $Line = [ordered]@{ at = Get-IsoNow; event = $Event; data = $Data }
    ($Line | ConvertTo-Json -Depth 80 -Compress) | Add-Content -Path $Path -Encoding UTF8
}

function New-CmcpDispatchContract {
    param([string]$RawCommand, [string]$ChatId)
    $Arguments = [ordered]@{
        rawCommand = $RawCommand
        workspacePath = $TargetRepo
        componentName = $Name
        maxAutoIterations = $MaxIterations
        activate = $true
        confirmGo = $true
        allowOverwrite = $false
        promptMode = 'raw'
        executorMode = 'browser'
        timeoutMs = 30000
    }
    if ($ChatId) { $Arguments.url = "https://chatgpt.com/c/$ChatId" }
    [ordered]@{
        ok = $true
        status = 'TASK_BANK_UI_INTERACTION_CONTRACT_READY'
        stage = 'ui_interaction_submit'
        tool = 'console.write.browser.session.cmcp.go'
        arguments = $Arguments
        mutation = 'write'
        confirmationRequired = $false
        execution = 'external_console_mcp_required'
        nextAction = 'dispatch_ui_interaction_submit'
    }
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
    if ($Tool -ne 'console.write.browser.session.cmcp.go') { throw "task-bank UI submit expected cmcp.go, got $Tool" }
    $BridgeRaw = & $Bridge -PayloadPath $DaemonPayload.dispatchPayloadPath -ResultPath $DaemonPayload.expectedResultPath 2>&1
    $BridgePayload = $BridgeRaw | ConvertFrom-Json
    $Result = Read-JsonFile -Path $DaemonPayload.expectedResultPath
    $AdapterRaw = & $TransportAdapter -Task $Task -MaxIterations $MaxIterations -PayloadPath $DaemonPayload.dispatchPayloadPath -ResultPath $DaemonPayload.expectedResultPath 2>&1
    $AdapterPayload = $AdapterRaw | ConvertFrom-Json
    Append-Journal -TaskId $TaskId -Event 'uiSubmit' -Data ([ordered]@{ tool = $Tool; dispatchStatus = $DaemonPayload.status; bridgeStatus = $BridgePayload.status; resultStatus = $Result.status; adapterStatus = $AdapterPayload.status })
    [pscustomobject]@{ tool = $Tool; daemon = $DaemonPayload; bridge = $BridgePayload; result = $Result; adapter = $AdapterPayload }
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

function ConvertTo-NormalizedAnswer {
    param($Settled, [string]$TaskId, [string]$ChatId, [string]$TargetId)
    $Latest = $Settled.latest_assistant
    $Text = if ($Latest -and $Latest.text) { [string]$Latest.text } else { '' }
    $Json = Get-AssistantJson -Text $Text
    $AssistantStatus = [string]$Settled.status
    $SemanticStatus = Get-SemanticStatus -AssistantJson $Json -AssistantText $Text -AssistantStatus $AssistantStatus
    [ordered]@{
        ok = ($Settled.ok -eq $true)
        status = 'ENGINE_ANSWER_CAPTURED'
        task_id = $TaskId
        assistantCaptured = ($Text.Length -gt 0)
        assistantText = $Text
        assistantJson = $Json
        assistantOk = ($Settled.ok -eq $true)
        assistantStatus = $AssistantStatus
        semanticStatus = $SemanticStatus
        semanticNextAction = if ($SemanticStatus -in @('TOOL_CALL_BLOCKED','REFUSAL')) { 'stop_loop' } else { 'continue_or_stop_by_budget' }
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
        chatId = $null
        targetId = $null
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
        chatId = $null
        targetId = $null
        taskId = $TaskId
        url = $null
        status = 'created'
        lastBindAt = $null
        lastProbeAt = $null
        composerState = $null
        lastAssistantHash = $null
        lastAssistantCapturedAt = $null
        recoveryAttempt = 0
    }
}

Ensure-Dir $TaskDir
Ensure-Dir $JournalDir
Ensure-Dir $AnswerDir
Ensure-Dir $BridgeDir
Ensure-Dir $ChatDir
Ensure-Dir $RunnerStateDir

$TaskId = 'repo-smoke-' + (Get-Hash ($TargetRepo.ToLowerInvariant() + '|' + $Name)).Substring(0, 16)
$TaskPath = Join-Path $TaskDir ($TaskId + '.json')
$ChatPath = Join-Path $ChatDir ($TaskId + '.json')
$Task = New-TaskRecord -TaskId $TaskId
$Chat = New-ChatRecord -TaskId $TaskId
$TaskTaskText = "Task-bank product loop. Name: $Name. Target workspace: $TargetRepo. Goal: read-only repository loop smoke; avoid file changes; avoid commits."
$InitialPrompt = "Run a read-only repository loop smoke for workspace $TargetRepo. Use only safe inspection. Do not edit files. Do not commit. Return strict JSON with ok, status, tool, workspacePath, and summary."
$SubmittedCount = 0
$AssistantCapturedCount = 0
$InternalStepCount = 0
$ToolsUsed = @()
$DecisionStages = @('task-bank', 'chat-bank', 'round-robin-scheduler')
$LastAssistantStatus = $null
$LastSemanticStatus = $null
$FinalStatus = 'TASK_BANK_LOOP_STARTED'
$StartedAt = Get-Date
$MaxElapsedSeconds = [Math]::Max(240, $MaxIterations * 180)

Write-JsonFile -Value $Task -Path $TaskPath
Write-JsonFile -Value $Chat -Path $ChatPath
Append-Journal -TaskId $TaskId -Event 'taskCreated' -Data ([ordered]@{ taskPath = $TaskPath; chatPath = $ChatPath })
Write-Host ("progress " + ([ordered]@{ event = 'taskCreated'; taskId = $TaskId; taskBankPath = $TaskPath; chatBankPath = $ChatPath } | ConvertTo-Json -Depth 20 -Compress))

while ($true) {
    if (((Get-Date) - $StartedAt).TotalSeconds -gt $MaxElapsedSeconds) {
        $Task.status = 'bounded_timeout'
        $FinalStatus = 'TASK_BANK_LOOP_BOUNDED_TIMEOUT'
        break
    }
    if ($Task.interactionCount -ge $Task.maxInteractions) {
        $Task.status = 'interaction_budget_exhausted'
        $FinalStatus = 'TASK_BANK_INTERACTION_BUDGET_EXHAUSTED'
        break
    }
    if ($Task.status -in @('terminal_success','terminal_failed','semantic_blocked')) { break }

    if ($Task.status -in @('created','ready_next_interaction')) {
        if ($Task.targetId) {
            $PreflightArgs = [ordered]@{ expectedTargetId = $Task.targetId; timeoutMs = 5000 }
            $Preflight = Invoke-BridgeTool -Tool 'console.read_.browser.chatgpt.composer.preflight' -Arguments $PreflightArgs -TaskId $TaskId
            $ToolsUsed += 'console.read_.browser.chatgpt.composer.preflight'
            $InternalStepCount++
            Write-Host ("progress " + ([ordered]@{ event = 'internalPoll'; tool = 'console.read_.browser.chatgpt.composer.preflight'; status = $Preflight.result.status; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))
        }
        $RawCommand = if ($Task.interactionCount -eq 0) { $InitialPrompt } else { "Continue the read-only repository loop smoke for workspace $TargetRepo. Use the previous assistant answer as context. Do not edit files. Do not commit. Return strict JSON with ok, status, tool, workspacePath, summary, and nextAction." }
        $Contract = New-CmcpDispatchContract -RawCommand $RawCommand -ChatId $Task.chatId
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
            Write-JsonFile -Value $Task -Path $TaskPath
            break
        }
        $SubmittedCount++
        $Task.status = 'waiting_answer'
        $Task.sentAt = Get-IsoNow
        if ($Submit.result.cmcp_go_trace -and $Submit.result.cmcp_go_trace.opened_target_id) { $Task.targetId = [string]$Submit.result.cmcp_go_trace.opened_target_id }
        if ($Submit.result.cmcp_go_trace -and $Submit.result.cmcp_go_trace.opened_chat_id) { $Task.chatId = [string]$Submit.result.cmcp_go_trace.opened_chat_id }
        $Chat.targetId = $Task.targetId
        $Chat.chatId = $Task.chatId
        $Chat.url = if ($Task.chatId) { "https://chatgpt.com/c/$($Task.chatId)" } else { 'https://chatgpt.com/' }
        $Chat.status = 'waiting_answer'
        $Chat.lastBindAt = Get-IsoNow
        $Task.nextPollAt = (Get-Date).AddSeconds(35).ToUniversalTime().ToString('o')
        $Task.updatedAt = Get-IsoNow
        Write-JsonFile -Value $Task -Path $TaskPath
        Write-JsonFile -Value $Chat -Path $ChatPath
        Write-Host ("progress " + ([ordered]@{ event = 'uiSubmit'; submitted = $true; submittedCount = $SubmittedCount; chatId = $Task.chatId; targetId = $Task.targetId; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))
    }

    if ($Task.status -eq 'waiting_answer') {
        $Now = Get-Date
        $Due = [datetime]::Parse($Task.nextPollAt).ToUniversalTime()
        if ($Now.ToUniversalTime() -lt $Due) {
            $SleepSeconds = [Math]::Min(35, [Math]::Max(1, [int][Math]::Ceiling(($Due - $Now.ToUniversalTime()).TotalSeconds)))
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
        $Probe = Invoke-BridgeTool -Tool 'console.read_.browser.chatgpt.watch.probe' -Arguments $ProbeArgs -TaskId $TaskId
        $ToolsUsed += 'console.read_.browser.chatgpt.watch.probe'
        $InternalStepCount++
        Update-TaskAndChatFromProbe -Task $Task -Chat $Chat -Probe $Probe.result
        Write-Host ("progress " + ([ordered]@{ event = 'internalPoll'; tool = 'console.read_.browser.chatgpt.watch.probe'; status = $Probe.result.status; watchNextAction = $Probe.result.decision.next_action; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 30 -Compress))

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
        $StepSummary = Invoke-BridgeTool -Tool 'console.read_.browser.chatgpt.run.loop.step.summary' -Arguments $StepArgs -TaskId $TaskId
        $ToolsUsed += 'console.read_.browser.chatgpt.run.loop.step.summary'
        $InternalStepCount++
        Write-Host ("progress " + ([ordered]@{ event = 'internalPoll'; tool = 'console.read_.browser.chatgpt.run.loop.step.summary'; status = $StepSummary.result.status; nextAction = $StepSummary.result.next_action; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))

        $Ready = ($Probe.result.decision.next_action -eq 'RUN_STABLE_CAPTURE' -or $StepSummary.result.next_action -eq 'RUN_STABLE_CAPTURE')
        if (-not $Ready) {
            $NextMs = if ($Probe.result.decision.next_probe_after_ms) { [int]$Probe.result.decision.next_probe_after_ms } else { 35000 }
            $Task.nextPollAt = (Get-Date).AddMilliseconds([Math]::Max(35000, $NextMs)).ToUniversalTime().ToString('o')
            $Task.updatedAt = Get-IsoNow
            Write-JsonFile -Value $Task -Path $TaskPath
            Write-JsonFile -Value $Chat -Path $ChatPath
            continue
        }

        Write-Host ("progress " + ([ordered]@{ event = 'answerReady'; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount; assistantHash = $Task.lastAssistantHash } | ConvertTo-Json -Depth 20 -Compress))
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
        $Settled = Invoke-BridgeTool -Tool 'console.read_.browser.chatgpt.answer.settle' -Arguments $SettleArgs -TaskId $TaskId
        $ToolsUsed += 'console.read_.browser.chatgpt.answer.settle'
        $InternalStepCount++
        if ($Settled.result.selected -and $Settled.result.selected.chat_id) { $Task.chatId = [string]$Settled.result.selected.chat_id; $Chat.chatId = $Task.chatId }
        if ($Settled.result.selected -and $Settled.result.selected.id) { $Task.targetId = [string]$Settled.result.selected.id; $Chat.targetId = $Task.targetId }

        $Answer = ConvertTo-NormalizedAnswer -Settled $Settled.result -TaskId $TaskId -ChatId $Task.chatId -TargetId $Task.targetId
        $AnswerPath = Join-Path $AnswerDir ($TaskId + '-' + ([guid]::NewGuid().ToString('N')) + '.answer.json')
        Write-JsonFile -Value ([pscustomobject]$Answer) -Path $AnswerPath
        $AssistantCapturedCount++
        $LastAssistantStatus = [string]$Answer.assistantStatus
        $LastSemanticStatus = [string]$Answer.semanticStatus
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
        $DecisionNextAction = if ($Task.interactionCount -ge $Task.maxInteractions) { 'stop_loop' } elseif ($LastSemanticStatus -in @('TOOL_CALL_BLOCKED','REFUSAL')) { 'stop_loop' } else { 'dispatch_next_ui_interaction' }
        $Task.decisionState = [pscustomobject]@{
            status = if ($DecisionNextAction -eq 'stop_loop') { 'terminal_or_budget' } else { 'next_interaction_ready' }
            adapterStatus = $AdapterResult.finalActionResult.status
            semanticStatus = $LastSemanticStatus
            nextAction = $DecisionNextAction
            nextDispatchContract = if ($DecisionNextAction -eq 'dispatch_next_ui_interaction') { New-CmcpDispatchContract -RawCommand "Continue the read-only repository loop smoke for workspace $TargetRepo based on the captured assistant answer. Do not edit files. Do not commit. Return strict JSON with ok, status, tool, workspacePath, summary, and nextAction." -ChatId $Task.chatId } else { $null }
        }
        $Task.status = if ($DecisionNextAction -eq 'stop_loop') { if ($LastSemanticStatus -in @('TOOL_CALL_BLOCKED','REFUSAL')) { 'semantic_blocked' } else { 'terminal_success' } } else { 'ready_next_interaction' }
        $Chat.status = $Task.status
        $Task.updatedAt = Get-IsoNow
        Write-JsonFile -Value $Task -Path $TaskPath
        Write-JsonFile -Value $Chat -Path $ChatPath
        Write-Host ("progress " + ([ordered]@{ event = 'decisionApplied'; adapterStatus = $AdapterResult.finalActionResult.status; semanticStatus = $LastSemanticStatus; nextAction = $DecisionNextAction; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 30 -Compress))
        if ($DecisionNextAction -eq 'dispatch_next_ui_interaction') {
            Write-Host ("progress " + ([ordered]@{ event = 'nextInteractionScheduled'; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))
        } else {
            $FinalStatus = if ($Task.interactionCount -ge $Task.maxInteractions) { 'TASK_BANK_INTERACTION_BUDGET_EXHAUSTED' } else { 'TASK_BANK_TASK_TERMINAL' }
            Write-Host ("progress " + ([ordered]@{ event = 'taskTerminal'; finalStatus = $FinalStatus; interactionCycleCount = $Task.interactionCount; internalStepCount = $InternalStepCount } | ConvertTo-Json -Depth 20 -Compress))
            break
        }
    }
}

$Task.updatedAt = Get-IsoNow
Write-JsonFile -Value $Task -Path $TaskPath
Write-JsonFile -Value $Chat -Path $ChatPath
$ActiveTasks = @($Task | Where-Object { $_.status -notin @('terminal_success','terminal_failed','semantic_blocked','interaction_budget_exhausted') })
$CompletedTasks = @($Task | Where-Object { $_.status -in @('terminal_success','interaction_budget_exhausted') })
$SemanticFailed = $LastSemanticStatus -in @('TOOL_CALL_BLOCKED','REFUSAL')
$Ok = (-not $SemanticFailed) -and ($Task.interactionCount -ge [Math]::Min($MaxIterations, [int]$Task.interactionCount)) -and ($Task.status -in @('terminal_success','interaction_budget_exhausted'))

[pscustomobject]@{
    ok = [bool]$Ok
    status = if ($Ok) { 'TASK_BANK_LOOP_COMPLETED' } else { 'TASK_BANK_LOOP_FAILED' }
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
    finalStatus = $FinalStatus
    taskBankPath = $TaskBankRoot
    chatBankPath = $ChatBankRoot
    runnerStatePath = $RunnerStatePath
    nextAction = if ($Ok) { 'task_bank_loop_completed' } else { 'inspect_task_bank_loop' }
} | ConvertTo-Json -Depth 100
