param(
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$BaselinePath = Join-Path $Root 'config/orchestration-boundary-baseline.json'

if (-not (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) {
    throw "orchestration boundary baseline not found: $BaselinePath"
}

$Baseline = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
$LegacyFiles = @($Baseline.legacyReferenceFiles | ForEach-Object { ([string]$_).Replace([char]92,[char]47) })
$Prefixes = @($Baseline.forbiddenOwnershipPrefixes | ForEach-Object { [string]$_ })

$Found = @()
foreach ($Prefix in $Prefixes) {
    $Raw = & git -C $Root grep -n -I -F -- $Prefix -- . 2>$null
    if ($LASTEXITCODE -notin @(0,1)) {
        throw "git grep failed for prefix $Prefix"
    }
    foreach ($Line in @($Raw)) {
        if ([string]::IsNullOrWhiteSpace([string]$Line)) { continue }
        if ($Line -notmatch '^([^:]+):(\d+):(.*)$') { continue }
        $File = $Matches[1].Replace([char]92,[char]47)
        $Found += [pscustomobject]@{
            prefix = $Prefix
            file = $File
            line = [int]$Matches[2]
            text = $Matches[3].Trim()
            legacy = ($LegacyFiles -contains $File)
            production = ($File -match '^(src|tool|bin)/')
        }
    }
}

$NewBoundaryViolations = @($Found | Where-Object { $_.production -and -not $_.legacy })
$RemainingProductionDependencies = @($Found | Where-Object { $_.production })
$MigrationComplete = ($RemainingProductionDependencies.Count -eq 0)
$BaselineStable = ($NewBoundaryViolations.Count -eq 0)
$Ok = if ($Strict) { $BaselineStable -and $MigrationComplete } else { $BaselineStable }

$Payload = [ordered]@{
    ok = $Ok
    status = if (-not $BaselineStable) {
        'ORCHESTRATION_BOUNDARY_REGRESSION'
    } elseif ($MigrationComplete) {
        'ORCHESTRATION_SHADOW_MIGRATION_COMPLETE'
    } elseif ($Strict) {
        'ORCHESTRATION_CUTOVER_NOT_READY'
    } else {
        'ORCHESTRATION_SHADOW_BOUNDARY_STABLE'
    }
    mode = if ($Strict) { 'cutover_gate' } else { 'shadow_guard' }
    divergencePoint = [string]$Baseline.divergencePoint
    consoleMcpBehavioralBaseline = [string]$Baseline.consoleMcpBehavioralBaseline
    baselineStable = $BaselineStable
    migrationComplete = $MigrationComplete
    matchCount = $Found.Count
    remainingProductionDependencyCount = $RemainingProductionDependencies.Count
    newBoundaryViolationCount = $NewBoundaryViolations.Count
    remainingProductionFiles = @($RemainingProductionDependencies.file | Sort-Object -Unique)
    newBoundaryViolations = @($NewBoundaryViolations)
    nextAction = if (-not $BaselineStable) {
        'remove_new_console_orchestration_dependency'
    } elseif (-not $MigrationComplete) {
        'continue_shadow_migration_without_cutover'
    } else {
        'run_full_parity_and_cutover_acceptance'
    }
}

$Payload | ConvertTo-Json -Depth 40
if (-not $Ok) { exit 1 }
