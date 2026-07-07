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
$Dispatcher = Join-Path $Root 'tool/runner-dispatcher.ps1'
$Runner = Join-Path $Root 'tool/runner-adapter.ps1'

$AcceptedRaw = & $Dispatcher -PayloadPath $PayloadPath -ResultPath $ResultPath 2>&1
$Accepted = $AcceptedRaw | ConvertFrom-Json
if ($Accepted.status -ne 'DISPATCHER_TRANSPORT_RESULT_ACCEPTED') {
    [pscustomobject]@{ ok = $false; status = 'RUNNER_TRANSPORT_ADAPTER_RESULT_REJECTED'; accepted = $Accepted; nextAction = 'inspect_transport_result' } | ConvertTo-Json -Depth 40
    exit 0
}
$AcceptedPath = Join-Path (Split-Path -Parent $ResultPath) ('accepted-' + (Split-Path -Leaf $ResultPath))
$Accepted | ConvertTo-Json -Depth 40 | Set-Content -Path $AcceptedPath -Encoding UTF8

$RunnerArgs = @('-Task', $Task, '-MaxIterations', $MaxIterations, '-RetryAttempt', $RetryAttempt, '-TransportResultPath', $AcceptedPath)
if ($UntilRc) { $RunnerArgs += '-UntilRc' }
$FeedRaw = & $Runner @RunnerArgs 2>&1
$Feed = $FeedRaw | ConvertFrom-Json
[pscustomobject]@{
    ok = $true
    status = 'RUNNER_TRANSPORT_ADAPTER_FED'
    action = 'transport_result_accepted_and_fed'
    payloadPath = $PayloadPath
    resultPath = $ResultPath
    acceptedPath = $AcceptedPath
    accepted = $Accepted
    feed = $Feed
    nextAction = if ($Feed.nextDispatchPayload) { 'invoke_next_dispatch_payload' } elseif ($Feed.finalActionResult) { $Feed.finalActionResult.nextAction } else { 'wait_or_review' }
} | ConvertTo-Json -Depth 60
