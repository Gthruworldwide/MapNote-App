import 'dart:async';
import 'dart:math' as math;

import '../../services/motion_sensor_hub.dart';
import 'session_guard.dart';

/// Detects whether the device is being **hand-held** or is lying **still on a
/// surface**, from the accelerometer's micro-movements alone.
///
/// This is the sensor half of the security story. [SessionGuard] decides *when*
/// a session expires, but it needs to know whether the phone is in someone's
/// hand or abandoned on a café table — a desk-resting phone is the realistic
/// theft case, and it deserves a much shorter leash than one being carried and
/// used. The guard deliberately takes a boolean so it stays pure; this class is
/// where the boolean comes from.
///
/// How it judges: a device being held is never perfectly still. Even a hand at
/// rest produces small orientation tremors, and a device being carried produces
/// steps and swings. A device on a solid surface holds its orientation and its
/// residual amplitude stays under the sensor's own noise floor. So the signal is
/// **orientation drift** (a slow low-pass of the gravity vector) plus a low
/// **motion-energy** gate — not raw amplitude, which a single bump would trip.
///
/// Privacy: it consumes raw sensor vectors and emits an enum. Nothing is logged,
/// stored or transmitted; no location, identity or user content is involved.
class DeviceLockDetector {
  DeviceLockDetector({
    required this.hub,
    this.stillnessThreshold = const Duration(seconds: 20),
    this.movementEnergyMps2 = 0.12,
    this.orientationDriftDegrees = 3.0,
    this.accelerationStream,
  });

  /// How long the device must be still before it is judged surface-idle.
  ///
  /// Deliberately generous: people hold a phone perfectly still while reading,
  /// and flipping the vault's timeout to the short clock every time they pause
  /// would be hostile. 20 s of *literal* stillness is a phone that was put down.
  final Duration stillnessThreshold;

  /// Residual motion (gravity removed) above which the device counts as moving.
  /// 0.12 m/s² is comfortably above a phone resting on a hard surface and
  /// comfortably below the tremor of a hand holding one.
  final double movementEnergyMps2;

  /// How far the gravity vector must rotate to count as a re-orientation, in
  /// degrees. Picking a phone up or turning a wrist moves it far more than this;
  /// a device on a desk drifts only fractions of a degree.
  final double orientationDriftDegrees;

  final MotionSensorHub hub;

  /// Overrides the sensor feed (tests drive samples directly).
  final Stream<AccelerometerSample>? accelerationStream;

  StreamSubscription<AccelerometerSample>? _subscription;

  /// Emits the verdict whenever it changes (broadcast).
  ///
  /// A stream rather than a poll: the privacy dimmer listens to it, so the cue
  /// appears on the transition instead of on the next timer tick, and nothing has
  /// to keep a periodic timer alive.
  final StreamController<InteractionContext> _contexts =
      StreamController<InteractionContext>.broadcast();

  /// Gravity estimate (low-pass of the raw vector), the orientation reference.
  double _gx = 0;
  double _gy = 0;
  double _gz = 0;
  bool _hasGravity = false;

  DateTime? _lastMovementAt;
  InteractionContext _context = InteractionContext.unknown;
  bool _running = false;
  bool _disposed = false;
  int _samples = 0;

  /// How strongly gravity is smoothed. ~0.05 separates orientation drift (which
  /// this must track) from tremor (which must not register as drift).
  static const double _gravityAdaptation = 0.05;

  /// Current verdict. Starts [InteractionContext.unknown] until samples arrive.
  InteractionContext get context => _context;

  /// The verdict changes, as a broadcast stream.
  Stream<InteractionContext> get contextChanges => _contexts.stream;

  /// Sets the verdict and notifies listeners only on an actual change.
  void _setContext(InteractionContext next) {
    if (next == _context) return;
    _context = next;
    if (!_disposed) _contexts.add(next);
  }

  /// Whether the detector is listening to the sensor feed.
  bool get isRunning => _running;

  /// Samples processed (diagnostics/tests).
  int get sampleCount => _samples;

  /// Convenience for callers that just need the boolean [SessionGuard] wants.
  bool get isHandHeld => _context != InteractionContext.surfaceIdle;

  /// Starts listening. Idempotent. Never throws: without the sensor the verdict
  /// simply stays [InteractionContext.unknown], which the guard treats as
  /// hand-held (i.e. the *longer* timeout), so a broken sensor can never
  /// surprise the user by locking a session early.
  ///
  /// When a caller supplies [accelerationStream] it owns the hardware, so the
  /// hub is left alone — the detector only reference-counts the shared hub on
  /// the production path.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    final Stream<AccelerometerSample>? override = accelerationStream;
    if (override == null) await hub.start();
    _subscription = (override ?? hub.accelerometer).listen(
      handleSample,
      onError: (Object _) {
        // A sensor error leaves the verdict where it was; nothing to do.
      },
    );
  }

  /// Processes one raw accelerometer sample.
  ///
  /// Public so a test can drive the judgement sample-by-sample with exact
  /// timing instead of racing a stream.
  void handleSample(AccelerometerSample sample, {DateTime? at}) {
    _samples += 1;
    final DateTime now = at ?? sample.at;

    if (!_hasGravity) {
      _gx = sample.x;
      _gy = sample.y;
      _gz = sample.z;
      _hasGravity = true;
      _lastMovementAt = now;
      _setContext(InteractionContext.handHeld);
      return;
    }

    // Slowly track gravity, so a deliberate re-orientation is absorbed without
    // a step change being mistaken for a tremor.
    _gx += (sample.x - _gx) * _gravityAdaptation;
    _gy += (sample.y - _gy) * _gravityAdaptation;
    _gz += (sample.z - _gz) * _gravityAdaptation;

    // Residual = what is left after the steady pull of gravity, i.e. actual
    // motion. Orientation drift = how far the raw vector has rotated away from
    // the smoothed gravity estimate.
    final double rx = sample.x - _gx;
    final double ry = sample.y - _gy;
    final double rz = sample.z - _gz;
    final double residual = math.sqrt(rx * rx + ry * ry + rz * rz);

    final double gNorm = math.sqrt(_gx * _gx + _gy * _gy + _gz * _gz);
    final double sNorm =
        math.sqrt(sample.x * sample.x + sample.y * sample.y + sample.z * sample.z);
    double driftDegrees = 0;
    if (gNorm > 0.1 && sNorm > 0.1) {
      final double cosAngle =
          ((_gx * sample.x + _gy * sample.y + _gz * sample.z) / (gNorm * sNorm))
              .clamp(-1.0, 1.0);
      driftDegrees = math.acos(cosAngle) * 180 / math.pi;
    }

    final bool moving =
        residual >= movementEnergyMps2 || driftDegrees >= orientationDriftDegrees;
    if (moving) _lastMovementAt = now;

    final DateTime? lastMove = _lastMovementAt;
    if (lastMove == null) {
      _setContext(InteractionContext.handHeld);
      return;
    }
    _setContext(
      now.difference(lastMove) >= stillnessThreshold
          ? InteractionContext.surfaceIdle
          : InteractionContext.handHeld,
    );
  }

  /// Clears the evidence and returns to [InteractionContext.unknown].
  ///
  /// Called when a session ends, so the next session starts from a neutral
  /// verdict instead of inheriting the previous one.
  void reset() {
    _hasGravity = false;
    _lastMovementAt = null;
    _samples = 0;
    _setContext(InteractionContext.unknown);
  }

  /// Stops listening and releases the sensor reference.
  Future<void> stop() async {
    _running = false;
    final StreamSubscription<AccelerometerSample>? subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  Future<void> dispose() async {
    await stop();
    _disposed = true;
    await _contexts.close();
  }
}
