/// Battery-aware adaptive GPS sampling interval.
///
/// Adjusts the location update interval based on both device speed and battery level,
/// balancing location accuracy with energy consumption. When battery is low or the
/// device is stationary, sampling intervals are widened; when battery is high and
/// speed is significant, higher-frequency updates are maintained.
///
/// The sampling strategy follows these principles:
/// - **Stationary**: Interval widened to conserve battery (no positional change expected)
/// - **Low battery**: Aggressive interval widening to extend operational time
/// - **High speed**: Maintain or reduce interval to capture meaningful movement
/// - **Medium speed**: Adaptive interval based on battery percentage
final class BatteryAwareSampler {
  /// Minimum sampling interval in milliseconds (maximum sampling frequency).
  /// No sampling faster than this, regardless of battery or speed.
  static const int minIntervalMs = 2000;

  /// Maximum sampling interval in milliseconds (minimum sampling frequency).
  /// No sampling slower than this, to maintain basic tracking.
  static const int maxIntervalMs = 60000;

  /// Battery percentage threshold below which sampling is widened.
  static const double lowBatteryThreshold = 20.0;

  /// Battery percentage threshold above which normal sampling applies.
  static const double highBatteryThreshold = 80.0;

  /// Speed threshold in m/s above which sampling is not widened.
  static const double speedThresholdMps = 5.0;

  /// The current battery level as a percentage (0–100).
  final double batteryLevel;

  /// The current speed in metres per second. `null` if unknown/stationary.
  final double? speedMps;

  /// Creates a [BatteryAwareSampler] with the given battery level and optional speed.
  const BatteryAwareSampler({
    required this.batteryLevel,
    required this.speedMps,
  }) : assert(batteryLevel >= 0 && batteryLevel <= 100,
            'batteryLevel must be in range [0, 100]');

  /// Returns the recommended sampling interval in milliseconds based on battery
  /// level and current speed.
  ///
  /// The interval is computed as follows:
  /// 1. Start with a base interval linearly interpolated between [minIntervalMs]
  ///    and [maxIntervalMs] based on battery level.
  /// 2. If [speedMps] is provided and exceeds [speedThresholdMps], narrow the
  ///    interval toward [minIntervalMs].
  /// 3. Clamp the result to [minIntervalMs, maxIntervalMs].
  int recommendedIntervalMs() {
    // Base interval from battery level (linear interpolation)
    double batteryFactor;
    if (batteryLevel <= lowBatteryThreshold) {
      batteryFactor = 1.0; // Use max interval when very low
    } else if (batteryLevel >= highBatteryThreshold) {
      batteryFactor = 0.0; // Use min interval when high
    } else {
      // Linear interpolation between 1.0 and 0.0
      batteryFactor = (highBatteryThreshold - batteryLevel) /
          (highBatteryThreshold - lowBatteryThreshold);
    }

    // Base interval: closer to max when battery is low
    double baseInterval =
        minIntervalMs + (maxIntervalMs - minIntervalMs) * batteryFactor;

    // Speed adjustment: if moving quickly, narrow the interval
    double? effectiveSpeed = speedMps;
    if (effectiveSpeed != null && effectiveSpeed > speedThresholdMps) {
      // Interpolate toward minIntervalMs based on how fast we're going
      // (speed above 5 m/s = 18 km/h)
      final double speedFactor = (effectiveSpeed - speedThresholdMps) /
          (10.0 - speedThresholdMps)
              .clamp(0.0, 1.0); // 10 m/s = 36 km/h reference
      baseInterval = baseInterval *
          (1.0 - speedFactor * 0.5); // At most 50% narrowing at 10 m/s
    }

    // Clamp to valid range
    return baseInterval.clamp(minIntervalMs, maxIntervalMs).round();
  }
}
