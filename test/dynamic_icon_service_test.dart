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

    test('the dark alias name contains the light one (regression guard)', () {
      // apply() compares the FQ component name with a '.$target' suffix, never a
      // plain substring, precisely because of this overlap.
      expect(DynamicIconService.darkIconName, contains(DynamicIconService.lightIconName));
      expect(
        'com.routenote.routenote.ic_launcher_dark'
            .endsWith('.${DynamicIconService.lightIconName}'),
        isFalse,
      );
      expect(
        'com.routenote.routenote.ic_launcher_dark'
            .endsWith('.${DynamicIconService.darkIconName}'),
        isTrue,
      );
    });
  });
}