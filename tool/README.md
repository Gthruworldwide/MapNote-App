# RouteNote supervisor agent (dev-machine tool)

`supervisor_agent.py` is a **development-time** QA loop. It reads a
*sanitized* diagnostics file, asks Gemini to diagnose issues against
RouteNote's constraints, and hands the fix instructions to a developer CLI
(Claude Code / Cursor). It is **not** part of the app — RouteNote itself stays
zero-backend and offline-first; nothing here ships to devices.

## Quick start

```bash
pip install google-generativeai
echo 'GEMINI_API_KEY=...' > tool/.env        # .env is git-ignored
export GEMINI_API_KEY="$(cat tool/.env | cut -d= -f2)"   # or your shell's dotenv

python tool/supervisor_agent.py --input routenote_diagnostics.json --check
python tool/supervisor_agent.py --input routenote_diagnostics.json --dry-run
python tool/supervisor_agent.py --input routenote_diagnostics.json --yes --no-run
python tool/supervisor_agent.py --input routenote_diagnostics.json --yes
python tool/supervisor_agent.py --watch --interval 15 --input routenote_diagnostics.json
```

## Telegram control bridge

`supervisor_agent.py` can also run as a small Telegram bot so the dev machine
can be driven remotely (useful when you are away from the keyboard):

```bash
# put the token + your chat id in tool/.env (git-ignored)
python tool/supervisor_agent.py --telegram-check   # validate token/chat id
python tool/supervisor_agent.py --telegram         # start the polling loop
```

| Command | Effect |
| --- | --- |
| `/start`, `/help` | Show the control menu |
| `/status` | System time, Git branch + working-tree state, and connected device (`REA NX9`) via `flutter devices` |
| `/test` | Run `flutter test` and reply with the summary |
| `/prompt <instruction>` | Forward the instruction to the dev agent (same hand-off as the automated loop) |

`/prompt` runs whatever `DEV_AGENT_CMD` + `DEV_AGENT_EXTRA_ARGS` point at, with
the instruction appended as one argv element, from the repo root. Example for
the OpenCode CLI (not on PATH here, so an absolute path is used):

```env
DEV_AGENT_CMD=C:\path\to\opencode-cli.exe
DEV_AGENT_EXTRA_ARGS=["run","--auto","--model","opencode/big-pickle"]
```

(`--auto` lets it apply edits unattended; drop it to require approvals.)

Safety:

- **Single authorized user.** Every update is checked against
  `TELEGRAM_CHAT_ID`; messages from any other `user.id` are ignored.
- **No shell.** Commands are fixed argv lists run with `shell=False`;
  `/prompt` text is passed to the dev agent as a single argv element and is
  never parsed by a shell.
- **Redacted replies.** Command output is passed through the same redactor as
  the diagnostics loop before it is sent.
- The bot token lives only in `tool/.env`. A long-polling loop keeps a single
  outbound HTTPS connection to `api.telegram.org`; nothing here touches the
  Flutter app.

> Start the polling loop inside `supervisor_agent.py` itself with
> `--telegram`; it is a foreground process (Ctrl+C to stop).

## Input contract

`--input` accepts either **one JSON array** of records or **JSON-lines**
(one record per line — the shape the app's `HealthEvent.toMap()` produces
when exported). The tool does not care about field names: each record is
flattened to text and analyzed. Records are truncated to 500 chars each and
the excerpt sent to Gemini is capped (`--max-chars`, default 60 000).

How to get a sanitized export from the app: the diagnostics live in the Hive
`health_events` key (bounded, sanitized events — `AppObserverService` never
writes raw errors or stack traces). Export them via an adb-backed debug
helper or a future debug screen; do **not** paste crash dumps with stack
traces into the input file.

## Safety (why it works this way)

- **No credentials in the repo.** `GEMINI_API_KEY` comes from the
  environment. `tool/.env` is git-ignored.
- **No shell injection.** The model's output is passed to the dev agent as a
  single argv element (`subprocess.run(..., shell=False)`). `DEV_AGENT_CMD`
  (default `claude`) and `DEV_AGENT_EXTRA_ARGS` (a JSON list) choose the
  binary and its fixed flags — model text is never split or parsed as shell.
- **Defense-in-depth redaction.** Inputs are run through a redactor
  (Google API keys, `Bearer`/`api_key`/`authorization` values, long
  tokens, emails) before anything leaves the machine.
- **Consent + audit trail.** TTY runs ask before sending; CI needs `--yes`.
  Reports (including the exact excerpt sent and the fix prompt) go to
  `tool/reports/`; the input file is never modified or truncated.
- **`--dry-run`** composes without calling Gemini or running any binary.

## Environment

| Variable | Default | Meaning |
| --- | --- | --- |
| `GEMINI_API_KEY` | — (required) | Gemini API key |
| `SUPERVISOR_GEMINI_MODEL` | `gemini-1.5-pro` | Model id |
| `DEV_AGENT_CMD` | `claude` | Dev-agent binary (must be installed) |
| `DEV_AGENT_EXTRA_ARGS` | `[]` | JSON list of fixed argv, e.g. `["-p","--output-format","text"]` |
| `TELEGRAM_BOT_TOKEN` | — | BotFather token for the control bot |
| `TELEGRAM_CHAT_ID` | — | The only `user.id` the bot will obey |

## Offline privacy audit (`hive_audit.dart`)

`hive_audit.dart` is a **read-only, offline** auditor for a Hive box pulled off
a device. It answers the question "does anything in local storage contain a
user's coordinates?" without the app, a network, or an account.

```bash
# Pull the box off a debuggable build (binary-safe: do NOT use PowerShell `>`,
# which corrupts the file and makes Hive report "Recovering corrupted box").
cmd /c "adb -s <serial> exec-out run-as com.routenote.routenote cat app_flutter/settings.hive > out/settings.hive"

dart run tool/hive_audit.dart out
```

It prints the top-level keys, the event-type histogram of `health_events`, the
**union of every payload key** the log has ever contained, and a privacy scan
for forbidden keys (`latitude`, `lng`, `place_id`, …), coordinate-shaped keys
and bare lat/lng number pairs. It also reports the session state
(`is_logged_in`, `last_synced`, age against the trust window) that decides
whether a cold launch takes the "session still fresh" branch.

Nothing leaves the machine: the tool opens the box read-only and prints to
stdout. It never contacts Google, Gemini or Drive.

> **Pull the box without corrupting it.** PowerShell's `>` re-encodes a byte
> stream, which turns a 231 KB Hive box into a 463 KB file that Hive then
> reports as "Recovering corrupted box". Pull it through `cmd /c` instead:
>
> ```bash
> cmd /c "adb -s <serial> exec-out run-as com.routenote.routenote cat app_flutter/settings.hive > out/settings.hive"
> ```
>
> Once the bytes are intact, a plain-text scan works: Hive CE stores strings as
> UTF-8 bytes (single-byte for ASCII text), so `last_synced`, `is_logged_in`
> and friends are readable with `strings`/`grep` (if the tool is installed on
> the host). `tool/hive_audit.dart` does not depend on `strings` — it parses
> the box with `hive_ce` and additionally scans the raw bytes itself.

### Reproducing a "trusted session" device state

`hive_seed_session.dart` writes the exact keys and value shapes
`SettingsRepository` persists (`is_logged_in`, `auth_user`, `last_synced`) into
a pulled box, so a device can be put into the "session synced recently"
branch without a live Google account:

```bash
dart run tool/hive_seed_session.dart out            # trusted (last_synced inside the window)
dart run tool/hive_seed_session.dart out --stale    # stale -> the full restore must run
```

Push the result back with a binary-safe copy and cold-launch the app. A
trusted session must produce **zero** `executeGetCredential` calls; a stale one
must still restore. Always `am force-stop` the app before pushing a modified
box back, so Hive does not overwrite it from its in-memory state.

> **Auditing a device that holds a real Google session.** The default mode
> replaces `auth_user` with the placeholder `audit-device@example.com`, which
> leaves the device showing a fake account. Add `--only-age` to keep the box's
> existing `is_logged_in` / `auth_user` and age **only** `last_synced`:
>
> ```bash
> dart run tool/hive_seed_session.dart out --stale --only-age
> ```
>
> That is the non-destructive way to measure the stale branch on a device that
> is really signed in. The trust evidence heals on its own: the next
> successful Drive round-trip re-stamps `last_synced`.

## Android release signing (`create_upload_keystore.ps1`)

Creates the **upload keystore** for the Android release build and the
`key.properties` file that points at it. Dev-machine only; nothing here
ships to the device.

```bash
powershell -ExecutionPolicy Bypass -File tool/create_upload_keystore.ps1
powershell -ExecutionPolicy Bypass -File tool/create_upload_keystore.ps1 -Password "my-secret"
powershell -ExecutionPolicy Bypass -File tool/create_upload_keystore.ps1 -Alias upload -Validity 10000
```

It writes two files:

| Path | Git | Contents |
| --- | --- | --- |
| `android/app/upload-keystore.jks` | ignored | The RSA-2048 upload key, alias `upload`, valid 10 000 days |
| `android/key.properties` | ignored | `storePassword`, `keyPassword`, `keyAlias`, `storeFile` |

Both are ignored by the root `.gitignore` (`key.properties`, `*.jks`,
`*.keystore`) and by `android/.gitignore`. The passwords are generated with
`RandomNumberGenerator` and hex-encoded, so they need no escaping in a Java
`.properties` file — and nothing sensitive ever reaches git.

`android/app/build.gradle.kts` parses `key.properties` at configuration time
and binds it to `signingConfigs.release`. If the file is missing the release
build falls back to the **debug** key with a warning, so a fresh clone still
compiles; such a bundle is rejected by Play, which is the intended signal.

> **Back the keystore up outside the repository.** It is deliberately not
> synced through git, so losing it means Google Play can no longer accept
> updates for the package under the same signing identity.

## iOS Info.plist validation (`validate_info_plist.py`)

`plutil -lint` is macOS-only, so on a Windows/Linux host this script is the
equivalent gate for `ios/Runner/Info.plist`. It performs the same two stages
`plutil` does for the XML plist format, then asserts the app's permission and
background-mode contract.

```bash
python tool/validate_info_plist.py
```

| Stage | What it checks |
| --- | --- |
| XML | The file is well-formed XML (`xml.etree.ElementTree`) |
| Plist | It parses as a plist dictionary (`plistlib.load`) |
| Contract | Every required key is present and correctly typed |
| Contract | `UIBackgroundModes` contains `location` and `processing` |
| Contract | `BGTaskSchedulerPermittedIdentifiers` is non-empty, unique, and covers `routenote.periodicSync` |

The last check is not cosmetic: `processing` requires permitted identifiers,
and the identifier must be the exact string the app registers with
`BGTaskScheduler` — here `AppConfig.backgroundSyncUniqueName`, which
`workmanager_apple` passes straight through as the task identifier. A missing
or mismatched entry makes the registration throw at runtime and fails App
Store validation.

> **No `ios/Podfile` on purpose.** This project uses Swift Package Manager
> (`FlutterGeneratedPluginSwiftPackage`), so `pod install` is not part of the
> build. The customary `PERMISSION_LOCATION=1` / `PERMISSION_SENSORS=1`
> `GCC_PREPROCESSOR_DEFINITIONS` belong to `permission_handler_apple`, and
> `permission_handler` is not a dependency of this app. See the "Platform
> configuration" section of the top-level `README.md` for the full rationale.

## Related

- App-side diagnostics: `AppObserverService` / `AppHealthLogger`
  (`lib/src/services/`) — records sanitized events; this tool only consumes
  an exported snapshot of them.
- Standards: `AGENT_SKILLS.md` §2.3 (secrets hygiene) applies here too.