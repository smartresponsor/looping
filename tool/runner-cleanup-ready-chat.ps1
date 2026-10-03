[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ChatId
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Bridge = Join-Path $Root 'tool/runner-console-mcp-bridge.ps1'
$WorkDir = Join-Path $Root 'var/runner/cleanup-proof'
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }

function Invoke-BridgeTool {
    param([Parameter(Mandatory=$true)][string]$Tool, [Parameter(Mandatory=$true)]$Arguments)
    $Id = [guid]::NewGuid().ToString('N')
    $PayloadPath = Join-Path $WorkDir ($Id + '.payload.json')
    $ResultPath = Join-Path $WorkDir ($Id + '.result.json')
    [pscustomobject]@{
        runnerExecutionPlan = [ordered]@{
            tool = $Tool
            arguments = $Arguments
        }
    } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $PayloadPath -Encoding UTF8
    $Raw = & $Bridge -PayloadPath $PayloadPath -ResultPath $ResultPath 2>&1
    $BridgeResult = $Raw | ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $ResultPath -PathType Leaf)) { throw "Bridge result missing for $Tool" }
    $Result = Get-Content -LiteralPath $ResultPath -Raw | ConvertFrom-Json
    [pscustomobject]@{ bridge = $BridgeResult; result = $Result }
}

function Get-ReadyToDeleteSignal {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $null }
    $VisibleLines = @()
    $InsideFence = $false
    foreach ($Line in @($Text -split '\r?\n|\r')) {
        $Trimmed = ([string]$Line).Trim()
        if ($Trimmed.StartsWith('```')) { $InsideFence = -not $InsideFence; continue }
        if (-not $InsideFence -and $Trimmed -ne '') { $VisibleLines += $Trimmed }
    }
    $Tail = @($VisibleLines | Select-Object -Last 5)
    $HasTrue = @($Tail | Where-Object { $_ -ceq '{"ready_to_delete":true}' }).Count -gt 0
    $HasFalse = @($Tail | Where-Object { $_ -ceq '{"ready_to_delete":false}' }).Count -gt 0
    if ($HasTrue -eq $HasFalse) { return $null }
    return $HasTrue
}

$Settle = Invoke-BridgeTool -Tool 'read_.browser.chatgpt.answer.settle' -Arguments ([ordered]@{
    ports = @(9222, 9223)
    preferredChatId = $ChatId
    requireChatId = $true
    maxMessages = 40
    timeoutMs = 3000
    readinessProfile = 'quick_probe'
    maxWaitMs = 10000
    observationBudgetMs = 5000
    pollMs = 1000
    minStableSamples = 2
    idleQuietMs = 2000
    requireComposerSendMode = $false
})

$Text = if ($Settle.result.latest_assistant -and $Settle.result.latest_assistant.text) { [string]$Settle.result.latest_assistant.text } else { '' }
$Signal = Get-ReadyToDeleteSignal -Text $Text
if ($Settle.result.ok -ne $true -or $Settle.result.status -ne 'ANSWER_STABLE' -or $Signal -ne $true) {
    [pscustomobject]@{
        ok = $false
        status = 'READY_TO_DELETE_PROOF_NOT_SATISFIED'
        chatId = $ChatId
        settleStatus = [string]$Settle.result.status
        readyToDelete = $Signal
        action = 'keep'
    } | ConvertTo-Json -Depth 20
    exit 0
}

$ResolvedChatId = if ($Settle.result.selected -and $Settle.result.selected.chat_id) { [string]$Settle.result.selected.chat_id } else { $null }
if ($ResolvedChatId -ne $ChatId) { throw "Resolved chat id mismatch: expected=$ChatId actual=$ResolvedChatId" }

$Delete = Invoke-BridgeTool -Tool 'write.browser.chatgpt.chat.delete.execute' -Arguments ([ordered]@{
    ports = @(9222, 9223)
    expectedChatId = $ResolvedChatId
    authorizationMode = 'lifecycle_ready_to_delete'
    readyToDelete = $true
    closeTarget = $true
    timeoutMs = 5000
})

[pscustomobject]@{
    ok = ($Delete.result.ok -eq $true)
    status = [string]$Delete.result.status
    chatId = $ResolvedChatId
    readyToDelete = $true
    stillVisible = $Delete.result.still_visible
    deleteInnerStatus = if ($Delete.result.delete) { [string]$Delete.result.delete.status } else { $null }
    patchHttpStatus = if ($Delete.result.delete) { $Delete.result.delete.patch_http_status } else { $null }
    patchBodyPreview = if ($Delete.result.delete) { $Delete.result.delete.patch_body_preview } else { $null }
    targetCloseStatus = if ($Delete.result.target_close) { [string]$Delete.result.target_close.status } else { $null }
    action = if ($Delete.result.ok -eq $true) { 'deleted_and_closed' } else { 'keep_for_review' }
} | ConvertTo-Json -Depth 30
