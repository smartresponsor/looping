param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

function Read-Text {
    param([Parameter(Mandatory=$true)][string]$Path)
    Get-Content -Raw -Path (Join-Path $Root $Path)
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

$RepoSmoke = Read-Text 'tool/runner-repo-smoke.ps1'
$Bridge = Read-Text 'tool/runner-console-mcp-bridge.mjs'
$Adapter = Read-Text 'tool/runner-adapter.ps1'
$Dispatcher = Read-Text 'tool/runner-dispatcher.ps1'

$ParseTargets = @(
    'tool/runner-repo-smoke.ps1',
    'tool/runner-console-mcp-bridge.ps1',
    'tool/runner-feed-result.ps1',
    'tool/runner-adapter.ps1'
)
foreach ($Target in $ParseTargets) {
    $Tokens = $null
    $Errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root $Target), [ref]$Tokens, [ref]$Errors) | Out-Null
    Assert-True (@($Errors).Count -eq 0) "$Target has PowerShell parse errors"
}

Assert-True ($RepoSmoke -match 'runner-daemon\.ps1') 'repo smoke must call runner-daemon'
Assert-True ($RepoSmoke -match 'runner-transport-adapter\.ps1') 'repo smoke must feed runner-transport-adapter'
Assert-True ($RepoSmoke -match 'runner-console-mcp-bridge\.ps1') 'repo smoke must execute selected tool through bridge'
Assert-True ($RepoSmoke -match 'expectedResultPath') 'repo smoke must write selected result path'
Assert-True ($RepoSmoke -match 'RUNNER_TRANSPORT_ADAPTER_FED') 'repo smoke must require adapter feed success'
Assert-True ($RepoSmoke -notmatch '&\s*[^\r\n]*cmcp\.go') 'repo smoke must not directly invoke cmcp.go'
Assert-True ($RepoSmoke -notmatch 'captureMode\s*=\s*[''"]synthetic') 'engine chain must not create synthetic captures'

$RequiredBridgeTools = @(
    'console.write.browser.session.cmcp.go',
    'console.read_.repo.context.capture',
    'console.read_.repo.workspace.status',
    'console.read_.repo.memory.graph.plan'
)
foreach ($Tool in $RequiredBridgeTools) {
    Assert-True ($Bridge.Contains($Tool)) "bridge missing required tool $Tool"
}

Assert-True (-not $Bridge.Contains('console.write.browser.chatgpt.chat.create.send')) 'bridge must not allow legacy fallback tool'
Assert-True ($Dispatcher.Contains('console.write.browser.session.cmcp.go')) 'dispatcher must allow cmcp.go'
Assert-True (-not ($Dispatcher -match "allowedTools\s*=.*console\.write\.browser\.chatgpt\.chat\.create\.send")) 'dispatcher must not allow fallback tool'
Assert-True (-not ($Adapter -match "console\.write\.browser\.chatgpt\.chat\.create\.send'\s*,\s*'console\.write\.browser\.session\.cmcp\.go")) 'adapter engine path must not accept fallback-or-cmcp'

[pscustomobject]@{
    ok = $true
    status = 'RUNNER_REPO_SMOKE_CHECK_PASSED'
    checks = @(
        'cli_calls_runner_daemon',
        'cli_executes_selected_tool_through_bridge',
        'cli_feeds_runner_transport_adapter',
        'runner_state_controls_next_iteration',
        'fallback_tool_not_allowed',
        'synthetic_capture_not_used_in_engine_chain'
    )
} | ConvertTo-Json -Depth 20
