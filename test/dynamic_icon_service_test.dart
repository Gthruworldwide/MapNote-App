import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routenote/src/services/dynamic_icon_service.dart';

void main() {
  group('DynamicIconService.iconNameFor', () {
    test('forced light mode always selects the light alias', () {
      expect(
        DynamicIconService.iconNameFor(ThemeMode.light, Brightness.light),
        DynamicIconService.lightIconName,
      );
      // Explicit light overrides a dark OS setting.
      expect(
        DynamicIconService.iconNameFor(ThemeMode.light, Brightness.dark),
        DynamicIconService.lightIconName,
      );
    });

    test('forced dark mode always selects the dark alias', () {
      expect(
        DynamicIconService.iconNameFor(ThemeMode.dark, Brightness.dark),
        DynamicIconService.darkIconName,
      );
      // Explicit dark overrides a light OS setting.
      expect(
        DynamicIconService.iconNameFor(ThemeMode.dark, Brightness.light),
        DynamicIconService.darkIconName,
      );
    });

    test('system mode follows the OS brightness', () {
      expect(
        DynamicIconService.iconNameFor(ThemeMode.system, Brightness.light),
        DynamicIconService.lightIconName,
      );
      expect(
        DynamicIconService.iconNameFor(ThemeMode.system, Brightness.dark),
        DynamicIconService.darkIconName,
      );
    });

    test('isDark mirrors the selected alias', () {
      expect(DynamicIconService.isDark(ThemeMode.dark, Brightness.light), isTrue);
      expect(DynamicIconService.isDark(ThemeMode.light, Brightness.dark), isFalse);
      expect(DynamicIconService.isDark(ThemeMode.system, Brightness.dark), isTrue);
      expect(
        DynamicIconService.isDark(ThemeMode.system, Brightness.light),
        isFalse,
      );
    });

    test('alias names are fully qualified so the plugin can resolve them', () {
      // flutter_dynamic_icon_plus passes these strings straight into
      // ComponentName(context, name) and stores them to compare against
      // ActivityInfo.name (always fully qualified). A short name
      // ('ic_launcher_dark') is not expanded by the system, so
      // setComponentEnabledSetting throws "Component class … does not exist"
      // from inside the plugin's service — an uncatchable native crash.
      const String applicationId = 'com.routenote.routenote';
      expect(
        DynamicIconService.lightIconName,
        '$applicationId.ic_launcher',
      );
      expect(
        DynamicIconService.darkIconName,
        '$applicationId.ic_launcher_dark',
      );
    });

    test('the two alias names are distinct with no prefix overlap', () {
      // The dark alias name contains the light one, so apply() compares the
      // full component name for equality rather than testing a substring or
      // tail — 'com.routenote.routenote.ic_launcher' is not the tail of the
      // dark name, but the bare 'ic_launcher' fragment is.
      expect(
        DynamicIconService.darkIconName,
        contains(DynamicIconService.lightIconName),
      );
      expect(
        DynamicIconService.darkIconName
            .endsWith(DynamicIconService.lightIconName),
        isFalse,
      );
      expect(
        DynamicIconService.lightIconName == DynamicIconService.darkIconName,
        isFalse,
      );
    });
  });
}