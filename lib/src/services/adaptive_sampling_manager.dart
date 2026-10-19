import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'transport_classifier.dart';

/// A snapshot of the device battery as the adaptive sampler consumes it.
///
/// Deliberately coarse: the sampler only needs to know whether saving power is
/// urgent (and whether it can afford to spend it). The level is 0…1; `null`
/// means the platform refused to say, and the sampler then assumes a healthy
/// battery rather than throttling tracking on a guess.
class BatteryStatus {
  const BatteryStatus({required this.level, required this.charging});

  /// "Nothing was readable" — treated as a healthy, unplugged battery.
  static const BatteryStatus unknown =
      BatteryStatus(level: null, charging: false);

  /// Battery charge, 0…1, or `null` when unavailable.
  final double? level;

  /// Whether the device is plugged in / charging.
  final bool charging;

  /// Charge below which the sampler stretches its intervals.
  static const double lowThreshold = 0.2;

  /// True when the battery is low *and* not being charged (charging cancels
  /// the power concern). An unknown level (`null`) is treated as healthy —
  /// tracking is never throttled on a guess.
  bool get isLow => !charging && (level ?? 1) < lowThreshold;

  @override
  bool operator ==(Object other) =>
      other is BatteryStatus && other.level == level && other.charging == charging;

  @override
  int get hashCode => Object.hash(level, charging);
}

/// Where the sampler gets its [BatteryStatus] from. Production uses
/// [PlatformBatteryStatusSource]; tests inject a scripted source.
abstract class BatteryStatusSource {
  Future<BatteryStatus> read();
}

/// Where the [AdaptiveSamplingNotifier] reads the battery from. Colocated
/// with the sampler (not in `app_providers.dart`) so the notifier can read it
/// without a cyclic import; tests override it with a scripted source.
final Provider<BatteryStatusSource> batteryStatusProvider =
    Provider<BatteryStatusSource>(
  (Ref ref) => const PlatformBatteryStatusSource(),
);

/// Production source: reads the sticky `ACTION_BATTERY_CHANGED` broadcast
/// that `MainActivity`'s tracking method channel exposes as
/// `getBatteryLevel` (0…1). Falls back to [BatteryStatus.unknown] whenever the
/// platform is unavailable, so a dead channel degrades to "healthy battery"
/// instead of dropping tracking.
class PlatformBatteryStatusSource implements BatteryStatusSource {
  const PlatformBatteryStatusSource({this.channel = defaultChannel});

  /// Must match `TRACKING_CHANNEL` in `MainActivity.kt`.
  static const MethodChannel defaultChannel =
      MethodChannel('com.routenote.routenote/tracking');

  final MethodChannel channel;

  @override
  Future<BatteryStatus> read() async {
    try {
      final Object? raw = await channel.invokeMethod<Object?>('getBatteryLevel');
      if (raw is num) {
        // The platform reports a negative value when the level is unreadable
        // (no sticky broadcast, odd platform). That is "unknown", not "empty".
        final double value = raw.toDouble();
        if (value < 0) return BatteryStatus.unknown;
        final double clamped = value.clamp(0.0, 1.0).toDouble();
        return BatteryStatus(level: clamped, charging: false);
      }
      return BatteryStatus.unknown;
    } catch (_) {
      return BatteryStatus.unknown;
    }
  }
}

/// One decision of the adaptive sampler: how often the position stream should
/// ask for a fix, at what accuracy, given how the device is moving and how
/// much battery is left.
class SamplingProfile {
  const SamplingProfile({
    required this.mode,
    required this.interval,
    required this.accuracy,
    required this.distanceFilter,
    required this.battery,
  });

  /// Conservative default (matches the stationary profile): applied before
  /// any classifier verdict or battery reading has arrived.
  static const SamplingProfile defaults = SamplingProfile(
    mode: TransportMode.stationary,
    interval: stationaryInterval,
    accuracy: LocationAccuracy.lowest,
    distanceFilter: stationaryDistanceFilterMeters,
    battery: BatteryStatus.unknown,
  );

  /// Transport verdict the profile was computed for.
  final TransportMode mode;

  /// Minimum interval between position requests.
  final Duration interval;

  /// Accuracy the position stream should ask for.
  final LocationAccuracy accuracy;

  /// Metres the device must move between two delivered fixes.
  final int distanceFilter;

  /// Battery snapshot the profile was computed for.
  final BatteryStatus battery;

  /// True when the device is moving at **transport speeds** (vehicle or
  /// train).
  ///
  /// This is the only state that pays for GPS-grade (`high`) accuracy — in
  /// every other tier the balanced-power tier is what the receiver gets,
  /// which is what keeps the background duty cycle (and the battery) cheap.
  /// The trackers use this to lift the background accuracy cap while moving
  /// fast, where a coarse fix would turn a motorway into chords.
  bool get transportSpeeds =>
      mode == TransportMode.vehicle || mode == TransportMode.train;

  static const Duration vehicleInterval = Duration(seconds: 1);
  static const Duration trainInterval = Duration(seconds: 1);
  static const Duration walkingInterval = Duration(seconds: 15);
  static const Duration stationaryInterval = Duration(seconds: 60);

  /// Movement filters per tier. 10 m lets every 1 s vehicle fix and every
  /// 15 s walking fix through (both modes cover more than 10 m in a single
  /// interval), while the stationary tier's 50 m swallows GPS jitter
  /// outright, so a parked phone never wakes the fix callback at all.
  static const int vehicleDistanceFilterMeters = 10;
  static const int trainDistanceFilterMeters = 10;
  static const int walkingDistanceFilterMeters = 10;
  static const int stationaryDistanceFilterMeters = 50;

  @override
  bool operator ==(Object other) =>
      other is SamplingProfile &&
      other.mode == mode &&
      other.interval == interval &&
      other.accuracy == accuracy &&
      other.distanceFilter == distanceFilter &&
      other.battery == battery;

  @override
  int get hashCode =>
      Object.hash(mode, interval, accuracy, distanceFilter, battery);

  @override
  String toString() =>
      'SamplingProfile($mode, ${interval.inSeconds}s, $accuracy, '
      '${distanceFilter}m, $battery)';
}

/// Pure decision rule: transport mode + battery → [SamplingProfile].
///
/// The four motion tiers (documented in `AGENT_SKILLS.md`'s tracking section):
///
/// * **vehicle / train** — 1 s intervals at `high` accuracy: at 30 m/s a 5 s
///   default would space fixes 150 m apart, turning a motorway into a
///   polyline of chords; 1 s keeps the path on the road. Transport speeds
///   ([SamplingProfile.transportSpeeds]) are the *only* tier that pays for
///   GPS-grade fixes — in every other tier the receiver stays on the
///   balanced-power tier.
/// * **walking** — 15 s at `medium`: geolocator's `medium` *is* Android's
///   `PRIORITY_BALANCED_POWER_ACCURACY`, the balanced-power tier (the enum
///   has no literal `balanced` value). A walker covers ~20 m in that window,
///   right at the 10 m movement filter, so the cadence tracks real progress
///   without demanding a GPS lock for every step.
/// * **stationary** — 60 s at *lowest* accuracy behind a 50 m movement
///   filter: this is the "pause" tier. The filter swallows jitter outright
///   so the callback is not woken at all; the accelerometer classifier keeps
///   running and wakes sampling again the moment the device moves.
///
/// Battery then modulates every tier: below [BatteryStatus.lowThreshold]
/// (and not charging) the interval doubles and accuracy drops one notch;
/// while charging the interval halves so a plugged-in trip is captured at
/// maximum fidelity. The movement filter never changes with the battery —
/// it is a property of how far the device moves in one interval, not of how
/// much power is left.
@visibleForTesting
SamplingProfile computeProfile({
  required TransportMode mode,
  required BatteryStatus battery,
}) {
  Duration interval;
  LocationAccuracy accuracy;
  int distanceFilter;
  switch (mode) {
    case TransportMode.vehicle:
      interval = SamplingProfile.vehicleInterval;
      accuracy = LocationAccuracy.high;
      distanceFilter = SamplingProfile.vehicleDistanceFilterMeters;
    case TransportMode.train:
      interval = SamplingProfile.trainInterval;
      accuracy = LocationAccuracy.high;
      distanceFilter = SamplingProfile.trainDistanceFilterMeters;
    case TransportMode.walking:
      interval = SamplingProfile.walkingInterval;
      accuracy = LocationAccuracy.medium;
      distanceFilter = SamplingProfile.walkingDistanceFilterMeters;
    case TransportMode.stationary:
      interval = SamplingProfile.stationaryInterval;
      accuracy = LocationAccuracy.lowest;
      distanceFilter = SamplingProfile.stationaryDistanceFilterMeters;
  }
  if (battery.isLow) {
    interval = interval * 2;
    accuracy = _oneNotchDown(accuracy);
  } else if (battery.charging) {
    final Duration halved = interval ~/ 2;
    interval = halved < SamplingProfile.vehicleInterval
        ? SamplingProfile.vehicleInterval
        : halved;
  }
  return SamplingProfile(
    mode: mode,
    interval: interval,
    accuracy: accuracy,
    distanceFilter: distanceFilter,
    battery: battery,
  );
}

LocationAccuracy _oneNotchDown(LocationAccuracy accuracy) {
  switch (accuracy) {
    case LocationAccuracy.bestForNavigation:
    case LocationAccuracy.best:
    case LocationAccuracy.high:
      return LocationAccuracy.medium;
    case LocationAccuracy.medium:
      return LocationAccuracy.low;
    case LocationAccuracy.low:
    case LocationAccuracy.lowest:
    case LocationAccuracy.reduced:
      return LocationAccuracy.lowest;
  }
}

/// Battery-aware dynamic sampling: recomputes the tracking profile whenever
/// the transport mode or the battery changes, and exposes it as Riverpod
/// state so the tracker can re-open its stream at the new cadence.
///
/// The transport mode arrives from `TransportClassifier` (wired in
/// `AutoMotionController`); the battery is polled on a slow timer while
/// [startPolling] is active — once a minute, which is far below anything the
/// receiver itself costs. Nothing here touches location data, so nothing here
/// can leak it: the whole state is an enum, a duration and an accuracy tier.
class AdaptiveSamplingNotifier extends Notifier<SamplingProfile> {
  /// How often the battery is re-read while polling.
  static const Duration batteryPollEvery = Duration(seconds: 60);

  TransportMode _mode = TransportMode.stationary;
  BatteryStatus _battery = BatteryStatus.unknown;
  Timer? _pollTimer;

  @override
  SamplingProfile build() {
    ref.onDispose(() {
      _pollTimer?.cancel();
      _pollTimer = null;
    });
    return SamplingProfile.defaults;
  }

  /// The latest battery snapshot the profile was computed with.
  BatteryStatus get battery => _battery;

  /// Latest transport verdict the profile was computed with.
  TransportMode get mode => _mode;

  /// Feeds a new transport verdict; recomputes the profile when it changed.
  void observeTransport(TransportMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    _recompute();
  }

  /// Re-reads the battery now (and starts no timer). Safe to call any time;
  /// a failed read degrades to "unknown" (healthy) rather than throttling.
  Future<void> refreshBattery() async {
    final BatteryStatusSource source = ref.read(batteryStatusProvider);
    final BatteryStatus battery = await source.read();
    if (battery == _battery) return;
    _battery = battery;
    _recompute();
  }

  /// Starts the slow battery poll. Idempotent; the timer is cancelled on
  /// provider disposal.
  void startPolling() {
    if (_pollTimer != null) return;
    unawaited(refreshBattery());
    _pollTimer = Timer.periodic(batteryPollEvery, (_) {
      unawaited(refreshBattery());
    });
  }

  /// Stops the battery poll (tracking ended).
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Recomputes the profile from the current inputs, advancing [state] only
  /// on an actual change (so listeners never see no-op churn).
  void _recompute() {
    final SamplingProfile next = computeProfile(mode: _mode, battery: _battery);
    if (next != state) state = next;
  }
}

/// The live tracking profile (minimum request interval + accuracy tier for
/// the current motion and battery state). `AutoMotionController` listens to
/// this and pushes changed profiles into the tracker.
final NotifierProvider<AdaptiveSamplingNotifier, SamplingProfile>
    adaptiveSamplingProvider =
    NotifierProvider<AdaptiveSamplingNotifier, SamplingProfile>(
  AdaptiveSamplingNotifier.new,
);
