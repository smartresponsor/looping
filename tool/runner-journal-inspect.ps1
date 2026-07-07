param(
    [int]$Tail = 20,
    [string]$Task,
    [string]$Component,
    [switch]$SummaryOnly
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$JournalPath = Join-Path $Root 'var/runner/journal/runner.ndjson'

if (-not (Test-Path $JournalPath)) {
    [pscustomobject]@{
        ok = $true
        status = 'RUNNER_JOURNAL_EMPTY'
        journalPath = $JournalPath
        totalEvents = 0
        events = @()
        summary = @()
    } | ConvertTo-Json -Depth 40
    exit 0
}

$Events = @()
Get-Content -Path $JournalPath | Where-Object { $_ -and $_.Trim() } | ForEach-Object {
    $Events += ($_ | ConvertFrom-Json)
}

if ($Task) { $Events = @($Events | Where-Object { [string]$_.task -eq $Task }) }
if ($Component) { $Events = @($Events | Where-Object { [string]$_.component -eq $Component }) }

$Summary = @(
    $Events |
        Group-Object -Property component, status |
        ForEach-Object {
            $Parts = $_.Name -split ', '
            [pscustomobject]@{
                component = if ($Parts.Count -gt 0) { $Parts[0] } else { '' }
                status = if ($Parts.Count -gt 1) { $Parts[1] } else { '' }
                count = $_.Count
            }
        }
)

$TailEvents = if ($Tail -gt 0) { @($Events | Select-Object -Last $Tail) } else { @() }
[pscustomobject]@{
    ok = $true
    status = 'RUNNER_JOURNAL_INSPECTED'
    journalPath = $JournalPath
