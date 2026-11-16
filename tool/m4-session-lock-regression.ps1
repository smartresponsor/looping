param()
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Scripts=@('tool/runner-task-bank-loop.ps1','tool/runner-daemon.ps1','tool/runner-transport-adapter.ps1','tool/runner-adapter.ps1','tool/runner-scheduled-task.ps1')
foreach($Item in $Scripts) {
  $Tokens=$null; $Errors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root $Item),[ref]$Tokens,[ref]$Errors)
  if(@($Errors).Count -gt 0){ throw ("PARSER_ERROR:" + $Item + ":" + (@($Errors).Count)) }
}
$LockPath=Join-Path $Root 'var/runner/lock/runner.lock'
if(Test-Path -LiteralPath $LockPath){throw 'EXISTING_LOCK_PRESERVED_MANUAL_REVIEW'}
$LockDir=Split-Path -Parent $LockPath
New-Item -ItemType Directory -Path $LockDir -Force | Out-Null
try {
  $Results = @(1..12 | ForEach-Object -Parallel {
    $Path = $using:LockPath
    try {
      $File=[System.IO.File]::Open($Path,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)
      try { [System.Threading.Thread]::Sleep(200); return 'CLAIMED' }
      finally { $File.Dispose() }
    } catch [System.IO.IOException] { return 'BUSY' }
  } -ThrottleLimit 12)
  if(@($Results | Where-Object { $_ -eq 'CLAIMED' }).Count -ne 1){ throw 'NON_ATOMIC_LOCK_ACQUISITION' }
  if(@($Results | Where-Object { $_ -eq 'BUSY' }).Count -ne 11){ throw 'UNEXPECTED_CONTENDER_RESULTS' }
  # The runner wrapper must be blocked while another owner holds the lock.
  $Metadata=[pscustomobject]@{owner='fixture-other';pid=42;acquiredAt=(Get-Date).ToUniversalTime().ToString('o')}
  $Metadata | ConvertTo-Json -Compress | Set-Content -LiteralPath $LockPath
  $ActualBefore=Get-Content -Raw -LiteralPath $LockPath
  $Out=@(& (Join-Path $Root 'tool/runner-scheduled-task.ps1') -TargetRepo $Root -MaxIterations 1 -Name 'm4-lock-test' -InitialPrompt 'DO_NOT_EXECUTE' -AdoptChatId '00000000-0000-0000-0000-000000000001' -ExpectedTargetId '00000000000000000000000000000001')
  if(@($Out).Count -ne 1 -or ([string]$Out[0]) -notmatch 'RUNNER_SCHEDULE_BUSY'){ throw 'WRAPPER_BUSY_GUARD_FAILED' }
  if((Get-Content -Raw -LiteralPath $LockPath) -ne $ActualBefore){throw 'WRAPPER_MUTATED_UNOWNED_LOCK'}
  $LegacyDeclined=0
  foreach($Legacy in @(
      @{file='runner-repo-smoke.ps1';args=@('-TargetRepo',$Root)},
      @{file='runner-runtime-smoke.ps1';args=@()}
  )) {
    try {
      if ($Legacy.file -eq 'runner-repo-smoke.ps1') {
        & (Join-Path $Root 'tool/runner-repo-smoke.ps1') -TargetRepo $Root | Out-Null
      } else {
        & (Join-Path $Root 'tool/runner-runtime-smoke.ps1') | Out-Null
      }
      throw ('LEGACY_LOCK_GUARD_BYPASSED:'+ $Legacy.file)
    } catch {
      if ($_.Exception.Message -notmatch '(REPO_SMOKE_SHARED_RUNNER_LOCK_BUSY|RUNTIME_SMOKE_SHARED_RUNNER_LOCK_BUSY)') { throw }
      $LegacyDeclined++
    }
    if ((Get-Content -Raw -LiteralPath $LockPath) -ne $ActualBefore) {throw 'LEGACY_MUTATED_UNOWNED_LOCK'}
  }
  if ($LegacyDeclined -ne 2) {throw 'LEGACY_GUARD_MISSING'}
  $TaskBankDeclined = $false
  try {
    & (Join-Path $Root 'tool/runner-task-bank-loop.ps1') -TargetRepo $Root -MaxIterations 1 -Name 'lock-only-fixture' -InitialPrompt 'DO_NOT_EXECUTE' | Out-Null
    throw 'TASK_BANK_LOCK_BYPASSED'
  } catch {
    if ($_.Exception.Message -notmatch 'TASK_BANK_SHARED_RUNNER_LOCK_BUSY') { throw }
    $TaskBankDeclined = $true
  }
  if (-not $TaskBankDeclined -or (Get-Content -Raw -LiteralPath $LockPath) -ne $ActualBefore) {throw 'TASK_BANK_MUTATED_UNOWNED_LOCK'}
  [pscustomobject]@{ok=$true;status='M4_SESSION_LOCK_ACCEPTANCE_PASS';competitors=12;winners=1;busy=11;wrapperDeclined=$true;legacyDeclined=$LegacyDeclined;taskBankDeclined=$TaskBankDeclined;browserCalls=0} | ConvertTo-Json -Compress
} finally { if((Test-Path -LiteralPath $LockPath) -and (Get-Content -Raw -LiteralPath $LockPath) -match 'fixture-other'){Remove-Item -LiteralPath $LockPath -Force} }
