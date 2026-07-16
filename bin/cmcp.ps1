param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = 'Stop'

$ScriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$BinDir = Split-Path -Parent $ScriptPath
$Root = Split-Path -Parent $BinDir
$Runner = Join-Path $Root 'tool\runner-repo-smoke.ps1'
$AdoptRunner = Join-Path $Root 'tool\runner-adopt-current-chat.ps1'
$ConsoleMcpRoot = Join-Path (Split-Path -Parent $Root) 'console-mcp'
$ConsoleMcpDevConsole = Join-Path $ConsoleMcpRoot 'tool\dev-console.ps1'
$ConsoleMcpCli = Join-Path $ConsoleMcpRoot 'bin\cmcp.ps1'
function Show-CmcpUsage {
    Write-Host 'cmcp command shim'
    Write-Host ''
    Write-Host 'Status:'
    Write-Host "  bin:    $BinDir"
    Write-Host "  root:   $Root"
    Write-Host "  runner: $Runner"
    Write-Host ''
    Write-Host 'Available now:'
    Write-Host '  cmcp --version'
    Write-Host '  cmcp doctor'
    Write-Host '  cmcp stop'
    Write-Host '  cmcp adopt <component> M<number> @location'
    Write-Host '  cmcp adopt <component> M<number> <chat-url-or-chat-id>'
    Write-Host ''
    Write-Host 'Planned next:'
    Write-Host '  cmcp go cataloging'
    Write-Host '  cmcp smoke cataloging'
}

if (-not $Args -or $Args.Count -eq 0) {
    Show-CmcpUsage
    exit 0
}

$Command = $Args[0]

switch ($Command) {
    '--version' {
        Write-Output 'cmcp shim 0.1.0'
        exit 0
    }
    'doctor' {
        $Ok = $true
        if (-not (Test-Path -LiteralPath $Runner -PathType Leaf)) {
            Write-Error "Runner not found: $Runner"
            $Ok = $false
        }
        if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
            Write-Error 'pwsh was not found in PATH.'
            $Ok = $false
        }
        if (-not (Test-Path -LiteralPath $ConsoleMcpDevConsole -PathType Leaf)) {
            Write-Error "Console MCP lifecycle command not found: $ConsoleMcpDevConsole"
            $Ok = $false
        }
        if ($Ok) {
            Write-Output 'CMCP_SHIM_READY'
            exit 0
        }
        exit 1
    }
    'stop' {
        if ($Args.Count -ne 1) {
            Write-Error 'Usage: cmcp stop'
            exit 2
        }
        if (-not (Test-Path -LiteralPath $ConsoleMcpDevConsole -PathType Leaf)) {
            Write-Error "Console MCP lifecycle command not found: $ConsoleMcpDevConsole"
            exit 1
        }
        $Pwsh = Get-Command pwsh -ErrorAction Stop
        & $Pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $ConsoleMcpDevConsole stop-server
        exit $LASTEXITCODE
    }
    'adopt' {
        if ($Args.Count -lt 4 -or [string]::IsNullOrWhiteSpace($Args[1]) -or [string]::IsNullOrWhiteSpace($Args[3])) {
            Write-Error 'Usage: cmcp adopt <component> M<number> <existing-location-or-chat-reference>'
            exit 2
        }
        if (-not (Test-Path -LiteralPath $AdoptRunner -PathType Leaf)) {
            Write-Error "Adoption runner not found: $AdoptRunner"
            exit 1
        }
        $Component = [string]$Args[1]
        $MaxIterations = 3
        if ($Args.Count -ge 3 -and [string]$Args[2] -match '^M([1-9][0-9]?)$') {
            $MaxIterations = [int]$Matches[1]
        } elseif ($Args.Count -ge 3) {
            Write-Error 'Iteration budget must use M<number>, for example M13.'
            exit 2
        }
        $ExistingLocation = [string]$Args[3]
        & $AdoptRunner -ComponentName $Component -ExistingLocation $ExistingLocation -MaxIterations $MaxIterations
        exit $LASTEXITCODE
    }
    default {
        if (-not (Test-Path -LiteralPath $ConsoleMcpCli -PathType Leaf)) {
            Write-Error "Console MCP CLI not found: $ConsoleMcpCli"
            exit 1
        }
        & $ConsoleMcpCli @Args
        exit $LASTEXITCODE
    }
}
