function Enter-RunnerSessionLock {
    param([Parameter(Mandatory=$true)][ValidateSet('repo-smoke','runtime-smoke','task-bank')][string]$Owner)
    $Root = Split-Path -Parent $PSScriptRoot
    $Path = Join-Path $Root 'var/runner/lock/runner.lock'
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $Token = [guid]::NewGuid().ToString('N')
    try {
        $Handle = [System.IO.File]::Open($Path,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)
    } catch [System.IO.IOException] {
        throw (($Owner.Replace('-','_').ToUpperInvariant()) + '_SHARED_RUNNER_LOCK_BUSY')
    }
    try {
        $Metadata = [pscustomobject]@{owner=$Owner;sessionToken=$Token;pid=$PID;acquiredAt=(Get-Date).ToUniversalTime().ToString('o')}
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes(($Metadata | ConvertTo-Json -Compress))
        $Handle.Write($Bytes,0,$Bytes.Length)
        $Handle.Flush($true)
    } finally { $Handle.Dispose() }
    return [pscustomobject]@{path=$Path;owner=$Owner;token=$Token}
}

function Exit-RunnerSessionLock {
    param([Parameter(Mandatory=$true)]$Session)
    if (-not (Test-Path -LiteralPath $Session.path)) { return }
    try { $Actual = Get-Content -Raw -LiteralPath $Session.path | ConvertFrom-Json }
    catch { throw 'RUNNER_SESSION_LOCK_METADATA_CORRUPT_RECONCILE_MANUALLY' }
    if ($Actual.owner -ne $Session.owner -or $Actual.sessionToken -ne $Session.token) {
        throw 'RUNNER_SESSION_LOCK_OWNER_MISMATCH_RECONCILE_MANUALLY'
    }
    Remove-Item -LiteralPath $Session.path -Force
}
