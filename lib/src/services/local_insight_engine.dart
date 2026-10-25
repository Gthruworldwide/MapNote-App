import 'dart:math' as math;

import '../data/models/agent_insight.dart';
import '../data/models/place.dart';
import 'app_health_logger.dart';

/// Anonymised snapshot of everything the agent reasons about.
class AgentContext {
  const AgentContext({
    required this.places,
    required this.health,
    this.lastSynced,
    this.isSignedIn = false,
    this.now,
    this.motion = MotionSnapshot.none,
  });

  final List<Place> places;
  final HealthSummary health;

  /// Last successful sync, or null when the device has never synced.
  final DateTime? lastSynced;

  final bool isSignedIn;

  /// Today's measured motion. Defaults to [MotionSnapshot.none], so every
  /// caller that does not track motion keeps producing exactly the insights it
  /// produced before.
  final MotionSnapshot motion;

  /// Injectable clock for deterministic tests.
  final DateTime? now;

  DateTime get _now => (now ?? DateTime.now()).toUtc();
}

/// Today's measured motion, as the insight engine sees it.
///
/// A plain numeric snapshot — distances in kilometres plus a step count — so the
/// engine stays pure and the numbers can only be the ones the tracker actually
/// persisted (`DailyGpsSummary.walkKm` / `runKm` / `vehicleKm`, and the day's
/// recorded step total). No coordinate, place name or timestamp reaches this
/// type, which keeps a motion insight free of anything that could identify
/// where the user went (AGENT_SKILLS.md §5).
class MotionSnapshot {
  const MotionSnapshot({
    this.walkingKm = 0,
    this.runningKm = 0,
    this.vehicleKm = 0,
    this.steps = 0,
  });

  /// Nothing measured — the default for every existing caller.
  static const MotionSnapshot none = MotionSnapshot();

  /// Distance walked, measured by the step counter.
  final double walkingKm;

  /// Distance run, measured by the step counter.
  final double runningKm;

  /// Distance covered in a vehicle, measured from the GPS track.
  final double vehicleKm;

  /// Steps counted today (0 when the device has no step sensor).
  final int steps;

  /// Total distance across all three categories, in kilometres.
  double get totalKm => walkingKm + runningKm + vehicleKm;

  /// Whether the day measured no motion at all.
  bool get isEmpty => totalKm <= 0;

  @override
  bool operator ==(Object other) =>
      other is MotionSnapshot &&
      other.walkingKm == walkingKm &&
      other.runningKm == runningKm &&
      other.vehicleKm == vehicleKm &&
      other.steps == steps;

  @override
  int get hashCode => Object.hash(walkingKm, runningKm, vehicleKm, steps);

  @override
  String toString() =>
      'MotionSnapshot(walk ${walkingKm.toStringAsFixed(2)} km, '
      'run ${runningKm.toStringAsFixed(2)} km, '
      'vehicle ${vehicleKm.toStringAsFixed(2)} km, $steps steps)';
}

/// Pure, offline recommendation engine.
///
/// It inspects the user's *local* data structure and aggregated health metrics
/// and produces explainable, rule-based [AgentInsight]s. It performs no I/O and
/// no network access, which makes it fast, testable and fully available when
/// offline — the optional cloud LLM only ever augments it.
class LocalInsightEngine {
  const LocalInsightEngine();

  /// Places closer than this are considered a "nearby cluster".
  static const double nearbyThresholdMeters = 80;

  /// A backup older than this, while signed in, is considered stale.
  static const Duration staleBackupAfter = Duration(days: 7);

  /// How much measured motion makes today worth summarising. Below this the
  /// card stays quiet: a few metres of walking to the shop is not news.
  static const double motionSummaryMinKm = 1;

  List<AgentInsight> analyze(AgentContext context) {
    final List<AgentInsight> insights = <AgentInsight>[];

    if (context.places.isEmpty) {
      insights.add(
        const AgentInsight(
          id: 'welcome',
          kind: AgentInsightKind.welcome,
          severity: AgentInsightSeverity.info,
          action: AgentInsightAction.none,
        ),
      );
      return insights;
    }

    final AgentInsight? duplicates = _nearbyDuplicates(context.places);
    if (duplicates != null) insights.add(duplicates);

    final int missingNotes = context.places
        .where((Place place) => place.notes.trim().isEmpty)
        .length;
    if (missingNotes > 0) {
      insights.add(
        AgentInsight(
          id: 'unorganized',
          kind: AgentInsightKind.unorganizedPlaces,
          params: <String, Object?>{'count': missingNotes},
        ),
      );
    }

    // Network / sync health. A run of failures is the strongest signal.
    final int syncFailures = context.health.syncFailed;
    if (syncFailures >= 2) {
      insights.add(
        AgentInsight(
          id: 'network',
          kind: AgentInsightKind.networkWarning,
          severity: AgentInsightSeverity.warning,
          params: <String, Object?>{'count': syncFailures},
          action: AgentInsightAction.syncNow,
        ),
      );
    } else if (syncFailures == 1) {
      insights.add(
        AgentInsight(
          id: 'sync-issues',
          kind: AgentInsightKind.syncIssues,
          severity: AgentInsightSeverity.warning,
          params: <String, Object?>{'count': syncFailures},
          action: AgentInsightAction.syncNow,
        ),
      );
    }

    final int parseFailures =
        context.health.parseFailures + context.health.shortLinkFailures;
    if (parseFailures >= 2) {
      insights.add(
        AgentInsight(
          id: 'parse-issues',
          kind: AgentInsightKind.parseIssues,
          params: <String, Object?>{'count': parseFailures},
        ),
      );
    }

    final DateTime? lastSynced = context.lastSynced?.toUtc();
    if (context.isSignedIn &&
        (lastSynced == null ||
            context._now.difference(lastSynced) > staleBackupAfter)) {
      final int days = lastSynced == null
          ? 0
          : context._now.difference(lastSynced).inDays;
      insights.add(
        AgentInsight(
          id: 'stale-backup',
          kind: AgentInsightKind.staleBackup,
          params: <String, Object?>{'days': days},
          action: AgentInsightAction.syncNow,
        ),
      );
    }

    final bool anyPinned = context.places.any((Place place) => place.isPinned);
    if (context.places.length >= 12 && !anyPinned) {
      insights.add(
        AgentInsight(
          id: 'pin-favorites',
          kind: AgentInsightKind.pinFavorites,
          params: <String, Object?>{'count': context.places.length},
          action: AgentInsightAction.none,
        ),
      );
    }

    if (context.places.length >= 25) {
      insights.add(
        const AgentInsight(
          id: 'optimization',
          kind: AgentInsightKind.optimization,
          severity: AgentInsightSeverity.info,
        ),
      );
    }

    // Today's own motion. Only the numbers the tracker measured are reported, so
    // the card can never claim movement that was not recorded — and the id is
    // stable, so dismissing it keeps it away until the user asks for a refresh.
    if (context.motion.totalKm >= motionSummaryMinKm) {
      insights.add(
        AgentInsight(
          id: 'motion-summary',
          kind: AgentInsightKind.motionSummary,
          severity: AgentInsightSeverity.info,
          params: <String, Object?>{
            'walkingKm': context.motion.walkingKm,
            'runningKm': context.motion.runningKm,
            'vehicleKm': context.motion.vehicleKm,
            'steps': context.motion.steps,
          },
        ),
      );
    }

    insights.sort((AgentInsight a, AgentInsight b) {
      final int bySeverity = _sortValue(a).compareTo(_sortValue(b));
      return bySeverity != 0 ? bySeverity : a.id.compareTo(b.id);
    });
    return insights;
  }

  AgentInsight? _nearbyDuplicates(List<Place> places) {
    final int n = places.length;
    if (n < 2) return null;

    final List<bool> visited = List<bool>.filled(n, false);
    int clusteredPlaces = 0;
    int clusters = 0;

    for (int i = 0; i < n; i++) {
      if (visited[i]) continue;
      final List<int> group = <int>[i];
      for (int j = i + 1; j < n; j++) {
        if (visited[j]) continue;
        if (_distanceMeters(places[i], places[j]) <=
            nearbyThresholdMeters) {
          group.add(j);
        }
      }
      if (group.length >= 2) {
        clusters++;
        clusteredPlaces += group.length;
        for (final int index in group) {
          visited[index] = true;
        }
      }
    }

    if (clusters == 0) return null;
    return AgentInsight(
      id: 'nearby-duplicates',
      kind: AgentInsightKind.nearbyDuplicates,
      params: <String, Object?>{'count': clusteredPlaces, 'clusters': clusters},
    );
  }

  static int _sortValue(AgentInsight insight) {
    final int severity = switch (insight.severity) {
      AgentInsightSeverity.warning => 0,
      AgentInsightSeverity.suggestion => 1,
      AgentInsightSeverity.info => 2,
    };
    return severity;
  }

  static double _distanceMeters(Place a, Place b) {
    const double earthRadius = 6371000;
    final double dLat = _radians(b.latitude - a.latitude);
    final double dLng = _radians(b.longitude - a.longitude);
    final double lat1 = _radians(a.latitude);
    final double lat2 = _radians(b.latitude);

    final double h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
