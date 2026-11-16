param()
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Lock=Join-Path $Root 'var/runner/lock/runner.lock'
if(Test-Path -LiteralPath $Lock){throw 'EXISTING_LOCK_REQUIRES_MANUAL_RECONCILIATION'}
$State=Join-Path $Root 'var/runner/state/latest.json'
$StateBefore=if(Test-Path -LiteralPath $State){(Get-FileHash -LiteralPath $State -Algorithm SHA256).Hash}else{$null}
$Caught=$null
try {
  & (Join-Path $Root 'tool/runner-scheduled-task.ps1') -TargetRepo $Root -MaxIterations 1 -Name 'm5-offline-denial' -InitialPrompt 'NEVER_DISPATCH' -AdoptChatId '00000000-0000-0000-0000-000000000001' -ExpectedTargetId '00000000000000000000000000000001' -CdpPort 9224 | Out-Null
} catch {
  $Caught=$_.Exception.Message
}
if($Caught -notmatch 'SCHEDULED_ATOMIC_TARGET_TRANSPORT_NOT_ACTIVATED'){throw "UNSAFE_SCHEDULED_ADMISSION:$Caught"}
if(Test-Path -LiteralPath $Lock){throw 'SCHEDULED_DENIAL_LEFT_SHARED_LOCK'}
$StateAfter=if(Test-Path -LiteralPath $State){(Get-FileHash -LiteralPath $State -Algorithm SHA256).Hash}else{$null}
if($StateAfter -ne $StateBefore){throw 'SCHEDULED_DENIAL_MUTATED_RUNNER_STATE'}
$Wrapper=Get-Content -Raw -LiteralPath (Join-Path $Root 'tool/runner-scheduled-task.ps1')
$Task=Get-Content -Raw -LiteralPath (Join-Path $Root 'tool/runner-task-bank-loop.ps1')
if($Wrapper -notmatch '-ExpectedTargetId \$ExpectedTargetId' -or $Wrapper -notmatch '-AdoptChatId \$AdoptChatId') {throw 'SCHEDULED_PARAMETERS_NOT_PROPAGATED'}
if($Task -notmatch 'SCHEDULED_TARGET_BINDING_REQUIRED' -or $Task -notmatch 'SCHEDULED_ATOMIC_TARGET_TRANSPORT_NOT_ACTIVATED') {throw 'SCHEDULED_BYPASS_GUARD_MISSING'}
[pscustomobject]@{ok=$true;status='M5_SCHEDULED_TARGET_FAIL_CLOSED_PASS';denial=$Caught;lockRemoved=$true;runnerStateUnchanged=$true;browserCalls=0}|ConvertTo-Json -Compress
