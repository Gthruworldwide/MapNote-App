import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_ce/hive.dart';
import 'package:integration_test/integration_test.dart';

import 'package:routenote/app.dart';
import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/local/place_local_data_source.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/data/remote/auth_service.dart';
import 'package:routenote/src/features/home/widgets/place_card.dart';
import 'package:routenote/src/features/home/widgets/smart_insights_card.dart';
import 'package:routenote/src/features/settings/settings_screen.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/app_health_logger.dart';
import 'package:routenote/src/services/biometric_service.dart';
import 'package:routenote/src/services/location_service.dart';

/// End-to-end UI flow tests for MapNote.
///
/// Run them against a device/emulator with:
///
/// ```sh
/// flutter test integration_test/app_test.dart -d <device-id>
/// # or the convenience wrapper:
/// ./scripts/run_integration_tests.ps1 -Device <device-id>
/// ```
///
/// Unlike the widget tests under `test/`, the integration binding uses *real*
/// async I/O, so these tests exercise the actual widget tree, Riverpod wiring
/// and genuine Hive storage (a per-test temp directory). The external platform
/// channels that would otherwise block or leave the app (Google sign-in,
/// biometrics, geolocator) are stubbed with fakes so the flows stay
/// deterministic.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<dynamic> placesBox;
  late Box<dynamic> settingsBox;
  late HiveDatabase database;
  late PlaceLocalDataSource dataSource;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routenote_it_');
    Hive.init(tempDir.path);
    placesBox = await Hive.openBox<dynamic>('it_places');
    settingsBox = await Hive.openBox<dynamic>('it_settings');
    database = HiveDatabase(placesBox: placesBox, settingsBox: settingsBox);
    dataSource = PlaceLocalDataSource(database);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Boots the real app with fake platform services.
  Future<void> pumpApp(
    WidgetTester tester, {
    bool biometricVerdict = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hiveDatabaseProvider.overrideWithValue(database),
          // Never touch the `google_sign_in` platform channel.
          authServiceProvider.overrideWithValue(_FakeAuthService()),
          // No file-backed health log is needed by these flows.
          appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
          // Deterministic unlock: the fake always (or never) verifies.
          biometricServiceProvider.overrideWithValue(
            _FakeBiometrics(verdict: biometricVerdict),
          ),
          // Location is "ready" so no indeterminate spinner blocks settling.
          locationServiceProvider.overrideWithValue(
            const _FakeLocationService(),
          ),
        ],
        child: const MapNoteApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Place samplePlace({bool locked = false}) => Place(
    id: 'place-1',
    name: 'Cairo Tower',
    notes: 'Near the Nile',
    latitude: 30.0444,
    longitude: 31.2357,
    timestamp: DateTime.utc(2026, 1, 1),
    isLocked: locked,
  );

  testWidgets(
    'launches and navigates the main areas (Places, Settings, Smart Insights)',
    (WidgetTester tester) async {
      await dataSource.put(samplePlace());
      await pumpApp(tester);

      // --- Places: the home list ------------------------------------------
      expect(find.text('My Places'), findsOneWidget);
      expect(find.byType(PlaceCard), findsOneWidget);

      // --- Smart Insights: the agent card is mounted on Home --------------
      expect(find.byType(SmartInsightsCard), findsOneWidget);

      // --- Settings: pushed from the app bar ------------------------------
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsWidgets);

      // The Smart Insights master toggle lives further down the (lazy)
      // settings list, so scroll it into view before asserting.
      final Finder smartInsightsToggle = find.text('Enable Smart Insights');
      await tester.scrollUntilVisible(
        smartInsightsToggle,
        300,
        scrollable: find.descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(Scrollable),
        ),
      );
      expect(smartInsightsToggle, findsOneWidget);

      // --- Back to Places --------------------------------------------------
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('My Places'), findsOneWidget);
      expect(find.byType(PlaceCard), findsOneWidget);
    },
  );

  testWidgets(
    'long-press opens the place actions sheet without any layout overflow',
    (WidgetTester tester) async {
      // Collect RenderFlex overflow reports explicitly so the intent is clear;
      // the test binding would fail on them anyway.
      final List<String> overflowReports = <String>[];
      final FlutterExceptionHandler? previousErrorHandler = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        final String text = details.exceptionAsString();
        if (text.contains('overflowed')) overflowReports.add(text);
        previousErrorHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousErrorHandler);

      await dataSource.put(samplePlace());
      await pumpApp(tester);

      await tester.longPress(find.byType(PlaceCard));
      await tester.pumpAndSettle();

      // Every action is present and reachable inside the sheet.
      expect(find.text('Navigate'), findsOneWidget);
      expect(find.text('Pin to top'), findsOneWidget);
      expect(find.text('Share QR code'), findsOneWidget);
      expect(find.text('Add shortcut to home screen'), findsOneWidget);
      expect(find.text('Lock location'), findsOneWidget);
      expect(find.text('Hide location'), findsOneWidget);

      expect(
        overflowReports,
        isEmpty,
        reason: 'The place actions sheet must not overflow: $overflowReports',
      );

      // Dismiss via the modal barrier and confirm we are back on the list.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(PlaceCard), findsOneWidget);
    },
  );

  // The next two tests exercise the two directions of the lock/unlock toggle.
  // Each starts from a known seed and performs a single sheet interaction,
  // which keeps the flow deterministic (mirroring `test/unlock_flow_test.dart`).
  testWidgets(
    'locking a place through the actions sheet masks it in the list',
    (WidgetTester tester) async {
      await dataSource.put(samplePlace());
      await pumpApp(tester);

      // Starts unlocked: the real title is visible.
      expect(find.text('Cairo Tower'), findsOneWidget);

      await tester.longPress(find.byType(PlaceCard));
      await tester.pumpAndSettle();
      expect(find.text('Lock location'), findsOneWidget);

      await tester.tap(find.text('Lock location'));
      await tester.pumpAndSettle();

      expect(find.text('Location locked'), findsOneWidget);
      final Place? stored = await dataSource.getById('place-1');
      expect(stored, isNotNull);
      expect(stored!.isLocked, isTrue);

      // Locked rows are masked, so the raw title must not be on screen.
      expect(find.text('Cairo Tower'), findsNothing);
    },
  );

  testWidgets(
    'unlocking a locked place through the actions sheet reveals it again',
    (WidgetTester tester) async {
      await dataSource.put(samplePlace(locked: true));
      await pumpApp(tester);

      // Starts locked and masked.
      expect(find.text('Cairo Tower'), findsNothing);

      await tester.longPress(find.byType(PlaceCard));
      await tester.pumpAndSettle();
      expect(find.text('Unlock location'), findsOneWidget);

      // Unlocking is verified (fake verdict: verified), persisted to Hive and
      // reflected back into the list.
      await tester.tap(find.text('Unlock location'));
      await tester.pumpAndSettle();

      final Place? stored = await dataSource.getById('place-1');
      expect(stored, isNotNull);
      expect(stored!.isLocked, isFalse);
      expect(find.text('Cairo Tower'), findsOneWidget);
      expect(find.textContaining('30.044'), findsOneWidget);
    },
  );
}

/// Stand-in for [AuthService] so tests never touch the `google_sign_in`
/// platform channel.
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

/// Fake identity gate with a test-controlled verdict, so the lock/unlock flow
/// runs without the `local_auth` platform channel.
class _FakeBiometrics extends BiometricService {
  const _FakeBiometrics({required this.verdict});

  final bool verdict;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> authenticate({required String reason}) async => verdict;
}

/// Fake geolocator-backed service reporting "all good", so location rows render
/// instantly and no spinner ever blocks `pumpAndSettle`.
class _FakeLocationService extends LocationService {
  const _FakeLocationService();

  @override
  Future<bool> isServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.always;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<LocationResult> determinePosition() async =>
      const LocationSuccess(latitude: 30.0444, longitude: 31.2357);
}
