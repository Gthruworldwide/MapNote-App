# RouteNote Supervisor Agent Instructions

## Role

You are the **Supervisor Agent** for RouteNote (Flutter, offline-first, Hive CE,
Google Drive sync). You read the diagnostics file `app_logs.txt` produced by
`AppLogger` (`lib/src/services/app_logger.dart`), diagnose the root cause of
each issue, and hand the **Developer Agent** (Big Pickle / Cursor / Claude)
a single, unambiguous fix task per issue.

The file lives in the app's documents directory on the device. Get it with:

```bash
# Needs a *debug* build connected to adb (`run-as` requires a debuggable
# package). On Android, AppLogger writes into the app's internal files dir.
adb exec-out run-as com.routenote.routenote cat files/app_logs.txt > app_logs.txt
# or export it through any debug helper available on the target platform
```

> Optional automation: `tool/supervisor_agent.py` (dev-machine only) reads a
> diagnostics file, asks Gemini to diagnose it, and forwards the generated fix
> prompt to a developer CLI. This document defines the prompt format that both
> the script and a manual workflow must produce.

## Log format produced by AppLogger

One entry per line, plus optional indented detail lines:

```text
[2026-10-10T08:00:00.000] [ERROR] [SYNC] Drive backup sync failed
  ErrorDetails: ...
  StackTrace: ...
```

- `[LEVEL]`: `INFO`, `WARNING`, `ERROR`.
- `[CATEGORY]` vocabulary emitted by the app:
  - `FLUTTER_FRAMEWORK` — caught by `FlutterError.onError` (runtime errors).
  - `UNCAUGHT_ASYNC` — caught by `PlatformDispatcher.onError`.
  - `SYNC` — Drive backup / restore failures.
  - `AUTH` — silent sign-in / session validation failures.
  - `LOCATION_PARSER` — maps-URL or coordinate parsing bugs.
  - `UI` — performance / layout signals (future use).
  - `HIVE_DB` — persistence failures (future use).

## Workflow

1. **Read & filter**: keep `[ERROR]` and `[WARNING]` entries; drop `[INFO]`.
2. **Deduplicate**: identical or near-identical entries within a window count
   as one issue (the app already bounds the file to the most recent ~256 KB).
3. **Prioritize**:
   - **P0 (Critical)**: auth loops, Drive sync/restore failures, Hive box
     corruption.
   - **P1 (High)**: location parsing failures (regex edge cases).
   - **P2 (Normal)**: UI glitches, network retries, non-blocking warnings.
4. **Produce one fix task** per issue with the template below. Do **not**
   merge unrelated issues into one task.

## Fix task template (send verbatim to the Developer Agent)

```text
[ROUTE_NOTE_AUTO_FIX_TASK]
Category: <SYNC | AUTH | LOCATION_PARSER | UI | HIVE_DB | FLUTTER_FRAMEWORK>
Priority: <P0 | P1 | P2>

Problem Description:
<What is failing, in 1-2 sentences, based only on the log evidence.>

Log Context:
<The exact app_logs.txt entry (with the ErrorDetails/StackTrace lines) that
shows the failure. Do not invent data not present in the log.>

Target File(s):
<Exact paths, e.g. lib/src/services/location_parser.dart.>

Architectural Constraints:
- Zero-backend: local Hive CE persistence; absence of new failures only.
- State management via Riverpod — no new global singletons.
- Both Android and iOS; keep `AGENT_SKILLS.md` rules in mind.
- All user-facing strings via l10n ARB files (EN + AR).
- Must run `flutter analyze lib test` and `flutter test` after the fix.

Requested Fix:
<Step-by-step, precise edit instructions: which function to change, the new
behavior, and the verification commands to run.>

Reject if:
- The log evidence is ambiguous — ask for a fuller export instead of guessing.
- The fix would persist secrets, add a backend, or break offline-first.
```

## Definition of done

- The developer agent applies only the changes described in `Requested Fix`.
- `flutter analyze` is clean and `flutter test` passes (full suite).
- No secrets/API keys or user PII appear in `app_logs.txt` entries (the app
  redacts and truncates; verify the paste-back did not reintroduce any).