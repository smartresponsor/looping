[CmdletBinding(DefaultParameterSetName='Dispatch')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='Dispatch')][string]$PayloadPath,
    [Parameter(Mandatory=$true,ParameterSetName='Dispatch')][string]$ResultPath,
    [Parameter(Mandatory=$true,ParameterSetName='Handshake')][switch]$HandshakeCheck,
    [Parameter(ParameterSetName='Handshake')][switch]$DiagnosticAwsProvider
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$McpRoot = Split-Path -Parent $Root
if ((Split-Path -Leaf $McpRoot) -eq '.worktrees') {
    $McpRoot = Split-Path -Parent $McpRoot
}
$Bridge = Join-Path $Root 'tool/runner-console-mcp-bridge.mjs'

if (-not $HandshakeCheck -and -not (Test-Path -LiteralPath $PayloadPath -PathType Leaf)) { throw "payload file not found: $PayloadPath" }

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
    return $Known -contains $Value.Trim()
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
    $Endpoint = 'http://127.0.0.1:3335/mcp'
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

$InitialPrevious = [Environment]::GetEnvironmentVariable('CONSOLE_MCP_BEARER_TOKEN_PREVIOUS','Process')
$InitialEndpoint = [Environment]::GetEnvironmentVariable('CONSOLE_MCP_ENDPOINT','Process')
try {
$SecretRuntime = Join-Path $McpRoot 'AwsSecretContract\tool\secret-runtime.ps1'
$ExportedCurrentToken = $null
$ExportedPreviousToken = $null
if (-not $DiagnosticAwsProvider -and -not $InitialTokenWasFallback) {
    $ExportedPreviousToken = $InitialPrevious
} elseif (-not $DiagnosticAwsProvider -and $env:LOOPING_SECRET_RUNTIME_ENABLED -ceq '1') {
    if (-not (Test-Path -LiteralPath $SecretRuntime -PathType Leaf)) { throw 'CONSOLE_MCP_APPROVED_SECRET_RUNTIME_MISSING' }
    [Environment]::SetEnvironmentVariable('CONSOLE_MCP_BEARER_TOKEN',$null,'Process')
    [Environment]::SetEnvironmentVariable('CONSOLE_MCP_BEARER_TOKEN_PREVIOUS',$null,'Process')
    # Invoke in a child scope and request only the runner bearer contract.
    & $SecretRuntime -Command export-env -Consumer console-mcp -Name CONSOLE_MCP_BEARER_TOKEN -IncludePrevious
    $ExportedCurrentToken = [Environment]::GetEnvironmentVariable('CONSOLE_MCP_BEARER_TOKEN', 'Process')
    $ExportedPreviousToken = [Environment]::GetEnvironmentVariable('CONSOLE_MCP_BEARER_TOKEN_PREVIOUS', 'Process')
    $TokenSource = 'aws-secret-runtime'
}

# Use the same configured secret contract as Console MCP. The AWS CLI
# inherits existing IAM authorization; no grant, cache or credential file is created.
function Get-RunnerBearerFromAws {
    try {
        $SecretId = if (-not [string]::IsNullOrWhiteSpace($env:CONSOLE_MCP_BEARER_SECRET_ID)) {
            $env:CONSOLE_MCP_BEARER_SECRET_ID.Trim()
        } else { '/secret/dev/console-mcp/' + 'bearer-token' }
        $Aws = Get-Command aws -CommandType Application -ErrorAction Stop
        $Raw = & $Aws.Source secretsmanager get-secret-value --secret-id $SecretId --query SecretString --output json 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'AWS_PROVIDER_REJECTED' }
        $Secret = ($Raw -join "\n") | ConvertFrom-Json -ErrorAction Stop
        if ($Secret -isnot [string]) { throw 'AWS_SECRET_STRING_REQUIRED' }
        $Value = $Secret.Trim()
        if ($Value.StartsWith('{')) {
            $Object = $Value | ConvertFrom-Json -ErrorAction Stop
            $Value = $null
            foreach ($Key in @('CONSOLE_MCP_BEARER_TOKEN','value','token','apiToken','secret')) {
                if ($Object.PSObject.Properties.Name -contains $Key -and $Object.$Key -is [string] -and -not (Test-KnownDevFallback -Value $Object.$Key)) {
                    $Value = $Object.$Key.Trim()
                    break
                }
            }
        }
        if ((Test-KnownDevFallback -Value $Value) -or $Value -eq 'None' -or $Value -match '\s') { throw 'AWS_SECRET_INVALID' }
        return $Value
    } catch {
        throw 'CONSOLE_MCP_AWS_BEARER_UNAVAILABLE'
    }
}

$ResolvedToken = [Environment]::GetEnvironmentVariable('CONSOLE_MCP_BEARER_TOKEN','Process')
if ($DiagnosticAwsProvider) {
    if (-not $HandshakeCheck) { throw 'CONSOLE_MCP_AWS_DIAGNOSTIC_ONLY' }
    $ResolvedToken = Get-RunnerBearerFromAws
    $TokenSource = 'aws-secrets-manager'
}
$Endpoint = Resolve-ConsoleMcpEndpoint
$TokenPresent = -not (Test-KnownDevFallback -Value $ResolvedToken)
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
    $PSNativeCommandUseErrorActionPreference = $false
    if ($script:HandshakeCheck) {
        $Output = & node $Bridge '--handshake-check' 2>&1
    } else {
        $Output = & node $Bridge --payload $PayloadPath --result $ResultPath 2>&1
    }
    [pscustomobject]@{
        exitCode = $LASTEXITCODE
        output = @($Output)
    }
}

$Attempts = @(
    [pscustomobject]@{ token = $ResolvedToken; source = $TokenSource }
)
foreach ($Candidate in $(if (-not $DiagnosticAwsProvider) { @(
    [pscustomobject]@{ token = $ExportedCurrentToken; source = 'aws-secret-runtime' },
    [pscustomobject]@{ token = $ExportedPreviousToken; source = if ($TokenSource -eq 'env') { 'env-previous' } else { 'aws-secret-runtime-previous' } }
) })) {
    if (-not (Test-KnownDevFallback -Value $Candidate.token) -and -not (@($Attempts | ForEach-Object { $_.token }) -ccontains $Candidate.token)) {
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

        $AttemptMessage = ($AttemptOutput -join "`n").Trim()
        if ($BridgeAttempt.exitCode -ne 77 -or $AttemptMessage -cne 'CONSOLE_MCP_HANDSHAKE_UNAUTHORIZED_NO_DISPATCH') {
            throw $AttemptMessage
        }
    }

    return [pscustomobject]@{ ok = $false; output = @(); message = 'Unauthorized' }
}

$BridgeRun = Invoke-BridgeAttempts -AttemptList $Attempts
# NOTE: this bridge is pinned to the runner-bearer profile only (Resolve-ConsoleMcpEndpoint
# always returns :3335) - there is intentionally no fallback to :3333 (chatgpt-oauth). That
# profile requires a real OAuth JWT and would reject a bearer token outright, so falling back
# to it here would just trade one confusing 401 for another. If :3335 is down, fail loudly
# instead of guessing at a different, incompatible endpoint.

if (-not $BridgeRun.ok) {
    throw ("CONSOLE_MCP_UNAUTHORIZED " + ([pscustomobject]$Bootstrap | ConvertTo-Json -Compress))
}

$Raw = $BridgeRun.output
$BridgeResult = $Raw | ConvertFrom-Json
$BridgeResult | Add-Member -NotePropertyName envBootstrap -NotePropertyValue ([pscustomobject]$Bootstrap) -Force
if (-not $HandshakeCheck -and (Test-Path -LiteralPath $ResultPath -PathType Leaf)) {
    $ToolResult = Get-Content -Raw -Path $ResultPath | ConvertFrom-Json
    $ToolResult | Add-Member -NotePropertyName envBootstrap -NotePropertyValue ([pscustomobject]$Bootstrap) -Force
    $ToolResult | ConvertTo-Json -Depth 40 | Set-Content -Path $ResultPath -Encoding UTF8
}
$BridgeResult | ConvertTo-Json -Depth 40
} finally {
    [Environment]::SetEnvironmentVariable('CONSOLE_MCP_BEARER_TOKEN',$InitialToken,'Process')
    [Environment]::SetEnvironmentVariable('CONSOLE_MCP_BEARER_TOKEN_PREVIOUS',$InitialPrevious,'Process')
    [Environment]::SetEnvironmentVariable('CONSOLE_MCP_ENDPOINT',$InitialEndpoint,'Process')
}
