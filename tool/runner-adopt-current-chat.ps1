param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,119}$')][string]$ComponentName,
    [Parameter(Mandatory=$true)][string]$CurrentChatUrl,
    [ValidateRange(1,100)][int]$MaxIterations = 3,
    [string]$WorkspaceRoot = 'D:\PhpstormProjects\www'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Runner = Join-Path $Root 'tool/runner-repo-smoke.ps1'

try { $Uri = [Uri]$CurrentChatUrl } catch { throw "invalid CurrentChatUrl: $CurrentChatUrl" }
if ($Uri.Scheme -ne 'https' -or $Uri.Host -notin @('chatgpt.com','chat.openai.com')) {
    throw "CurrentChatUrl must be an HTTPS ChatGPT conversation URL: $CurrentChatUrl"
}
if ($Uri.AbsolutePath -notmatch '^/(?:c|chat)/([0-9a-fA-F-]{36})/?$') {
    throw "CurrentChatUrl does not contain a supported conversation id: $CurrentChatUrl"
}
$ChatId = $Matches[1].ToLowerInvariant()
$TargetRepo = Join-Path $WorkspaceRoot $ComponentName
if (-not (Test-Path -LiteralPath $TargetRepo -PathType Container)) {
    [pscustomobject]@{
        ok = $false
        status = 'ADOPT_TARGET_REPOSITORY_NOT_FOUND'
        componentName = $ComponentName
        targetRepo = $TargetRepo
        chatId = $ChatId
        nextAction = 'provide_existing_component_name'
    } | ConvertTo-Json -Depth 20
    exit 1
}

& $Runner -TargetRepo $TargetRepo -MaxIterations $MaxIterations -Name $ComponentName -Chain -EngineExecutor -AdoptChatId $ChatId
exit $LASTEXITCODE
