import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/remote/auth_service.dart';
import 'package:routenote/src/features/settings/location_settings_screen.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/app_health_logger.dart';

class _FakeAuthService implements AuthService {
  @override
  AuthUser? get currentUser => null;

  @override
  bool get isSignedIn => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<AuthUser?> signInSilently() async => null;

  @override
  Future<AuthUser> signIn() => throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  Future<Map<String, String>?> authorizationHeaders({
    bool prompt = false,
  }) async {
    return null;
  }
}

void main() {
  late Directory tempDir;
  late Box<dynamic> placesBox;
  late Box<dynamic> settingsBox;
  late HiveDatabase database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routenote_gps_ui_');
    Hive.init(tempDir.path);
    placesBox = await Hive.openBox<dynamic>('test_places');
    settingsBox = await Hive.openBox<dynamic>('test_settings');
    database = HiveDatabase(placesBox: placesBox, settingsBox: settingsBox);
  });

  tearDown(() async {
    await placesBox.close();
    await settingsBox.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    // Taller viewport so every settings section is mounted (ListView only
    // builds visible children at 800x600).
    tester.view.physicalSize = const Size(800, 1900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hiveDatabaseProvider.overrideWithValue(database),
          authServiceProvider.overrideWithValue(_FakeAuthService()),
          appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LocationSettingsScreen(),
        ),
      ),
    );
    // No pumpAndSettle: the location status row shows an indeterminate spinner.
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('settings shows the daily GPS toggle (off by default)',
      (WidgetTester tester) async {
    await pumpSettings(tester);

    expect(find.text('Enable Smart AutoMotion'), findsOneWidget);
    expect(
      find.text(
        'Fuses GPS and motion sensors to track distance & speed while saving battery',
      ),
      findsOneWidget,
    );

    // Off by default: the report tile is hidden.
    expect(find.text('Distance today'), findsNothing);

    // The switch reflects the default (off).
    final Finder gpsSwitch = find.descendant(
      of: find.widgetWithText(
        SwitchListTile,
        'Enable Smart AutoMotion',
      ),
      matching: find.byType(Switch),
    );
    final Switch switchWidget = tester.widget<Switch>(gpsSwitch);
    expect(switchWidget.value, isFalse);
  });

  testWidgets('when enabled in storage the toggle is on and the report tile '
      'shows today\'s distance and max speed', (WidgetTester tester) async {
    // Seed through runAsync: real Hive writes cannot complete inside the
    // FakeAsync zone of a widget test.
    await tester.runAsync(
      () => settingsBox.put('gps_tracking_enabled', true),
    );

    await pumpSettings(tester);

    final Finder gpsSwitch = find.descendant(
      of: find.widgetWithText(
        SwitchListTile,
        'Enable Smart AutoMotion',
      ),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(gpsSwitch).value, isTrue);

    // The daily report tile is now visible with km / km/h units.
    expect(find.text('Distance today'), findsOneWidget);
    expect(find.text('Max speed'), findsOneWidget);
    expect(find.textContaining('km/h'), findsWidgets);
  });

  testWidgets('flipping the toggle on persists it and reveals the report tile',
      (WidgetTester tester) async {
    await pumpSettings(tester);
    expect(find.text('Distance today'), findsNothing);

    final Finder gpsSwitch = find.descendant(
      of: find.widgetWithText(
        SwitchListTile,
        'Enable Smart AutoMotion',
      ),
      matching: find.byType(Switch),
    );

    // The onChanged handler writes to real Hive: drive the tap through the
    // real event loop with runAsync so the write (and the follow-up provider
    // update) completes before we return to the FakeAsync zone.
    await tester.runAsync(() async {
      await tester.tap(gpsSwitch);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    await tester.pump();

    expect(find.text('Distance today'), findsOneWidget);
    expect(find.text('Max speed'), findsOneWidget);

    // Persisted for future launches.
    bool? persisted;
    await tester.runAsync(() async {
      persisted = settingsBox.get('gps_tracking_enabled') as bool?;
    });
    expect(persisted, isTrue);

    // And it survives a fresh screen (same storage).
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpSettings(tester);
    expect(find.text('Distance today'), findsOneWidget);
  });
}