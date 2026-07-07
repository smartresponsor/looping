param(
    [Parameter(Mandatory=$true)][string]$PayloadPath,
    [switch]$DryRun,
    [switch]$Invoke
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $PayloadPath)) { throw "payload file not found: $PayloadPath" }

$Payload = Get-Content -Raw -Path $PayloadPath | ConvertFrom-Json
$Items = @($Payload)
if ($Payload.responseDispatcherPayload) { $Items = @($Payload.responseDispatcherPayload) }

$AllowedTool = @{
    'console.write.engine.reply.draft' = 'write'
    'console.write.engine.reply.submit' = 'write'
}

$Invocation = @()
for ($Index = 0; $Index -lt $Items.Count; $Index++) {
    $Item = $Items[$Index]
    $ToolCall = $Item.toolCall
    if (-not $ToolCall) { throw "toolCall missing at index $Index" }

    $ToolName = [string]$ToolCall.name
    if (-not $AllowedTool.ContainsKey($ToolName)) { throw "host bridge tool not allowed: $ToolName" }
    if ($Item.status -ne 'DISPATCHER_REAL_EXECUTION_ADAPTER_READY') { throw "dispatcher payload is not ready for host invocation: $($Item.status)" }

    $Invocation += [ordered]@{
        index = $Index
        tool = $ToolName
        allowedMode = $AllowedTool[$ToolName]
        arguments = $ToolCall.arguments
        sourceStatus = $Item.status
    }
}

$Plan = [ordered]@{
    ok = $true
    status = 'HOST_BRIDGE_INVOCATION_PLAN_READY'
    payloadPath = $PayloadPath
    invocationCount = $Invocation.Count
    invocations = $Invocation
    dryRunOnly = $true
    realInvocation = 'external_host_required'
    nextAction = 'invoke_listed_console_mcp_tools_in_order'
}

if ($DryRun -or -not $Invoke) {
    [pscustomobject]$Plan | ConvertTo-Json -Depth 40
    exit 0
}

if (($env:CHATGPT_LOOP_HOST_BRIDGE) -ne '1') {
    [pscustomobject]@{
        ok = $false
        status = 'HOST_BRIDGE_ENV_REQUIRED'
        requiredEnv = 'CHATGPT_LOOP_HOST_BRIDGE=1'
        invocationCount = $Invocation.Count
        invocations = $Invocation
        realInvocation = 'blocked'
    } | ConvertTo-Json -Depth 40
    exit 0
}

[pscustomobject]@{
    ok = $false
    status = 'HOST_BRIDGE_TRANSPORT_NOT_CONFIGURED'
    reason = 'PowerShell host bridge has no direct MCP transport configured. The returned invocations must be executed by the ChatGPT/tool host or a configured MCP client transport.'
    invocationCount = $Invocation.Count
    invocations = $Invocation
    realInvocation = 'not_executed'
    nextAction = 'configure_mcp_client_transport_or_execute_from_chatgpt_tool_host'
} | ConvertTo-Json -Depth 40
