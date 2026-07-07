param([int]$Tail=20,[string]$Task="")
$ErrorActionPreference="Stop"
$Root=Split-Path -Parent $PSScriptRoot
$JournalPath=Join-Path $Root "var/runner/journal/runner.ndjson"
if(-not(Test-Path $JournalPath)){[pscustomobject]@{ok=$true;status="RUNNER_JOURNAL_EMPTY";journalPath=$JournalPath;filter=[pscustomobject]@{task=$Task;tail=$Tail};summary=[pscustomobject]@{total=0;returned=0;tasks=@();tools=@();statuses=@()};events=@()}|ConvertTo-Json -Depth 40;exit 0}
$Lines=@(Get-Content -Path $JournalPath|Where-Object{$_ -and $_.Trim()})
$Events=@()
foreach($Line in $Lines){try{$Event=$Line|ConvertFrom-Json;if($Task -and [string]$Event.task -ne $Task){continue};$Events+=$Event}catch{$Events+=[pscustomobject]@{component="runner-journal-inspect";status="RUNNER_JOURNAL_EVENT_PARSE_FAILED";raw=$Line}}}
$Returned=@($Events|Select-Object -Last $Tail)
$Tasks=@($Events|ForEach-Object{$_.task}|Where-Object{$_}|Sort-Object -Unique)
$Tools=@($Events|ForEach-Object{if($_.dispatchTool){$_.dispatchTool}elseif($_.expectedTool){$_.expectedTool}}|Where-Object{$_}|Sort-Object -Unique)
$Statuses=@($Events|ForEach-Object{$_.status}|Where-Object{$_}|Sort-Object -Unique)
[pscustomobject]@{ok=$true;status="RUNNER_JOURNAL_INSPECTED";journalPath=$JournalPath;filter=[pscustomobject]@{task=$Task;tail=$Tail};summary=[pscustomobject]@{total=@($Events).Count;returned=@($Returned).Count;tasks=$Tasks;tools=$Tools;statuses=$Statuses};events=$Returned}|ConvertTo-Json -Depth 60
