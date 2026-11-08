$ErrorActionPreference = 'Stop'

# ASCII-only for compatibility with Windows PowerShell 5.1.
$projectRoot = Split-Path -Parent $PSScriptRoot
$clientDir = Join-Path $projectRoot 'opaque-client'
$packageJson = Join-Path $clientDir 'package.json'

if (-not (Test-Path -LiteralPath $packageJson)) {
    throw "Cannot find opaque-client/package.json. Put this script in frontend/scripts/."
}

# Resolve "npm" as PowerShell resolves it. Some installations expose npm.ps1
# rather than npm.cmd, so do not require the .cmd shim.
$npmCommand = Get-Command 'npm' -ErrorAction SilentlyContinue
if (-not $npmCommand) {
    Write-Host "Could not resolve npm in this PowerShell session."
    Write-Host "PATH=$env:PATH"
    Write-Host "Try: Get-Command npm -All"
    Write-Host "Try: where.exe npm"
    throw "npm was not found. Node.js/npm may be missing from PATH in this session."
}

Write-Host ("Using npm command: " + $npmCommand.Source)
Push-Location $clientDir
try {
    Write-Host '[1/3] Installing OPAQUE client dependencies...'
    if ($npmCommand.CommandType -eq 'Application' -or $npmCommand.CommandType -eq 'ExternalScript') {
        & $npmCommand.Source install
    }
    else {
        npm install
    }
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