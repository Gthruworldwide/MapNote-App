class Station {
  final String id;
  final String name;
  final String category;
  final bool hasDriveThru;
  final String city;
  final String area;
  final double latitude;
  final double longitude;
  final int speedLimitZone;
  final DateTime timestamp;
  /// Direction this station serves (e.g., 'القاهرة', 'الإسكندرية', 'السويس').
  final String? directionBound;
  /// Whether this station is currently operational/active.
  final bool isOperational;

  Station({
    required this.id,
    required this.name,
    required this.category,
    required this.hasDriveThru,
    required this.city,
    required this.area,
    required this.latitude,
    required this.longitude,
    required this.speedLimitZone,
    required this.timestamp,
    this.directionBound,
    this.isOperational = true,
  });

  factory Station.fromJson(Map<String, dynamic> json) {
    return Station(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Station',
      category: json['category'] ?? 'general',
      hasDriveThru: json['has_drive_thru'] ?? false,
      city: json['city'] ?? '',
      area: json['area'] ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      speedLimitZone: json['speed_limit_zone'] ?? 0,
      timestamp: _parseTimestamp(json['timestamp']),
      directionBound: json['direction_bound'] ?? '',
      isOperational: json['is_operational'] ?? true,
    );
  }

  static DateTime _parseTimestamp(Object? value) {
    if (value is int) return DateTime.fromMicrosecondsSinceEpoch(value * 1000);
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    if (value is DateTime) return value;
    return DateTime.now();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'has_drive_thru': hasDriveThru,
        'city': city,
        'area': area,
        'latitude': latitude,
        'longitude': longitude,
        'speed_limit_zone': speedLimitZone,
        'timestamp': timestamp.microsecondsSinceEpoch,
        'direction_bound': directionBound,
        'is_operational': isOperational,
      };

  /// Convert station to map (alias for toJson)
  Map<String, dynamic> toMap() => toJson();
}