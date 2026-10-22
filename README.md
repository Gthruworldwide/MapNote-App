# MapNote

**Save your favourite places offline. Sync them to your private Google Drive.**

MapNote is an **offline-first, zero-backend** Flutter app for Android and iOS.
It saves GPS locations locally on the device (Hive), backs them up to the user's
*private* Google Drive app-data folder, and delegates turn-by-turn navigation to
Google Maps or Waze via deep links.

No custom server, no database to operate — your data is yours. Firebase is used
only for anonymous crash and usage telemetry, never for your places.

---

## Table of contents

- [Overview](#overview)
- [Design principles (strict rules)](#design-principles-strict-rules)
- [Zero-backend architecture (Google Drive sync)](#zero-backend-architecture-google-drive-sync)
- [Features](#features)
- [User flow](#user-flow)
- [Tech stack](#tech-stack)
- [How sync works](#how-sync-works)
- [Monitoring & recommendation agent (Smart Insights)](#monitoring--recommendation-agent-smart-insights)
- [Telemetry & crash reporting (Firebase)](#telemetry--crash-reporting-firebase)
- [Backup format](#backup-format)
- [Project structure](#project-structure)
- [Getting started](#getting-started)
- [Configuration reference](#configuration-reference)
- [Localization](#localization)
- [Quality gates](#quality-gates)
- [Platform configuration](#platform-configuration)
- [Distributing to testers (Firebase App Distribution)](#distributing-to-testers-firebase-app-distribution)
- [Roadmap](#roadmap)
- [License](#license)

---

## Overview

MapNote solves a simple problem: remembering places (a parking spot, a trailhead,
a friend's building) without depending on a third-party account or a backend you
have to pay for and maintain.

- **Local-first.** Every place lives on the device in a Hive database. The app is
  fully usable with no network and no sign-in.
- **Private cloud backup.** Optional Google Sign-In grants exactly one scope,
  `drive.appdata`, which exposes only the app's *own hidden* Drive folder. The
  user's documents, photos, and other Drive files are never visible to the app.
- **Zero backend.** There is no server to host, no auth server, and no database to
  operate. OAuth happens directly between the app and Google; the backup is a
  single JSON file in the user's Drive. Anonymous crash reports and usage
  analytics (Firebase) are the only telemetry, and they never include your places.
- **Bilingual.** Full English / Arabic UI, no hardcoded strings.

## Design principles (strict rules)

These are non-negotiable constraints for the project:

1. **Zero external backend.** No Firebase, AWS, or any custom backend servers for
   database storage. Firebase is used *only* for anonymous crash/usage telemetry
   (see [Telemetry & crash reporting](#telemetry--crash-reporting-firebase)).
2. **Offline-first.** All data is saved locally on the device using a fast local
   database (`Hive`). The app is fully functional with no network.
3. **Cloud sync, the "WhatsApp model".** Backup and cross-device sync serialise
   the local database into a JSON file that is synced silently to the user's
   Google Drive, using the hidden `drive.appdata` scope for app-specific
   storage. There is no bespoke sync service.
4. **Bilingual by construction.** The UI supports **Arabic (`ar`)** and
   **English (`en`)** natively via `flutter_localizations` and `.arb` files. UI
   strings are never hardcoded.
5. **Navigation is delegated.** The app ships no turn-by-turn navigation engine;
   it sends coordinates to Google Maps or Waze through intents / deep links
   (`url_launcher`).

## Zero-backend architecture (Google Drive sync)

The app is a self-contained client. The only external service is Google (OAuth +
Drive API), and it is used purely as a personal, private file store.

```
┌────────────────────────────── Flutter app (device) ──────────────────────────────┐
│                                                                                   │
│  UI: Home · Add Place · Place Detail · Settings        (plain Navigator)          │
│        │                                                                          │
│        ▼                                                                          │
│  Riverpod 3 state (Notifier / AsyncNotifier / FutureProvider)                      │
│        │                                                                          │
│        ▼                                                                          │
│  Repositories:  PlaceRepository            SyncRepository                         │
│        │                 │                       │                                │
│        ▼                 ▼                       ▼                                │
│  PlaceLocalDataSource   Hive CE boxes      DriveService (googleapis v3)            │
│  (JSON maps)            places/settings    _AuthenticatedClient (http.BaseClient)  │
│                                                  │                                │
└──────────────────────────────────────────────────┼───────────────────────────────┘
                                                   │ Bearer token
                                                   ▼
                                    Google OAuth 2.0  +  Drive API
                                    scope: drive.appdata (appDataFolder only)
                                                   │
                                                   ▼
                                    routenote_backup.json (hidden app folder)
```

There is **no** application server, API gateway, or database host. The "backend"
is the operating system's local storage plus the user's own Google Drive.

## Features

- 📍 Save the current GPS location with a name and notes.
- 📋 **Paste a location** from the clipboard — Google Maps links (full and
  short), `geo:` URIs, and raw `lat, lng` pairs are parsed automatically.
- ✏️ **Custom coordinates** — switch to a manual latitude/longitude entry with
  range validation instead of using the current GPS fix.
- 🔗 **Share target** — share a place from Google Maps / WhatsApp / a browser
  and MapNote opens the save screen pre-filled.
- 💾 Fully offline-first — all data lives in a local Hive database.
- ☁️ One-tap backup/sync to the user's **private** Google Drive app-data folder.
- 🔒 Only the `drive.appdata` scope is ever requested.
- 🔁 Automatic sync on app open (once signed in), on app resume (throttled), and a
  24-hour periodic background backup aligned to midnight.
- ♻️ Automatic restore on a fresh device: when the local database is empty and a
  backup exists, it is pulled down automatically.
- 🧭 Navigation delegated to Google Maps / Waze via deep links — no in-app maps.
- 🌐 Arabic / English UI (`flutter_localizations` + ARB files).
- 🌗 Light & dark themes.
- 🛰️ **Daily GPS tracking** — an optional toggle that records today's distance
  and max speed in the foreground *and background* (a location foreground service
  keeps the stream alive once tracking is switched on).
- 🚶 **AutoMotion** — an independent daily motion tracker with a custom
  electric-blue/mint status badge; when paused, the Home card stays visible with
  today's recorded totals. Tapping the card opens an **AutoMotion dashboard**
  with a live driver-mode speed readout and a trip history of recorded days.
- 🤖 **Smart Insights** — a privacy-first monitoring & recommendation agent that
  watches local app health (lifecycle, sync failures, location-parsing failures,
  UI latency) and the shape of the user's data, then suggests tidy-ups, sync
  reminders and optimisations. Works fully offline with a local rule engine; an
  optional Google Gemini layer adds localized tips when a key is configured.
- 🔐 **Encrypted Saved Places vault** — move a place into a biometric-gated,
  AES-256 encrypted Hive box (`secure_places`) that stays unreadable while the
  vault is locked. The key lives in the device keystore, never in the app, and
  is dropped as soon as you leave the vault screen. A device with no lock screen
  at all still gets in — with an explicit warning, never silently.
- 🧩 **Geofenced place suggestions** — today's trip stops where you dwelled for
  more than five minutes are matched against your saved places, so the matched
  place can be opened (or the stop saved) in one tap. Purely derived on-device:
  nothing is stored, and no name, note or coordinate leaves the device.
- 📈 **Crash & usage telemetry** — best-effort Firebase Crashlytics + Analytics so
  crashes are fixed before testers hit them (anonymous; never your places).

## User flow

1. **Capture location (one tap).** The user opens the app and presses the FAB.
   The app grabs the exact GPS coordinates; the user adds a **Name** and
   **Notes**, and the place is saved to the local database.
   - **Or save a location you are not at.** Use **Custom coordinates** to type
     latitude/longitude, **Paste location from clipboard** to import a map link
     or a `lat, lng` pair, or **share** a place from another app.
2. **Search & retrieve.** Saved places are listed newest-first and can be
   filtered with the search bar.
3. **Navigate.** Tapping a place opens its detail screen; **Navigate** hands the
   coordinates to Google Maps (or Waze) for routing.
4. **Auto-sync.** On sign-in / app open / resume, the local JSON overrides the
   Google Drive JSON backup.
5. **Restore.** Signing in on a new device (with an empty local database) fetches
   the JSON from Drive and populates the local database.

## Tech stack

| Concern | Choice |
| --- | --- |
| Framework | Flutter 3.44+ (stable) / Dart 3.12 |
| State management | `flutter_riverpod` 3.x (`Notifier`, `AsyncNotifier`) |
| Local storage | `hive_ce` + `hive_ce_flutter` (JSON maps, no codegen adapter) |
| Google sign-in | `google_sign_in` 7.x new API (`authenticate(scopeHint:)`) |
| Drive API | `googleapis` Drive v3 with a custom `http.BaseClient` injecting the Bearer token |
| HTTP | `http` |
| Background work | `workmanager` 24h periodic task (`ExistingPeriodicWorkPolicy.update`) |
| Recommendations | Local rule engine (always on) + optional Google Gemini via `http` (`--dart-define=GEMINI_API_KEY`) |
| Location | `geolocator` |
| Compass & Qibla | `flutter_compass` (magnetometer heading) + `geomag` (WMM-2020 magnetic declination → true north) |
| Deep links | `url_launcher` (Google Maps, `geo`, `google.navigation`, Waze, `https`) |
| Share target | `receive_sharing_intent` (text/links shared into the app) |
| Localization | `flutter_localizations` + `intl` + ARB (`app_en.arb`, `app_ar.arb`) |
| IDs | `uuid` |
| Icons | `flutter_launcher_icons` (Figma "Location Notebook" pin; light/dark masters + glyph + monochrome) |
| Branding | Vector lockup in `assets/brand/` (two SVGs: pin `route_note_mark`, two-tone `route_note_wordmark`) → animated cold-start splash + static About card; built by `tool/gen_brand_logo.ps1` |
| Routing | Plain `Navigator` (no `go_router`) |
| Telemetry | `firebase_core` + `firebase_crashlytics` + `firebase_analytics` (Firebase BoM 35.0.0) |
| Tester distribution | Firebase App Distribution (`firebase appdistribution:distribute`) |

## How sync works

The device copy is **always the source of truth**; the Drive file is only a
backup. This is a deliberate "device wins" policy (chosen over timestamp merging
to avoid conflict resolution complexity).

`SyncRepository.syncNow()`:

1. If local data is **non-empty** → upload it, overwriting
   `routenote_backup.json` in Drive.
2. If local data is **empty** and a backup exists → download and restore it into
   the local database (used when installing on a new phone).
3. If not signed in → the sync is skipped silently.

> **Signing out does not delete your places.** Sign-out only clears the Google
> session from the device; saved locations stay in the local Hive database
> (offline-first, zero data loss). A later sign-in keeps the local data as the
> source of truth; restore only happens on a device whose database is empty.

Syncs are triggered:

- when a Google session is restored on app open;
- when the app returns to the foreground (`AppLifecycleState.resumed`), throttled
  to at most once per minute;
- by a `workmanager` periodic task every 24 hours, first scheduled for the next
  midnight. The task runs in a separate background isolate and re-initialises
  Hive itself (`backgroundSyncDispatcher`).

A manual **Restore from Google Drive** action is also available in Settings (with
a confirmation dialog).

## Monitoring & recommendation agent (Smart Insights)

MapNote ships a lightweight, privacy-first "AI assistant" that watches the
app's local health and the shape of the user's data, then surfaces contextual
suggestions in a subtle **Smart Insights** card on Home and a **Smart insights**
section in Settings.

```
lib/src/services/
  app_health_logger.dart      # bounded local event/health log (Hive-backed)
  app_observer_service.dart   # sanitized issue-reporting facade over the log
  app_logger.dart             # bounded, redacted app_logs.txt diagnostics feed
  local_insight_engine.dart   # pure, offline rule engine (no network)
  gemini_client.dart          # optional Gemini generateContent client
  agent_service.dart          # facade: local engine + optional cloud layer
```

### What is logged

`AppHealthLogger` keeps a bounded (200-event) ring buffer of app
launch/resume/pause, sync started/succeeded/failed/skipped, place
saved/deleted, location-parse failures (including short-link resolution) and
Home UI latency. Events never leave the device; the agent only consumes
aggregate `HealthSummary` counts.

### What is suggested (local, offline)

| Signal | Suggestion |
| --- | --- |
| Two or more places within ~80 m | Group / rename nearby places |
| Places with no notes | Add details so they are recognisable |
| Repeated sync failures | Possible weak network / retry sync |
| Repeated parse failures | Paste the full Google Maps link |
| Signed in but backup > 7 days old | Back up now |
| 12+ places, none pinned | Pin favourites |
| Very large list | Keep the list tidy |

Insights are dismissible (persisted), prioritised by severity, and capped to the
top three so the card stays subtle.

### Optional cloud layer (Gemini)

The local engine always runs and needs no account. If the app is built with one
or more restricted Gemini keys:

```sh
flutter run \
  --dart-define=GEMINI_API_KEY=primary-key,fallback-key \
  --dart-define=GEMINI_MODEL=gemini-2.0-flash
```

`GEMINI_API_KEY` is a **pool**: comma/semicolon/whitespace separated keys, tried
in order. `KeyRotationService` puts a key that answers `401`, `403`, `429`, or a
`400` `API_KEY_INVALID` on a 10-minute cooldown and retries the request with the
next healthy key, so a single exhausted or revoked key cannot take the cloud
layer offline. Keys are read from the environment only — never committed to the
repository — and are never logged.

For CI/release builds the key lives in the **`GEMINI_API_KEY` GitHub Actions
repository secret** (Settings → Secrets and variables → Actions), which
`.github/workflows/android-release.yml` forwards as a `--dart-define`. Put any
fallback keys in the same secret, comma separated.

…the agent additionally asks Gemini for up to three localized suggestions and
merges them with the local ones. **Only anonymous aggregate metrics** (counts
such as `savedPlaces`, `nearbyClusters`, `recentSyncFailures`, `lastBackupDaysAgo`)
are sent — never place names, notes, ids or coordinates. Cloud AI can be turned
off at any time in **Settings → Smart insights**.

To keep suggestions grounded in real state, the cloud model may call two small
**on-device tools** (executed locally — the model never runs code itself):

- `checkSyncStatus` — reports the real Drive backup timestamp and recent sync
  success/failure/skip counts from the local health log,
- `parseLocationLink` — validates a pasted map link or raw text and returns its
  coordinates.

A tool result is only produced — and only leaves the device — if the model
actually invokes it, which itself only happens while cloud AI is enabled.

## Telemetry & crash reporting (Firebase)

MapNote never sends your places anywhere but your own Google Drive. Firebase is
used only for two *anonymous* operational signals:

| Product | Package | What it does |
| --- | --- | --- |
| **Crashlytics** | `firebase_crashlytics` | Reports uncaught Dart exceptions and native crashes/ANRs with a stack trace so they can be fixed before testers hit them. |
| **Analytics** | `firebase_analytics` | Collects anonymous usage events and session data (sessions, device model, app version). No place names, notes, ids or coordinates are logged. |

How it is wired:

- `lib/main.dart` initialises Firebase once at startup inside a `try/catch`, so an
  offline cold start (or a bad config) can never block the app. Dart errors are
  forwarded to `FirebaseCrashlytics` from `FlutterError.onError` and
  `PlatformDispatcher.instance.onError`.
- The native side is configured by the `com.google.gms.google-services` and
  `com.google.firebase.crashlytics` Gradle plugins plus
  `android/app/google-services.json` (committed — a client config, not a secret).
- The Crashlytics Gradle plugin uploads the release mapping files, so stack traces
  stay readable after R8 minification.
- Debug builds expose a **Test Crash** button (the guide's step 3) that is
  compiled out of release/profile builds; it was used to verify the pipeline
  end-to-end.

> Both collectors default to on. They can be turned off at runtime with
> `setAnalyticsCollectionEnabled(false)` / `setCrashlyticsCollectionEnabled(false)`.
> iOS is not wired to Firebase in this repository (Android only).

## Backup format

A single JSON file (`routenote_backup.json`) in the app-specific Drive folder:

```json
{
  "last_synced": "2026-10-09T12:00:00Z",
  "places": [
    {
      "id": "uuid-v4",
      "name": "Cairo Tower",
      "notes": "Near the Nile",
      "latitude": 30.0444,
      "longitude": 31.2357,
      "timestamp": "2026-10-09T11:00:00Z"
    }
  ]
}
```

## Project structure

```
lib/
  app.dart                         # MaterialApp (l10n, theme, locale) + lifecycle sync
  main.dart                        # bootstrap: Hive init + ProviderScope
  l10n/                            # app_en.arb, app_ar.arb (+ generated/)
  src/
    core/
      config/app_config.dart       # --dart-define OAuth IDs, scope, file/box names
      config/preferred_nav_app.dart
      navigation/app_navigator.dart # global navigator key (share intents)
      theme/app_theme.dart         # light & dark themes
      utils/date_formats.dart
      utils/geo_distance.dart      # shared Haversine distance helper
    data/
      models/                      # Place, BackupData, DailyGpsSummary, AgentInsight
      local/                       # HiveDatabase, PlaceLocalDataSource,
                                   #   SettingsRepository, auto_motion_data_source,
                                   #   gps_daily_data_source
      remote/                      # auth_service, google_auth_service, drive_service
      repositories/                # PlaceRepository, SyncRepository
    services/                      # location, navigation, location_parser,
                                   #   share_intent, background sync scheduler,
                                   #   gps_tracker_service, auto_motion_service,
                                   #   lock_gate, biometric_service,
                                   #   dynamic_icon_service, home_shortcut_service,
                                   #   app_health_logger, app_observer_service,
                                   #   app_logger, local_insight_engine,
                                   #   gemini_client, key_rotation_service,
                                   #   agent_service
    providers/app_providers.dart   # all Riverpod providers & notifiers
    widgets/                       # shared UI: qibla_indicator, motion_metric,
                                   #   track_failure_text
    features/
      home/                        # list + search + AppBar actions + Smart Insights
        widgets/                   # place_card, smart_insights_card,
                                   #   auto_motion_card + auto_motion_badge
      automotion/                  # AutoMotion dashboard: driver mode + trip history
      add_place/                   # GPS or pasted/manual coordinates, name & notes
      place_detail/                # view / navigate / delete
      settings/                    # sign-in, sync, restore, language, theme, agent
                                   #   + hidden_vault_screen (locked places)
      saved_places/                # Clean Architecture encrypted vault
                                   #   (domain/data/presentation): AES-256 Hive
                                   #   box, biometric gate, geofenced suggestions
test/                              # Hive-backed widget tests + parser/share tests (120)
integration_test/app_test.dart     # on-device end-to-end UI flow tests
ios/ShareExtension/                # iOS share-extension templates + README
scripts/run_dev.ps1                # Windows helper: run with real OAuth IDs
scripts/run_integration_tests.ps1  # Windows helper: run the E2E integration tests
scripts/distribute_app.ps1         # Windows helper: upload a release APK to App Distribution
assets/icon/                       # launcher-icon sources (Figma SVG in src/, light/dark
                                   #   1024px masters, glyph + monochrome layers)
assets/brand/                      # MapNote lockup as two SVGs (mark + wordmark),
                                   #   built by tool/gen_brand_logo.ps1 from src/
assets/app_icon_animated.gif       # bundled animated asset
```

## Getting started

### Prerequisites

- **Flutter 3.44+** on the `stable` channel (`flutter --version`).
- **Android Studio** (for the Android SDK) and/or **Xcode** (iOS, macOS only).
- A **Google Cloud project** to create the OAuth clients and enable the Drive API.
- A physical device or emulator/Simulator.

### 1. Clone and install dependencies

```sh
git clone https://github.com/Gthruworldwide/RouteNote-App.git
cd RouteNote-App
flutter pub get
flutter gen-l10n        # runs automatically on build; explicit here is fine
```

### 2. Enable the Google Drive API

In the [Google Cloud Console](https://console.cloud.google.com/):

1. Create or select a project.
2. **APIs & Services → Library → “Google Drive API” → Enable.**

### 3. Create OAuth client IDs

**API & Services → Credentials → Create credentials → OAuth client ID.**

| Client type | Purpose | Feeds |
| --- | --- | --- |
| **Web application** | `serverClientId` used by `google_sign_in` on **Android** | `GOOGLE_SERVER_CLIENT_ID` |
| **Android** | Lets Play Services recognise your app (package + SHA-1) | validation only |
| **iOS** | Client for the iOS app (bundle `com.routenote.routenote`) | `GOOGLE_IOS_CLIENT_ID` |

- **Android:** add your signing SHA-1 (`keytool -list -v -keystore ...`) under an
  *Android* OAuth client with package name `com.routenote.routenote`. You can add
  multiple fingerprints (debug **and** release).
- **iOS:** create an *iOS* client with bundle ID `com.routenote.routenote`. The
  reversed client ID
  (`com.googleusercontent.apps.<ios-client-id>`) must be added to
  `ios/Runner/Info.plist` under `CFBundleURLTypes` (see
  [Platform configuration](#platform-configuration)).

> The app requests **only** `https://www.googleapis.com/auth/drive.appdata`.

#### OAuth consent screen (one-time)

1. **APIs & Services → OAuth consent screen.**
2. User type **External** (an “Internal” app only works inside a Workspace you own).
3. **Scopes:** add `https://www.googleapis.com/auth/drive.appdata` (use *Add
   manually* if it is not in the picker).
4. **Test users:** add your Google account(s). While the app is in **Testing**
   status, only these accounts can authorise — enough for personal/MVP use.
5. Publish only when you want to open sign-in to everyone. `drive.appdata` is a
   sensitive scope, so external users may trigger a verification review; as the
   project owner/test user you can authorise without waiting.

### 4. Run

```sh
# Android or iOS — the same client IDs are compiled in for both.
flutter run \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com \
  --dart-define=GOOGLE_IOS_CLIENT_ID=yyyy.apps.googleusercontent.com
```

> Without these defines the app still builds and runs fully offline — Google
> sign-in is simply unavailable until real client IDs are supplied.

On Windows there is a helper script (client IDs are public identifiers, not
secrets):

```powershell
.\scripts\run_dev.ps1
# or target a device explicitly:
.\scripts\run_dev.ps1 -d <device-id>
```

### 5. Build for release

The Android release build is signed with an **upload keystore** that is not
part of the repository. Create it once per machine before the first release
build:

```sh
# Generates android/app/upload-keystore.jks (alias "upload") and the
# gitignored android/key.properties that points at it.
powershell -ExecutionPolicy Bypass -File tool\create_upload_keystore.ps1
```

> **Back the keystore up outside the repository.** `key.properties` and
> `*.jks` are git-ignored, so the key is never shared through git — which also
> means losing it locks you out of Play updates under the same signing
> identity.

Without `android/key.properties` the release build still works, but it falls
back to the **debug** key and logs a warning; such a bundle is rejected by
Play. `android/app/build.gradle.kts` reads the file at configuration time and
binds it to `signingConfigs.release`.

```sh
# Android
flutter build apk     --release --dart-define=GOOGLE_SERVER_CLIENT_ID=... --dart-define=GOOGLE_IOS_CLIENT_ID=...
flutter build appbundle --release --dart-define=GOOGLE_SERVER_CLIENT_ID=... --dart-define=GOOGLE_IOS_CLIENT_ID=...

# Obfuscated release bundle with the symbols kept out of the artifact
# (upload build/app/outputs/symbols to Crashlytics so Dart stack traces
# can be deobfuscated):
flutter build appbundle --release --obfuscate --split-debug-info=build/app/outputs/symbols

# iOS (requires macOS + Xcode)
flutter build ios      --release --dart-define=GOOGLE_SERVER_CLIENT_ID=... --dart-define=GOOGLE_IOS_CLIENT_ID=...
```

The release build type runs **R8** (`isMinifyEnabled`) and shrinks resources
(`isShrinkResources`). The ProGuard rules that make that safe live in
`android/app/proguard-rules.pro` — each one covers a dependency that is only
reached by reflection (the Flutter plugin registrant, Tink's Protobuf fields
behind `flutter_secure_storage`, and the JNI bridge).

Regenerate the native launcher icons after changing the source art. The Figma
exports live in `assets/icon/src/` (light + dark SVG); the rasterised 1024×1024
masters are `assets/icon/ic_launcher_master_light.png` (white "normal" backdrop)
and `assets/icon/ic_launcher_master_dark.png` (AMOLED-black dark backdrop).

```sh
# 1. extract the pin glyph + themed silhouette from the light master
powershell -ExecutionPolicy Bypass -File tool\gen_dark_icon.ps1 -Phase assets
# 2. build the light icon set (legacy + adaptive + iOS)
dart run flutter_launcher_icons
# 3. build the dark alt-icon set used by the dynamic light/dark switch
powershell -ExecutionPolicy Bypass -File tool\gen_dark_icon.ps1 -Phase res
```

> On this Flutter SDK, `flutter pub run flutter_launcher_icons` can crash in
> `flutter_tools` (feature-flags error, exit 255); `dart run flutter_launcher_icons`
> is the reliable entry point.

### Brand logo and splash

`tool/gen_brand_logo.ps1` derives the app's brand assets from the canonical Figma
export in `assets/brand/src/` (`figma_lockup_horizontal_light.svg`, frame
415x176). It emits **two** SVGs, not one:

| File | Contents | Cropped viewBox |
| --- | --- | --- |
| `assets/brand/route_note_mark.svg` | the location-pin / notebook mark | `31.5 31.5 78.5 113` |
| `assets/brand/route_note_wordmark.svg` | "Route" (`#145CFF`) + "Note" (`#00CFFF`) | `136 31.5 245 113` |

They are split because the cold-start splash animates the two halves
independently, and they share one vertical band so `BrandLockup`
(`lib/src/core/brand/brand_lockup.dart`) can recompose them at any size — the
geometry constants live in both files, so keep them in step.

The Figma artboards are solid white or black and the pin's chevron is stroked in
the *artboard* colour, so the tool drops the artboard and moves the chevron into
an SVG `<mask>` (evaluated as luminance) that punches it out of the pin. The
mark is therefore genuinely transparent there, and one asset pair reads correctly
on the white day splash, the AMOLED night splash and the themed About card. Being
vector, the mark also scales up on startup with no raster softness.

```sh
# Regenerate both SVGs (idempotent, no external tools).
powershell -ExecutionPolicy Bypass -File tool\gen_brand_logo.ps1
```

**Where they appear.** The **horizontal** lockup heads the Settings → About card
(static, width 190). The **cold-start splash** is `BrandSplash`, an overlay
mounted from `MaterialApp.builder` and kept for the app's lifetime, so it sits
above the navigator, never re-parents it, and never replays on navigation or on
returning from the background. The platform launch screens
(`android/app/src/main/res/drawable*/launch_background.xml` and iOS
`LaunchScreen.storyboard`) show only the plain brand background — no logo — so
the entrance animation can build the lockup from invisible without it blinking
out first.

**Motion contract.** The entrance is 850 ms, ease-out (`Curves.easeOut`, the
reference's `cubic-bezier(0, 0, 0.58, 1)`), no overshoot:

| t (s) | Animation |
| --- | --- |
| 0.00 | mark invisible at 88% scale; wordmark hidden, +6 lp below its final spot |
| 0.00 → 0.50 | mark opacity 0 → 1 |
| 0.00 → 0.60 | mark scale 88% → 100%, centre fixed |
| 0.28 → 0.85 | wordmark opacity 0 → 1 and rises 6 lp into place |
| 0.85 → 1.10 | cross-fade (250 ms) to the live app |

The reference file (`RouteNote / Motion / Horizontal / 2s`) runs for 2 s, but its
last 1.15 s is just the finished lockup being held — the splash stops when the
entrance ends. Starting up adds no fixed delay: `main()` finishes Firebase/Hive
initialization before `runApp`, so the app is already live under the splash; a
slower initialization simply holds the finished logo. With **Reduce Motion** the
entrance is skipped (the final lockup is shown immediately) while the cross-fade
is kept, since a dissolve is the recommended substitute for movement.

### 6. Firebase (already configured)

Crashlytics and Analytics are wired up and committed, so a fresh clone builds with
them out of the box:

- `android/app/google-services.json` — the Android client for the `routenote-app`
  Firebase project (package `com.routenote.routenote`).
- `android/settings.gradle.kts` + `android/app/build.gradle.kts` — apply the
  `google-services` and `firebase.crashlytics` plugins and add the SDKs via the
  Firebase BoM.
- `lib/main.dart` — best-effort `Firebase.initializeApp()` and crash handlers.

To point the app at a different Firebase project, replace
`android/app/google-services.json` with the file downloaded from your console,
keeping the package name `com.routenote.routenote`.

## Configuration reference

All compile-time values live in `lib/src/core/config/app_config.dart` and are
injected with `--dart-define` (never hardcoded):

| `--dart-define` | Required | Where it is used |
| --- | --- | --- |
| `GOOGLE_SERVER_CLIENT_ID` | Android (for sign-in) | `serverClientId` in `GoogleSignIn.instance.initialize` |
| `GOOGLE_IOS_CLIENT_ID` | iOS (for sign-in) | `clientId` in `GoogleSignIn.instance.initialize` |
| `GEMINI_API_KEY` | No — optional | Enables the optional cloud recommendation layer (`GeminiClient`). A comma-separated **pool** rotated by `KeyRotationService`; in CI it comes from the `GEMINI_API_KEY` repository secret. Without it the agent runs fully offline |
| `GEMINI_MODEL` | No — defaults to `gemini-2.0-flash` | Model used by the optional cloud recommendation layer |

Firebase is configured natively (not through `--dart-define`); see
[Firebase (already configured)](#6-firebase-already-configured).

## Localization

- Template locale: English (`lib/l10n/app_en.arb`); Arabic: `lib/l10n/app_ar.arb`.
- Generated sources live in `lib/l10n/generated/` (output configured in
  `l10n.yaml`). No user-facing string is hardcoded — everything goes through
  `AppLocalizations`.

## Quality gates

```sh
flutter analyze     # expected: No issues found!
flutter test        # Hive-backed widget smoke tests
```

### End-to-end (integration) tests

`integration_test/app_test.dart` drives the real widget tree on a device or
emulator: it launches the app, navigates Places → Settings → Smart Insights,
long-presses a place to open the actions sheet (asserting no layout overflow)
and exercises the lock/unlock toggle. External platform channels (Google
sign-in, biometrics, geolocator) are stubbed so the flows stay deterministic.

```sh
flutter test integration_test/app_test.dart -d <device-id>
# Windows shortcut (omit -Device to use the only connected device):
.\scripts\run_integration_tests.ps1 -Device <device-id>
```

## Platform configuration

Already committed — the notes below explain what is in place.

- **Android** (`android/app/src/main/AndroidManifest.xml`):
  `INTERNET`, `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION`,
  `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`,
  `ACCESS_BACKGROUND_LOCATION`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`,
  `USE_BIOMETRIC`, the `.LocationTrackingService` foreground service
  (`foregroundServiceType="location"`) that keeps background tracking alive, a
  `<queries>` block for the `geo`, `google.navigation`, and `https` intents, and
  `ACTION_SEND` / `ACTION_SEND_MULTIPLE` share filters for `text/*`.
- **Firebase Gradle plugins** (`android/settings.gradle.kts`,
  `android/app/build.gradle.kts`): `com.google.gms.google-services` and
  `com.google.firebase.crashlytics` (**3.0.8**) are applied for the
  `routenote-app` project, with the SDKs pinned by the Firebase **BoM 35.0.0**.
- **Android / Kotlin build notes (KGP & built-in Kotlin):** the app builds with
  **built-in Kotlin** (`android.builtInKotlin=true` in `android/gradle.properties`)
  on **AGP 9.2.1 / Gradle 9.4.1 / compileSdk 37**, so **no module applies the
  legacy Kotlin Gradle Plugin (KGP)** in the default build. This is the supported
  path forward: a future Flutter release removes the legacy KGP shim, so the app
  is already migrated.
  - `receive_sharing_intent` was upgraded **1.8.1 → 1.9.0** and no longer applies
    KGP (its Dart API is byte-for-byte unchanged). 1.9.0 also carries iOS SwiftPM
    + SceneDelegate follow-ups; see `ios/ShareExtension/README.md`.
  - `firebase_core`, `firebase_analytics`, `firebase_crashlytics` and
    `workmanager_android` apply KGP **only while `android.builtInKotlin=false`**,
    so they need no changes.
  - `flutter_dynamic_icon_plus` still applies KGP unconditionally upstream in every
    release (1.6.0 included), so it is **vendored** under
    `third_party/flutter_dynamic_icon_plus` (pinned by `dependency_overrides` in
    `pubspec.yaml`) with a patched `android/build.gradle` that applies KGP only
    when built-in Kotlin is off. The Dart API matches the published release
    exactly; drop the override once upstream ships a built-in-Kotlin release.
  - `android.newDsl=false` stays: the app still uses the legacy AGP DSL types.
  - **Residual notice:** Flutter detects KGP by *textually scanning* each plugin's
    `build.gradle` (see `FlutterPluginUtils.kgpRegex*`), so it still prints
    `plugins that apply Kotlin Gradle Plugin (KGP): firebase_analytics,
    firebase_core, firebase_crashlytics, flutter_dynamic_icon_plus,
    workmanager_android` even though all five guard on `android.builtInKotlin`.
    That notice is a false positive only the upstream packages can remove; it is
    non-fatal and the build exits `0`.
  See <https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin>.
- **Gradle JDK is not pinned in the repository.** `org.gradle.java.home` is an
  absolute, machine-specific path, so committing one breaks every other
  environment with `Value '<path>' given for org.gradle.java.home Gradle property
  is invalid` (a CI runner, a teammate, a fresh clone). Supply the toolchain
  (JDK 17+) per machine instead — `flutter config --jdk-dir <path>`,
  `org.gradle.java.home=<path>` in the user-level `~/.gradle/gradle.properties`,
  or `JAVA_HOME`. Never add it back to `android/gradle.properties`.
- **Debug test-crash button** (`MainActivity.kt`): the Crashlytics guide's
  "Test Crash" button is added only when the activity is debuggable, so it never
  appears in a release or profile build.
- **Share target:** Android is fully wired. On iOS the `receive_sharing_intent`
  plugin also needs a Share Extension **target**, which can only be created in
  Xcode — ready-to-use templates and step-by-step instructions live in
  `ios/ShareExtension/README.md`.
- **iOS** (`ios/Runner/Info.plist`):
  - **Privacy strings:** `NSLocationWhenInUseUsageDescription`,
    `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSLocationAlwaysUsageDescription`,
    `NSFaceIDUsageDescription` (biometric unlock of locked places and the Hidden
    Vault) and `NSMotionUsageDescription`. The motion string is **not
    decorative**: the Qibla indicator (`lib/src/widgets/qibla_indicator.dart`)
    uses `flutter_compass`, whose iOS plugin calls
    `startDeviceMotionUpdates(...)` in its initializer — so the motion feed
    starts at **plugin registration**, i.e. at app launch, not when the Qibla
    widget is first shown. Apple: *"If you don't include this key, your app will
    crash when it attempts to access motion data."*
  - **Background modes:** `UIBackgroundModes` = `location` (the daily trackers
    keep receiving fixes in the background), `processing` and `fetch` (the
    `workmanager` periodic backup is a `BGAppRefreshTask`, which iOS only
    delivers under the Background fetch mode).
    `processing` additionally requires `BGTaskSchedulerPermittedIdentifiers`,
    which must list the exact identifiers the app registers with
    `BGTaskScheduler` — here `routenote.periodicSync`, i.e.
    `AppConfig.backgroundSyncUniqueName`, which `workmanager_apple` passes
    straight through as the task identifier. A missing or mismatched entry makes
    the registration throw at runtime and fails App Store validation.
  - **Document sharing:** `LSSupportsOpeningDocumentsInPlace` +
    `UIFileSharingEnabled` expose the app documents directory in the Files app.
    That directory holds the Hive boxes (`places.hive`, `settings.hive` — the
    latter carries the Google account snapshot `{id, email, displayName,
    photoUrl}`, never a token) and the redacted `app_logs.txt`, so the user can
    back the data up but can also edit or delete it.
  - **URL schemes:** `LSApplicationQueriesSchemes` (`comgooglemaps`, `googlemaps`,
    `waze`), and `CFBundleURLTypes` containing the reversed iOS client ID
    (`com.googleusercontent.apps.<ios-client-id>`) so the OAuth flow can return to
    the app, plus the `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)` scheme used by the
    share extension.
  - **Validation:** `plutil -lint` is macOS-only, so
    `python tool/validate_info_plist.py` is the cross-platform equivalent: it
    checks XML well-formedness, parses the file with `plistlib` and asserts the
    permission / background-mode contract above.
  > **There is deliberately no `ios/Podfile` — the project uses Swift Package
  > Manager.** Plugins are pulled in through `FlutterGeneratedPluginSwiftPackage`
  > (an `XCLocalSwiftPackageReference` in `ios/Runner.xcodeproj/project.pbxproj`);
  > there is no `ios/Pods/`, no `Podfile.lock` and no `Pods-Runner.*.xcconfig`.
  > Flutter skips CocoaPods processing **only when the Podfile is absent**
  > (`flutter_tools/lib/src/macos/cocoapod_utils.dart`), so *adding* a Podfile
  > would silently switch the iOS build to CocoaPods: `pod install` would become
  > mandatory on every build machine, and a `post_install` hook's
  > `installer.pods_project.targets` would contain none of the SPM-compiled
  > plugins.
  > The customary `PERMISSION_LOCATION=1` / `PERMISSION_SENSORS=1`
  > `GCC_PREPROCESSOR_DEFINITIONS` are **`permission_handler_apple`'s**
  > compile-time macros, and `permission_handler` is not a dependency of this app
  > (it uses `geolocator`, `local_auth` and `workmanager` instead) — so such a
  > hook would gate code that is never compiled here. Do not add a Podfile
  > unless `permission_handler` is adopted **and** the project is deliberately
  > migrated off SwiftPM.
- **Application ID / bundle ID:** `com.routenote.routenote` on both platforms.
- **Icons:** the Figma "Location Notebook" pin. `flutter_launcher_icons` builds the
  light icon from `assets/icon/ic_launcher_master_light.png` (white backdrop) plus
  the glyph (`ic_launcher_foreground.png`) and themed (`ic_launcher_monochrome.png`)
  layers; `tool/gen_dark_icon.ps1` builds the dark alt-icon set (`ic_launcher_dark`,
  `#000000` backdrop) used by the dynamic light/dark switch. Adaptive backgrounds:
  `#FFFFFF` (light) / `#000000` (dark), see `android/app/src/main/res/values/colors.xml`.
  The switch is driven by the two `<activity-alias>` entries in
  `AndroidManifest.xml` (`.ic_launcher` enabled, `.ic_launcher_dark` disabled) and
  `lib/src/services/dynamic_icon_service.dart`.
  > **Keep the alias names fully qualified.** `flutter_dynamic_icon_plus` passes the
  > Dart string straight to `ComponentName(context, name)` and compares it verbatim
  > against `ActivityInfo.name` (always `<applicationId>.<alias>`). A short name
  > such as `ic_launcher_dark` is never expanded by the system, so
  > `setComponentEnabledSetting` throws *"Component class … does not exist"* inside
  > the plugin's own service — a native crash Dart cannot catch. `lightIconName` /
  > `darkIconName` must therefore stay
  > `com.routenote.routenote.ic_launcher` / `…ic_launcher_dark`, tied to the
  > `applicationId` in `android/app/build.gradle.kts`. The switch is applied when the
  > task leaves recents, which is when the plugin writes it.
- **Branding:** the MapNote lockup is vector (`assets/brand/route_note_mark.svg`
  + `route_note_wordmark.svg`, composed by `lib/src/core/brand/brand_lockup.dart`)
  and backs the cold-start splash and the Settings → About card.
  `lib/src/features/splash/brand_splash.dart` plays the approved 850 ms entrance
  over the live navigator and cross-fades out (see "Brand logo and splash" for the
  motion contract). The Android launch window and the iOS launch screen show the
  same plain brand background before Flutter's first frame — never the logo, so
  the animation can build it from invisible. `tool/gen_brand_logo.ps1` regenerates
  both SVGs.

## Distributing to testers (Firebase App Distribution)

Ship builds to testers straight from the Firebase CLI — no Play Console
round-trip, and every install's crashes flow into the same Crashlytics dashboard.

### One-time setup

The CLI is a Node.js tool, so install Node.js first, then:

```sh
npm install -g firebase-tools
firebase login
firebase use routenote-app          # project 679774190551
```

Groups and testers live under **App Distribution → Testers & Groups** in the
console, and can also be managed from the CLI:

```sh
firebase appdistribution:groups:create testers testers --project routenote-app
firebase appdistribution:testers:add you@example.com --group-alias testers --project routenote-app
firebase appdistribution:groups:list --project routenote-app
```

The Android app id for this project is:

```
1:679774190551:android:d7bf2f949f60ed62912992
```

### Build and distribute

```sh
# 1. Build the release APK
flutter build apk --release \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com \
  --dart-define=GOOGLE_IOS_CLIENT_ID=yyyy.apps.googleusercontent.com

# 2. Upload it to a tester group
firebase appdistribution:distribute \
  build/app/outputs/flutter-apk/app-release.apk \
  --app 1:679774190551:android:d7bf2f949f60ed62912992 \
  --groups testers \
  --release-notes "MapNote 1.0.5 (11) — pilot build"
```

Testers receive an email invite and install through the **App Tester** app.

On Windows the upload step is wrapped in a helper script:

```powershell
.\scripts\distribute_app.ps1 -Groups testers -Notes "MapNote 1.0.5 (11) — pilot"
```

> **Script blocked by execution policy?** Windows defaults to a `Restricted`
> policy. Allow local scripts once with
> `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`, or run the script with
> `powershell -ExecutionPolicy Bypass -File .\scripts\distribute_app.ps1 -Groups testers`.

> **Signing.** Release builds currently use the **debug** keystore
> (`signingConfig = signingConfigs.getByName("debug")` in
> `android/app/build.gradle.kts`). That is fine for App Distribution and for
> Google Sign-In while testing (add the debug SHA-1 to your Android OAuth
> client), but a Play Store release needs a real upload keystore with its SHA-1
> registered in both Google Cloud and Firebase.

> Prefer a Play-format bundle? `flutter build appbundle --release` produces the
> `.aab`; App Distribution installs the APK directly, which is why the APK is the
> default here.

## Roadmap

MapNote follows the **project master roadmap**: an offline-first, zero-backend
location-saving and navigation app for Android and iOS.

**Tech requirements.** Flutter (latest stable) · Riverpod · Hive · `geolocator` ·
`url_launcher` · `google_sign_in` + `googleapis` (Drive API v3) ·
`flutter_localizations` + `intl` · Firebase Crashlytics + Analytics.

**Delivery phases**

| Phase | Scope | Status |
| --- | --- | --- |
| **1 — Local-first core** | Riverpod scaffolding, Hive CRUD, Home (search + FAB + empty state), Add Place (name/notes), Place Detail | ✅ Done |
| **2 — Location capture** | `geolocator` with graceful permission handling (granted / denied / disabled / error) | ✅ Done |
| **3 — Navigation delegation** | Google Maps / Waze via `url_launcher` intents only — no in-app turn-by-turn | ✅ Done |
| **4 — Zero-backend sync** | Google Sign-In (v7), Drive v3 `appDataFolder`, device-wins backup/restore, auto-sync on open & resume, 24h background task | ✅ Done |
| **5 — Polish & release** | EN/AR localization, light/dark themes, launcher icons, MIT license, README | ✅ Done |
| **6 — Observability & tester distribution** | Firebase Crashlytics + Analytics (best-effort init), debug-only test-crash button, Firebase App Distribution workflow | ✅ Done |
| **Future** | Optional timestamp-based merge, multi-device conflict UI, import/export, parking shortcut widget | 💡 Ideas |

## License

Released under the **MIT License**. See [`MIT-LICENSE`](MIT-LICENSE).

## Disclaimer

MapNote is an independent project and is not affiliated with Google, Google
Maps, or Waze. Map and navigation trademarks belong to their respective owners.
