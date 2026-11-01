# One-time consolidated regression test for PlanBlindBox V2.1–V2.5.
# Runs only local automated tests; no writes to MySQL/Redis/RabbitMQ.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$original = Get-Location
$adminToken = $env:MOD_ADMIN_TOKEN
$hadAdminToken = Test-Path Env:MOD_ADMIN_TOKEN
try {
  Write-Host '[1/3] Maven mod-server tests' -ForegroundColor Cyan
  # Test-only token is configured inside test/resources/application.yml.
  Remove-Item Env:MOD_ADMIN_TOKEN -ErrorAction SilentlyContinue
  Set-Location (Join-Path $root 'mod-server')
  & mvn clean test
  if ($LASTEXITCODE -ne 0) { throw 'mod-server mvn clean test failed' }

  Write-Host '[2/3] Flutter dependencies' -ForegroundColor Cyan
  Set-Location (Join-Path $root 'frontend')
  & flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }

  Write-Host '[3/3] Flutter tests' -ForegroundColor Cyan
  & flutter test
  if ($LASTEXITCODE -ne 0) { throw 'flutter test failed' }

  Write-Host 'All automated tests passed.' -ForegroundColor Green
} finally {
  if ($hadAdminToken) { $env:MOD_ADMIN_TOKEN = $adminToken }
  else { Remove-Item Env:MOD_ADMIN_TOKEN -ErrorAction SilentlyContinue }
  Set-Location $original
}
