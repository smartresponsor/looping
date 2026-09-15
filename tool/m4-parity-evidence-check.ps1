$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

Push-Location $Root
try {
    & php -d zend.assertions=1 -d assert.exception=1 tool/live-shadow-parity-evidence-regression.php
    if ($LASTEXITCODE -ne 0) {
        throw "M4 parity evidence regression failed with exit code $LASTEXITCODE"
    }

    & php tool/live-shadow-parity-summary.php
    if ($LASTEXITCODE -ne 0) {
        throw "M4 parity evidence summary failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
