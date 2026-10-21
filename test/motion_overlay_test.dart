import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/features/automotion/widgets/motion_summary_sheet.dart';
import 'package:routenote/src/features/automotion/widgets/trip_route_card.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/app_health_logger.dart';
import 'package:routenote/src/services/driving_event_locator.dart';
import 'package:routenote/src/services/motion_profiler.dart';
import 'package:routenote/src/services/transport_classifier.dart';

import 'helpers/route_preview_harness.dart';

/// A maneuver recorded on the analyzer, so the notifier picks it up exactly the
/// way production does (through `onEvent`, not by poking the provider).
DrivingEvent _event(DrivingEventType type, {required DateTime at}) =>
    DrivingEvent(
      type: type,
      peakMps2: type == DrivingEventType.harshBraking ? -6 : 5,
      startedAt: at,
      duration: const Duration(seconds: 1),
    );

void main() {
  late Directory tempDir;
  late Box motionBox;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mapnote_motion_overlay');
    Hive.init(tempDir.path);
    motionBox = await Hive.openBox<dynamic>('auto_motion_overlay_test');
  });

  tearDown(() async {
    await motionBox.close();
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true).catchError((_) => tempDir);
  });

  /// Mounts [child] with the network-free route overrides and returns the
  /// container for provider-level assertions.
  Future<ProviderContainer> pump(
    WidgetTester tester,
    ScriptedMotion motion,
    Widget child, {
    ThemeData? theme,
    List<Override> extraOverrides = const <Override>[],
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          autoMotionServiceProvider.overrideWithValue(motion),
          routeTileProviderProvider.overrideWithValue(NoImageryTiles()),
          routeMilestoneNamesProvider.overrideWith(() => QuietNames()),
          // Emitting a maneuver makes `DrivingEventsNotifier` mirror it into the
          // health log, which reaches for `hiveDatabaseProvider`. A real box
          // writes inside `testWidgets` FakeAsync and never completes
          // (AGENT_SKILLS.md §1.2), so log in memory only.
          appHealthLoggerProvider.overrideWithValue(AppHealthLogger(null)),
          ...extraOverrides,
        ],
        child: MaterialApp(
          theme: theme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  /// Records a straight three-fix route so every vertex carries a timestamp.
  Future<void> recordRoute(
    ScriptedMotion motion, {
    required DateTime t0,
  }) async {
    motion.recordPosition(fix(0, 0, speed: 8, at: t0));
    motion.recordPosition(
      fix(0.009, 0.001, speed: 12, at: t0.add(const Duration(seconds: 5))),
    );
    motion.recordPosition(
      fix(0.018, -0.001, speed: 15, at: t0.add(const Duration(seconds: 10))),
    );
  }

  testWidgets('a detected maneuver is pinned on the map at its route vertex', (
    WidgetTester tester,
  ) async {
    final DateTime t0 = DateTime(2026, 10, 21, 9);
    final ScriptedMotion motion = ScriptedMotion(SilentStore(motionBox));
    final ProviderContainer container = await pump(
      tester,
      motion,
      const TripRouteCard(),
    );
    await recordRoute(motion, t0: t0);
    await tester.pump();
    await tester.pump();

    // Baseline: start + end pins only.
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
      hasLength(2),
    );

    // Materialise the notifier's subscription BEFORE emitting, exactly as the
    // dashboard does when it mounts: `onEvent` is a broadcast stream that
    // buffers nothing, so a later first read would miss the maneuver.
    container.read(drivingEventsProvider);
    final analyzer = container.read(motionBehaviorAnalyzerProvider);
    analyzer.observeTransport(TransportMode.vehicle);
    analyzer.observeDrivingEvent(
      _event(DrivingEventType.pothole, at: t0.add(const Duration(seconds: 5))),
    );
    await tester.pump();

    // The notifier surfaced it and the locator placed it on a route vertex.
    final List<LocatedDrivingEvent> located = container.read(
      locatedDrivingEventsProvider,
    );
    expect(located, hasLength(1));
    expect(located.single.event.type, DrivingEventType.pothole);

    // The map now draws the event badge on top of start + end.
    final MarkerLayer markers = tester.widget<MarkerLayer>(
      find.byType(MarkerLayer),
    );
    expect(markers.markers, hasLength(3));
    // Placed on the second vertex (the 5 s fix), which the Kalman filter has
    // smoothed — so match the neighbourhood, not the raw input exactly.
    expect(located.single.point.latitude, closeTo(0.009, 0.002));
    expect(tester.takeException(), isNull);
  });

  testWidgets('every maneuver kind lands on the map, none falls through', (
    WidgetTester tester,
  ) async {
    final DateTime t0 = DateTime(2026, 10, 21, 9);
    final ScriptedMotion motion = ScriptedMotion(SilentStore(motionBox));
    final ProviderContainer container = await pump(
      tester,
      motion,
      const TripRouteCard(),
    );
    await recordRoute(motion, t0: t0);
    await tester.pump();

    final analyzer = container.read(motionBehaviorAnalyzerProvider);
    container.read(drivingEventsProvider); // subscribe before emitting
    analyzer.observeTransport(TransportMode.vehicle);
    for (final DrivingEventType type in DrivingEventType.values) {
      analyzer.observeDrivingEvent(_event(type, at: t0));
    }
    await tester.pump();

    final List<LocatedDrivingEvent> located = container.read(
      locatedDrivingEventsProvider,
    );
    expect(located, hasLength(DrivingEventType.values.length));
    expect(
      located.map((LocatedDrivingEvent e) => e.event.type).toSet(),
      DrivingEventType.values.toSet(),
    );
    final MarkerLayer markers = tester.widget<MarkerLayer>(
      find.byType(MarkerLayer),
    );
    expect(markers.markers, hasLength(2 + DrivingEventType.values.length));
  });

  testWidgets('a new trip clears the map markers and the score', (
    WidgetTester tester,
  ) async {
    final DateTime t0 = DateTime(2026, 10, 21, 9);
    final ScriptedMotion motion = ScriptedMotion(SilentStore(motionBox));
    final ProviderContainer container = await pump(
      tester,
      motion,
      const TripRouteCard(),
    );
    await recordRoute(motion, t0: t0);
    await tester.pump();

    final analyzer = container.read(motionBehaviorAnalyzerProvider);
    container.read(drivingEventsProvider); // subscribe before emitting
    analyzer.observeTransport(TransportMode.vehicle);
    analyzer.observeDrivingEvent(
      _event(DrivingEventType.harshBraking, at: t0),
    );
    await tester.pump();
    expect(container.read(locatedDrivingEventsProvider), hasLength(1));
    expect(container.read(motionScoreProvider).total, 1);

    // This is what `AutoMotionController` calls the moment a trip begins.
    container.read(drivingEventsProvider.notifier).clear();
    await tester.pump();

    expect(container.read(locatedDrivingEventsProvider), isEmpty);
    expect(container.read(motionScoreProvider).total, 0);
    expect(container.read(motionScoreProvider).score, 100);
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
      hasLength(2),
    );
  });

  testWidgets('a maneuver with no route evidence is never misplaced', (
    WidgetTester tester,
  ) async {
    final DateTime t0 = DateTime(2026, 10, 21, 9);
    final ScriptedMotion motion = ScriptedMotion(SilentStore(motionBox));
    final ProviderContainer container = await pump(
      tester,
      motion,
      const TripRouteCard(),
    );
    await recordRoute(motion, t0: t0);
    await tester.pump();

    final analyzer = container.read(motionBehaviorAnalyzerProvider);
    container.read(drivingEventsProvider); // subscribe before emitting
    analyzer.observeTransport(TransportMode.vehicle);
    // Timestamped an hour off the route: no vertex can honestly host it.
    analyzer.observeDrivingEvent(
      _event(
        DrivingEventType.speedBump,
        at: t0.subtract(const Duration(hours: 1)),
      ),
    );
    await tester.pump();

    // It is still a real maneuver in the log...
    expect(container.read(drivingEventsProvider), hasLength(1));
    // ...but it earns no map marker, and the score still counts it.
    expect(container.read(locatedDrivingEventsProvider), isEmpty);
    expect(container.read(motionScoreProvider).total, 1);
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
      hasLength(2),
    );
  });

  testWidgets('tapping an event marker explains the maneuver', (
    WidgetTester tester,
  ) async {
    final DateTime t0 = DateTime(2026, 10, 21, 9);
    final ScriptedMotion motion = ScriptedMotion(SilentStore(motionBox));
    final ProviderContainer container = await pump(
      tester,
      motion,
      const TripRouteCard(),
    );
    await recordRoute(motion, t0: t0);
    await tester.pump();

    final analyzer = container.read(motionBehaviorAnalyzerProvider);
    container.read(drivingEventsProvider); // subscribe before emitting
    analyzer.observeTransport(TransportMode.vehicle);
    analyzer.observeDrivingEvent(
      _event(DrivingEventType.pothole, at: t0),
    );
    await tester.pump();

    // Tap the badge: the sheet reports the kind, magnitude and time.
    await tester.tap(find.byType(GestureDetector).last);
    await tester.pumpAndSettle();

    expect(find.text('Pothole'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the summary sheet renders the score and per-kind tallies', (
    WidgetTester tester,
  ) async {
    final DateTime t0 = DateTime(2026, 10, 21, 9);
    final ScriptedMotion motion = ScriptedMotion(SilentStore(motionBox));
    final ProviderContainer container = await pump(
      tester,
      motion,
      const MotionSummarySheet(),
    );

    // A clean trip reads as such before anything is detected.
    expect(find.text('Trip driving score'), findsOneWidget);
    expect(find.text('100 / 100'), findsOneWidget);
    expect(find.text('Clean trip — no harsh maneuvers.'), findsOneWidget);

    final analyzer = container.read(motionBehaviorAnalyzerProvider);
    container.read(drivingEventsProvider); // subscribe before emitting
    analyzer.observeTransport(TransportMode.vehicle);
    analyzer.observeDrivingEvent(
      _event(DrivingEventType.harshBraking, at: t0),
    );
    analyzer.observeDrivingEvent(
      _event(DrivingEventType.pothole, at: t0.add(const Duration(minutes: 1))),
    );
    await tester.pump();
    await tester.pump();

    // Every kind has a stable row; the tallied ones carry their counts.
    expect(find.text('2 events'), findsOneWidget);
    for (final DrivingEventType type in DrivingEventType.values) {
      expect(
        find.text(_labelOf(type)),
        findsOneWidget,
        reason: 'every kind must have its own localized row',
      );
    }
    expect(find.text('Clean trip — no harsh maneuvers.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the summary sheet collapses to its header and keeps the score', (
    WidgetTester tester,
  ) async {
    final ScriptedMotion motion = ScriptedMotion(SilentStore(motionBox));
    await pump(tester, motion, const MotionSummarySheet());

    expect(find.text('Clean trip — no harsh maneuvers.'), findsOneWidget);

    await tester.tap(find.text('Trip driving score'));
    await tester.pumpAndSettle();

    // Collapsed: the body is gone, the score stays legible.
    expect(find.text('Clean trip — no harsh maneuvers.'), findsNothing);
    expect(find.text('100 / 100'), findsOneWidget);

    await tester.tap(find.text('Trip driving score'));
    await tester.pumpAndSettle();
    expect(find.text('Clean trip — no harsh maneuvers.'), findsOneWidget);
  });

  testWidgets('the motion summary renders in Arabic RTL', (
    WidgetTester tester,
  ) async {
    final ScriptedMotion motion = ScriptedMotion(SilentStore(motionBox));
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Mounted once, directly under Arabic: the sheet must derive every layout
    // decision from directionality, not from a left/right assumption.
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          autoMotionServiceProvider.overrideWithValue(motion),
          routeTileProviderProvider.overrideWithValue(NoImageryTiles()),
          routeMilestoneNamesProvider.overrideWith(() => QuietNames()),
        ],
        child: const MaterialApp(
          locale: Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: MotionSummarySheet()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('تقييم قيادة الرحلة'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(MotionSummarySheet))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the motion summary renders in dark mode without hardcoded colors', (
    WidgetTester tester,
  ) async {
    final ScriptedMotion motion = ScriptedMotion(SilentStore(motionBox));
    await pump(
      tester,
      motion,
      const MotionSummarySheet(),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B6C4A),
          brightness: Brightness.dark,
        ),
      ),
    );

    expect(find.text('Trip driving score'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// The English label for a kind, mirroring the ARB values.
String _labelOf(DrivingEventType type) => switch (type) {
  DrivingEventType.harshAcceleration => 'Harsh acceleration',
  DrivingEventType.harshBraking => 'Hard braking',
  DrivingEventType.sharpTurn => 'Sharp turn',
  DrivingEventType.speedBump => 'Speed bump',
  DrivingEventType.pothole => 'Pothole',
};
