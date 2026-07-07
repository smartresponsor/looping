param(
    [int]$KeepFiles = 200,
    [int]$KeepJournalLines = 2000,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Deleted = @()

function Remove-OldRunnerFile {
    param([string]$Directory, [string]$Pattern, [int]$Keep)
    if (-not (Test-Path $Directory)) { return }
    $Files = @(Get-ChildItem -Path $Directory -File -Filter $Pattern | Sort-Object LastWriteTimeUtc -Descending)
    if ($Files.Count -le $Keep) { return }
    foreach ($File in @($Files | Select-Object -Skip $Keep)) {
        $script:Deleted += $File.FullName
        if (-not $DryRun) { Remove-Item -Path $File.FullName -Force }
    }
}

$NextDispatchDir = Join-Path $Root 'var/runner/next-dispatch'
Remove-OldRunnerFile -Directory $NextDispatchDir -Pattern '*.json' -Keep $KeepFiles
Remove-OldRunnerFile -Directory $NextDispatchDir -Pattern '*.handoff.json' -Keep $KeepFiles
Remove-OldRunnerFile -Directory (Join-Path $Root 'var/runner') -Pattern '*.result.json' -Keep $KeepFiles
Remove-OldRunnerFile -Directory (Join-Path $Root 'var/runner') -Pattern 'accepted-*.json' -Keep $KeepFiles

$JournalPath = Join-Path $Root 'var/runner/journal/runner.ndjson'
$JournalTrimmed = $false
if (Test-Path $JournalPath) {
    $Lines = @(Get-Content -Path $JournalPath)
    if ($Lines.Count -gt $KeepJournalLines) {
        $JournalTrimmed = $true
        if (-not $DryRun) { @($Lines | Select-Object -Last $KeepJournalLines) | Set-Content -Path $JournalPath -Encoding UTF8 }
    }
}

[pscustomobject]@{
    ok = $true
    status = 'RUNNER_CLEANUP_COMPLETED'
    dryRun = [bool]$DryRun
    keepFiles = $KeepFiles
    keepJournalLines = $KeepJournalLines
    deletedCount = @($Deleted).Count
    deleted = $Deleted
