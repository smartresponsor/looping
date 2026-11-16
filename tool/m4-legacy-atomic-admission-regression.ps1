param()
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Lock=Join-Path $Root 'var/runner/lock/runner.lock'
$Helper=Join-Path $Root 'tool/runner-entry-lock.ps1'
. $Helper
if (Test-Path -LiteralPath $Lock) {throw 'EXISTING_LOCK_REQUIRES_MANUAL_RECONCILIATION'}
$Out=@(1..12 | ForEach-Object -Parallel {
  . $using:Helper
  try {
    $Ticket=Enter-RunnerSessionLock -Owner 'repo-smoke'
    try { [System.Threading.Thread]::Sleep(250); 'ACQUIRED' }
    finally { Exit-RunnerSessionLock -Session $Ticket }
  } catch {
    if ($_.Exception.Message -notmatch 'REPO_SMOKE_SHARED_RUNNER_LOCK_BUSY') { throw }
    'BUSY'
  }
} -ThrottleLimit 12)
$Granted=@($Out | Where-Object {$_ -eq 'ACQUIRED'}).Count
$Denied=@($Out | Where-Object {$_ -eq 'BUSY'}).Count
if ($Granted -ne 1 -or $Denied -ne 11) {throw "HELPER_LOCK_CONTENTION_FAILED granted=$Granted denied=$Denied"}
if (Test-Path -LiteralPath $Lock) {throw 'HELPER_DID_NOT_RELEASE_OWN_LOCK'}
$Ticket2=Enter-RunnerSessionLock -Owner 'runtime-smoke'
try {
  $Metadata=Get-Content -Raw -LiteralPath $Lock | ConvertFrom-Json
  if ($Metadata.owner -ne 'runtime-smoke' -or $Metadata.sessionToken -ne $Ticket2.token) {throw 'SESSION_METADATA_MISMATCH'}
  $Other=[pscustomobject]@{path=$Ticket2.path;owner='repo-smoke';token=[guid]::NewGuid().ToString('N')}
  $Rejected=$false
  try {Exit-RunnerSessionLock -Session $Other} catch {
    if ($_.Exception.Message -notmatch 'OWNER_MISMATCH') {throw}
    $Rejected=$true
  }
  if (-not $Rejected -or -not (Test-Path -LiteralPath $Lock)) {throw 'UNOWNED_RELEASE_NOT_BLOCKED'}
} finally { Exit-RunnerSessionLock -Session $Ticket2 }
if (Test-Path -LiteralPath $Lock) {throw 'LOCK_LEAK'}
[pscustomobject]@{ok=$true;status='M4_LEGACY_ATOMIC_ADMISSION_PASS';contenders=12;winners=1;busy=11;wrongOwnerReleaseRejected=$true;browserCalls=0} | ConvertTo-Json -Compress
