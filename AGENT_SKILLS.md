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
`homeShortcutServiceProvider`, `authServiceProvider`, `driveServiceProvider`,
`syncRepositoryProvider`, `backgroundSyncSchedulerProvider`,
`appHealthLoggerProvider`, `appObserverServiceProvider`,
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
`authenticate(reason:)` degrade to `false` (never throw). Locked places
(`Place.isLocked`) are excluded from the Home list and their coordinates/notes
are revealed only after a successful biometric / device-credential prompt
(hidden vault, place detail, actions sheet).

**Eval.**

- No `LocalAuthentication()` instantiation outside `BiometricService`.
- No locked place content is rendered or navigable without a successful
  `authenticate()` in the same flow.
- Every auth failure falls back to "still hidden", not to "revealed".

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

## Reporting

When an agent completes a change, report:

```
Verification gate: analyze [pass/fail], tests [pass/fail]
1 Architecture & data integrity .... pass/fail
2 Data security & auth ............. pass/fail
3 Location parsing accuracy ........ pass/fail
4 UI/UX (dark mode, RTL) ........... pass/fail
```

Each failure must cite the file/line and the standard violated, and be fixed
before the change is considered complete.