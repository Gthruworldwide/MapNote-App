# Session Briefing — MapNote-App (RouteNote)

**Read first:** `AGENTS.md` → `AGENT_SKILLS.md` (canonical pass/fail standard — read before editing AND before finishing any task). Then `.opencode/PROJECT_STATE.md` for project memory.

---

## 1. Git state

- **Repo:** `D:\RouteNote App` · **Branch:** `main`
- **HEAD:** `e9698a5` (`feat(automotion): integrate stationary idle detector for battery saving`)
- **Last commit:** `feat(automotion): integrate stationary idle detector for battery saving`
- **Working tree: CLEAN** — no modified, no untracked files. `.opencode/` is tracked.
- **Code checkpoint:** `e9698a5` — AutoMotion Phase 4 **COMPLETE** (custom date range + offline export + L10n parity + zero-coords assertion) + offline tile caching & 3D pins LOD + stationary idle detector (smart battery saver). Previous checkpoints remain intact.
- **Recent history:** `e9698a5` ← `e363171` (offline tile cache & export) ← `335dda3` (export sheet in settings) ← `f1288ef` (custom date range & export UI) ← `442c187` (state refresh) ← `9582f8e` (UI overhaul)

## 2. Completed in this session

- **AutoMotion Phase 4 — COMPLETE (`e9698a5`).** Custom date range selector (`showDateRangePicker`) on aggregates card; `AutoMotionExportBottomSheet` (CSV/JSON, zero-coords assertion) accessible from AutoMotion & Settings; L10n parity (9 keys); offline tile caching & 3D pins LOD (`OfflineTileCacheStrategy`, `BuiltInMapCachingProvider` 100MB, `RepaintBoundary`, LOD zoom>=12); stationary idle detector integration (smart battery saver toggle, 6 tests). Verification gate: 836 tests, clean analyzer.
- **UI/UX overhaul — COMPLETE** (carried, `9582f8e`).
- **AutoMotion Phase 3 — COMPLETE** (carried, `0c5fc38`).
- **Cold-launch auth optimization — COMPLETE** (carried, `2b23e9b`), device-verified 2026-10-21.

## 3. Pending work — exact next step

No open code workstream. Roadmap §4 (AutoMotion) fully shipped through Phase 3.

**Optional next milestones:**
1. **Physical device validation** of AutoMotion Phase 3 on `AYDL024206002031` (Honor 90, Android 15) — install debug build, record a short drive/walk, confirm per-mode breakdown + 7/30-day aggregates render on the dashboard. Device is currently **detached**; perform ADB recovery first.
2. **End-to-end run of the `mapnote-device-audit` skill** (cold-launch auth regression + Hive privacy inspection) on the device.
3. **Push** the 8 commits ahead of `origin/main` when ready (`git push`).

**Secondary (optional):** run the device audit skill end-to-end. Device currently **detached** — if exercising it, first do ADB recovery on `AYDL024206002031`.

## 4. Key findings / device context — remember these

**Device:** `AYDL024206002031` (Honor 90, Android 15, SDK 35) — **NOT currently attached** (`adb devices` empty now).
**ADB:** `C:\Users\nader\AppData\Local\Android\Sdk\platform-tools\adb.exe` · **Package:** `com.routenote.routenote` · **Activity:** `com.routenote.routenote/.MainActivity`
**Real Google account:** `nader.adel7777@gmail.com` (last state TRUSTED). **Never seed without `-OnlyAge`** — default seed replaces `auth_user` with placeholder `audit-device@example.com`.
**Hive boxes:** `settings.hive`, `places.hive`, `gps_daily.hive`, `auto_motion_box.hive`, `secure_places.hive`, `adaptive_profile.hive` (`app_flutter/`).

### Verified facts (do not re-derive)
| Fact | Detail |
| --- | --- |
| `AppConfig.sessionTrustWindow` is the intended design | Approved. No alternate mechanism needed. |
| Device audit result | 0 chooser triggers on trusted branch; clean single-call fallback on stale branch; self-healing re-stamp. |
| `strings` on Android 15 | `/system/bin/strings` (toybox), works under `run-as`, in-place. `settings.hive` privacy: 0 `latitude`/`longitude` hits while payload keys present; `places.hive` control **must** hit. |
| PowerShell/ADB gotchas | `&&` = parse error in PS 5.1 (use `;`); `flutter install` defaults to `--release` (not debuggable → `run-as` fails) so use `--debug`; `flutter build apk --release` doesn’t install (use `--use-application-binary=`); never pull Hive boxes with PS `>` (use `cmd /c ... exec-out run-as ... cat ... > ...`). |
| logcat gotchas | Must use `-v threadtime` (default `brief` misses the counter → false PASS); `logcat -c` may not flush; count `CredentialManager: starting executeGetCredential` (authoritative), ignore raw `CredentialChooserActivity` line counts. |
| Tooling to reuse | `tool/device_cold_launch_auth_audit.ps1`, `tool/hive_audit.dart`, `tool/device_seed_session.ps1` / `tool/hive_seed_session.dart` (`-OnlyAge`), `tool/README.md`. |
| Pre-commit / gate | `scripts/hooks/pre-commit` runs `flutter analyze lib test` only when Dart staged. Gate: analyze clean; all tests pass; no secrets in `lib/`/`android/`/`ios/`. |

**START HERE (next session):** no code workstream open. AutoMotion Phase 4 complete. Optional: device validation on `AYDL024206002031`, or push the 4 commits ahead of origin. Repo clean.
