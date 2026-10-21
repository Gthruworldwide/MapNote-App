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
- **Active Checkpoint (code):** `9582f8e` — UI/UX overhaul, responsive font scaling, CompactActionBar, GPS drift filter & settings refresh. Verification gate: 821 tests passing, clean analyzer.
- **Latest Commit:** `9582f8e` — `feat(ui): responsive font scaling, compact action bar, GPS drift filter, settings refresh` (17 files, 622 insertions).
- **Completed Task:** Font scaling (4-preset, `settingsBox`), CompactActionBar long-press menu, GPS drift/indoor noise filter (`maxAccuracyMeters` configurable, real-motion gate), settings refresh (font scale/haptic/density toggles), 3-pillar foundations (`AutoMotionExportService`, `StationaryIdleDetector`, `OfflineTileCacheStrategy`).
- **Previously completed:** AutoMotion Phase 3 — **COMPLETE** (`0c5fc38`); Cold-launch auth optimization — **COMPLETE** (`2b23e9b`), device-verified 2026-10-21.
- **Next Open Work:** TBD — no open workstream. (Optional: device validation of AutoMotion Phase 3 + font scaling on `AYDL024206002031`; device currently detached.)
- **Device Audit Skill:** `.opencode/skills/mapnote-device-audit/SKILL.md`.
- **Documentation:** `AGENT_SKILLS.md` §2.1, §4, §5, §6.
