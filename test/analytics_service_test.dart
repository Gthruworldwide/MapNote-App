import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/app.dart';
import 'package:routenote/src/data/local/auto_motion_data_source.dart';
import 'package:routenote/src/data/local/hive_database.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/data/remote/auth_service.dart';
import 'package:routenote/src/features/home/widgets/auto_motion_card.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/analytics_service.dart';
import 'package:routenote/src/services/app_health_logger.dart';
import 'package:routenote/src/services/auto_motion_service.dart';
import 'package:routenote/src/services/foreground_tracking_service.dart';
import 'package:routenote/src/services/location_service.dart';
import 'package:routenote/src/services/share_intent_service.dart';
import 'package:routenote/src/widgets/qibla_indicator.dart';

/// One recorded [AnalyticsService.logEvent] call.
class _LoggedEvent {
  const _LoggedEvent(this.name, this.parameters);

  final String name;
  final Map<String, Object>? parameters;
}

/// Stands in for Firebase Analytics: records what the app emits instead of
/// sending it. Tests never initialise Firebase, so the real service would
/// simply drop everything and nothing could be asserted.
class _RecordingAnalytics extends AnalyticsService {
  final List<_LoggedEvent> logged = <_LoggedEvent>[];

  List<String> get names =>
      logged.map((_LoggedEvent event) => event.name).toList(growable: false);

  @override
  Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    logged.add(_LoggedEvent(name, parameters));
  }
}

/// Stand-in for [ShareIntentService]: the real one subscribes to an EventChannel
/// whose "listen" has no handler in a widget test, and that MissingPluginException
/// lands in the test's real-event-loop window as an uncaught async error.
class _FakeShareIntentService extends ShareIntentService {
  @override
  Stream<String> textStream() => const Stream<String>.empty();

  @override
  Future<List<String>> initialText() async => const <String>[];
}

/// Stand-in for [AuthService] so widget tests never touch the
/// `google_sign_in` platform channel.
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

/// A tracker that reports (and performs) a real start/stop transition without
/// touching the geolocator channels — which never resolve inside the FakeAsync
/// zone of a widget test — so the trip lifecycle events are observable.
class _TrackableMotion extends AutoMotionService {
  _TrackableMotion(AutoMotionDataSource store) : super(dailyStore: store);

  bool _tracking = false;

  @override
  bool get isTracking => _tracking;

  @override
  Future<bool> start({
    LocationService? locations,
    Stream<Position>? positions,
  }) async {
    _tracking = true;
    return true;
  }

  @override
  // A real stop() persists to Hive; handing that write to the FakeAsync
  // teardown zone would hang the runner.
  Future<void> stop() async => _tracking = false;
}

/// Native foreground-service channel, mocked for the duration of each test.
///
/// `AutoMotionController` runs its start/stop actions on a serialized queue
/// whose every turn awaits `ForegroundTrackingService.sync()`. With no handler
/// that call never resolves inside the FakeAsync zone of a widget test (its
/// only escape is a 25s timeout the fake clock does not reach), so the queue
/// would stall and the queued `_idleNow` would never run.
const MethodChannel _trackingChannel = MethodChannel(
  ForegroundTrackingService.channelName,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<dynamic> placesBox;
  late Box<dynamic> settingsBox;
  late HiveDatabase database;
  late _RecordingAnalytics analytics;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routenote_analytics_');
    Hive.init(tempDir.path);
    placesBox = await Hive.openBox<dynamic>('test_places');
    settingsBox = await Hive.openBox<dynamic>('test_settings');
    database = HiveDatabase(placesBox: placesBox, settingsBox: settingsBox);
    analytics = _RecordingAnalytics();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _trackingChannel,
      (MethodCall call) async => true,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_trackingChannel, null);
    await placesBox.close();
    await settingsBox.close();
    await tempDir.delete(recursive: true);
  });

  // `Override` is deliberately not exported by name in Riverpod 3, so the
  // list type is inferred from the `overrideWith*` calls.
  overrides({AutoMotionService? motion}) => [
        hiveDatabaseProvider.overrideWithValue(database),
        authServiceProvider.overrideWithValue(_FakeAuthService()),
        // The widget tree runs inside a FakeAsync zone, where a real Hive
        // write can never complete (and would deadlock `box.close()` in
        // tearDown). Keep the health log in memory for these tests.
        appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
        analyticsServiceProvider.overrideWithValue(analytics),
        shareIntentServiceProvider.overrideWithValue(_FakeShareIntentService()),
        if (motion != null) autoMotionServiceProvider.overrideWithValue(motion),
      ];

  Future<void> pumpApp(
    WidgetTester tester, {
    AutoMotionService? motion,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(motion: motion),
        child: const MapNoteApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  // ---------------------------------------------------------------------------
  // Offline-first degradation (AGENT_SKILLS.md §1.1)
  // ---------------------------------------------------------------------------

  test('without Firebase every event is a silent no-op, never a crash', () async {
    final AnalyticsService service = AnalyticsService();

    expect(service.analytics, isNull,
        reason: 'no Firebase app is initialised inside tests');
    expect(service.isEnabled, isFalse);
    await expectLater(
      service.logEvent(AnalyticsEvents.placeSaved),
      completes,
      reason: 'a build without google-services.json must still boot and run',
    );
  });

  test('the observer list stays empty when Firebase is unavailable', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(analyticsServiceProvider).isEnabled, isFalse);
    expect(container.read(analyticsNavigatorObserversProvider), isEmpty,
        reason: 'navigation must never depend on Firebase being present');
  });

  // ---------------------------------------------------------------------------
  // Event names (firebase_analytics throws on invalid / reserved names)
  // ---------------------------------------------------------------------------

  test('every custom event name is a valid, non-reserved Analytics name', () {
    const List<String> names = <String>[
      AnalyticsEvents.autoMotionTripStarted,
      AnalyticsEvents.autoMotionTripEnded,
      AnalyticsEvents.qiblaCompassOpened,
      AnalyticsEvents.placeSaved,
    ];

    // Names drawn from firebase_analytics' own validation rules: at most 40
    // `[a-zA-Z0-9_]` characters, never the reserved `firebase_` prefix and
    // never one of its reserved built-in names (logEvent throws on all three).
    const List<String> reserved = <String>[
      'error',
      'app_exception',
      'first_open',
      'user_engagement',
      'session_start',
      'app_remove',
    ];

    for (final String name in names) {
      expect(name, matches(RegExp(r'^[a-zA-Z0-9_]{1,40}$')),
          reason: '"$name" would be rejected by logEvent');
      expect(name.startsWith('firebase_'), isFalse,
          reason: '"$name" uses a reserved prefix');
      expect(reserved, isNot(contains(name)),
          reason: '"$name" collides with a built-in Analytics event');
    }
  });

  // ---------------------------------------------------------------------------
  // Core flows
  // ---------------------------------------------------------------------------

  test('saving a place logs place_saved without any place data', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: overrides(),
    );
    addTearDown(container.dispose);

    await container.read(placesProvider.notifier).save(
          Place(
            id: 'place-1',
            name: 'Cairo Tower',
            notes: 'Near the Nile',
            latitude: 30.0444,
            longitude: 31.2357,
            timestamp: DateTime.utc(2026, 10, 9, 12),
          ),
        );

    final _LoggedEvent saved = analytics.logged.singleWhere(
      (_LoggedEvent event) => event.name == AnalyticsEvents.placeSaved,
    );
    expect(analytics.names, <String>[AnalyticsEvents.placeSaved],
        reason: 'the add/edit funnel must emit the event exactly once');

    // Privacy: nothing identifying the place leaves the device — no name, no
    // notes, no coordinates (AGENT_SKILLS.md §2.3).
    expect(saved.parameters ?? <String, Object>{}, isEmpty);
  });

  testWidgets('opening the compass sheet logs qibla_compass_opened once',
      (WidgetTester tester) async {
    await pumpApp(tester);
    expect(analytics.names, isEmpty);

    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pumpAndSettle();

    expect(analytics.names, <String>[AnalyticsEvents.qiblaCompassOpened]);

    // Dismiss the sheet so teardown runs against a settled tree.
    Navigator.of(tester.element(find.byType(QiblaIndicator))).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('expanding the compass island logs the event, collapsing does not',
      (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.longPress(find.byIcon(Icons.explore_outlined));
    await tester.pumpAndSettle();
    expect(analytics.names, <String>[AnalyticsEvents.qiblaCompassOpened]);

    // Collapsing the island hides the compass, so it must not add a second
    // "opened" event to the funnel.
    await tester.longPress(find.byIcon(Icons.explore));
    await tester.pumpAndSettle();
    expect(analytics.names, hasLength(1));
  });

  testWidgets(
      'one AutoMotion session logs exactly one trip_started and one '
      'trip_ended', (WidgetTester tester) async {
    await tester.runAsync(() => settingsBox.put('enable_auto_motion', true));
    await pumpApp(
      tester,
      motion: _TrackableMotion(AutoMotionDataSource(settingsBox)),
    );

    // The controller reconciles on every rebuild while enabled; the transition
    // guard must keep the funnel at a single "started" event regardless.
    expect(find.byType(AutoMotionCard), findsOneWidget);
    expect(analytics.names, <String>[AnalyticsEvents.autoMotionTripStarted]);

    // Flip the toggle the way Settings does, then let the queued stop run.
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(TextField)),
    );
    await tester.runAsync(() async {
      await container
          .read(autoMotionEnabledProvider.notifier)
          .setEnabled(false);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    await tester.pump();

    expect(analytics.names, <String>[
      AnalyticsEvents.autoMotionTripStarted,
      AnalyticsEvents.autoMotionTripEnded,
    ]);
  });
}
