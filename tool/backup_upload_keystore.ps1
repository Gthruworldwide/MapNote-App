<#
.SYNOPSIS
    Creates an encrypted, offline backup of the Google Play upload key.

.DESCRIPTION
    Bundles `android/app/upload-keystore.jks` and `android/key.properties`
    into a single AES-256 encrypted 7-Zip archive (header encryption on, so
    the file names are hidden too) and writes it to a destination you choose.

    Why an archive and not a plain copy: losing the upload key means the app
    can never be updated on Google Play again under this signing identity, so
    the copy has to survive a disk failure *and* must not sit unprotected in a
    sync folder. The archive is encrypted with a passphrase you supply (or one
    this script generates), and the passphrase is stored somewhere else -
    a password manager, a printed sheet in a safe, or a separate USB stick.

    Safety rules the script enforces:
      * the destination must be OUTSIDE the git working tree, so the key can
        never end up in a commit;
      * the archive is verified with `7z t` right after it is written;
      * the staged plaintext copies are deleted in a `finally` block.

.EXAMPLE
    # interactive: you type the passphrase twice
    powershell -ExecutionPolicy Bypass -File tool\backup_upload_keystore.ps1 -DestinationDirectory D:\SecureBackup

.EXAMPLE
    # non-interactive: pass the passphrase and let a random one be generated
    powershell -ExecutionPolicy Bypass -File tool\backup_upload_keystore.ps1 `
        -DestinationDirectory E:\keys -Password 'correct horse battery staple'
#>
[CmdletBinding()]
param(
    # Where the encrypted archive is written. Must be outside the repo.
    [Parameter(Mandatory = $true)]
    [string]$DestinationDirectory,

    # Archive passphrase. Omit to have a strong one generated and printed once.
    [string]$Password,

    # Also drop the two raw files next to the archive (not recommended).
    [switch]$AlsoCopyPlaintext
)

$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$keystoreSrc = Join-Path $root 'android\app\upload-keystore.jks'
$propsSrc = Join-Path $root 'android\key.properties'
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'

function Fail([string]$message) {
    Write-Host ("  FAIL  {0}" -f $message) -ForegroundColor Red
    exit 1
}

Write-Host '=== 1. source files ==='
foreach ($p in @($keystoreSrc, $propsSrc, $sevenZip)) {
    if (-not (Test-Path $p)) { Fail ("missing  {0}" -f $p) }
    Write-Host ("  OK    {0} ({1} bytes)" -f $p.Replace("$root\", ''), (Get-Item $p).Length)
}

Write-Host ''
Write-Host '=== 2. destination ==='
$dest = [System.IO.Path]::GetFullPath($DestinationDirectory)
$repoRoot = [System.IO.Path]::GetFullPath($root)
if ($dest.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    Fail ("the destination is inside the git working tree ({0}) - pick a folder outside the repo" -f $dest)
}
if (-not (Test-Path $dest)) {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Write-Host ("  created {0}" -f $dest)
}
$dest = (Resolve-Path $dest).Path
Write-Host ("  using   {0}" -f $dest)

foreach ($cloud in @('OneDrive', 'Dropbox', 'Google Drive', 'iCloud', 'GoogleDrive')) {
    if ($dest -match [regex]::Escape($cloud)) {
        Write-Host ("  NOTE   the destination looks cloud-synced ({0})." -f $cloud) -ForegroundColor Yellow
        Write-Host '         The archive is encrypted, so the file itself is safe there - but keep the'
        Write-Host '         passphrase in a *different* place, never next to the archive.'
    }
}

Write-Host ''
Write-Host '=== 3. passphrase ==='
$generated = $false
if ([string]::IsNullOrWhiteSpace($Password)) {
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $Password = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $generated = $true
}
if ($Password.Length -lt 12) { Fail 'the passphrase must be at least 12 characters' }
Write-Host ("  length {0}" -f $Password.Length)
if ($generated) {
    Write-Host '  NOTE   a passphrase was generated. It is printed once, below:' -ForegroundColor Yellow
    Write-Host ("        {0}" -f $Password) -ForegroundColor Yellow
    Write-Host '         Copy it into your password manager NOW, then rerun with -Password to overwrite this archive.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '=== 4. staging ==='
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("routenote-keystage-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$archive = Join-Path $dest ("routenote-upload-key-{0}.7z" -f $stamp)
try {
    Copy-Item $keystoreSrc (Join-Path $stage 'upload-keystore.jks') -Force
    Copy-Item $propsSrc (Join-Path $stage 'key.properties') -Force
    Write-Host ("  staged 2 files in {0}" -f $stage)

    # The public fingerprint goes *inside* the archive as a restore crib.
    $keytool = 'C:\Users\nader\.jdks\temurin-17\bin\keytool.exe'
    $env:KS_STORE_PASS = (Get-Content $propsSrc | Where-Object { $_ -match '^\s*storePassword\s*=' }) -replace '^\s*storePassword\s*=\s*', ''
    $info = & $keytool -list -v -keystore (Join-Path $stage 'upload-keystore.jks') -storepass:env KS_STORE_PASS 2>&1 | Out-String
    $sha256 = (($info -split "`r?`n") | Where-Object { $_ -match 'SHA256:' } | Select-Object -First 1) -replace '.*SHA256:\s*', ''
    $sha1 = (($info -split "`r?`n") | Where-Object { $_ -match 'SHA1:' } | Select-Object -First 1) -replace '.*SHA1:\s*', ''
    $valid = (($info -split "`r?`n") | Where-Object { $_ -match 'Valid from:' } | Select-Object -First 1) -replace '^\s+', ''
    @(
        'RouteNote - Google Play upload key backup'
        "created        : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "alias          : $((Get-Content $propsSrc | Where-Object { $_ -match '^\s*keyAlias\s*=' }) -replace '^\s*keyAlias\s*=\s*', '')"
        "validity       : $($valid.Trim())"
        "SHA-256        : $($sha256.Trim())"
        "SHA-1          : $($sha1.Trim())"
        ''
        'Files'
        '  upload-keystore.jks   the RSA-2048 upload key (keep for the life of the app)'
        '  key.properties       storePassword / keyPassword / keyAlias / storeFile'
        ''
        'Restore'
        '  1. Extract this archive (7-Zip, the passphrase you chose).'
        '  2. Copy upload-keystore.jks -> android/app/upload-keystore.jks'
        '  3. Copy key.properties    -> android/key.properties'
        '  4. Check android/app/build.gradle.kts still points storeFile at upload-keystore.jks.'
        '  5. flutter build appbundle --release'
        '  6. tool\verify_upload_keystore.ps1 must pass before you ship.'
        ''
        'The storeFile value inside key.properties is relative to android/app/ on this machine.'
    ) | Set-Content (Join-Path $stage 'RESTORE-INSTRUCTIONS.txt') -Encoding UTF8
    Remove-Item Env:KS_STORE_PASS -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host '=== 5. encrypting ==='
    # The 7z format encrypts with AES-256 (7zAES, SHA-256 key derivation) by
    # default; -mhe=on additionally encrypts the header, so the file names are
    # hidden as well. The cipher is asserted in step 6, not assumed.
    $out = & $sevenZip a -t7z -mhe=on ("-p" + $Password) $archive (Join-Path $stage '*') 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Write-Host $out; Fail '7-Zip could not write the archive' }
    Write-Host ("  wrote  {0} ({1} bytes)" -f $archive, (Get-Item $archive).Length)

    Write-Host ''
    Write-Host '=== 6. verifying the archive ==='
    $test = & $sevenZip t ("-p" + $Password) $archive 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Write-Host $test; Fail 'the archive does not open with that passphrase' }
    if ($test -notmatch 'Everything is Ok') { Write-Host $test; Fail 'the archive test did not report "Everything is Ok"' }
    Write-Host '  OK    the archive opens with the passphrase and every entry tests clean'

    $listing = & $sevenZip l -slt ("-p" + $Password) $archive 2>&1 | Out-String
    foreach ($needle in @('upload-keystore.jks', 'key.properties', 'RESTORE-INSTRUCTIONS.txt')) {
        if ($listing -match [regex]::Escape($needle)) { Write-Host ("  OK    contains {0}" -f $needle) }
        else { Fail ("the archive does not contain {0}" -f $needle) }
    }
    if ($listing -match 'Encrypted = \+') { Write-Host '  OK    the entries are encrypted' }
    else { Fail 'the archive entries are not encrypted' }
    if ($listing -match '7zAES:19') { Write-Host '  OK    cipher is AES-256 (7zAES, SHA-256 key derivation)' }
    else { Fail ("unexpected cipher in the archive (expected 7zAES:19 = AES-256): {0}" -f (($listing -split "`r?`n") | Where-Object { $_ -match 'Method' }) -join ' | ') }

    Write-Host ''
    Write-Host '=== 7. archive checksum ==='
    $archiveHash = (Get-FileHash $archive -Algorithm SHA256).Hash
    Write-Host ("  SHA-256 {0}" -f $archiveHash)
    Write-Host ("  size    {0} bytes" -f (Get-Item $archive).Length)

    if ($AlsoCopyPlaintext) {
        Copy-Item $keystoreSrc $dest -Force
        Copy-Item $propsSrc $dest -Force
        Write-Host '  NOTE   raw copies were also placed in the destination (as requested).' -ForegroundColor Yellow
    }
}
finally {
    Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
    Remove-Item Env:KS_STORE_PASS -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host 'staging copies removed'
}

Write-Host ''
Write-Host 'RESULT: the encrypted backup is ready.' -ForegroundColor Green
Write-Host "  archive : $archive"
if ($generated) {
    Write-Host ("  passphrase (shown once): {0}" -f $Password) -ForegroundColor Yellow
}
Write-Host '  Store the passphrase in a different place than the archive, then verify the'
Write-Host '  backup on another machine with:  7z x <archive> -p<passphrase>'
exit 0
