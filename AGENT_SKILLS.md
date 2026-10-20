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

**Eval.**

- `signInSilently` is used **only** as the app-level method name on
  `AuthService`/`GoogleAuthService` — never as a `GoogleSignIn` instance
  method.
- Silent restore failure → signed-out state, no crash, no error UI.
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
- **Isolate plumbing is failure-tolerant.** Spawn failure, worker death, error or
  timeout degrades to "no events" and respawns on the next window; window
  buffering, hop cadence, per-kind cooldown and start/stop/dispose are covered by
  `test/ml_classifier_isolate_test.dart`, including a real-isolate path.

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