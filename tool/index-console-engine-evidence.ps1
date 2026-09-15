param(
    [string]$EventLogPath,
    [int]$MaxPerClass = 20
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($EventLogPath)) {
    $McpRoot = Split-Path -Parent $Root
    $EventLogPath = Join-Path $McpRoot 'console-mcp\var\log\engine\event.jsonl'
}
if (-not (Test-Path -LiteralPath $EventLogPath -PathType Leaf)) {
    throw "Console engine event log not found: $EventLogPath"
}

$Classes = [ordered]@{
    retry = [System.Collections.Generic.List[object]]::new()
    rate_limit = [System.Collections.Generic.List[object]]::new()
    orphan = [System.Collections.Generic.List[object]]::new()
    human_decision = [System.Collections.Generic.List[object]]::new()
    stall = [System.Collections.Generic.List[object]]::new()
    completion = [System.Collections.Generic.List[object]]::new()
}
$LineCount = 0
$ParseErrors = 0

function Add-Candidate {
    param([string]$Class, $Event, [string]$EvidenceMarker)
    if ($Classes[$Class].Count -ge $MaxPerClass) { return }
    $Classes[$Class].Add([pscustomobject][ordered]@{
        coverageClass = $Class
        taskId = [string]$Event.task_id
        eventId = [string]$Event.event_id
        ts = [string]$Event.ts
        event = [string]$Event.event
        evidenceMarker = $EvidenceMarker
        immutableReceipt = $true
        origin = 'console_engine_history'
    })
}

foreach ($Line in [System.IO.File]::ReadLines($EventLogPath)) {
    $LineCount++
    if ([string]::IsNullOrWhiteSpace($Line)) { continue }
    try {
        $Event = $Line | ConvertFrom-Json -Depth 100
    } catch {
        $ParseErrors++
        continue
    }
    $Raw = $Line.ToLowerInvariant()
    $EventName = [string]$Event.event

    if ($Raw.Contains('"retryable":true')) {
        Add-Candidate -Class 'retry' -Event $Event -EvidenceMarker 'retryable:true'
    }
    if ($EventName -eq 'engine_rate_limit_cooldown_recorded' -or $Raw.Contains('"rate_limit_detected":true')) {
        Add-Candidate -Class 'rate_limit' -Event $Event -EvidenceMarker 'rate_limit_recorded'
    }
    if ($Raw.Contains('orphaned_answer') -or $Raw.Contains('orphaned answer') -or $Raw.Contains('resubmit_orphan')) {
        Add-Candidate -Class 'orphan' -Event $Event -EvidenceMarker 'orphan_marker'
    }
    if ($Raw.Contains('human_decision_required')) {
        Add-Candidate -Class 'human_decision' -Event $Event -EvidenceMarker 'human_decision_required'
    }
    if ($Raw.Contains('stalled_no_semantic_progress')) {
        Add-Candidate -Class 'stall' -Event $Event -EvidenceMarker 'stalled_no_semantic_progress'
    }
    if ($Raw.Contains('decision_done_verified:')) {
        Add-Candidate -Class 'completion' -Event $Event -EvidenceMarker 'decision_done_verified'
    }
}

$Counts = [ordered]@{}
foreach ($Key in $Classes.Keys) { $Counts[$Key] = $Classes[$Key].Count }

[pscustomobject][ordered]@{
    ok = $true
    status = 'CONSOLE_ENGINE_HISTORICAL_EVIDENCE_INDEXED'
    source = $EventLogPath
    sourceReadOnly = $true
    lineCount = $LineCount
    parseErrors = $ParseErrors
    counts = $Counts
    candidates = $Classes
} | ConvertTo-Json -Depth 20
