# Cold-launch auth regression check for MapNote.
#
# Implements the measurement method documented in AGENT_SKILLS.md 2.1:
#   * Count `CredentialManager: starting executeGetCredential` -- that is the
#     real loop signature. `CredentialChooserActivity` lines are NOT a valid
#     signal (one invocation emits >100 lines of SurfaceFlinger chatter).
#   * Detect focus theft by polling the resumed activity DURING the launch
#     window: on a multi-account device the chooser takes `topResumedActivity`
#     for ~2s before MapNote regains the foreground.
#
# NOTE: logcat must be read with -v threadtime (or raw/long). The default
# `brief` format renders the tag as `I/CredentialManager( 2522):` which does
# NOT contain the "CredentialManager: starting ..." substring the counter
# looks for -- a `brief` run silently reports zero for every launch.
#
# Usage:
#   powershell -File tool/device_cold_launch_auth_audit.ps1 -Launches 4
#   powershell -File tool/device_cold_launch_auth_audit.ps1 -Serial <adb-serial>
#
# The device must have a persisted Google session (is_logged_in + auth_user),
# otherwise there is nothing to restore and the check is meaningless.

param(
  [int]$Launches = 4,
  [int]$SettleSeconds = 20,
  [string]$Label = "run",
  [string]$Serial = "",
  [string]$AdbPath = "",
  [string]$Package = "com.routenote.routenote"
)

$ErrorActionPreference = "Continue"

if ([string]::IsNullOrWhiteSpace($AdbPath)) {
  $AdbPath = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
}
if ([string]::IsNullOrWhiteSpace($Serial)) {
  # Fall back to the single attached device.
  $devices = @(& $AdbPath devices | Select-Object -Skip 1 | Where-Object { $_ -match "device$" })
  if ($devices.Count -eq 0) {
    Write-Error "no adb device found; pass -Serial <serial>"
    exit 1
  }
  $Serial = ($devices[0] -split "\s+")[0]
}

$adb = $AdbPath
$serial = $Serial
$pkg = $Package
$activity = "$pkg/.MainActivity"

function Invoke-Adb {
  param([string[]]$Arguments)
  & $adb -s $serial @Arguments 2>&1
}

Write-Output "==============================================================="
Write-Output " COLD LAUNCH AUTH REGRESSION -- $Label"
Write-Output " device : $serial"
Write-Output " launches: $Launches (settle ${SettleSeconds}s each)"
Write-Output "==============================================================="

$rows = @()

for ($i = 1; $i -le $Launches; $i++) {
  Invoke-Adb @("logcat", "-c") | Out-Null
  Invoke-Adb @("shell", "am", "force-stop", $pkg) | Out-Null
  Start-Sleep -Seconds 2

  Invoke-Adb @("shell", "am", "start", "-n", $activity) | Out-Null

  # Poll the resumed activity for the whole launch window so a chooser that
  # grabs the foreground for ~2s is actually observed.
  $seen = [System.Collections.Generic.HashSet[string]]::new()
  $deadline = (Get-Date).AddSeconds($SettleSeconds)
  while ((Get-Date) -lt $deadline) {
    $line = (Invoke-Adb @("shell", "dumpsys", "activity", "activities") |
        Select-String -Pattern "topResumedActivity" |
        Select-Object -First 1)
    if ($line) {
      $m = [regex]::Match($line.ToString(), "topResumedActivity=\S+ \S+ (\S+)")
      $who = if ($m.Success) { $m.Groups[1].Value } else { $line.ToString().Trim() }
      [void]$seen.Add($who)
    }
    Start-Sleep -Milliseconds 700
  }

  $log = Invoke-Adb @("logcat", "-d", "-v", "threadtime")

  # The authoritative counter.
  $execGetCred = @($log | Select-String -SimpleMatch "CredentialManager: starting executeGetCredential").Count
  # The moment Play Services decides the chooser must be shown.
  $uiNeeded = @($log | Select-String -SimpleMatch "ui invocation is needed").Count
  # Supporting (noisy) signals -- reported, never used to fail the run.
  $chooser = @($log | Select-String -SimpleMatch "CredentialChooserActivity").Count
  $assisted = @($log | Select-String -SimpleMatch "AssistedSignInActivity").Count

  $stolen = @($seen | Where-Object { $_ -notmatch "routenote" })
  $focusLost = $stolen.Count -gt 0

  $rows += [pscustomobject]@{
    Launch             = $i
    ExecGetCredential  = $execGetCred
    UiInvocationNeeded = $uiNeeded
    ChooserLines       = $chooser
    FocusLost          = $focusLost
    StolenBy           = ($stolen -join ",")
  }

  Write-Output ""
  Write-Output "--- launch $i/$Launches ---"
  Write-Output "  executeGetCredential : $execGetCred   <-- authoritative"
  Write-Output "  ui invocation needed : $uiNeeded      <-- chooser shown?"
  Write-Output "  chooser/assisted     : $chooser / $assisted  (noisy, informational)"
  Write-Output "  foreground seen      : $(($seen | Sort-Object) -join ' | ')"
  Write-Output "  focus stolen by      : $(if ($focusLost) { $stolen -join ',' } else { '(none)' })"
}

Write-Output ""
Write-Output "==================== SUMMARY ($Label) ===================="
$rows | Format-Table -AutoSize | Out-String | Write-Output

$total = ($rows | Measure-Object -Property ExecGetCredential -Sum).Sum
$maxOne = ($rows | Measure-Object -Property ExecGetCredential -Maximum).Maximum
$uiTotal = ($rows | Measure-Object -Property UiInvocationNeeded -Sum).Sum
$focusLostAny = @($rows | Where-Object { $_.FocusLost }).Count

Write-Output "total executeGetCredential across $Launches launches : $total"
Write-Output "max per launch                                      : $maxOne"
Write-Output "total 'ui invocation is needed'                      : $uiTotal"
Write-Output "launches where focus left MapNote                   : $focusLostAny / $Launches"
if ($maxOne -le 1) {
  Write-Output "RESULT: PASS  (<=1 executeGetCredential per launch -- no chooser loop)"
} else {
  Write-Output "RESULT: FAIL  (>1 executeGetCredential per launch -- chooser LOOP)"
}
if ($uiTotal -eq 0) {
  Write-Output "        AND the Credential Manager chooser was never shown (0 x 'ui invocation is needed')"
} else {
  Write-Output "        BUT the Credential Manager chooser was raised $uiTotal time(s) -- focus theft possible"
}
Write-Output "==========================================================="
