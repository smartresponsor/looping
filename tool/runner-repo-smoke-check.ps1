param([switch]$RuntimeCheckOnly)

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

if ($RuntimeCheckOnly) {
    $PSNativeCommandUseErrorActionPreference = $false
    $BridgePath = Join-Path $Root 'tool/runner-console-mcp-bridge.mjs'
    $McpRoot = Split-Path -Parent $Root
    if ((Split-Path -Leaf $McpRoot) -eq '.worktrees') {
        $McpRoot = Split-Path -Parent $McpRoot
    }
    $SdkRoot = Join-Path $McpRoot 'console-mcp'
    $Temp = Join-Path ([System.IO.Path]::GetTempPath()) ('looping-runtime-check-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $Temp
    $Saved = @{}
    foreach ($Name in @('LOOPING_CONSOLE_MCP_ROOT','CONSOLE_MCP_BEARER_TOKEN','CONSOLE_MCP_BEARER_TOKEN_PREVIOUS','CONSOLE_MCP_ENDPOINT','LOOPING_SECRET_RUNTIME_ENABLED')) {
        $Saved[$Name] = [Environment]::GetEnvironmentVariable($Name,'Process')
    }
    function Invoke-Probe([string[]]$Arguments) {
        $Output = & node $BridgePath @Arguments 2>&1
        [pscustomobject]@{ code = $LASTEXITCODE; output = ($Output -join "\n") }
    }
    try {
        $env:CONSOLE_MCP_BEARER_TOKEN = $null
        $env:CONSOLE_MCP_ENDPOINT = $null
        $env:LOOPING_CONSOLE_MCP_ROOT = $null
        $Probe = Invoke-Probe @('--runtime-check')
        Assert-True ($Probe.code -eq 0) 'default SDK resolution failed'
        $Receipt = $Probe.output | ConvertFrom-Json
        Assert-True ($Receipt.status -eq 'LOOPING_CONSOLE_MCP_SDK_READY' -and $Receipt.connected -eq $false -and $Receipt.dispatched -eq $false) 'SDK probe must be offline'
        $env:LOOPING_CONSOLE_MCP_ROOT = $SdkRoot
        $Probe = Invoke-Probe @('--runtime-check')
        Assert-True ($Probe.code -eq 0) 'explicit SDK resolution failed'
        $env:LOOPING_CONSOLE_MCP_ROOT = 'relative/path'
        $Probe = Invoke-Probe @('--runtime-check')
        Assert-True ($Probe.code -ne 0 -and $Probe.output.Contains('LOOPING_CONSOLE_MCP_ROOT_INVALID')) 'relative SDK root accepted'
        $env:LOOPING_CONSOLE_MCP_ROOT = Join-Path $Temp 'missing-sdk'
        $Probe = Invoke-Probe @('--runtime-check')
        Assert-True ($Probe.code -ne 0 -and $Probe.output.Contains('LOOPING_CONSOLE_MCP_SDK_UNAVAILABLE')) 'missing SDK accepted or fallback used'
        $Payload = Join-Path $Temp 'payload.json'
        $Result = Join-Path $Temp 'result.json'
        '{"runnerExecutionPlan":{"tool":"read_.repo.workspace.status","arguments":{}}}' | Set-Content -LiteralPath $Payload -Encoding UTF8
        $env:LOOPING_CONSOLE_MCP_ROOT = $SdkRoot
        $env:CONSOLE_MCP_BEARER_TOKEN = 'dev'
        $Probe = Invoke-Probe @('--payload',$Payload,'--result',$Result)
        Assert-True ($Probe.code -ne 0 -and $Probe.output.Contains('CONSOLE_MCP_BEARER_TOKEN_MISSING_OR_PLACEHOLDER')) 'placeholder credential accepted'
        $env:CONSOLE_MCP_BEARER_TOKEN = 'offline-fixture-not-a-real-credential'
        $env:CONSOLE_MCP_ENDPOINT = 'http://127.0.0.1:1/mcp'
        $Probe = Invoke-Probe @('--payload',$Payload,'--result',$Result)
        Assert-True ($Probe.code -ne 0 -and $Probe.output.Contains('CONSOLE_MCP_ENDPOINT_NOT_RUNNER_PROFILE')) 'non-runner endpoint accepted'
        Assert-True (-not (Test-Path -LiteralPath $Result)) 'negative probe produced a tool receipt'
        $BridgeSource = Read-Text 'tool/runner-console-mcp-bridge.mjs'
        $WrapperSource = Read-Text 'tool/runner-console-mcp-bridge.ps1'
        Assert-True ($BridgeSource.IndexOf('CONSOLE_MCP_HANDSHAKE_UNAUTHORIZED_NO_DISPATCH') -lt $BridgeSource.IndexOf('await client.callTool(') -and $BridgeSource.Contains('process.exitCode = 77')) 'handshake rejection must precede tool dispatch'
        Assert-True ($WrapperSource.Contains('exitCode -ne 77') -and $WrapperSource.Contains("-cne 'CONSOLE_MCP_HANDSHAKE_UNAUTHORIZED_NO_DISPATCH'")) 'retry must require exact pre-dispatch rejection'
        Assert-True ($WrapperSource.Contains("[Parameter(ParameterSetName='Handshake')][switch]"+'$DiagnosticAwsProvider') -and $WrapperSource.Contains('if ($DiagnosticAwsProvider) {') -and $WrapperSource.Contains("throw 'CONSOLE_MCP_AWS_DIAGNOSTIC_ONLY'")) 'AWS provider must be restricted to explicit handshake diagnostics'
        $WrapperPath = Join-Path $Root 'tool/runner-console-mcp-bridge.ps1'
        $env:LOOPING_SECRET_RUNTIME_ENABLED = $null
        $env:CONSOLE_MCP_BEARER_TOKEN = 'dev'
        $env:CONSOLE_MCP_BEARER_TOKEN_PREVIOUS = 'synthetic-previous'
        $env:CONSOLE_MCP_ENDPOINT = 'http://127.0.0.1:1/mcp'
        $MissingRejected = $false
        try { & $WrapperPath -HandshakeCheck | Out-Null } catch {
            $MissingRejected = $_.Exception.Message.Contains('CONSOLE_MCP_BEARER_TOKEN_MISSING')
        }
        Assert-True $MissingRejected 'missing authorized credential must fail before dispatch'
        Assert-True ($env:CONSOLE_MCP_BEARER_TOKEN -ceq 'dev' -and $env:CONSOLE_MCP_BEARER_TOKEN_PREVIOUS -ceq 'synthetic-previous' -and $env:CONSOLE_MCP_ENDPOINT -ceq 'http://127.0.0.1:1/mcp') 'failed admission must restore all process variables'
        $BindingRejected = $false
        try { & $WrapperPath -PayloadPath $Payload -ResultPath $Result -DiagnosticAwsProvider | Out-Null } catch {
            $BindingRejected = $_.FullyQualifiedErrorId -match 'AmbiguousParameterSet|ParameterSetCannotBeResolved'
        }
        Assert-True $BindingRejected 'AWS diagnostic cannot be combined with dispatch'
        Assert-True ($WrapperSource.Contains("-Name CONSOLE_MCP_BEARER_TOKEN -IncludePrevious") -and $WrapperSource.Contains('$env:LOOPING_SECRET_RUNTIME_ENABLED')) 'shared provider must be scoped and opt-in'
        [pscustomobject]@{ok=$true;status='LOOPING_RUNTIME_BOOTSTRAP_DELTA_PASS';sdkVersion=$Receipt.sdkVersion;checks=13;liveDispatches=0;browserCalls=0} | ConvertTo-Json -Compress
    } finally {
        foreach ($Name in $Saved.Keys) {
            [Environment]::SetEnvironmentVariable($Name,$Saved[$Name],'Process')
        }
        Remove-Item -LiteralPath $Temp -Recurse -Force
    }
    return
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
Assert-True ($AdoptRunner -match '\[string\]\$ExistingLocation') 'adoption entrypoint must require an explicit existing chat location from the calling layer'
Assert-True ($AdoptRunner -notmatch 'console\.read_\.browser\.chatgpt\.tab\.bind') 'adoption entrypoint must not guess this chat from supervised browser inventory'
Assert-True ($AdoptRunner -match 'preferredChatId = \$ChatId' -and $AdoptRunner -match 'locator = \$ExistingLocation') 'adoption entrypoint must pass the explicit chat id or locator to the adoption tool'
Assert-True ($AdoptRunner -cmatch "tool\s*=\s*'write\.browser\.chatgpt\.chat\.adopt_go'") 'adoption entrypoint must dispatch the canonical unprefixed adopt_go execution path'
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
Assert-True ($BridgeWrapper -match 'http://127\.0\.0\.1:3335/mcp') 'bridge wrapper must use runner-bearer 3335 endpoint'
Assert-True ($BridgeWrapper -notmatch 'foreach\s*\(\$Port\s+in\s+@\(3333,\s*3335\)\)') 'runner bridge must not fall back from runner 3335 to oauth 3333'
Assert-True ($Bridge -match 'http://127\.0\.0\.1:3335/mcp') 'node bridge fallback endpoint must use runner-bearer 3335'

$RequiredBridgeTools = @(
    'write.browser.session.cmcp.go',
    'write.browser.chatgpt.chat.adopt_go',
    'read_.browser.chatgpt.composer.preflight',
    'read_.browser.chatgpt.watch.probe',
    'read_.browser.chatgpt.watch.next',
    'read_.browser.chatgpt.run.loop.plan',
    'read_.browser.chatgpt.run.loop.step',
    'read_.browser.chatgpt.run.loop.step.summary',
    'read_.browser.chatgpt.run.loop.auto.summary',
    'read_.browser.chatgpt.answer.settle',
    'write.browser.session.run.loop.daemon.start',
    'read_.repo.context.capture',
    'read_.repo.workspace.status',
    'read_.repo.memory.graph.plan'
)
foreach ($Tool in $RequiredBridgeTools) {
    Assert-True ($Bridge.Contains($Tool)) "bridge missing required tool $Tool"
}

Assert-True (-not $Bridge.Contains('write.browser.chatgpt.chat.create.send')) 'bridge must not allow legacy fallback tool'
Assert-True ($Dispatcher.Contains('write.browser.session.cmcp.go')) 'dispatcher must allow cmcp.go'
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
