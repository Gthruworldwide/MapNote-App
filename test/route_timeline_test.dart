import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;
import 'package:intl/intl.dart' hide TextDirection;

import 'package:routenote/l10n/generated/app_localizations.dart';
import 'package:routenote/src/features/automotion/widgets/route_timeline.dart';
import 'package:routenote/src/providers/app_providers.dart';
import 'package:routenote/src/services/route_milestones.dart';

/// The three milestones of a short Greater-Cairo morning, with names exactly
/// as the resolver would key them.
final RouteMilestone _start = RouteMilestone(
  kind: RouteMilestoneKind.tripStart,
  at: DateTime(2026, 10, 19, 8, 15),
  latitude: 30.31,
  longitude: 31.18,
);
final RouteMilestone _stop = RouteMilestone(
  kind: RouteMilestoneKind.stop,
  at: DateTime(2026, 10, 19, 8, 45),
  latitude: 30.35,
  longitude: 31.10,
);
final RouteMilestone _end = RouteMilestone(
  kind: RouteMilestoneKind.tripEnd,
  at: DateTime(2026, 10, 19, 9, 30),
  latitude: 30.40,
  longitude: 31.05,
);
final List<RouteMilestone> _milestones = <RouteMilestone>[_start, _stop, _end];

const Map<String, String?> _names = <String, String?>{
  // Keys match `RouteMilestone.coordinateKey` (3-decimal quantisation).
  '30.310,31.180': 'Giza',
  '30.350,31.100': 'Sheikh Zayed',
  '30.400,31.050': 'Industrial Zone',
};

/// The clock format the timeline renders, derived rather than hardcoded:
/// modern intl separates the time from AM/PM with U+202F (narrow no-break
/// space), so an `'8:15 AM'` literal would never match.
String _jm(DateTime at) => DateFormat.jm('en').format(at.toLocal());

/// The timeline renders whatever this notifier hands back — no geocoder, no
/// retry timers inside the test's FakeAsync zone.
class _FixedNames extends RouteMilestoneNames {
  _FixedNames(this.names);

  final Map<String, String?> names;

  @override
  Map<String, String?> build() => names;
}

void main() {
  /// Mounts a bare [RouteTimeline] with fixed milestones and names.
  Future<void> pump(
    WidgetTester tester, {
    List<RouteMilestone>? milestones,
    Map<String, String?> names = _names,
    ThemeData? theme,
    Locale? locale,
  }) async {
    final List<RouteMilestone> rows = milestones ?? _milestones;
    // English clock symbols for the `_jm` expectations below — idempotent,
    // and makes the helper independent of delegate load order.
    await initializeDateFormatting('en');
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          routeMilestonesProvider.overrideWithValue(rows),
          routeMilestoneNamesProvider.overrideWith(() => _FixedNames(names)),
        ],
        child: MaterialApp(
          theme: theme,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: RouteTimeline(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'shows every milestone with its name, kind, exact time and date',
    (WidgetTester tester) async {
      await pump(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Route milestones'), findsOneWidget);

      // Resolved names, each paired with its kind label underneath.
      expect(find.text('Giza'), findsOneWidget);
      expect(find.text('Sheikh Zayed'), findsOneWidget);
      expect(find.text('Industrial Zone'), findsOneWidget);
      expect(find.text('Trip start'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('Trip end'), findsOneWidget);

      // Exact clock times and the full date on every row. Times are derived
      // from the same DateFormat the widget uses, and sanity-checked below so
      // a formatting regression still fails loudly.
      final String start = _jm(_start.at);
      final String stop = _jm(_stop.at);
      final String end = _jm(_end.at);
      expect(start, startsWith('8:15'));
      expect(stop, startsWith('8:45'));
      expect(end, startsWith('9:30'));
      expect(find.text(start), findsOneWidget);
      expect(find.text(stop), findsOneWidget);
      expect(find.text(end), findsOneWidget);
      expect(find.text('Oct 19, 2026'), findsNWidgets(3));

      // Rows are chronological top to bottom.
      final double t1 = tester.getTopLeft(find.text(start)).dy;
      final double t2 = tester.getTopLeft(find.text(stop)).dy;
      final double t3 = tester.getTopLeft(find.text(end)).dy;
      expect(t1, lessThan(t2));
      expect(t2, lessThan(t3));
    },
  );

  testWidgets('falls back to kind labels when no names were resolved '
      '(offline)', (WidgetTester tester) async {
    await pump(tester, names: const <String, String?>{});

    expect(tester.takeException(), isNull);
    expect(find.text('Giza'), findsNothing);
    expect(find.text('Sheikh Zayed'), findsNothing);
    expect(find.text('Industrial Zone'), findsNothing);
    // The kind label moves up into the primary slot.
    expect(find.text('Trip start'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Trip end'), findsOneWidget);
    // Times are unaffected — they come from the fixes, not the geocoder.
    final String stop = _jm(_stop.at);
    expect(stop, startsWith('8:45'));
    expect(find.text(stop), findsOneWidget);
  });

  testWidgets('a route without timed milestones shows the empty note', (
    WidgetTester tester,
  ) async {
    await pump(tester, milestones: const <RouteMilestone>[]);

    expect(tester.takeException(), isNull);
    expect(find.text('Route milestones'), findsNothing);
    expect(
      find.text(
        'No timed milestones on this route yet — timed stops appear here as '
        'the trip is recorded.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders in dark mode with theme colours', (
    WidgetTester tester,
  ) async {
    await pump(tester, theme: ThemeData.dark());

    expect(tester.takeException(), isNull);
    expect(find.text('Route milestones'), findsOneWidget);
    expect(find.text('Giza'), findsOneWidget);
    expect(find.text(_jm(_start.at)), findsOneWidget);
  });

  testWidgets('renders in Arabic (RTL) with localized chrome', (
    WidgetTester tester,
  ) async {
    // Arabic date/time symbols for `DateFormat.jm('ar')`.
    await initializeDateFormatting('ar');
    await pump(tester, locale: const Locale('ar'));

    expect(tester.takeException(), isNull);
    expect(find.text('محطات المسار'), findsOneWidget);
    // Place names are data, not chrome — they stay as the resolver returned.
    expect(find.text('Giza'), findsOneWidget);
    expect(find.text('Sheikh Zayed'), findsOneWidget);
  });
}
