param()
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
& node (Join-Path $Root 'tool/m5-atomic-transport-admission-regression.mjs')
if($LASTEXITCODE -ne 0){throw 'M5_ATOMIC_TRANSPORT_REGRESSION_FAILED'}
& php -d zend.assertions=1 -d assert.exception=1 (Join-Path $Root 'tool/m5-atomic-dispatch-planner-regression.php')
if($LASTEXITCODE -ne 0){throw 'M5_ATOMIC_DISPATCH_PLANNER_REGRESSION_FAILED'}
& php -d zend.assertions=1 -d assert.exception=1 (Join-Path $Root 'tool/m5-atomic-bridge-guard-regression.php')
if($LASTEXITCODE -ne 0){throw 'M5_ATOMIC_BRIDGE_GUARD_REGRESSION_FAILED'}
& node (Join-Path $Root 'tool/m5-console-capture-adapter-regression.mjs')
if($LASTEXITCODE -ne 0){throw 'M5_CONSOLE_CAPTURE_SCHEMA_REGRESSION_FAILED'}
& node (Join-Path $Root 'tool/m5-scheduled-coordinator-regression.mjs')
if($LASTEXITCODE -ne 0){throw 'M5_SCHEDULED_COORDINATOR_REGRESSION_FAILED'}
$CliOutput=& node (Join-Path $Root 'tool/m5-scheduled-cli.mjs')
if($LASTEXITCODE -ne 0 -or ($CliOutput | ConvertFrom-Json).status -ne 'M5_CLI_OFFLINE_ONLY'){throw 'M5_CLI_OFFLINE_PREFLIGHT_FAILED'}
$DeniedOutput=& node (Join-Path $Root 'tool/m5-scheduled-cli.mjs') --live 2>&1
if($LASTEXITCODE -ne 2 -or ($DeniedOutput | ConvertFrom-Json).status -ne 'M5_LIVE_CLI_NOT_ADMITTED'){throw 'M5_CLI_LIVE_DENIAL_FAILED'}
Write-Output 'M5_CLI_FAIL_CLOSED_PASS'
Write-Output 'M5_ATOMIC_OFFLINE_ACCEPTANCE_PASS'
