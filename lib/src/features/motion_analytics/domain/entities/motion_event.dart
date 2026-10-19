/// What the on-device motion classifier decided about one window of driving.
///
/// The names mirror the class labels a trained model would emit (see
/// [modelLabel]), so the same taxonomy covers the deterministic classifier
/// shipped today and a TFLite model dropped in later.
enum MotionEventKind {
  /// Sustained longitudinal deceleration (`Z_car` strongly negative).
  hardBrake,

  /// Sustained longitudinal acceleration (`Z_car` strongly positive).
  hardAccel,

  /// Sustained lateral force (`X_car` beyond threshold) — cornering.
  sharpTurn,

  /// A short upward vertical impulse (`Y_car` positive spike) — a bump's lip.
  speedBump,

  /// A short downward vertical impulse (`Y_car` negative spike).
  pothole,

  /// Nothing above the calm thresholds: the window is a smooth stretch, not a
  /// maneuver.
  smoothDrive;

  /// The class name this kind is expected to carry in a trained model's label
  /// set (`labels[{index}] == modelLabel`), matching the published taxonomy
  /// `[Hard_Brake, Hard_Accel, Sharp_Turn, Speed_Bump, Pothole, Smooth_Drive]`.
  String get modelLabel => switch (this) {
    MotionEventKind.hardBrake => 'Hard_Brake',
    MotionEventKind.hardAccel => 'Hard_Accel',
    MotionEventKind.sharpTurn => 'Sharp_Turn',
    MotionEventKind.speedBump => 'Speed_Bump',
    MotionEventKind.pothole => 'Pothole',
    MotionEventKind.smoothDrive => 'Smooth_Drive',
  };

  /// The class this kind maps to when a model's label order is unknown.
  static MotionEventKind? fromModelLabel(String label) {
    for (final MotionEventKind kind in MotionEventKind.values) {
      if (kind.modelLabel == label) return kind;
    }
    return null;
  }
}

/// One maneuver classified from the vehicle-frame window.
///
/// Carries no location, identity or user content — a kind, a signed magnitude
/// and a timestamp — so it can never leak where or who drove.
class MotionEvent {
  const MotionEvent({
    required this.kind,
    required this.confidence,
    required this.peakMps2,
    required this.startedAt,
  });

  /// Which maneuver this is.
  final MotionEventKind kind;

  /// Model confidence in `[0, 1]` — how far past the decision boundary the
  /// evidence sat, never a probability of anything about the driver.
  final double confidence;

  /// Signed peak on the deciding vehicle axis (m/s²): negative for
  /// [MotionEventKind.hardBrake] / [MotionEventKind.pothole], positive for
  /// [MotionEventKind.hardAccel] / [MotionEventKind.speedBump]. Meaningless
  /// (zero) for [MotionEventKind.smoothDrive].
  final double peakMps2;

  /// When the window that produced this classification ended.
  final DateTime startedAt;

  @override
  bool operator ==(Object other) =>
      other is MotionEvent &&
      other.kind == kind &&
      other.confidence == confidence &&
      other.peakMps2 == peakMps2 &&
      other.startedAt == startedAt;

  @override
  int get hashCode => Object.hash(kind, confidence, peakMps2, startedAt);

  @override
  String toString() =>
      'MotionEvent(${kind.modelLabel}, ${confidence.toStringAsFixed(2)}, '
      '${peakMps2.toStringAsFixed(1)} m/s² @ $startedAt)';
}
