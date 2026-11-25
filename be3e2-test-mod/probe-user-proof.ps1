param(
    [string]$Server = 'http://127.0.0.1:8091',
    [switch]$GrantCapability,
    [switch]$RevokeAfterTest
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$base = $Server.TrimEnd('/')
$modId = 'com.planblindbox.test.task'
$version = '1.0.0'
$capability = 'host.tasks.create'
$capUrl = "$base/api/v1/me/mods/$modId/versions/$version/capabilities/$capability"
$secure = Read-Host 'Enter your logged-in user JWT (hidden, not MOD_ADMIN_TOKEN)' -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $jwt = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
if ([string]::IsNullOrWhiteSpace($jwt)) { throw 'A user JWT is required' }
$headers = @{ Authorization = "Bearer $jwt" }

if ($GrantCapability) {
    $grant = Invoke-RestMethod -Uri $capUrl -Headers $headers -Method Put `
        -ContentType 'application/json; charset=utf-8' -Body '{"granted":true}'
    Write-Host ("User grant: " + $grant.userGranted)
}
$status = Invoke-RestMethod -Uri $capUrl -Headers $headers -Method Get
Write-Host ("adminApproved=" + $status.adminApproved + "; userGranted=" + $status.userGranted + "; packageEnabled=" + $status.packageEnabled + "; effective=" + $status.effective)
if ($status.effective -ne $true) { throw 'Authorization is not effective. Check admin approval and user grant.' }
$issued = Invoke-RestMethod -Uri "$capUrl/proof" -Headers $headers -Method Post -ContentType 'application/json' -Body '{}'
if ([string]::IsNullOrWhiteSpace($issued.token)) { throw 'No JWS token was returned' }
Write-Host ("JWS issued, kid=" + $issued.keyId)
$verifyUrl = "$base/api/v1/me/mod-capability-proofs/verify"
$verifyBody = @{ token=$issued.token; modId=$modId; version=$version; capability=$capability } | ConvertTo-Json -Compress
$verified = Invoke-RestMethod -Uri $verifyUrl -Headers $headers -Method Post -ContentType 'application/json' -Body $verifyBody
if ($verified.active -ne $true) { throw 'Online proof verification did not return active=true' }
Write-Host 'Online proof verified: active=true'
if ($RevokeAfterTest) {
    $revoke = Invoke-RestMethod -Uri $capUrl -Headers $headers -Method Delete
    if ($revoke.userGranted -ne $false) { throw 'Revocation was not confirmed' }
    try {
        $unexpected = Invoke-RestMethod -Uri $verifyUrl -Headers $headers -Method Post `
            -ContentType 'application/json' -Body $verifyBody -ErrorAction Stop
        throw 'SECURITY FAILURE: Revoked proof was still accepted!'
    } catch {
        $httpStatus = if ($null -ne $_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        if ($httpStatus -ne 403) { throw }
        Write-Host 'Revocation check passed: old proof rejected with HTTP 403.'
    }
}
Write-Host 'Do not share the JWT or JWS token.'
