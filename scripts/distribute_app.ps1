# Uploads a RouteNote release APK to Firebase App Distribution so testers get an
# email invite and install it through the App Tester app (no Play Console needed).
#
# Requires firebase-tools and a logged-in session:
#   npm install -g firebase-tools
#   firebase login
#
# Usage from the project root:
#   .\scripts\distribute_app.ps1
#   .\scripts\distribute_app.ps1 -Groups testers -Notes "1.0.1 (2) - pilot"
#   .\scripts\distribute_app.ps1 -Path build\app\outputs\flutter-apk\app-release.apk

param(
  [string]$Path   = 'build/app/outputs/flutter-apk/app-release.apk',
  [string]$Groups = 'testers',
  [string]$Notes  = ''
)

$ErrorActionPreference = 'Stop'

# Android app id for the routenote-app Firebase project (679774190551).
$appId = '1:679774190551:android:d7bf2f949f60ed62912992'

if (-not (Test-Path $Path)) {
  throw "APK not found at '$Path'. Build it first:  flutter build apk --release"
}

# Locate the Firebase CLI: prefer PATH, then a user-scoped Node install.
$firebase = (Get-Command firebase -ErrorAction SilentlyContinue).Source
if (-not $firebase) {
  $firebase = Get-ChildItem "$env:LOCALAPPDATA\nodejs\node-*\firebase.cmd" -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
}
if (-not $firebase) {
  throw 'Firebase CLI not found. Install it with:  npm install -g firebase-tools'
}

$fbArgs = @('appdistribution:distribute', $Path, '--app', $appId, '--groups', $Groups)
if ($Notes) { $fbArgs += @('--release-notes', $Notes) }

Write-Host "Uploading $Path to group '$Groups'..." -ForegroundColor Cyan
& $firebase @fbArgs

Write-Host 'Distributed. Testers will receive an email invite.' -ForegroundColor Green
