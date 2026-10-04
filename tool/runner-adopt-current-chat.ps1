param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,119}$')][string]$ComponentName,
    [Parameter(Mandatory=$true)][string]$ExistingLocation,
    [ValidateRange(1,100)][int]$MaxIterations = 3,
    [string]$WorkspaceRoot = ''
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Split-Path -Parent (Split-Path -Parent $Root)
}
$Bridge = Join-Path $Root 'tool/runner-console-mcp-bridge.ps1'
$BridgeDir = Join-Path $Root 'var/runner/task-bank/bridge'
$ChatId = $null
if ($ExistingLocation -match '^[0-9a-fA-F-]{36}$') {
    $ChatId = $ExistingLocation.ToLowerInvariant()
} elseif ($ExistingLocation -match '^https://(?:chatgpt\.com|chat\.openai\.com)/(?:c|chat)/([0-9a-fA-F-]{36})/?$') {
    $ChatId = $Matches[1].ToLowerInvariant()
}
$TargetRepo = Join-Path $WorkspaceRoot $ComponentName
if (-not (Test-Path -LiteralPath $TargetRepo -PathType Container)) {
    [pscustomobject]@{
        ok = $false
        status = 'ADOPT_TARGET_REPOSITORY_NOT_FOUND'
        componentName = $ComponentName
        targetRepo = $TargetRepo
        chatId = $ChatId
        nextAction = 'provide_existing_component_name'
    } | ConvertTo-Json -Depth 20
    exit 1
}

$null = New-Item -ItemType Directory -Path $BridgeDir -Force
$Id = [guid]::NewGuid().ToString('N')
$PayloadPath = Join-Path $BridgeDir ($Id + '.payload.json')
$ResultPath = Join-Path $BridgeDir ($Id + '.result.json')
$Arguments = [ordered]@{
    componentName = $ComponentName
    workspacePath = $TargetRepo
    maxAutoIterations = $MaxIterations
    activate = $true
    recoverComposer = $false
    confirmGo = $true
    timeoutMs = 30000
}
if ($ChatId) { $Arguments.preferredChatId = $ChatId } else { $Arguments.locator = $ExistingLocation }
$Payload = [ordered]@{ runnerExecutionPlan = [ordered]@{ tool = 'write.browser.chatgpt.chat.adopt_go'; arguments = $Arguments } }
$Payload | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $PayloadPath -Encoding UTF8
$Raw = & $Bridge -PayloadPath $PayloadPath -ResultPath $ResultPath 2>&1
$BridgeExitCode = $LASTEXITCODE
if (-not (Test-Path -LiteralPath $ResultPath -PathType Leaf)) { throw "adopt result was not written: $ResultPath`n$Raw" }
$ResultRaw = Get-Content -Raw -LiteralPath $ResultPath
$ResultRaw
try {
    $Result = $ResultRaw | ConvertFrom-Json -Depth 30
    if ($Result.ok -ne $true) { exit 1 }
} catch {
    if ($BridgeExitCode -ne 0) { exit $BridgeExitCode }
    throw "adopt result is not valid JSON: $ResultPath"
}
exit $BridgeExitCode
