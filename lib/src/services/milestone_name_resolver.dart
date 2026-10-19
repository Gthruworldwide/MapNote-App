import 'dart:async';

import 'geocoding_service.dart';
import 'route_milestones.dart';

/// Reverse-geocoded place names for [RouteMilestone]s, resolved lazily and
/// cached for the lifetime of the app session.
///
/// Design constraints:
///
///  * **Offline-first.** Every lookup goes through [GeocodingService], which
///    is best-effort by contract: a device with no network or no geocoder
///    yields `null`, never an exception. The timeline then falls back to the
///    milestone's kind label ("Trip start"), so nothing on screen breaks.
///  * **Lightweight.** Results (including misses, which are negative-cached
///    with [retryAfter] so a dashboard rebuild loop never hammers the platform
///    geocoder) live in a plain in-memory map — no Hive box, no schema change,
///    no migration risk. A fresh session simply re-asks.
///  * **Gentle.** Lookups are serialised through a single queue with a
///    [lookupGap] between platform calls, and concurrent requests for the same
///    coordinate share one in-flight future.
///
/// Tests inject a scripted [GeocodingService], a fake [now] clock, and
/// `lookupGap: Duration.zero`, so every branch is deterministic.
class MilestoneNameResolver {
  MilestoneNameResolver({
    required this.geocoding,
    this.now = DateTime.now,
    this.retryAfter = const Duration(minutes: 5),
    this.lookupGap = const Duration(milliseconds: 300),
  });

  /// The (platform) geocoder used for reverse lookups — injectable in tests.
  final GeocodingService geocoding;

  /// Clock used for negative-cache expiry — injectable in tests.
  final DateTime Function() now;

  /// How long a `null` result is trusted before the geocoder is asked again.
  final Duration retryAfter;

  /// Pause between serialised platform lookups.
  final Duration lookupGap;

  final Map<String, _NameEntry> _cache = <String, _NameEntry>{};
  final Map<String, Future<String?>> _inFlight = <String, Future<String?>>{};
  Future<void> _queue = Future<void>.value();

  /// The subset of [milestones] whose names are already known, keyed by
  /// [RouteMilestone.coordinateKey]. Unresolved keys are absent so callers can
  /// render the kind label immediately and upgrade in place when a name lands.
  Map<String, String?> cached(Iterable<RouteMilestone> milestones) =>
      <String, String?>{
        for (final RouteMilestone milestone in milestones)
          if (_cache.containsKey(milestone.coordinateKey))
            milestone.coordinateKey: _cache[milestone.coordinateKey]!.name,
      };

  /// Resolves every not-yet-known name in [milestones], awaiting the platform
  /// lookups. Never throws; repeated calls are cheap once the cache is warm.
  Future<void> resolve(Iterable<RouteMilestone> milestones) async {
    for (final RouteMilestone milestone in milestones) {
      if (!_needsLookup(milestone)) continue;
      await _lookup(milestone);
    }
  }

  /// Picks the best short area name for a milestone from a resolved
  /// [PlaceSuggestion].
  ///
  /// Milestones narrate *areas* ("Giza", "Sheikh Zayed"), so neighbourhood,
  /// city and governorate fields win in that order. The venue/feature name is
  /// used only when no area is known — and skipped when the platform geocoder
  /// merely echoed the coordinates back ("30.0444, 31.2357"), which reads
  /// worse than no name at all. Streets are deliberately ignored: "26th of
  /// July Corridor" is not where a stop happened, it is how it is reached.
  static String? labelFor(PlaceSuggestion suggestion) {
    final String? area = _firstNonEmpty(<String?>[
      suggestion.subLocality,
      suggestion.locality,
      suggestion.administrativeArea,
    ]);
    if (area != null) return area;
    final String? name = suggestion.name;
    if (name != null && !_looksLikeCoordinates(name)) return name;
    return _firstNonEmpty(<String?>[suggestion.country]);
  }

  bool _needsLookup(RouteMilestone milestone) {
    final _NameEntry? entry = _cache[milestone.coordinateKey];
    if (entry == null) return true;
    if (entry.name != null) return false;
    final DateTime? retryAt = entry.retryAt;
    return retryAt == null || !now().isBefore(retryAt);
  }

  Future<String?> _lookup(RouteMilestone milestone) {
    final String key = milestone.coordinateKey;
    final Future<String?>? pending = _inFlight[key];
    if (pending != null) return pending;
    final Future<String?> future = _enqueue(() => _reverse(milestone))
        .then((String? name) {
          _cache[key] = _NameEntry(
            name,
            retryAt: name == null ? now().add(retryAfter) : null,
          );
          return name;
        })
        .whenComplete(() {
          // Block body on purpose: `Map<String, Future<String?>>.remove`
          // hands back the stored future — which is the very future being
          // completed here — and `whenComplete` waits on a returned future,
          // which would deadlock the chain on itself.
          _inFlight.remove(key);
        });
    _inFlight[key] = future;
    return future;
  }

  /// Runs [task] after the previously queued lookup finished, with a
  /// [lookupGap] pause in between so bursts of milestones cannot stampede the
  /// platform geocoder.
  Future<String?> _enqueue(Future<String?> Function() task) {
    final Future<String?> result = _queue.then((_) async {
      if (lookupGap > Duration.zero) {
        await Future<void>.delayed(lookupGap);
      }
      return task();
    });
    // Keep the chain alive even if an injected lookup misbehaves and throws;
    // `_reverse` already catches, this is belt and braces.
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<String?> _reverse(RouteMilestone milestone) async {
    try {
      final PlaceSuggestion? suggestion = await geocoding.reverse(
        latitude: milestone.latitude,
        longitude: milestone.longitude,
      );
      if (suggestion == null) return null;
      return labelFor(suggestion);
    } catch (_) {
      return null;
    }
  }
}

/// A cached reverse-geocode result: the label (or `null` when unresolved) and
/// when a `null` should stop being trusted.
class _NameEntry {
  const _NameEntry(this.name, {this.retryAt});

  final String? name;
  final DateTime? retryAt;
}

final RegExp _coordinateLike = RegExp(
  r'^-?\d{1,3}(?:[.,]\d+)?\s*,\s*-?\d{1,3}(?:[.,]\d+)?$',
);

bool _looksLikeCoordinates(String value) =>
    _coordinateLike.hasMatch(value.trim());

String? _firstNonEmpty(List<String?> values) {
  for (final String? value in values) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}
