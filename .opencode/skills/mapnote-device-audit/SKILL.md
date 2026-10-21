---
name: mapnote-device-audit
description: Cold-launch auth regression checks, Hive privacy audits, and device testing for MapNote-App on target device AYDL024206002031.
license: MIT
compatibility: opencode
metadata:
  opencode/slash: "true"
  opencode/autoinvoke: "true"
---

Run this audit **from the repository root** (`D:\RouteNote App`). It re-checks the
two device-level guarantees that no unit test can cover: the Google silent-restore
behaviour on a cold launch, and the privacy of the on-device Hive health log.

The standard this audit enforces is `AGENT_SKILLS.md` §2.1 (auth) and §2.3
(secrets / privacy).

## Target Environment

- **Device ID:** `AYDL024206002031` (Honor 90 / Android 15)
- **ADB Path:** `C:\Users\nader\AppData\Local\Android\Sdk\platform-tools\adb.exe`
- **Package:** `com.routenote.routenote`
- **Activity:** `com.routenote.routenote/.MainActivity`
- **Box location on device:** `app_flutter/` inside the app data dir
  (`settings.hive`, `places.hive`, `gps_daily.hive`, `auto_motion_box.hive`,
  `secure_places.hive`, `adaptive_profile.hive`)

## Verification Steps

### 1. ADB Recovery

Run this if the device `AYDL024206002031` is missing from `adb devices`:

```powershell
$adb = "C:\Users\nader\AppData\Local\Android\Sdk\platform-tools\adb.exe"
& $adb kill-server
& $adb start-server
& $adb devices
```

> **Do not chain with `&&`.** The dev shell is Windows PowerShell 5.1, where
> `&&` is a *parse error* (`The token '&&' is not a valid statement separator in
> this version.`), not a sequencing operator. Use separate statements or `;`.

The device must list as `device` (not `offline` / `unauthorized`). If it lists as
`unauthorized`, unlock the phone and accept the RSA prompt; if it is absent
entirely, re-plug the cable and confirm USB debugging is on.

### 2. Cold-Launch Auth Audit

- **Install the Release APK.**
  `flutter build apk --release` only *builds* — it does not install. Install it
  afterwards:

  ```powershell
  flutter build apk --release
  flutter install -d AYDL024206002031 --use-application-binary=build/app/outputs/flutter-apk/app-release.apk
  ```

  The release build is **not** debuggable, so `run-as` is unavailable here — that
  is fine for this step (it only reads logcat); step 3 re-installs the debug
  build for the Hive inspection.

- **Execute 4 consecutive cold launches** using `am force-stop` and `am start`:

  ```powershell
  & $adb -s AYDL024206002031 logcat -c
  & $adb -s AYDL024206002031 shell am force-stop com.routenote.routenote
  Start-Sleep -Seconds 2
  & $adb -s AYDL024206002031 shell am start -n com.routenote.routenote/.MainActivity
  Start-Sleep -Seconds 20
  & $adb -s AYDL024206002031 logcat -d -v threadtime
  ```

  Repeat 4× (clear the log between launches so each launch is measured alone).

- **Verify 0 crashes/ANRs**, and confirm `executeGetCredential` triggers **at
  most once per launch** without loops.

#### Traps that produce a false PASS

| Trap | Why it fails silently |
| --- | --- |
| Reading logcat **without `-v threadtime`** | The default `brief` format renders the tag as `I/CredentialManager( 2522):`, which does **not** contain the substring `CredentialManager: starting executeGetCredential` the counter looks for. A `brief` run reports **zero for every launch** — a green run that measured nothing. |
| Counting `CredentialChooserActivity` | One chooser invocation emits **>100 lines** of SurfaceFlinger/WindowManager chatter, so the raw line count is meaningless as a regression signal. |
| Trusting `logcat -c` | It does not always flush a pending entry, so a launch can report `executeGetCredential = 2` where the plugin made a single attempt. Corroborate with the `ui invocation is needed` line and the raw logcat. |
| Auditing a device with no Google session | With no persisted `is_logged_in` / `auth_user` there is nothing to restore and the check is meaningless — expect 0 calls for the wrong reason. Confirm the session state first (see `tool/hive_audit.dart`, which prints `last_synced` age against the trust window). |

#### The authoritative signals

- `CredentialManager: starting executeGetCredential` — **the** loop signature.
  `> 1` in a single launch = a restore loop = **FAIL**.
- `ui invocation is needed` — Play Services decided the chooser must be shown
  (focus theft is possible).
- `CredentialChooserActivity` / `AssistedSignInActivity` — informational only.

#### Expected results

- Session **trusted** (`last_synced` younger than `AppConfig.sessionTrustWindow`)
  → **0** `executeGetCredential` calls, chooser never raised.
- Session **stale** or absent → **exactly 1** call, chooser may be raised once,
  **no loop**.

To measure the stale branch on a device that holds a **real** Google session, use
`powershell -File tool/device_seed_session.ps1 -Serial AYDL024206002031 -Stale -OnlyAge`.
**Always pass `-OnlyAge`**: without it the seed replaces `auth_user` with the
placeholder `audit-device@example.com` and leaves the device showing a fake
account. The trust evidence heals on its own — the next successful Drive
round-trip re-stamps `last_synced`.

#### Prefer the existing harness

`tool/device_cold_launch_auth_audit.ps1` already implements every rule above
(force-stop + start, `-v threadtime` logcat, the authoritative counter, and
`topResumedActivity` polling to detect focus theft):

```powershell
powershell -File tool/device_cold_launch_auth_audit.ps1 -Serial AYDL024206002031 -Launches 4
```

Its summary ends in `RESULT: PASS` / `RESULT: FAIL`. Use the manual commands
above only to investigate a failure.

### 3. Hive Privacy Inspection

- **Install the Debug APK.** `run-as` requires a **debuggable** build, so the
  release APK from step 2 cannot be used here — the debug install must come
  first if you are doing both in one session:

  ```powershell
  flutter install -d AYDL024206002031 --debug
  ```

  > **`--debug` is not optional.** `flutter install` defaults to the **release**
  > mode (`--release … (default mode)`), and a release build is *not*
  > debuggable — `run-as` then fails with *"package is not debuggable"* and the
  > whole inspection is impossible. Verify before auditing:
  >
  > ```powershell
  > & $adb -s AYDL024206002031 shell "dumpsys package com.routenote.routenote" |
  >   Select-String "DEBUGGABLE"
  > ```
  >
  > The flag list must contain `DEBUGGABLE`.

- **Inspect the `settingsBox` key `health_events`:**

  ```powershell
  & $adb -s AYDL024206002031 shell "run-as com.routenote.routenote strings app_flutter/settings.hive"
  ```

- **Confirm EXACTLY ZERO `latitude` or `longitude` fields are persisted** in the
  stored payloads.

The health log must carry only kind / magnitude / timestamp — never place names,
notes or coordinates (`AGENT_SKILLS.md` §5, "Privacy").

#### Notes on the command

- `strings` **does** exist on this device (`/system/bin/strings`, toybox) and
  works under `run-as`. It runs **in place** on the box, so there is no pull and
  no redirection — the PowerShell `>` UTF-16LE corruption trap (which turns a
  231 KB box into a 463 KB "Recovering corrupted box") applies only to the
  *pull* form used by `tool/hive_audit.dart`.
- Hive CE stores strings as UTF-8 bytes, so ASCII keys are readable directly.
- Match the **full key names** `latitude` / `longitude`. A loose substring match
  also hits innocent keys such as `uiLatency`.

#### Non-vacuity control (required)

A zero hit only means something if the command actually reached the health-log
content. Before accepting "zero", prove both halves:

1. **The payload is visible** — the expected keys must be present in the output:
   `health_events`, `maneuver`, `peak_mps2`, `duration_ms`.
2. **The detector works** — run the *same* command against a box that
   legitimately holds coordinates. It **must** hit:

   ```powershell
   & $adb -s AYDL024206002031 shell "run-as com.routenote.routenote strings app_flutter/places.hive"
   ```

   Expect repeated `latitude` / `longitude` hits. If this control does **not**
   hit, the detector is broken and the zero on `settings.hive` is meaningless.

#### Deeper audit (optional)

For a structured walk — top-level keys, the `health_events` type histogram, the
union of every payload key ever written, and a scan for coordinate-shaped keys
and bare lat/lng pairs — pull the box **binary-safe** and run the repo auditor:

```powershell
cmd /c "`"$adb`" -s AYDL024206002031 exec-out run-as com.routenote.routenote cat app_flutter/settings.hive > .scratch/audit/settings.hive"
dart run tool/hive_audit.dart .scratch/audit
```

> **Never pull a Hive box with PowerShell `>`.** It re-encodes the byte stream
> (231 KB → 463 KB) and Hive then reports "Recovering corrupted box". Always go
> through `cmd /c "adb ... exec-out run-as ... cat ... > out.hive"`.

## Reporting

Report the audit as pass/fail with evidence, per `AGENT_SKILLS.md` "Reporting":

```
Cold-launch auth audit: pass/fail
  session state (trusted|stale): <last_synced age>
  launches: 4 | executeGetCredential per launch: <n,n,n,n> | chooser raised: <n>
  crashes/ANRs: <n>
Hive privacy audit: pass/fail
  health_events payload keys visible: yes/no
  latitude/longitude hits in settings.hive: <n>   (control places.hive hits: <n>)
```

Any `executeGetCredential > 1` in a single launch, any crash/ANR, any
`latitude`/`longitude` hit in `settings.hive`, **or** a non-vacuity control that
fails to hit is a **FAIL** — fix it before the change is considered complete.
