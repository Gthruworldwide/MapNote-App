import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';

import 'app_logger.dart';

/// Keeps the Android launcher icon in sync with the effective app theme.
///
/// RouteNote ships a light launcher icon (`ic_launcher`, white backdrop + blue
/// pin) and a dark variant (`ic_launcher_dark`, navy backdrop + white pin).
/// Both are declared as a pair of `<activity-alias>` entries in
/// AndroidManifest.xml; [apply] enables the alias matching the requested
/// brightness via `flutter_dynamic_icon_plus`, which disables the other alias
/// so the launcher always shows exactly one entry.
///
/// The switch is best-effort:
/// * On platforms without alternate-icon support it silently no-ops
///   (including the MissingPluginException path in `flutter test`).
/// * Genuine failures are logged rather than thrown — a launcher icon must
///   never take the app down.
class DynamicIconService {
  const DynamicIconService();

  /// Alias names declared in AndroidManifest.xml (used as the alternate-icon
  /// identifiers by flutter_dynamic_icon_plus).
  static const String lightIconName = 'ic_launcher';
  static const String darkIconName = 'ic_launcher_dark';

  /// Maps a [themeMode] + system [brightness] to the icon variant that should
  /// be active. In forced light/dark the explicit mode wins; in system mode the
  /// icon follows the OS brightness. Pure function, unit-tested.
  static String iconNameFor(ThemeMode themeMode, Brightness brightness) {
    return switch (themeMode) {
      ThemeMode.light => lightIconName,
      ThemeMode.dark => darkIconName,
      ThemeMode.system => brightness == Brightness.dark
          ? darkIconName
          : lightIconName,
    };
  }

  /// True when the dark variant should be active for [themeMode]/[brightness].
  static bool isDark(ThemeMode themeMode, Brightness brightness) =>
      iconNameFor(themeMode, brightness) == darkIconName;

  /// Switches the launcher icon to the variant matching [dark].
  Future<void> apply(bool dark) async {
    final String target = dark ? darkIconName : lightIconName;
    try {
      if (!await FlutterDynamicIconPlus.supportsAlternateIcons) return;
      final String? current = await FlutterDynamicIconPlus.alternateIconName;
      // alternateIconName returns the enabled alias's fully-qualified name,
      // e.g. com.routenote.routenote.ic_launcher_dark. Compare the tail so the
      // sub-string 'ic_launcher' inside 'ic_launcher_dark' can never cause a
      // false "already applied" skip.
      if (current != null && current.endsWith('.$target')) return;
      await FlutterDynamicIconPlus.setAlternateIconName(iconName: target);
    } catch (error) {
      // Unsupported platform / unregistered plugin (e.g. host-side `flutter
      // test`): not an app failure, stay silent.
      if (error is MissingPluginException) return;
      AppLogger.log(
        category: 'UI',
        message: 'Dynamic app icon switch failed',
        error: error.toString(),
        level: LogLevel.warning,
      );
    }
  }
}