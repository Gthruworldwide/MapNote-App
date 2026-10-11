import 'package:hive_ce/hive.dart';

/// Thin wrapper around the opened Hive boxes so the rest of the app does not
/// depend on Hive's static API directly.
class HiveDatabase {
  HiveDatabase({
    required this.placesBox,
    required this.settingsBox,
    Box<dynamic>? gpsDailyBox,
  }) : gpsDailyBox = gpsDailyBox ?? settingsBox;

  /// Box keyed by place id, values are JSON-compatible maps.
  final Box<dynamic> placesBox;

  /// Small box for app preferences (locale, last sync timestamp, ...).
  final Box<dynamic> settingsBox;

  /// Per-day GPS tracking summaries. `main()` passes a dedicated box; other
  /// constructors (background isolate, tests) fall back to the settings box so
  /// nothing extra needs to be opened.
  final Box<dynamic> gpsDailyBox;
}
