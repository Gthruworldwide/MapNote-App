import 'package:fake_async/fake_async.dart'; // ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';

import 'package:routenote/src/services/geocoding_service.dart';
import 'package:routenote/src/services/milestone_name_resolver.dart';
import 'package:routenote/src/services/route_milestones.dart';

/// A stop at [latitude]/[longitude], unless overridden.
RouteMilestone _milestone({
  double latitude = 30.0,
  double longitude = 31.0,
  RouteMilestoneKind kind = RouteMilestoneKind.stop,
  DateTime? at,
}) => RouteMilestone(
  kind: kind,
  at: at ?? DateTime(2026, 10, 19, 8, 15),
  latitude: latitude,
  longitude: longitude,
);

/// A [GeocodingService] whose reverse lookup is [lookup] with every call
/// recorded in [calls] as `[latitude, longitude]`.
GeocodingService _service(
  Future<List<Placemark>> Function(double lat, double lon) lookup, {
  required List<List<double>> calls,
}) => GeocodingService(
  placemarkLookup: (double lat, double lon) {
    calls.add(<double>[lat, lon]);
    return lookup(lat, lon);
  },
);

void main() {
  group('MilestoneNameResolver.labelFor', () {
    test('prefers neighbourhood over city and governorate', () {
      final PlaceSuggestion suggestion = PlaceSuggestion(
        subLocality: 'Sheikh Zayed',
        locality: 'Giza',
        administrativeArea: 'Giza Governorate',
        country: 'Egypt',
      );
      expect(MilestoneNameResolver.labelFor(suggestion), 'Sheikh Zayed');
    });

    test('falls back to city, then governorate', () {
      expect(
        MilestoneNameResolver.labelFor(
          PlaceSuggestion(
            locality: 'Giza',
            administrativeArea: 'Giza Governorate',
          ),
        ),
        'Giza',
      );
      expect(
        MilestoneNameResolver.labelFor(
          PlaceSuggestion(administrativeArea: 'Giza Governorate'),
        ),
        'Giza Governorate',
      );
    });

    test('uses the venue name when no area is known', () {
      expect(
        MilestoneNameResolver.labelFor(
          const PlaceSuggestion(name: 'Cairo Tower'),
        ),
        'Cairo Tower',
      );
    });

    test('skips coordinate echoes from the platform geocoder', () {
      // Android's Geocoder returns the raw coordinates as the feature name
      // when it has nothing better — that must never surface as a label.
      expect(
        MilestoneNameResolver.labelFor(
          const PlaceSuggestion(
            name: '30.0444, 31.2357',
            administrativeArea: 'Cairo Governorate',
          ),
        ),
        'Cairo Governorate',
      );
      expect(
        MilestoneNameResolver.labelFor(
          const PlaceSuggestion(name: '30.0444,31.2357'),
        ),
        isNull,
      );
    });

    test('trims whitespace around the chosen label', () {
      expect(
        MilestoneNameResolver.labelFor(
          const PlaceSuggestion(subLocality: '  Zamalek  '),
        ),
        'Zamalek',
      );
    });

    test('an empty suggestion resolves to no name', () {
      expect(MilestoneNameResolver.labelFor(const PlaceSuggestion()), isNull);
    });
  });

  group('MilestoneNameResolver.resolve / cached', () {
    test('resolves a name and serves it from the cache afterwards', () async {
      final List<List<double>> calls = <List<double>>[];
      final MilestoneNameResolver resolver = MilestoneNameResolver(
        geocoding: _service(
          (_, _) async => <Placemark>[const Placemark(subLocality: 'Zamalek')],
          calls: calls,
        ),
        lookupGap: Duration.zero,
      );
      final RouteMilestone m = _milestone();

      await resolver.resolve(<RouteMilestone>[m]);
      expect(resolver.cached(<RouteMilestone>[m])[m.coordinateKey], 'Zamalek');
      expect(calls, hasLength(1));

      // Second time round: cache hit, no platform call.
      await resolver.resolve(<RouteMilestone>[m]);
      expect(calls, hasLength(1));
    });

    test('distinct coordinates are looked up separately', () async {
      final List<List<double>> calls = <List<double>>[];
      final MilestoneNameResolver resolver = MilestoneNameResolver(
        geocoding: _service(
          (double lat, _) async => <Placemark>[
            Placemark(subLocality: lat == 30.0 ? 'Zamalek' : 'Giza'),
          ],
          calls: calls,
        ),
        lookupGap: Duration.zero,
      );
      final RouteMilestone zamalek = _milestone(latitude: 30.0);
      final RouteMilestone giza = _milestone(
        latitude: 30.5,
        longitude: 31.2,
      );

      await resolver.resolve(<RouteMilestone>[zamalek, giza]);
      final Map<String, String?> names = resolver.cached(<RouteMilestone>[
        zamalek,
        giza,
      ]);
      expect(names[zamalek.coordinateKey], 'Zamalek');
      expect(names[giza.coordinateKey], 'Giza');
      expect(calls, hasLength(2));
    });

    test('a miss is negative-cached until the retry window passes', () async {
      final List<List<double>> calls = <List<double>>[];
      DateTime now = DateTime(2026, 10, 19, 8);
      final MilestoneNameResolver resolver = MilestoneNameResolver(
        geocoding: _service((_, _) async => <Placemark>[], calls: calls),
        now: () => now,
        lookupGap: Duration.zero,
      );
      final RouteMilestone m = _milestone();

      await resolver.resolve(<RouteMilestone>[m]);
      expect(resolver.cached(<RouteMilestone>[m]), contains(m.coordinateKey));
      expect(resolver.cached(<RouteMilestone>[m])[m.coordinateKey], isNull);
      expect(calls, hasLength(1));

      // Still inside the five-minute window: no repeat call.
      now = now.add(const Duration(minutes: 4));
      await resolver.resolve(<RouteMilestone>[m]);
      expect(calls, hasLength(1));

      // Window passed: the geocoder gets one more chance.
      now = now.add(const Duration(minutes: 2));
      await resolver.resolve(<RouteMilestone>[m]);
      expect(calls, hasLength(2));
    });

    test('a thrown lookup resolves to null instead of an exception', () async {
      final List<List<double>> calls = <List<double>>[];
      final MilestoneNameResolver resolver = MilestoneNameResolver(
        geocoding: _service(
          (_, _) async => throw StateError('geocoder offline'),
          calls: calls,
        ),
        lookupGap: Duration.zero,
      );
      final RouteMilestone m = _milestone();

      await resolver.resolve(<RouteMilestone>[m]);
      expect(resolver.cached(<RouteMilestone>[m])[m.coordinateKey], isNull);
      expect(calls, hasLength(1));
    });

    test('concurrent resolves share a single platform call', () async {
      final List<List<double>> calls = <List<double>>[];
      final MilestoneNameResolver resolver = MilestoneNameResolver(
        geocoding: _service(
          (_, _) async => <Placemark>[const Placemark(locality: 'Giza')],
          calls: calls,
        ),
        lookupGap: Duration.zero,
      );
      final RouteMilestone m = _milestone();

      await Future.wait(<Future<void>>[
        resolver.resolve(<RouteMilestone>[m]),
        resolver.resolve(<RouteMilestone>[m]),
      ]);
      expect(calls, hasLength(1));
      expect(resolver.cached(<RouteMilestone>[m])[m.coordinateKey], 'Giza');
    });

    test('start and stop at the same coordinate share one lookup', () async {
      final List<List<double>> calls = <List<double>>[];
      final MilestoneNameResolver resolver = MilestoneNameResolver(
        geocoding: _service(
          (_, _) async => <Placemark>[const Placemark(locality: 'Giza')],
          calls: calls,
        ),
        lookupGap: Duration.zero,
      );
      final RouteMilestone start = _milestone(
        latitude: 30.0,
        longitude: 31.0,
        kind: RouteMilestoneKind.tripStart,
      );
      final RouteMilestone stop = _milestone(latitude: 30.0, longitude: 31.0);

      await resolver.resolve(<RouteMilestone>[start, stop]);
      expect(calls, hasLength(1));
      final Map<String, String?> names = resolver.cached(<RouteMilestone>[
        start,
        stop,
      ]);
      expect(names, hasLength(1));
      expect(names.values.single, 'Giza');
    });
  });

  group('MilestoneNameResolver lookup pacing', () {
    test('serialises lookups with the configured gap', () {
      fakeAsync((FakeAsync async) {
        final List<List<double>> calls = <List<double>>[];
        final MilestoneNameResolver resolver = MilestoneNameResolver(
          geocoding: _service(
            (_, _) async => <Placemark>[const Placemark(locality: 'Giza')],
            calls: calls,
          ),
          lookupGap: const Duration(milliseconds: 300),
        );

        final Future<void> done = resolver.resolve(<RouteMilestone>[
          _milestone(latitude: 30.0),
          _milestone(latitude: 31.5),
        ]);
        // Tracked with a flag instead of `expect(done, completes)`: the async
        // matcher would park an expectation inside the fake zone, which
        // nothing flushes after `fakeAsync` returns — hanging the test.
        bool completed = false;
        done.whenComplete(() => completed = true);

        // The first lookup waits out its gap before touching the geocoder.
        async.flushMicrotasks();
        expect(calls, isEmpty);

        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();
        expect(calls, hasLength(1));

        // The second is gated behind its own gap, not racing the first.
        async.elapse(const Duration(milliseconds: 299));
        async.flushMicrotasks();
        expect(calls, hasLength(1));

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(calls, hasLength(2));

        // Both lookups drained ⇒ `resolve` itself finished its queue.
        expect(completed, isTrue);
      });
    });
  });
}
