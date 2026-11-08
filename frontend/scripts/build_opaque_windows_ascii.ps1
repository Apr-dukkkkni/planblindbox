$ErrorActionPreference = 'Stop'

# This script intentionally contains ASCII-only text so Windows PowerShell 5.1
# can read it regardless of the local ANSI code page.

$projectRoot = Split-Path -Parent $PSScriptRoot
$clientDir = Join-Path $projectRoot 'opaque-client'
$packageJson = Join-Path $clientDir 'package.json'

if (-not (Test-Path -LiteralPath $packageJson)) {
    throw "Cannot find opaque-client/package.json. Put this script in frontend/scripts/."
}

$npmCommand = Get-Command 'npm.cmd' -ErrorAction SilentlyContinue
if (-not $npmCommand) {
    throw "npm.cmd was not found. Install Node.js LTS and reopen PowerShell."
}

Push-Location $clientDir
try {
    Write-Host '[1/3] Installing OPAQUE client dependencies...'
    & $npmCommand.Source install
    if ($LASTEXITCODE -ne 0) {
        throw "npm install failed with exit code $LASTEXITCODE."
    }

    $esbuild = Join-Path $clientDir 'node_modules\.bin\esbuild.cmd'
    if (-not (Test-Path -LiteralPath $esbuild)) {
        throw "esbuild was not installed at node_modules/.bin/esbuild.cmd."
    }

    Write-Host '[2/3] Building OPAQUE client bundle...'
    & $esbuild '.\src\bridge.js' --bundle --format=iife --target=es2022 '--outfile=..\web\opaque_client.js'
    if ($LASTEXITCODE -ne 0) {
        throw "esbuild failed with exit code $LASTEXITCODE."
    }

    Write-Host '[3/3] Copying bundle to Flutter assets...'
    $webBundle = Join-Path $projectRoot 'web\opaque_client.js'
    $assetDir = Join-Path $projectRoot 'assets\opaque'
    $assetBundle = Join-Path $assetDir 'opaque_client.js'

    if (-not (Test-Path -LiteralPath $webBundle)) {
        throw "Build output was not created: $webBundle"
    }

    if (-not (Test-Path -LiteralPath $assetDir)) {
        New-Item -ItemType Directory -Path $assetDir -Force | Out-Null
    }

    Copy-Item -LiteralPath $webBundle -Destination $assetBundle -Force

    Write-Host ''
    Write-Host 'OPAQUE client build completed successfully.' -ForegroundColor Green
    Get-Item -LiteralPath $webBundle, $assetBundle |
        Select-Object FullName, Length |
        Format-Table -AutoSize
}
finally {
    Pop-Location
}
