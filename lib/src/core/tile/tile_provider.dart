import 'dart:typed_data';

/// Abstract base class for map tile providers.
///
/// All tile providers for [FlutterMap] should extend this class so that
/// the map UI can depend on the abstraction rather than a concrete implementation.
/// This enables swapping tile sources (e.g. OpenStreetMap, CartoDB, offline caches)
/// without rewriting map widget trees.
abstract class MapTileProvider {
  /// Fetch the tile image data for the given [x], [y] and [z] (zoom level).
  ///
  /// Implementations should complete the returned future with the raw tile bytes,
  /// or error if the tile cannot be fetched.
  Future<Uint8List> getTile(int x, int y, int z);

  /// Optional: indicate whether this provider requires network access.
  ///
  /// Defaults to `true`. Providers that can operate offline (e.g. from a cached
  /// map tile store) may override this to return `false`.
  ///
  /// When `false`, the [TileLayer] may render a placeholder or empty tiles
  /// rather than showing network errors.
  bool get requiresNetwork => true;
}