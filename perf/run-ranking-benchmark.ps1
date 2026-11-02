#requires -Version 5.1
# PlanBlindBox ranking benchmark runner (Windows PowerShell 5.1 compatible).
# No DDL, grants, deletes, imports, or changes to other services.
param(
    [ValidatePattern('^plan_mod_perf_[a-zA-Z0-9_]+$')][string]$Database = 'plan_mod_perf_100k',
    [ValidateRange(1,500)][int]$VUs = 50,
    [ValidateRange(1,3600)][int]$StageSeconds = 20,
    [ValidateRange(1,50)][int]$Limit = 10,
    [ValidateRange(0,60)][double]$SleepSeconds = 0.2,
    [ValidateRange(1025,65535)][int]$Port = 8092,
    [switch]$RunTests,
    [string]$BaselineJson = ''
)

$ErrorActionPreference = 'Stop'
$perfDir = $PSScriptRoot
$root = Split-Path -Path $perfDir -Parent
$serverDir = Join-Path $root 'mod-server'
$k6Script = Join-Path $perfDir 'ranking-mysql-load.js'

if (-not (Test-Path (Join-Path $serverDir 'pom.xml'))) {
    throw "Missing mod-server/pom.xml under $root"
}
if (-not (Test-Path $k6Script)) { throw 'Missing ranking-mysql-load.js next to this script.' }
foreach ($program in @('mvn', 'java', 'docker', 'curl.exe')) {
    if (-not (Get-Command $program -ErrorAction SilentlyContinue)) {
        throw "Missing required command: $program"
    }
}
if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
    throw "Port $Port is already in use. Stop the existing test service first; this script will not kill it."
}

$password = $env:MOD_DB_PASSWORD
if ([string]::IsNullOrWhiteSpace($password)) {
    $password = Read-Host 'Enter mod_app MySQL password'
}
if ([string]::IsNullOrWhiteSpace($password)) { throw 'A database password is required.' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDirName = "$stamp-$Database"
$outDir = Join-Path (Join-Path $perfDir 'results') $outDirName
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$logPath = Join-Path $outDir 'server.log'
$errPath = Join-Path $outDir 'server-err.log'
$summaryPath = Join-Path $outDir 'k6-summary.json'
$reportPath = Join-Path $outDir 'report.md'

$envNames = @(
    'MOD_SERVER_PORT', 'MOD_DB_URL', 'MOD_DB_USER', 'MOD_DB_PASSWORD',
    'MOD_RANKING_ENABLED', 'SPRING_FLYWAY_ENABLED',
    'SERVER_ERROR_INCLUDE_STACKTRACE', 'SERVER_ERROR_INCLUDE_MESSAGE',
    'SERVER_ERROR_INCLUDE_EXCEPTION',
    'SPRING_DATASOURCE_URL', 'SPRING_DATASOURCE_USERNAME', 'SPRING_DATASOURCE_PASSWORD'
)
$oldEnv = @{}
foreach ($name in $envNames) {
    $oldEnv[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$serverProcess = $null

try {
    # Maven integration tests use H2 + Flyway. Clear any inherited benchmark
    # datasource overrides before running tests (never point tests at perf MySQL).
    foreach ($name in @(
        'MOD_SERVER_PORT', 'MOD_DB_URL', 'MOD_DB_USER', 'MOD_DB_PASSWORD',
        'MOD_RANKING_ENABLED', 'SPRING_FLYWAY_ENABLED',
        'SPRING_DATASOURCE_URL', 'SPRING_DATASOURCE_USERNAME', 'SPRING_DATASOURCE_PASSWORD'
    )) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }

    Push-Location $serverDir
    try {
        if ($RunTests) {
            Write-Host 'Running Maven tests using H2 and Flyway...'
            & mvn -B clean test
            if ($LASTEXITCODE -ne 0) { throw "Maven tests failed (exit $LASTEXITCODE)." }
        }
        Write-Host 'Building backend JAR...'
        & mvn -B -DskipTests package
        if ($LASTEXITCODE -ne 0) { throw "Maven package failed (exit $LASTEXITCODE)." }
        $jar = Get-ChildItem -Path (Join-Path $serverDir 'target') -Filter '*.jar' |
            Where-Object { $_.Name -notmatch '(original|sources|javadoc)' } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -eq $jar) { throw 'Cannot find runnable JAR under mod-server/target.' }
    }
    finally {
        Pop-Location
    }

    # Only the benchmark backend receives these settings; tests have completed.
    $env:MOD_SERVER_PORT = [string]$Port
    $env:MOD_DB_URL = "jdbc:mysql://127.0.0.1:3306/${Database}?useUnicode=true&characterEncoding=utf8&serverTimezone=Asia/Shanghai"
    $env:MOD_DB_USER = 'mod_app'
    $env:MOD_DB_PASSWORD = $password
    $env:MOD_RANKING_ENABLED = 'false'
    $env:SPRING_FLYWAY_ENABLED = 'false'
    $env:SERVER_ERROR_INCLUDE_STACKTRACE = 'never'
    $env:SERVER_ERROR_INCLUDE_MESSAGE = 'never'
    $env:SERVER_ERROR_INCLUDE_EXCEPTION = 'false'

    Write-Host "Starting isolated backend on port $Port..."
    $serverProcess = Start-Process -FilePath 'java' `
        -ArgumentList @('-jar', ('"' + $jar.FullName + '"')) `
        -WorkingDirectory $serverDir -PassThru `
        -RedirectStandardOutput $logPath -RedirectStandardError $errPath

    $localUrl = "http://127.0.0.1:${Port}/api/v1/mods/ranking?limit=$Limit"
    Write-Host "Waiting for HTTP 200 at $localUrl ..."
    $ready = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if ($serverProcess.HasExited) {
            throw "Backend exited early. See $logPath and $errPath"
        }
        $status = & curl.exe -s --max-time 3 -o NUL -w '%{http_code}' $localUrl
        if ($status -eq '200') { $ready = $true; break }
        if ($status -eq '500') {
            throw "Endpoint returned HTTP 500. Check DB connection, permissions, and logs: $logPath"
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw "Endpoint never reached HTTP 200. See $logPath" }

    $targetUrl = "http://host.docker.internal:${Port}/api/v1/mods/ranking?limit=$Limit"
    Write-Host "Running k6: db=$Database, vus=$VUs, stage=${StageSeconds}s, limit=$Limit"
    $mountPath = $perfDir -replace '\\', '/'
    $summaryInContainer = "/scripts/results/$outDirName/k6-summary.json"
    & docker run --rm -v "${mountPath}:/scripts" `
        -e "TARGET_URL=$targetUrl" -e "VUS=$VUs" `
        -e "STAGE_SECONDS=${StageSeconds}s" -e "SLEEP_SECONDS=$SleepSeconds" `
        grafana/k6 run --summary-export $summaryInContainer /scripts/ranking-mysql-load.js
    if ($LASTEXITCODE -ne 0) { throw "k6 exited with code $LASTEXITCODE." }
    if (-not (Test-Path $summaryPath)) { throw "k6 summary not found: $summaryPath" }

    $summary = Get-Content -Path $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $metrics = $summary.metrics
    $avgMs = [math]::Round([double]$metrics.http_req_duration.values.avg, 2)
    $p95Ms = [math]::Round([double]$metrics.http_req_duration.values.'p(95)', 2)
    $requestCount = $metrics.http_reqs.values.count
    $qps = [math]::Round([double]$metrics.http_reqs.values.rate, 2)
    $errorPct = [math]::Round([double]$metrics.http_req_failed.values.rate * 100, 3)

    $lines = @(
        '# PlanBlindBox ranking benchmark',
        '',
        "- Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "- Database: $Database",
        "- Stages: 4 x ${StageSeconds}s; peak VUs: $VUs; pause: ${SleepSeconds}s; limit: $Limit",
        "- Requests: $requestCount",
        "- Average: $avgMs ms",
        "- P95: $p95Ms ms",
        "- QPS: $qps",
        "- HTTP failure rate: $errorPct%"
    )
    if (-not [string]::IsNullOrWhiteSpace($BaselineJson)) {
        $baseline = Get-Content -Path $BaselineJson -Raw -Encoding UTF8 | ConvertFrom-Json
        $baselineP95 = [double]$baseline.metrics.http_req_duration.values.'p(95)'
        $baselineQps = [double]$baseline.metrics.http_reqs.values.rate
        if ($baselineP95 -gt 0) {
            $lines += "- P95 vs baseline: $([math]::Round($p95Ms / $baselineP95, 2)) x (lower is better)"
        }
        if ($baselineQps -gt 0) {
            $lines += "- QPS vs baseline: $([math]::Round($qps / $baselineQps, 2)) x (higher is better)"
        }
    }
    $lines | Set-Content -Path $reportPath -Encoding UTF8
    Write-Host "`nReport saved: $reportPath"
    $lines | ForEach-Object { Write-Host $_ }
}
finally {
    if (($null -ne $serverProcess) -and (-not $serverProcess.HasExited)) {
        Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
    }
    foreach ($name in $envNames) {
        [Environment]::SetEnvironmentVariable($name, $oldEnv[$name], 'Process')
    }
    $password = $null
}
