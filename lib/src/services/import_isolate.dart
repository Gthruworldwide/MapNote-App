/// Utility functions for import/export operations.
/// These are used by the ImportService for file parsing.
library;

/// Extract string from list at index, return null if out of bounds
String? extractString(List<String>? row, int? idx) {
  if (idx == null || idx >= (row?.length ?? 0)) return null;
  final cell = row?[idx];
  if (cell == null || cell.trim().isEmpty) return null;
  return cell.trim();
}

/// Validate coordinate bounds
String? validateCoordinate(double lat, double lng) {
  if (lat < -90 || lat > 90) {
    return 'Latitude must be between -90 and 90';
  }
  if (lng < -180 || lng > 180) {
    return 'Longitude must be between -180 and 180';
  }
  return null;
}

/// Arabic character normalization
String normalizeArabic(String input) {
  if (input.isEmpty) return input;

  // Normalize Alif variants: أ/إ/ا -> أ
  final normalized = input
      .replaceAll('إ', 'أ')
      .replaceAll('أ', 'أ')
      .replaceAll('آ', 'أ');

  // normalize Ta Marbuta to Ha
  final result = normalized.replaceAll('ة', 'ه');

  return result;
}

/// Parse Google Maps URL to extract coordinates
LatLng? parseMapsUrl(String? url) {
  if (url == null) return null;

  try {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    // Try ?q=lat,lng
    final qParam = uri.queryParameters['q'];
    if (qParam != null) {
      final parts = qParam.split(',');
      if (parts.length >= 2) {
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) {
          final validation = validateCoordinate(lat, lng);
          if (validation == null) {
            return LatLng(lat, lng);
          }
        }
      }
    }

    // Try ?ll=lat,lng
    final llParam = uri.queryParameters['ll'];
    if (llParam != null) {
      final parts = llParam.split(',');
      if (parts.length >= 2) {
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) {
          final validation = validateCoordinate(lat, lng);
          if (validation == null) {
            return LatLng(lat, lng);
          }
        }
      }
    }

    // Try @lat,lng in path
    final pathMatch = RegExp(r'@(-?\d{1,3}(?:\.\d+?)),(-?\d{1,3}(?:\.\d+?)?)')
        .firstMatch(uri.path);
    if (pathMatch != null) {
      final latString = pathMatch.group(1);
      final lngString = pathMatch.group(2);
      if (latString != null && lngString != null) {
        final lat = double.tryParse(latString);
        final lng = double.tryParse(lngString);
        if (lat != null && lng != null) {
          final validation = validateCoordinate(lat, lng);
          if (validation == null) {
            return LatLng(lat, lng);
          }
        }
      }
    }

    return null;
  } catch (_) {
    return null;
  }
}

class LatLng {
  final double latitude;
  final double longitude;

  LatLng(this.latitude, this.longitude);
}

/// Enum for import source file type
enum ImportSource { excel, csv }

/// Column mapping result for auto-detection
class ColumnMapping {
  final int? stationNameIdx;
  final int? latitudeIdx;
  final int? longitudeIdx;
  final int? cityIdx;
  final int? areaIdx;
  final int? categoryIdx;

  ColumnMapping({
    this.stationNameIdx,
    this.latitudeIdx,
    this.longitudeIdx,
    this.cityIdx,
    this.areaIdx,
    this.categoryIdx,
  });

  /// Auto-detect column mapping from headers
  static ColumnMapping autoMap(List<String> headers) {
    // Find station name column
    int? stationNameIdx;
    int? latitudeIdx;
    int? longitudeIdx;
    int? cityIdx;
    int? areaIdx;
    int? categoryIdx;

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].trim().toLowerCase();
      // Station Name variations
      if (stationNameIdx == null &&
          ['اسم المحطة', 'اسم', 'name', 'station name', 'station', 'النقطة']
              .contains(h)) {
        stationNameIdx = i;
      }
      // Latitude variations
      if (latitudeIdx == null &&
          ['خط العرض', 'Latitude', 'Lat', 'y'].contains(h)) {
        latitudeIdx = i;
      }
      // Longitude variations
      if (longitudeIdx == null &&
          ['خط الطول', 'Longitude', 'Lng', 'Lon', 'x'].contains(h)) {
        longitudeIdx = i;
      }
      // City/Area variations
      if (cityIdx == null && ['المدينة', 'City', 'Area'].contains(h)) {
        cityIdx = i;
      }
      // Area variations (if not caught by city)
      if (areaIdx == null && ['المنطقة', 'Area', 'District'].contains(h)) {
        areaIdx = i;
      }
      // Category variations
      if (categoryIdx == null && ['النوع', 'Category', 'Type'].contains(h)) {
        categoryIdx = i;
      }
    }

    return ColumnMapping(
      stationNameIdx: stationNameIdx,
      latitudeIdx: latitudeIdx,
      longitudeIdx: longitudeIdx,
      cityIdx: cityIdx,
      areaIdx: areaIdx,
      categoryIdx: categoryIdx,
    );
  }
}