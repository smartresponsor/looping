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
    Write-Host '  cmcp adopt <component> M<number> <current-chat-url>'
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
        if ($Ok) {
            Write-Output 'CMCP_SHIM_READY'
            exit 0
        }
        exit 1
    }
    'adopt' {
        if ($Args.Count -lt 4 -or [string]::IsNullOrWhiteSpace($Args[1]) -or [string]::IsNullOrWhiteSpace($Args[3])) {
            Write-Error 'Usage: cmcp adopt <component> M<number> <current-chat-url>'
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
        $CurrentChatUrl = [string]$Args[3]
        & $AdoptRunner -ComponentName $Component -CurrentChatUrl $CurrentChatUrl -MaxIterations $MaxIterations
        exit $LASTEXITCODE
    }
    default {
        Write-Error "Unsupported cmcp command yet: $Command. Run: cmcp doctor"
        exit 2
    }
}
