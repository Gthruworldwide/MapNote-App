import 'dart:convert';

import 'package:geolocator/geolocator.dart';

import '../data/models/station_model.dart';
import '../data/remote/auth_service.dart';
import '../data/remote/drive_service.dart';

import '../data/local/hive_database.dart';

/// StationService no longer loads a hardcoded `assets/data/stations.json`.
/// Stations are fetched from the authenticated user's private Google Drive
/// AppData folder, or falling back to locally stored Hive data.
class StationService {
  /// Create a [StationService] with the required dependencies.
  StationService({
    required this.driveService,
    required this.authService,
    required this.hiveDatabase,
  });

  final DriveService driveService;
  final AuthService authService;
  final HiveDatabase hiveDatabase;

  List<Station> _stations = [];
  bool _loaded = false;

  /// All stations for the current user, loaded from Drive or local Hive.
  List<Station> get allStations => List.unmodifiable(_stations);

  /// Filter stations by city and/or category.
  List<Station> filterStations({String? city, String? category}) {
    return _stations.where((station) {
      final cityMatch =
          city == null || city.isEmpty || city == 'all' || station.city == city;
      final categoryMatch =
          category == null || category.isEmpty || station.category == category;
      return cityMatch && categoryMatch;
    }).toList();
  }

  /// Get nearby stations within max distance (km), sorted by distance.
  List<Map<String, dynamic>> getNearbyStations(
    Position userPosition,
    double maxDistanceKm,
  ) {
    final nearby = <Map<String, dynamic>>[];

    for (var station in _stations) {
      final distanceInMeters = Geolocator.distanceBetween(
        userPosition.latitude,
        userPosition.longitude,
        station.latitude,
        station.longitude,
      );

      final distanceKm = distanceInMeters / 1000;
      if (distanceKm <= maxDistanceKm) {
        nearby.add({
          'station': station,
          'distance_km': distanceKm,
        });
      }
    }

    // Sort from closest to farthest
    nearby.sort((a, b) {
      final distanceA = a['distance_km'] as double;
      final distanceB = b['distance_km'] as double;
      return distanceA.compareTo(distanceB);
    });

    return nearby;
  }

  /// Get total station count
  int get stationCount => _stations.length;

  /// Returns the [limit] nearest active stations to [currentStationId].
  /// If [directionBound] is provided, only stations matching that direction
  /// corridor are considered.
  List<Station> findNearestAlternatives({
    required String currentStationId,
    String? directionBound,
    int limit = 3,
  }) {
    // 1️⃣  Find the reference station's coordinates.
    Station? refStation;
    for (var s in _stations) {
      if (s.id == currentStationId) {
        refStation = s;
        break;
      }
    }
    if (refStation == null) return [];

    // 2️⃣  Filter candidates: operational, not the reference itself.
    final candidates = _stations.where(
      (station) =>
          station.isOperational &&
          station.id != currentStationId &&
          (directionBound == null ||
              station.directionBound == directionBound),
    ).toList();

    // 3️⃣  Calculate distances from the reference station.
    final List<Station> withDistance = [];
    for (var station in candidates) {
      // We can't easily add a field, so we'll just keep distance info
      // by creating a wrapper or using the existing station with distance
      // stored separately. For simplicity, we'll just return the stations
      // sorted by computed distance.
      withDistance.add(station);
    }

    // 4️⃣  Sort ascending by distance using a temporary list with distances.
    // Since Station is immutable, we compute distances on the fly during sort.
    final StationDistances sorted = StationDistances(
      stations: List.from(withDistance),
      referenceLat: refStation.latitude,
      referenceLng: refStation.longitude,
    );
    sorted.sortByDistance();

    // 5️⃣  Return the top [limit] stations.
    return sorted.stations.take(limit).toList();
  }

  /// Initialize the service: attempt to load stations from Drive (if user
  /// is signed in), falling back to local Hive storage.
  ///
  /// Must be called on user gesture (e.g. app start with a persisted session).
  Future<void> initialize() async {
    if (_loaded) return;
    _loaded = true;

    // Try Drive first if user is authenticated
    if (authService.isSignedIn && authService.currentUser != null) {
      final jsonContent = await driveService.downloadBackup();
      if (jsonContent != null) {
        final List<dynamic> data = json.decode(jsonContent);
        _stations = data.map((json) => Station.fromJson(json)).toList();
        await _saveStationsToHive(_stations);
        return;
      }
    }

    // Fall back to local Hive
    _stations = await _loadStationsFromHive();
  }

  /// Save [stations] to the local Hive box named [app_config.stationBoxName].
  Future<void> _saveStationsToHive(List<Station> stations) async {
    final box = hiveDatabase.stationBox;
    await box.clear();

    for (final station in stations) {
      final jsonString = json.encode(station.toMap());
      await box.put(station.timestamp.toIso8601String(), jsonString);
    }
  }

  /// Load stations from the local Hive box.
  Future<List<Station>> _loadStationsFromHive() async {
    final box = hiveDatabase.stationBox;
    if (box.isEmpty) return [];

    final List<Station> stations = <Station>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is String) {
        try {
          final map = json.decode(raw) as Map<String, dynamic>;
          stations.add(Station.fromJson(map));
        } catch (_) {
          // skip malformed entries
        }
      }
    }
    // Sort by timestamp descending (newest first)
    stations.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return stations;
  }
}

/// Helper class to sort [Station]s by distance from a reference point.
class StationDistances {
  final List<Station> stations;
  final double referenceLat;
  final double referenceLng;

  StationDistances({
    required this.stations,
    required this.referenceLat,
    required this.referenceLng,
  });

  void sortByDistance() {
    stations.sort((a, b) {
      final da = Geolocator.distanceBetween(
        referenceLat,
        referenceLng,
        a.latitude,
        a.longitude,
      );
      final db = Geolocator.distanceBetween(
        referenceLat,
        referenceLng,
        b.latitude,
        b.longitude,
      );
      return da.compareTo(db);
    });
  }
}