import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:latlong2/latlong.dart';

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/features/automotion/widgets/route_map_view.dart';
import 'package:routenote/src/features/automotion/widgets/route_timeline.dart';
import 'package:routenote/src/features/automotion/widgets/trip_path_painter.dart';
import 'package:routenote/src/features/automotion/widgets/trip_route_card.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/polyline_smoother.dart';
import 'package:routenote/src/services/route_milestones.dart';

import 'helpers/route_preview_harness.dart';

/// The OSM tile contract of the route map — the new network dependency, pinned
/// here so any change has to be a deliberate one.
const String _osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String _attribution = '© OpenStreetMap contributors';

bool _hasTripPainter(WidgetTester tester) => find
    .byWidgetPredicate(
      (Widget widget) =>
          widget is CustomPaint && widget.painter is TripPathPainter,
    )
    .evaluate()
    .isNotEmpty;

void main() {
  late Directory tempDir;
  late Box motionBox;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mapnote_route_preview');
    Hive.init(tempDir.path);
    motionBox = await Hive.openBox<dynamic>('auto_motion_test_preview');
  });

  tearDown(() async {
    await motionBox.close();
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true).catchError((_) => tempDir);
  });

  /// Mounts a bare [TripRouteCard] with the network-free overrides and returns
  /// the container for camera / provider assertions. [tiles] replaces the
  /// default no-imagery provider for the offline-fallback scenario — passed
  /// here rather than via [extraOverrides] because a container may override
  /// one provider only once.
  Future<ProviderContainer> pump(
    WidgetTester tester,
    ScriptedMotion motion, {
    List<Override> extraOverrides = const <Override>[],
    TileProvider? tiles,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          autoMotionServiceProvider.overrideWithValue(motion),
          routeTileProviderProvider.overrideWithValue(
            tiles ?? NoImageryTiles(),
          ),
          routeMilestoneNamesProvider.overrideWith(() => QuietNames()),
          ...extraOverrides,
        ],
        child: MaterialApp(
          theme: theme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: TripRouteCard(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return ProviderScope.containerOf(
      tester.element(find.byType(TripRouteCard)),
    );
  }

  /// Records the same three-fix straight route the dashboard tests use and
  /// lets the card rebuild.
  Future<void> recordRoute(ScriptedMotion motion) async {
    motion.recordPosition(fix(0, 0, speed: 8));
    motion.recordPosition(fix(0.009, 0.001, speed: 12));
    motion.recordPosition(fix(0.018, -0.001, speed: 15));
  }

  testWidgets('renders the OpenStreetMap tile view over the offline grid', (
    WidgetTester tester,
  ) async {
    final ScriptedMotion motion = ScriptedMotion(SilentStore(motionBox));
    await pump(tester, motion);
    await recordRoute(motion);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(FlutterMap), findsOneWidget);

    // The tile layer is wired to OSM with the injected (network-free) provider
    // — never the default network client — and `TileLayer` folds the app's
    // package name into the User-Agent header (OSM tile-use etiquette).
    final TileLayer tiles = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(tiles.urlTemplate, _osmUrl);
    expect(tiles.tileProvider, isA<NoImageryTiles>());
    expect(
      tiles.tileProvider.headers['User-Agent'],
      contains('com.routenote.routenote'),
    );

    // The route itself is drawn by pure widget layers — it renders with zero
    // tiles loaded (halo + core stroke, mirroring the offline painter).
    final PolylineLayer polylines = tester.widget<PolylineLayer>(
      find.byType(PolylineLayer),
    );
    expect(polylines.polylines, hasLength(2));
    expect(polylines.polylines.first.points.length, greaterThanOrEqualTo(3));

    // Start (primary) and end (error) pins — no dwell stops recorded.
    final MarkerLayer markers = tester.widget<MarkerLayer>(
      find.byType(MarkerLayer),
    );
    expect(markers.markers, hasLength(2));

    // OSM attribution stays visible.
    expect(find.text(_attribution), findsOneWidget);

    // The offline grid is mounted UNDER the map and the map background is
    // transparent — that combination is what makes tiles-never-load degrade
    // to the grid view instead of a blank box.
    final Stack stack = tester.widget<Stack>(
      find
          .ancestor(of: find.byType(RouteMapView), matching: find.byType(Stack))
          .first,
    );
    final int painterIndex = stack.children.indexWhere(
      (Widget w) => w is RepaintBoundary,
    );
    final int mapIndex = stack.children.indexWhere(
      (Widget w) => w is RouteMapView,
    );
    expect(painterIndex, greaterThanOrEqualTo(0));
    expect(mapIndex, greaterThan(painterIndex));
    final CustomPaint grid = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byWidget(stack.children[painterIndex]),
        matching: find.byType(CustomPaint),
      ),
    );
    expect((grid.painter! as TripPathPainter).routeVisible, isFalse);

    final FlutterMap map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.options.backgroundColor, Colors.transparent);
  });

  testWidgets('auto-fits the camera around the whole recorded route', (
    WidgetTester tester,
  ) async {
    final ScriptedMotion motion = ScriptedMotion(SilentStore(motionBox));
    final ProviderContainer container = await pump(tester, motion);
    await recordRoute(motion);
    await tester.pump();
    await tester.pump();

    final List<RoutePoint> path = container
        .read(autoMotionServiceProvider)
        .smoothedPath;
    expect(path, isNotEmpty);

    final MapCamera camera = container.read(routeMapControllerProvider).camera;
    for (final RoutePoint point in path) {
      expect(
        camera.visibleBounds.contains(LatLng(point.latitude, point.longitude)),
        isTrue,
        reason:
            'route point (${point.latitude}, ${point.longitude}) left the '
            'fitted camera',
      );
    }
  });

  testWidgets('offline fallback: grid and route render when tiles never '
      'arrive', (WidgetTester tester) async {
    final ScriptedMotion motion = ScriptedMotion(SilentStore(motionBox));
    await pump(tester, motion, tiles: NeverLoadingTiles());
    await recordRoute(motion);
    await tester.pump();
    await tester.pump();

    // Airplane mode: not a single tile ever resolves. The card still shows the
    // tinted grid, the map's route layers, the milestones timeline and the
    // attribution — and raises nothing.
    expect(tester.takeException(), isNull);
    expect(_hasTripPainter(tester), isTrue);
    expect(find.byType(FlutterMap), findsOneWidget);
    final PolylineLayer polylines = tester.widget<PolylineLayer>(
      find.byType(PolylineLayer),
    );
    expect(polylines.polylines.first.points, isNotEmpty);
    expect(find.byType(RouteTimeline), findsOneWidget);
    expect(find.text(_attribution), findsOneWidget);
  });

  testWidgets('stop milestones are pinned on the map', (
    WidgetTester tester,
  ) async {
    final ScriptedMotion motion = ScriptedMotion(SilentStore(motionBox));
    await pump(
      tester,
      motion,
      extraOverrides: <Override>[
        routeMilestonesProvider.overrideWithValue(<RouteMilestone>[
          RouteMilestone(
            kind: RouteMilestoneKind.tripStart,
            at: DateTime(2026, 10, 19, 8),
            latitude: 0,
            longitude: 0,
          ),
          RouteMilestone(
            kind: RouteMilestoneKind.stop,
            at: DateTime(2026, 10, 19, 8, 30),
            latitude: 30.31,
            longitude: 31.18,
          ),
          RouteMilestone(
            kind: RouteMilestoneKind.tripEnd,
            at: DateTime(2026, 10, 19, 9),
            latitude: 0.018,
            longitude: -0.001,
          ),
        ]),
      ],
    );
    await recordRoute(motion);
    await tester.pump();
    await tester.pump();

    final MarkerLayer markers = tester.widget<MarkerLayer>(
      find.byType(MarkerLayer),
    );
    expect(markers.markers, hasLength(3));
    expect(
      markers.markers.map((Marker m) => m.point.latitude),
      contains(30.31),
    );
  });

  testWidgets('an empty route shows the empty state with no map mounted', (
    WidgetTester tester,
  ) async {
    final ScriptedMotion motion = ScriptedMotion(SilentStore(motionBox));
    await pump(tester, motion);

    expect(tester.takeException(), isNull);
    expect(find.byType(FlutterMap), findsNothing);
    expect(_hasTripPainter(tester), isFalse);
    expect(find.byType(RouteTimeline), findsNothing);
    expect(
      find.text(
        'No route recorded yet — turn on tracking and drive or walk to see it '
        'drawn here.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders the tile view and timeline in dark mode', (
    WidgetTester tester,
  ) async {
    final ScriptedMotion motion = ScriptedMotion(SilentStore(motionBox));
    await pump(tester, motion, theme: ThemeData.dark());
    await recordRoute(motion);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text(_attribution), findsOneWidget);
    expect(find.byType(RouteTimeline), findsOneWidget);
  });
}
