param(
    [Parameter(Mandatory=$true)][string]$Task,
    [string]$Mode = 'repo_rc_implementation',
    [int]$MaxIterations = 1,
    [switch]$UntilRc,
    [switch]$Execute,
    [switch]$Continue,
    [switch]$SimulateHost,
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

$Payload | Add-Member -NotePropertyName runnerMode -NotePropertyValue ($(if ($SimulateHost) { 'simulate_host_e2e' } elseif ($Continue) { 'continue' } elseif ($Execute) { 'execute_read_only' } else { 'dry_run' })) -Force

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
    status = 'EXECUTE_READ_ONLY_READY'
    tool = $Payload.runnerExecutionPlan.tool
    arguments = $Payload.runnerExecutionPlan.arguments
    hostCallRequired = $Payload.runnerExecutionPlan.hostCallRequired
    resultMapping = $Payload.runnerExecutionPlan.resultMapping
    reason = 'Host runner must invoke the allowlisted read-only Console MCP tool with these arguments.'
} -Force
$Payload | ConvertTo-Json -Depth 20
