#requires -Version 5.1
# Convert an existing k6 --summary-export JSON to a validated Markdown report.
# Run independently: does not start services, change environments, or rerun k6.
param(
    [Parameter(Mandatory=$true)][string]$SummaryPath,
    [string]$Database = 'plan_mod_perf_100k',
    [ValidateRange(1,500)][int]$VUs = 50,
    [ValidateRange(1,3600)][int]$StageSeconds = 20,
    [ValidateRange(1,50)][int]$Limit = 10,
    [ValidateRange(0,60)][double]$SleepSeconds = 0.2,
    [string]$BaselineJson = ''
)
$ErrorActionPreference = 'Stop'

function Get-PropertyValue($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [System.Collections.IDictionary]) {
        if ($obj.Contains($name)) { return $obj[$name] }
        return $null
    }
    $prop = $obj.PSObject.Properties[$name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}
function Get-Metrics($summary) {
    $m = Get-PropertyValue $summary 'metrics'
    if ($null -ne $m) { return $m }
    foreach ($parentName in @('data','summary')) {
        $parent = Get-PropertyValue $summary $parentName
        $m = Get-PropertyValue $parent 'metrics'
        if ($null -ne $m) { return $m }
    }
    return $null
}
function Get-MetricNumber($summary, [string]$name, [string]$field) {
    $metrics = Get-Metrics $summary
    $metric = Get-PropertyValue $metrics $name
    $values = Get-PropertyValue $metric 'values'
    if ($null -eq $values) { $values = $metric }
    $raw = Get-PropertyValue $values $field
    if ($null -eq $raw) {
        $allNames = if ($null -ne $metrics) { @($metrics.PSObject.Properties.Name) -join ', ' } else { '<no metrics object>' }
        $metricJson = if ($null -ne $metric) { $metric | ConvertTo-Json -Depth 4 -Compress } else { '<metric missing>' }
        throw "Missing k6 metric '$name.$field' in summary. Available metrics: $allNames. Metric content: $metricJson. Please share this error and the first 40 lines of k6-summary.json; no zero report will be produced."
    }
    $n = 0.0
    $styles = [System.Globalization.NumberStyles]::Float
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    if (-not [double]::TryParse([string]$raw, $styles, $culture, [ref]$n)) {
        throw "Invalid numeric k6 metric '$name.$field': $raw"
    }
    return $n
}
function Read-Summary([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { throw "File not found: $path" }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

$fullSummaryPath = (Resolve-Path -LiteralPath $SummaryPath).Path
$summary = Read-Summary $fullSummaryPath
$count = Get-MetricNumber $summary 'http_reqs' 'count'
$avg = Get-MetricNumber $summary 'http_req_duration' 'avg'
$p95 = Get-MetricNumber $summary 'http_req_duration' 'p(95)'
$qps = Get-MetricNumber $summary 'http_reqs' 'rate'
# k6 --summary-export commonly stores Rate metrics under values.value,
# while some summary formats use values.rate. Support both explicitly.
$failedMetric = Get-PropertyValue (Get-Metrics $summary) 'http_req_failed'
$failedValues = Get-PropertyValue $failedMetric 'values'
if ($null -eq $failedValues) { $failedValues = $failedMetric }
if ($null -ne (Get-PropertyValue $failedValues 'value')) {
    $errorRate = Get-MetricNumber $summary 'http_req_failed' 'value'
} elseif ($null -ne (Get-PropertyValue $failedValues 'rate')) {
    $errorRate = Get-MetricNumber $summary 'http_req_failed' 'rate'
} else {
    throw "Missing k6 http_req_failed rate: expected 'value' or 'rate'. No report generated."
}
if ($errorRate -lt 0 -or $errorRate -gt 1) {
    throw "Invalid HTTP failure rate: $errorRate (expected 0..1). No report generated."
}
if ($count -le 0 -or $qps -le 0 -or $avg -le 0 -or $p95 -le 0) {
    throw "Invalid empty benchmark summary: requests=$count, avg=$avg, p95=$p95, QPS=$qps. No report generated."
}
$requests = [long][math]::Round($count)
$failed = [long][math]::Round($count * $errorRate)
$avgMs = [math]::Round($avg, 2)
$p95Ms = [math]::Round($p95, 2)
$qpsRounded = [math]::Round($qps, 2)
$errorPct = [math]::Round($errorRate * 100, 3)
$reportPath = Join-Path (Split-Path -Path $fullSummaryPath -Parent) 'report.md'
$lines = @(
    '# PlanBlindBox ranking benchmark',
    '',
    "- Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- Database: $Database",
    "- Stages: 4 x ${StageSeconds}s; peak VUs: $VUs; pause: ${SleepSeconds}s; limit: $Limit",
    "- Requests: $requests",
    "- Average: $avgMs ms",
    "- P95: $p95Ms ms",
    "- QPS: $qpsRounded",
    "- HTTP failure rate: $errorPct% ($failed / $requests)"
)
if (-not [string]::IsNullOrWhiteSpace($BaselineJson)) {
    $base = Read-Summary $BaselineJson
    $bP95 = Get-MetricNumber $base 'http_req_duration' 'p(95)'
    $bQps = Get-MetricNumber $base 'http_reqs' 'rate'
    if ($bP95 -gt 0) { $lines += "- P95 vs baseline: $([math]::Round($p95 / $bP95, 2)) x (lower is better)" }
    if ($bQps -gt 0) { $lines += "- QPS vs baseline: $([math]::Round($qps / $bQps, 2)) x (higher is better)" }
}
$lines | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host "Report saved: $reportPath"
$lines | ForEach-Object { Write-Host $_ }
