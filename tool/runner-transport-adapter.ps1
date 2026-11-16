param(
    [Parameter(Mandatory=$true)][string]$Task,
    [Parameter(Mandatory=$true)][string]$PayloadPath,
    [Parameter(Mandatory=$true)][string]$ResultPath,
    [int]$MaxIterations = 1,
    [int]$RetryAttempt = 0,
    [switch]$UntilRc
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$RunnerLockPath = $null
trap {
    if (-not $InheritedScheduledLock -and $RunnerLockPath -and (Test-Path $RunnerLockPath)) { Remove-Item -Path $RunnerLockPath -Force }
    throw $_
}
$Dispatcher = Join-Path $Root 'tool/runner-dispatcher.ps1'
$Runner = Join-Path $Root 'tool/runner-adapter.ps1'
$LockDir = Join-Path $Root 'var/runner/lock'
New-Item -ItemType Directory -Path $LockDir -Force | Out-Null
$CandidateLockPath = Join-Path $LockDir 'runner.lock'
$InheritedScheduledLock = $false
if (-not [string]::IsNullOrWhiteSpace([string]$env:LOOPING_SCHEDULE_SESSION_TOKEN)) {
    if (-not (Test-Path -LiteralPath $CandidateLockPath)) { throw 'TRANSPORT_SCHEDULE_LOCK_MISSING' }
    try { $SessionLock = Get-Content -Raw -LiteralPath $CandidateLockPath | ConvertFrom-Json }
    catch { throw 'TRANSPORT_SCHEDULE_LOCK_INVALID' }
    if ($SessionLock.owner -ne 'scheduled-task' -or $SessionLock.sessionToken -ne $env:LOOPING_SCHEDULE_SESSION_TOKEN) { throw 'TRANSPORT_SCHEDULE_LOCK_MISMATCH' }
    $InheritedScheduledLock = $true
}
if (-not $InheritedScheduledLock) {
try {
    $Handle = [System.IO.File]::Open($CandidateLockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
} catch [System.IO.IOException] {
    [pscustomobject]@{ ok = $false; status = 'RUNNER_LOCK_BUSY'; lockPath = $CandidateLockPath; nextAction = 'manual_reconcile_if_stale' } | ConvertTo-Json -Depth 20
    exit 0
}
$RunnerLockPath = $CandidateLockPath
try {
    $Payload = [pscustomobject]@{ owner = 'runner-transport-adapter'; pid = $PID; acquiredAt = (Get-Date).ToUniversalTime().ToString('o') }
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Depth 20))
    $Handle.Write($Bytes, 0, $Bytes.Length)
    $Handle.Flush($true)
} finally {
    $Handle.Dispose()
}
}

function Write-RunnerJournalEvent {
    param([Parameter(Mandatory=$true)]$Event)
    $JournalDir = Join-Path $Root 'var/runner/journal'
    if (-not (Test-Path $JournalDir)) { New-Item -ItemType Directory -Path $JournalDir | Out-Null }
    $JournalPath = Join-Path $JournalDir 'runner.ndjson'
    $Event | Add-Member -NotePropertyName writtenAt -NotePropertyValue (Get-Date).ToUniversalTime().ToString('o') -Force
    ([pscustomobject]$Event | ConvertTo-Json -Depth 40 -Compress) + "`n" | Add-Content -Path $JournalPath -Encoding UTF8
    return $JournalPath
}

function Get-OptionalProperty {
    param($InputObject, [string]$Name)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject.PSObject.Properties.Name -contains $Name) { return $InputObject.$Name }
    return $null
}

$DispatchPayload = Get-Content -Raw -Path $PayloadPath | ConvertFrom-Json
$ExpectedTool = [string]$DispatchPayload.runnerExecutionPlan.tool
$RawResult = Get-Content -Raw -Path $ResultPath | ConvertFrom-Json
$MissingFields = @()
if ($null -eq $RawResult.ok) { $MissingFields += 'ok' }
if (-not $RawResult.tool) { $MissingFields += 'tool' }
if (-not $RawResult.status) { $MissingFields += 'status' }
if ($MissingFields.Count -gt 0) {
    if (-not $InheritedScheduledLock -and (Test-Path $RunnerLockPath)) { Remove-Item -Path $RunnerLockPath -Force }
    [pscustomobject]@{ ok = $false; status = 'RUNNER_TRANSPORT_RESULT_CONTRACT_INVALID'; missingFields = $MissingFields; expectedTool = $ExpectedTool; nextAction = 'rewrite_executor_result_file' } | ConvertTo-Json -Depth 40
    exit 0
}
if ([string]$RawResult.tool -ne $ExpectedTool) {
    if (-not $InheritedScheduledLock -and (Test-Path $RunnerLockPath)) { Remove-Item -Path $RunnerLockPath -Force }
    [pscustomobject]@{ ok = $false; status = 'RUNNER_TRANSPORT_RESULT_TOOL_MISMATCH'; expectedTool = $ExpectedTool; actualTool = [string]$RawResult.tool; nextAction = 'rewrite_executor_result_file' } | ConvertTo-Json -Depth 40
    exit 0
}

$AcceptedRaw = & $Dispatcher -PayloadPath $PayloadPath -ResultPath $ResultPath 2>&1
$Accepted = $AcceptedRaw | ConvertFrom-Json
if ($Accepted.status -ne 'DISPATCHER_TRANSPORT_RESULT_ACCEPTED') {
    if (-not $InheritedScheduledLock -and (Test-Path $RunnerLockPath)) { Remove-Item -Path $RunnerLockPath -Force }
    [pscustomobject]@{ ok = $false; status = 'RUNNER_TRANSPORT_ADAPTER_RESULT_REJECTED'; accepted = $Accepted; nextAction = 'inspect_transport_result' } | ConvertTo-Json -Depth 40
    exit 0
}
$AcceptedPath = Join-Path (Split-Path -Parent $ResultPath) ('accepted-' + (Split-Path -Leaf $ResultPath))
$Accepted | ConvertTo-Json -Depth 40 | Set-Content -Path $AcceptedPath -Encoding UTF8

$RunnerArgs = @{ Task = $Task; MaxIterations = $MaxIterations; RetryAttempt = $RetryAttempt; TransportResultPath = $AcceptedPath }
if ($UntilRc) { $RunnerArgs.UntilRc = $true }
$FeedRaw = & $Runner @RunnerArgs 2>&1
$Feed = $FeedRaw | ConvertFrom-Json
$JournalPath = Write-RunnerJournalEvent ([ordered]@{ component = 'runner-transport-adapter'; status = 'RUNNER_TRANSPORT_ADAPTER_FED'; action = 'transport_result_accepted_and_fed'; task = $Task; expectedTool = $ExpectedTool; payloadPath = $PayloadPath; resultPath = $ResultPath; acceptedPath = $AcceptedPath })
[pscustomobject]@{
    ok = $true
    status = 'RUNNER_TRANSPORT_ADAPTER_FED'
    lockReleased = $(if (-not $InheritedScheduledLock -and (Test-Path $RunnerLockPath)) { Remove-Item -Path $RunnerLockPath -Force; $true } else { $false })
    action = 'transport_result_accepted_and_fed'
    payloadPath = $PayloadPath
    resultPath = $ResultPath
    acceptedPath = $AcceptedPath
    accepted = $Accepted
    feed = $Feed
    nextAction = $(
        $FeedNextDispatchPayload = Get-OptionalProperty -InputObject $Feed -Name 'nextDispatchPayload'
        $FeedFinalActionResult = Get-OptionalProperty -InputObject $Feed -Name 'finalActionResult'
        $FeedFinalNextAction = Get-OptionalProperty -InputObject $FeedFinalActionResult -Name 'nextAction'
        if ($FeedNextDispatchPayload) { 'invoke_next_dispatch_payload' } elseif ($FeedFinalNextAction) { $FeedFinalNextAction } else { 'wait_or_review' }
    )
} | ConvertTo-Json -Depth 60
