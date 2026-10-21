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
- **Last Verified Commit:** `2b23e9b` (last **code**-verified commit; clean tree — the only later commit is this docs-only `.opencode/` addition, which changes no Dart source).
- **Completed Task:** Cold-launch auth optimization — **COMPLETE**, device-verified 2026-10-21 on Honor 90 / Android 15. The launch-time restore is suppressed while `last_synced` is younger than `AppConfig.sessionTrustWindow`; the restore is single-flight across `AuthNotifier` rebuilds, and only a user-initiated Drive action may re-establish the session.
- **Next Open Work:** AutoMotion Phase 3 — per-mode activity breakdown + 7/30-day aggregates.
- **Device Audit Skill:** `.opencode/skills/mapnote-device-audit/SKILL.md` — cold-launch auth regression checks + Hive privacy inspection on `AYDL024206002031`.
- **Documentation:** `AGENT_SKILLS.md` §2.1.
