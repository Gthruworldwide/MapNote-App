import 'package:hive_ce/hive.dart';

import '../../core/config/preferred_nav_app.dart';
import '../../core/security/session_guard.dart';

/// The four font-size presets selectable in Settings.
enum FontScalePreset { small, standard, large, extraLarge }

/// Small key/value store for app preferences backed by a Hive box.
class SettingsRepository {
  SettingsRepository(this._box);

  final Box<dynamic> _box;

  static const String _localeKey = 'locale';
  static const String _themeModeKey = 'theme_mode';
  static const String _lastSyncedKey = 'last_synced';
  static const String _isLoggedInKey = 'is_logged_in';
  static const String _authUserKey = 'auth_user';
  static const String _cloudAiKey = 'cloud_ai_enabled';
  static const String _dismissedInsightsKey = 'dismissed_insights';
  static const String _preferredNavAppKey = 'preferred_nav_app';
  static const String _smartInsightsEnabledKey = 'smart_insights_enabled';
  static const String _gpsTrackingEnabledKey = 'gps_tracking_enabled';
  static const String _autoMotionEnabledKey = 'enable_auto_motion';
  static const String _sessionTimeoutMinutesKey = 'session_timeout_minutes';
  static const String _lockOnDeviceLockKey = 'lock_on_device_lock';
  static const String _fontScaleKey = 'font_scale';
  static const String _hapticFeedbackKey = 'haptic_feedback';
  static const String _uiDensityCompactKey = 'ui_density_compact';
  static const String _smartBatterySaverKey = 'smart_battery_saver';
  static const String _biometricVaultEnabledKey = 'enable_biometric_vault';

  /// BCP-47 language code of the selected locale, or null for system default.
  String? get localeCode => _box.get(_localeKey) as String?;

  Future<void> setLocaleCode(String? code) async {
    if (code == null || code.isEmpty) {
      await _box.delete(_localeKey);
    } else {
      await _box.put(_localeKey, code);
    }
  }

  int? get themeModeIndex => _box.get(_themeModeKey) as int?;

  Future<void> setThemeModeIndex(int index) async {
    await _box.put(_themeModeKey, index);
  }

  DateTime? get lastSynced {
    final Object? raw = _box.get(_lastSyncedKey);
    if (raw is String) return DateTime.tryParse(raw)?.toUtc();
    return null;
  }

  Future<void> setLastSynced(DateTime time) async {
    await _box.put(_lastSyncedKey, time.toUtc().toIso8601String());
  }

  /// Whether a Google session was active the last time the app ran.
  ///
  /// This is the *local* mirror of the remote session, used to render the
  /// signed-in UI on the first frame instead of a "Signing in..." loader.
  bool get isLoggedIn => _box.get(_isLoggedInKey) == true;

  /// The cached profile of the signed-in user, or null when none is stored.
  Map<String, dynamic>? get authUser {
    final Object? raw = _box.get(_authUserKey);
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  /// Persists the cached Google session (or clears it when [user] is null) so
  /// launch can render the signed-in state without waiting on the network.
  Future<void> saveAuthSession(Map<String, dynamic>? user) async {
    await _box.put(_isLoggedInKey, user != null);
    if (user == null) {
      await _box.delete(_authUserKey);
    } else {
      await _box.put(_authUserKey, user);
    }
  }

  /// Whether optional cloud (Gemini) recommendations are allowed.
  ///
  /// Defaults to true so the feature works once an API key is compiled in; the
  /// user can switch it off in Settings to keep everything local.
  bool get isCloudAiEnabled => (_box.get(_cloudAiKey) as bool?) ?? true;

  Future<void> setCloudAiEnabled(bool enabled) async {
    await _box.put(_cloudAiKey, enabled);
  }

  /// Which app should open for turn-by-turn navigation.
  ///
  /// Defaults to [PreferredNavApp.system].
  PreferredNavApp get preferredNavApp {
    final Object? raw = _box.get(_preferredNavAppKey);
    if (raw is String) {
      return PreferredNavApp.values.firstWhere(
        (PreferredNavApp app) => app.name == raw,
        orElse: () => PreferredNavApp.system,
      );
    }
    return PreferredNavApp.system;
  }

  Future<void> setPreferredNavApp(PreferredNavApp app) async {
    await _box.put(_preferredNavAppKey, app.name);
  }

  /// Whether the Smart Insights feature is shown on the Home screen.
  ///
  /// Defaults to true; the user can hide the card from Settings.
  bool get areSmartInsightsEnabled =>
      (_box.get(_smartInsightsEnabledKey) as bool?) ?? true;

  Future<void> setSmartInsightsEnabled(bool enabled) async {
    await _box.put(_smartInsightsEnabledKey, enabled);
  }

  /// Whether daily GPS tracking is switched on (Settings → GPS tracking).
  ///
  /// Defaults to off; the feature only runs while the app is open and only
  /// while a location permission is granted.
  bool get isGpsTrackingEnabled => _box.get(_gpsTrackingEnabledKey) == true;

  Future<void> setGpsTrackingEnabled(bool enabled) async {
    await _box.put(_gpsTrackingEnabledKey, enabled);
  }

  /// Whether AutoMotion is switched on (Settings → AutoMotion).
  ///
  /// **Defaults to on.** A fresh install records from its very first launch, so
  /// the user does not have to find Settings → Location before getting a day's
  /// distance. Only an explicit `false` — the user flipping the toggle off —
  /// disables it: a missing key *and* a corrupt (non-bool) value both read as
  /// on, because AutoMotion works entirely on the device and never transmits a
  /// trip. The toggle still persists every change, so an opt-out survives.
  bool get isAutoMotionEnabled {
    final Object? stored = _box.get(_autoMotionEnabledKey);
    return stored is bool ? stored : true;
  }

  Future<void> setAutoMotionEnabled(bool enabled) async {
    await _box.put(_autoMotionEnabledKey, enabled);
  }

  /// How many minutes the encrypted vault may stay unlocked without
  /// interaction, as chosen in Settings.
  ///
  /// Defaults to [SessionGuard.defaultInactivityTimeout] (15 min) when the user
  /// has never set it, so an existing install keeps its behaviour and a fresh
  /// install gets a sane window. The value is *clamped* to the selectable set on
  /// read, so a hand-edited or corrupted box can never produce a nonsensical
  /// timeout (e.g. zero, which would lock the vault instantly).
  int get sessionTimeoutMinutes {
    final Object? raw = _box.get(_sessionTimeoutMinutesKey);
    final int fallback = SessionGuard.defaultInactivityTimeout.inMinutes;
    if (raw is! num) return fallback;
    final int value = raw.toInt();
    if (SessionGuard.selectableInactivityMinutes.contains(value)) return value;
    return fallback;
  }

  Future<void> setSessionTimeoutMinutes(int minutes) async {
    if (!SessionGuard.selectableInactivityMinutes.contains(minutes)) {
      throw ArgumentError.value(
        minutes,
        'minutes',
        'must be one of ${SessionGuard.selectableInactivityMinutes}',
      );
    }
    await _box.put(_sessionTimeoutMinutesKey, minutes);
  }

  /// Whether reaching the device lock screen must lock the encrypted vault
  /// immediately (the default).
  ///
  /// Defaults to true: a phone that has left the user's hands must not keep an
  /// unlocked vault in memory.
  bool get isLockOnDeviceLockEnabled =>
      (_box.get(_lockOnDeviceLockKey) as bool?) ?? true;

  Future<void> setLockOnDeviceLockEnabled(bool enabled) async {
    await _box.put(_lockOnDeviceLockKey, enabled);
  }

  /// Stable ids of insights the user has dismissed, so the agent stops
  /// nagging across launches.
  List<String> get dismissedInsightIds {
    final Object? raw = _box.get(_dismissedInsightsKey);
    if (raw is! List) return const <String>[];
    return raw.whereType<String>().toList(growable: false);
  }

  /// Remembers a dismissed insight, keeping the list bounded.
  Future<void> dismissInsight(String id) async {
    final List<String> ids = dismissedInsightIds.toList();
    if (!ids.contains(id)) ids.add(id);
    const int maxDismissed = 100;
    if (ids.length > maxDismissed) {
      ids.removeRange(0, ids.length - maxDismissed);
    }
    await _box.put(_dismissedInsightsKey, ids);
  }

  Future<void> clearDismissedInsights() async {
    await _box.delete(_dismissedInsightsKey);
  }

  /// The selected font-size preset. Defaults to [FontScalePreset.standard].
  FontScalePreset get fontScalePreset {
    final Object? raw = _box.get(_fontScaleKey);
    if (raw is String) {
      for (final FontScalePreset p in FontScalePreset.values) {
        if (p.name == raw) return p;
      }
    }
    return FontScalePreset.standard;
  }

  Future<void> setFontScalePreset(FontScalePreset preset) async {
    await _box.put(_fontScaleKey, preset.name);
  }

  /// Whether haptic feedback is enabled (default on).
  bool get isHapticFeedbackEnabled =>
      (_box.get(_hapticFeedbackKey) as bool?) ?? true;

  Future<void> setHapticFeedbackEnabled(bool enabled) async {
    await _box.put(_hapticFeedbackKey, enabled);
  }

  /// Whether the UI uses the compact density (default off = comfortable).
  bool get isUiDensityCompact =>
      (_box.get(_uiDensityCompactKey) as bool?) ?? false;

  Future<void> setUiDensityCompact(bool compact) async {
    await _box.put(_uiDensityCompactKey, compact);
  }

  /// Smart battery saver for AutoMotion (default on).
  bool get isSmartBatterySaverEnabled =>
      (_box.get(_smartBatterySaverKey) as bool?) ?? true;

  Future<void> setSmartBatterySaverEnabled(bool enabled) async {
    await _box.put(_smartBatterySaverKey, enabled);
  }

  /// Whether the biometric (encrypted) vault is offered (default on).
  ///
  /// Turning it off hides the encrypted-vault entry points. It never deletes
  /// anything: places already moved into the encrypted box stay encrypted on
  /// disk and reappear the moment the vault is switched back on, so the toggle
  /// can never lose a place.
  bool get isBiometricVaultEnabled =>
      (_box.get(_biometricVaultEnabledKey) as bool?) ?? true;

  Future<void> setBiometricVaultEnabled(bool enabled) async {
    await _box.put(_biometricVaultEnabledKey, enabled);
  }
}
