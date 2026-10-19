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
class AppConfig {
  const AppConfig._();

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
  static const String appVersion = '1.0.5';

  /// Drive scope that grants access to the hidden, app-specific
  /// `appDataFolder` only. The user's other Drive files are never visible.
  static const String driveAppDataScope =
      'https://www.googleapis.com/auth/drive.appdata';

  static const List<String> driveScopes = <String>[driveAppDataScope];

  /// Name of the single JSON backup file stored in the app data folder.
  static const String backupFileName = 'routenote_backup.json';

  static const String backupMimeType = 'application/json';

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

  /// Key used to persist the bounded health-event log in the settings box.
  static const String healthLogKey = 'health_events';

  /// Maximum number of health events kept on device.
  static const int healthLogCapacity = 200;
}
