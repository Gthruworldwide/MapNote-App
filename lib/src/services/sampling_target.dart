import 'package:geolocator/geolocator.dart';

/// The live-stream surface shared by the two daily trackers.
///
/// `GpsTrackerService` and `AutoMotionService` each own a position stream and
/// each accept an adaptive-sampling profile, but nothing else about them is
/// alike. Naming the shared slice here lets the composition root translate an
/// `EngineProfile` (the central FSM's verdict) into stream settings through a
/// single code path instead of two near-identical copies that could drift.
///
/// The implementation lives on the trackers; this is only the contract the
/// provider layer programs against.
abstract interface class SamplingTarget {
  /// Applies an adaptive-sampling profile to the live position stream.
  ///
  /// See `GpsTrackerService.applySampling` for the full semantics: the
  /// interval, accuracy tier and movement filter shape the request, while
  /// [paused] closes the platform subscription outright so the GNSS receiver
  /// can sleep. [transportSpeed] is the sole exception that keeps GPS-grade
  /// accuracy while backgrounded.
  Future<void> applySampling({
    Duration? interval,
    LocationAccuracy? accuracy,
    int? distanceFilter,
    bool transportSpeed,
    bool paused,
  });
}
