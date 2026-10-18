import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Result of a location request.
sealed class LocationResult {
  const LocationResult();
}

class LocationSuccess extends LocationResult {
  const LocationSuccess({
    required this.latitude,
    required this.longitude,
    this.accuracy,
  });

  final double latitude;
  final double longitude;
  final double? accuracy;
}

class LocationPermissionDenied extends LocationResult {
  const LocationPermissionDenied({required this.permanentlyDenied});

  final bool permanentlyDenied;
}

class LocationServiceDisabled extends LocationResult {
  const LocationServiceDisabled();
}

class LocationFailure extends LocationResult {
  const LocationFailure(this.message);

  final String message;
}

/// A snapshot of the device's location availability, used by UI indicators.
class LocationStatus {
  const LocationStatus({
    required this.serviceEnabled,
    required this.permission,
  });

  /// Whether the system location service (GPS) is switched on.
  final bool serviceEnabled;

  /// The current permission level the OS reports for this app.
  final LocationPermission permission;

  /// True when the app is allowed to read the device location.
  bool get permissionGranted =>
      permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;

  /// True when the user must act before location can be read.
  bool get needsAction => !serviceEnabled || !permissionGranted;
}

/// GPS capture built on `geolocator`.
class LocationService {
  const LocationService();

  /// Horizontal distance, in metres, a device must move between two fixes of
  /// [positionStream]. 10 m is coarse enough to keep the GPS duty cycle (and
  /// therefore the battery) sane while still resolving a street-level path.
  static const int trackingDistanceFilterMeters = 10;

  /// The stream settings every long-running tracker uses while MapNote is
  /// **visible**: best-available accuracy with a 10 m movement filter.
  ///
  /// On Android this is [AndroidSettings] with `forceLocationManager: false`,
  /// i.e. the **Fused Location Provider** (`FusedLocationProviderClient`) rather
  /// than the raw `LocationManager`. The fused provider is the sensor-fusion
  /// layer: it combines GPS, Wi-Fi, cell-tower and on-device motion/sensor
  /// inputs, so while the GPS signal is obstructed (tunnel, dense city, indoor
  /// car park) it still produces fixes from Wi-Fi/cell/sensors instead of
  /// going silent. `intervalDuration` pins the fused request interval to 5 s
  /// (the plugin's own default, made explicit here) and `distanceFilter` keeps
  /// the 10 m movement threshold.
  ///
  /// On iOS this is [AppleSettings] with background updates allowed, matching
  /// the `UIBackgroundModes`/`NSLocationAlwaysAndWhenInUseUsageDescription`
  /// entries in `Info.plist`: `pauseLocationUpdatesAutomatically` is disabled so
  /// CoreLocation keeps delivering fixes to a backgrounded app, and the activity
  /// type is `fitness` so the mitigation that would otherwise stop a stationary
  /// walker from receiving fixes does not kick in. Everywhere else the plain
  /// high-accuracy settings apply.
  static final LocationSettings trackingLocationSettings = trackingSettingsFor();

  /// The same profile at reduced precision for a **backgrounded** tracker, so
  /// the receiver's duty cycle (and therefore the battery) drops when the
  /// screen is off: [LocationAccuracy.medium] is geolocator's name for
  /// Android's `PRIORITY_BALANCED_POWER_ACCURACY` — Wi-Fi/cell/sensor-assisted
  /// fixes instead of demanding a continuous GPS lock (geolocator's enum has
  /// no literal `balanced` value; `medium` *is* the balanced-power tier) — and
  /// iOS applies its matching reduced-precision accuracy. The 10 m movement
  /// filter and the 5 s interval are unchanged, so every measurement rule
  /// (jitter, min-step, speed caps, gap recovery) behaves identically in both
  /// modes; only the power cost of obtaining a fix changes.
  static final LocationSettings backgroundTrackingLocationSettings =
      trackingSettingsFor(accuracy: LocationAccuracy.medium);

  /// Builds a tracking profile: accuracy (defaults to [LocationAccuracy.high]),
  /// the fused-provider request interval (defaults to 5 s) and the movement
  /// filter in metres (defaults to 10 m).
  ///
  /// The adaptive sampling manager derives its profiles from this — e.g. a
  /// one-second interval while in a fast vehicle, a one-minute / passive
  /// profile while stationary — while [trackingLocationSettings] and
  /// [backgroundTrackingLocationSettings] stay the two fixed baselines.
  static LocationSettings trackingSettingsFor({
    LocationAccuracy? accuracy,
    Duration? intervalDuration,
    int? distanceFilter,
  }) {
    final LocationAccuracy resolvedAccuracy =
        accuracy ?? LocationAccuracy.high;
    final Duration resolvedInterval =
        intervalDuration ?? const Duration(seconds: 5);
    final int resolvedDistanceFilter =
        distanceFilter ?? trackingDistanceFilterMeters;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
          accuracy: resolvedAccuracy,
          distanceFilter: resolvedDistanceFilter,
          forceLocationManager: false,
          intervalDuration: resolvedInterval,
        ),
      TargetPlatform.iOS => AppleSettings(
          accuracy: resolvedAccuracy,
          distanceFilter: resolvedDistanceFilter,
          activityType: ActivityType.fitness,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
        ),
      _ => LocationSettings(
          accuracy: resolvedAccuracy,
          distanceFilter: resolvedDistanceFilter,
        ),
    };
  }

  /// Raw position stream (default settings: [trackingLocationSettings]).
  ///
  /// Use [trackingPositionStream] when the stream has to survive platform
  /// failures — this raw stream closes for good when it errors.
  Stream<Position> positionStream({LocationSettings? settings}) =>
      Geolocator.getPositionStream(
        locationSettings: settings ?? trackingLocationSettings,
      );

  /// The stream the daily trackers subscribe to: [positionStream] wrapped in
  /// [reconnectingPositionStream], so a dropped or closed platform stream is
  /// re-opened with capped backoff instead of silently freezing tracking.
  ///
  /// [onError] reports every failure that triggered a reconnect (never called
  /// for fixes that were merely rejected by the accumulator's noise filters).
  Stream<Position> trackingPositionStream({
    LocationSettings? settings,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) =>
      reconnectingPositionStream(
        () => positionStream(settings: settings),
        onError: onError,
      );

  /// The OS's own report of the location provider being switched **off** and
  /// back **on** (`geolocator`'s service-status stream).
  ///
  /// This is what lets a tracker tell a real GPS outage — the user toggled
  /// location, or the OS throttled the provider — apart from a parked phone
  /// that simply stops producing fixes: the daily engines arm their
  /// gap-recovery pass on [ServiceStatus.disabled] and judge the skipped span
  /// against a plausible-speed ceiling when fixes come back.
  Stream<ServiceStatus> serviceStatusStream() =>
      Geolocator.getServiceStatusStream();

  /// The most recent position the OS has cached for this app, or `null` when
  /// there is none.
  ///
  /// This is the cheap, non-blocking counterpart to [determinePosition]:
  /// `Geolocator.getLastKnownPosition` returns the platform's cached fix
  /// immediately instead of powering up the receiver, so UI that only needs an
  /// approximate location (for example the Qibla bearing) can render the moment
  /// it opens and then refine itself from [trackingPositionStream].
  Future<Position?> lastKnownPosition() => Geolocator.getLastKnownPosition();

  Future<LocationResult> determinePosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationServiceDisabled();
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return LocationPermissionDenied(
        permanentlyDenied: permission == LocationPermission.deniedForever,
      );
    }

    try {
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return LocationSuccess(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
    } catch (e) {
      return LocationFailure(e.toString());
    }
  }

  /// Whether the system location service (GPS) is currently enabled.
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  /// Reads the current permission level without prompting the user.
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  /// Shows the OS permission dialog when possible.
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}

/// Wraps [open] in a stream that survives the source failing.
///
/// `geolocator`'s stream can deliver an error and then close — the fused
/// location provider restarts, the OS reclaims the receiver, the app gets
/// throttled. The subscription then stays "open" while never delivering another
/// fix, so tracking *looks* alive and records nothing. Every failure (an error
/// **or** an unexpected completion) is reported through [onError] and re-opens
/// the source with exponential backoff capped at [maxBackoff]; one real fix
/// resets the backoff. Cancelling the returned stream cancels the pending
/// reconnect too, so a test never leaks a timer.
Stream<Position> reconnectingPositionStream(
  Stream<Position> Function() open, {
  Duration initialBackoff = const Duration(seconds: 2),
  Duration maxBackoff = const Duration(minutes: 1),
  void Function(Object error, StackTrace stackTrace)? onError,
}) {
  final _PositionReconnector reconnector = _PositionReconnector(
    open: open,
    initialBackoff: initialBackoff,
    maxBackoff: maxBackoff,
    onError: onError,
  );

  final StreamController<Position> controller = StreamController<Position>(
    onListen: reconnector.connect,
    onCancel: reconnector.cancel,
  );
  reconnector.sink = controller;
  return controller.stream;
}

/// Owns one [reconnectingPositionStream] subscription: its backoff timer, the
/// current inner subscription, and the teardown that stops both.
class _PositionReconnector {
  _PositionReconnector({
    required this.open,
    required this.initialBackoff,
    required this.maxBackoff,
    required this.onError,
  });

  final Stream<Position> Function() open;
  final Duration initialBackoff;
  final Duration maxBackoff;
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// The outer controller this reconnector feeds; assigned right after the
  /// controller is constructed (its `onListen` needs [connect]).
  late final StreamController<Position> sink;

  StreamSubscription<Position>? _subscription;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _cancelled = false;

  /// Opens the source. Any synchronous failure counts as a failure too.
  void connect() {
    _reconnectTimer = null;
    if (sink.isClosed || _cancelled) return;
    try {
      _subscription = open().listen(
        (Position position) {
          // A real fix proves the channel is healthy: restart the backoff so
          // the next hiccup reconnects quickly instead of waiting a minute.
          _attempt = 0;
          sink.add(position);
        },
        onError: (Object error, StackTrace stackTrace) {
          onError?.call(error, stackTrace);
          scheduleReconnect();
        },
        // A stream that simply ended is just as dead as one that errored.
        onDone: scheduleReconnect,
        cancelOnError: true,
      );
    } catch (error, stackTrace) {
      onError?.call(error, stackTrace);
      scheduleReconnect();
    }
  }

  /// Cancels the dead subscription and re-opens the source after a delay.
  void scheduleReconnect() {
    if (sink.isClosed) return;
    _attempt += 1;
    // 2s, 4s, 8s, 16s, 32s, then the 1 minute ceiling.
    final int factor = 1 << (_attempt < 6 ? _attempt - 1 : 5);
    final int delayMs = math.min<int>(
      initialBackoff.inMilliseconds * factor,
      maxBackoff.inMilliseconds,
    );
    _reconnectTimer?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), connect);
  }

  /// Tears everything down; called when the tracker unsubscribes.
  Future<void> cancel() async {
    _cancelled = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _attempt = 0;
    final StreamSubscription<Position>? subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }
}
