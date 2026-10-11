# RouteNote

**Save your favourite places offline. Sync them to your private Google Drive.**

RouteNote is an **offline-first, zero-backend** Flutter app for Android and iOS.
It saves GPS locations locally on the device (Hive), backs them up to the user's
*private* Google Drive app-data folder, and delegates turn-by-turn navigation to
Google Maps or Waze via deep links.

No Firebase. No custom server. No database to operate. Your data is yours.

---

## Table of contents

- [Overview](#overview)
- [Design principles (strict rules)](#design-principles-strict-rules)
- [Zero-backend architecture (Google Drive sync)](#zero-backend-architecture-google-drive-sync)
- [Features](#features)
- [User flow](#user-flow)
- [Tech stack](#tech-stack)
- [How sync works](#how-sync-works)
- [Backup format](#backup-format)
- [Project structure](#project-structure)
- [Getting started](#getting-started)
- [Configuration reference](#configuration-reference)
- [Localization](#localization)
- [Quality gates](#quality-gates)
- [Platform configuration](#platform-configuration)
- [Roadmap](#roadmap)
- [License](#license)

---

## Overview

RouteNote solves a simple problem: remembering places (a parking spot, a trailhead,
a friend's building) without depending on a third-party account or a backend you
have to pay for and maintain.

- **Local-first.** Every place lives on the device in a Hive database. The app is
  fully usable with no network and no sign-in.
- **Private cloud backup.** Optional Google Sign-In grants exactly one scope,
  `drive.appdata`, which exposes only the app's *own hidden* Drive folder. The
  user's documents, photos, and other Drive files are never visible to the app.
- **Zero backend.** There is no server to host, no auth server, and no analytics.
  OAuth happens directly between the app and Google; the backup is a single JSON
  file in the user's Drive.
- **Bilingual.** Full English / Arabic UI, no hardcoded strings.

## Design principles (strict rules)

These are non-negotiable constraints for the project:

1. **Zero external backend.** No Firebase, AWS, or any custom backend servers for
   database storage.
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
  and RouteNote opens the save screen pre-filled.
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
- 🤖 **Smart Insights** — a privacy-first monitoring & recommendation agent that
  watches local app health (lifecycle, sync failures, location-parsing failures,
  UI latency) and the shape of the user's data, then suggests tidy-ups, sync
  reminders and optimisations. Works fully offline with a local rule engine; an
  optional Google Gemini layer adds localized tips when a key is configured.

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
| Deep links | `url_launcher` (Google Maps, `geo`, `google.navigation`, Waze, `https`) |
| Share target | `receive_sharing_intent` (text/links shared into the app) |
| Localization | `flutter_localizations` + `intl` + ARB (`app_en.arb`, `app_ar.arb`) |
| IDs | `uuid` |
| Icons | `flutter_launcher_icons` (generated from `assets/app_icon.png`) |
| Routing | Plain `Navigator` (no `go_router`) |

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

RouteNote ships a lightweight, privacy-first "AI assistant" that watches the
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

The local engine always runs and needs no account. If the app is built with a
restricted Gemini key:

```sh
flutter run \
  --dart-define=GEMINI_API_KEY=xxxx \
  --dart-define=GEMINI_MODEL=gemini-2.0-flash
```

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
      navigation/app_navigator.dart # global navigator key (share intents)
      theme/app_theme.dart         # light & dark themes
      utils/date_formats.dart
    data/
      models/                      # Place, BackupData (JSON shape)
      local/                       # HiveDatabase, PlaceLocalDataSource, SettingsRepository
      remote/                      # auth_service, google_auth_service, drive_service
      repositories/                # PlaceRepository, SyncRepository
    services/                      # location, navigation, location_parser,
                                   #   share_intent, background sync scheduler,
                                   #   app_health_logger, local_insight_engine,
                                   #   gemini_client, agent_service
    providers/app_providers.dart   # all Riverpod providers & notifiers
    features/
      home/                        # list + search + AppBar actions + Smart Insights
      add_place/                   # GPS or pasted/manual coordinates, name & notes
      place_detail/                # view / navigate / delete
      settings/                    # sign-in, sync, restore, language, theme, agent
test/                              # Hive-backed widget tests + parser/share tests
integration_test/app_test.dart     # on-device end-to-end UI flow tests
ios/ShareExtension/                # iOS share-extension templates + README
scripts/run_dev.ps1                # Windows helper: run with real OAuth IDs
scripts/run_integration_tests.ps1  # Windows helper: run the E2E integration tests
assets/app_icon.png                # source icon for flutter_launcher_icons
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

```sh
# Android
flutter build apk     --release --dart-define=GOOGLE_SERVER_CLIENT_ID=... --dart-define=GOOGLE_IOS_CLIENT_ID=...
flutter build appbundle --release --dart-define=GOOGLE_SERVER_CLIENT_ID=... --dart-define=GOOGLE_IOS_CLIENT_ID=...

# iOS (requires macOS + Xcode)
flutter build ios      --release --dart-define=GOOGLE_SERVER_CLIENT_ID=... --dart-define=GOOGLE_IOS_CLIENT_ID=...
```

Regenerate the native launcher icons after changing `assets/app_icon.png`:

```sh
flutter pub run flutter_launcher_icons
```

## Configuration reference

All compile-time values live in `lib/src/core/config/app_config.dart` and are
injected with `--dart-define` (never hardcoded):

| `--dart-define` | Required | Where it is used |
| --- | --- | --- |
| `GOOGLE_SERVER_CLIENT_ID` | Android (for sign-in) | `serverClientId` in `GoogleSignIn.instance.initialize` |
| `GOOGLE_IOS_CLIENT_ID` | iOS (for sign-in) | `clientId` in `GoogleSignIn.instance.initialize` |
| `GEMINI_API_KEY` | No — optional | Enables the optional cloud recommendation layer (`GeminiClient`); without it the agent runs fully offline |
| `GEMINI_MODEL` | No — defaults to `gemini-2.0-flash` | Model used by the optional cloud recommendation layer |

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
  `RECEIVE_BOOT_COMPLETED`, a `<queries>` block for the `geo`,
  `google.navigation`, and `https` intents, and `ACTION_SEND` /
  `ACTION_SEND_MULTIPLE` share filters for `text/*`.
- **Share target:** Android is fully wired. On iOS the `receive_sharing_intent`
  plugin also needs a Share Extension **target**, which can only be created in
  Xcode — ready-to-use templates and step-by-step instructions live in
  `ios/ShareExtension/README.md`.
- **iOS** (`ios/Runner/Info.plist`): `NSLocationWhenInUseUsageDescription`,
  `LSApplicationQueriesSchemes` (`comgooglemaps`, `googlemaps`, `waze`), and
  `CFBundleURLTypes` containing the reversed iOS client ID
  (`com.googleusercontent.apps.<ios-client-id>`) so the OAuth flow can return to
  the app, plus the `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)` scheme used by the
  share extension.
- **Application ID / bundle ID:** `com.routenote.routenote` on both platforms.
- **Icons:** generated with `flutter_launcher_icons` from `assets/app_icon.png`.

## Roadmap

RouteNote follows the **project master roadmap**: an offline-first, zero-backend
location-saving and navigation app for Android and iOS.

**Tech requirements.** Flutter (latest stable) · Riverpod · Hive · `geolocator` ·
`url_launcher` · `google_sign_in` + `googleapis` (Drive API v3) ·
`flutter_localizations` + `intl`.

**Delivery phases**

| Phase | Scope | Status |
| --- | --- | --- |
| **1 — Local-first core** | Riverpod scaffolding, Hive CRUD, Home (search + FAB + empty state), Add Place (name/notes), Place Detail | ✅ Done |
| **2 — Location capture** | `geolocator` with graceful permission handling (granted / denied / disabled / error) | ✅ Done |
| **3 — Navigation delegation** | Google Maps / Waze via `url_launcher` intents only — no in-app turn-by-turn | ✅ Done |
| **4 — Zero-backend sync** | Google Sign-In (v7), Drive v3 `appDataFolder`, device-wins backup/restore, auto-sync on open & resume, 24h background task | ✅ Done |
| **5 — Polish & release** | EN/AR localization, light/dark themes, launcher icons, MIT license, README | ✅ Done |
| **Future** | Optional timestamp-based merge, multi-device conflict UI, import/export, parking shortcut widget | 💡 Ideas |

## License

Released under the **MIT License**. See [`MIT-LICENSE`](MIT-LICENSE).

## Disclaimer

RouteNote is an independent project and is not affiliated with Google, Google
Maps, or Waze. Map and navigation trademarks belong to their respective owners.
