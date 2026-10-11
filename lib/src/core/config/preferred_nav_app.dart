/// The app used to launch turn-by-turn navigation from place cards.
///
/// Persisted in the Hive settings box under `preferred_nav_app` (as the enum's
/// stable `name`).
enum PreferredNavApp {
  /// Let the operating system choose (platform default).
  system,

  /// Google Maps, via `google.navigation:` / `comgooglemaps://`.
  googleMaps,

  /// Waze, via `waze://` (falls back to its universal link).
  waze,
}
