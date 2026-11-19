/// Compile-time configuration for MapNote.
///
/// The OAuth *client* ids below are public identifiers (the client *secret* is
/// never used by the app). They default to the MapNote Google Cloud project so
/// the app works however it is launched (IDE, adb, or the run script), and can
/// be overridden at build time:
///
/// ```sh
/// flutter run \
///   --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com \
///   --dart-define=GOOGLE_IOS_CLIENT_ID=yyyy.apps.googleusercontent.com
/// ```
///
/// The Gemini API key is the one real secret here. It is read from the
/// environment only (`--dart-define`, or the `GEMINI_API_KEY` CI secret) and is
/// never written into the repository or a release artifact.
/// Build-bound product edition. The value comes from
/// `--dart-define=MAPNOTE_EDITION=work|automotion`, never from a runtime
/// provider override, so a distributed binary's capabilities cannot be widened
/// after it is built.
enum AppEdition { work, automotion }

/// Immutable capability set derived only from [AppConfig.mapnoteEditionRaw].
///
/// Every capability that touches a vehicle sensor, background location or
/// AutoMotion analytics is granted exclusively to the automotion edition. An
/// unknown or missing define fails closed to [AppEdition.work].
class EditionCapabilities {
  const EditionCapabilities(this.edition);

  factory EditionCapabilities.fromBuild() =>
      EditionCapabilities(AppConfig.appEdition);

  final AppEdition edition;

  bool get isAutomotion => edition == AppEdition.automotion;

  /// Master switch for the whole AutoMotion subsystem.
  bool get automotionEnabled => isAutomotion;

  bool get backgroundLocationEnabled => isAutomotion;
  bool get activityRecognitionEnabled => isAutomotion;
  bool get motionSensorsEnabled => isAutomotion;
  bool get automotiveForegroundServiceEnabled => isAutomotion;
  bool get automotionUiEnabled => isAutomotion;

  /// Admin UI belongs to the Work Edition only.
  bool get allowAdminUi => edition == AppEdition.work;

  /// Work Edition station administration is not shipped in this branch. Keep
  /// the privileged capability off until the work-edition branch wires it to a
  /// server-enforced custom claim.
  bool get allowFirebaseStationAdmin => false;
}

class AppConfig {
  const AppConfig._();

  /// Edition identity injected by the build. Unknown values are fail-closed to
  /// `work` by [AppConfig.appEdition] — the edition with the fewest capabilities.
  static const String mapnoteEditionRaw = String.fromEnvironment(
    'MAPNOTE_EDITION',
    defaultValue: 'work',
  );

  /// Kept as an alias for callers that only need the raw identity string.
  static String get appEditionRaw => mapnoteEditionRaw;

  static AppEdition get appEdition => parseEdition(mapnoteEditionRaw);

  /// Fail-closed parser so an unknown build string can never grant privileges.
  static AppEdition parseEdition(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'automotion':
        return AppEdition.automotion;
      case 'work':
      default:
        return AppEdition.work;
    }
  }

  /// Web / server OAuth client id. Required on Android for `google_sign_in`.
  ///
  /// Defaults to the MapNote Web client; override with
  /// `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '679774190551-ojvh4k0r769c77osa7n0v3a3itlvsfr4.apps.googleusercontent.com',
  );

  /// iOS OAuth client id. Required on iOS. Public identifier; see
  /// [googleServerClientId]. Override with `--dart-define=GOOGLE_IOS_CLIENT_ID=...`.
  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue:
        '679774190551-79f3eefd6ncu34appi5rie8lo2use8i9.apps.googleusercontent.com',
  );

  /// Human-readable version shown in Settings → About.
  ///
  /// Keep in sync with the `version` field in `pubspec.yaml`.
  static const String appVersion = '1.0.6';

  /// Drive scope that grants access to the hidden, app-specific
  /// `appDataFolder` only. The user's other Drive files are never visible.
  static const String driveAppDataScope =
      'https://www.googleapis.com/auth/drive.appdata';

  static const List<String> driveScopes = <String>[driveAppDataScope];

  /// Name of the single JSON backup file stored in the app data folder.
  static const String backupFileName = 'routenote_backup.json';

  static const String backupMimeType = 'application/json';

  /// Restore is a write into local Hive storage, so every downloaded payload is
  /// bounded before decoding and every record is validated before persistence.
  static const int maxBackupBytes = 8 * 1024 * 1024;
  static const int maxBackupPlaces = 20000;
  static const int maxBackupJsonDepth = 64;
  static const int maxPlaceIdLength = 128;
  static const int maxPlaceNameLength = 300;
  static const int maxPlaceNotesLength = 4000;
  static const int maxPlacePlusCodeLength = 32;
  static const Duration maxBackupTimestampSkew = Duration(days: 1);
  static const int minBackupTimestampMs = 946684800000; // 2000-01-01 UTC.

  /// Hive box names.
  static const String placesBoxName = 'places';
  static const String settingsBoxName = 'settings';
  static const String gpsDailyBoxName = 'gps_daily';
  static const String autoMotionBoxName = 'auto_motion_box';

  /// AES-256 encrypted box holding the biometric-gated "encrypted vault"
  /// places. Additive: the plain [placesBoxName] box is never touched, so it
  /// adds no schema change and no migration. The box is opened lazily and only
  /// after the user passes the biometric gate.
  static const String securePlacesBoxName = 'secure_places';

  /// AES-256 encrypted box holding the *adaptive profile*: anonymous numbers the
  /// motion pipeline has learned about this device (vibration baselines and
  /// adapted thresholds). Additive and separate from every other box, so it
  /// changes no existing schema. Unlike the vault it needs no user prompt — it
  /// holds no user content, only scalars — so it is opened by the analytics
  /// pipeline itself and degrades to the defaults if it cannot be read.
  static const String adaptiveProfileBoxName = 'adaptive_profile';

  /// How often the periodic background backup runs.
  static const Duration backgroundSyncFrequency = Duration(hours: 24);

  /// Unique name used by the background task scheduler.
  static const String backgroundSyncUniqueName = 'routenote.periodicSync';

  // ---------------------------------------------------------------------------
  // Monitoring & recommendation agent (optional, privacy-safe)
  // ---------------------------------------------------------------------------

  /// Optional Google Gemini API key(s) for the cloud recommendation engine.
  ///
  /// The app is **offline-first and zero-backend by default**: when this is
  /// empty (or the user turns cloud AI off in Settings), the agent still runs
  /// using the fully local, rule-based engine.
  ///
  /// The value is a comma/whitespace separated **pool** so an exhausted or
  /// revoked key can be rotated out without shipping a new build. It is read
  /// from the environment only — never committed to the repo — e.g. locally:
  ///
  /// ```sh
  /// flutter run --dart-define=GEMINI_API_KEY=primary-key,fallback-key
  /// ```
  ///
  /// and in CI from the `GEMINI_API_KEY` GitHub Actions repository secret
  /// (see `.github/workflows/android-release.yml`). Rotating keys is handled by
  /// `KeyRotationService`. Only anonymous aggregate metrics are ever sent
  /// (counts and structural summaries — never place names, notes, coordinates).
  ///
  /// Use [geminiApiKeys] for the parsed pool; [geminiApiKey] returns the first
  /// configured key for backwards compatibility.
  static const String geminiApiKeysRaw = String.fromEnvironment('GEMINI_API_KEY');

  /// The parsed, de-duplicated key pool (may be empty).
  static List<String> get geminiApiKeys => parseGeminiApiKeys(geminiApiKeysRaw);

  /// The first configured key, or an empty string when none is configured.
  static String get geminiApiKey {
    final List<String> keys = geminiApiKeys;
    return keys.isEmpty ? '' : keys.first;
  }

  /// Splits a raw `GEMINI_API_KEY` value into a clean key pool.
  ///
  /// Accepts commas, semicolons and whitespace as separators, trims each entry,
  /// drops blanks and de-duplicates while preserving priority order.
  static List<String> parseGeminiApiKeys(String raw) {
    final List<String> keys = <String>[];
    for (final String part in raw.split(RegExp(r'[,;\s]+'))) {
      final String trimmed = part.trim();
      if (trimmed.isEmpty || keys.contains(trimmed)) continue;
      keys.add(trimmed);
    }
    return keys;
  }

  /// Gemini model used for recommendations. Override with
  /// `--dart-define=GEMINI_MODEL=gemini-2.0-flash`.
  static const String geminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.0-flash',
  );

  /// Whether at least one Gemini API key was compiled in.
  static bool get isGeminiConfigured => geminiApiKeys.isNotEmpty;

  /// How often the recommendation agent re-runs while the app stays open.
  static const Duration agentRefreshInterval = Duration(hours: 6);

  /// Network timeout for a single cloud recommendation request.
  static const Duration agentRequestTimeout = Duration(seconds: 12);

  /// Maximum function-call round trips allowed per cloud request.
  static const int agentToolRounds = 4;

  /// Maximum number of insights shown at once (the rest are queued away).
  static const int maxAgentInsights = 3;

  /// Optional Geoapify API key for optional enhanced geocoding.
  ///
  /// The app is **offline-first by default**: when this is empty (or the user
  /// turns cloud AI off in Settings), the app uses the native [package:geocoding]
  /// geocoder only. No network calls are made on core paths.
  ///
  /// The value is read from the environment only — never committed to the repo —
  /// e.g. locally:
  ///
  /// ```sh
  /// flutter run --dart-define=GEOAPIFY_API_KEY=your-geoapify-key
  /// ```
  ///
  /// and in CI from the `GEOAPIFY_API_KEY` secret (see
  /// `.github/workflows/android-release.yml`).
  ///
  /// Only anonymous counts and structural summaries are ever sent — never place
  /// names, notes, or coordinates beyond what the user explicitly shares.
  ///
  /// The key travels as the `apiKey` query parameter in the request URL only.
  static const String geoApiKeysRaw = String.fromEnvironment('GEOAPIFY_API_KEY');

  /// The parsed, de-duplicated key pool (may be empty).
  static List<String> get geoApiKeys => parseGeoApiKeys(geoApiKeysRaw);

  /// The first configured key, or an empty string when none is configured.
  static String get geoApiKey {
    final List<String> keys = geoApiKeys;
    return keys.isEmpty ? '' : keys.first;
  }

  /// Splits a raw `GEOAPIFY_API_KEY` value into a clean key pool.
  ///
  /// Accepts a single key (no separators needed). Trims whitespace and drops blanks.
  static List<String> parseGeoApiKeys(String raw) {
    final List<String> keys = <String>[];
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return keys;
    if (!keys.contains(trimmed)) keys.add(trimmed);
    return keys;
  }

  /// Whether at least one Geoapify API key was compiled in.
  static bool get isGeoApifyConfigured => geoApiKeys.isNotEmpty;

  /// Network timeout for a single cloud geocoding request.
  static const Duration geocodeTimeout = Duration(seconds: 12);

  /// Key used to persist the bounded health-event log in the settings box.
  static const String healthLogKey = 'health_events';

  /// Maximum number of health events kept on device.
  static const int healthLogCapacity = 200;

  /// How long a cached Google session is trusted without re-asking the platform.
  ///
  /// A successful Drive upload or restore is the only thing that writes
  /// `last_synced`, and it cannot succeed without a live bearer token — so a
  /// `last_synced` inside this window is *evidence* the session works, not a
  /// guess. While the evidence is fresh, launch skips
  /// `attemptLightweightAuthentication()` entirely.
  ///
  /// That matters because the plugin's "lightweight" authentication is allowed
  /// to raise the Credential Manager chooser (Play Services logs
  /// `ui invocation is needed`), which steals focus on every cold start on a
  /// device with several Google accounts. Skipping it keeps launch silent for
  /// the common case; a session that has gone stale still gets the full
  /// restore, and any Drive call that *does* fail falls back to the existing
  /// re-authenticate path.
  ///
  /// Deliberately shorter than [backgroundSyncFrequency] so a daily background
  /// sync is never suppressed by this window.
  static const Duration sessionTrustWindow = Duration(hours: 12);
}
