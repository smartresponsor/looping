param(
    [Parameter(Mandatory=$true)][string]$PayloadPath,
    [Parameter(Mandatory=$true)][string]$ResultPath
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$McpRoot = Split-Path -Parent $Root
$Bridge = Join-Path $Root 'tool/runner-console-mcp-bridge.mjs'

if (-not (Test-Path $PayloadPath)) { throw "payload file not found: $PayloadPath" }

function Test-KnownDevFallback {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    $Known = @(
        'dev',
        'test',
        'changeme',
        'change-me',
        'dev-token',
        'local-dev-token',
        'console-mcp-dev-token'
    )
    return $Known -contains $Value
}

function Test-LocalPortListening {
    param([Parameter(Mandatory=$true)][int]$Port)

    try {
        $Connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop |
            Where-Object { $_.LocalAddress -in @('127.0.0.1', '0.0.0.0', '::', '::1') } |
            Select-Object -First 1
        return $null -ne $Connection
    } catch {
        try {
            $Client = [Net.Sockets.TcpClient]::new()
            try {
                $Async = $Client.BeginConnect('127.0.0.1', $Port, $null, $null)
                if (-not $Async.AsyncWaitHandle.WaitOne(500)) { return $false }
                $Client.EndConnect($Async)
                return $true
            } finally {
                $Client.Dispose()
            }
        } catch {
            return $false
        }
    }
}

function Resolve-ConsoleMcpEndpoint {
    $Endpoint = 'http://127.0.0.1:3334/mcp'
    [Environment]::SetEnvironmentVariable('CONSOLE_MCP_ENDPOINT', $Endpoint, 'Process')
    Set-Item -Path Env:\CONSOLE_MCP_ENDPOINT -Value $Endpoint
    return $Endpoint
}

function Get-EndpointPort {
    param([Parameter(Mandatory=$true)][string]$Endpoint)

    try {
        return ([Uri]$Endpoint).Port
    } catch {
        return 0
    }
}

$InitialToken = [Environment]::GetEnvironmentVariable('CONSOLE_MCP_BEARER_TOKEN', 'Process')
$InitialTokenWasExplicit = -not [string]::IsNullOrWhiteSpace($InitialToken)
$InitialTokenWasFallback = Test-KnownDevFallback -Value $InitialToken
$TokenSource = if ($InitialTokenWasExplicit -and -not $InitialTokenWasFallback) { 'env' } else { 'fallback-unknown' }

$SecretRuntime = Join-Path $McpRoot 'AwsSecretContract\tool\secret-runtime.ps1'
$ExportedCurrentToken = $null
$ExportedPreviousToken = $null
if (Test-Path -LiteralPath $SecretRuntime -PathType Leaf) {
    . $SecretRuntime -Command export-env -Consumer console-mcp -IncludePrevious
    $ExportedCurrentToken = [Environment]::GetEnvironmentVariable('CONSOLE_MCP_BEARER_TOKEN', 'Process')
    $ExportedPreviousToken = [Environment]::GetEnvironmentVariable('CONSOLE_MCP_BEARER_TOKEN_PREVIOUS', 'Process')
    if ($InitialTokenWasExplicit -and -not $InitialTokenWasFallback) {
        [Environment]::SetEnvironmentVariable('CONSOLE_MCP_BEARER_TOKEN', $InitialToken, 'Process')
        Set-Item -Path Env:\CONSOLE_MCP_BEARER_TOKEN -Value $InitialToken
    } elseif (-not [string]::IsNullOrWhiteSpace($env:CONSOLE_MCP_BEARER_TOKEN)) {
        $TokenSource = 'aws-secret-runtime'
    }
}

$Endpoint = Resolve-ConsoleMcpEndpoint
$TokenPresent = -not [string]::IsNullOrWhiteSpace($env:CONSOLE_MCP_BEARER_TOKEN)
$Bootstrap = [ordered]@{
    endpoint = $Endpoint
    tokenPresent = $TokenPresent
    tokenSource = $TokenSource
}

if (-not $TokenPresent) {
    throw ("CONSOLE_MCP_BEARER_TOKEN_MISSING " + ([pscustomobject]$Bootstrap | ConvertTo-Json -Compress))
}

$EndpointPort = Get-EndpointPort -Endpoint $Endpoint
if ($EndpointPort -le 0 -or -not (Test-LocalPortListening -Port $EndpointPort)) {
    throw ("CONSOLE_MCP_ENDPOINT_UNREACHABLE " + ([pscustomobject]$Bootstrap | ConvertTo-Json -Compress))
}

function Invoke-NodeBridge {
    $Output = & node $Bridge --payload $PayloadPath --result $ResultPath 2>&1
    [pscustomobject]@{
        exitCode = $LASTEXITCODE
        output = @($Output)
    }
}

$Attempts = @(
    [pscustomobject]@{ token = $env:CONSOLE_MCP_BEARER_TOKEN; source = $TokenSource }
)
foreach ($Candidate in @(
    [pscustomobject]@{ token = $ExportedCurrentToken; source = 'aws-secret-runtime' },
    [pscustomobject]@{ token = $ExportedPreviousToken; source = 'aws-secret-runtime-previous' }
)) {
    if (-not [string]::IsNullOrWhiteSpace($Candidate.token) -and -not (@($Attempts | ForEach-Object { $_.token }) -contains $Candidate.token)) {
        $Attempts += $Candidate
    }
}

function Invoke-BridgeAttempts {
    param([Parameter(Mandatory=$true)]$AttemptList)

    foreach ($Attempt in $AttemptList) {
        [Environment]::SetEnvironmentVariable('CONSOLE_MCP_BEARER_TOKEN', $Attempt.token, 'Process')
        Set-Item -Path Env:\CONSOLE_MCP_BEARER_TOKEN -Value $Attempt.token
        $Bootstrap.tokenSource = $Attempt.source
        $BridgeAttempt = Invoke-NodeBridge
        $AttemptOutput = @($BridgeAttempt.output)
        if ($BridgeAttempt.exitCode -eq 0) {
            return [pscustomobject]@{ ok = $true; output = $AttemptOutput; message = $null }
        }

        $AttemptMessage = ($AttemptOutput -join "`n")
        if ($AttemptMessage -notmatch 'Unauthorized') {
            throw $AttemptMessage
        }
    }

    return [pscustomobject]@{ ok = $false; output = @(); message = 'Unauthorized' }
}

$BridgeRun = Invoke-BridgeAttempts -AttemptList $Attempts
# NOTE: this bridge is pinned to the codex-bearer profile only (Resolve-ConsoleMcpEndpoint
# always returns :3334) - there is intentionally no fallback to :3333 (chatgpt-oauth). That
# profile requires a real OAuth JWT and would reject a bearer token outright, so falling back
# to it here would just trade one confusing 401 for another. If :3334 is down, fail loudly
# instead of guessing at a different, incompatible endpoint.

if (-not $BridgeRun.ok) {
    throw ("CONSOLE_MCP_UNAUTHORIZED " + ([pscustomobject]$Bootstrap | ConvertTo-Json -Compress))
}

$Raw = $BridgeRun.output
$BridgeResult = $Raw | ConvertFrom-Json
$BridgeResult | Add-Member -NotePropertyName envBootstrap -NotePropertyValue ([pscustomobject]$Bootstrap) -Force
if (Test-Path -LiteralPath $ResultPath -PathType Leaf) {
    $ToolResult = Get-Content -Raw -Path $ResultPath | ConvertFrom-Json
    $ToolResult | Add-Member -NotePropertyName envBootstrap -NotePropertyValue ([pscustomobject]$Bootstrap) -Force
    $ToolResult | ConvertTo-Json -Depth 40 | Set-Content -Path $ResultPath -Encoding UTF8
}
$BridgeResult | ConvertTo-Json -Depth 40
