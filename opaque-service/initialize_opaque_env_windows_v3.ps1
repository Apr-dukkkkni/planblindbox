$ErrorActionPreference = 'Stop'

# Run from PlanBlindBox\opaque-service.
if (-not (Test-Path -LiteralPath '.\package.json')) {
    throw 'Run this script from the opaque-service directory.'
}
if (-not (Test-Path -LiteralPath '.\node_modules\@serenity-kit\opaque')) {
    throw 'OPAQUE dependency is missing. Run npm install first.'
}

$nodeCommand = Get-Command node -ErrorAction Stop
$nodePath = $nodeCommand.Source
if ([string]::IsNullOrWhiteSpace($nodePath)) {
    throw 'Could not resolve node.exe.'
}

$validatorFile = Join-Path $PWD '.pbb_validate_opaque_setup.mjs'
$generatorFile = Join-Path $PWD '.pbb_generate_opaque_setup.mjs'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$validatorJs = @'
import * as opaque from "@serenity-kit/opaque";
await opaque.ready;
opaque.server.getPublicKey(process.env.OPAQUE_SERVER_SETUP);
process.stdout.write("VALID");
'@

$generatorJs = @'
import * as opaque from "@serenity-kit/opaque";
await opaque.ready;
const setup = opaque.server.createSetup();
opaque.server.getPublicKey(setup);
process.stdout.write(setup);
'@

[System.IO.File]::WriteAllText($validatorFile, $validatorJs, $utf8NoBom)
[System.IO.File]::WriteAllText($generatorFile, $generatorJs, $utf8NoBom)

function Invoke-NodeWithTimeout([string]$ScriptPath, [int]$TimeoutSeconds = 15) {
    $id = [Guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $PWD (".pbb_node_" + $id + ".out")
    $stderrPath = Join-Path $PWD (".pbb_node_" + $id + ".err")
    $process = $null

    try {
        $argument = '"' + $ScriptPath + '"'
        $process = Start-Process -FilePath $nodePath `
            -ArgumentList $argument `
            -WorkingDirectory $PWD `
            -PassThru -NoNewWindow `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch {}
            try { $process.WaitForExit() } catch {}
            throw "Node validation timed out after $TimeoutSeconds seconds."
        }

        $process.Refresh()
        $stdout = if (Test-Path $stdoutPath) {
            [System.IO.File]::ReadAllText($stdoutPath).Trim()
        } else { '' }
        $stderr = if (Test-Path $stderrPath) {
            [System.IO.File]::ReadAllText($stderrPath).Trim()
        } else { '' }

        return [PSCustomObject]@{
            ExitCode = $process.ExitCode
            Stdout = $stdout
            Stderr = $stderr
        }
    }
    finally {
        foreach ($path in @($stdoutPath, $stderrPath)) {
            if (Test-Path $path) { Remove-Item -LiteralPath $path -Force }
        }
    }
}

function Test-OpaqueSetup([string]$Candidate) {
    if ([string]::IsNullOrWhiteSpace($Candidate)) { return $false }

    $previous = $env:OPAQUE_SERVER_SETUP
    try {
        $env:OPAQUE_SERVER_SETUP = $Candidate
        $result = Invoke-NodeWithTimeout $validatorFile 15
        return ($result.ExitCode -eq 0 -and $result.Stdout -eq 'VALID')
    }
    catch {
        Write-Host ("Setup validation did not pass: " + $_.Exception.Message)
        return $false
    }
    finally {
        $env:OPAQUE_SERVER_SETUP = $previous
    }
}

try {
    Write-Host '[1/4] Checking saved OPAQUE_SERVER_SETUP values...'

    $candidateValues = @(
        $env:OPAQUE_SERVER_SETUP,
        [Environment]::GetEnvironmentVariable('OPAQUE_SERVER_SETUP', 'User'),
        [Environment]::GetEnvironmentVariable('OPAQUE_SERVER_SETUP', 'Machine')
    )

    $validSetup = $null
    foreach ($candidate in $candidateValues) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and
            (Test-OpaqueSetup $candidate)) {
            $validSetup = $candidate
            break
        }
    }

    if ($null -eq $validSetup) {
        Write-Warning 'No valid OPAQUE_SERVER_SETUP was found in Process, User, or Machine environment.'
        Write-Warning 'Generating a new setup changes this OPAQUE server identity. Previously registered OPAQUE accounts using another setup will no longer authenticate.'
        $confirmation = Read-Host 'Only if this is a fresh OPAQUE test server with no registered OPAQUE users, type GENERATE'
        if ($confirmation -cne 'GENERATE') {
            throw 'Cancelled. Locate the original OPAQUE_SERVER_SETUP; do not generate a replacement.'
        }

        Write-Host '[2/4] Generating and validating a persistent server setup...'
        $generated = Invoke-NodeWithTimeout $generatorFile 20
        if ($generated.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($generated.Stdout)) {
            if ($generated.Stderr) { Write-Host $generated.Stderr }
            throw 'Node could not generate OPAQUE_SERVER_SETUP. Nothing was saved.'
        }
        $validSetup = $generated.Stdout.Trim()
        if (-not (Test-OpaqueSetup $validSetup)) {
            throw 'The generated OPAQUE_SERVER_SETUP failed validation. Nothing was saved.'
        }
    }
    else {
        Write-Host '[2/4] Reusing an existing valid OPAQUE_SERVER_SETUP.'
    }

    [Environment]::SetEnvironmentVariable('OPAQUE_SERVER_SETUP', $validSetup, 'User')
    $env:OPAQUE_SERVER_SETUP = $validSetup

    Write-Host '[3/4] Checking OPAQUE_INTERNAL_SECRET...'
    $placeholderValues = @(
        '你之前配置的内部通信密钥',
        'replace-with-at-least-32-random-bytes'
    )

    $secretCandidates = @(
        $env:OPAQUE_INTERNAL_SECRET,
        [Environment]::GetEnvironmentVariable('OPAQUE_INTERNAL_SECRET', 'User'),
        [Environment]::GetEnvironmentVariable('OPAQUE_INTERNAL_SECRET', 'Machine')
    )

    $validSecret = $null
    foreach ($candidate in $secretCandidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and
            $placeholderValues -notcontains $candidate.Trim() -and
            [System.Text.Encoding]::UTF8.GetByteCount($candidate) -ge 32) {
            $validSecret = $candidate
            break
        }
    }

    if ($null -eq $validSecret) {
        $randomBytes = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($randomBytes) } finally { $rng.Dispose() }
        $validSecret = [Convert]::ToBase64String($randomBytes)
    }

    [Environment]::SetEnvironmentVariable('OPAQUE_INTERNAL_SECRET', $validSecret, 'User')
    $env:OPAQUE_INTERNAL_SECRET = $validSecret

    Write-Host '[4/4] Final checks...'
    if (-not (Test-OpaqueSetup $env:OPAQUE_SERVER_SETUP)) {
        throw 'Final OPAQUE_SERVER_SETUP validation failed.'
    }
    if ([System.Text.Encoding]::UTF8.GetByteCount($env:OPAQUE_INTERNAL_SECRET) -lt 32) {
        throw 'OPAQUE_INTERNAL_SECRET is shorter than 32 bytes.'
    }

    Write-Host ''
    Write-Host 'SUCCESS: OPAQUE environment is ready.'
    Write-Host 'OPAQUE_SERVER_SETUP is valid and saved in Windows User environment (value hidden).'
    Write-Host 'OPAQUE_INTERNAL_SECRET is set to at least 32 random bytes and saved (value hidden).'
    Write-Host 'Both values are active in this PowerShell window.'
    Write-Host 'Next command: npm start'
}
finally {
    foreach ($path in @($validatorFile, $generatorFile)) {
        if (Test-Path $path) { Remove-Item -LiteralPath $path -Force }
    }
}
