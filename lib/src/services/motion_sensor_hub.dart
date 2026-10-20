import 'dart:async';

import 'package:flutter/services.dart';

/// One raw accelerometer reading (m/s², device axes, gravity included),
/// timestamped on arrival in Dart — the platform channel carries no clock.
class AccelerometerSample {
  const AccelerometerSample(this.x, this.y, this.z, this.at);

  final double x;
  final double y;
  final double z;
  final DateTime at;
}

/// One raw gyroscope reading (rad/s around the device axes), timestamped on
/// arrival in Dart. Android's z axis is the yaw rate a flat-mounted phone
/// experiences; dead reckoning integrates it into a world heading.
class GyroscopeSample {
  const GyroscopeSample(this.x, this.y, this.z, this.at);

  final double x;
  final double y;
  final double z;
  final DateTime at;
}

/// Single-subscription hub over the native motion `EventChannel`
/// (`com.routenote.routenote/motion`, see `MotionSensorChannel.kt`).
///
/// The platform channel accepts **one** Dart subscriber at a time — a second
/// `receiveBroadcastStream().listen` would silently steal the native event
/// sink from the first — but three consumers now need the same sensor feed:
/// the trackers' movement signal, the transport-mode classifier and the
/// dead-reckoning engine. The hub is that one subscriber: it opens the channel
/// once and fans the parsed samples out to any number of broadcast listeners,
/// reference-counted so the hardware is only sampled while at least one
/// consumer is running (see [start]/[stop]).
///
/// Events are `[x, y, z, tag]` where `tag` is `0` for the accelerometer and
/// `1` for the gyroscope; a bare `[x, y, z]` payload (older builds, tests)
/// counts as an accelerometer sample. Everything else is ignored, so a
/// malformed event can never poison a consumer. No location, identity or user
/// data ever crosses this channel — raw sensor vectors only.
class MotionSensorHub {
  MotionSensorHub({
    EventChannel? channel,
    DateTime Function()? clock,
  })  : _channel = channel ?? const EventChannel(channelName),
        _clock = clock ?? DateTime.now;

  /// Must match `MOTION_CHANNEL` in `MainActivity.kt`.
  static const String channelName = 'com.routenote.routenote/motion';

  /// Payload tag distinguishing the two sensors multiplexed on one channel.
  static const int accelerometerTag = 0;
  static const int gyroscopeTag = 1;

  final EventChannel _channel;
  final DateTime Function() _clock;

  final StreamController<AccelerometerSample> _accelerometers =
      StreamController<AccelerometerSample>.broadcast();
  final StreamController<GyroscopeSample> _gyroscopes =
      StreamController<GyroscopeSample>.broadcast();

  StreamSubscription<dynamic>? _subscription;
  int _users = 0;

  /// Parsed accelerometer feed (broadcast; buffers nothing while unlistened).
  Stream<AccelerometerSample> get accelerometer => _accelerometers.stream;

  /// Parsed gyroscope feed (broadcast; buffers nothing while unlistened).
  Stream<GyroscopeSample> get gyroscope => _gyroscopes.stream;

  /// How many consumers currently hold the hardware open (diagnostics/tests).
  int get userCount => _users;

  /// Whether the native channel is currently being listened to.
  bool get isListening => _subscription != null;

  /// Opens the native channel on the first consumer; later calls only bump the
  /// reference count. Never throws: without the channel (tests, iOS, a device
  /// without the sensor) the streams simply stay silent.
  Future<void> start() async {
    _users += 1;
    if (_users != 1) return;
    try {
      _subscription = _channel.receiveBroadcastStream().listen(
            handlePlatformEvent,
            onError: (Object _) {
              // No accelerometer / sensor error: consumers stay silent.
            },
          );
    } catch (_) {
      // Platform channel unavailable (tests / unsupported platform).
    }
  }

  /// Releases one consumer; the last release cancels the native subscription
  /// so no sensor is sampled while MapNote is not tracking.
  Future<void> stop() async {
    if (_users == 0) return;
    _users -= 1;
    if (_users != 0) return;
    final StreamSubscription<dynamic>? subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  /// Cancels the native subscription outright and closes both broadcast feeds.
  /// The hub is unusable afterwards; used from `ref.onDispose`. Closing is what
  /// detaches any listener still attached, so a later `start()` cannot silently
  /// revive a hub that the container already dropped.
  Future<void> dispose() async {
    _users = 0;
    final StreamSubscription<dynamic>? subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    await _accelerometers.close();
    await _gyroscopes.close();
  }

  /// Routes one raw platform event to the matching broadcast stream.
  /// Public so tests can drive the hub without a binary messenger.
  void handlePlatformEvent(Object? event) {
    final DateTime at = _clock();
    final AccelerometerSample? accelerometer = parseAccelerometer(event, at);
    if (accelerometer != null) {
      _accelerometers.add(accelerometer);
      return;
    }
    final GyroscopeSample? gyroscope = parseGyroscope(event, at);
    if (gyroscope != null) {
      _gyroscopes.add(gyroscope);
    }
  }

  /// Parses an `[x, y, z, tag]` (or bare `[x, y, z]`) payload as an
  /// accelerometer sample; `null` when the payload is not one.
  static AccelerometerSample? parseAccelerometer(Object? event, DateTime at) {
    final List<double>? values = _sampleValues(event, accelerometerTag);
    if (values == null) return null;
    return AccelerometerSample(values[0], values[1], values[2], at);
  }

  /// Parses an `[x, y, z, tag]` payload as a gyroscope sample; `null` when the
  /// payload is not one (a bare `[x, y, z]` is accelerometer data).
  static GyroscopeSample? parseGyroscope(Object? event, DateTime at) {
    final List<double>? values = _sampleValues(event, gyroscopeTag);
    if (values == null) return null;
    return GyroscopeSample(values[0], values[1], values[2], at);
  }

  /// Returns the three axis values of [event] when its shape and sensor tag
  /// match [tag]; `null` otherwise. Untyped values are coerced with `num`, so
  /// platform ints and doubles are both accepted.
  static List<double>? _sampleValues(Object? event, int tag) {
    if (event is! List || event.length < 3) return null;
    final Object? eventTag = event.length > 3 ? event[3] : accelerometerTag;
    if (eventTag is! num || eventTag.toInt() != tag) return null;
    final Object? x = event[0];
    final Object? y = event[1];
    final Object? z = event[2];
    if (x is! num || y is! num || z is! num) return null;
    if (!x.isFinite || !y.isFinite || !z.isFinite) return null;
    return <double>[x.toDouble(), y.toDouble(), z.toDouble()];
  }
}
