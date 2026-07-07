param(
    [Parameter(Mandatory=$true)][string]$Task,
    [string]$Mode = 'repo_rc_implementation',
    [int]$MaxIterations = 1,
    [int]$RetryAttempt = 0,
    [switch]$UntilRc,
    [switch]$Execute,
    [switch]$Continue,
    [switch]$SimulateHost,
    [switch]$Dispatch,
    [switch]$DryRun,
    [switch]$AutoFinalAction,
    [switch]$ExecuteReal,
    [switch]$NextDispatchExecuteReal,
    [switch]$ResumeLatest,
    [switch]$ResponseDispatch,
    [string]$HostBridgeResultPath,
    [string]$AnswerCaptureResultPath,
    [string]$GatewayDecisionResultPath,
    [string]$WorkerTickResultPath,
    [string]$TransportResultPath,
    [string]$ReplySequenceResultPath,
    [string]$HostResultOk,
    [string]$HostTaskId,
    [string]$HostChatId,
    [string]$HostTargetId,
    [string]$AskVerdict,
    [string]$AskRisks,
    [string]$AskPolicyReferences,
    [string]$AskMessageToChat,
    [string]$AskNextAction,
    [string]$ResponseTaskId,
    [string]$ResponseChatId,
    [string]$ResponseTargetId
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$RunnerStateSchemaVersion = 2
$RunnerRuntimeVersion = '2026.07.runner-loop'

function New-RunnerStateCapabilities {
    [pscustomobject]@{
        nextDispatch = $true
        transportResult = $true
        replySequence = $true
        resumeLatest = $true
        budgetCursor = $true
        retryPolicy = $true
        recoveryDispatch = $true
        recoveryResult = $true
    }
}

function Add-NextDispatchEnvelope {
    param([Parameter(Mandatory=$true)]$Payload)

    if (-not $Payload.nextDispatchContract) { return }

    $DispatchDir = Join-Path $Root 'var/runner/next-dispatch'
    if (-not (Test-Path $DispatchDir)) { New-Item -ItemType Directory -Path $DispatchDir | Out-Null }

    $Dispatcher = Join-Path $Root 'tool/runner-dispatcher.ps1'
    $Contracts = @()
    if ($Payload.nextDispatchContract.sequence) {
        $Contracts += @($Payload.nextDispatchContract.sequence)
    } else {
        $Contracts += $Payload.nextDispatchContract
    }

    $DispatchPayloads = @()
    $DispatchResults = @()
    for ($Index = 0; $Index -lt $Contracts.Count; $Index++) {
        $Contract = $Contracts[$Index]
        $DispatchPayload = [ordered]@{
            ok = $true
            runId = $Payload.runId
            taskId = $Payload.taskId
            runnerExecutionPlan = [ordered]@{
                ok = $true
                status = 'RUNNER_EXECUTION_PLAN_READY'
                tool = $Contract.tool
                arguments = $Contract.arguments
                allowedMode = 'write'
                mutation = $Contract.mutation
                confirmationRequired = $Contract.confirmationRequired
                confirmationGate = 'disabled'
                hostCallRequired = $true
            }
        }
        $DispatchPath = Join-Path $DispatchDir ($Payload.runId + '.' + $Index + '.json')
        [pscustomobject]$DispatchPayload | ConvertTo-Json -Depth 40 | Set-Content -Path $DispatchPath -Encoding UTF8
        if ($NextDispatchExecuteReal) {
            $DispatchRaw = & $Dispatcher -PayloadPath $DispatchPath -ExecuteReal 2>&1
        } else {
            $DispatchRaw = & $Dispatcher -PayloadPath $DispatchPath -DryRun 2>&1
        }
        $DispatchPayloads += [pscustomobject]@{ index = $Index; path = $DispatchPath; tool = $Contract.tool }
        $DispatchResults += ($DispatchRaw | ConvertFrom-Json)
    }

    $RealEnvRequired = @($DispatchResults | Where-Object { $_.status -eq 'DISPATCHER_REAL_EXECUTION_ENV_REQUIRED' }).Count -gt 0
    $RealAdapterReady = ($DispatchResults.Count -gt 0) -and ((@($DispatchResults | Where-Object { $_.status -eq 'DISPATCHER_REAL_EXECUTION_ADAPTER_READY' }).Count) -eq $DispatchResults.Count)
    $DispatchStatus = if ($NextDispatchExecuteReal -and $RealAdapterReady) { 'NEXT_DISPATCH_REAL_ADAPTER_READY' } elseif ($NextDispatchExecuteReal -and $RealEnvRequired) { 'NEXT_DISPATCH_REAL_ENV_REQUIRED' } else { 'NEXT_DISPATCH_BOUNDARY_READY' }

    $Payload | Add-Member -NotePropertyName nextDispatchPayload -NotePropertyValue $DispatchPayloads -Force
    $Payload | Add-Member -NotePropertyName nextDispatchBoundary -NotePropertyValue $DispatchResults -Force
    $Payload | Add-Member -NotePropertyName nextDispatchStatus -NotePropertyValue $DispatchStatus -Force
    $Payload | Add-Member -NotePropertyName nextDispatchExecutionMode -NotePropertyValue ($(if ($NextDispatchExecuteReal) { 'execute_real' } else { 'dry_run' })) -Force
}

function Add-RetryPolicy {
    param([Parameter(Mandatory=$true)]$Payload)

    if (-not $Payload.finalActionResult) { return }
    $Status = [string]$Payload.finalActionResult.status
    $Policy = switch ($Status) {
        'FINAL_ACTION_ANSWER_CAPTURE_WAIT' { [ordered]@{ ok = $true; status = 'RETRY_POLICY_READY'; action = 'retry_answer_capture'; strategy = 'bounded_retry'; nextAction = 'retry_answer_capture'; maxAttempts = 5 } }
        'FINAL_ACTION_GATEWAY_WAIT' { [ordered]@{ ok = $true; status = 'RETRY_POLICY_READY'; action = 'retry_gateway_decision'; strategy = 'bounded_retry'; nextAction = 'retry_gateway_decision'; maxAttempts = 3 } }
        'FINAL_ACTION_WORKER_RETRY' { [ordered]@{ ok = $true; status = 'RETRY_POLICY_READY'; action = 'retry_worker_tick'; strategy = 'bounded_retry'; nextAction = 'retry_worker_tick'; maxAttempts = 3 } }
        'FINAL_ACTION_WORKER_WAITING_USER' { [ordered]@{ ok = $true; status = 'RETRY_POLICY_WAITING_USER'; action = 'wait_for_user_or_reply'; strategy = 'external_wait'; nextAction = 'wait_for_user_or_reply'; maxAttempts = 0 } }
        'FINAL_ACTION_BUDGET_EXHAUSTED' { [ordered]@{ ok = $true; status = 'RETRY_POLICY_STOP'; action = 'stop_loop'; strategy = 'terminal'; nextAction = 'stop_loop'; maxAttempts = 0 } }
        'FINAL_ACTION_RC_REACHED' { [ordered]@{ ok = $true; status = 'RETRY_POLICY_STOP'; action = 'stop_loop'; strategy = 'terminal'; nextAction = 'stop_loop'; maxAttempts = 0 } }
        default { $null }
    }
    if ($Policy) {
        $Policy.attempt = $RetryAttempt
        $Policy.nextAttempt = if ([int]$Policy.maxAttempts -gt 0) { $RetryAttempt + 1 } else { $RetryAttempt }
        if ([int]$Policy.maxAttempts -gt 0 -and $RetryAttempt -ge [int]$Policy.maxAttempts) {
            $RecoveryAction = switch ([string]$Policy.action) {
                'retry_answer_capture' { 'recover_browser_target' }
                'retry_gateway_decision' { 'recover_chat_binding' }
                'retry_worker_tick' { 'recover_worker_state' }
                default { 'stop_hard' }
            }
            $RecoveryContract = switch ($RecoveryAction) {
                'recover_browser_target' { [ordered]@{ ok = $true; status = 'RECOVERY_DISPATCH_CONTRACT_READY'; stage = 'recovery'; tool = 'console.write.engine.chat.bind'; arguments = [ordered]@{ taskId = if ($ResponseTaskId) { $ResponseTaskId } else { $null }; requireVisibleTarget = $true; refreshBinding = $true; recoveryMode = 'browser_target' }; mutation = 'write'; confirmationRequired = $false; execution = 'external_console_mcp_required'; nextAction = 'dispatch_recovery_chat_bind' } }
                'recover_chat_binding' { [ordered]@{ ok = $true; status = 'RECOVERY_DISPATCH_CONTRACT_READY'; stage = 'recovery'; tool = 'console.write.engine.chat.bind'; arguments = [ordered]@{ taskId = if ($ResponseTaskId) { $ResponseTaskId } else { $null }; requireVisibleTarget = $true; refreshBinding = $true; recoveryMode = 'chat_binding' }; mutation = 'write'; confirmationRequired = $false; execution = 'external_console_mcp_required'; nextAction = 'dispatch_recovery_chat_bind' } }
                'recover_worker_state' { [ordered]@{ ok = $true; status = 'RECOVERY_DISPATCH_CONTRACT_READY'; stage = 'recovery'; tool = 'console.write.engine.worker.tick'; arguments = [ordered]@{ maxTicks = 1; stopOnIdle = $true; stopOnWaitingUser = $true; recoveryMode = 'worker_state' }; mutation = 'write'; confirmationRequired = $false; execution = 'external_console_mcp_required'; nextAction = 'dispatch_recovery_worker_tick' } }
                default { $null }
            }
            $Payload | Add-Member -NotePropertyName recoveryPlan -NotePropertyValue ([pscustomobject]@{
                ok = $true
                status = 'RECOVERY_PLAN_READY'
                action = $RecoveryAction
                reason = 'Retry policy was exhausted and requires recovery planning.'
                dispatchContract = $RecoveryContract
                nextAction = $RecoveryAction
            }) -Force
            $Payload | Add-Member -NotePropertyName nextDispatchContract -NotePropertyValue ($(if ($RecoveryContract) { [pscustomobject]$RecoveryContract } else { $null })) -Force
            $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
                ok = $false
                status = 'FINAL_ACTION_RETRY_EXHAUSTED'
                action = $RecoveryAction
                nextAction = $RecoveryAction
            } -Force
            $Policy.status = 'RETRY_POLICY_EXHAUSTED'
            $Policy.action = 'stop_or_recover'
            $Policy.strategy = 'terminal'
            $Policy.nextAction = 'stop_or_recover'
        }
        $Payload | Add-Member -NotePropertyName retryPolicy -NotePropertyValue ([pscustomobject]$Policy) -Force
    }
}

function Update-RunnerBudget {
    param([Parameter(Mandatory=$true)]$Payload)

    if (-not $Payload.budget) { return }
    if (-not $Payload.finalActionResult) { return }

    if ($Payload.budget.untilRc -eq $true) {
        $Signal = ''
        if ($Payload.workerTickResult) { $Signal = [string]$Payload.workerTickResult.status }
        if ($Payload.gatewayDecisionResult -and -not $Signal) { $Signal = [string]$Payload.gatewayDecisionResult.decision_status }
        if ($Signal -in @('RC_REACHED', 'ENGINE_WORKER_TICK_RC_REACHED', 'RELEASE_READY', 'GA_READY')) {
            $Payload | Add-Member -NotePropertyName nextDispatchContract -NotePropertyValue $null -Force
            $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
                ok = $true
                status = 'FINAL_ACTION_RC_REACHED'
                action = 'stop_loop'
                nextAction = 'stop_loop'
            } -Force
        }
        return
    }

    $SpendActions = @(
        'FINAL_ACTION_WORKER_CONTINUE',
        'FINAL_ACTION_WORKER_STOP',
        'FINAL_ACTION_TRANSPORT_RESULT_FED',
        'FINAL_ACTION_REPLY_SEQUENCE_ACCEPTED'
    )
    if ($SpendActions -notcontains [string]$Payload.finalActionResult.status) { return }

    $Remaining = [int]$Payload.budget.remaining
    if ($Remaining -gt 0) { $Remaining = $Remaining - 1 }
    $Payload.budget.remaining = $Remaining
    if ($Remaining -le 0 -and [string]$Payload.finalActionResult.status -eq 'FINAL_ACTION_WORKER_CONTINUE') {
        $Payload | Add-Member -NotePropertyName nextDispatchContract -NotePropertyValue $null -Force
        $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
            ok = $true
            status = 'FINAL_ACTION_BUDGET_EXHAUSTED'
            action = 'stop_loop'
            nextAction = 'stop_loop'
        } -Force
    }
}

function Write-RunnerState {
    param([Parameter(Mandatory=$true)]$Payload)

    Update-RunnerBudget -Payload $Payload
    Add-RetryPolicy -Payload $Payload
    Add-NextDispatchEnvelope -Payload $Payload

    $StateDir = Join-Path $Root 'var/runner/state'
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir | Out-Null }

    $State = [ordered]@{
        ok = $true
        status = 'RUNNER_STATE_PERSISTED'
        runId = $Payload.runId
        taskId = $Payload.taskId
        runnerMode = $Payload.runnerMode
        finalActionSelected = $Payload.finalActionSelected
        finalActionResult = $Payload.finalActionResult
        nextDispatchContract = $Payload.nextDispatchContract
        budget = if ($Payload.budget) { $Payload.budget } else { [ordered]@{ mode = 'single_step'; remaining = $MaxIterations; untilRc = [bool]$UntilRc } }
        retryPolicy = $Payload.retryPolicy
        retryAttempt = $RetryAttempt
        recoveryPlan = $Payload.recoveryPlan
        updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    $State.schemaVersion = $RunnerStateSchemaVersion
    $State.runtimeVersion = $RunnerRuntimeVersion
    $State.capabilities = (New-RunnerStateCapabilities)

    $LatestPath = Join-Path $StateDir 'latest.json'
    $RunPath = Join-Path $StateDir (($Payload.runId) + '.json')
    [pscustomobject]$State | ConvertTo-Json -Depth 40 | Set-Content -Path $LatestPath -Encoding UTF8
    [pscustomobject]$State | ConvertTo-Json -Depth 40 | Set-Content -Path $RunPath -Encoding UTF8
    $Payload | Add-Member -NotePropertyName runnerStatePath -NotePropertyValue $LatestPath -Force
    $Payload | Add-Member -NotePropertyName runnerStateStatus -NotePropertyValue 'RUNNER_STATE_PERSISTED' -Force
}

if ($ResumeLatest) {
    $StatePath = Join-Path $Root 'var/runner/state/latest.json'
    if (-not (Test-Path $StatePath)) { throw "latest runner state not found: $StatePath" }
    $State = Get-Content -Raw -Path $StatePath | ConvertFrom-Json
    if ($State.status -ne 'RUNNER_STATE_PERSISTED') { throw "latest runner state is not persisted: $($State.status)" }
    $StateSchemaVersion = if ($State.schemaVersion) { [int]$State.schemaVersion } else { 1 }
    if ($StateSchemaVersion -gt $RunnerStateSchemaVersion) { throw "latest runner state schema is newer than runtime: $StateSchemaVersion" }
    $Payload = [pscustomobject]@{
        ok = $true
        runId = $State.runId
        taskId = $State.taskId
        runnerMode = 'resume_latest'
        finalActionSelected = $State.finalActionSelected
        finalActionResult = @{
            ok = $true
            status = 'FINAL_ACTION_RESUME_LATEST'
            action = 'resume_latest'
            nextAction = 'dispatch_next_from_state'
        }
        nextDispatchContract = $State.nextDispatchContract
        budget = if ($State.budget) { $State.budget } else { [ordered]@{ mode = 'single_step'; remaining = $MaxIterations; untilRc = [bool]$UntilRc } }
        resumeState = $State
        resumeStatePath = $StatePath
    }
    Write-RunnerState -Payload $Payload
    $Payload | ConvertTo-Json -Depth 40
    exit 0
}

$ArgsList = @('bin/console', 'chatgpt-loop:run', "--task=$Task", "--mode=$Mode")

if ($UntilRc) { $ArgsList += '--until-rc=1' } else { $ArgsList += "--max-iterations=$MaxIterations" }
if ($HostResultOk) {
    $ArgsList += "--host-result-ok=$HostResultOk"
    if ($HostTaskId) { $ArgsList += "--host-task-id=$HostTaskId" }
    if ($HostChatId) { $ArgsList += "--host-chat-id=$HostChatId" }
    if ($HostTargetId) { $ArgsList += "--host-target-id=$HostTargetId" }
}
if ($AskVerdict) { $ArgsList += "--ask-verdict=$AskVerdict" }
if ($AskRisks) { $ArgsList += "--ask-risks=$AskRisks" }
if ($AskPolicyReferences) { $ArgsList += "--ask-policy-references=$AskPolicyReferences" }
if ($AskMessageToChat) { $ArgsList += "--ask-message-to-chat=$AskMessageToChat" }
if ($AskNextAction) { $ArgsList += "--ask-next-action=$AskNextAction" }
if ($ResponseTaskId) { $ArgsList += "--response-task-id=$ResponseTaskId" }
if ($ResponseChatId) { $ArgsList += "--response-chat-id=$ResponseChatId" }
if ($ResponseTargetId) { $ArgsList += "--response-target-id=$ResponseTargetId" }

$Raw = & php @ArgsList 2>&1
$Payload = $Raw | ConvertFrom-Json

if (-not $Payload.dispatchEnvelope) { throw 'dispatchEnvelope missing' }
if (-not $Payload.runnerExecutionPlan) { throw 'runnerExecutionPlan missing' }
if ($Payload.runnerExecutionPlan.ok -ne $true) { throw "runner execution plan not ready: $($Payload.runnerExecutionPlan.status)" }

$FinalAction = if ($Payload.finalAction) { [string]$Payload.finalAction.action } else { 'unknown' }
if ($AutoFinalAction) {
    if ($FinalAction -eq 'dispatch_chat_response') {
        $Dispatch = $true
        $ResponseDispatch = $true
        $DryRun = $true
    } elseif ($FinalAction -eq 'continue_loop') {
        $Continue = $true
    }
}

$Payload | Add-Member -NotePropertyName finalActionSelected -NotePropertyValue $FinalAction -Force
$Payload | Add-Member -NotePropertyName runnerMode -NotePropertyValue ($(if ($ReplySequenceResultPath) { 'reply_sequence_result' } elseif ($TransportResultPath) { 'transport_result' } elseif ($WorkerTickResultPath) { 'worker_tick_result' } elseif ($GatewayDecisionResultPath) { 'gateway_decision_result' } elseif ($AnswerCaptureResultPath) { 'answer_capture_result' } elseif ($HostBridgeResultPath) { 'host_bridge_result' } elseif ($AutoFinalAction) { 'auto_final_action' } elseif ($Dispatch -and $SimulateHost) { 'dispatch_simulate_e2e' } elseif ($Dispatch) { 'dispatch_skeleton' } elseif ($SimulateHost) { 'simulate_host_e2e' } elseif ($Continue) { 'continue' } elseif ($Execute) { 'execute_allowlisted' } else { 'dry_run' })) -Force
$Payload | Add-Member -NotePropertyName budget -NotePropertyValue ([pscustomobject]@{ mode = if ($UntilRc) { 'until_rc' } else { 'steps' }; remaining = $MaxIterations; untilRc = [bool]$UntilRc }) -Force

if ($ReplySequenceResultPath) {
    if (-not (Test-Path $ReplySequenceResultPath)) { throw "reply sequence result file not found: $ReplySequenceResultPath" }
    $ReplySequenceResult = Get-Content -Raw -Path $ReplySequenceResultPath | ConvertFrom-Json
    $ReplyResults = @($ReplySequenceResult.results)
    if ($ReplyResults.Count -ne 2) { throw "reply sequence result count mismatch: $($ReplyResults.Count)" }
    if ($ReplyResults[0].tool -ne 'console.write.engine.reply.draft') { throw "reply sequence draft result tool mismatch" }
    if ($ReplyResults[1].tool -ne 'console.write.engine.reply.submit') { throw "reply sequence submit result tool mismatch" }
    if ($ReplyResults[0].ok -ne $true -or $ReplyResults[1].ok -ne $true) { throw "reply sequence result was not successful" }

    $ReplyTaskId = if ($ResponseTaskId) { $ResponseTaskId } elseif ($ReplyResults[1].task_id) { $ReplyResults[1].task_id } elseif ($ReplyResults[0].task_id) { $ReplyResults[0].task_id } else { $null }
    $ReplyTargetId = if ($ResponseTargetId) { $ResponseTargetId } elseif ($ReplyResults[1].target_id) { $ReplyResults[1].target_id } elseif ($ReplyResults[0].target_id) { $ReplyResults[0].target_id } else { $null }
    $NextLoopTickPlan = [ordered]@{
        ok = $true
        status = 'REPLY_SEQUENCE_ACCEPTED_PLAN_READY'
        stage = 'answer_capture'
        phase = 'reply_watch'
        action = 'capture_next_answer'
        taskId = $ReplyTaskId
        targetId = $ReplyTargetId
        maxIterations = $MaxIterations
        untilRc = [bool]$UntilRc
        nextAction = 'dispatch_answer_capture'
    }
    $NextLoopTickContract = [ordered]@{
        ok = $true
        status = 'REPLY_SEQUENCE_NEXT_CAPTURE_CONTRACT_READY'
        stage = 'answer_capture'
        tool = 'console.write.engine.answer.capture'
        arguments = [ordered]@{
            taskId = $NextLoopTickPlan.taskId
            preferredChatId = if ($ResponseChatId) { $ResponseChatId } else { $null }
            requireChatId = $true
            readinessProfile = 'rc_gate'
            confirmCapture = $true
        }
        mutation = 'write'
        confirmationRequired = $false
        execution = 'external_console_mcp_required'
        nextAction = 'dispatch_answer_capture'
    }
    $Payload | Add-Member -NotePropertyName replySequenceResult -NotePropertyValue $ReplySequenceResult -Force
    $Payload | Add-Member -NotePropertyName nextLoopTickPlan -NotePropertyValue ([pscustomobject]$NextLoopTickPlan) -Force
    $Payload | Add-Member -NotePropertyName nextLoopTickContract -NotePropertyValue ([pscustomobject]$NextLoopTickContract) -Force
    $Payload | Add-Member -NotePropertyName nextDispatchContract -NotePropertyValue ([pscustomobject]$NextLoopTickContract) -Force
    $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
        ok = $true
        status = 'FINAL_ACTION_REPLY_SEQUENCE_ACCEPTED'
        action = 'continue_after_reply_sequence'
        nextAction = 'dispatch_answer_capture'
    } -Force
    Write-RunnerState -Payload $Payload
    $Payload | ConvertTo-Json -Depth 40
    exit 0
}

if ($TransportResultPath) {
    if (-not (Test-Path $TransportResultPath)) { throw "transport result file not found: $TransportResultPath" }
    $TransportResult = Get-Content -Raw -Path $TransportResultPath | ConvertFrom-Json
    if ($TransportResult.status -ne 'DISPATCHER_TRANSPORT_RESULT_ACCEPTED') { throw "transport result not accepted: $($TransportResult.status)" }
    $TransportTool = [string]$TransportResult.tool
    $TransportPayload = $TransportResult.result
    $TransportPayloadPath = Join-Path (Split-Path -Parent $TransportResultPath) ('transport-intake-' + $TransportTool.Replace('.', '-').Replace('_', '-') + '.json')
    $TransportPayload | ConvertTo-Json -Depth 40 | Set-Content -Path $TransportPayloadPath -Encoding UTF8

    $IntakeArgs = @('-Task', $Task, '-MaxIterations', $MaxIterations, '-ResponseTaskId', $(if ($ResponseTaskId) { $ResponseTaskId } elseif ($TransportPayload.task_id) { $TransportPayload.task_id } else { '' }))
    if ($TransportTool -eq 'console.write.engine.answer.capture') {
        $IntakeArgs += @('-AnswerCaptureResultPath', $TransportPayloadPath)
    } elseif ($TransportTool -eq 'console.write.engine.gateway.decide') {
        $IntakeArgs += @('-GatewayDecisionResultPath', $TransportPayloadPath)
    } elseif ($TransportTool -eq 'console.write.engine.worker.tick') {
        $IntakeArgs += @('-WorkerTickResultPath', $TransportPayloadPath)
        if ([string]$TransportPayload.recoveryMode -eq 'worker_state') {
            $IntakeArgs += @('-RetryAttempt', 0)
            $Payload | Add-Member -NotePropertyName recoveryResult -NotePropertyValue $TransportResult -Force
        }
    } elseif ($TransportTool -eq 'console.write.engine.chat.bind') {
        $RecoveredTaskId = if ($ResponseTaskId) { $ResponseTaskId } elseif ($TransportPayload.task_id) { $TransportPayload.task_id } else { $null }
        $RecoveryCaptureContract = [ordered]@{
            ok = $true
            status = 'RECOVERY_RESULT_NEXT_CAPTURE_CONTRACT_READY'
            stage = 'answer_capture'
            tool = 'console.write.engine.answer.capture'
            arguments = [ordered]@{
                taskId = $RecoveredTaskId
                preferredChatId = if ($TransportPayload.chat_id) { $TransportPayload.chat_id } else { $null }
                requireChatId = $true
                readinessProfile = 'rc_gate'
                confirmCapture = $true
                retryAttempt = 0
            }
            mutation = 'write'
            confirmationRequired = $false
            execution = 'external_console_mcp_required'
            nextAction = 'dispatch_answer_capture'
        }
        $Payload | Add-Member -NotePropertyName recoveryResult -NotePropertyValue $TransportResult -Force
        $Payload | Add-Member -NotePropertyName retryAttempt -NotePropertyValue 0 -Force
        $Payload | Add-Member -NotePropertyName nextDispatchContract -NotePropertyValue ([pscustomobject]$RecoveryCaptureContract) -Force
        $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
            ok = $true
            status = 'FINAL_ACTION_RECOVERY_RESULT_ACCEPTED'
            action = 'dispatch_answer_capture'
            nextAction = 'dispatch_answer_capture'
        } -Force
        Write-RunnerState -Payload $Payload
        $Payload | ConvertTo-Json -Depth 40
        exit 0
    } elseif ($TransportTool -eq 'console.write.engine.reply.draft' -or $TransportTool -eq 'console.write.engine.reply.submit') {
        $Payload | Add-Member -NotePropertyName transportResult -NotePropertyValue $TransportResult -Force
        $Payload | Add-Member -NotePropertyName transportIntakePath -NotePropertyValue $TransportPayloadPath -Force
        $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
            ok = $true
            status = 'FINAL_ACTION_TRANSPORT_REPLY_ACCEPTED'
            action = 'wait_for_reply_sequence_completion'
            nextAction = 'collect_reply_sequence_result'
        } -Force
        Write-RunnerState -Payload $Payload
        $Payload | ConvertTo-Json -Depth 40
        exit 0
    } else {
        throw "transport result tool is not routable: $TransportTool"
    }

    $IntakeRaw = & $PSCommandPath @IntakeArgs 2>&1
    $Payload | Add-Member -NotePropertyName transportResult -NotePropertyValue $TransportResult -Force
    $Payload | Add-Member -NotePropertyName transportIntakePath -NotePropertyValue $TransportPayloadPath -Force
    $Payload | Add-Member -NotePropertyName transportIntakePayload -NotePropertyValue ($IntakeRaw | ConvertFrom-Json) -Force
    $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
        ok = $true
        status = 'FINAL_ACTION_TRANSPORT_RESULT_FED'
        action = 'transport_result_fed_to_runner_intake'
        nextAction = 'continue_from_transport_intake_payload'
    } -Force
    Write-RunnerState -Payload $Payload
    $Payload | ConvertTo-Json -Depth 40
    exit 0
}

if ($WorkerTickResultPath) {
    if (-not (Test-Path $WorkerTickResultPath)) { throw "worker tick result file not found: $WorkerTickResultPath" }
    $WorkerTickResult = Get-Content -Raw -Path $WorkerTickResultPath | ConvertFrom-Json
    $WorkerStatus = [string]$WorkerTickResult.status
    if ($WorkerStatus -eq 'ENGINE_WORKER_TICK_ACCEPTED' -or $WorkerStatus -eq 'ENGINE_WORKER_TICK_CONTINUE') {
        $WorkerContinuePlan = [ordered]@{
            ok = $true
            status = 'WORKER_TICK_CONTINUE_PLAN_READY'
            stage = 'bounded_worker_tick'
            action = 'continue_loop'
            taskId = if ($ResponseTaskId) { $ResponseTaskId } elseif ($WorkerTickResult.task_id) { $WorkerTickResult.task_id } else { $null }
            nextAction = 'continue_loop'
        }
        $Payload | Add-Member -NotePropertyName workerTickResult -NotePropertyValue $WorkerTickResult -Force
        $Payload | Add-Member -NotePropertyName workerContinuePlan -NotePropertyValue ([pscustomobject]$WorkerContinuePlan) -Force
        $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
            ok = $true
            status = 'FINAL_ACTION_WORKER_CONTINUE'
            action = 'continue_loop'
            nextAction = 'continue_loop'
        } -Force
    } elseif ($WorkerStatus -eq 'ENGINE_WORKER_TICK_WAITING_USER') {
        $WorkerWaitPlan = [ordered]@{
            ok = $true
            status = 'WORKER_TICK_WAITING_USER_PLAN_READY'
            stage = 'bounded_worker_tick'
            action = 'wait_for_user_or_reply'
            nextAction = 'wait_for_user_or_reply'
        }
        $Payload | Add-Member -NotePropertyName workerTickResult -NotePropertyValue $WorkerTickResult -Force
        $Payload | Add-Member -NotePropertyName workerWaitPlan -NotePropertyValue ([pscustomobject]$WorkerWaitPlan) -Force
        $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
            ok = $true
            status = 'FINAL_ACTION_WORKER_WAITING_USER'
            action = 'wait_for_user_or_reply'
            nextAction = 'wait_for_user_or_reply'
        } -Force
    } elseif ($WorkerStatus -eq 'ENGINE_WORKER_TICK_IDLE' -or $WorkerStatus -eq 'ENGINE_WORKER_TICK_STOPPED' -or $WorkerStatus -eq 'ENGINE_WORKER_TICK_RC_REACHED' -or $WorkerStatus -eq 'RC_REACHED' -or $WorkerStatus -eq 'RELEASE_READY' -or $WorkerStatus -eq 'GA_READY') {
        $WorkerStopPlan = [ordered]@{
            ok = $true
            status = 'WORKER_TICK_STOP_PLAN_READY'
            stage = 'bounded_worker_tick'
            action = 'stop_loop'
            nextAction = 'stop_loop'
        }
        $Payload | Add-Member -NotePropertyName workerTickResult -NotePropertyValue $WorkerTickResult -Force
        $Payload | Add-Member -NotePropertyName workerStopPlan -NotePropertyValue ([pscustomobject]$WorkerStopPlan) -Force
        $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
            ok = $true
            status = 'FINAL_ACTION_WORKER_STOP'
            action = 'stop_loop'
            nextAction = 'stop_loop'
        } -Force
    } else {
        $WorkerRetryPlan = [ordered]@{
            ok = $true
            status = 'WORKER_TICK_RETRY_PLAN_READY'
            stage = 'bounded_worker_tick'
            action = 'retry_worker_tick'
            nextAction = 'retry_worker_tick'
        }
        $Payload | Add-Member -NotePropertyName workerTickResult -NotePropertyValue $WorkerTickResult -Force
        $Payload | Add-Member -NotePropertyName workerRetryPlan -NotePropertyValue ([pscustomobject]$WorkerRetryPlan) -Force
        $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
            ok = $true
            status = 'FINAL_ACTION_WORKER_RETRY'
            action = 'retry_worker_tick'
            nextAction = 'retry_worker_tick'
        } -Force
    }
    Write-RunnerState -Payload $Payload
    $Payload | ConvertTo-Json -Depth 40
    exit 0
}

if ($GatewayDecisionResultPath) {
    if (-not (Test-Path $GatewayDecisionResultPath)) { throw "gateway decision result file not found: $GatewayDecisionResultPath" }
    $GatewayDecisionResult = Get-Content -Raw -Path $GatewayDecisionResultPath | ConvertFrom-Json
    if ($GatewayDecisionResult.status -ne 'ENGINE_GATEWAY_DECISION_RECORDED') { throw "gateway decision result not recorded: $($GatewayDecisionResult.status)" }
    $DecisionStatus = [string]$GatewayDecisionResult.decision_status
    if (-not $DecisionStatus) { $DecisionStatus = 'CONTINUE' }
    $DecisionStatus = $DecisionStatus.ToUpperInvariant()

    if ($DecisionStatus -eq 'CONTINUE' -or $DecisionStatus -eq 'ALLOW') {
        $ContinuePlan = [ordered]@{
            ok = $true
            status = 'GATEWAY_CONTINUE_PLAN_READY'
            stage = 'bounded_worker_tick'
            action = 'continue_loop'
            taskId = if ($ResponseTaskId) { $ResponseTaskId } elseif ($GatewayDecisionResult.task_id) { $GatewayDecisionResult.task_id } else { $null }
            maxIterations = $MaxIterations
            untilRc = [bool]$UntilRc
            nextAction = 'continue_loop'
        }
        $ContinueContract = [ordered]@{
            ok = $true
            status = 'GATEWAY_CONTINUE_CONTRACT_READY'
            stage = 'bounded_worker_tick'
            tool = 'console.write.engine.worker.tick'
            arguments = [ordered]@{
                maxTicks = 1
                stopOnIdle = $true
                stopOnWaitingUser = $true
                budgetMode = if ($UntilRc) { 'until_rc' } else { 'single_step' }
                remainingBudget = $MaxIterations
            }
            mutation = 'write'
            confirmationRequired = $false
            execution = 'external_console_mcp_required'
            nextAction = 'dispatch_worker_tick'
        }
        $Payload | Add-Member -NotePropertyName gatewayDecisionResult -NotePropertyValue $GatewayDecisionResult -Force
        $Payload | Add-Member -NotePropertyName gatewayContinuePlan -NotePropertyValue ([pscustomobject]$ContinuePlan) -Force
        $Payload | Add-Member -NotePropertyName gatewayContinueContract -NotePropertyValue ([pscustomobject]$ContinueContract) -Force
        $Payload | Add-Member -NotePropertyName nextDispatchContract -NotePropertyValue ([pscustomobject]$ContinueContract) -Force
        $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
            ok = $true
            status = 'FINAL_ACTION_GATEWAY_CONTINUE'
            action = 'continue_loop'
            nextAction = 'continue_loop'
        } -Force
    } elseif ($DecisionStatus -eq 'WAIT' -or $DecisionStatus -eq 'RETRY') {
        $WaitPlan = [ordered]@{
            ok = $true
            status = 'GATEWAY_WAIT_PLAN_READY'
            stage = 'gateway_decision'
            action = 'retry_gateway_decision'
            nextAction = 'retry_gateway_decision'
        }
        $Payload | Add-Member -NotePropertyName gatewayDecisionResult -NotePropertyValue $GatewayDecisionResult -Force
        $Payload | Add-Member -NotePropertyName gatewayWaitPlan -NotePropertyValue ([pscustomobject]$WaitPlan) -Force
        $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
            ok = $true
            status = 'FINAL_ACTION_GATEWAY_WAIT'
            action = 'retry_gateway_decision'
            nextAction = 'retry_gateway_decision'
        } -Force
    } else {
        $ReplyPlan = [ordered]@{
            ok = $true
            status = 'GATEWAY_REPLY_BACK_PLAN_READY'
            stage = 'reply_back'
            action = 'dispatch_chat_response'
            decisionStatus = $DecisionStatus
            taskId = if ($ResponseTaskId) { $ResponseTaskId } elseif ($GatewayDecisionResult.task_id) { $GatewayDecisionResult.task_id } else { $null }
            nextAction = 'dispatch_chat_response'
        }
        $ReplyBackContract = [ordered]@{
            ok = $true
            status = 'GATEWAY_REPLY_BACK_CONTRACT_READY'
            sequence = @(
                [ordered]@{
                    stage = 'reply_draft'
                    tool = 'console.write.engine.reply.draft'
                    arguments = [ordered]@{
                        taskId = $ReplyPlan.taskId
                        expectedTargetId = if ($ResponseTargetId) { $ResponseTargetId } else { $null }
                        allowOverwrite = $false
                        confirmDraft = $true
                    }
                    mutation = 'write'
                    confirmationRequired = $false
                    execution = 'external_console_mcp_required'
                },
                [ordered]@{
                    stage = 'reply_submit'
                    tool = 'console.write.engine.reply.submit'
                    arguments = [ordered]@{
                        taskId = $ReplyPlan.taskId
                        expectedTargetId = if ($ResponseTargetId) { $ResponseTargetId } else { $null }
                        confirmSubmit = $true
                    }
                    mutation = 'write'
                    confirmationRequired = $false
                    execution = 'external_console_mcp_required'
                }
            )
            nextAction = 'dispatch_chat_response'
        }
        $Payload | Add-Member -NotePropertyName gatewayDecisionResult -NotePropertyValue $GatewayDecisionResult -Force
        $Payload | Add-Member -NotePropertyName gatewayReplyBackPlan -NotePropertyValue ([pscustomobject]$ReplyPlan) -Force
        $Payload | Add-Member -NotePropertyName gatewayReplyBackContract -NotePropertyValue ([pscustomobject]$ReplyBackContract) -Force
        $Payload | Add-Member -NotePropertyName nextDispatchContract -NotePropertyValue ([pscustomobject]$ReplyBackContract) -Force
        $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
            ok = ($DecisionStatus -ne 'BLOCK')
            status = if ($DecisionStatus -eq 'BLOCK') { 'FINAL_ACTION_GATEWAY_BLOCK' } else { 'FINAL_ACTION_GATEWAY_REPLY_BACK' }
            action = 'dispatch_chat_response'
            nextAction = 'dispatch_chat_response'
        } -Force
    }
    Write-RunnerState -Payload $Payload
    $Payload | ConvertTo-Json -Depth 40
    exit 0
}

if ($AnswerCaptureResultPath) {
    if (-not (Test-Path $AnswerCaptureResultPath)) { throw "answer capture result file not found: $AnswerCaptureResultPath" }
    $AnswerCaptureResult = Get-Content -Raw -Path $AnswerCaptureResultPath | ConvertFrom-Json
    $AnswerReady = ($AnswerCaptureResult.ok -eq $true -and $AnswerCaptureResult.status -eq 'ENGINE_ANSWER_CAPTURED')
    if ($AnswerReady) {
        $GatewayDecisionContract = [ordered]@{
            ok = $true
            status = 'GATEWAY_DECISION_CONTRACT_READY'
            stage = 'gateway_decision'
            tool = 'console.write.engine.gateway.decide'
            arguments = [ordered]@{
                taskId = if ($ResponseTaskId) { $ResponseTaskId } elseif ($AnswerCaptureResult.task_id) { $AnswerCaptureResult.task_id } else { $null }
                maxOutputTokens = 900
                temperature = 0.1
                raw = $false
                confirmDecision = $true
            }
            mutation = 'write'
            confirmationRequired = $false
            execution = 'external_console_mcp_required'
            nextAction = 'dispatch_gateway_decision'
        }
        $Payload | Add-Member -NotePropertyName answerCaptureResult -NotePropertyValue $AnswerCaptureResult -Force
        $Payload | Add-Member -NotePropertyName gatewayDecisionContract -NotePropertyValue ([pscustomobject]$GatewayDecisionContract) -Force
        $Payload | Add-Member -NotePropertyName nextDispatchContract -NotePropertyValue ([pscustomobject]$GatewayDecisionContract) -Force
        $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
            ok = $true
            status = 'FINAL_ACTION_ANSWER_CAPTURED'
            action = 'dispatch_gateway_decision'
            nextAction = 'dispatch_gateway_decision'
        } -Force
    } else {
        $WaitPlan = [ordered]@{
            ok = $true
            status = 'ANSWER_CAPTURE_WAIT_PLAN_READY'
            stage = 'answer_capture'
            action = 'retry_answer_capture'
            reason = 'Answer capture is not ready yet; keep the loop in bounded wait/retry mode.'
            nextAction = 'retry_answer_capture'
        }
        $Payload | Add-Member -NotePropertyName answerCaptureResult -NotePropertyValue $AnswerCaptureResult -Force
        $Payload | Add-Member -NotePropertyName answerCaptureWaitPlan -NotePropertyValue ([pscustomobject]$WaitPlan) -Force
        $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
            ok = $true
            status = 'FINAL_ACTION_ANSWER_CAPTURE_WAIT'
            action = 'retry_answer_capture'
            nextAction = 'retry_answer_capture'
        } -Force
    }
    Write-RunnerState -Payload $Payload
    $Payload | ConvertTo-Json -Depth 40
    exit 0
}

if ($HostBridgeResultPath) {
    $PayloadDir = Join-Path $Root 'var/runner'
    if (-not (Test-Path $PayloadDir)) { New-Item -ItemType Directory -Path $PayloadDir | Out-Null }
    $HostPayloadPath = Join-Path $PayloadDir ($Payload.runId + '.host-bridge.json')
    $Payload | ConvertTo-Json -Depth 40 | Set-Content -Path $HostPayloadPath -Encoding UTF8
    $HostBridge = Join-Path $Root 'tool/runner-host-bridge.ps1'
    $HostBridgeRaw = & $HostBridge -PayloadPath $HostPayloadPath -ResultPath $HostBridgeResultPath 2>&1
    $HostBridgePayload = $HostBridgeRaw | ConvertFrom-Json
    if ($HostBridgePayload.status -ne 'HOST_BRIDGE_RESULT_ACCEPTED') { throw "host bridge result not accepted: $($HostBridgePayload.status)" }
    $Payload | Add-Member -NotePropertyName hostBridgePayloadPath -NotePropertyValue $HostPayloadPath -Force
    $NextLoopTickPlan = [ordered]@{
        ok = $true
        status = 'NEXT_LOOP_TICK_PLAN_READY'
        reason = 'Canonical reply-back was accepted by the host bridge; wait for the next assistant answer before continuing evidence and gate evaluation.'
        stage = 'answer_capture'
        phase = 'reply_watch'
        action = 'capture_next_answer'
        taskId = if ($ResponseTaskId) { $ResponseTaskId } elseif ($HostBridgePayload.invocations[0].arguments.taskId) { $HostBridgePayload.invocations[0].arguments.taskId } else { $null }
        targetId = if ($ResponseTargetId) { $ResponseTargetId } elseif ($HostBridgePayload.invocations[0].arguments.expectedTargetId) { $HostBridgePayload.invocations[0].arguments.expectedTargetId } else { $null }
        maxIterations = $MaxIterations
        untilRc = [bool]$UntilRc
        nextCommand = 'run_answer_capture_then_continue_loop'
    }
    $NextLoopTickContract = [ordered]@{
        ok = $true
        status = 'NEXT_LOOP_TICK_CONTRACT_READY'
        stage = 'answer_capture'
        tool = 'console.write.engine.answer.capture'
        arguments = [ordered]@{
            taskId = $NextLoopTickPlan.taskId
            preferredChatId = if ($ResponseChatId) { $ResponseChatId } else { $null }
            requireChatId = $true
            readinessProfile = 'rc_gate'
            confirmCapture = $true
        }
        mutation = 'write'
        confirmationRequired = $false
        execution = 'external_console_mcp_required'
        nextAction = 'dispatch_answer_capture'
    }
    $Payload | Add-Member -NotePropertyName hostBridgeResult -NotePropertyValue $HostBridgePayload -Force
    $Payload | Add-Member -NotePropertyName nextLoopTickPlan -NotePropertyValue ([pscustomobject]$NextLoopTickPlan) -Force
    $Payload | Add-Member -NotePropertyName nextLoopTickContract -NotePropertyValue ([pscustomobject]$NextLoopTickContract) -Force
    $Payload | Add-Member -NotePropertyName nextDispatchContract -NotePropertyValue ([pscustomobject]$NextLoopTickContract) -Force
    $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
        ok = $true
        status = 'FINAL_ACTION_HOST_RESULT_ACCEPTED'
        action = 'continue_after_host_invocation'
        nextAction = $HostBridgePayload.nextAction
    } -Force
    Write-RunnerState -Payload $Payload
    $Payload | ConvertTo-Json -Depth 40
    exit 0
}

if ($AutoFinalAction -and $FinalAction -in @('wait_for_ask_gateway_result', 'provide_response_chat_id', 'provide_response_task_id', 'wait_or_review')) {
    $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
        ok = $true
        status = 'FINAL_ACTION_WAITING'
        action = $FinalAction
        reason = $Payload.finalAction.reason
    } -Force
    Write-RunnerState -Payload $Payload
    $Payload | ConvertTo-Json -Depth 30
    exit 0
}

if ($AutoFinalAction -and $FinalAction -like 'stop*') {
    $Payload | Add-Member -NotePropertyName finalActionResult -NotePropertyValue @{
        ok = $false
        status = 'FINAL_ACTION_STOPPED'
        action = $FinalAction
        reason = $Payload.finalAction.reason
    } -Force
    Write-RunnerState -Payload $Payload
    $Payload | ConvertTo-Json -Depth 30
    exit 0
}

if ($Dispatch) {
    $PayloadDir = Join-Path $Root 'var/runner'
    if (-not (Test-Path $PayloadDir)) { New-Item -ItemType Directory -Path $PayloadDir | Out-Null }
    $PayloadPath = Join-Path $PayloadDir ($Payload.runId + '.json')
    $Payload | ConvertTo-Json -Depth 30 | Set-Content -Path $PayloadPath -Encoding UTF8
    $Dispatcher = Join-Path $Root 'tool/runner-dispatcher.ps1'
    if ($SimulateHost) { $DispatchRaw = & $Dispatcher -PayloadPath $PayloadPath -Simulate 2>&1 } elseif ($DryRun) { $DispatchRaw = & $Dispatcher -PayloadPath $PayloadPath -DryRun 2>&1 } else { $DispatchRaw = & $Dispatcher -PayloadPath $PayloadPath -DryRun 2>&1 }
    $DispatcherPayload = $DispatchRaw | ConvertFrom-Json
    $Payload | Add-Member -NotePropertyName dispatchPayloadPath -NotePropertyValue $PayloadPath -Force
    $Payload | Add-Member -NotePropertyName dispatcherPayload -NotePropertyValue $DispatcherPayload -Force
    if ($SimulateHost) {
        $BridgeArgs = @('bin/console', 'chatgpt-loop:run', "--task=$Task", "--host-result-ok=$([int]$DispatcherPayload.ok)")
        if ($DispatcherPayload.taskId) { $BridgeArgs += "--host-task-id=$($DispatcherPayload.taskId)" }
        if ($DispatcherPayload.chatId) { $BridgeArgs += "--host-chat-id=$($DispatcherPayload.chatId)" }
        if ($DispatcherPayload.targetId) { $BridgeArgs += "--host-target-id=$($DispatcherPayload.targetId)" }
        $BridgeRaw = & php @BridgeArgs 2>&1
        $BridgePayload = $BridgeRaw | ConvertFrom-Json
        if (-not $BridgePayload.hostResultBridge) { throw 'dispatch simulated hostResultBridge missing' }
        $ContinueArgs = @($BridgePayload.hostResultBridge.continueArgs)
        $ContinueRaw = & php @ContinueArgs 2>&1
        $Payload | Add-Member -NotePropertyName dispatchedHostPayload -NotePropertyValue $BridgePayload -Force
        $Payload | Add-Member -NotePropertyName continuePayload -NotePropertyValue ($ContinueRaw | ConvertFrom-Json) -Force
    }
    if ($ResponseDispatch) {
        $ResponseSequence = @($Payload.chatResponseDispatchContract.sequence)
        if ($ResponseSequence.Count -lt 1) { throw 'chat response dispatch sequence missing' }
        $ResponseEnvelope = $ResponseSequence[0]
        $ResponsePayload = [ordered]@{
            ok = $true
            runId = $Payload.runId
            taskId = $Payload.taskId
            runnerExecutionPlan = [ordered]@{
                ok = $true
                status = 'RUNNER_EXECUTION_PLAN_READY'
                tool = $ResponseEnvelope.tool
                arguments = $ResponseEnvelope.arguments
                allowedMode = 'write'
                mutation = $ResponseEnvelope.mutation
                confirmationRequired = $ResponseEnvelope.confirmationRequired
                confirmationGate = 'disabled'
                hostCallRequired = $true
                resultMapping = @{
                    'ok=true' = '--dispatch-status=ok'
                    'ok=false' = '--dispatch-status=failed'
                    taskId = '--external-task-id'
                    chatId = '--external-chat-id'
                    targetId = '--external-target-id'
                }
            }
        }
        $ResponsePayloadPath = Join-Path $PayloadDir ($Payload.runId + '.response.json')
        $ResponsePayload | ConvertTo-Json -Depth 30 | Set-Content -Path $ResponsePayloadPath -Encoding UTF8
        if ($ExecuteReal) { $ResponseDispatchRaw = & $Dispatcher -PayloadPath $ResponsePayloadPath -ExecuteReal 2>&1 } elseif ($SimulateHost) { $ResponseDispatchRaw = & $Dispatcher -PayloadPath $ResponsePayloadPath -Simulate 2>&1 } else { $ResponseDispatchRaw = & $Dispatcher -PayloadPath $ResponsePayloadPath -DryRun 2>&1 }
        $ResponseDispatcherPayloads = @()
        $ResponseDispatcherPayloads += ($ResponseDispatchRaw | ConvertFrom-Json)
        if ($ResponseSequence.Count -gt 1) {
            for ($Index = 1; $Index -lt $ResponseSequence.Count; $Index++) {
                $ResponseEnvelope = $ResponseSequence[$Index]
                $ResponsePayload.runnerExecutionPlan.tool = $ResponseEnvelope.tool
                $ResponsePayload.runnerExecutionPlan.arguments = $ResponseEnvelope.arguments
                $ResponsePayload.runnerExecutionPlan.mutation = $ResponseEnvelope.mutation
                $ResponsePayload.runnerExecutionPlan.confirmationRequired = $ResponseEnvelope.confirmationRequired
                $ResponsePayloadPath = Join-Path $PayloadDir ($Payload.runId + '.response.' + $Index + '.json')
                $ResponsePayload | ConvertTo-Json -Depth 30 | Set-Content -Path $ResponsePayloadPath -Encoding UTF8
                if ($ExecuteReal) { $ResponseDispatchRaw = & $Dispatcher -PayloadPath $ResponsePayloadPath -ExecuteReal 2>&1 } elseif ($SimulateHost) { $ResponseDispatchRaw = & $Dispatcher -PayloadPath $ResponsePayloadPath -Simulate 2>&1 } else { $ResponseDispatchRaw = & $Dispatcher -PayloadPath $ResponsePayloadPath -DryRun 2>&1 }
                $ResponseDispatcherPayloads += ($ResponseDispatchRaw | ConvertFrom-Json)
            }
        }
        $Payload | Add-Member -NotePropertyName responseDispatchPayloadPath -NotePropertyValue $ResponsePayloadPath -Force
        $Payload | Add-Member -NotePropertyName responseDispatcherPayload -NotePropertyValue $ResponseDispatcherPayloads -Force
    }
    Write-RunnerState -Payload $Payload
    $Payload | ConvertTo-Json -Depth 30
    exit 0
}

if ($SimulateHost) {
    $SimTaskId = 'sim-' + $Payload.taskId
    $SimChatId = 'sim-chat-' + $Payload.runId
    $SimTargetId = 'sim-target-' + $Payload.runId
    $SimArgs = @('bin/console', 'chatgpt-loop:run', "--task=$Task", '--host-result-ok=1', "--host-task-id=$SimTaskId", "--host-chat-id=$SimChatId", "--host-target-id=$SimTargetId")
    $SimRaw = & php @SimArgs 2>&1
    $SimPayload = $SimRaw | ConvertFrom-Json
    if (-not $SimPayload.hostResultBridge) { throw 'simulated hostResultBridge missing' }
    $ContinueArgs = @($SimPayload.hostResultBridge.continueArgs)
    $ContinueRaw = & php @ContinueArgs 2>&1
    $Payload | Add-Member -NotePropertyName simulatedHostPayload -NotePropertyValue $SimPayload -Force
    $Payload | Add-Member -NotePropertyName continuePayload -NotePropertyValue ($ContinueRaw | ConvertFrom-Json) -Force
    Write-RunnerState -Payload $Payload
    $Payload | ConvertTo-Json -Depth 30
    exit 0
}

if ($Continue) {
    if (-not $Payload.hostResultBridge) { throw 'hostResultBridge missing' }
    if ($Payload.hostResultBridge.ok -ne $true) { throw "hostResultBridge not ready: $($Payload.hostResultBridge.status)" }
    $ContinueArgs = @($Payload.hostResultBridge.continueArgs)
    $ContinueRaw = & php @ContinueArgs 2>&1
    $Payload | Add-Member -NotePropertyName continuePayload -NotePropertyValue ($ContinueRaw | ConvertFrom-Json) -Force
    Write-RunnerState -Payload $Payload
    $Payload | ConvertTo-Json -Depth 30
    exit 0
}

if (-not $Execute) {
    Write-RunnerState -Payload $Payload
    $Payload | ConvertTo-Json -Depth 20
    exit 0
}

$Payload | Add-Member -NotePropertyName executionResult -NotePropertyValue @{
    ok = $true
    status = 'EXECUTE_ALLOWLISTED_READY'
    tool = $Payload.runnerExecutionPlan.tool
    arguments = $Payload.runnerExecutionPlan.arguments
    hostCallRequired = $Payload.runnerExecutionPlan.hostCallRequired
    resultMapping = $Payload.runnerExecutionPlan.resultMapping
    allowedMode = $Payload.runnerExecutionPlan.allowedMode
    mutation = $Payload.runnerExecutionPlan.mutation
    confirmationGate = $Payload.runnerExecutionPlan.confirmationGate
    reason = 'Host runner must invoke the allowlisted Console MCP tool with these arguments.'
} -Force
Write-RunnerState -Payload $Payload
$Payload | ConvertTo-Json -Depth 20
