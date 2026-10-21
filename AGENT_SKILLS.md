# RouteNote AI Agent — Skills & Evaluation Standards

RouteNote is an **offline-first** saved-places app (Flutter) with optional Google
Drive backup and an opt-in Gemini "Smart Insights" layer. This file is the
canonical, **pass/fail** evaluation standard every automated agent change must
meet. It maps 1:1 onto the four skills areas and is written so any AI agent can
verify compliance from the codebase without human judgement calls.

> Rule of thumb for agents: **before** editing, read the area(s) this file
> defines for the files you touch; **after** editing, re-check those files and
> run the verification gate. Report per-area pass/fail with evidence.

---

## Verification gate (runs for every change)

1. `flutter analyze lib test` → **No issues found**.
2. `flutter test` → **all tests pass**.
3. Secrets hygiene (see §2.3): no API keys/tokens in `lib/`, `android/`,
   `ios/` or release artifacts.

---

## 1. Architecture & data integrity

### 1.1 Zero-backend / offline-first

**Constraint.** RouteNote has **no RouteNote-run server**. The app must boot and
all core flows (browse, add, edit, lock, search, insights) work with no network
and with no API key configured. Network use is restricted to:

- Google Drive REST sync (scope `drive.appdata`) — only while signed in,
- the opt-in Gemini `generateContent` client — only when a key is built in,
- `url_launcher` map deep links (Google Maps / Waze),
- short-map-link resolution inside `LocationParser.resolveShortLink`.

**Eval.**

- A commit must never add a *required* network call on any core path.
- A new dependency on a network package or a new endpoint host is a review
  item: justify it in the commit or it fails.
- **Gemini is strictly opt-in.** Zero network calls when
  `GeminiClient.isConfigured == false` or the Settings *Smart insights* toggle
  is off (`cloudAiEnabledProvider`). The key comes from
  `--dart-define=GEMINI_API_KEY` (`AppConfig.geminiApiKey` via
  `String.fromEnvironment`), travels in the **`x-goog-api-key` header — never
  in the URL** — and transport failures surface as opaque
  `AgentException('Cloud suggestions unavailable' | '... timed out')` messages;
  `debugPrint` inside the client is gated behind `kDebugMode`.

### 1.2 Hive CE persistence

**Constraint.** All persistence uses **Hive CE** (`hive_ce` / `hive_ce_flutter`,
table `2.20.x`, package `hive_ce`). Two boxes:

- `placesBox` (`HiveDatabase.placesBox`) — keyed by `place.id`, value
  `Place.toMap()`.
- `settingsBox` (`HiveDatabase.settingsBox`) — via `SettingsRepository`,
  reserved keys: `locale`, `theme_mode`, `last_synced`, `is_logged_in`,
  `auth_user`, `cloud_ai_enabled`, `dismissed_insights`, and
  `AppConfig.healthLogKey = 'health_events'` for the agent health log.

**Eval.**

- Widgets/providers never touch `box.put` directly: new persistent state goes
  through `SettingsRepository` or `PlaceRepository`/`PlaceLocalDataSource`.
- Keys are declared once as `static const` in the owning repository (or
  `AppConfig` for cross-cutting keys) and referenced, never string-duplicated.
- `AppHealthLogger` accepts a nullable box: `null` = in-memory only. **Full-app
  widget tests must override `appHealthLoggerProvider` with
  `AppHealthLogger(null)`** — a real box writes inside `testWidgets`
  FakeAsync and never completes, deadlocking the runner (known hazard).
- **Single sanctioned file-writer exception:** `AppLogger`
  (`lib/src/services/app_logger.dart`) writes `app_logs.txt` in the app
  documents directory for the Supervisor Agent workflow
  (`SUPERVISOR_INSTRUCTIONS.md`). It is the *only* on-disk file writer:
  entries are credential-redacted and truncated, and the file is bounded
  (keeps only the newest ~256 KB). Never add a second file logger, and never
  bypass the redaction/truncation.
- Schema changes are backwards compatible or migrate; never silently drop
  user data.

### 1.3 Riverpod (3.4.x) patterns

**Constraint.** Service singletons are plain `Provider`s; sync derived state
uses `Notifier`; async loads use `AsyncNotifier` (state is `AsyncValue<T>`).
Canonical providers (do not rename): `hiveDatabaseProvider`,
`settingsRepositoryProvider`, `placeLocalDataSourceProvider`,
`placeRepositoryProvider`, `locationServiceProvider`, `navigationServiceProvider`,
`shareIntentServiceProvider`, `biometricServiceProvider`,
`homeShortcutServiceProvider`, `dynamicIconServiceProvider`,
`authServiceProvider`, `driveServiceProvider`,
`syncRepositoryProvider`, `backgroundSyncSchedulerProvider`,
`appHealthLoggerProvider`, `appObserverServiceProvider`,
`analyticsServiceProvider`, `analyticsNavigatorObserversProvider`,
`localInsightEngineProvider`, `geminiClientProvider`,
`agentServiceProvider`, `placesProvider`, `authProvider`, `locationStatusProvider`,
`syncControllerProvider`, `localeControllerProvider`, `themeModeProvider`,
`agentProvider`, `cloudAiEnabledProvider`.

**Eval.**

- `ref.watch` appears only inside `build`; `ref.read`/`ref.listen` only in
  callbacks and async actions.
- `AsyncNotifier.build` returns `FutureOr`; consumers render via
  `AsyncValue.when`, and build returns quickly (no blocking I/O).
- Timers/subscriptions are cancelled with `ref.onDispose` (the agent's 6 h
  one-shot re-run timer must be cancelled on dispose); background merges use
  `ref.invalidateSelf()` / guarded re-emission, not periodic
  `ref.watch`-triggered loops.
- Avoid needless rebuilds: watch only what the subtree renders; keep
  `AgentNotifier`-style merge guards (compare derived id lists before re-emitting).
- No `BuildContext` reads outside `build`; no polling while a widget is off-screen.

### 1.4 i18n (English + Arabic)

**Constraint.** Every user-facing string is declared in
`lib/l10n/app_en.arb` **and** `lib/l10n/app_ar.arb` and accessed through
generated `AppLocalizations` (`l10n.<key>`). No raw string literals in
widgets — including `Text(...)`, `labelText`, `tooltip`, `SnackBar`, semantics.

**Eval.**

- `flutter gen-l10n` regenerates `lib/l10n/generated/…`; a missing key in
  either locale is a generator error, so both locales are always in sync.
- grep widget files for hardcoded UI strings; every match is a failure.
- Plurals/placeholders use ARB `{param}` slots, never string concatenation of
  translated fragments.

---

## 2. Data security & auth handling

### 2.1 Silent Google Auth

**Constraint.** Sign-in restore is **silent**: never shows UI and never blocks
the first frame. Flow: `AuthNotifier.build` → `_signInSilentlyInBackground()` →
`authService.signInSilently()` → `GoogleAuthService.signInSilently` →
`GoogleSignIn.instance.attemptLightweightAuthentication()`.

> **google_sign_in v7 removed `signInSilently()`.** Do not reintroduce it —
> `attemptLightweightAuthentication()` is its silent replacement. Drive token
> validation (`_validateDriveAccess`) is non-interactive; nothing prompts.

> **`attemptLightweightAuthentication()` is *not guaranteed* UI-free.** The
> plugin contract explicitly leaves "the amount of allowable UI" to the
> platform. On Android it routes through **Credential Manager**
> (`CredentialManager.getCredentialAsync(activity, …)`), which launches
> `CredentialChooserActivity` / `AssistedSignInActivity` when it cannot
> auto-select. Those run **inside MapNote's own task**, so opening the chooser
> backgrounds MapNote and dismissing it foregrounds MapNote again — a restore
> that re-enters on that rebuild loops forever. The restore must therefore be
> (a) attempted **only when a session was actually persisted** (`is_logged_in`,
> `auth_user`) and (b) **single-flight per process** (`AuthNotifier.
> _restoreAttempted`, a `static` field precisely so it survives provider
> rebuilds). Reset it through `AuthNotifier.resetRestoreGuard()` in tests only.

> **Measured on device (Honor 90, Android 15): the chooser is raised on an
> ordinary cold launch, not only when re-entering.** With a persisted session
> and no churn at all, Play Services logged
> `Provider status changed - ui invocation is needed`, then
> `CredentialChooserActivity` and `AssistedSignInActivity` each took
> `topResumedActivity` for ~2 s before MapNote regained the foreground. The
> reported cause is `CREDENTIALS_RECEIVED` from `GoogleIdService`; the trigger is
> **more than one Google account on the device**, which makes auto-selection
> ambiguous and forces the platform to ask. The single-flight guard still
> prevents a *loop* (measured: exactly one `executeGetCredential` per launch), but
> it does not prevent the prompt.
>
> **Consequence for the wording above:** "silent replacement" is too strong. On a
> multi-account device it is prompt-free only when the session needs no
> re-resolution. Counting `CredentialChooserActivity` lines in `logcat` is
> meaningless as a regression signal — one invocation emits >100 lines of
> SurfaceFlinger/WindowManager chatter. Count
> `CredentialManager: starting executeGetCredential` instead; more than one per
> launch is the real loop signature.

> **Suppression (`AppConfig.sessionTrustWindow`).** Because a Drive upload or
> restore cannot succeed without a live bearer token, `last_synced` is
> *evidence* the stored credentials work. While it is younger than
> `sessionTrustWindow`, `AuthNotifier.build` skips
> `attemptLightweightAuthentication()` outright, so no chooser can appear.
> A stale or absent `last_synced` still performs the full restore. Suppressing
> the launch-time call means `AuthService.isSignedIn` stays false until
> something re-establishes the account, so `SyncController._ensureSessionForDrive`
> performs the restore on the first *explicit* Drive action (Sync / Restore) —
> where platform UI is user-initiated and expected. The window is deliberately
> shorter than `backgroundSyncFrequency` so the headless backup is never
> suppressed.
>
> **Only a user gesture may re-establish the session.** This is the part that
> is easy to get wrong, because suppressing the *launch-time* restore is not
> enough on its own. The restore has to move to the explicit Drive action, and
> the automatic syncs must not carry it back: `SyncController.syncSilently()`
> fires on every app resume, and the Home screen's "sync on open" fires on
> every launch. Measured on the Honor 90: with the restore reachable from
> those automatic paths, the chooser was still raised on **4 of 4** cold
> launches (`CredentialChooserActivity` / `AssistedSignInActivity` took
> `topResumedActivity` every time) even though `AuthNotifier.build` had
> skipped its own call. `SyncController.syncNow` therefore takes a
> `userInitiated` flag, and only the Sync button, pull-to-refresh and a
> "Sync now" insight pass `true`.
>
> **There is no token cache.** `GoogleAuthService.authorizationHeaders()`
> needs a live `GoogleSignInAccount`, which only `signInSilently()` /
> `signIn()` produce. So a suppressed launch genuinely has no bearer token:
> the automatic sync reports `skippedNotSignedIn` until a user-initiated sync
> restores the account. That is the intended trade-off — the daily headless
> backup builds its own graph and restores the session on its own, so the
> backup is never lost.
>
> **Reproduction.** `tool/device_cold_launch_auth_audit.ps1` runs the
> measurement (force-stop → launch → poll `topResumedActivity` → count
> `executeGetCredential`), `tool/device_seed_session.ps1` puts the device into
> the trusted or stale session state, and `tool/hive_audit.dart` audits a
> pulled Hive box offline. All three are dev-machine tools; nothing in them
> ships to the device.
>
> To measure the **stale** branch on a device that holds a *real* Google
> session, seed with `--only-age`: it ages `last_synced` and leaves
> `auth_user` / `is_logged_in` untouched. The default seed mode replaces the
> identity with a placeholder, which would leave the device showing a fake
> account. The trust evidence heals by itself — the next successful Drive
> round-trip re-stamps `last_synced`.

**Eval.**

- `signInSilently` is used **only** as the app-level method name on
  `AuthService`/`GoogleAuthService` — never as a `GoogleSignIn` instance
  method.
- A **signed-out launch never calls `signInSilently()`** — there is nothing to
  restore, so the attempt (and its platform chooser) must not be made.
  Regression-covered in `auth_session_test.dart`.
- A launch whose cached session synced inside `sessionTrustWindow` **must not
  call `signInSilently()`**. The evidence must stay real: `last_synced` is
  written only after a successful Drive round-trip, so it cannot be faked by a
  mere app-start timestamp. Covered by the "freshly synced session skips the
  platform restore entirely" case, and the evidence rule itself is pinned by
  the "last_synced is written only after a successful Drive round-trip" case
  (a *failed* upload must not stamp it, or the suppression would outlive the
  session it was granted for).
- The suppression is **conditional, never a blanket skip**. A session whose
  `last_synced` is missing or older than `sessionTrustWindow` must still
  perform the full restore, exactly as before. Measured on the Honor 90: a
  stale session raised the Credential Manager chooser on the very first cold
  launch (`executeGetCredential` = 1, `ui invocation is needed` = 1, focus
  taken by `AssistedSignInActivity`), while the seeded trusted session
  produced zero calls on four consecutive cold launches. The suppression must
  never become a way to permanently disable session restore.

  > **Re-verified 2026-10-21** on AYDL024206002031 (Honor 90, Android 15):
  >
  > *Trusted branch* — the device's `settingsBox` reported `is_logged_in = true`
  > with a `last_synced` 10 minutes old (inside the window → TRUSTED).
  > `tool/device_cold_launch_auth_audit.ps1 -Launches 4` reported
  > `executeGetCredential` = **0**, `ui invocation is needed` = **0** and
  > `CredentialChooserActivity` / `AssistedSignInActivity` = **0** on every
  > launch. The only activity that took the foreground was the permission
  > controller's `GrantPermissionsActivity` on the first launch — the
  > location-permission prompt, not the Credential Manager chooser. The
  > automatic "sync on open" on those launches did **not** re-establish the
  > session, which is what the `userInitiated` flag exists to prevent.
  >
  > *Stale branch* — `last_synced` was aged past the window with
  > `--only-age` (the real `auth_user` untouched). The very next cold launch
  > restored: `executeGetCredential` = **1**, `ui invocation is needed` = **1**,
  > and `CredentialChooserActivity` / `AssistedSignInActivity` took
  > `topResumedActivity`. One plugin call, one chooser — **no loop**. The raw
  > logcat shows the escalation: `starting executeGetCredential` →
  > `Provider status changed - ui invocation is needed` →
  > `AssistedSignInActivity`, all inside MapNote's own task.
  >
  > *Self-healing* — the launches after that reported **0** calls again: the
  > successful Drive round-trip re-stamped `last_synced`, so the session was
  > TRUSTED once more. The suppression is conditional and self-repairing, not a
  > blanket skip.
  >
  > **Counting caveat.** `logcat -c` does not always flush a pending entry, so
  > a launch can inherit a stale line and report 2 where the plugin made a
  > single attempt. Trust the per-launch count only when it is corroborated by
  > the `ui invocation is needed` line (one chooser = one attempt); the raw
  > logcat is the tie-breaker.
- Suppression **must not break Drive sync**: the explicit sync/restore paths
  restore the account first (`_ensureSessionForDrive`). A suppressed launch that
  then reports `skippedNotSignedIn` on a manual Sync is a failure.
- **Only a user-initiated Drive action may reach `_ensureSessionForDrive`.**
  The automatic syncs — `SyncController.syncSilently()` (app resume) and the
  Home screen's "sync on open" — must not re-establish the session, or the
  chooser returns on every cold launch even though `AuthNotifier.build`
  skipped its own call. `syncNow` carries a `userInitiated` flag; the Sync
  button, pull-to-refresh and a "Sync now" insight pass `true`, everything
  automatic does not. Regression-covered in `auth_session_test.dart` ("an
  automatic sync does not re-establish the session" / "an explicit sync
  re-establishes the session before touching Drive").
- The restore is **single-flight across `AuthNotifier` rebuilds**;
  `container.invalidate(authProvider)` must not produce a second attempt.
- A `null`/throwing silent result **keeps** the cached session — a transient
  refusal is never a silent sign-out. Both branches are regression-covered in
  `auth_session_test.dart` ("a null silent result keeps the cached session" and
  "a throwing silent restore keeps the cached session").
- Silent restore failure → no crash, no error UI.
- Both restore entry points obey the precondition: `AuthNotifier.build` **and**
  the headless `backgroundSyncDispatcher` (a backup job with nothing to back up
  when signed out) check the persisted session before attempting.
- **Restore semantics:** Drive restore runs only when the local places list is
  **empty and a backup exists** (`SyncRepository`); non-empty local data is
  **never** overwritten silently.

### 2.2 Sign-out

**Constraint.** **Sign-out keeps all local data** (offline-first, zero data
loss, documented in the README). `AuthNotifier.signOut()` clears only:

- the Google account/remote session (`authService.signOut()`),
- the local auth snapshot (`saveAuthSession(null)`),
- in-memory auth state → `AsyncValue.data(null)`.

It must **not** clear `placesBox` or user content in `settingsBox`.

**Eval.**

- `AuthNotifier.signOut()` contains no `placesRepository`/`box.clear()` calls.
- A future "wipe everything" feature (if ever requested) is a **separate,
  explicitly-confirmed** action — it is not sign-out.

### 2.3 Secrets & release hygiene

**Constraint.** No tokens, API keys or OAuth secrets in the app or its release
output. OAuth *client IDs* are public identifiers (fine in source); the client
*secret* never exists in the app.

**Eval.**

- Gemini key: `String.fromEnvironment` only; header `x-goog-api-key`, never a
  URL query parameter; never logged (opaque errors + `kDebugMode` gates).
- `AppLogger` redacts keys/tokens/emails and truncates entries before writing
  `app_logs.txt`; that file must never contain Gemini keys, bearer tokens, or
  Google OAuth secrets (regression-tested in `app_logger_test.dart`).
- `gemini_client_test.dart` includes regression tests that assert the key
  appears in the request **header** and **not** in the URL, and that transport
  errors stay opaque.
- Release scan: build artifacts must not contain `GEMINI_API_KEY` values,
  tokens, or coordinates of user places beyond what the user explicitly shares.

### 2.4 Locked / hidden places (local_auth)

**Constraint.** `BiometricService` (`lib/src/services/biometric_service.dart`)
is the **only** file touching `local_auth`. `isAvailable()` and
`authenticate(reason:)` degrade to `false` (never throw). Auth is adaptive
(`biometricOnly: false`), so the system may fall back to the device PIN /
pattern / password. Locked places (`Place.isLocked`) stay in the Home list
but **masked** (title / notes / coordinates replaced by placeholder bars);
their real content is revealed only after a successful biometric /
device-credential prompt (hidden vault, place detail, actions sheet).

**Fallback.** When the device cannot verify identity at all (no biometrics
**and** no screen lock — e.g. an emulator), every locked-location gate is
allowed through with a warning (`noDeviceSecurityWarning`,
`allowWhenUnavailable: true` in `ensureUnlocked`). This prevents deadlocks
where the user can lock a place but never unlock it. There is exactly one
escape hatch; do not silently reveal locked content on any other path.

**Eval.**

- No `LocalAuthentication()` instantiation outside `BiometricService`.
- No locked place content is rendered or navigable without a successful
  `authenticate()` in the same flow.
- Every auth failure falls back to "still hidden", not to "revealed".
- The only exception is the no-security fallback above, which must show the
  warning string and must not be added on rows that are *not* locked.

---

## 3. Location parsing accuracy

**Constraint.** `LocationParser` (`lib/src/services/location_parser.dart`) is
the single extractor for map links, share intents and pasted text. Canonical
patterns (all range-checked before returning; `parse()` is pure/sync):

| Pattern | Example |
| --- | --- |
| Raw pair `lat, lng` (`,` or `;`, optional sign) | `30.0444, 31.2357` |
| `@lat,lng` view anchor | `https://maps.google.com/?q=...@30.0459,31.2243,17z` |
| `/maps/place/lat,lng` | `…/maps/place/30.0459,31.2243` |
| Query params `q\|query\|ll\|sll\|daddr\|saddr\|destination\|center` | `?q=30.0459,31.2243` |
| `geo:` URIs | `geo:30.0459,31.2243` |
| Loose decimal pair anywhere in text (decimals required) | `Cairo Tower 30.0459, 31.2243` |
| Place name `/maps/place/<name>/` | `…/maps/place/Cairo+Tower/` |
| Short links `maps.app.goo.gl`, `goo.gl/maps`, `g.co/kgs` | resolved over network via `resolveShortLink`, failures tolerated |

Parsing is lenient (first match wins) but **safe**: out-of-range latitude
(±90) / longitude (±180) is rejected; custom coordinates in the add screen are
validated; parse failures are logged as anonymous health events — the Hive
health log never stores raw input or coordinates, and nothing is sent to the
cloud. The only place raw parse input may appear is the bounded, redacted
`app_logs.txt` device file (`AppLogger`), which the Supervisor Agent uses to
reproduce regex edge cases; it never leaves the device except through an
explicit developer export.

**Eval.**

- `test/location_parser_test.dart` covers every row above (URL forms, `geo:`,
  raw pairs, loose pairs, short-link resolution with a mock, garbage input,
  range rejection).
- A new extraction pattern requires: the regex in `LocationParser` **and** a
  unit test; if user-visible, the ARB string too.
- `parseLocationLink` (agent tool) returns `{success, latitude, longitude,
  name?}` only for valid parses; anonymous metrics remain aggregate counts
  only (never names, ids, or coordinates).

---

## 4. Automated UI/UX quality checks

### 4.1 Dark mode compliance

**Constraint.** Material 3; `AppTheme.light()` and `AppTheme.dark()` are both
built from `ColorScheme.fromSeed(seedColor: Color(0xFF1B6C4A),
brightness: …)`; `themeModeProvider` (system/light/dark) is persisted as
`theme_mode`. Widgets derive every color from the theme.

**Eval.**

- Widget files contain **no hardcoded `Colors.white|black|grey`-style values**
  for text/surfaces. Sole allowlist: `qr_code_dialog.dart` paints a
  `Colors.white` canvas for QR scannability.
- All text/backgrounds come from `Theme.of(context).colorScheme`
  (`onSurface`, `onSurfaceVariant`, `surface`, `primary`, `outlineVariant`, …).
- Every changed screen is rendered (or widget-tested) in `ThemeMode.dark` and
  `ThemeMode.light`; contrast must not rely on a single brightness.
- New theme tokens belong in `AppTheme`, not scattered across widgets.

### 4.2 RTL support

**Constraint.** Arabic is in `supportedLocales` (`AppLocalizations.
supportedLocales`); direction flows from the locale via MaterialApp, and
widgets must be direction-agnostic.

**Eval.**

- Layout uses directional APIs: `EdgeInsetsDirectional` /
  `paddingDirectional`, `textDirection`-aware alignment, `Row` order that
  mirrors automatically.
- No `EdgeInsets.only(left:…)` / `.only(right:…)` or
  `Alignment.centerLeft/centerRight` for layout in `lib/`; each match is a
  failure (fix with directional equivalents).
- Directional icons (arrows, chevrons, back) are chosen/rendered so they flip
  under `Directionality`; no manual `Transform.flip` hacks.
- No fixed-width crops that clip long Arabic strings; text scales and wraps.
- String interpolation uses ARB placeholders, never concatenated translated
  fragments (mixes LTR/RTL incorrectly).

---

## 5. On-device motion analytics (offload & privacy)

**Constraint.** `lib/src/core/sensors/gravity_alignment_calculator.dart` plus
`lib/src/features/motion_analytics/{domain,data}` classify driving maneuvers
(hard brake, hard accel, sharp turn, speed bump, pothole, smooth drive) from the
shared accelerometer feed. Inference is offloaded off the platform thread, and
nothing about it leaves the device.

**Eval.**

- **Inference never runs on the platform thread.** The shipped path is
  `IsolateMotionInferenceRunner` (a persistent worker isolate); the isolate entry
  point is a top-level function marked `@pragma('vm:entry-point')` so release
  AOT does not tree-shake it. `InlineMotionInferenceRunner` is test-only.
- **A TFLite model can be dropped in without touching downstream code.** The
  classifier depends on the `MotionModel` interface (input `[1,128,3]`
  gravity-free `float32` in `[lateral, vertical, longitudinal]` order; shared
  `decodeMotionScores` for output), not on a concrete model. No fabricated
  weights ship: today's model is `HeuristicMotionModel`, a deterministic
  threshold classifier with documented physical thresholds.
- **Alignment is honest.** `GravityAlignmentCalculator` publishes no frame until
  its health gates pass (sample count, physical gravity band, observable
  heading); a phone pointed along gravity reports "not aligned" rather than
  inventing a heading, and callers must fall back. Gravity is learned only while
  the device is stationary, so a maneuver can never re-train the frame.
- **Sign conventions are consistent and tested.** Right-handed vehicle frame;
  `Z_car` accel `>0` / brake `<0`, `X_car` left `>0` / right `<0`, `Y_car` bump
  `>0` / pothole `<0`.
- **Fusion keeps the existing taxonomy stable.** New `DrivingEventType` values
  are **appended** (indices of `harshAcceleration`/`harshBraking` unchanged);
  every new kind has a localized label (`app_en.arb` + `app_ar.arb`) and a
  distinct icon in `driving_events_card.dart` — no kind may fall through to
  another kind's label.
- **Privacy.** Events carry kind + magnitude + timestamp only; no place names,
  notes or coordinates reach logs, analytics or the classifier.
- **A maneuver may be drawn on the map without gaining a location.** The map
  overlay needs a position per event, but `MotionEvent`/`DrivingEvent` must stay
  coordinate-free, and `DrivingEventsNotifier` mirrors every event into the
  health log. The pairing therefore lives in a **separate, transient** derivation
  (`DrivingEventLocator` → `locatedDrivingEventsProvider`): the event keeps no
  coordinate, the position is borrowed from the **route vertex nearest its
  timestamp**, and the result is held in memory only — never persisted, never
  logged, never sent anywhere. A maneuver further than
  `DrivingEventLocator.maxPlacementGap` (30 s) from any vertex is **dropped, not
  misplaced**; a vertex without a timestamp cannot host a marker. Never add a
  coordinate field to `DrivingEvent`/`MotionEvent` to simplify the overlay.
- **Presentation is declared once.** Icon, warning tone and localized label for a
  `DrivingEventType` live only in `driving_event_presentation.dart`; the card,
  the map markers and the summary sheet all read from it, so no kind can fall
  through to another kind's label in one surface while being correct in another.
  `test/motion_score_test.dart` and `test/motion_overlay_test.dart` pin this.
- **The map overlay is derived state, not new storage.** `locatedDrivingEventsProvider`
  and `motionScoreProvider` watch `drivingEventsProvider` and
  `autoMotionFixesProvider`; neither adds a Hive key, and both empty the moment
  `DrivingEventsNotifier.clear()` runs at the start of a new trip.
- **Isolate plumbing is failure-tolerant.** Spawn failure, worker death, error or
  timeout degrades to "no events" and respawns on the next window; window
  buffering, hop cadence, per-kind cooldown and start/stop/dispose are covered by
  `test/ml_classifier_isolate_test.dart`, including a real-isolate path.
- **Every channel and port is released on the way out.** A `ReceivePort`'s
  `listen` subscription is stored and cancelled *before* the port is closed, or
  the reference outlives the port; the worker's own `ReceivePort` is released by
  sending it a graceful shutdown message before `Isolate.kill`, not by killing it
  mid-listen. `IsolateMotionInferenceRunner.dispose` is idempotent, fails pending
  completers, drops the worker and closes every port.
- **Process-wide hooks are removed on dispose.** `SchedulerBinding
  .addTimingsCallback` registers for the lifetime of the *binding*, not the
  widget: the callback must be held in a field and handed to
  `removeTimingsCallback` in `dispose()`, otherwise it keeps the state object and
  its monitor reachable and keeps firing after the widget is gone.
- **Shared hubs are closed, not just parked.** `MotionSensorHub.dispose` cancels
  the native subscription *and* closes both broadcast controllers, so a later
  `start()` cannot revive a hub the container already dropped. Covered by
  `test/resource_leak_audit_test.dart`.

---

## 6. Adaptive engine: gating, session security & adaptive memory

**Constraint.** `lib/src/core/orchestrator/adaptive_engine_orchestrator.dart`,
`lib/src/core/motion/{activity_state_manager,motion_gate}.dart`,
`lib/src/core/security/session_guard.dart` and `lib/src/core/memory/` form the
central, offline "adaptive engine": one FSM decides what the expensive
subsystems should do, an activity gate keeps them off while the user is
stationary or walking, a session guard owns how long the encrypted vault may
stay unlocked, and an encrypted profile box remembers anonymous per-device
numbers. All of it is pure Dart over injected clocks and stores — no telemetry,
no network, no PII.

**Eval.**

- **One authority per decision.** The orchestrator is the single place that maps
  evidence (`ActivityState`, speed, fix age) to an `EngineProfile`. Subsystems
  read the profile; they do not each re-derive "am I needed". `EngineProfile` is
  declarative (interval, distance filter, flags), so the FSM is testable with no
  sensor, GPS, isolate or Hive.
- **The gate runs *in front of* the pipeline, not inside it.** While the state
  is not a confirmed vehicle, `MotionGate.gated` forwards **zero** samples, so
  `MotionBehaviorAnalyzer` and `MLClassifierIsolate` never see a sample — no ring
  buffer, no gravity EMA, no isolate request. A boolean check inside the analyzer
  is *not* sufficient (it would still pay per-sample costs) and is a review
  failure. `test/motion_gate_test.dart` asserts `forwardedSamples == 0` for a
  walking feed.
- **The profile owns the location stream too, and idle really pauses it.**
  `EngineProfile` carries `locationPaused` and `accuracy` alongside the interval
  and distance filter, and `applyEngineProfile` in `app_providers.dart` is the
  single place that translates a profile into `applySampling` for **both** daily
  trackers. `EngineState.idleStandby` sets `locationPaused: true`, which cancels
  the platform position subscription outright — a stream open at *any* cadence
  keeps the fused provider (and the GNSS receiver) awake, which the OS reports to
  the user as "frequently checks your location". Merely stretching the interval
  is not enough and is a review failure. `ActiveDriveAnalytics` is the **only**
  state that asks for `LocationAccuracy.high` with a 5 m filter and passes
  `transportSpeed: true`; a hardcoded `transportSpeed` flag (which grants
  GPS-grade fixes while parked) must never return. Idle is a 10-minute / 200 m /
  `lowest` safety net behind the pause, not the mechanism. The session survives a
  pause — distance, max speed, the last fix and the outage window all persist, so
  resuming re-opens the stream without restarting the trip. Covered by
  `test/engine_profile_application_test.dart` and the pause cases in
  `test/gps_tracker_test.dart`.
- **The FSM stream is not the only way a profile reaches a tracker.** The
  orchestrator emits on *state change*, so a tracker that starts while the
  machine is already `idleStandby` receives no transition and would open a live
  GPS-grade stream. Every start path must therefore apply the orchestrator's
  **current** `profile` (the getter), never wait for an emission. The transport
  classifier's `SamplingProfile` is **evidence, not an authority**: feeding it
  straight into `applySampling` (with no `paused` argument) silently re-opens an
  idle stream on every classifier tick, which on a real device shows up as a
  `HIGH_ACCURACY, minUpdateInterval=0, hiddenFromAppOps` fused registration that
  never goes away. Only `applyEngineProfile` may call `applySampling`, and both
  controllers must `observe(trackingActive: true)` on start and `suspend()` on
  stop so the FSM is never stale. Verified on device with
  `adb shell dumpsys location` / `cmd appops get … MONITOR_HIGH_POWER_LOCATION`:
  the `(running)` flag and the fused request must be absent once the app is
  backgrounded while idle.
- **One OS location client, owned by `LocationHub`.** `getPositionStream` is
  never called by a feature. Android registers the app as a separate location
  client for **every** open request, so each extra Dart subscription is another
  `WorkSource` entry and another reason to keep the receiver awake. All
  consumers (both daily trackers, the Qibla compass) acquire the app-wide
  `LocationHub` (`lib/src/services/location_hub.dart`, provider
  `locationHubProvider`); it opens **exactly one** platform subscription,
  reference-counts its consumers, serves the **strongest** tier any of them
  wants, and re-opens that single handle only when the resolved tier changes —
  replacing, never stacking. `release`/`pauseAll` cancel the handle outright the
  moment the last consumer leaves, which is the state `idleStandby` requires.
  The handle's registration is **synchronous** with `acquire`/`release` (the
  platform cancel is the only awaited part), so there is never a window where
  the app reads "active" with no consumer, or "paused" with a live client. A
  hub subscription must be *released*, not merely cancelled: cancelling the
  listener alone leaves the app registered. A consumer's **cadence** is part of
  its request (`interval`/`distanceFilter`), never left to the 5 s default:
  opening the shared handle without the profile's interval leaves Android
  holding a `@+5s0ms` request that no engine wanted. Covered by
  `test/location_hub_test.dart`.
- **Entering the vehicle state is strict; leaving it is slow.** Vehicle requires
  speed above 15 km/h **and** held (5 s continuous, gap-tolerant) vehicle-range
  vibration **and** step-cadence rejection (0.5–3 Hz band power share). Leaving
  requires 2 minutes of consistent pedestrian/still evidence, so a red light
  never stops analysis. Speed is compared in **m/s**, never through a km/h
  round-trip (`15 / 3.6 * 3.6 != 15.0` in binary floating point).
- **Session security is one owner.** `SessionGuard` is the only decider of when
  the vault must re-prompt (OS device lock, background grace, inactivity,
  surface-idle short clock, explicit end). Its token is **opaque and random** —
  never an account id, email or place — and token-store I/O is best-effort and
  **not awaited** by `beginSession`/`endSession`, so a keystore that never answers
  can never hang an unlock or a lock. The vault's `lock()` ends the session
  *before* its first `await`, because it is called from widget `dispose` and
  reading `ref` after an async gap throws `UnmountedRefException`
  (regression-covered).
- **The device lock is stricter than backgrounding.** An OS device-lock event
  (`AppLifecycleState.hidden` on Android) ends the session **immediately**, with
  no grace period, via `onDeviceLocked()`; a plain background (home button, app
  switch, `paused`) only starts the background grace clock. Both are routed
  through the same `sessionEnds` stream, so there is exactly one vault-lock path.
  `lockOnDeviceLock` is user-configurable and defaults to on.
- **The inactivity window is configurable and clamped.** `inactivityTimeout`
  comes from `settingsBox` key `session_timeout_minutes`
  (`SettingsRepository.sessionTimeoutMinutes`) and must be one of
  `SessionGuard.selectableInactivityMinutes`; a hand-edited or corrupt box value
  degrades to the 15-minute default rather than to an instantly-locking vault.
  `setInactivityTimeout` applies live — the next `tick` uses the new value.
  `sessionGuardProvider` reads the settings **best-effort** (a container without a
  Hive box gets the safe defaults instead of a poisoned provider), because the
  guard sits on the vault's critical path.
- **Hand-held vs surface-idle is measured, not proxied.**
  `DeviceLockDetector` judges orientation drift (a slow low-pass of the gravity
  vector) plus a residual-motion gate from the accelerometer, and publishes the
  verdict on `contextChanges` **only when it actually changes**. It is the only
  source of the guard's `observeMovement` boolean; a stopped or absent sensor
  leaves the verdict `unknown`, which the guard treats as hand-held (the longer
  clock), so a broken sensor can never lock a session early. The privacy dimmer
  renders strictly from `ColorScheme` and treats `unknown` as hand-held — it must
  never cover content on a guess.
- **Adaptive memory is fail-safe.** `AdaptiveProfile` holds **only numeric
  scalars** (baselines, thresholds, counters) — nothing that could identify a
  user or a place. It lives in its own AES-256 box (`adaptive_profile`) with its
  **own key**, separate from the vault (which is biometric-gated) and from
  `places`/`settings` (no schema change). Every failure — no keystore, corrupt
  box, malformed record — degrades to `AdaptiveProfile.defaults`; a tuning file
  must never disable classification. Adapted thresholds never fall below the
  documented physical minima.
- **Diagnostics stay local.** `SelfDiagnosticMonitor` tracks frame pacing, RSS
  and background time through an injected reader; a throwing reader is swallowed.
  Its snapshot carries numbers and coarse enum names only and is written solely
  to the local health log — no telemetry, no analytics upload, no network.
- **Tests.** `test/adaptive_engine_orchestrator_test.dart`,
  `test/activity_state_manager_test.dart`, `test/motion_gate_test.dart`,
  `test/session_guard_test.dart`, `test/device_lock_detector_test.dart`,
  `test/vault_privacy_dimmer_test.dart` and `test/adaptive_memory_test.dart` cover
  the state transitions, boundary values, inability to open on ambiguous evidence,
  step rejection, auto-standby timing, session expiry paths, device-lock
  immediacy, configurable-timeout clamping and profile degradation.

---

## Reporting

When an agent completes a change, report:

```
Verification gate: analyze [pass/fail], tests [pass/fail]
1 Architecture & data integrity .... pass/fail
2 Data security & auth ............. pass/fail
3 Location parsing accuracy ........ pass/fail
4 UI/UX (dark mode, RTL) ........... pass/fail
5 On-device motion analytics ....... pass/fail
6 Adaptive engine (gate/security) ... pass/fail
```

Each failure must cite the file/line and the standard violated, and be fixed
before the change is considered complete.