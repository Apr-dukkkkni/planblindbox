param(
    [string]$Server = 'http://127.0.0.1:8091',
    [switch]$ApproveCapability
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$modId = 'com.planblindbox.test.task'
$version = '1.0.0'
$publisherId = 'com.planblindbox.testpublisher'
$capability = 'host.tasks.create'
$keyDir = Join-Path $env:USERPROFILE '.planblindbox-be3e2-publisher'
$privatePath = Join-Path $keyDir 'publisher-private.pkcs8'
$publicPath = Join-Path $keyDir 'publisher-public.x509'
$tool = Join-Path $PSScriptRoot 'PublisherSigner.java'
$manifestPath = Join-Path $PSScriptRoot 'task-template-v1\manifest.json'

if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Manifest not found: $manifestPath" }
if (-not (Get-Command java -ErrorAction SilentlyContinue)) { throw 'JDK 17+ java command was not found.' }
if ((Test-Path $privatePath) -xor (Test-Path $publicPath)) {
    throw 'Publisher key pair is incomplete. Refusing to silently replace it.'
}
if (-not (Test-Path $privatePath)) {
    & java $tool init $keyDir
    if ($LASTEXITCODE -ne 0) { throw 'JDK Publisher key generation failed' }
}

$signatureOutput = @(& java $tool sign $keyDir $manifestPath)
if ($LASTEXITCODE -ne 0) { throw 'Manifest signature failed' }
$values = @{}
foreach ($line in $signatureOutput) {
    if ($line -match '^([A-Za-z0-9]+)=(.*)$') { $values[$matches[1]] = $matches[2] }
}
if ($values['signatureVerified'] -ne 'true') { throw 'Publisher self-verification failed' }
$keyId = $values['keyId']
$signatureBase64 = $values['signatureBase64']
$manifestSha256 = $values['manifestSha256']
$pubB64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($publicPath))
Write-Host ("Local publisher key ID: " + $keyId)
Write-Host ("Local manifest SHA-256: " + $manifestSha256)

$secure = Read-Host 'Enter the local MOD_ADMIN_TOKEN (hidden)' -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $adminToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
if ([string]::IsNullOrWhiteSpace($adminToken)) { throw 'MOD_ADMIN_TOKEN cannot be empty' }
$headers = @{ Authorization = "Bearer $adminToken" }
$base = $Server.TrimEnd('/')

$keyUrl = "$base/api/v1/publishers/$publisherId/keys/$keyId"
$registered = $null
try {
    $registered = Invoke-RestMethod -Uri $keyUrl -Method Get -ErrorAction Stop
} catch {
    $status = if ($null -ne $_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
    if ($status -ne 404) { throw }
}
if ($null -eq $registered) {
    $enrollUrl = "$base/api/v1/admin/publishers/$publisherId/keys"
    $request = @{ publicKeyBase64 = $pubB64 } | ConvertTo-Json -Compress
    $registered = Invoke-RestMethod -Uri $enrollUrl -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $request
    Write-Host 'Publisher public key enrolled.'
} else {
    if ($registered.status -ne 'ACTIVE' -or $registered.publicKeyX509Base64 -ne $pubB64) {
        throw 'Publisher key exists but is revoked or differs from local public key.'
    }
    Write-Host 'Publisher public key already enrolled and ACTIVE.'
}

$publishUrl = "$base/api/v1/admin/mods/publish"
$publishHeaders = @{
    Authorization = "Bearer $adminToken"
    'X-Publisher-Key-Id' = $keyId
    'X-Publisher-Signature' = $signatureBase64
}
try {
    $published = Invoke-RestMethod -Uri $publishUrl -Method Post -Headers $publishHeaders `
       -ContentType 'application/json; charset=utf-8' -Body ([System.IO.File]::ReadAllBytes($manifestPath))
    Write-Host ("Published " + $published.id + " " + $published.version)
} catch {
    $status = if ($null -ne $_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
    if ($status -ne 409) { throw }
    # 409 can mean an existing version. Accept it ONLY when its exact manifest hash
    # and publisher key match this fixture. Do not mask unrelated conflicts.
    $existing = Invoke-WebRequest -UseBasicParsing -Uri "$base/api/v1/mods/$modId/versions/$version/manifest" -Method Get
    if ($existing.Headers['X-Mod-Manifest-SHA256'] -ne $manifestSha256 -or
        $existing.Headers['X-Publisher-Key-Id'] -ne $keyId) {
        throw 'Version conflict: existing manifest or Publisher key differs. No overwrite performed.'
    }
    Write-Host 'Version already published with the same manifest hash and Publisher key.'
}

if ($ApproveCapability) {
    # Re-approving may increment the authorization revision and invalidate old proofs.
    $approveUrl = "$base/api/v1/admin/mods/$modId/versions/$version/capabilities/$capability/approval"
    $approval = Invoke-RestMethod -Uri $approveUrl -Method Put -Headers $headers `
        -ContentType 'application/json; charset=utf-8' `
        -Body '{"approved":true,"reason":"BE-3E-2 local integration test"}'
    Write-Host ("Admin approval: " + $approval.adminApproved)
    Write-Host ("Package enabled: " + $approval.packageEnabled)
    Write-Host 'User grant remains separate: sign in as a real user before issuing proof.'
} else {
    Write-Host 'Not yet approved. Re-run with -ApproveCapability after review.'
}
Write-Host 'Do not share publisher-private.pkcs8 or MOD_ADMIN_TOKEN.'
