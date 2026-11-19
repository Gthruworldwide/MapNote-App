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

/// The narrow part of [FirebaseAnalytics] MapNote uses.
///
/// A sink seam lets tests observe what would be sent without initialising
/// Firebase; production wiring uses [_FirebaseAnalyticsEventSink].
abstract interface class AnalyticsEventSink {
  Future<void> logEvent({
    required String name,
    required Map<String, Object> parameters,
  });
}

class _FirebaseAnalyticsEventSink implements AnalyticsEventSink {
  const _FirebaseAnalyticsEventSink(this._client);

  final FirebaseAnalytics _client;

  @override
  Future<void> logEvent({
    required String name,
    required Map<String, Object> parameters,
  }) =>
      _client.logEvent(name: name, parameters: parameters);
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
  ///
  /// [sink] exists only for tests. It cannot bypass the event-name allowlist.
  AnalyticsService({this.analytics, AnalyticsEventSink? sink})
      : _sink = sink ??
            (analytics == null
                ? null
                : _FirebaseAnalyticsEventSink(analytics));

  /// The underlying client, or `null` when Firebase never initialised.
  final FirebaseAnalytics? analytics;

  final AnalyticsEventSink? _sink;

  /// Only these four coarse events may ever leave the device.
  ///
  /// The old `Map<String, Object>` pass-through made it possible for any future
  /// caller to attach place names, notes or coordinates. There is no
  /// legitimate parameterised event today, so the API is closed instead of
  /// relying on every caller to remember the privacy rule.
  static const Set<String> allowedEvents = <String>{
    AnalyticsEvents.autoMotionTripStarted,
    AnalyticsEvents.autoMotionTripEnded,
    AnalyticsEvents.qiblaCompassOpened,
    AnalyticsEvents.placeSaved,
  };

  /// Whether events will actually be delivered.
  bool get isEnabled => _sink != null;

  /// Records one allowlisted, parameter-free event.
  ///
  /// Never throws: a failed send is swallowed (and echoed only in debug) so
  /// instrumentation can't turn a working screen into a crash.
  Future<void> logEvent(String name) async {
    if (!allowedEvents.contains(name)) {
      if (kDebugMode) {
        debugPrint('AnalyticsService refused unknown event: $name');
      }
      return;
    }
    final AnalyticsEventSink? sink = _sink;
    if (sink == null) return;
    try {
      await sink.logEvent(
        name: name,
        parameters: const <String, Object>{},
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('AnalyticsService.logEvent($name) failed: $error');
      }
    }
  }
}
