// Shared fakes for the map-preview widget tests — the AutoMotion route card
// and the saved-place route preview (tile map, offline fallback, milestone
// timeline). Nothing here touches the network or platform channels — widget
// tests must be deterministic and offline, exactly like the app's own
// fallback path.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';

import 'package:routenote/src/data/local/auto_motion_data_source.dart';
import 'package:routenote/src/data/models/daily_gps_summary.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/auto_motion_service.dart';
import 'package:routenote/src/services/location_service.dart';

/// Builds a [Position] with the required fields for geolocator 14.
Position fix(double lat, double lon, {double speed = 0, DateTime? at}) {
  return Position(
    latitude: lat,
    longitude: lon,
    timestamp: at ?? DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
    hasAccuracy: true,
    hasSpeed: true,
  );
}

/// In-memory store: a real Hive write can never complete inside a widget
/// test's FakeAsync zone, so persistence is a no-op here.
class SilentStore extends AutoMotionDataSource {
  SilentStore(super.box);

  @override
  Future<void> save(DailyGpsSummary summary) async {}
}

/// AutoMotion tracker that reports "started" without touching platform
/// channels, so tests control the fixes through [AutoMotionService
/// .recordPosition].
class ScriptedMotion extends AutoMotionService {
  ScriptedMotion(AutoMotionDataSource store) : super(dailyStore: store);

  @override
  Future<bool> start({
    LocationService? locations,
    Stream<Position>? positions,
  }) async => true;
}

/// A 1x1 fully transparent PNG, used as the "tile" served by the network-free
/// providers below: the tile layer renders, but no imagery ever lands.
final Uint8List transparentPngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR length + type
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1 px
  0x08, 0x06, 0x00, 0x00, 0x00, // 8-bit RGBA, no interlace
  0x1F, 0x15, 0xC4, 0x89, // IHDR CRC
  0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT length + type
  0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, // zlib stream
  0x0D, 0x0A, 0x2D, 0xB4, // IDAT CRC
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND length + type
  0xAE, 0x42, 0x60, 0x82, // IEND CRC
]);

/// Serves the transparent [transparentPngBytes] for every tile: the map
/// "loads" cleanly with zero imagery, which is what a widget test should see
/// (no HTTP, no errors, and the offline grid stays visible underneath).
class NoImageryTiles extends TileProvider {
  static final MemoryImage _blank = MemoryImage(transparentPngBytes);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _blank;
}

/// Models airplane mode: every tile image future stays pending forever, so
/// not a single tile ever arrives — the pure offline condition. No error is
/// raised (flutter_map treats pending tiles as "not here yet"), keeping the
/// test exception-free.
class NeverLoadingTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      const _NeverLoadedTile();
}

/// An [ImageProvider] that never completes. `loadImage` is the supported
/// override point in the pinned Flutter version; the future handed to
/// [OneFrameImageStreamCompleter] simply never fires.
class _NeverLoadedTile extends ImageProvider<_NeverLoadedTile> {
  const _NeverLoadedTile();

  @override
  Future<_NeverLoadedTile> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_NeverLoadedTile>(this);

  @override
  ImageStreamCompleter loadImage(
    _NeverLoadedTile key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
}

/// Keeps milestone names unresolved in widget tests: the real resolver would
/// hit the platform geocoder and schedule retry timers inside FakeAsync.
class QuietNames extends RouteMilestoneNames {
  @override
  Map<String, String?> build() => const <String, String?>{};
}
