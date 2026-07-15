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
$WorkspaceRoot = Split-Path -Parent (Split-Path -Parent $Root)

function Invoke-CmcpComponent {
    param([Parameter(Mandatory=$true)][string[]]$CommandArgs)

    if ($CommandArgs.Count -lt 2 -or [string]::IsNullOrWhiteSpace($CommandArgs[0])) {
        Write-Error 'Usage: cmcp [go] <component> M<number> [options]'
        exit 2
    }

    $Component = [string]$CommandArgs[0]
    if ($Component -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,119}$') {
        Write-Error 'Component must be a valid repository name.'
        exit 2
    }

    if ([string]$CommandArgs[1] -notmatch '^M([1-9][0-9]?)$') {
        Write-Error 'Iteration budget must use M<number>, for example M13.'
        exit 2
    }
    $MaxIterations = [int]$Matches[1]

    $TargetRepo = Join-Path $WorkspaceRoot $Component
    if (-not (Test-Path -LiteralPath $TargetRepo -PathType Container)) {
        Write-Error "Target repository not found: $TargetRepo"
        exit 1
    }

    $ForwardedArgs = @($CommandArgs)
    if (-not (@($ForwardedArgs) -contains '--live')) {
        $ForwardedArgs += '--live'
    }
    $RawCommand = 'cmcp ' + (($ForwardedArgs | ForEach-Object { [string]$_ }) -join ' ')

    & $Runner -TargetRepo $TargetRepo -MaxIterations $MaxIterations -Name $Component -Chain -EngineExecutor -RawCommand $RawCommand
    exit $LASTEXITCODE
}

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
    Write-Host '  cmcp <component> M<number> [options]'
    Write-Host '  cmcp go <component> M<number> [options]'
    Write-Host '  cmcp adopt <component> M<number> <current-chat-url>'
}

if (-not $Args -or $Args.Count -eq 0) {
    Show-CmcpUsage
    exit 0
}

$CommandArgs = @($Args)
if ($CommandArgs[0] -eq 'go') {
    $CommandArgs = @($CommandArgs | Select-Object -Skip 1)
    if ($CommandArgs.Count -eq 0) {
        Write-Error 'Usage: cmcp go <component> M<number> [options]'
        exit 2
    }
}

$Command = $CommandArgs[0]

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
        if ($CommandArgs.Count -lt 4 -or [string]::IsNullOrWhiteSpace($CommandArgs[1]) -or [string]::IsNullOrWhiteSpace($CommandArgs[3])) {
            Write-Error 'Usage: cmcp adopt <component> M<number> <current-chat-url>'
            exit 2
        }
        if (-not (Test-Path -LiteralPath $AdoptRunner -PathType Leaf)) {
            Write-Error "Adoption runner not found: $AdoptRunner"
            exit 1
        }
        $Component = [string]$CommandArgs[1]
        $MaxIterations = 3
        if ($CommandArgs.Count -ge 3 -and [string]$CommandArgs[2] -match '^M([1-9][0-9]?)$') {
            $MaxIterations = [int]$Matches[1]
        } elseif ($CommandArgs.Count -ge 3) {
            Write-Error 'Iteration budget must use M<number>, for example M13.'
            exit 2
        }
        $CurrentChatUrl = [string]$CommandArgs[3]
        & $AdoptRunner -ComponentName $Component -CurrentChatUrl $CurrentChatUrl -MaxIterations $MaxIterations
        exit $LASTEXITCODE
    }
    default {
        Invoke-CmcpComponent -CommandArgs $CommandArgs
    }
}
