$ErrorActionPreference = 'Stop'

# Apply the V2 analyzer-fix overlay to the Flutter frontend root.
$projectRoot = Split-Path -Parent $PSScriptRoot
$zipPath = Join-Path $PSScriptRoot 'planblindbox_v2_analyzer_fixes.zip'

if (-not (Test-Path -LiteralPath $zipPath)) {
    throw 'Cannot find planblindbox_v2_analyzer_fixes.zip beside this script.'
}

$relativeFiles = @(
    'lib\auth\auth_api.dart',
    'lib\auth\auth_pages.dart',
    'lib\data\local\local_database.dart',
    'lib\data\local\local_plan_repository.dart',
    'lib\data\local\sqflite_web_factory_stub.dart',
    'lib\data\wellbeing_repository.dart',
    'lib\screens\app_shell.dart',
    'lib\screens\custom_shop_pages.dart',
    'lib\screens\mod_management_page.dart',
    'lib\screens\mod_marketplace_page.dart',
    'lib\screens\my_page.dart',
    'lib\screens\store_page.dart',
    'lib\screens\user_cloud_progress_page.dart',
    'lib\services\core_sync_store.dart',
    'lib\services\mod_registry.dart'
)

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $projectRoot ".v2-analyzer-backup_$stamp"
foreach ($relative in $relativeFiles) {
    $source = Join-Path $projectRoot $relative
    if (Test-Path -LiteralPath $source) {
        $backup = Join-Path $backupRoot $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $backup -Force
    }
}
Write-Host "Backup created at: $backupRoot"

Write-Host 'Applying analyzer-fix overlay...'
Expand-Archive -LiteralPath $zipPath -DestinationPath $projectRoot -Force

Write-Host 'Formatting changed Dart files...'
$dartFiles = $relativeFiles | Where-Object { $_.EndsWith('.dart') } | ForEach-Object { Join-Path $projectRoot $_ }
& dart format $dartFiles
if ($LASTEXITCODE -ne 0) {
    throw "dart format failed with exit code $LASTEXITCODE. Backup: $backupRoot"
}

Write-Host ''
Write-Host 'Running flutter analyze...'
& flutter analyze
$analyzeExit = $LASTEXITCODE

Write-Host ''
Write-Host 'Running flutter test...'
& flutter test
$testExit = $LASTEXITCODE

Write-Host ''
Write-Host "flutter analyze exit code: $analyzeExit"
Write-Host "flutter test exit code: $testExit"
Write-Host "Backup: $backupRoot"

if ($analyzeExit -ne 0 -or $testExit -ne 0) {
    exit 1
}
Write-Host 'Analyzer and tests completed successfully.' -ForegroundColor Green
