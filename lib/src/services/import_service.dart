import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../data/models/place.dart';
import '../data/models/station_model.dart';

import 'import_isolate.dart';

/// Strategy for handling duplicate records
enum DuplicateStrategy { skip, overwrite, append }

/// Progress callback type
typedef ImportProgressCallback = void Function(
  int processed,
  int total,
  double percentage,
);

/// Completion callback type
typedef ImportCompletionCallback = void Function(
  ImportResultDetail result,
  List<Place> parsedPlaces,
  List<Station> parsedStations,
);

/// Error callback type
typedef ImportErrorCallback = void Function(String message);

/// Shared UUID generator for import record ids.
const Uuid uuid = Uuid();

/// Result of import operation
class ImportResult {
  final int successCount;
  final int errorCount;
  final int duplicateCount;

  ImportResult(this.successCount, this.errorCount, this.duplicateCount);

  factory ImportResult.fromJson(Map<String, dynamic> json) {
    return ImportResult(
      json['successCount'] ?? 0,
      json['errorCount'] ?? 0,
      json['duplicateCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'successCount': successCount,
        'errorCount': errorCount,
        'duplicateCount': duplicateCount,
      };
}

/// Detailed result of import operation
class ImportResultDetail {
  final int successCount;
  final int errorCount;
  final int duplicateCount;
  final List<Place> parsedPlaces;
  final List<Station> parsedStations;
  final Map<int, String> rowErrors;

  ImportResultDetail({
    required this.successCount,
    required this.errorCount,
    required this.duplicateCount,
    required this.parsedPlaces,
    required this.parsedStations,
    required this.rowErrors,
  });

  Map<String, dynamic> toJson() => {
        'successCount': successCount,
        'errorCount': errorCount,
        'duplicateCount': duplicateCount,
        'parsedPlaces': parsedPlaces.map((p) => p.toMap()).toList(),
        'parsedStations': parsedStations.map((s) => s.toJson()).toList(),
        'rowErrors': rowErrors.map((k, v) => MapEntry(k, '$k: $v')),
      };

  factory ImportResultDetail.fromJson(Map<String, dynamic> json) {
    final rowErrors = <int, String>{};
    final rawErrors = json['rowErrors'] as Map<dynamic, dynamic>? ?? {};
    rawErrors.forEach((k, v) {
      rowErrors[k is int ? k : int.tryParse(k.toString()) ?? 0] =
          v is String ? v : v.toString();
    });

    return ImportResultDetail(
      successCount: json['successCount'] ?? 0,
      errorCount: json['errorCount'] ?? 0,
      duplicateCount: json['duplicateCount'] ?? 0,
      parsedPlaces: (json['parsedPlaces'] as List?)
          ?.map((p) => Place.fromMap(Map<String, dynamic>.from(p ?? {})))
          .toList() ?? [],
      parsedStations: (json['parsedStations'] as List?)
          ?.map((s) => Station.fromJson(Map<String, dynamic>.from(s ?? {})))
          .toList() ?? [],
      rowErrors: rowErrors,
    );
  }
}

/// Main Import Service that handles the complete import workflow
class ImportService {
  /// Hive boxes for persistence
  late Box<Place> _placesBox;
  late Box<Station> _stationsBox;

  /// Current import state
  ImportResultDetail? _currentResult;

  ImportService._internal();
  static final ImportService _instance = ImportService._internal();
  factory ImportService() => _instance;

  /// Initialize service with Hive boxes
  factory ImportService.init(Box<Place> placesBox, Box<Station> stationsBox) {
    _instance._placesBox = placesBox;
    _instance._stationsBox = stationsBox;
    return _instance;
  }

  /// Start import from file path
  Future<ImportResultDetail> importFromFile({
    required String filePath,
    required ImportSource source,
    required DuplicateStrategy strategy,
    ImportProgressCallback? onProgress,
    ImportCompletionCallback? onComplete,
    ImportErrorCallback? onError,
  }) async {
    _currentResult = null;

    // Read file and parse
    final List<List<String>> rows = _readFile(filePath);

    if (rows.isEmpty || rows.length <= 1) {
      onError?.call('Empty import file');
      return ImportResultDetail(
        successCount: 0,
        errorCount: 0,
        duplicateCount: 0,
        parsedPlaces: [],
        parsedStations: [],
        rowErrors: {},
      );
    }

    // Get headers from first row
    final headers = rows.first.map((cell) => cell.toString()).toList();

    // Auto-map columns
    final mapping = ColumnMapping.autoMap(headers);

    // Process each data row
    int successCount = 0;
    int errorCount = 0;
    final List<Place> parsedPlaces = [];
    final List<Station> parsedStations = [];

    const Uuid uuid = Uuid();

    for (int i = 1; i < rows.length; i++) { // Skip header row
      final row = rows[i];

      try {
        // Extract values based on mapping
        final String? stationName =
            _extractString(row, mapping.stationNameIdx);
        final String? latStr = _extractString(row, mapping.latitudeIdx);
        final String? lngStr = _extractString(row, mapping.longitudeIdx);
        final String? city = _extractString(row, mapping.cityIdx);
        final String? area = _extractString(row, mapping.areaIdx);
        final String? category = _extractString(row, mapping.categoryIdx);

        // Skip if essential fields are missing
        if (stationName == null || stationName.isEmpty ||
            latStr == null || latStr.isEmpty ||
            lngStr == null || lngStr.isEmpty) {
          errorCount++;
          continue;
        }

        // Parse coordinates
        final double lat = double.tryParse(latStr.trim()) ?? 0;
        final double lng = double.tryParse(lngStr.trim()) ?? 0;

        // Validate coordinates
        final validationError = validateCoordinate(lat, lng);
        if (validationError != null) {
          errorCount++;
          continue;
        }

        // Normalize Arabic in name and category
        final normalizedName = normalizeArabic(stationName);
        final normalizedCategory = category != null
            ? normalizeArabic(category)
            : 'general';

        // Create place using Place.fromMap
        final place = Place.fromMap(<String, dynamic>{
          'id': uuid.v4(),
          'name': normalizedName,
          'notes': '',
          'latitude': lat,
          'longitude': lng,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'isPinned': false,
          'isHidden': false,
          'isLocked': false,
          'isVaulted': false,
        });

        // Create station using Station.fromJson
        final station = Station.fromJson(<String, dynamic>{
          'id': uuid.v4(),
          'name': normalizedName,
          'category': normalizedCategory,
          'has_drive_thru': false,
          'city': city ?? '',
          'area': area ?? '',
          'latitude': lat,
          'longitude': lng,
          'speed_limit_zone': 0,
        });

        parsedPlaces.add(place);
        parsedStations.add(station);
        successCount++;
      } catch (e) {
        errorCount++;
        // Continue to next row
      }
    }

    // Process results with duplicate handling
    return _processImportResults(
      result: ImportResult(successCount, errorCount, errorCount),
      strategy: strategy,
      parsedPlaces: parsedPlaces,
      parsedStations: parsedStations,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
    );
  }

  /// Process import results with duplicate handling
  ImportResultDetail _processImportResults({
    required ImportResult result,
    required DuplicateStrategy strategy,
    ImportProgressCallback? onProgress,
    ImportCompletionCallback? onComplete,
    ImportErrorCallback? onError,
    required List<Place> parsedPlaces,
    required List<Station> parsedStations,
  }) {
    // Apply duplicate strategy to places
    final List<Place> processedPlaces = _applyDuplicateStrategyPlaces(
      parsedPlaces,
      strategy,
    );

    // Apply duplicate strategy to stations
    final List<Station> processedStations = _applyDuplicateStrategyStations(
      parsedStations,
      strategy,
    );

    // Batch insert into Hive
    final int successCount = _batchInsertPlaces(processedPlaces);
    final int errorCount = result.errorCount;
    final int duplicateCount = _countDuplicates(
      processedPlaces,
      processedStations,
    );

    _currentResult = ImportResultDetail(
      successCount: successCount,
      errorCount: errorCount,
      duplicateCount: duplicateCount,
      parsedPlaces: processedPlaces,
      parsedStations: processedStations,
      rowErrors: {},
    );

    // Notify completion
    onComplete?.call(_currentResult!, processedPlaces, processedStations);

    return _currentResult!;
  }

  /// Read file and return rows as `List<List<String>>`
  List<List<String>> _readFile(String filePath) {
    final List<List<String>> rows = [];

    if (!File(filePath).existsSync()) {
      return rows;
    }

    try {
      final file = File(filePath);
      final String extension = filePath.split('.').last.toLowerCase();

      switch (extension) {
        case 'xlsx':
        case 'xls':
          // Use excel package or fallback to CSV
          // final excel = Excel.decode(await file.readAsBytes());
          // For now, fallback to CSV-like reading
          // fall through to csv
        case 'csv':
          final contents = file.readAsStringSync();
          final lines = contents.split('\n');

          for (final line in lines) {
            // Simple CSV parsing - handle basic cases with quotes
            final cells = <String>[];
            bool inQuotes = false;
            String current = '';

            for (int i = 0; i < line.length; i++) {
              final char = line[i];

              if (char == '"') {
                inQuotes = !inQuotes;
                current += char;
              } else if (char == ',' && !inQuotes) {
                cells.add(current.trim());
                current = '';
              } else {
                current += char;
              }
            }
            cells.add(current.trim());
            if (cells.isNotEmpty || line.isNotEmpty) {
              rows.add(cells);
            }
          }
          break;
        default:
          // Try as CSV fallback
          final contents = file.readAsStringSync();
          final lines = contents.split('\n');

          for (final line in lines) {
            final cells = <String>[];
            bool inQuotes = false;
            String current = '';

            for (int i = 0; i < line.length; i++) {
              final char = line[i];

              if (char == '"') {
                inQuotes = !inQuotes;
                current += char;
              } else if (char == ',' && !inQuotes) {
                cells.add(current.trim());
                current = '';
              } else {
                current += char;
              }
            }
            cells.add(current.trim());
            if (cells.isNotEmpty || line.isNotEmpty) {
              rows.add(cells);
            }
          }
      }
    } catch (e) {
      // Return empty on error
    }

    return rows;
  }

  /// Extract string from row at index, return null if out of bounds
  String? _extractString(List<String>? row, int? idx) {
    if (idx == null || idx >= (row?.length ?? 0)) return null;
    final cell = row?[idx];
    if (cell == null || cell.trim().isEmpty) return null;
    return cell.trim();
  }

  /// Apply duplicate strategy to places
  List<Place> _applyDuplicateStrategyPlaces(
      List<Place> newPlaces, DuplicateStrategy strategy) {
    final List<Place> result = [];

    for (final place in newPlaces) {
      // Check if existing record with same coordinates exists
      final existing = _placesBox.values.where((p) {
        return p.latitude == place.latitude &&
            p.longitude == place.longitude &&
            p.id != place.id;
      }).toList().firstOrNull;

      if (existing != null && existing.id.isNotEmpty) {
        // Existing record found - apply strategy
        switch (strategy) {
          case DuplicateStrategy.skip:
            // Skip - don't add
            continue;
          case DuplicateStrategy.overwrite:
            // Update existing record with new data
            final updated = place.copyWith(id: existing.id);
            _placesBox.put(existing.id, updated);
            result.add(updated);
            break;
          case DuplicateStrategy.append:
            // Generate new UUID and append as new record
            final withNewId = place.copyWith(id: uuid.v4());
            _placesBox.put(withNewId.id, withNewId);
            result.add(withNewId);
            break;
        }
      } else {
        // New record - just add
        _placesBox.put(place.id, place);
        result.add(place);
      }
    }

    return result;
  }

  /// Apply duplicate strategy to stations
  List<Station> _applyDuplicateStrategyStations(
      List<Station> newStations, DuplicateStrategy strategy) {
    final List<Station> result = [];

    for (final station in newStations) {
      // Check if existing record with same coordinates exists
      final existing = _stationsBox.values.where((s) {
        return s.latitude == station.latitude &&
            s.longitude == station.longitude &&
            s.id != station.id;
      }).toList().firstOrNull;

      if (existing != null && existing.id.isNotEmpty) {
        // Existing record found - apply strategy
        switch (strategy) {
          case DuplicateStrategy.skip:
            // Skip - don't add
            continue;
          case DuplicateStrategy.overwrite:
            // Update existing record with new data
            final updated = station.copyWith(id: existing.id);
            _stationsBox.put(updated.id, updated);
            result.add(updated);
            break;
          case DuplicateStrategy.append:
            // Generate new UUID and append as new record
            final withNewId = station.copyWith(id: uuid.v4());
            _stationsBox.put(withNewId.id, withNewId);
            result.add(withNewId);
            break;
        }
      } else {
        // New record - just add
        _stationsBox.put(station.id, station);
        result.add(station);
      }
    }

    return result;
  }

  /// Count duplicates between new and existing records
  int _countDuplicates(
      List<Place> newPlaces, List<Station> newStations) {
    int count = 0;

    // Check places duplicates against existing
    for (final place in newPlaces) {
      final exists = _placesBox.values.any(
        (p) => p.latitude == place.latitude && p.longitude == place.longitude,
      );
      if (exists) count++;
    }

    // Check stations duplicates against existing
    for (final station in newStations) {
      final exists = _stationsBox.values.any(
        (s) => s.latitude == station.latitude && s.longitude == station.longitude,
      );
      if (exists) count++;
    }

    return count;
  }

  /// Batch insert places into Hive in chunks
  int _batchInsertPlaces(List<Place> places) {
    if (places.isEmpty) return 0;

    final batchSize = 100; // Insert 100 at a time
    int successCount = 0;

    for (int i = 0; i < places.length; i += batchSize) {
      final batch = places.sublist(
          i, i + batchSize > places.length ? places.length : i + batchSize);

      // Write batch to Hive
      for (final place in batch) {
        _placesBox.put(place.id, place);
        successCount++;
      }
    }

    return successCount;
  }

  /// Import from assets (Excel, CSV)
  Future<ImportResultDetail> importFromAssets({
    required String assetName,
    required ImportSource source,
    required DuplicateStrategy strategy,
    ImportProgressCallback? onProgress,
    ImportCompletionCallback? onComplete,
    ImportErrorCallback? onError,
  }) async {
    String filePath = '';

    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$assetName');

      // Copy asset to temp file if it doesn't exist
      if (!tempFile.existsSync()) {
        final bytes = await rootBundle.load(assetName);
        await tempFile.writeAsBytes(bytes.buffer.asUint8List());
      }

      filePath = tempFile.path;

      return await importFromFile(
        filePath: filePath,
        source: source,
        strategy: strategy,
        onProgress: onProgress,
        onComplete: onComplete,
        onError: onError,
      );
    } catch (e) {
      onError?.call('Error importing from assets: ${e.toString()}');
      return ImportResultDetail(
        successCount: 0,
        errorCount: 0,
        duplicateCount: 0,
        parsedPlaces: [],
        parsedStations: [],
        rowErrors: {},
      );
    }
  }

  /// Get current import result
  ImportResultDetail? getCurrentResult() => _currentResult;

  /// Reset current result
  void resetResult() {
    _currentResult = null;
  }
}

/// Extension on Place for copyWith with id preservation
extension PlaceX on Place {
  Place copyWith({
    String? id,
    String? name,
    String? notes,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    bool? isPinned,
    bool? isHidden,
    bool? isLocked,
    bool? isVaulted,
  }) {
    return Place(
      id: id ?? this.id,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      isPinned: isPinned ?? this.isPinned,
      isHidden: isHidden ?? this.isHidden,
      isLocked: isLocked ?? this.isLocked,
      isVaulted: isVaulted ?? this.isVaulted,
    );
  }
}

/// Extension on Station for copyWith with id preservation
extension StationX on Station {
  Station copyWith({
    String? id,
    String? name,
    String? category,
    bool? hasDriveThru,
    String? city,
    String? area,
    double? latitude,
    double? longitude,
    int? speedLimitZone,
  }) {
    return Station(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      hasDriveThru: hasDriveThru ?? this.hasDriveThru,
      city: city ?? this.city,
      area: area ?? this.area,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      speedLimitZone: speedLimitZone ?? this.speedLimitZone,
      timestamp: DateTime.now(),
    );
  }
}