/// Aggregated GPS metrics for a single calendar day.
///
/// Stored in Hive as a JSON-compatible map via [toMap]/[fromMap] (the same
/// convention as [Place], so no TypeAdapter is needed).
class DailyGpsSummary {
  const DailyGpsSummary({
    required this.date,
    this.totalKm = 0,
    this.maxSpeedKmh = 0,
  });

  /// The calendar day this summary belongs to, at local midnight.
  final DateTime date;

  /// Total distance travelled that day, in kilometres.
  final double totalKm;

  /// Highest measured speed that day, in km/h.
  final double maxSpeedKmh;

  DailyGpsSummary copyWith({
    DateTime? date,
    double? totalKm,
    double? maxSpeedKmh,
  }) {
    return DailyGpsSummary(
      date: date ?? this.date,
      totalKm: totalKm ?? this.totalKm,
      maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
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
    };
  }

  factory DailyGpsSummary.fromMap(Map<String, dynamic> map) {
    final DateTime date = _parseDay(map['date']) ??
        dayOf(DateTime.now());
    return DailyGpsSummary(
      date: date,
      totalKm: (map['total_km'] as num?)?.toDouble() ?? 0,
      maxSpeedKmh: (map['max_speed'] as num?)?.toDouble() ?? 0,
    );
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
      other.maxSpeedKmh == maxSpeedKmh;

  @override
  int get hashCode => Object.hash(date, totalKm, maxSpeedKmh);

  @override
  String toString() =>
      'DailyGpsSummary(${dayKey(date)}, ${totalKm.toStringAsFixed(2)} km, '
      '${maxSpeedKmh.toStringAsFixed(1)} km/h)';
}