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
- **Active Checkpoint (code):** `0c5fc38` — AutoMotion Phase 3 **COMPLETE**. Per-mode activity breakdown (walk/run/vehicle) on `DailyGpsSummary` with backward-compatible defaults, 7/30-day aggregates in RAM from `auto_motion_box` (`AutoMotionDataSource`), dashboard UI integration, full en/ar localization, and 12 new aggregation tests. Verification gate: 821 tests passing, clean analyzer.
- **Latest Commit:** `0c5fc38` — `feat(automotion): implement phase 3 per-mode breakdown & 7/30-day aggregates` (11 files, 930 insertions).
- **Completed Task:** AutoMotion Phase 3 — **COMPLETE**. Model + aggregates + UI + localization + tests; Hive schemas unchanged (additive keys with defaults); `gps_daily.hive` untouched; zero coordinates in health log; secrets scan clean.
- **Previously completed:** Cold-launch auth optimization — **COMPLETE** (`2b23e9b`), device-verified 2026-10-21 on Honor 90 / Android 15 (`AYDL024206002031`).
- **Next Open Work:** TBD — no open workstream. (Optional: device audit skill end-to-end run; device currently detached.)
- **Device Audit Skill:** `.opencode/skills/mapnote-device-audit/SKILL.md` — cold-launch auth regression checks + Hive privacy inspection on `AYDL024206002031`.
- **Documentation:** `AGENT_SKILLS.md` §2.1, §5.
