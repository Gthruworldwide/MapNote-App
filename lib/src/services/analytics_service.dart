import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Custom event names for MapNote's core user flows.
///
/// Constants (rather than inline string literals) keep a single funnel from
/// silently splitting into two differently-spelled events in the console.
class AnalyticsEvents {
  const AnalyticsEvents._();

  /// AutoMotion driver mode began recording a trip.
  static const String autoMotionTripStarted = 'automotion_trip_started';

  /// AutoMotion driver mode stopped recording a trip.
  static const String autoMotionTripEnded = 'automotion_trip_ended';

  /// The Qibla compass became visible (Dynamic Island slot or full sheet).
  static const String qiblaCompassOpened = 'qibla_compass_opened';

  /// A place was persisted from the add/edit flow.
  static const String placeSaved = 'place_saved';
}

/// Thin, best-effort facade over [FirebaseAnalytics].
///
/// MapNote is offline-first, so Firebase can genuinely be unavailable (a build
/// without `google-services.json`, a device without Play services). Every call
/// therefore degrades to a no-op instead of throwing: instrumentation must
/// never be able to break a user flow or block launch.
///
/// Privacy: only coarse, non-identifying values are ever sent. Place names,
/// notes, coordinates and any other user content stay on the device — no PII
/// is handed to [logEvent] (AGENT_SKILLS.md §2.3).
class AnalyticsService {
  /// Wraps [analytics]; when omitted or null every call is a silent no-op.
  AnalyticsService({this.analytics});

  /// The underlying client, or `null` when Firebase never initialised.
  final FirebaseAnalytics? analytics;

  /// Whether events will actually be delivered.
  bool get isEnabled => analytics != null;

  /// Records a custom [name]d event with optional [parameters].
  ///
  /// Never throws: a failed send is swallowed (and echoed only in debug) so
  /// instrumentation can't turn a working screen into a crash.
  Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    final FirebaseAnalytics? client = analytics;
    if (client == null) return;
    try {
      await client.logEvent(
        name: name,
        parameters: parameters ?? const <String, Object>{},
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('AnalyticsService.logEvent($name) failed: $error');
      }
    }
  }
}
