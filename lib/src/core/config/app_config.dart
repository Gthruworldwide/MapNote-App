/// Compile-time configuration for MapNote.
///
/// None of these values are secrets. OAuth *client* ids are public identifiers
/// (the client *secret* is never used by the app). They default to the MapNote
/// Google Cloud project so the app works however it is launched (IDE, adb, or
/// the run script), and can be overridden at build time:
///
/// ```sh
/// flutter run \
///   --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com \
///   --dart-define=GOOGLE_IOS_CLIENT_ID=yyyy.apps.googleusercontent.com
/// ```
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
  static const String appVersion = '1.0.4';

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

  /// How often the periodic background backup runs.
  static const Duration backgroundSyncFrequency = Duration(hours: 24);

  /// Unique name used by the background task scheduler.
  static const String backgroundSyncUniqueName = 'routenote.periodicSync';

  // ---------------------------------------------------------------------------
  // Monitoring & recommendation agent (optional, privacy-safe)
  // ---------------------------------------------------------------------------

  /// Optional Google Gemini API key for the cloud recommendation engine.
  ///
  /// The app is **offline-first and zero-backend by default**: when this is
  /// empty (or the user turns cloud AI off in Settings), the agent still runs
  /// using the fully local, rule-based engine. Provide a restricted key with:
  ///
  /// ```sh
  /// flutter run --dart-define=GEMINI_API_KEY=xxxx
  /// ```
  ///
  /// Only anonymous aggregate metrics are ever sent (counts and structural
  /// summaries — never place names, notes, or coordinates).
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  /// Gemini model used for recommendations. Override with
  /// `--dart-define=GEMINI_MODEL=gemini-2.0-flash`.
  static const String geminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.0-flash',
  );

  /// Whether a Gemini API key was compiled in.
  static bool get isGeminiConfigured => geminiApiKey.isNotEmpty;

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
