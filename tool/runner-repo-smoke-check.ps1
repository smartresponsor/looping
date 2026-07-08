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
$TaskBankLoop = Read-Text 'tool/runner-task-bank-loop.ps1'
$Bridge = Read-Text 'tool/runner-console-mcp-bridge.mjs'
$Adapter = Read-Text 'tool/runner-adapter.ps1'
$Dispatcher = Read-Text 'tool/runner-dispatcher.ps1'

$ParseTargets = @(
    'tool/runner-repo-smoke.ps1',
    'tool/runner-console-mcp-bridge.ps1',
    'tool/runner-feed-result.ps1',
    'tool/runner-adapter.ps1'
    'tool/runner-task-bank-loop.ps1'
)
foreach ($Target in $ParseTargets) {
    $Tokens = $null
    $Errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root $Target), [ref]$Tokens, [ref]$Errors) | Out-Null
    Assert-True (@($Errors).Count -eq 0) "$Target has PowerShell parse errors"
}

Assert-True ($RepoSmoke -match 'runner-daemon\.ps1') 'repo smoke must call runner-daemon'
Assert-True ($RepoSmoke -match 'runner-task-bank-loop\.ps1') 'repo smoke must route engine chain through task-bank loop helper'
Assert-True ($RepoSmoke -match 'runner-transport-adapter\.ps1') 'repo smoke must feed runner-transport-adapter'
Assert-True ($RepoSmoke -match 'runner-console-mcp-bridge\.ps1') 'repo smoke must execute selected tool through bridge'
Assert-True ($RepoSmoke -match 'expectedResultPath') 'repo smoke must write selected result path'
Assert-True ($RepoSmoke -match 'RUNNER_TRANSPORT_ADAPTER_FED') 'repo smoke must require adapter feed success'
Assert-True ($RepoSmoke -notmatch '&\s*[^\r\n]*cmcp\.go') 'repo smoke must not directly invoke cmcp.go'
Assert-True ($RepoSmoke -notmatch 'captureMode\s*=\s*[''"]synthetic') 'engine chain must not create synthetic captures'
Assert-True ($TaskBankLoop -match 'interactionCycleCount') 'final output must expose interactionCycleCount'
Assert-True ($TaskBankLoop -match 'internalStepCount') 'final output must expose internalStepCount'
Assert-True ($TaskBankLoop -match 'task-bank') 'task-bank state must be used'
Assert-True ($TaskBankLoop -match 'chat-bank') 'chat-bank state must be used'
Assert-True ($TaskBankLoop -match 'answerCaptured') 'answer capture progress must be emitted'
Assert-True ($TaskBankLoop -match 'decisionApplied') 'decision consumption must happen after answer capture'
Assert-True ($TaskBankLoop -match "TOOL_CALL_BLOCKED") 'blocked tool calls must be semantic outcomes'
Assert-True ($TaskBankLoop -notmatch 'interactionCount\\s*=\\s*\\[int\\]\\$Task\\.interactionCount \\+ 1[\\s\\S]{0,400}uiSubmit') 'submit alone must not increment interaction count'
Assert-True ($TaskBankLoop -notmatch "console\\.read_\\.repo\\.workspace\\.status[\\s\\S]{0,300}interactionCount\\s*=") 'repo status must not increment interaction count'
Assert-True ($TaskBankLoop -notmatch "console\\.read_\\.repo\\.memory\\.graph\\.plan[\\s\\S]{0,300}interactionCount\\s*=") 'memory graph must not increment interaction count'
Assert-True ($Adapter -match '\$NextDispatchProperties\s*=\s*@\(\$NextDispatchContract\.PSObject\.Properties\.Name\)') 'adapter must inspect nextDispatchContract properties before reading shape-specific members'
Assert-True ($Adapter -match '\$HasSequenceContract\s*=\s*\$NextDispatchProperties\s+-contains\s+''sequence''') 'adapter must support sequence nextDispatchContract'
Assert-True ($Adapter -match '\$HasSingleToolContract\s*=\s*\(\$NextDispatchProperties\s+-contains\s+''tool''\)\s+-and\s+\(\$NextDispatchProperties\s+-contains\s+''arguments''\)') 'adapter must support single-tool nextDispatchContract'
Assert-True ($Adapter -match '\$Contracts\s*\+=\s*\$NextDispatchContract') 'single-tool nextDispatchContract must normalize to one contract'
Assert-True ($Adapter -match '(?s)elseif \(\$HasSingleToolContract\).*?else \{\s*return\s*\}') 'adapter must skip gracefully when nextDispatchContract has no supported shape'

$RequiredBridgeTools = @(
    'console.write.browser.session.cmcp.go',
    'console.read_.browser.chatgpt.composer.preflight',
    'console.read_.browser.chatgpt.watch.probe',
    'console.read_.browser.chatgpt.watch.next',
    'console.read_.browser.chatgpt.run.loop.plan',
    'console.read_.browser.chatgpt.run.loop.step',
    'console.read_.browser.chatgpt.run.loop.step.summary',
    'console.read_.browser.chatgpt.run.loop.auto.summary',
    'console.read_.browser.chatgpt.answer.settle',
    'console.write.browser.session.run.loop.daemon.start',
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
        'synthetic_capture_not_used_in_engine_chain',
        'max_iterations_counts_ui_cycles_only',
        'task_bank_chat_bank_persisted',
        'watcher_tools_reused',
        'single_tool_next_dispatch_contract'
    )
} | ConvertTo-Json -Depth 20
