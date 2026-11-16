param()
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Scripts=@(
    'tool/runner-task-bank-loop.ps1',
    'tool/runner-daemon.ps1',
    'tool/runner-transport-adapter.ps1'
)
foreach($Relative in $Scripts){
    $Path=Join-Path $Root $Relative
    $Tokens=$null
    $Errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$Tokens,[ref]$Errors)
    if(@($Errors).Count -gt 0){throw "M4_POWERSHELL_PARSE_FAILED:${Relative}:$(@($Errors).Count)"}
}
$Task=Get-Content -Raw -LiteralPath (Join-Path $Root 'tool/runner-task-bank-loop.ps1')
$Daemon=Get-Content -Raw -LiteralPath (Join-Path $Root 'tool/runner-daemon.ps1')
$Transport=Get-Content -Raw -LiteralPath (Join-Path $Root 'tool/runner-transport-adapter.ps1')
if($Task -notmatch '\[ValidateSet\(''repo_smoke'',''scheduled_task''\)\]\[string\]\$TaskMode'){throw 'M4_MODE_MISSING'}
if($Task -notmatch "SCHEDULED_TASK_REQUIRES_DISABLE_CHAT_DELETION"){throw 'M4_DELETE_GUARD_MISSING'}
if($Task -notmatch 'completionVerified = \$false'){throw 'M4_UNVERIFIED_DEFAULT_MISSING'}
if($Task -notmatch 'scheduled_task.*Continue the original scheduled task'){throw 'M4_CONTINUATION_MISSING'}
foreach($Text in @($Daemon,$Transport)){
    if($Text -notmatch 'FileMode\]::CreateNew'){throw 'M4_ATOMIC_LOCK_MISSING'}
    if($Text -match 'AgeMinutes -lt 30'){throw 'M4_UNSAFE_STALE_REAPING_PRESENT'}
}
[pscustomobject]@{ok=$true;status='M4_STATIC_ACCEPTANCE_PASS';parsedScripts=$Scripts.Count;liveBrowserInvocations=0}|ConvertTo-Json -Compress
