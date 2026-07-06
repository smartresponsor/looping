param(
    [Parameter(Mandatory=$true)][string]$Task,
    [string]$Mode = 'repo_rc_implementation',
    [int]$MaxIterations = 1,
    [switch]$UntilRc,
    [switch]$Execute,
    [switch]$Continue,
    [switch]$SimulateHost,
    [switch]$Dispatch,
    [switch]$DryRun,
    [string]$HostResultOk,
    [string]$HostTaskId,
    [string]$HostChatId,
    [string]$HostTargetId
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$ArgsList = @('bin/console', 'chatgpt-loop:run', "--task=$Task", "--mode=$Mode")

if ($UntilRc) { $ArgsList += '--until-rc=1' } else { $ArgsList += "--max-iterations=$MaxIterations" }
if ($HostResultOk) {
    $ArgsList += "--host-result-ok=$HostResultOk"
    if ($HostTaskId) { $ArgsList += "--host-task-id=$HostTaskId" }
    if ($HostChatId) { $ArgsList += "--host-chat-id=$HostChatId" }
    if ($HostTargetId) { $ArgsList += "--host-target-id=$HostTargetId" }
}

$Raw = & php @ArgsList 2>&1
$Payload = $Raw | ConvertFrom-Json

if (-not $Payload.dispatchEnvelope) { throw 'dispatchEnvelope missing' }
if (-not $Payload.runnerExecutionPlan) { throw 'runnerExecutionPlan missing' }
if ($Payload.runnerExecutionPlan.ok -ne $true) { throw "runner execution plan not ready: $($Payload.runnerExecutionPlan.status)" }

$Payload | Add-Member -NotePropertyName runnerMode -NotePropertyValue ($(if ($Dispatch -and $SimulateHost) { 'dispatch_simulate_e2e' } elseif ($Dispatch) { 'dispatch_skeleton' } elseif ($SimulateHost) { 'simulate_host_e2e' } elseif ($Continue) { 'continue' } elseif ($Execute) { 'execute_allowlisted' } else { 'dry_run' })) -Force

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
    $Payload | ConvertTo-Json -Depth 30
    exit 0
}

if ($Continue) {
    if (-not $Payload.hostResultBridge) { throw 'hostResultBridge missing' }
    if ($Payload.hostResultBridge.ok -ne $true) { throw "hostResultBridge not ready: $($Payload.hostResultBridge.status)" }
    $ContinueArgs = @($Payload.hostResultBridge.continueArgs)
    $ContinueRaw = & php @ContinueArgs 2>&1
    $Payload | Add-Member -NotePropertyName continuePayload -NotePropertyValue ($ContinueRaw | ConvertFrom-Json) -Force
    $Payload | ConvertTo-Json -Depth 30
    exit 0
}

if (-not $Execute) {
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
$Payload | ConvertTo-Json -Depth 20
