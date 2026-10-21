# Session Briefing — MapNote-App (RouteNote)

**Read first:** `AGENTS.md` → `AGENT_SKILLS.md` (canonical pass/fail standard — read before editing AND before finishing any task). Then `.opencode/PROJECT_STATE.md` for project memory.

---

## 1. Git state

- **Repo:** `D:\RouteNote App` · **Branch:** `main`
- **HEAD:** `4b59433` (`docs(opencode): mark AutoMotion Phase 3 complete (0c5fc38)`)
- **Last commit:** `docs(opencode): mark AutoMotion Phase 3 complete (0c5fc38)`
- **Working tree: CLEAN** — no modified, no untracked files. `.opencode/` is tracked.
- **Code checkpoint:** `0c5fc38` (`feat(automotion): implement phase 3 per-mode breakdown & 7/30-day aggregates`) — **AutoMotion Phase 3 COMPLETE**. Previous checkpoint `2b23e9b` (cold-launch auth, device-verified 2026-10-21) remains intact.
- **Recent history:** `4b59433` ← `0c5fc38` (AutoMotion Phase 3) ← `ab1e626` (docs: set auth checkpoint) ← `3a352d8` (device audit skill) ← `2b23e9b` (auth trust-window tests) ← `3ab161d` (Hive encoding fix)

## 2. Completed in this session

- **AutoMotion Phase 3 — COMPLETE.** Per-mode activity breakdown (walk/run/vehicle) on `DailyGpsSummary` with backward-compatible defaults; 7/30-day aggregates computed in RAM from `auto_motion_box` (`AutoMotionDataSource.aggregates`/`last7Days`/`last30Days`); `_ActivityBreakdownCard` + `_AggregatesCard` rendered on the dashboard; all new strings in both `app_en.arb` and `app_ar.arb`; 12 new aggregation tests in `test/auto_motion_aggregates_test.dart`. Verification gate: 821 tests passing, clean analyzer.
- **Cold-launch auth optimization — COMPLETE** (carried from prior session, `2b23e9b`), device-verified 2026-10-21 on Honor 90 / Android 15.
- **Device audit skill** `.opencode/skills/mapnote-device-audit/SKILL.md` added; full 360° integrity audit passed (Hive backward-compat, l10n parity, secrets scan, health-log privacy zero-coords).

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

**START HERE (next session):** no code workstream open. If continuing, pick one of the optional milestones above (device validation of AutoMotion Phase 3, or end-to-end device audit). Otherwise the repo is clean and ready to push.
