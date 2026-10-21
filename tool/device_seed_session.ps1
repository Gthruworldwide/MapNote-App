# Puts the device into the "trusted session" state and pushes it back.
#
# Reproducible version of the device-audit seeding step:
#   1. force-stop the app so Hive is not holding the box in memory
#   2. pull `app_flutter/settings.hive` off the device (binary-safe)
#   3. seed `is_logged_in` / `auth_user` / `last_synced` with hive_ce
#   4. push the modified box back, owned by the app uid
#
# After this, a cold launch must produce ZERO `executeGetCredential` calls
# (the launch skips the platform restore), while a `--stale` seed must still
# perform the full restore.
#
# `-OnlyAge` keeps the device's own `auth_user` / `is_logged_in` and ages only
# `last_synced`. Use it on a device that holds a real Google session: without
# it the seed replaces the signed-in identity with a placeholder and the
# device is left showing a fake account. The trust evidence heals on its own
# -- the next successful Drive round-trip re-stamps `last_synced`.
#
# Usage:
#   powershell -File tool/device_seed_session.ps1
#   powershell -File tool/device_seed_session.ps1 -Stale
#   powershell -File tool/device_seed_session.ps1 -Stale -OnlyAge

param(
  [string]$Serial = "",
  [string]$AdbPath = "",
  [string]$Package = "com.routenote.routenote",
  [switch]$Stale,
  [switch]$OnlyAge,
  [string]$WorkDir = ".scratch/seed"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($AdbPath)) {
  $AdbPath = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
}
if ([string]::IsNullOrWhiteSpace($Serial)) {
  $devices = @(& $AdbPath devices | Select-Object -Skip 1 | Where-Object { $_ -match "device$" })
  if ($devices.Count -eq 0) { throw "no adb device found; pass -Serial <serial>" }
  $Serial = ($devices[0] -split "\s+")[0]
}

# 1. Stop the app: Hive caches the open box and would overwrite our edit.
& $AdbPath -s $Serial shell am force-stop $Package | Out-Null
Start-Sleep -Seconds 2

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$box = Join-Path $WorkDir "settings.hive"

# 2. Pull. `cmd /c` is required: PowerShell's `>` mangles binary output
#    (it re-encodes the byte stream and Hive then reports a corrupted box).
cmd /c "`"$AdbPath`" -s $Serial exec-out run-as $Package cat app_flutter/settings.hive > `"$box`""

# 3. Seed.
$seedArgs = @("run", "tool/hive_seed_session.dart", $WorkDir)
if ($Stale) { $seedArgs += "--stale" }
if ($OnlyAge) { $seedArgs += "--only-age" }
& dart @seedArgs
if ($LASTEXITCODE -ne 0) { throw "hive_seed_session.dart failed" }

# 4. Push back. `adb push` lands in /data/local/tmp; `run-as cp` copies it
#    into the app's private dir as the app uid.
cmd /c "`"$AdbPath`" -s $Serial push `"$box`" /data/local/tmp/settings.hive"
& $AdbPath -s $Serial shell "run-as $Package cp /data/local/tmp/settings.hive app_flutter/settings.hive"
& $AdbPath -s $Serial shell "rm -f /data/local/tmp/settings.hive"
# Drop the box's stale lock file so the app opens our copy rather than
# complaining about a box another process had open.
& $AdbPath -s $Serial shell "run-as $Package rm -f app_flutter/settings.lock"

Write-Output "seeded session pushed to $Serial"
