import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Independent "is the device moving?" evidence, used by the daily trackers to
/// bridge GPS outages (tunnels, parking garages, urban canyons).
///
/// GPS alone cannot answer this: the outage *is* the missing measurement. So
/// while a tracker is running the sensor bridge keeps sampling the device's
/// accelerometer, and every accepted fix also contributes its Doppler speed
/// (sensor + GPS fusion). The trackers then only bridge the geometric gap
/// between the last fix and the recovering fix when [lastMotionAt] is newer than
/// that last fix — i.e. when the phone demonstrably kept moving through the
/// blackout instead of simply being parked.
abstract class MotionSignal {
  /// Wall-clock time of the most recent motion evidence, or `null` when the
  /// device has not been seen moving since this service was created.
  DateTime? get lastMotionAt;

  /// Whether the motion evidence is recent enough to call the device "moving"
  /// right now (see [MotionClassifier.evidenceTtl]).
  bool get inTransit;

  /// Joins the signal (reference counted). The sensor bridge only samples while
  /// at least one tracker is running, so leaving both toggles off costs nothing.
  Future<void> start();

  /// Releases one [start] (reference counted).
  Future<void> stop();

  /// Fuses the Doppler speed (m/s) of an accepted GPS fix as motion evidence.
  void observeSpeed(double metersPerSecond);
}

/// The default [MotionSignal]: no sensor bridge is wired up (unit tests, iOS,
/// unsupported platforms), so the trackers fall back to the plain fix-to-fix
/// window and never bridge a long outage.
class NoMotionSignal implements MotionSignal {
  const NoMotionSignal();

  @override
  DateTime? get lastMotionAt => null;

  @override
  bool get inTransit => false;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void observeSpeed(double metersPerSecond) {}
}

/// Pure-Dart movement classifier: turns raw accelerometer samples into motion
/// evidence.
///
/// Gravity is tracked with a slow low-pass filter and removed from every
/// sample; what remains is the vibration of the engine / road / hand. A phone
/// lying on a desk reads far below [vibrationThreshold], a phone in a moving
/// vehicle far above it, so the classifier survives the phone being held at any
/// angle.
///
/// The classifier is deliberately platform-free so it can be unit tested with
/// synthetic samples (see `test/motion_signal_test.dart`).
class MotionClassifier {
  MotionClassifier({
    DateTime Function()? clock,
    this.windowSamples = 16,
    this.gravityAdaptation = 0.1,
    this.vibrationThreshold = 0.28,
    this.evidenceTtl = const Duration(seconds: 30),
  })  : assert(windowSamples > 0),
        _clock = clock ?? DateTime.now;

  /// How many residual samples are RMS-averaged before a verdict is produced.
  /// At the Android `SENSOR_DELAY_UI` rate (~16 Hz) this is about one second.
  final int windowSamples;

  /// Weight of each new sample in the gravity estimate (0…1). Small enough that
  /// the filter follows the phone's attitude but not the vibration itself.
  final double gravityAdaptation;

  /// RMS residual (m/s²) above which the window counts as "in a moving
  /// vehicle". Below it are sensor noise and a hand-held phone.
  final double vibrationThreshold;

  /// How long a single piece of evidence keeps [inTransit] true. Continuous
  /// vibration refreshes it, so a tunnel keeps the device "moving" for as long
  /// as the car actually is.
  final Duration evidenceTtl;

  /// Doppler speed above which a GPS fix alone counts as motion evidence
  /// (m/s, i.e. ≈ 5 km/h).
  static const double movingSpeedThresholdMps = 1.4;

  final DateTime Function() _clock;

  double _gravityX = 0;
  double _gravityY = 0;
  double _gravityZ = 0;
  bool _gravitySeeded = false;

  final List<double> _residuals = <double>[];
  DateTime? _lastMotionAt;

  DateTime? get lastMotionAt => _lastMotionAt;

  bool get inTransit {
    final DateTime? last = _lastMotionAt;
    return last != null && _clock().difference(last) < evidenceTtl;
  }

  /// Feeds one raw accelerometer sample (m/s², gravity included) and returns
  /// whether this sample produced motion evidence.
  bool feedAcceleration(double x, double y, double z) {
    if (!_gravitySeeded) {
      _gravityX = x;
      _gravityY = y;
      _gravityZ = z;
      _gravitySeeded = true;
    } else {
      _gravityX += (x - _gravityX) * gravityAdaptation;
      _gravityY += (y - _gravityY) * gravityAdaptation;
      _gravityZ += (z - _gravityZ) * gravityAdaptation;
    }

    final double residualX = x - _gravityX;
    final double residualY = y - _gravityY;
    final double residualZ = z - _gravityZ;
    _residuals.add(math.sqrt(
      residualX * residualX + residualY * residualY + residualZ * residualZ,
    ));
    if (_residuals.length > windowSamples) {
      _residuals.removeAt(0);
    }
    if (_residuals.length < windowSamples) return false;

    double sumSquares = 0;
    for (final double residual in _residuals) {
      sumSquares += residual * residual;
    }
    final double rms = math.sqrt(sumSquares / _residuals.length);
    if (rms.isNaN || rms < vibrationThreshold) return false;

    _lastMotionAt = _clock();
    return true;
  }

  /// Fuses a Doppler speed reading (m/s) from a GPS fix. Returns whether the
  /// reading counted as motion evidence.
  bool observeSpeed(double metersPerSecond) {
    if (!metersPerSecond.isFinite ||
        metersPerSecond.abs() < movingSpeedThresholdMps) {
      return false;
    }
    _lastMotionAt = _clock();
    return true;
  }
}

/// Accelerometer-backed [MotionSignal] (Android sensor bridge).
///
/// Raw samples arrive on the `com.routenote.routenote/motion` event channel
/// (see `MotionSensorChannel.kt`); classification happens here in Dart so the
/// interesting logic stays unit-testable. Outside Android the bridge is inert
/// and only the GPS-speed fusion contributes evidence.
class SensorMotionSignal implements MotionSignal {
  SensorMotionSignal({
    EventChannel? channel,
    MotionClassifier? classifier,
  })  : _channel = channel ?? const EventChannel(channelName),
        classifier = classifier ?? MotionClassifier();

  /// Must match `MOTION_CHANNEL` in `MainActivity.kt`.
  static const String channelName = 'com.routenote.routenote/motion';

  final EventChannel _channel;

  /// The classifier behind this signal, exposed for diagnostics and tests.
  final MotionClassifier classifier;

  StreamSubscription<dynamic>? _subscription;
  int _users = 0;

  @override
  DateTime? get lastMotionAt => classifier.lastMotionAt;

  @override
  bool get inTransit => classifier.inTransit;

  @override
  Future<void> start() async {
    _users += 1;
    if (_users != 1) return;
    // The sensor bridge is Android-only; elsewhere the GPS-speed fusion is all
    // the evidence there is (and the channel has no handler).
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      _subscription = _channel.receiveBroadcastStream().listen(
        _onSample,
        onError: (Object _) {
          // No accelerometer / sensor error: fall back to speed-only evidence.
        },
      );
    } catch (_) {
      // Platform channel unavailable (tests / unsupported platform).
    }
  }

  @override
  Future<void> stop() async {
    _users = math.max(0, _users - 1);
    if (_users != 0) return;
    final StreamSubscription<dynamic>? subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  @override
  void observeSpeed(double metersPerSecond) =>
      classifier.observeSpeed(metersPerSecond);

  /// Consumes one `[x, y, z]` accelerometer sample from the platform.
  void _onSample(dynamic event) {
    if (event is! List || event.length < 3) return;
    final Object? x = event[0];
    final Object? y = event[1];
    final Object? z = event[2];
    if (x is! num || y is! num || z is! num) return;
    classifier.feedAcceleration(x.toDouble(), y.toDouble(), z.toDouble());
  }
}
