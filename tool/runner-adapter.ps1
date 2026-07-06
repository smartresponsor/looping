param(
    [Parameter(Mandatory=$true)][string]$Task,
    [string]$Mode = 'repo_rc_implementation',
    [int]$MaxIterations = 1,
    [switch]$UntilRc,
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$ArgsList = @('bin/console', 'chatgpt-loop:run', "--task=$Task", "--mode=$Mode")

if ($UntilRc) { $ArgsList += '--until-rc=1' } else { $ArgsList += "--max-iterations=$MaxIterations" }

$Raw = & php @ArgsList 2>&1
$Payload = $Raw | ConvertFrom-Json

if (-not $Payload.dispatchEnvelope) { throw 'dispatchEnvelope missing' }
if (-not $Payload.dispatchEnvelope.tool) { throw 'dispatchEnvelope.tool missing' }
if ($Payload.dispatchEnvelope.confirmationRequired -eq $true) { throw 'confirmation required before execution' }
if ($Payload.dispatchEnvelope.mutation -ne 'none') { throw "non-read-only envelope blocked: $($Payload.dispatchEnvelope.mutation)" }

$Payload | Add-Member -NotePropertyName runnerMode -NotePropertyValue ($(if ($Execute) { 'execute_read_only' } else { 'dry_run' })) -Force

if (-not $Execute) {
    $Payload | ConvertTo-Json -Depth 20
    exit 0
}

$Payload | Add-Member -NotePropertyName executionResult -NotePropertyValue @{ ok = $false; status = 'EXECUTE_NOT_WIRED'; reason = 'Console MCP invocation is intentionally not wired in this adapter yet.' } -Force
$Payload | ConvertTo-Json -Depth 20
