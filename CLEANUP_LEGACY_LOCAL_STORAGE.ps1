[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$FrontendRoot = Join-Path $ProjectRoot 'frontend'
$LibRoot = Join-Path $FrontendRoot 'lib'
$TestRoot = Join-Path $FrontendRoot 'test'

$RequiredFiles = @(
    (Join-Path $FrontendRoot 'pubspec.yaml'),
    (Join-Path $LibRoot 'data/local/local_database.dart'),
    (Join-Path $LibRoot 'data/local/local_plan_repository.dart'),
    (Join-Path $LibRoot 'data/local/sqflite_web_factory_stub.dart')
)
foreach ($file in $RequiredFiles) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "项目结构不符合预期，缺少主实现文件：$file。没有删除任何文件。"
    }
}

$ActiveDatabase = Get-Content -LiteralPath (Join-Path $LibRoot 'data/local/local_database.dart') -Raw
if ($ActiveDatabase -notmatch 'version:\s*8\s*,') {
    throw '主数据库尚未升级到 schema v8。请先应用上一轮 Frontend Repair Patch；没有删除任何文件。'
}

$Pubspec = Get-Content -LiteralPath (Join-Path $FrontendRoot 'pubspec.yaml') -Raw
$NameMatch = [regex]::Match($Pubspec, '(?m)^name:\s*([A-Za-z0-9_]+)\s*$')
if (-not $NameMatch.Success) {
    throw '无法从 pubspec.yaml 读取 Dart package 名称。没有删除任何文件。'
}
$PackageName = $NameMatch.Groups[1].Value

$LegacyRelativePaths = @(
    'lib/local/local_database.dart',
    'lib/local/local_plan_repository.dart',
    'lib/local/local_growth_service.dart',
    'lib/local/sqflite_web_factory_stub.dart',
    'lib/data/local_database.dart'
)
$LegacyFullPaths = @{}
foreach ($relative in $LegacyRelativePaths) {
    $full = [System.IO.Path]::GetFullPath((Join-Path $FrontendRoot $relative))
    $LegacyFullPaths[$full.ToLowerInvariant()] = $relative
}

# Refuse to delete a legacy file if any non-legacy Dart file still imports it.
$DartRoots = @($LibRoot, $TestRoot) | Where-Object { Test-Path -LiteralPath $_ }
$DartFiles = Get-ChildItem -Path $DartRoots -Recurse -File -Filter '*.dart'
$ImportPattern = [regex]'(?m)(?:import|export|part)\s+[''"]([^''"]+)[''"]'
$ExternalReferences = @()

foreach ($sourceFile in $DartFiles) {
    $sourceFull = [System.IO.Path]::GetFullPath($sourceFile.FullName)
    if ($LegacyFullPaths.ContainsKey($sourceFull.ToLowerInvariant())) {
        continue
    }

    $sourceText = Get-Content -LiteralPath $sourceFull -Raw
    foreach ($match in $ImportPattern.Matches($sourceText)) {
        $uri = $match.Groups[1].Value
        $candidate = $null

        if ($uri.StartsWith('dart:')) {
            continue
        }
        elseif ($uri.StartsWith("package:$PackageName/")) {
            $packagePath = $uri.Substring(("package:$PackageName/").Length)
            $candidate = Join-Path $LibRoot $packagePath
        }
        elseif ($uri.StartsWith('package:')) {
            continue
        }
        else {
            $candidate = Join-Path $sourceFile.DirectoryName $uri
        }

        if ($null -ne $candidate) {
            $candidateFull = [System.IO.Path]::GetFullPath($candidate)
            if ($LegacyFullPaths.ContainsKey($candidateFull.ToLowerInvariant())) {
                $lineNumber = ($sourceText.Substring(0, $match.Index) -split "`n").Count
                $ExternalReferences += "$($sourceFile.FullName):$lineNumber -> $uri"
            }
        }
    }
}

if ($ExternalReferences.Count -gt 0) {
    Write-Host '发现仍然引用旧文件的 Dart 代码，已中止删除：' -ForegroundColor Red
    $ExternalReferences | ForEach-Object { Write-Host "  $_" }
    throw '请先迁移这些引用，再重新执行清理脚本。没有删除任何文件。'
}

Write-Host '依赖检查通过：没有非遗留 Dart 文件引用待删除文件。' -ForegroundColor Green
Write-Host '将清理以下旧实现：'
$LegacyRelativePaths | ForEach-Object { Write-Host "  frontend/$_" }

foreach ($relative in $LegacyRelativePaths) {
    $target = Join-Path $FrontendRoot $relative
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        if ($PSCmdlet.ShouldProcess($target, '删除已确认无外部引用的旧版实现')) {
            Remove-Item -LiteralPath $target -Force
            Write-Host "已删除：frontend/$relative" -ForegroundColor Yellow
        }
    }
}

$LegacyDirectory = Join-Path $LibRoot 'local'
if ((Test-Path -LiteralPath $LegacyDirectory -PathType Container) -and
    -not (Get-ChildItem -LiteralPath $LegacyDirectory -Force | Select-Object -First 1)) {
    if ($PSCmdlet.ShouldProcess($LegacyDirectory, '删除空的旧版目录')) {
        Remove-Item -LiteralPath $LegacyDirectory -Force
        Write-Host '已删除空目录：frontend/lib/local' -ForegroundColor Yellow
    }
}
elseif (Test-Path -LiteralPath $LegacyDirectory -PathType Container) {
    Write-Host 'frontend/lib/local 中仍有其他文件，保留目录，不做批量删除。' -ForegroundColor Cyan
}

Write-Host ''
Write-Host '清理结束。主数据库与仓储保留在：' -ForegroundColor Green
Write-Host '  frontend/lib/data/local/local_database.dart'
Write-Host '  frontend/lib/data/local/local_plan_repository.dart'
Write-Host 'Web 条件导入占位文件保留在：'
Write-Host '  frontend/lib/data/local/sqflite_web_factory_stub.dart'
