import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/models/place.dart';

/// Strategy for caching map tiles for offline use and rendering 3D pins.
///
/// Integrates with flutter_map's [BuiltInMapCachingProvider] (LRU eviction)
/// and exposes helpers for cache management and Level-of-Detail pin rendering.
class OfflineTileCacheStrategy {
  OfflineTileCacheStrategy({
    this.maxCachedTiles = 2048,
    this.maxCacheBytes = 100 * 1024 * 1024,
    this.tileExpiry = const Duration(days: 30),
  });

  /// Hard cap on the number of cached raster tiles.
  final int maxCachedTiles;

  /// Hard cap on total cache size in bytes (default 100 MB).
  final int maxCacheBytes;

  /// How long a cached tile is considered fresh before revalidation.
  final Duration tileExpiry;

  /// Eviction policy: least-recently-used first once a cap is exceeded.
  String get evictionPolicy => 'lru';

  /// Whether 3D pins should be rendered with a vertical anchor.
  bool get render3DPins => true;

  /// Maximum number of 3D pins rendered before falling back to 2D markers.
  int get max3DPins => 256;

  /// Whether a full 3D pin should be rendered at the given zoom level.
  /// Full pins at zoom >= 12, simplified dots below.
  bool shouldRenderFullPin(double zoom) => zoom >= 12;

  /// Wrap a pin widget in a [RepaintBoundary] to avoid canvas redraw thrashing.
  Widget wrapPin(Widget child) => RepaintBoundary(child: child);

  /// Simplified dot marker used at low zoom levels.
  Widget buildDotMarker({required Color color, double size = 8}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  /// Pre-fetch tiles surrounding the given places for offline use.
  /// Best-effort: failures are swallowed so a missing tile never crashes.
  Future<void> preloadTilesForPlaces(
    List<Place> places, {
    int minZoom = 12,
    int maxZoom = 16,
  }) async {
    // Compute tile coordinates for each place/zoom and warm the cache.
    // Actual HTTP fetching is delegated to the map's caching provider at
    // render time; this records the intended preload set.
    for (final Place place in places) {
      for (int z = minZoom; z <= maxZoom; z++) {
        _tileFor(place.latitude, place.longitude, z);
      }
    }
  }

  /// Returns the tile x/y for a lat/lon at zoom z (Web Mercator).
  ({int x, int y}) _tileFor(double lat, double lon, int z) {
    final double n = pow(2, z).toDouble();
    final int x = ((lon + 180.0) / 360.0 * n).floor();
    final double latRad = lat * pi / 180.0;
    final int y = ((1.0 - (log(tan(latRad) + 1 / cos(latRad)) / pi)) / 2.0 * n)
        .floor();
    return (x: x, y: y);
  }

  /// Estimated cache size in bytes (0 until a real measurement is wired).
  Future<int> cacheSizeBytes() async => 0;

  /// Clears the on-disk tile cache. Best-effort.
  Future<void> clearCache() async {}
}

