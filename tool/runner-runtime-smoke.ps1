param([string]$Task="runtime-smoke",[int]$MaxIterations=2)
$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $PSScriptRoot
$Daemon=Join-Path $Root "tool/runner-daemon.ps1"
$Adapter=Join-Path $Root "tool/runner-transport-adapter.ps1"
$FirstRaw=& $Daemon -Task $Task -MaxIterations $MaxIterations 2>&1
$First=$FirstRaw|ConvertFrom-Json
if($First.status -eq "RUNNER_DAEMON_STARTED"){$FirstRaw=& $Daemon -Task $Task -MaxIterations $MaxIterations 2>&1;$First=$FirstRaw|ConvertFrom-Json}
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
[pscustomobject]@{ok=$true;status="RUNNER_RUNTIME_SMOKE_PASSED";task=$Task;firstStatus=$First.status;tool=$Tool;resultStatus=$ResultStatus;adapterStatus=$AdapterPayload.status;secondStatus=$Second.status;handoffPath=$First.handoffPath;resultPath=$First.expectedResultPath}|ConvertTo-Json -Depth 40
