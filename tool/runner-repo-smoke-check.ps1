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
$BridgeWrapper = Read-Text 'tool/runner-console-mcp-bridge.ps1'
$Adapter = Read-Text 'tool/runner-adapter.ps1'
$Dispatcher = Read-Text 'tool/runner-dispatcher.ps1'
$AdoptRunner = Read-Text 'tool/runner-adopt-current-chat.ps1'
$CmcpShim = Read-Text 'bin/cmcp.ps1'

$ParseTargets = @(
    'tool/runner-repo-smoke.ps1',
    'tool/runner-console-mcp-bridge.ps1',
    'tool/runner-feed-result.ps1',
    'tool/runner-adapter.ps1'
    'tool/runner-task-bank-loop.ps1'
    'tool/runner-adopt-current-chat.ps1'
    'bin/cmcp.ps1'
)
foreach ($Target in $ParseTargets) {
    $Tokens = $null
    $Errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root $Target), [ref]$Tokens, [ref]$Errors) | Out-Null
    Assert-True (@($Errors).Count -eq 0) "$Target has PowerShell parse errors"
}

Assert-True ($RepoSmoke -match 'runner-daemon\.ps1') 'repo smoke must call runner-daemon'
Assert-True ($RepoSmoke -notmatch 'runner-task-bank-loop\.ps1') 'repo smoke must remain the only production loop implementation'
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
Assert-True ($TaskBankLoop -match 'lockedChatId') 'task-bank loop must lock one task to one chatId'
Assert-True ($RepoSmoke -match '\[string\]\$AdoptChatId') 'repo smoke must expose AdoptChatId parameter'
Assert-True ($TaskBankLoop -match '\[string\]\$AdoptChatId') 'task-bank loop must expose AdoptChatId parameter'
Assert-True ($TaskBankLoop -match 'Normalize-ChatId') 'task-bank loop must normalize adopted ChatGPT chat ids'
Assert-True ($AdoptRunner -match '\[string\]\$CurrentChatUrl') 'adoption entrypoint must require currentChatUrl from the calling layer'
Assert-True ($AdoptRunner -notmatch 'console\.read_\.browser\.chatgpt\.tab\.bind') 'adoption entrypoint must not guess this chat from supervised browser inventory'
Assert-True ($AdoptRunner -match '-AdoptChatId \$ChatId') 'adoption entrypoint must pass the URL-derived chat id into the TaskBank loop'
Assert-True ($AdoptRunner -match '-Chain' -and $AdoptRunner -match '-EngineExecutor') 'adoption entrypoint must start the real TaskBank engine chain'
Assert-True ($CmcpShim -match "'adopt'") 'cmcp shim must expose adopt command'
Assert-True ($TaskBankLoop -match '\$UseInitialPrompt = \(\$Task\.interactionCount -eq 0 -and -not \$AdoptedChatId\)') 'adopt mode must not dispatch the initial prompt/mixin first'
Assert-True ($TaskBankLoop -match 'SINGLE_CHAT_REBIND_FAILED') 'task-bank loop must fail explicitly when single-chat rebind fails'
Assert-True ($TaskBankLoop -match 'AcceptanceDir' -and $TaskBankLoop -match 'Write-AcceptanceArtifact') 'task-bank loop must write final acceptance artifact'
Assert-True ($TaskBankLoop -match 'M3_ACCEPTANCE_PASS') 'task-bank loop must expose strict M3 acceptance pass status'
Assert-True ($TaskBankLoop -match 'acceptanceArtifactPath') 'task-bank loop final JSON must expose acceptance artifact path'
Assert-True ($TaskBankLoop -match 'OBSERVATION_WINDOW_EXPIRED' -and $TaskBankLoop -match 'ANSWER_CAPTURE_OBSERVATION_WINDOW_EXPIRED') 'expired observation with empty answer must be capture failure'
Assert-True ($TaskBankLoop -match 'assistantCaptured = \$Captured') 'assistantCaptured must be derived from non-empty answer text'
Assert-True ($TaskBankLoop -match '\$AssistantCapturedCount\+\+' -and $TaskBankLoop.IndexOf('$AssistantCapturedCount++') -gt $TaskBankLoop.IndexOf('if (-not $Answer.assistantCaptured)')) 'assistantCapturedCount must increment only after capture validation'
Assert-True ($TaskBankLoop -notmatch 'interactionCount\\s*=\\s*\\[int\\]\\$Task\\.interactionCount \\+ 1[\\s\\S]{0,400}uiSubmit') 'submit alone must not increment interaction count'
Assert-True ($TaskBankLoop -notmatch "console\\.read_\\.repo\\.workspace\\.status[\\s\\S]{0,300}interactionCount\\s*=") 'repo status must not increment interaction count'
Assert-True ($TaskBankLoop -notmatch "console\\.read_\\.repo\\.memory\\.graph\\.plan[\\s\\S]{0,300}interactionCount\\s*=") 'memory graph must not increment interaction count'
Assert-True ($Adapter -match '\$NextDispatchProperties\s*=\s*@\(\$NextDispatchContract\.PSObject\.Properties\.Name\)') 'adapter must inspect nextDispatchContract properties before reading shape-specific members'
Assert-True ($Adapter -match '\$HasSequenceContract\s*=\s*\$NextDispatchProperties\s+-contains\s+''sequence''') 'adapter must support sequence nextDispatchContract'
Assert-True ($Adapter -match '\$HasSingleToolContract\s*=\s*\(\$NextDispatchProperties\s+-contains\s+''tool''\)\s+-and\s+\(\$NextDispatchProperties\s+-contains\s+''arguments''\)') 'adapter must support single-tool nextDispatchContract'
Assert-True ($Adapter -match '\$Contracts\s*\+=\s*\$NextDispatchContract') 'single-tool nextDispatchContract must normalize to one contract'
Assert-True ($Adapter -match '(?s)elseif \(\$HasSingleToolContract\).*?else \{\s*return\s*\}') 'adapter must skip gracefully when nextDispatchContract has no supported shape'
Assert-True ($BridgeWrapper -match 'AwsSecretContract\\tool\\secret-runtime\.ps1') 'bridge wrapper must locate AwsSecretContract secret runtime'
Assert-True ($BridgeWrapper -match 'export-env' -and $BridgeWrapper -match 'Consumer console-mcp' -and $BridgeWrapper -match 'IncludePrevious') 'bridge wrapper must export console-mcp consumer env with previous secret support'
Assert-True ($BridgeWrapper -match 'CONSOLE_MCP_BEARER_TOKEN_MISSING') 'bridge wrapper must fail explicitly when token is missing'
Assert-True ($BridgeWrapper -match 'CONSOLE_MCP_ENDPOINT_UNREACHABLE') 'bridge wrapper must fail explicitly when endpoint is unreachable'
Assert-True ($BridgeWrapper -match 'CONSOLE_MCP_UNAUTHORIZED') 'bridge wrapper must classify Unauthorized responses'
Assert-True ($BridgeWrapper -notmatch 'Write-(Host|Output|Information|Verbose|Warning|Error)[^\r\n]*CONSOLE_MCP_BEARER_TOKEN') 'bridge wrapper must not print bearer token values'
Assert-True ($BridgeWrapper -match 'http://127\.0\.0\.1:3334/mcp') 'bridge wrapper must use bearer-only 3334 endpoint'
Assert-True ($BridgeWrapper -notmatch 'foreach\s*\(\$Port\s+in\s+@\(3333,\s*3334\)\)') 'bridge wrapper must not fall back to oauth 3333 for bearer token flow'
Assert-True ($Bridge -match 'http://127\.0\.0\.1:3334/mcp') 'node bridge fallback endpoint must use bearer-only 3334'

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
        'single_tool_next_dispatch_contract',
        'bridge_secret_runtime_bootstrap',
        'single_chat_task_lock',
        'strict_m3_acceptance_artifact'
    )
} | ConvertTo-Json -Depth 20
