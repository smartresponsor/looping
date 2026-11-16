param()
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
& node (Join-Path $Root 'tool/m5-atomic-transport-admission-regression.mjs')
if($LASTEXITCODE -ne 0){throw 'M5_ATOMIC_TRANSPORT_REGRESSION_FAILED'}
& php -d zend.assertions=1 -d assert.exception=1 (Join-Path $Root 'tool/m5-atomic-dispatch-planner-regression.php')
if($LASTEXITCODE -ne 0){throw 'M5_ATOMIC_DISPATCH_PLANNER_REGRESSION_FAILED'}
& php -d zend.assertions=1 -d assert.exception=1 (Join-Path $Root 'tool/m5-atomic-bridge-guard-regression.php')
if($LASTEXITCODE -ne 0){throw 'M5_ATOMIC_BRIDGE_GUARD_REGRESSION_FAILED'}
& node (Join-Path $Root 'tool/m5-scheduled-coordinator-regression.mjs')
if($LASTEXITCODE -ne 0){throw 'M5_SCHEDULED_COORDINATOR_REGRESSION_FAILED'}
Write-Output 'M5_ATOMIC_OFFLINE_ACCEPTANCE_PASS'
