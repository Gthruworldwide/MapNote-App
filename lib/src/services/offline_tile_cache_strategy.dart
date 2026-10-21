/// Strategy for caching map tiles for offline use and rendering 3D pins.
///
/// **Foundation (Phase 3 follow-up).** This is a planning/strategy surface:
/// it defines the cache policy and pin-rendering hints without touching the
/// live map widget, so the existing flutter_map integration stays intact.
/// No network calls are made here and no coordinates are persisted beyond
/// what the user explicitly saves (`AGENT_SKILLS.md` §1.1, §4).
class OfflineTileCacheStrategy {
  const OfflineTileCacheStrategy({
    this.maxCachedTiles = 2048,
    this.maxCacheBytes = 64 * 1024 * 1024,
    this.tileExpiry = const Duration(days: 30),
  });

  /// Hard cap on the number of cached raster tiles.
  final int maxCachedTiles;

  /// Hard cap on total cache size in bytes.
  final int maxCacheBytes;

  /// How long a cached tile is considered fresh before revalidation.
  final Duration tileExpiry;

  /// Eviction policy: least-recently-used first once a cap is exceeded.
  String get evictionPolicy => 'lru';

  /// Whether 3D pins should be rendered with a vertical anchor (shadow +
  /// height) instead of flat 2D markers.
  bool get render3DPins => true;

  /// Maximum number of 3D pins rendered before falling back to 2D markers
  /// to protect frame pacing.
  int get max3DPins => 256;
}
