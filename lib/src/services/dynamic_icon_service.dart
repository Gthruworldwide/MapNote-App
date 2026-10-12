import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';

import 'app_logger.dart';

/// Keeps the Android launcher icon in sync with the effective app theme.
///
/// RouteNote ships a light launcher icon (`.ic_launcher`, white backdrop +
/// blue pin) and a dark variant (`.ic_launcher_dark`, AMOLED-black backdrop).
/// Both are declared as a pair of `<activity-alias>` entries in
/// AndroidManifest.xml; [apply] enables the alias matching the requested
/// brightness via `flutter_dynamic_icon_plus`, which disables the other alias
/// so the launcher always shows exactly one entry.
///
/// [lightIconName]/[darkIconName] must stay **fully qualified**
/// (`<applicationId>.ic_launcher_dark`). flutter_dynamic_icon_plus feeds the
/// string straight into `ComponentName(context, name)` and also stores it
/// verbatim in SharedPreferences to compare against `ActivityInfo.name`
/// (always fully qualified). A short name such as `ic_launcher_dark` is not
/// expanded by the system, so `setComponentEnabledSetting` throws
/// "Component class … does not exist" from inside the plugin's own service —
/// a native crash Dart cannot catch. It would also never match the plugin's
/// bookkeeping, which would disable the alias it had just enabled.
///
/// The switch is best-effort:
/// * On platforms without alternate-icon support it silently no-ops
///   (including the MissingPluginException path in `flutter test`).
/// * Genuine failures are logged rather than thrown — a launcher icon must
///   never take the app down.
class DynamicIconService {
  const DynamicIconService();

  /// Component names of the launcher `<activity-alias>` entries declared in
  /// AndroidManifest.xml, in the fully-qualified form
  /// flutter_dynamic_icon_plus requires. The prefix is the app's
  /// `applicationId` (`android/app/build.gradle.kts`); changing it means
  /// changing these too.
  static const String lightIconName = 'com.routenote.routenote.ic_launcher';
  static const String darkIconName =
      'com.routenote.routenote.ic_launcher_dark';

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
      // alternateIconName reports the enabled alias in the same
      // fully-qualified shape as [target], so an exact compare decides
      // whether a switch is needed. Substring/tail compares are deliberately
      // avoided: the bare fragment 'ic_launcher' also occurs inside
      // 'ic_launcher_dark', which made the old check order-dependent.
      if (current == target) return;
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