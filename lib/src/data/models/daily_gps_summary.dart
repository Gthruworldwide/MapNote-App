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

  DailyGpsSummary copyWith({
    DateTime? date,
    double? totalKm,
    double? maxSpeedKmh,
    double? lastLatitude,
    double? lastLongitude,
    DateTime? lastFixAt,
  }) {
    return DailyGpsSummary(
      date: date ?? this.date,
      totalKm: totalKm ?? this.totalKm,
      maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
      lastLatitude: lastLatitude ?? this.lastLatitude,
      lastLongitude: lastLongitude ?? this.lastLongitude,
      lastFixAt: lastFixAt ?? this.lastFixAt,
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
    return <String, dynamic>{
      'date': dayKey(date),
      'total_km': totalKm,
      'max_speed': maxSpeedKmh,
      'last_lat': lastLatitude,
      'last_lon': lastLongitude,
      'last_fix_at': lastFixAt?.toIso8601String(),
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
    );
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
      other.lastFixAt == lastFixAt;

  @override
  int get hashCode => Object.hash(
        date,
        totalKm,
        maxSpeedKmh,
        lastLatitude,
        lastLongitude,
        lastFixAt,
      );

  @override
  String toString() =>
      'DailyGpsSummary(${dayKey(date)}, ${totalKm.toStringAsFixed(2)} km, '
      '${maxSpeedKmh.toStringAsFixed(1)} km/h)';
}