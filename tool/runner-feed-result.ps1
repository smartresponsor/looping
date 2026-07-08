param(
    [Parameter(Mandatory=$true)][string]$ResultPath,
    [int]$MaxIterations = 1,
    [int]$RetryAttempt = 0,
    [switch]$UntilRc
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Adapter = Join-Path $Root 'tool/runner-transport-adapter.ps1'
$StatePath = Join-Path $Root 'var/runner/state/latest.json'

function Resolve-PayloadPath {
    param([Parameter(Mandatory=$true)][string]$Path)

    if ($Path -notmatch '\.result\.json$') {
        return $null
    }

    $Candidate = $Path -replace '\.result\.json$', '.json'
    if (Test-Path $Candidate) {
        return $Candidate
    }

    return $null
}

function Resolve-RunnerTask {
    param(
        [Parameter(Mandatory=$true)]$Payload,
        $State
    )

    if ($Payload.taskId) { return [string]$Payload.taskId }
    if ($Payload.requestedTaskId) { return [string]$Payload.requestedTaskId }
    if ($Payload.handoff -and $Payload.handoff.task) { return [string]$Payload.handoff.task }
    if ($State -and $State.taskId) { return [string]$State.taskId }

    return $null
}

if (-not (Test-Path $ResultPath)) {
    [pscustomobject]@{ ok = $false; status = 'RUNNER_FEED_RESULT_NOT_FOUND'; resultPath = $ResultPath; nextAction = 'write_executor_result_file' } | ConvertTo-Json -Depth 20
    exit 0
}

$PayloadPath = Resolve-PayloadPath -Path $ResultPath
if (-not $PayloadPath) {
    [pscustomobject]@{ ok = $false; status = 'RUNNER_FEED_PAYLOAD_PATH_NOT_INFERRED'; resultPath = $ResultPath; nextAction = 'pass_matching_payload_path_or_use_standard_result_name' } | ConvertTo-Json -Depth 20
    exit 0
}

if (-not (Test-Path $PayloadPath)) {
    [pscustomobject]@{ ok = $false; status = 'RUNNER_FEED_PAYLOAD_NOT_FOUND'; payloadPath = $PayloadPath; resultPath = $ResultPath; nextAction = 'restore_dispatch_payload_file' } | ConvertTo-Json -Depth 20
    exit 0
}

$Payload = Get-Content -Raw -Path $PayloadPath | ConvertFrom-Json
$State = if (Test-Path $StatePath) { Get-Content -Raw -Path $StatePath | ConvertFrom-Json } else { $null }
$Task = Resolve-RunnerTask -Payload $Payload -State $State
if (-not $Task) {
    [pscustomobject]@{ ok = $false; status = 'RUNNER_FEED_TASK_NOT_INFERRED'; payloadPath = $PayloadPath; resultPath = $ResultPath; nextAction = 'rerun_runner_with_task_seed' } | ConvertTo-Json -Depth 20
    exit 0
}

$AdapterArgs = @{ Task = $Task; PayloadPath = $PayloadPath; ResultPath = $ResultPath; MaxIterations = $MaxIterations; RetryAttempt = $RetryAttempt }
if ($UntilRc) { $AdapterArgs.UntilRc = $true }

$AdapterRaw = & $Adapter @AdapterArgs 2>&1
$AdapterPayload = $AdapterRaw | ConvertFrom-Json

[pscustomobject]@{
    ok = [bool]$AdapterPayload.ok
    status = 'RUNNER_FEED_RESULT_COMPLETED'
    task = $Task
    payloadPath = $PayloadPath
    resultPath = $ResultPath
    adapterStatus = [string]$AdapterPayload.status
    adapterNextAction = [string]$AdapterPayload.nextAction
    adapter = $AdapterPayload
} | ConvertTo-Json -Depth 60
