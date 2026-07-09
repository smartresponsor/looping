param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = 'Stop'

$ScriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$BinDir = Split-Path -Parent $ScriptPath
$Root = Split-Path -Parent $BinDir
$Runner = Join-Path $Root 'tool\runner-repo-smoke.ps1'

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
        if ($Ok) { Write-Output 'CMCP_SHIM_READY' }
        exit ($(if ($Ok) { 0 } else { 1 }))
    }
    default {
        Write-Error "Unsupported cmcp command yet: $Command. Run: cmcp doctor"
        exit 2
    }
}
