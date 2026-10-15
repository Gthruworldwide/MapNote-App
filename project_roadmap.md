# PROJECT MASTER ROADMAP & CONTEXT

**Project Name:** MapNote
**Role:** Expert Senior Flutter Developer and Architect.
**Objective:** Build an offline-first, zero-backend location saving and navigation mobile application (Android/iOS).

## 1. Core Architecture & Philosophy (STRICT RULES)

- **ZERO EXTERNAL BACKEND:** Do NOT use Firebase, AWS, or any custom backend servers for database storage. (Exception: anonymous crash/usage telemetry via Firebase Crashlytics + Analytics is permitted — it never stores or transmits user places.)
- **Storage Mechanism:** The app is Offline-First. All data is saved locally on the device using a fast local database (`Hive`).
- **Cloud Sync (The WhatsApp Model):** For backup and cross-device sync, the app uses Google OAuth 2.0 and the **Google Drive API**. The local database is serialized into a JSON file and synced silently to the user's Google Drive (using `drive.appdata` scope for hidden app-specific storage).
- **Bilingual UI (i18n):** The application UI MUST support both **Arabic (ar)** and **English (en)** natively using `flutter_localizations` and `.arb` files. Do NOT hardcode UI strings.
- **Navigation Delegation:** The app does NOT feature a built-in turn-by-turn navigation engine. It uses intent/deep-linking (`url_launcher`) to send coordinates to Google Maps or Waze.

## 2. Core Features & User Flow

1. **Capture Location (One-Tap):** User opens the app, presses a FAB. The app grabs exact GPS coordinates. User adds a Name and Notes. Data is saved locally.
2. **Save a Location You Are Not At:** The Add Location screen supports custom latitude/longitude entry (with range validation), a **Paste location from clipboard** action (parses Google Maps full/short links, `geo:` URIs, and raw `lat, lng`), and a **Share target** so a place shared from Google Maps / WhatsApp / a browser opens the screen pre-filled.
3. **Search & Retrieve:** User searches their saved places list via a search bar.
4. **Navigate:** User taps a saved location card -> Taps "Navigate" -> Google Maps opens with destination coordinates ready for routing.
5. **Auto-Sync:** Local JSON overrides the Google Drive JSON backup.
6. **Restore:** If the user logs into a new device via Google, the app fetches JSON from Drive and populates local database.

## 3. Tech Stack Requirements

- **Framework:** Flutter (Latest Version).
- **State Management:** Riverpod.
- **Local Storage:** `Hive`.
- **Location:** `geolocator`.
- **Routing/Maps:** `url_launcher`.
- **Share Target:** `receive_sharing_intent` (text/link sharing into the app).
- **Auth & Sync:** `google_sign_in` and `googleapis` (Drive API v3).
- **Localization:** `flutter_localizations` & `intl`.
- **Observability:** Firebase Crashlytics + Analytics (anonymous telemetry only — never user data).
- **Tester distribution:** Firebase App Distribution (`firebase appdistribution:distribute`).

## 4. AutoMotion & Driver Experience

AutoMotion is a first-party, **offline** daily motion tracker, independent of the
Daily GPS tracker. It records today's distance and max speed into the dedicated
`auto_motion_box` Hive box as one `DailyGpsSummary` per `YYYY-MM-DD` key.

- **Phase 1 (shipped):** foreground/background tracking, the Home status card
  (`auto_motion_card`), and the electric-blue/mint status badge (`auto_motion_badge`).
- **Phase 2 (this change):** a dedicated **AutoMotion dashboard** screen, opened by
  tapping the Home card, containing:
  - a **Driver mode** header — live current speed, active/paused status, and
    today's distance & max speed, with the shared one-tap location recovery;
  - a **Trip history** list — every recorded day, newest-first, read from
    `AutoMotionDataSource.all()`, with an empty state.
- **Phase 3 (deferred):** per-mode activity breakdown (walk / run / vehicle) and
  7/30-day aggregates. These require new persisted fields on `DailyGpsSummary`
  (added with backward-compatible defaults) and are intentionally out of scope
  for Phase 2.

Rules for this feature: fully offline (no backend), bilingual en/ar through ARB
keys (no hardcoded strings), no new runtime dependencies, and the two daily
trackers stay independent (separate boxes and settings switches).
