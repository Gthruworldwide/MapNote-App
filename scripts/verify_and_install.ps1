# MapNote Automated Verification & Local ADB Installation Script
# Location: scripts/verify_and_install.ps1
# Strict Verification Sequence: analyze → test → build → install → launch

$ErrorActionPreference = "Stop"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "🚀 Starting MapNote Local Verification & Install " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# Step 1: Static Code Analysis
Write-Host "`n[1/5] Running Static Analysis (flutter analyze)..." -ForegroundColor Yellow
flutter analyze
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Static Analysis failed! Aborting build." -ForegroundColor Red
    exit 1
}
Write-Host "✅ Static Analysis passed with 0 issues." -ForegroundColor Green

# Step 2: Unit & Widget Testing
Write-Host "`n[2/5] Running Unit & Widget Tests (flutter test)..." -ForegroundColor Yellow
flutter test
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Tests failed! Aborting build." -ForegroundColor Red
    exit 1
}
Write-Host "✅ All tests passed successfully." -ForegroundColor Green

# Step 3: Release APK Build
Write-Host "`n[3/5] Building Release APK (flutter build apk --release)..." -ForegroundColor Yellow
flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ APK Build failed!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Release APK built successfully." -ForegroundColor Green

# Step 4: Check Connected ADB Device
Write-Host "`n[4/5] Checking Connected ADB Device..." -ForegroundColor Yellow
$adbDevices = adb devices | Select-String -Pattern "\tdevice$"
if (-not $adbDevices) {
    Write-Host "❌ No active ADB device found! Please connect your phone via USB with Debugging ON." -ForegroundColor Red
    exit 1
}
Write-Host "✅ Connected Device Found." -ForegroundColor Green

# Step 5: Install and Launch App
Write-Host "`n[5/5] Installing APK and Launching App on Device..." -ForegroundColor Yellow
$apkPath = "build\app\outputs\flutter-apk\app-release.apk"
adb install -r $apkPath
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ ADB Installation failed!" -ForegroundColor Red
    exit 1
}

# Launch MainActivity automatically
adb shell am start -n com.routenote.routenote/.MainActivity
Write-Host "✅ App installed and launched successfully on your device!" -ForegroundColor Green

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "🎉 ALL CHECKS PASSED & APP OPERATIONAL LOCALLY!   " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan