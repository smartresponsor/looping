param(
    [Parameter(Mandatory=$true)][string]$TargetRepo,
    [Parameter(Mandatory=$true)][int]$MaxIterations,
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$InitialPrompt,
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$AdoptChatId,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Fa-f0-9]{32}$')][string]$ExpectedTargetId,
    [ValidateSet(9224)][int]$CdpPort = 9224
)
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$LockPath=Join-Path $Root 'var/runner/lock/runner.lock'
New-Item -ItemType Directory -Path (Split-Path -Parent $LockPath) -Force | Out-Null
$SessionToken=[guid]::NewGuid().ToString('N')
try {
    $Handle=[System.IO.File]::Open($LockPath,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)
} catch [System.IO.IOException] {
    [pscustomobject]@{ok=$false;status='RUNNER_SCHEDULE_BUSY';nextAction='reconcile_or_retry_later'} | ConvertTo-Json -Compress
    exit 0
}
try {
    $Metadata=[pscustomobject]@{owner='scheduled-task';sessionToken=$SessionToken;pid=$PID;acquiredAt=(Get-Date).ToUniversalTime().ToString('o')}
    $Bytes=[System.Text.Encoding]::UTF8.GetBytes(($Metadata | ConvertTo-Json -Compress))
    $Handle.Write($Bytes,0,$Bytes.Length)
    $Handle.Flush($true)
} finally { $Handle.Dispose() }
$PriorToken=$env:LOOPING_SCHEDULE_SESSION_TOKEN
try {
    $env:LOOPING_SCHEDULE_SESSION_TOKEN=$SessionToken
    & (Join-Path $Root 'tool/runner-task-bank-loop.ps1') -TargetRepo $TargetRepo -MaxIterations $MaxIterations -Name $Name -InitialPrompt $InitialPrompt -AdoptChatId $AdoptChatId -ExpectedTargetId $ExpectedTargetId -CdpPort $CdpPort -TaskMode scheduled_task -DisableChatDeletion
    if (-not $?) { throw 'SCHEDULED_TASK_RUNNER_FAILED' }
} finally {
    $env:LOOPING_SCHEDULE_SESSION_TOKEN=$PriorToken
    if (Test-Path -LiteralPath $LockPath) {
        try {
            $Actual=Get-Content -Raw -LiteralPath $LockPath | ConvertFrom-Json
            if ($Actual.sessionToken -eq $SessionToken -and $Actual.owner -eq 'scheduled-task') { Remove-Item -LiteralPath $LockPath -Force }
        } catch { Write-Warning 'SCHEDULED_TASK_LOCK_REQUIRES_RECONCILIATION' }
    }
}
