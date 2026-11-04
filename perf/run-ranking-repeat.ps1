#requires -Version 5.1
# Runs the existing PlanBlindBox benchmark N times and writes a comparison.
param(
    [ValidatePattern('^plan_mod_perf_[a-zA-Z0-9_]+$')][string]$Database = 'plan_mod_perf_100k',
    [ValidateRange(1,500)][int]$VUs = 50,
    [ValidateRange(1,3600)][int]$StageSeconds = 20,
    [ValidateRange(1,50)][int]$Limit = 10,
    [ValidateRange(0,60)][double]$SleepSeconds = 0.2,
    [ValidateRange(1,10)][int]$Runs = 3,
    [switch]$RunTests
)
$ErrorActionPreference = 'Stop'
$perfDir = $PSScriptRoot
$runner = Join-Path $perfDir 'run-ranking-benchmark.ps1'
if (-not (Test-Path $runner)) { throw 'Missing run-ranking-benchmark.ps1' }
$originalPassword = [Environment]::GetEnvironmentVariable('MOD_DB_PASSWORD','Process')
$secret = $originalPassword
if ([string]::IsNullOrWhiteSpace($secret)) { $secret = Read-Host 'Enter mod_app MySQL password' }
if ([string]::IsNullOrWhiteSpace($secret)) { throw 'Database password required.' }
$env:MOD_DB_PASSWORD = $secret
$results = @()
$sessionStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$comparisonPath = Join-Path (Join-Path $perfDir 'results') "comparison-$sessionStamp.md"
try {
    for ($i = 1; $i -le $Runs; $i++) {
        Write-Host "`n--- Ranking run $i / $Runs ---"
        $start = Get-Date
        $params = @{
            Database = $Database
            VUs = $VUs
            StageSeconds = $StageSeconds
            Limit = $Limit
            SleepSeconds = $SleepSeconds
        }
        if ($RunTests -and $i -eq 1) { $params.RunTests = $true }
        & $runner @params
        # Every successful invocation creates exactly one new result directory.
        $dirs = @(Get-ChildItem -LiteralPath (Join-Path $perfDir 'results') -Directory |
            Where-Object { $_.Name -like "*-$Database" -and $_.CreationTime -ge $start.AddSeconds(-2) } |
            Sort-Object CreationTime -Descending)
        if ($dirs.Count -eq 0) { throw "Cannot locate result directory for run $i" }
        $summaryPath = Join-Path $dirs[0].FullName 'k6-summary.json'
        if (-not (Test-Path $summaryPath)) { throw "Missing summary: $summaryPath" }
        $m = (Get-Content $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json).metrics
        $results += [pscustomobject]@{
            Run = $i
            Requests = [long]$m.http_reqs.values.count
            P95 = [double]$m.http_req_duration.values.'p(95)'
            QPS = [double]$m.http_reqs.values.rate
            FailPct = [double]$m.http_req_failed.values.value * 100
            Directory = $dirs[0].Name
        }
    }
    $rows = @(
        '# Ranking repeatability results',
        '',
        "- Database: $Database",
        "- Runs: $Runs, VUs: $VUs, stage seconds: $StageSeconds, sleep: $SleepSeconds, top limit: $Limit",
        '',
        '| Run | Requests | P95 (ms) | QPS | Fail (%) | Result folder |',
        '|---:|---:|---:|---:|---:|---|'
    )
    foreach ($r in $results) {
        $rows += ('| {0} | {1} | {2:N2} | {3:N2} | {4:N3} | {5} |' -f $r.Run,$r.Requests,$r.P95,$r.QPS,$r.FailPct,$r.Directory)
    }
    $avgP95 = [math]::Round(($results | Measure-Object -Property P95 -Average).Average,2)
    $avgQps = [math]::Round(($results | Measure-Object -Property QPS -Average).Average,2)
    $rows += ''
    $rows += "- Average of run P95 values: $avgP95 ms"
    $rows += "- Average of run QPS values: $avgQps"
    $rows += '- Note: Mean of individual-run P95s is not pooled P95.'
    $rows | Set-Content -LiteralPath $comparisonPath -Encoding UTF8
    Write-Host "`nComparison saved: $comparisonPath"
    $rows | ForEach-Object { Write-Host $_ }
} finally {
    [Environment]::SetEnvironmentVariable('MOD_DB_PASSWORD',$originalPassword,'Process')
    $secret = $null
}
