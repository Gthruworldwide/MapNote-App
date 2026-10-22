<#
.SYNOPSIS
    Integrity check for the Google Play upload keystore.

.DESCRIPTION
    Proves, *before* an offline backup is taken, that the upload key material
    is intact and usable:

      1. `key.properties` parses and names an existing keystore.
      2. The store password opens the keystore.
      3. The alias in `key.properties` is the key entry in that keystore.
      4. The key password unlocks the key entry.
      5. The key can actually sign (a throwaway jar is signed and verified).
      6. The certificate matches the one that signed the release AAB, so the
         backup really is the key Play Console knows.

    Passwords are never printed and never passed on the command line: they
    travel through the environment (`-storepass:env` / `-keypass:env`).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool\verify_upload_keystore.ps1
#>
[CmdletBinding()]
param(
    # Optional: an already-built AAB to compare the signing certificate with.
    [string]$AabPath = 'build\app\outputs\bundle\release\app-release.aab'
)

# Native tools write benign warnings to stderr; keep them out of the
# terminating-error path and judge success by $LASTEXITCODE instead.
$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$propsFile = Join-Path $root 'android\key.properties'
$keystoreDir = Join-Path $root 'android\app'
$jdkBin = 'C:\Users\nader\.jdks\temurin-17\bin'
$keytool = Join-Path $jdkBin 'keytool.exe'
$jarsigner = Join-Path $jdkBin 'jarsigner.exe'
$jarTool = Join-Path $jdkBin 'jar.exe'

$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$message) {
    $script:failures.Add($message)
    Write-Host ("  FAIL  {0}" -f $message) -ForegroundColor Red
}
function Ok([string]$message) {
    Write-Host ("  OK    {0}" -f $message) -ForegroundColor Green
}

Write-Host '=== 1. files ==='
foreach ($p in @($propsFile, $keytool, $jarsigner, $jarTool)) {
    if (Test-Path $p) { Ok ("exists  {0}" -f $p.Replace("$root\", '')) }
    else { Fail ("missing  {0}" -f $p) }
}
if (-not (Test-Path $propsFile)) { exit 1 }

Write-Host ''
Write-Host '=== 2. key.properties (values redacted) ==='
$cfg = @{}
foreach ($line in Get-Content $propsFile) {
    if ($line -match '^\s*([^#=\s]+)\s*=\s*(.*)$') {
        $cfg[$matches[1]] = $matches[2].Trim()
        Write-Host ("  {0,-14} = <redacted, {1} chars>" -f $matches[1], $matches[2].Trim().Length)
    }
}
foreach ($required in @('storePassword', 'keyPassword', 'keyAlias', 'storeFile')) {
    if (-not $cfg.ContainsKey($required)) { Fail ("key.properties has no '{0}' entry" -f $required) }
}
if ($failures.Count -gt 0) { Write-Host ''; Write-Host 'RESULT: PROBLEM FOUND - fix before backing up.'; exit 1 }

$alias = $cfg['keyAlias']
$storeFile = $cfg['storeFile']
$keystorePath = if ([System.IO.Path]::IsPathRooted($storeFile)) { $storeFile } else { Join-Path $keystoreDir $storeFile }

Write-Host ''
Write-Host '=== 3. keystore contents ==='
$env:KS_STORE_PASS = $cfg['storePassword']
$env:KS_KEY_PASS = $cfg['keyPassword']
try {
    $list = & $keytool -list -v -keystore $keystorePath -storepass:env KS_STORE_PASS 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Fail 'the store password does not open the keystore'
        Write-Host $list
        exit 1
    }
    Ok ("the store password opens '{0}'" -f $storeFile)

    $aliasLine = ($list -split "`r?`n") | Where-Object { $_ -match 'Alias name:' } | Select-Object -First 1
    $entryLine = ($list -split "`r?`n") | Where-Object { $_ -match 'Entry type:' } | Select-Object -First 1
    $shaLine = ($list -split "`r?`n") | Where-Object { $_ -match 'SHA256:' } | Select-Object -First 1
    $sha1Line = ($list -split "`r?`n") | Where-Object { $_ -match 'SHA1:' } | Select-Object -First 1
    $validLine = ($list -split "`r?`n") | Where-Object { $_ -match 'Valid from:' } | Select-Object -First 1

    if ($aliasLine -and $aliasLine -match [regex]::Escape($alias)) { Ok ("the keystore holds the alias '{0}'" -f $alias) }
    else { Fail ("alias mismatch - key.properties wants '{0}', keystore says: {1}" -f $alias, ($aliasLine -replace '^\s+', '')) }

    if ($entryLine -and $entryLine -match 'PrivateKeyEntry') { Ok 'the entry is a PrivateKeyEntry (usable for signing)' }
    else { Fail ("the alias entry is not a private key: {0}" -f ($entryLine -replace '^\s+', '')) }

    if ($shaLine) {
        $fingerprint = ($shaLine -replace '.*SHA256:\s*', '').Trim()
        Ok 'SHA-256 certificate fingerprint (public, record this with the backup):'
        Write-Host ("        {0}" -f $fingerprint)
    }
    else { Fail 'could not read the SHA-256 fingerprint' }

    if ($sha1Line) {
        Write-Host 'SHA-1 certificate fingerprint (this is what Play Console shows):'
        Write-Host ("        {0}" -f ($sha1Line -replace '.*SHA1:\s*', '').Trim())
    }

    if ($validLine) { Write-Host ("        {0}" -f ($validLine -replace '^\s+', '').Trim()) }

    Write-Host ''
    Write-Host '=== 4. key password unlocks the key entry ==='
    $probe = & $keytool -list -keystore $keystorePath -storepass:env KS_STORE_PASS -alias $alias -keypass:env KS_KEY_PASS 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { Ok 'the key password unlocks the key entry' }
    else { Fail 'the key password does not unlock the key entry' }

    Write-Host ''
    Write-Host '=== 5. the key can actually sign ==='
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("routenote-ks-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $jar = Join-Path $tmp 'probe.jar'
        $file = Join-Path $tmp 'probe.txt'
        Set-Content -Path $file -Value 'routenote upload key probe' -Encoding ASCII
        & $jarTool --create --file $jar -C $tmp probe.txt 2>&1 | Out-Null
        if (-not (Test-Path $jar)) { Fail 'could not build the throwaway archive' }
        $sign = & $jarsigner -keystore $keystorePath -storepass:env KS_STORE_PASS -keypass:env KS_KEY_PASS $jar $alias 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $verify = & $jarsigner -verify $jar 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0 -and $verify -match 'jar verified') { Ok 'a throwaway archive was signed and verified with the upload key' }
            else { Fail ("the signed archive did not verify: {0}" -f ($verify -replace '\s+', ' ')) }
        }
        else {
            Fail ("signing failed: {0}" -f ($sign -replace '\s+', ' '))
        }
    }
    finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }

    Write-Host ''
    Write-Host '=== 6. the release AAB is signed with this very key ==='
    $aab = if ([System.IO.Path]::IsPathRooted($AabPath)) { $AabPath } else { Join-Path $root $AabPath }
    if (-not (Test-Path $aab)) {
        Write-Host ("  SKIP  no AAB at '{0}' (build one to cross-check)" -f $AabPath)
    }
    else {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = $null
        try {
            $zip = [System.IO.Compression.ZipFile]::OpenRead($aab)
            $rsa = $zip.Entries | Where-Object { $_.FullName -match '^META-INF/.*\.RSA$' } | Select-Object -First 1
            if (-not $rsa) { Fail 'the AAB carries no META-INF/*.RSA signature block' }
            else {
                $tmpRsa = Join-Path ([System.IO.Path]::GetTempPath()) ("routenote-aab-" + [System.Guid]::NewGuid().ToString('N') + '.RSA')
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($rsa, $tmpRsa, $true)
                $cert = & $keytool -printcert -file $tmpRsa 2>&1 | Out-String
                Remove-Item $tmpRsa -Force -ErrorAction SilentlyContinue
                $aabSha = ($cert -split "`r?`n") | Where-Object { $_ -match 'SHA256:' } | Select-Object -First 1
                $aabFingerprint = if ($aabSha) { ($aabSha -replace '.*SHA256:\s*', '').Trim() } else { '' }
                if ($aabFingerprint -and $fingerprint -and $aabFingerprint -eq $fingerprint) {
                    Ok 'the AAB signature certificate matches the keystore fingerprint'
                }
                else {
                    Fail ("the AAB was signed with a different certificate ({0})" -f $aabFingerprint)
                }
            }
        }
        finally {
            if ($zip) { $zip.Dispose() }
        }
    }
}
finally {
    Remove-Item Env:KS_STORE_PASS -ErrorAction SilentlyContinue
    Remove-Item Env:KS_KEY_PASS -ErrorAction SilentlyContinue
}

Write-Host ''
if ($failures.Count -eq 0) {
    Write-Host 'RESULT: the upload key is intact and usable. Back up the keystore and key.properties off this machine now.' -ForegroundColor Green
    exit 0
}
Write-Host ("RESULT: {0} problem(s) found - do not back this up as-is." -f $failures.Count) -ForegroundColor Red
exit 1
