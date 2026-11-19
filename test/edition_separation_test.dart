import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/app.dart';
import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/core/config/app_config.dart';
import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/remote/auth_service.dart';
import 'package:routenote/src/features/automotion/automotion_screen.dart';
import 'package:routenote/src/features/automotion/route_history_screen.dart';
import 'package:routenote/src/features/home/widgets/auto_motion_card.dart';
import 'package:routenote/src/features/settings/location_settings_screen.dart';
import 'package:routenote/src/features/settings/preferences_settings_screen.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/app_health_logger.dart';

String _read(String path) => File(path).readAsStringSync();

/// True when [tag] has a node in [manifest] that both names [name] and carries
/// `tools:node="remove"` — the marker that makes manifest merger drop the node
/// inherited from the main source set.
bool _removesManifestNode(String manifest, String tag, String name) {
  final RegExp element = RegExp('<$tag\\b[^>]*?/>', dotAll: true);
  for (final Match match in element.allMatches(manifest)) {
    final String chunk = match.group(0)!;
    if (chunk.contains(name) && chunk.contains('tools:node="remove"')) {
      return true;
    }
  }
  return false;
}

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
  }) async =>
      null;
}

void main() {
  group('Android product-flavour separation', () {
    const String gradlePath = 'android/app/build.gradle.kts';
    const String mainManifest = 'android/app/src/main/AndroidManifest.xml';
    const String workManifest = 'android/app/src/work/AndroidManifest.xml';
    const String automotionManifest =
        'android/app/src/automotion/AndroidManifest.xml';

    test('both build-bound flavours are declared on the edition dimension', () {
      final String gradle = _read(gradlePath);
      expect(gradle, contains('flavorDimensions += "edition"'));
      expect(gradle, contains('create("work")'));
      expect(gradle, contains('create("automotion")'));
      expect(gradle, contains('versionNameSuffix = "-work"'));
      expect(gradle, contains('versionNameSuffix = "-automotion"'));
      expect(
        gradle,
        isNot(contains('applicationIdSuffix')),
        reason:
            'both flavours must keep the application id so the Firebase app '
            'and Drive OAuth client stay valid',
      );
    });

    test('work manifest removes every vehicle-only permission and service', () {
      final String work = _read(workManifest);
      const List<String> vehicleNodes = <String>[
        'android.permission.ACCESS_BACKGROUND_LOCATION',
        'android.permission.ACTIVITY_RECOGNITION',
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_LOCATION',
      ];
      for (final String permission in vehicleNodes) {
        expect(
          _removesManifestNode(work, 'uses-permission', permission),
          isTrue,
          reason: 'work must not request $permission',
        );
      }
      expect(
        _removesManifestNode(work, 'service', '.LocationTrackingService'),
        isTrue,
        reason: 'work must not ship the automotive tracking foreground service',
      );
    });

    test('the removed nodes really come from the main source set', () {
      // A `tools:node="remove"` for something the main manifest never declares
      // would be a no-op, so pin the main declarations as well.
      final String main = _read(mainManifest);
      for (final String permission in <String>[
        'android.permission.ACCESS_BACKGROUND_LOCATION',
        'android.permission.ACTIVITY_RECOGNITION',
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_LOCATION',
      ]) {
        expect(main, contains(permission));
      }
      expect(main, contains('android:name=".LocationTrackingService"'));
    });

    test('automotion manifest keeps the main source-set permissions', () {
      final String automotion = _read(automotionManifest);
      expect(
        automotion,
        isNot(contains('tools:node="remove"')),
        reason: 'automotion must not strip any vehicle capability',
      );
    });

    test('work flavour declaratively maps to the work edition build define', () {
      // The CI matrix injects MAPNOTE_EDITION and builds the matching flavour;
      // the workflow test pins the matrix itself. Here we verify the two names
      // agree so a typo cannot build a work APK with automotion capabilities.
      final String gradle = _read(gradlePath);
      expect(gradle, contains('manifestPlaceholders["mapnoteEdition"] = "work"'));
      expect(
        gradle,
        contains('manifestPlaceholders["mapnoteEdition"] = "automotion"'),
      );
      expect(AppConfig.parseEdition('work'), AppEdition.work);
      expect(AppConfig.parseEdition('automotion'), AppEdition.automotion);
    });
  });

  group('work edition hides AutoMotion UI and metrics', () {
    late Directory tempDir;
    late Box<dynamic> placesBox;
    late Box<dynamic> settingsBox;
    late HiveDatabase database;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('edition_ui_');
      Hive.init(tempDir.path);
      placesBox = await Hive.openBox<dynamic>('edition_ui_places');
      settingsBox = await Hive.openBox<dynamic>('edition_ui_settings');
      database = HiveDatabase(placesBox: placesBox, settingsBox: settingsBox);
    });

    tearDown(() async {
      await placesBox.close();
      await settingsBox.close();
      await tempDir.delete(recursive: true);
    });

    List<Override> baseOverrides() => <Override>[
          hiveDatabaseProvider.overrideWithValue(database),
          authServiceProvider.overrideWithValue(_FakeAuthService()),
          appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
        ];

    Future<void> pumpScreen(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(900, 1900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: child,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('location settings show no tracking section', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, const LocationSettingsScreen());

      // The AutoMotion section (and its toggles/report) is gone in work.
      expect(find.text('AutoMotion'), findsNothing);
      expect(find.text('Enable Smart AutoMotion'), findsNothing);
      expect(find.text('Distance today'), findsNothing);
    });

    testWidgets('the AutoMotion dashboard is replaced by an edition notice', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, const AutoMotionScreen());

      // Tests run in the default (English) locale.
      expect(
        find.text('This feature is not available in this edition.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.file_download_outlined), findsNothing);
    });

    testWidgets('route history is replaced by an edition notice', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, const RouteHistoryScreen());

      expect(
        find.text('This feature is not available in this edition.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.calendar_month_outlined), findsNothing);
    });

    testWidgets('preferences hide the motion-data export entry', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, const PreferencesSettingsScreen());

      expect(find.text('Export motion data'), findsNothing);
      expect(find.byIcon(Icons.file_download_outlined), findsNothing);
    });

    testWidgets('the Home screen renders no AutoMotion status card', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(),
          child: const MapNoteApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AutoMotionCard), findsNothing);
    });
  });
}
