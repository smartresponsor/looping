param(
    [Parameter(Mandatory=$true)][string]$PayloadPath,
    [switch]$Simulate,
    [switch]$DryRun,
    [switch]$ExecuteReal,
    [string]$ResultPath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $PayloadPath)) { throw "payload file not found: $PayloadPath" }

$Payload = Get-Content -Raw -Path $PayloadPath | ConvertFrom-Json
$Plan = $Payload.runnerExecutionPlan

if (-not $Plan) { throw 'runnerExecutionPlan missing' }
if ($Plan.ok -ne $true) { throw "runnerExecutionPlan not ready: $($Plan.status)" }

$AllowedTools = @{
    'console.read_.browser.chatgpt.entrypoint.plan' = 'read_only'
    'console.read_.repo.context.capture' = 'read_only'
    'console.read_.repo.workspace.status' = 'read_only'
    'console.read_.repo.memory.graph.plan' = 'read_only'
    'console.write.browser.session.cmcp.go' = 'write'
    'console.write.browser.session.title.prefix' = 'write'
    'console.write.engine.task.enqueue' = 'write'
    'console.write.engine.worker.tick' = 'write'
    'console.write.engine.chat.bind' = 'write'
    'console.write.engine.answer.capture' = 'write'
    'console.write.engine.gateway.decide' = 'write'
    'console.write.engine.reply.draft' = 'write'
    'console.write.engine.reply.submit' = 'write'
}

if (-not $AllowedTools.ContainsKey([string]$Plan.tool)) { throw "dispatcher tool not allowed: $($Plan.tool)" }
if ($Plan.allowedMode -ne $AllowedTools[[string]$Plan.tool]) { throw "dispatcher allowedMode mismatch: $($Plan.allowedMode)" }

if ($ResultPath) {
    if (-not (Test-Path $ResultPath)) { throw "result file not found: $ResultPath" }
    $ResultPayload = Get-Content -Raw -Path $ResultPath | ConvertFrom-Json
    if ($ResultPayload.tool -and $ResultPayload.tool -ne $Plan.tool) { throw "result tool mismatch: $($ResultPayload.tool)" }
    [pscustomobject]@{
        ok = ($ResultPayload.ok -eq $true)
        status = if ($ResultPayload.ok -eq $true) { 'DISPATCHER_TRANSPORT_RESULT_ACCEPTED' } else { 'DISPATCHER_TRANSPORT_RESULT_FAILED' }
        payloadPath = $PayloadPath
        resultPath = $ResultPath
        tool = $Plan.tool
        arguments = $Plan.arguments
        toolCall = @{
            name = $Plan.tool
            arguments = $Plan.arguments
        }
        result = $ResultPayload
        nextAction = 'feed_result_to_runner_intake'
    } | ConvertTo-Json -Depth 40
    exit 0
}

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

if ($ExecuteReal) {
    if (($env:CHATGPT_LOOP_REAL_EXECUTION) -ne '1') {
        [pscustomobject]@{
            ok = $false
            status = 'DISPATCHER_REAL_EXECUTION_ENV_REQUIRED'
            tool = $Plan.tool
            allowedMode = $Plan.allowedMode
            mutation = $Plan.mutation
            realExecution = 'blocked'
            requiredEnv = 'CHATGPT_LOOP_REAL_EXECUTION=1'
        } | ConvertTo-Json -Depth 30
        exit 0
    }

    [pscustomobject]@{
        ok = $true
        status = 'DISPATCHER_REAL_EXECUTION_ADAPTER_READY'
        tool = $Plan.tool
        arguments = $Plan.arguments
        allowedMode = $Plan.allowedMode
        mutation = $Plan.mutation
        realExecution = 'external_console_mcp_required'
        adapter = 'console_mcp_tool_call'
        toolCall = @{
            name = $Plan.tool
            arguments = $Plan.arguments
        }
        nextAction = 'invoke_console_mcp_tool_call'
    } | ConvertTo-Json -Depth 30
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
