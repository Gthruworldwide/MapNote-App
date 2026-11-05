# ADB Installation Guide for MapNote APK

## Prerequisites
- Windows 10/11 machine
- USB cable
- Android phone with Developer Options enabled

## Method 1: Install via Microsoft Store (Easiest)
1. Open Microsoft Store
2. Search for "Windows ADB"
3. Click "Get" or "Install"
4. Restart your terminal/command prompt

## Method 2: Manual Installation
1. **Enable Developer Mode:**
   - Settings → Privacy & security → For developers → Developer mode

2. **Enable USB Debugging:**
   - Settings → About phone → Tap "Build number" 7 times → Developer options
   - Settings → Developer options → USB debugging → Enable

3. **Install Windows Subsystem for Android (optional but recommended):**
   - Optional feature → Add "Windows Subsystem for Android"
   - Or install via: `winget install --id=ADB.WindowsADB`

## Method 3: Manual Download
1. Download ADB from: https://developer.android.com/platform-tools/adb
2. Extract the ZIP file
3. Add `platform-tools` to your PATH:
   - Right-click This PC → Properties → Advanced system settings → Environment Variables
   - Under System variables, select PATH → Edit → New
   - Add: `C:\Users\%USERNAME%\AppData\Local\Android\Sdk\platform-tools`
4. Restart your terminal/command prompt

## Install MapNote APK
Once ADB is installed:

```bash
adb install -r "D:\RouteNote App\build\app\outputs\flutter-apk\app-release.apk"
```

## Verify Installation
```bash
adb devices
adb shell pm list packages -d mapnote  # Check if MapNote is installed
```

## Troubleshooting
- **"device not authorized"** → Accept the USB debugging prompt on your phone
- **"more than one device/emulator"** → Disconnect other devices, select the correct one
- **Installation blocked** → Enable "Unknown sources" in phone settings → Security → Allow installation from this source

## APK Details
- **Path:** `D:\RouteNote App\build\app\outputs\flutter-apk\app-release.apk`
- **Size:** 70.5 MB
- **Features:** StationService + Drive sync + Hive fallback + Unified Place model + Full localization

## Verification Status (Already Complete)
- ✅ `flutter analyze lib` - 0 new errors
- ✅ `flutter test` - 1021 passed
- ✅ Release APK built successfully
- ✅ All agent changes verified, no regressions