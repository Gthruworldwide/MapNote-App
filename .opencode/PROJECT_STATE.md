# MapNote-App — Project Memory & Architecture Context

## 1. App Core Identity
- **App Name:** MapNote-App
- **Package Name:** `com.routenote.routenote`
- **Framework:** Flutter (Offline-First / Local-Only Architecture)
- **Primary Storage:** Hive
  - `placesBox`: Stores saved locations (`Place.toMap()`).
  - `settingsBox`: Stores app configuration and `health_events` key (driving/motion logs).
- **Privacy Standard:** ZERO geographical coordinates (`latitude`/`longitude`) are persisted in health or motion logs.

## 2. Hardware & Environment
- **Target Device:** Honor 90 (`AYDL024206002031`), Android 15 (SDK 35).
- **ADB Executable:** `C:\Users\nader\AppData\Local\Android\Sdk\platform-tools\adb.exe`
- **GCP Project:** `routenote-app`
- **Service Account Role:** `roles/firebase.admin` (Required for Firebase App Distribution uploads).

## 3. Pipeline & CI/CD Status
- **Workflow:** `.github/workflows/firebase-distribution.yml`
- **Optimization:** Split into independent `build` and `distribute` jobs.
- **Performance:** Distribution retry time reduced from 10m to ~43s.
- **Latest Distribution:** Release 1.0.5 (22), group `testers`.

## 4. Current Workstream & Active Checkpoint
- **Active Checkpoint (code):** `e9698a5` — AutoMotion Phase 4 **COMPLETE**. Custom date range selector (`showDateRangePicker`) on `AutoMotionScreen` aggregates card; `AutoMotionExportBottomSheet` (CSV/JSON offline export) accessible from AutoMotion & Settings; automated privacy assertion (zero lat/lng in payloads); L10n parity (9 new keys in both locales). Plus offline tile caching & 3D pins LOD (`OfflineTileCacheStrategy`, `BuiltInMapCachingProvider` 100 MB, `RepaintBoundary`, LOD zoom>=12) and stationary idle detector integration (smart battery saver toggle). Verification gate: 836 tests passing, clean analyzer.
- **Latest Commit:** `e9698a5` — `feat(automotion): integrate stationary idle detector for battery saving`.
- **Completed Task:** AutoMotion Phase 4 — **COMPLETE**. Custom date range + offline export; zero-coordinates guarantee; L10n parity; offline tile caching & 3D pins LOD; stationary idle detector (smart battery saver).
- **Previously completed:** AutoMotion Phase 3 — **COMPLETE** (`0c5fc38`); UI/UX overhaul — **COMPLETE** (`9582f8e`); Cold-launch auth optimization — **COMPLETE** (`2b23e9b`), device-verified 2026-10-21.
- **Next Open Work:** TBD — no open workstream. (Optional: device validation on `AYDL024206002031`; device currently detached.)
- **Device Audit Skill:** `.opencode/skills/mapnote-device-audit/SKILL.md`.
- **Documentation:** `AGENT_SKILLS.md` §2.1, §4, §5, §6.
