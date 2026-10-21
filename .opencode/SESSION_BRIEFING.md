# Session Briefing — MapNote-App (RouteNote)

**Read first:** `AGENTS.md` → `AGENT_SKILLS.md` (canonical pass/fail standard — read before editing AND before finishing any task). Then `.opencode/PROJECT_STATE.md` for project memory.

---

## 1. Git state

- **Repo:** `D:\RouteNote App` · **Branch:** `main`
- **HEAD:** `ab1e626` (`ab1e62664d7000cd74532ecf9d62972323e49e18`)
- **Last commit:** `docs(opencode): set 2b23e9b as active auth checkpoint`
- **Working tree: CLEAN** — no modified, no untracked files. `.opencode/` is tracked.
- **Code checkpoint:** `2b23e9b` (`test(auth): pin the trust-window evidence rule and the restore failure paths`) — **active auth checkpoint**, device-verified 2026-10-21. Latest commits `ab1e626` / `3a352d8` are **docs-only** (no Dart changes).
- **Recent history:** `ab1e626` ← `3a352d8` (add device audit skill + state refresh) ← `2b23e9b` (auth trust-window tests) ← `3ab161d` (Hive encoding fix) ← `f12420b` (Hive auditor + audit harness) ← `1da05e2` (cold-launch auth fix)

## 2. Completed in this session

- **New agent skill** `.opencode/skills/mapnote-device-audit/SKILL.md` (ID `mapnote-device-audit`, auto-discovered). Cold-launch auth regression (4× force-stop/start, `executeGetCredential` loop signature, `-v threadtime`) + Hive privacy inspection (`settings.hive`/`health_events`, zero `latitude`/`longitude`, `places.hive` non-vacuity control). Includes the empirically-corrected PowerShell/ADB/build/logcat details and pointers to existing tools.
- **`.opencode/PROJECT_STATE.md` updated** — reflects `2b23e9b` as the **active checkpoint** (the intended `AppConfig.sessionTrustWindow` architecture, device-verified), marks cold-launch auth **COMPLETE**, sets next open work to **AutoMotion Phase 3**.
- **Earlier work in this session** — `--only-age` / `-OnlyAge` for `tool/hive_seed_session.dart`/`tool/device_seed_session.ps1`; `test/hive_seed_session_test.dart` (5); `test/auth_session_test.dart` extended (+8 edge cases). **Verification gate:** 809 tests passing, clean analyzer.
- **Device verification (approved):** `AYDL024206002031` — 0 chooser triggers on trusted branch, clean single-call fallback on stale branch, self-healing re-stamp. Confirmed.

## 3. Pending work — exact next step

**Primary: AutoMotion Phase 3** (`project_roadmap.md` §4, `.opencode/PROJECT_STATE.md` §4) — **per-mode activity breakdown (walk / run / vehicle) + 7/30-day aggregates**.

Constraints: fully offline · bilingual en/ar via ARB keys (both `app_en.arb` and `app_ar.arb`) · **no new runtime dependencies** · two trackers stay independent (separate boxes/settings switches) · new fields on `DailyGpsSummary` with **backward-compatible defaults** · write only to `auto_motion_box` (do **not** touch `gps_daily.hive`).

**Exact first action:**
1. Read `project_roadmap.md` §4 and find `DailyGpsSummary`, `AutoMotionDataSource`, and the AutoMotion UI under `lib/src/features/automotion/`.
2. Add per-mode fields + 7/30-day aggregation with backward-compatible Hive defaults (never break existing schemas; `AGENT_SKILLS.md` §1.2).
3. Extend the dashboard (`lib/src/features/automotion/automotion_dashboard_screen.dart` and related widgets/providers) to surface breakdown + aggregates.
4. Add every new string to **both** `lib/l10n/app_en.arb` and `app_ar.arb`; wire through generated `AppLocalizations`.
5. Add/extend tests; run `flutter analyze lib test` and `flutter test` before finishing.

**Secondary (optional):** the new skill (`mapnote-device-audit`) hasn’t been run end-to-end yet. Device is currently **detached** — if you want to exercise it, first do ADB recovery on `AYDL024206002031`.

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

**START HERE (next session):** re-read `project_roadmap.md` §4 + the AutoMotion feature code (`lib/src/features/automotion/`), confirm `DailyGpsSummary` schema + `AutoMotionDataSource`, plan backward-compatible fields, then implement Phase 3 (per-mode breakdown + 7/30-day aggregates) with full i18n and tests.
