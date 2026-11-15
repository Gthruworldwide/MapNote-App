import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_ce/hive.dart';

import '../core/config/app_config.dart';
import '../data/models/place.dart';

/// First-launch seed engine for the bundled station catalogue.
///
/// `assets/data/stations.json` is the shipped copy of the audited station sheet
/// (active stations with their coordinates and — where the name match was
/// certain — their manager). On cold start it is merged into the **places**
/// box, so a support rep can open a station and see who runs it without any
/// external file.
///
/// It is deliberately additive and version-gated:
/// * a station is inserted only when its id is absent from the box, so a place
///   the user edited (`isCustom: true`) is never overwritten,
/// * a station that already exists under the same name and coordinates is
///   skipped, so a user who saved it manually does not get a duplicate,
/// * [AppConfig.stationsSeedVersionKey] records the catalogue version, so a
///   station the user deleted does not come back on the next launch and a new
///   catalogue can still top up the list by bumping
///   [AppConfig.stationsSeedVersion].
class DatabaseSeeder {
  DatabaseSeeder._();

  /// The seeded catalogue asset (declared in `pubspec.yaml`).
  static const String assetPath = 'assets/data/stations.json';

  /// Merges the bundled catalogue into [placesBox].
  ///
  /// Returns how many stations were inserted (0 when the current catalogue
  /// version was already applied). Never throws on a malformed catalogue
  /// entry: the app must still boot with whatever it can parse.
  static Future<int> maybeSeed({
    required Box<dynamic> placesBox,
    required Box<dynamic> settingsBox,
    Future<String> Function(String asset)? loadAsset,
  }) async {
    final Object? seededVersion =
        settingsBox.get(AppConfig.stationsSeedVersionKey);
    if (seededVersion is int &&
        seededVersion >= AppConfig.stationsSeedVersion) {
      return 0;
    }

    final String jsonString =
        await (loadAsset ?? rootBundle.loadString)(assetPath);

    // A corrupted or truncated catalogue must never block the first frame: the
    // app simply launches without the bundled stations.
    Object? decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException {
      return 0;
    }
    if (decoded is! List) return 0;

    // Existing ids plus a name+coordinates signature so a manually saved copy
    // of the same station is not duplicated by the seed.
    final Set<String> existingIds = <String>{
      for (final Object? key in placesBox.keys) key.toString(),
    };
    final Set<String> existingSignatures = <String>{};
    for (final Object? raw in placesBox.values) {
      if (raw is! Map) continue;
      existingSignatures.add(_signature(Place.fromMap(Map<String, dynamic>.from(raw))));
    }

    int inserted = 0;
    for (final Object? entry in decoded) {
      if (entry is! Map) continue;
      final Place place = Place.fromMap(Map<String, dynamic>.from(entry))
          .copyWith(isDefault: true, isCustom: false);
      if (place.id.isEmpty || place.name.isEmpty) continue;
      // A zero coordinate is a parse failure, not a station.
      if (place.latitude == 0 && place.longitude == 0) continue;
      if (existingIds.contains(place.id)) continue;
      if (existingSignatures.contains(_signature(place))) continue;

      await placesBox.put(place.id, place.toMap());
      existingIds.add(place.id);
      existingSignatures.add(_signature(place));
      inserted++;
    }

    await placesBox.flush();
    await settingsBox.put(AppConfig.stationsSeedVersionKey, AppConfig.stationsSeedVersion);
    return inserted;
  }

  /// Coarse identity for duplicate detection: same name at the same ~1 m spot.
  static String _signature(Place place) =>
      '${place.name.trim()}|${place.latitude.toStringAsFixed(5)}|'
      '${place.longitude.toStringAsFixed(5)}';
}
