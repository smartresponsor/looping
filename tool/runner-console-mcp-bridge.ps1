param(
    [Parameter(Mandatory=$true)][string]$PayloadPath,
    [Parameter(Mandatory=$true)][string]$ResultPath
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Bridge = Join-Path $Root 'tool/runner-console-mcp-bridge.mjs'

if (-not (Test-Path $PayloadPath)) { throw "payload file not found: $PayloadPath" }

$Raw = & node $Bridge --payload $PayloadPath --result $ResultPath 2>&1
if ($LASTEXITCODE -ne 0) {
    throw ($Raw -join "`n")
}

$Raw | ConvertFrom-Json | ConvertTo-Json -Depth 40
