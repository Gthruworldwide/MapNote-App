import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/core/theme/app_theme.dart';
import 'package:routenote/src/data/models/daily_gps_summary.dart';
import 'package:routenote/src/data/models/track_point.dart';
import 'package:routenote/src/data/models/trip_segment.dart';
import 'package:routenote/src/features/automotion/route_history_screen.dart';
import 'package:routenote/src/features/automotion/widgets/drive_segment_card.dart';
import 'package:routenote/src/features/automotion/widgets/run_segment_card.dart';
import 'package:routenote/src/features/automotion/widgets/stopover_card.dart';
import 'package:routenote/src/features/automotion/widgets/walk_segment_card.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/geocoding_service.dart';
import 'package:routenote/src/services/milestone_name_resolver.dart';
import 'package:routenote/src/services/route_milestones.dart';

import 'helpers/route_preview_harness.dart';

const double _metresPerDegreeLat = 111_320;
final DateTime _morning = DateTime(2026, 10, 20, 8);

TrackPoint _point({
  required DateTime at,
  required double latitude,
  required double speedMps,
  String activity = '',
  int? steps,
}) => TrackPoint(
  latitude: latitude,
  longitude: 31.2357,
  timestamp: at,
  speed: speedMps,
  hasSpeed: true,
  accuracy: 5,
  detectedActivity: activity,
  steps: steps,
);

List<TrackPoint> _track({
  required DateTime start,
  required int seconds,
  required double speedMps,
  double latitude = 30.0444,
}) => <TrackPoint>[
  for (int offset = 0; offset <= seconds; offset += 5)
    _point(
      at: start.add(Duration(seconds: offset)),
      latitude: latitude + (speedMps * offset) / _metresPerDegreeLat,
      speedMps: speedMps,
    ),
];

/// A day shaped like the feature's headline case: a drive, a five-minute
/// stopover and a **measured** walk.
///
/// The walk carries 8 steps per 5 s fix (96 steps/min) because the classifier
/// only labels a fix on foot when the pedometer counted steps for it. Without
/// them the same GPS trace would be a stopover, not a walk.
List<TrackPoint> _day() {
  final double driveEnd = 30.0444 + (20 * 300) / _metresPerDegreeLat;
  return <TrackPoint>[
    ..._track(start: _morning, seconds: 300, speedMps: 20),
    for (int offset = 0; offset <= 300; offset += 5)
      _point(
        at: _morning.add(Duration(seconds: 305 + offset)),
        latitude: driveEnd,
        speedMps: 0,
        activity: TrackPoint.still,
      ),
    for (int offset = 0; offset <= 240; offset += 5)
      _point(
        at: _morning.add(Duration(seconds: 610 + offset)),
        latitude: driveEnd + (1.4 * offset) / _metresPerDegreeLat,
        speedMps: 1.4,
        steps: offset == 0 ? null : 8,
      ),
  ];
}

/// A day with a drive and a **measured** run: 14 steps per 5 s fix (168 steps
/// per minute) at 3 m/s. Speed alone cannot separate a run from a brisk walk —
/// only the pedometer's cadence can.
List<TrackPoint> _runDay() {
  final double driveEnd = 30.0444 + (20 * 300) / _metresPerDegreeLat;
  return <TrackPoint>[
    ..._track(start: _morning, seconds: 300, speedMps: 20),
    for (int offset = 0; offset <= 240; offset += 5)
      _point(
        at: _morning.add(Duration(seconds: 305 + offset)),
        latitude: driveEnd + (3 * offset) / _metresPerDegreeLat,
        speedMps: 3,
        steps: offset == 0 ? null : 14,
      ),
  ];
}

/// A geocoder that answers with [area] as the neighbourhood and records every
/// call. The stopover-name path is the only network-shaped dependency in this
/// screen, so tests script it instead of touching the platform geocoder.
GeocodingService _geocoder({
  String? area,
  List<List<double>>? calls,
  bool throwing = false,
}) => GeocodingService(
  placemarkLookup: (double latitude, double longitude) async {
    calls?.add(<double>[latitude, longitude]);
    if (throwing) throw const _GeocoderFailure();
    return <Placemark>[
      if (area != null) Placemark(subLocality: area),
    ];
  },
);

class _GeocoderFailure implements Exception {
  const _GeocoderFailure();
}

void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required List<TrackPoint> points,
    ThemeData? theme,
    String? stopoverArea,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final GeocodingService geocoding = _geocoder(area: stopoverArea);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        rawDailyTrackPointsProvider.overrideWithValue(points),
        // The day is built from synthetic fixes, so there is no persisted
        // record to fall back to — and therefore no Hive box to open.
        dailyGpsRecordForDayProvider.overrideWith(
          (Ref ref, DateTime day) => null,
        ),
        routeTileProviderProvider.overrideWithValue(NoImageryTiles()),
        geocodingServiceProvider.overrideWithValue(geocoding),
        milestoneNameResolverProvider.overrideWithValue(
          MilestoneNameResolver(geocoding: geocoding, lookupGap: Duration.zero),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const RouteHistoryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('RouteHistoryScreen — timeline', () {
    testWidgets('renders the day as drive, stopover and walk cards', (
      WidgetTester tester,
    ) async {
      await pump(tester, points: _day());

      expect(find.text('Motion history'), findsOneWidget);
      expect(find.byType(DriveSegmentCard), findsOneWidget);
      expect(find.byType(StopoverCard), findsOneWidget);
      expect(find.byType(WalkSegmentCard), findsOneWidget);

      // Quick stats: 6 km driven + 288 m walked (384 measured steps at the
      // 0.75 m walking stride), plus the two five-minute stretches (drive time
      // and idle time).
      expect(find.text('6.28 km'), findsOneWidget);
      expect(find.text('5 min'), findsNWidgets(2));
      expect(find.text('Stopped for 5 min'), findsOneWidget);

      // The mode breakdown follows the day: it drove and it walked, it never
      // ran — so no Run row and no Run card can be rendered.
      expect(find.text('Vehicle'), findsOneWidget);
      expect(find.text('Walk'), findsNWidgets(2)); // card title + stat label
      expect(find.text('Run'), findsNothing);
      // The step total is a measurement, shown once in the breakdown.
      expect(find.text('Steps'), findsOneWidget);
      expect(find.text('384'), findsOneWidget);
      expect(find.text('288 m · 384 steps'), findsOneWidget);
    });

    testWidgets('a measured run renders as a run and only as a run', (
      WidgetTester tester,
    ) async {
      await pump(tester, points: _runDay());

      expect(find.byType(DriveSegmentCard), findsOneWidget);
      expect(find.byType(RunSegmentCard), findsOneWidget);
      // 10.8 km/h says nothing about gait; only the measured cadence can tell a
      // run from a brisk walk, so nothing may render as one.
      expect(find.byType(WalkSegmentCard), findsNothing);
      expect(find.byType(StopoverCard), findsNothing);

      // The mode breakdown lists the categories the day actually used.
      expect(find.text('Vehicle'), findsOneWidget);
      // "Run" is the card title and the breakdown label: one vocabulary.
      expect(find.text('Run'), findsNWidgets(2));
      expect(find.text('Walk'), findsNothing);

      // The first couple of fixes of the run are the cadence window warming up
      // (a trailing window needs a few increments before it can reach the run
      // threshold), so they are absorbed into the drive. What remains is 644
      // measured steps at the 0.95 m running stride = 611.8 m, never the 720 m
      // of GPS polyline a speed-only reading would have produced.
      expect(find.text('612 m · 644 steps'), findsOneWidget);
      expect(find.text('0.61 km'), findsOneWidget);
    });

    testWidgets('renders in dark mode without losing any segment', (
      WidgetTester tester,
    ) async {
      await pump(tester, points: _day(), theme: AppTheme.dark());

      expect(find.byType(DriveSegmentCard), findsOneWidget);
      expect(find.byType(StopoverCard), findsOneWidget);
      expect(find.byType(WalkSegmentCard), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(RouteHistoryScreen))).brightness,
        Brightness.dark,
      );
    });

    testWidgets('an empty day explains itself instead of showing a blank list',
        (WidgetTester tester) async {
      await pump(tester, points: const <TrackPoint>[]);

      expect(find.text('No motion recorded'), findsOneWidget);
      expect(find.byType(DriveSegmentCard), findsNothing);
      expect(find.text('0.00 km'), findsOneWidget);
    });

    testWidgets('a resolved place name names the stopover card', (
      WidgetTester tester,
    ) async {
      await pump(tester, points: _day(), stopoverArea: 'Zamalek');

      expect(find.text('Zamalek'), findsOneWidget);
      expect(find.text('Stopover'), findsNothing);
      // The name is an extra label, never a replacement for the facts.
      expect(find.text('Stopped for 5 min'), findsOneWidget);
    });
  });

  group('RouteHistoryScreen — date header', () {
    testWidgets('starts on today with the forward arrow disabled', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pump(tester, points: _day());

      expect(find.text('Today'), findsOneWidget);
      final IconButton next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      expect(next.onPressed, isNull);
      expect(
        container.read(selectedDateProvider),
        DailyGpsSummary.dayOf(DateTime.now()),
      );
    });

    testWidgets('stepping back a day shows yesterday and re-enables forward', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pump(tester, points: _day());

      await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_left));
      await tester.pumpAndSettle();

      expect(find.text('Yesterday'), findsOneWidget);
      final IconButton next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      expect(next.onPressed, isNotNull);

      final DateTime selected = container.read(selectedDateProvider);
      final DateTime today = DailyGpsSummary.dayOf(DateTime.now());
      expect(today.difference(selected).inDays, 1);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
    });
  });

  group('RouteHistoryScreen — map view', () {
    testWidgets('the toggle swaps the timeline for the colour-coded map', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pump(tester, points: _day());

      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();

      expect(container.read(motionHistoryViewModeProvider),
          MotionHistoryViewMode.map);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(DriveSegmentCard), findsNothing);

      // The legend names every motion kind the map can draw. Scoped to the map
      // itself, because the quick-stats breakdown above it names the same modes.
      Finder legend(String label) => find.descendant(
            of: find.byType(FlutterMap),
            matching: find.text(label),
          );
      expect(legend('Drive'), findsOneWidget);
      expect(legend('Walk'), findsOneWidget);
      expect(legend('Run'), findsOneWidget);
      expect(legend('Stopover'), findsOneWidget);

      // The stopover is pinned rather than drawn as a line.
      expect(
        find.byType(MarkerLayer),
        findsOneWidget,
      );

      await tester.tap(find.text('Timeline'));
      await tester.pumpAndSettle();
      expect(find.byType(FlutterMap), findsNothing);
      expect(find.byType(DriveSegmentCard), findsOneWidget);
    });

    testWidgets('an empty day shows the no-route message on the map', (
      WidgetTester tester,
    ) async {
      await pump(tester, points: const <TrackPoint>[]);

      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();

      expect(find.byType(FlutterMap), findsNothing);
      expect(find.text('No route to draw for this day.'), findsOneWidget);
    });
  });

  group('stopoverNamesProvider', () {
    /// A container whose motion history is [points] and whose geocoder is
    /// scripted, so no platform channel is touched.
    ProviderContainer containerFor(
      List<TrackPoint> points, {
      required GeocodingService geocoding,
      required MilestoneNameResolver resolver,
    }) {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          rawDailyTrackPointsProvider.overrideWithValue(points),
          dailyGpsRecordForDayProvider.overrideWith(
            (Ref ref, DateTime day) => null,
          ),
          geocodingServiceProvider.overrideWithValue(geocoding),
          milestoneNameResolverProvider.overrideWithValue(resolver),
        ],
      );
      addTearDown(container.dispose);
      // Keep the notifier alive for the whole test: it kicks off the lookups.
      container.listen(stopoverNamesProvider, (_, _) {});
      return container;
    }

    /// The single parked segment of [_day()], plus its centroid — exactly the
    /// coordinate the map pins and the resolver is asked about.
    ({TripSegment segment, RouteMilestone milestone}) stopoverOf(
      ProviderContainer container,
    ) {
      final TripSegment stop = container
          .read(motionHistoryProvider)
          .firstWhere((TripSegment s) => s.type == MotionType.stationary);
      double sumLat = 0;
      double sumLon = 0;
      for (final TrackPoint point in stop.points) {
        sumLat += point.latitude;
        sumLon += point.longitude;
      }
      return (
        segment: stop,
        milestone: RouteMilestone(
          kind: RouteMilestoneKind.stop,
          at: stop.startTime,
          latitude: sumLat / stop.points.length,
          longitude: sumLon / stop.points.length,
        ),
      );
    }

    test('a resolved stop is named by its start time, geocoded once', () async {
      final List<List<double>> calls = <List<double>>[];
      final GeocodingService geocoding = _geocoder(
        area: 'Zamalek',
        calls: calls,
      );
      final MilestoneNameResolver resolver = MilestoneNameResolver(
        geocoding: geocoding,
        lookupGap: Duration.zero,
      );
      final ProviderContainer container = containerFor(
        _day(),
        geocoding: geocoding,
        resolver: resolver,
      );

      final ({TripSegment segment, RouteMilestone milestone}) stop =
          stopoverOf(container);
      // Nothing is cached yet, so the card renders the generic label.
      expect(container.read(stopoverNamesProvider), isEmpty);

      // The notifier and the route card share one resolver: resolving the
      // milestone by hand must be all it takes for the stop to get its name…
      await resolver.resolve(<RouteMilestone>[stop.milestone]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // …keyed by start time, with exactly one platform call for the day.
      expect(
        container.read(stopoverNamesProvider)[stop.segment.startTime],
        'Zamalek',
      );
      expect(calls, hasLength(1));
      expect(calls.single[0], closeTo(stop.milestone.latitude, 1e-9));
      expect(calls.single[1], closeTo(stop.milestone.longitude, 1e-9));
    });

    test('a failing geocoder degrades to the label, never to an error', () async {
      final GeocodingService geocoding = _geocoder(throwing: true);
      final ProviderContainer container = containerFor(
        _day(),
        geocoding: geocoding,
        resolver: MilestoneNameResolver(
          geocoding: geocoding,
          lookupGap: Duration.zero,
        ),
      );

      expect(container.read(stopoverNamesProvider), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // The miss is negatively cached (so a rebuild loop never hammers the
      // platform geocoder) — the value is simply `null`, never an error.
      expect(
        container.read(stopoverNamesProvider).values,
        everyElement(isNull),
      );
    });

    test('a day with nothing parked never asks the geocoder', () async {
      final List<List<double>> calls = <List<double>>[];
      final GeocodingService geocoding = _geocoder(calls: calls);
      final ProviderContainer container = containerFor(
        _track(start: _morning, seconds: 300, speedMps: 20),
        geocoding: geocoding,
        resolver: MilestoneNameResolver(
          geocoding: geocoding,
          lookupGap: Duration.zero,
        ),
      );

      expect(container.read(stopoverNamesProvider), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, isEmpty);
    });
  });
}
