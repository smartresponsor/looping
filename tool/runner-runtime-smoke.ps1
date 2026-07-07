param([string]$Task="runtime-smoke",[int]$MaxIterations=2)
$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $PSScriptRoot
$Daemon=Join-Path $Root "tool/runner-daemon.ps1"
$Adapter=Join-Path $Root "tool/runner-transport-adapter.ps1"
$StateDir=Join-Path $Root "var/runner/state"
$StatePath=Join-Path $StateDir "latest.json"
$BackupPath=$null
$LockPath=Join-Path $Root "var/runner/lock/runner.lock"
if(Test-Path $LockPath){Remove-Item -Path $LockPath -Force}
if(Test-Path $StatePath){$BackupPath=$StatePath+".runtime-smoke.bak";Move-Item -Path $StatePath -Destination $BackupPath -Force}
trap{if(Test-Path $LockPath){Remove-Item -Path $LockPath -Force};if($BackupPath -and (Test-Path $BackupPath)){Move-Item -Path $BackupPath -Destination $StatePath -Force};throw $_}
if(-not(Test-Path $StateDir)){New-Item -ItemType Directory -Path $StateDir|Out-Null}
$RunId="runtime-smoke-"+([guid]::NewGuid().ToString("N"))
$Seed=[ordered]@{ok=$true;status="RUNNER_STATE_PERSISTED";schemaVersion=2;runtimeVersion="2026.07.runner-loop";runId=$RunId;taskId=$Task;runnerMode="runtime_smoke_seed";finalActionSelected="runtime_smoke";finalActionResult=[ordered]@{ok=$true;status="FINAL_ACTION_RESUME_LATEST";action="resume_latest";nextAction="dispatch_next_from_state"};nextDispatchContract=[ordered]@{ok=$true;status="RUNTIME_SMOKE_DISPATCH_CONTRACT_READY";stage="recovery";tool="console.write.engine.chat.bind";arguments=[ordered]@{taskId=$Task;requireVisibleTarget=$false;refreshBinding=$false;recoveryMode="runtime_smoke"};mutation="write";confirmationRequired=$false;execution="external_console_mcp_required";nextAction="dispatch_recovery_chat_bind"};budget=[ordered]@{mode="steps";remaining=$MaxIterations;untilRc=$false};retryPolicy=$null;retryAttempt=0;recoveryPlan=$null;updatedAt=(Get-Date).ToUniversalTime().ToString("o")}
[pscustomobject]$Seed|ConvertTo-Json -Depth 40|Set-Content -Path $StatePath -Encoding UTF8
$FirstRaw=& $Daemon -Task $Task -MaxIterations $MaxIterations 2>&1
$First=$FirstRaw|ConvertFrom-Json
if($First.status -ne "RUNNER_DAEMON_DISPATCH_READY"){throw "runtime smoke daemon was not dispatch ready: $($First.status)"}
$Tool=[string]$First.toolCall.name
$ResultStatus=switch($Tool){"console.write.engine.chat.bind"{"ENGINE_CHAT_BIND_RECOVERED"}"console.write.engine.answer.capture"{"ENGINE_ANSWER_CAPTURED"}"console.write.engine.gateway.decide"{"ENGINE_GATEWAY_DECISION_RECORDED"}"console.write.engine.worker.tick"{"ENGINE_WORKER_TICK_ACCEPTED"}"console.write.engine.reply.draft"{"ENGINE_REPLY_DRAFTED"}"console.write.engine.reply.submit"{"ENGINE_REPLY_SUBMITTED"}default{"ENGINE_TOOL_RESULT_ACCEPTED"}}
$Result=[pscustomobject]@{ok=$true;tool=$Tool;status=$ResultStatus;task_id=$Task;chat_id="runtime-smoke-chat";target_id="runtime-smoke-target";decision="CONTINUE";decision_status="CONTINUE"}
$Result|ConvertTo-Json -Depth 20|Set-Content -Path $First.expectedResultPath -Encoding UTF8
$AdapterRaw=& $Adapter -Task $Task -MaxIterations $MaxIterations -PayloadPath $First.dispatchPayloadPath -ResultPath $First.expectedResultPath 2>&1
$AdapterPayload=$AdapterRaw|ConvertFrom-Json
if($AdapterPayload.status -ne "RUNNER_TRANSPORT_ADAPTER_FED"){throw "runtime smoke adapter did not feed: $($AdapterPayload.status)"}
$SecondRaw=& $Daemon -Task $Task -MaxIterations $MaxIterations 2>&1
$Second=$SecondRaw|ConvertFrom-Json
if(Test-Path $LockPath){Remove-Item -Path $LockPath -Force}
if($BackupPath -and (Test-Path $BackupPath)){Move-Item -Path $BackupPath -Destination $StatePath -Force}
[pscustomobject]@{ok=$true;status="RUNNER_RUNTIME_SMOKE_PASSED";task=$Task;firstStatus=$First.status;tool=$Tool;resultStatus=$ResultStatus;adapterStatus=$AdapterPayload.status;secondStatus=$Second.status;handoffPath=$First.handoffPath;resultPath=$First.expectedResultPath}|ConvertTo-Json -Depth 40
