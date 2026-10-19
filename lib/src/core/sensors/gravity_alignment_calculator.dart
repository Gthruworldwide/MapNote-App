import 'dart:math' as math;

/// One accelerometer reading projected into the vehicle frame, gravity
/// removed, in m/s².
///
/// The frame is **right-handed**: `Z` runs forward along the vehicle's
/// longitudinal axis, `Y` points up against gravity, and `X` completes the
/// triad — which, for a right-handed frame, means it points to the driver's
/// **left**. Every sign below follows that single convention:
///
/// * [longitudinal] (`Z_car`) `> 0` accelerating, `< 0` braking;
/// * [lateral] (`X_car`) `> 0` a left-hand turn, `< 0` a right-hand turn;
/// * [vertical] (`Y_car`) `> 0` rising (a speed bump's lip), `< 0` dropping
///   (a pothole).
class VehicleAcceleration {
  const VehicleAcceleration({
    required this.lateral,
    required this.vertical,
    required this.longitudinal,
  });

  /// `X_car` — lateral forces: cornering, lane changes.
  final double lateral;

  /// `Y_car` — vertical impacts: speed bumps, potholes.
  final double vertical;

  /// `Z_car` — longitudinal: acceleration / braking.
  final double longitudinal;

  /// Euclidean magnitude of the gravity-free reading (m/s²).
  double get magnitude => math.sqrt(
    lateral * lateral + vertical * vertical + longitudinal * longitudinal,
  );

  @override
  String toString() =>
      'VehicleAcceleration(X ${lateral.toStringAsFixed(2)}, '
      'Y ${vertical.toStringAsFixed(2)}, '
      'Z ${longitudinal.toStringAsFixed(2)})';
}

/// A proper rotation from raw device axes into the vehicle frame.
///
/// The three axes are stored as unit vectors **expressed in device
/// coordinates**, which is exactly the conventional row-major rotation matrix
/// ([matrix] flattens them in that order). Being built from an orthonormal
/// triad it is a proper rotation: `X × Y = Z` and [determinant] is `+1`.
///
/// See [VehicleAcceleration] for the sign convention.
class VehicleFrame {
  const VehicleFrame({
    required this.xAxis,
    required this.yAxis,
    required this.zAxis,
  });

  /// `X_car` (lateral, driver's left) as a device-frame unit vector.
  final List<double> xAxis;

  /// `Y_car` (vertical, up) as a device-frame unit vector.
  final List<double> yAxis;

  /// `Z_car` (longitudinal, forward) as a device-frame unit vector.
  final List<double> zAxis;

  /// The 3×3 device→vehicle rotation in row-major order.
  List<double> get matrix => <double>[...xAxis, ...yAxis, ...zAxis];

  /// Determinant of [matrix] — `+1` for a proper rotation, `-1` for a
  /// reflection (which a correct alignment never produces).
  double get determinant {
    final List<double> a = xAxis;
    final List<double> b = yAxis;
    final List<double> c = zAxis;
    return a[0] * (b[1] * c[2] - b[2] * c[1]) -
        a[1] * (b[0] * c[2] - b[2] * c[0]) +
        a[2] * (b[0] * c[1] - b[1] * c[0]);
  }

  /// Rotates one gravity-free device reading into this frame (`vehicle = R·v`).
  VehicleAcceleration transform(double x, double y, double z) =>
      VehicleAcceleration(
        lateral: _project(xAxis, x, y, z),
        vertical: _project(yAxis, x, y, z),
        longitudinal: _project(zAxis, x, y, z),
      );

  static double _project(List<double> axis, double x, double y, double z) =>
      axis[0] * x + axis[1] * y + axis[2] * z;

  @override
  String toString() => 'VehicleFrame(matrix: $matrix)';
}

/// Which raw device axis faces **forward** once the phone is in its cradle.
///
/// Gravity alone cannot recover heading: it fixes the vertical axis but leaves
/// the rotation about it free. The mounting therefore *supplies* the yaw, and
/// [GravityAlignmentCalculator] only has to level (pitch/roll) that nominal
/// forward direction against the measured gravity.
enum DeviceMounting {
  /// Device **+y** (the top of the screen) faces forward — a portrait cradle.
  deviceY,

  /// Device **−y** faces forward — portrait, mounted upside down.
  deviceNegY,

  /// Device **+x** faces forward — landscape, top edge to the left.
  deviceX,

  /// Device **−x** faces forward — landscape, top edge to the right.
  deviceNegX;

  /// The nominal forward direction in raw device coordinates.
  List<double> get forward => switch (this) {
    DeviceMounting.deviceY => const <double>[0, 1, 0],
    DeviceMounting.deviceNegY => const <double>[0, -1, 0],
    DeviceMounting.deviceX => const <double>[1, 0, 0],
    DeviceMounting.deviceNegX => const <double>[-1, 0, 0],
  };
}

/// Aligns raw device axes with the vehicle's own axes, so acceleration can be
/// read as **longitudinal** (accel/brake), **lateral** (cornering) and
/// **vertical** (bumps) instead of as three arbitrary device axes.
///
/// # How it works
///
/// 1. The gravity vector is isolated from the raw samples with a per-axis
///    low-pass filter ([gravityAdaptation]). Filtering the *vector*, not just
///    its magnitude, is what preserves the direction needed here — and the
///    filter only runs while the device is **stationary** ([restSamples],
///    [restResidualThresholdMps2], [restStepThresholdMps2]). Letting it run
///    while the vehicle moves would drag the reference frame toward the
///    maneuver and fade the very signal being measured out of existence.
/// 2. `Y_car` is that gravity direction, normalized: the sensors measure the
///    upward reaction, so a phone lying flat, screen up, reads ≈ `+9.81` on
///    `z` and `(0, 0, +1)` is "up".
/// 3. `Z_car` is the mounting's nominal forward axis ([mounting]) projected
///    onto the plane perpendicular to `Y_car`, then normalized — that removes
///    the device's pitch and roll while keeping the heading the mounting
///    implies.
/// 4. `X_car = Y_car × Z_car` closes the right-handed triad.
///
/// # When it refuses to align
///
/// [frame] stays `null` until the estimate is trustworthy: at least
/// [minSamples] samples must have arrived, the filtered magnitude must sit
/// inside the physical gravity band ([minGravityMagnitude] …
/// [maxGravityMagnitude] — free-fall and heavy vibration are rejected), and the
/// nominal forward axis must have a real horizontal component
/// ([minForwardProjection]). A phone standing on its end has no observable
/// heading, so the calculator reports "not aligned" rather than inventing one;
/// callers fall back to raw-axis evidence.
///
/// Pure Dart, deterministic, no platform channels: unit tests drive
/// [addSample] directly.
class GravityAlignmentCalculator {
  GravityAlignmentCalculator({
    this.gravityAdaptation = 0.1,
    this.mounting = DeviceMounting.deviceY,
    this.restSamples = 20,
    this.restStepThresholdMps2 = 0.15,
    this.restResidualThresholdMps2 = 0.35,
    this.minSamples = 20,
    this.minGravityMagnitude = 7.0,
    this.maxGravityMagnitude = 12.0,
    this.minForwardProjection = 0.25,
  }) : assert(gravityAdaptation > 0 && gravityAdaptation <= 1),
       assert(minSamples > 0),
       assert(minForwardProjection >= 0 && minForwardProjection < 1);

  /// Fast low-pass weight applied to the gravity estimate while the device is
  /// **at rest** (see [restSamples]), so the frame settles within a few tenths
  /// of a second of the trip starting. While moving, gravity is not updated at
  /// all.
  final double gravityAdaptation;

  /// Consecutive still samples required before the estimate is updated
  /// (20 = 0.4 s at 50 Hz).
  final int restSamples;

  /// Largest sample-to-sample change (m/s²) that still counts as "not moving".
  /// A maneuver tends to move the reading quickly, so the *step* separates a
  /// device sitting in its cradle from one being accelerated.
  final double restStepThresholdMps2;

  /// Largest departure from the current gravity estimate (m/s²) that still
  /// reads as "this is gravity, not driving". Well below the smallest maneuver
  /// the classifier cares about, so a maneuver can never re-train the frame.
  final double restResidualThresholdMps2;

  /// Which device axis the cradle points forward (supplies the heading).
  final DeviceMounting mounting;

  /// Samples required before [frame] may be published (20 = 0.4 s at 50 Hz).
  final int minSamples;

  /// Smallest plausible gravity magnitude (m/s²) — below this the device is
  /// falling, not driving.
  final double minGravityMagnitude;

  /// Largest plausible gravity magnitude (m/s²) — above this the estimate is
  /// vibration, not gravity.
  final double maxGravityMagnitude;

  /// Minimum length of the forward axis' projection onto gravity's
  /// perpendicular plane; below it the heading is unobservable.
  final double minForwardProjection;

  final List<double> _gravity = <double>[0, 0, 0];
  final List<double> _previous = <double>[];
  bool _seeded = false;
  int _sampleCount = 0;
  int _quietSamples = 0;
  VehicleFrame? _frame;

  /// Raw samples fed so far.
  int get sampleCount => _sampleCount;

  /// The filtered gravity vector in device axes (m/s²), pointing up. Zero
  /// until the first sample seeds the filter.
  List<double> get gravity => List<double>.unmodifiable(_gravity);

  /// Magnitude of the filtered gravity estimate (m/s²).
  double get gravityMagnitude =>
      math.sqrt(_gravity[0] * _gravity[0] + _gravity[1] * _gravity[1] + _gravity[2] * _gravity[2]);

  /// Whether a trustworthy vehicle frame is currently available.
  bool get isAligned => _frame != null;

  /// The current device→vehicle rotation, or `null` while [isAligned] is
  /// false.
  VehicleFrame? get frame => _frame;

  /// Feeds one raw accelerometer sample (m/s², **gravity included**, device
  /// axes). The first sample seeds the filter so alignment does not start from
  /// a meaningless zero vector.
  ///
  /// Gravity is re-learned only while the device is *staying* still, and is
  /// frozen outright once it moves. That freeze is what keeps the frame honest:
  /// any non-zero per-sample weight accumulates across a 2.56 s window and drags
  /// the reference frame toward the maneuver, so the sensor would end up
  /// measuring the alignment chasing the braking rather than the braking
  /// itself. Stillness is judged against the current estimate
  /// ([restResidualThresholdMps2]) and the sample-to-sample change
  /// ([restStepThresholdMps2]), because a maneuver's *magnitude* alone is
  /// indistinguishable from gravity (a 4 m/s² brake raises `|a|` only from
  /// 9.81 to 10.6).
  void addSample(double x, double y, double z) {
    if (!_seeded) {
      _gravity[0] = x;
      _gravity[1] = y;
      _gravity[2] = z;
      _seeded = true;
    } else {
      final List<double> previous = _previous;
      final double step = previous.isEmpty
          ? 0
          : (x - previous[0]) * (x - previous[0]) +
                (y - previous[1]) * (y - previous[1]) +
                (z - previous[2]) * (z - previous[2]);
      // "At rest" is decided by the reading sitting close to the *current*
      // gravity estimate and barely changing. The magnitude band cannot do this
      // job: a 4 m/s² brake raises |a| only from 9.81 to 10.6, comfortably
      // inside any plausible gravity band, so a magnitude-only gate would let a
      // sustained maneuver drag the reference frame onto itself and fade the
      // braking out of the residual. Comparing against the estimate is what
      // separates "this is gravity, plus a little noise" from "this is gravity
      // plus a maneuver".
      final double residualSquared = (x - _gravity[0]) * (x - _gravity[0]) +
          (y - _gravity[1]) * (y - _gravity[1]) +
          (z - _gravity[2]) * (z - _gravity[2]);
      final bool quiet = residualSquared <=
              restResidualThresholdMps2 * restResidualThresholdMps2 &&
          step <= restStepThresholdMps2 * restStepThresholdMps2;
      _quietSamples = quiet ? _quietSamples + 1 : 0;
      if (_quietSamples >= restSamples) {
        _gravity[0] += (x - _gravity[0]) * gravityAdaptation;
        _gravity[1] += (y - _gravity[1]) * gravityAdaptation;
        _gravity[2] += (z - _gravity[2]) * gravityAdaptation;
      }
    }
    _previous
      ..clear()
      ..addAll(<double>[x, y, z]);
    _sampleCount++;
    _recompute();
  }

  /// Projects one raw sample into the vehicle frame with gravity removed, or
  /// `null` while the frame is not aligned.
  VehicleAcceleration? transform(double x, double y, double z) {
    final VehicleFrame? frame = _frame;
    if (frame == null) return null;
    return frame.transform(
      x - _gravity[0],
      y - _gravity[1],
      z - _gravity[2],
    );
  }

  /// Forgets the gravity estimate, the sample count and the frame — the next
  /// sample re-seeds from scratch. Used when a trip ends or the app resumes,
  /// so a device that was re-mounted mid-drive never keeps a stale frame.
  void reset() {
    _gravity[0] = 0;
    _gravity[1] = 0;
    _gravity[2] = 0;
    _seeded = false;
    _sampleCount = 0;
    _quietSamples = 0;
    _previous.clear();
    _frame = null;
  }

  /// Rebuilds the frame from the current estimate, publishing it only when
  /// every health gate passes.
  void _recompute() {
    final double magnitude = gravityMagnitude;
    if (_sampleCount < minSamples ||
        magnitude < minGravityMagnitude ||
        magnitude > maxGravityMagnitude) {
      _frame = null;
      return;
    }

    // Y_car: up, i.e. the inverse of free-fall direction the sensors report.
    final List<double> up = <double>[
      _gravity[0] / magnitude,
      _gravity[1] / magnitude,
      _gravity[2] / magnitude,
    ];

    // Z_car: the mounting's forward axis with its vertical part removed.
    final List<double> forward = mounting.forward;
    final double along = forward[0] * up[0] + forward[1] * up[1] + forward[2] * up[2];
    final List<double> horizontal = <double>[
      forward[0] - along * up[0],
      forward[1] - along * up[1],
      forward[2] - along * up[2],
    ];
    final double horizontalLength = math.sqrt(
      horizontal[0] * horizontal[0] +
          horizontal[1] * horizontal[1] +
          horizontal[2] * horizontal[2],
    );
    if (horizontalLength < minForwardProjection) {
      // The cradle points along gravity: heading is unobservable, so no frame
      // is published at all.
      _frame = null;
      return;
    }
    final List<double> longitudinal = <double>[
      horizontal[0] / horizontalLength,
      horizontal[1] / horizontalLength,
      horizontal[2] / horizontalLength,
    ];

    // X_car = Y_car × Z_car. Both operands are unit-length and perpendicular,
    // so the cross product is already a unit vector.
    final List<double> lateral = <double>[
      up[1] * longitudinal[2] - up[2] * longitudinal[1],
      up[2] * longitudinal[0] - up[0] * longitudinal[2],
      up[0] * longitudinal[1] - up[1] * longitudinal[0],
    ];

    _frame = VehicleFrame(
      xAxis: lateral,
      yAxis: up,
      zAxis: longitudinal,
    );
  }
}
