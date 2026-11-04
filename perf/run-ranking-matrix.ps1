#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidatePattern('^plan_mod_perf_[a-zA-Z0-9_]+$')]
    [string]$Database = 'plan_mod_perf_100k',
    [string]$VULadder = '100,150,200',
    [ValidateRange(1,10)]
    [int]$RunsPerLevel = 3,
    [ValidateRange(1,3600)]
    [int]$StageSeconds = 20,
    [ValidateRange(1,50)]
    [int]$Limit = 10,
    [ValidateRange(0,60)]
    [double]$SleepSeconds = 0.2,
    [ValidateRange(1025,65535)]
    [int]$Port = 8092,
    [ValidateRange(1,10000)]
    [double]$P95StopMs = 500,
    [ValidateRange(0.01,100)]
    [double]$FailureStopPct = 1.0,
    [switch]$RunTests
)

$ErrorActionPreference = 'Stop'
$perfDir = $PSScriptRoot
$runner = Join-Path $perfDir 'run-ranking-benchmark.ps1'
$resultsRoot = Join-Path $perfDir 'results'
if (-not (Test-Path -LiteralPath $runner)) { throw 'Missing run-ranking-benchmark.ps1.' }
if (-not (Test-Path -LiteralPath (Join-Path $perfDir 'ranking-mysql-load.js'))) { throw 'Missing ranking-mysql-load.js.' }
if (-not (Test-Path -LiteralPath $resultsRoot)) { New-Item -ItemType Directory -Path $resultsRoot -Force | Out-Null }

$vuLevels = @()
foreach ($part in ($VULadder -split ',')) {
    $value = 0
    if (-not [int]::TryParse($part.Trim(), [ref]$value) -or $value -lt 1 -or $value -gt 500) {
        throw "Invalid VU value '$part'. Use comma-separated integers from 1 to 500."
    }
    if ($vuLevels -contains $value) { throw "Duplicate VU value: $value" }
    $vuLevels += $value
}
if ($vuLevels.Count -eq 0) { throw 'VULadder cannot be empty.' }

function Get-Field($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-MetricField($Metrics, [string]$MetricName, [string]$FieldName, [switch]$Optional) {
    $metric = Get-Field $Metrics $MetricName
    if ($null -eq $metric) {
        if ($Optional) { return $null }
        throw "Missing metric '$MetricName'."
    }
    $values = Get-Field $metric 'values'
    $raw = $null
    if ($null -ne $values) { $raw = Get-Field $values $FieldName }
    if ($null -eq $raw) { $raw = Get-Field $metric $FieldName }
    if ($null -eq $raw) {
        if ($Optional) { return $null }
        throw "Missing metric field '$MetricName.$FieldName'."
    }
    $number = 0.0
    if (-not [double]::TryParse([string]$raw, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        throw "Non-numeric metric '$MetricName.$FieldName': $raw"
    }
    return $number
}

function Get-OptionalCounter($Metrics, [string]$MetricName) {
    $value = Get-MetricField $Metrics $MetricName 'count' -Optional
    if ($null -eq $value) { return $null }
    return [long][math]::Round([double]$value)
}

$originalPassword = [Environment]::GetEnvironmentVariable('MOD_DB_PASSWORD', 'Process')
$password = $originalPassword
if ([string]::IsNullOrWhiteSpace($password)) { $password = Read-Host 'Enter mod_app MySQL password' }
if ([string]::IsNullOrWhiteSpace($password)) { throw 'Database password is required.' }
$env:MOD_DB_PASSWORD = $password

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$matrixPath = Join-Path $resultsRoot "matrix-$stamp.md"
$csvPath = Join-Path $resultsRoot "matrix-$stamp.csv"
$allResults = @()
$stopReason = 'Completed all requested VU levels.'
$firstRun = $true
$stopMatrix = $false
$totalRuns = $vuLevels.Count * $RunsPerLevel
$currentRun = 0

try {
    Write-Host "Matrix: VUs=$($vuLevels -join ', '); runs per level=$RunsPerLevel; total planned runs=$totalRuns"
    Write-Host "Each run: 4 x ${StageSeconds}s; database=$Database; port=$Port"
    Write-Host "Safety stop: P95 >= ${P95StopMs}ms or HTTP failure rate >= ${FailureStopPct}%"

    foreach ($vu in $vuLevels) {
        if ($stopMatrix) { break }
        for ($round = 1; $round -le $RunsPerLevel; $round++) {
            if ($stopMatrix) { break }
            $currentRun++
            Write-Host "`n=== Matrix run $currentRun / $totalRuns : VUs=$vu, round=$round / $RunsPerLevel ==="

            $before = @{}
            Get-ChildItem -LiteralPath $resultsRoot -Directory | ForEach-Object { $before[$_.FullName] = $true }
            $runStarted = Get-Date
            $runError = $null
            $runParams = @{
                Database = $Database
                VUs = $vu
                StageSeconds = $StageSeconds
                Limit = $Limit
                SleepSeconds = $SleepSeconds
                Port = $Port
            }
            if ($RunTests -and $firstRun) { $runParams.RunTests = $true }

            try {
                & $runner @runParams
            }
            catch {
                $runError = $_.Exception.Message
                Write-Warning "Benchmark runner reported an error: $runError"
            }
            $firstRun = $false

            $newDirs = @(Get-ChildItem -LiteralPath $resultsRoot -Directory |
                Where-Object { $_.Name -like "*-$Database" -and -not $before.ContainsKey($_.FullName) } |
                Sort-Object CreationTime -Descending)
            if ($newDirs.Count -eq 0) {
                $allResults += [pscustomobject]@{
                    VUs=$vu; Round=$round; Requests=$null; AverageMs=$null; P95Ms=$null; QPS=$null
                    FailPct=$null; FailedRequests=$null; Http4xx=$null; Http429=$null; Http5xx=$null
                    NetworkFailures=$null; CheckPasses=$null; CheckFails=$null; Result='NO_OUTPUT'
                    Directory=''; Error=$runError
                }
                $stopReason = "No result directory was created for VUs=$vu round=$round."
                $stopMatrix = $true
                break
            }

            $resultDir = $newDirs[0]
            $summaryPath = Join-Path $resultDir.FullName 'k6-summary.json'
            if (-not (Test-Path -LiteralPath $summaryPath)) {
                $allResults += [pscustomobject]@{
                    VUs=$vu; Round=$round; Requests=$null; AverageMs=$null; P95Ms=$null; QPS=$null
                    FailPct=$null; FailedRequests=$null; Http4xx=$null; Http429=$null; Http5xx=$null
                    NetworkFailures=$null; CheckPasses=$null; CheckFails=$null; Result='SUMMARY_MISSING'
                    Directory=$resultDir.Name; Error=$runError
                }
                $stopReason = "Summary missing for VUs=$vu round=$round."
                $stopMatrix = $true
                break
            }

            try {
                $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $metrics = Get-Field $summary 'metrics'
                $requests = [long][math]::Round((Get-MetricField $metrics 'http_reqs' 'count'))
                $average = [math]::Round((Get-MetricField $metrics 'http_req_duration' 'avg'), 2)
                $p95 = [math]::Round((Get-MetricField $metrics 'http_req_duration' 'p(95)'), 2)
                $qps = [math]::Round((Get-MetricField $metrics 'http_reqs' 'rate'), 2)
                $failureRate = Get-MetricField $metrics 'http_req_failed' 'value' -Optional
                if ($null -eq $failureRate) { $failureRate = Get-MetricField $metrics 'http_req_failed' 'rate' }
                if ($failureRate -lt 0 -or $failureRate -gt 1) { throw "Invalid failure rate: $failureRate" }
                $failedRequests = [long][math]::Round($requests * $failureRate)
                $checks = Get-Field (Get-Field $summary 'root_group') 'checks'
                $httpCheck = Get-Field $checks 'HTTP 200'
                $checkPasses = Get-Field $httpCheck 'passes'
                $checkFails = Get-Field $httpCheck 'fails'
                $diag4xx = Get-OptionalCounter $metrics 'ranking_failed_http_4xx'
                $diag429 = Get-OptionalCounter $metrics 'ranking_failed_http_429'
                $diag5xx = Get-OptionalCounter $metrics 'ranking_failed_http_5xx'
                $diagNetwork = Get-OptionalCounter $metrics 'ranking_failed_network'
                $allResults += [pscustomobject]@{
                    VUs=$vu; Round=$round; Requests=$requests; AverageMs=$average; P95Ms=$p95; QPS=$qps
                    FailPct=[math]::Round($failureRate * 100, 3); FailedRequests=$failedRequests
                    Http4xx=$diag4xx; Http429=$diag429; Http5xx=$diag5xx; NetworkFailures=$diagNetwork
                    CheckPasses=$checkPasses; CheckFails=$checkFails
                    Result=$(if ($runError) { 'RUNNER_ERROR' } elseif ($failureRate -ge ($FailureStopPct / 100)) { 'THRESHOLD' } elseif ($p95 -ge $P95StopMs) { 'P95_LIMIT' } else { 'OK' })
                    Directory=$resultDir.Name; Error=$runError
                }
                Write-Host "Result: requests=$requests avg=${average}ms p95=${p95}ms qps=$qps fail=$([math]::Round($failureRate*100,3))%"
                if ($null -ne $diag4xx -or $null -ne $diag429 -or $null -ne $diag5xx -or $null -ne $diagNetwork) {
                    Write-Host "Failure classes: 4xx=$diag4xx 429=$diag429 5xx=$diag5xx network=$diagNetwork"
                }

                if ($runError) {
                    $stopReason = "Runner error at VUs=${vu} round=${round}: $runError"
                    $stopMatrix = $true
                } elseif (($failureRate * 100) -ge $FailureStopPct) {
                    $stopReason = "HTTP failure rate reached $([math]::Round($failureRate*100,3))% at VUs=$vu round=$round (stop threshold $FailureStopPct%)."
                    $stopMatrix = $true
                } elseif ($p95 -ge $P95StopMs) {
                    $stopReason = "P95 reached ${p95}ms at VUs=$vu round=$round (stop threshold ${P95StopMs}ms)."
                    $stopMatrix = $true
                }
            }
            catch {
                $parseError = $_.Exception.Message
                $allResults += [pscustomobject]@{
                    VUs=$vu; Round=$round; Requests=$null; AverageMs=$null; P95Ms=$null; QPS=$null
                    FailPct=$null; FailedRequests=$null; Http4xx=$null; Http429=$null; Http5xx=$null
                    NetworkFailures=$null; CheckPasses=$null; CheckFails=$null; Result='PARSE_ERROR'
                    Directory=$resultDir.Name; Error=$parseError
                }
                $stopReason = "Could not parse summary for VUs=${vu} round=${round}: $parseError"
                $stopMatrix = $true
            }
        }
    }

    $allResults | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    $lines = @(
        '# PlanBlindBox ranking load matrix',
        '',
        "- Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "- Database: $Database",
        "- VU ladder: $($vuLevels -join ', ')",
        "- Runs per level: $RunsPerLevel",
        "- Stages: 4 x ${StageSeconds}s; pause: ${SleepSeconds}s; top limit: $Limit",
        "- Safety stop: P95 >= ${P95StopMs}ms or HTTP failure rate >= ${FailureStopPct}%",
        "- Stop reason: $stopReason",
        '',
        '| VUs | Round | Requests | Avg (ms) | P95 (ms) | QPS | Fail (%) | HTTP 4xx | HTTP 429 | HTTP 5xx | Network | Result | Folder |',
        '|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|'
    )
    foreach ($r in $allResults) {
        $fmt = { param($v) if ($null -eq $v) { 'n/a' } else { [string]$v } }
        $lines += ('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | {12} |' -f `
            $r.VUs, $r.Round, (& $fmt $r.Requests), (& $fmt $r.AverageMs), (& $fmt $r.P95Ms),
            (& $fmt $r.QPS), (& $fmt $r.FailPct), (& $fmt $r.Http4xx), (& $fmt $r.Http429),
            (& $fmt $r.Http5xx), (& $fmt $r.NetworkFailures), $r.Result, $r.Directory)
    }
    $lines += ''
    $lines += '## Per-level averages'
    $lines += ''
    $lines += '| VUs | Valid runs | Mean requests | Mean avg (ms) | Mean P95 (ms) | Mean QPS | Mean fail (%) |'
    $lines += '|---:|---:|---:|---:|---:|---:|---:|'
    foreach ($group in ($allResults | Where-Object { $null -ne $_.Requests } | Group-Object VUs | Sort-Object { [int]$_.Name })) {
        $items = @($group.Group)
        $lines += ('| {0} | {1} | {2} | {3:N2} | {4:N2} | {5:N2} | {6:N3} |' -f `
            $group.Name, $items.Count,
            [math]::Round(($items | Measure-Object Requests -Average).Average),
            ($items | Measure-Object AverageMs -Average).Average,
            ($items | Measure-Object P95Ms -Average).Average,
            ($items | Measure-Object QPS -Average).Average,
            ($items | Measure-Object FailPct -Average).Average)
    }
    $lines += ''
    $lines += '- Note: Mean of per-run P95 values is not a pooled P95.'
    $lines += '- Missing diagnostic counters mean the k6 script did not emit those classifications; they are not treated as zero.'
    $lines | Set-Content -LiteralPath $matrixPath -Encoding UTF8

    Write-Host "`nMatrix report saved: $matrixPath"
    Write-Host "Matrix CSV saved: $csvPath"
    $lines | ForEach-Object { Write-Host $_ }
    if ($stopMatrix) { Write-Warning $stopReason }
}
finally {
    [Environment]::SetEnvironmentVariable('MOD_DB_PASSWORD', $originalPassword, 'Process')
    $password = $null
}
