param(
    [string]$Task = 'cmcp go cataloging',
    [int]$MaxIterations = 3
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Runner = Join-Path $Root 'tool/runner-adapter.ps1'

$Raw = & $Runner -Task $Task -MaxIterations $MaxIterations -Dispatch -SimulateHost 2>&1
$Payload = $Raw | ConvertFrom-Json

if (-not $Payload.dispatcherPayload) { throw 'dispatcherPayload missing' }
if ($Payload.dispatcherPayload.status -ne 'DISPATCHER_SIMULATED_RESULT') { throw "dispatcher did not simulate result: $($Payload.dispatcherPayload.status)" }
if (-not $Payload.dispatchedHostPayload) { throw 'dispatchedHostPayload missing' }
if (-not $Payload.continuePayload) { throw 'continuePayload missing' }
if ($Payload.continuePayload.dispatchResult.status -ne 'DISPATCH_RESULT_ACCEPTED') { throw "dispatch result was not accepted: $($Payload.continuePayload.dispatchResult.status)" }
if ($Payload.continuePayload.resumeState.status -ne 'RESUME_STATE_ADVANCED') { throw "resume state did not advance: $($Payload.continuePayload.resumeState.status)" }

[pscustomobject]@{
    ok = $true
    status = 'RUNNER_SMOKE_PASSED'
    task = $Task
    continueRunId = $Payload.continuePayload.runId
} | ConvertTo-Json -Depth 10
