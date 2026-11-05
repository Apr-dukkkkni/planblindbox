# At the PlanBlindBox project root:
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot 'frontend')
flutter pub add cryptography
if ($LASTEXITCODE -ne 0) { throw 'flutter pub add cryptography failed' }
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed; do not deploy until fixed' }
