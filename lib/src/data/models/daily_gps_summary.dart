import '../../services/polyline_smoother.dart';

/// Aggregated GPS metrics for a single calendar day.
///
/// Stored in Hive as a JSON-compatible map via [toMap]/[fromMap] (the same
/// convention as [Place], so no TypeAdapter is needed).
class DailyGpsSummary {
  const DailyGpsSummary({
    required this.date,
    this.totalKm = 0,
    this.maxSpeedKmh = 0,
    this.lastLatitude,
    this.lastLongitude,
    this.lastFixAt,
    this.path,
    this.walkKm = 0,
    this.runKm = 0,
    this.vehicleKm = 0,
    this.walkDurationSeconds = 0,
    this.runDurationSeconds = 0,
    this.vehicleDurationSeconds = 0,
  });

  /// The calendar day this summary belongs to, at local midnight.
  final DateTime date;

  /// Total distance travelled that day, in kilometres.
  final double totalKm;

  /// Highest measured speed that day, in km/h.
  final double maxSpeedKmh;

  /// Last accepted fix of the day (null when nothing was recorded). Persisting
  /// it lets a restarted service resume an in-progress trip instead of treating
  /// the next fix as a brand new trip.
  final double? lastLatitude;
  final double? lastLongitude;
  final DateTime? lastFixAt;

  /// The day's recorded route, already jitter-smoothed by `PolylineSmoother`
  /// on the way to disk, or `null` when nothing was recorded.
  ///
  /// An additive key: summaries written before this field existed simply
  /// parse back as `null`. The list may carry thousands of vertices, so it is
  /// deliberately excluded from [==]/[hashCode] — value identity here is the
  /// day's metrics, and deep-comparing whole routes on every equality check
  /// would be a trap.
  final List<RoutePoint>? path;

  /// Distance travelled on foot during the day, in kilometres.
  final double walkKm;

  /// Distance travelled running during the day, in kilometres.
  final double runKm;

  /// Distance travelled by vehicle during the day, in kilometres.
  final double vehicleKm;

  /// Time spent walking during the day, in seconds.
  final int walkDurationSeconds;

  /// Time spent running during the day, in seconds.
  final int runDurationSeconds;

  /// Time spent in a vehicle during the day, in seconds.
  final int vehicleDurationSeconds;

  /// Total distance across all modes, in kilometres.
  double get totalModeKm => walkKm + runKm + vehicleKm;

  /// Total time across all modes, in seconds.
  int get totalModeDurationSeconds =>
      walkDurationSeconds + runDurationSeconds + vehicleDurationSeconds;

  DailyGpsSummary copyWith({
    DateTime? date,
    double? totalKm,
    double? maxSpeedKmh,
    double? lastLatitude,
    double? lastLongitude,
    DateTime? lastFixAt,
    List<RoutePoint>? path,
    double? walkKm,
    double? runKm,
    double? vehicleKm,
    int? walkDurationSeconds,
    int? runDurationSeconds,
    int? vehicleDurationSeconds,
  }) {
    return DailyGpsSummary(
      date: date ?? this.date,
      totalKm: totalKm ?? this.totalKm,
      maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
      lastLatitude: lastLatitude ?? this.lastLatitude,
      lastLongitude: lastLongitude ?? this.lastLongitude,
      lastFixAt: lastFixAt ?? this.lastFixAt,
      path: path ?? this.path,
      walkKm: walkKm ?? this.walkKm,
      runKm: runKm ?? this.runKm,
      vehicleKm: vehicleKm ?? this.vehicleKm,
      walkDurationSeconds: walkDurationSeconds ?? this.walkDurationSeconds,
      runDurationSeconds: runDurationSeconds ?? this.runDurationSeconds,
      vehicleDurationSeconds:
          vehicleDurationSeconds ?? this.vehicleDurationSeconds,
    );
  }

  /// Stable key for a calendar day: `yyyy-MM-dd`.
  static String dayKey(DateTime day) {
    final String y = day.year.toString().padLeft(4, '0');
    final String m = day.month.toString().padLeft(2, '0');
    final String d = day.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// The local calendar day containing [time], normalised to midnight.
  static DateTime dayOf(DateTime time) =>
      DateTime(time.year, time.month, time.day);

  Map<String, dynamic> toMap() {
    // Local alias: instance fields never promote, and `path` is checked once
    // for both the null guard and the comprehension below.
    final List<RoutePoint>? route = path;
    return <String, dynamic>{
      'date': dayKey(date),
      'total_km': totalKm,
      'max_speed': maxSpeedKmh,
      'last_lat': lastLatitude,
      'last_lon': lastLongitude,
      'last_fix_at': lastFixAt?.toIso8601String(),
      // Stored as [lat, lon, epoch-ms] triples, rounded to 5 decimals
      // (~1.1 m): far finer than the smoothed path's accuracy and roughly
      // half the JSON size of full doubles. `null` (never an empty list)
      // keeps pre-path records byte-identical.
      'path': route == null
          ? null
          : <List<Object?>>[
              for (final RoutePoint point in route)
                <Object?>[
                  _round5(point.latitude),
                  _round5(point.longitude),
                  point.at?.millisecondsSinceEpoch,
                ],
            ],
      'walk_km': walkKm,
      'run_km': runKm,
      'vehicle_km': vehicleKm,
      'walk_duration_s': walkDurationSeconds,
      'run_duration_s': runDurationSeconds,
      'vehicle_duration_s': vehicleDurationSeconds,
    };
  }

  factory DailyGpsSummary.fromMap(Map<String, dynamic> map) {
    final DateTime date = _parseDay(map['date']) ??
        dayOf(DateTime.now());
    return DailyGpsSummary(
      date: date,
      totalKm: (map['total_km'] as num?)?.toDouble() ?? 0,
      maxSpeedKmh: (map['max_speed'] as num?)?.toDouble() ?? 0,
      lastLatitude: (map['last_lat'] as num?)?.toDouble(),
      lastLongitude: (map['last_lon'] as num?)?.toDouble(),
      lastFixAt: _parseInstant(map['last_fix_at']),
      path: _parsePath(map['path']),
      walkKm: (map['walk_km'] as num?)?.toDouble() ?? 0,
      runKm: (map['run_km'] as num?)?.toDouble() ?? 0,
      vehicleKm: (map['vehicle_km'] as num?)?.toDouble() ?? 0,
      walkDurationSeconds: (map['walk_duration_s'] as num?)?.toInt() ?? 0,
      runDurationSeconds: (map['run_duration_s'] as num?)?.toInt() ?? 0,
      vehicleDurationSeconds: (map['vehicle_duration_s'] as num?)?.toInt() ?? 0,
    );
  }

  /// Rounds to 5 decimal places (~1.1 m at the equator).
  static double _round5(double value) => (value * 1e5).roundToDouble() / 1e5;

  /// Tolerant path parser: a missing key, a wrong container type or a single
  /// malformed vertex degrades gracefully (null / fewer points) instead of
  /// failing the whole day's restore.
  static List<RoutePoint>? _parsePath(Object? value) {
    if (value is! List) return null;
    final List<RoutePoint> points = <RoutePoint>[];
    for (final Object? entry in value) {
      if (entry is! List || entry.length < 2) continue;
      final Object? lat = entry[0];
      final Object? lon = entry[1];
      if (lat is! num || lon is! num) continue;
      points.add(
        RoutePoint(
          latitude: lat.toDouble(),
          longitude: lon.toDouble(),
          at: entry.length > 2 && entry[2] is num
              ? DateTime.fromMillisecondsSinceEpoch(
                  (entry[2]! as num).toInt(),
                )
              : null,
        ),
      );
    }
    return points;
  }

  static DateTime? _parseInstant(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  static DateTime? _parseDay(Object? value) {
    if (value is DateTime) return dayOf(value);
    if (value is String) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return dayOf(parsed);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is DailyGpsSummary &&
      other.date == date &&
      other.totalKm == totalKm &&
      other.maxSpeedKmh == maxSpeedKmh &&
      other.lastLatitude == lastLatitude &&
      other.lastLongitude == lastLongitude &&
      other.lastFixAt == lastFixAt &&
      other.walkKm == walkKm &&
      other.runKm == runKm &&
      other.vehicleKm == vehicleKm &&
      other.walkDurationSeconds == walkDurationSeconds &&
      other.runDurationSeconds == runDurationSeconds &&
      other.vehicleDurationSeconds == vehicleDurationSeconds;

  @override
  int get hashCode => Object.hash(
        date,
        totalKm,
        maxSpeedKmh,
        lastLatitude,
        lastLongitude,
        lastFixAt,
        walkKm,
        runKm,
        vehicleKm,
        walkDurationSeconds,
        runDurationSeconds,
        vehicleDurationSeconds,
      );

  @override
  String toString() =>
      'DailyGpsSummary(${dayKey(date)}, ${totalKm.toStringAsFixed(2)} km, '
      '${maxSpeedKmh.toStringAsFixed(1)} km/h)';
}