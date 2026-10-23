import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/data/models/agent_insight.dart';
import 'package:routenote/src/data/models/place.dart';
import 'package:routenote/src/services/app_health_logger.dart';
import 'package:routenote/src/services/local_insight_engine.dart';

Place _place({
  required String id,
  required double latitude,
  required double longitude,
  String notes = 'note',
  bool pinned = false,
}) {
  return Place(
    id: id,
    name: 'Place $id',
    notes: notes,
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime.utc(2026, 1, 1),
    isPinned: pinned,
  );
}

HealthSummary _health({
  int syncFailed = 0,
  int syncSucceeded = 0,
  int parseFailures = 0,
  int shortLinkFailures = 0,
}) {
  return HealthSummary(
    totalEvents: 1,
    appLaunches: 1,
    appResumes: 0,
    syncSucceeded: syncSucceeded,
    syncFailed: syncFailed,
    syncSkipped: 0,
    parseFailures: parseFailures,
    shortLinkFailures: shortLinkFailures,
    placeSaves: 0,
  );
}

void main() {
  const LocalInsightEngine engine = LocalInsightEngine();

  test('suggests saving a first place when there are none', () {
    final List<AgentInsight> insights = engine.analyze(
      const AgentContext(places: <Place>[], health: HealthSummary.empty),
    );
    expect(insights, hasLength(1));
    expect(insights.single.kind, AgentInsightKind.welcome);
  });

  test('detects nearby duplicate coordinates and missing notes', () {
    final List<AgentInsight> insights = engine.analyze(
      AgentContext(
        places: <Place>[
          _place(id: 'a', latitude: 30.0, longitude: 31.0),
          _place(id: 'b', latitude: 30.0001, longitude: 31.0001),
          _place(id: 'c', latitude: 40.0, longitude: 40.0, notes: ''),
        ],
        health: HealthSummary.empty,
      ),
    );

    final AgentInsight duplicates = insights.firstWhere(
      (AgentInsight i) => i.kind == AgentInsightKind.nearbyDuplicates,
    );
    expect(duplicates.params['count'], 2);
    expect(duplicates.params['clusters'], 1);

    expect(
      insights.any(
        (AgentInsight i) => i.kind == AgentInsightKind.unorganizedPlaces,
      ),
      isTrue,
    );
  });

  test('does not flag far-apart places as duplicates', () {
    final List<AgentInsight> insights = engine.analyze(
      AgentContext(
        places: <Place>[
          _place(id: 'a', latitude: 30.0, longitude: 31.0),
          _place(id: 'b', latitude: 40.0, longitude: 40.0),
        ],
        health: HealthSummary.empty,
      ),
    );
    expect(
      insights.any(
        (AgentInsight i) => i.kind == AgentInsightKind.nearbyDuplicates,
      ),
      isFalse,
    );
  });

  test('warns after repeated sync failures and sorts warnings first', () {
    final List<AgentInsight> insights = engine.analyze(
      AgentContext(
        places: <Place>[_place(id: 'a', latitude: 30, longitude: 31)],
        health: _health(syncFailed: 3),
      ),
    );

    final AgentInsight warning = insights.firstWhere(
      (AgentInsight i) => i.kind == AgentInsightKind.networkWarning,
    );
    expect(warning.severity, AgentInsightSeverity.warning);
    expect(warning.action, AgentInsightAction.syncNow);
    expect(insights.first.kind, AgentInsightKind.networkWarning);
  });

  test('flags a single sync failure as a sync issue', () {
    final List<AgentInsight> insights = engine.analyze(
      AgentContext(
        places: <Place>[_place(id: 'a', latitude: 30, longitude: 31)],
        health: _health(syncFailed: 1),
      ),
    );
    expect(
      insights.any((AgentInsight i) => i.kind == AgentInsightKind.syncIssues),
      isTrue,
    );
  });

  test('a recovered sync run stops raising the sync issue', () {
    // End-to-end over the real logger so the "unrecovered run" rule and the
    // insight stay pinned together: tapping Sync, a "Sync now" insight or
    // pulling to refresh logs a success, and the banner must clear on its own.
    final AppHealthLogger logger = AppHealthLogger(null);
    final List<Place> places = <Place>[
      _place(id: 'a', latitude: 30, longitude: 31),
    ];
    bool raisesSyncIssue() => engine
        .analyze(AgentContext(places: places, health: logger.summary()))
        .any((AgentInsight i) => i.kind == AgentInsightKind.syncIssues);

    logger.log(HealthEventType.syncFailed, message: 'timeout');
    expect(raisesSyncIssue(), isTrue);

    logger.log(HealthEventType.syncSucceeded);

    expect(raisesSyncIssue(), isFalse);
  });

  test('reports parse problems once they accumulate', () {
    final List<AgentInsight> insights = engine.analyze(
      AgentContext(
        places: <Place>[_place(id: 'a', latitude: 30, longitude: 31)],
        health: _health(parseFailures: 2, shortLinkFailures: 1),
      ),
    );
    final AgentInsight parse = insights.firstWhere(
      (AgentInsight i) => i.kind == AgentInsightKind.parseIssues,
    );
    expect(parse.params['count'], 3);
  });

  test('flags a stale backup when signed in', () {
    final List<AgentInsight> insights = engine.analyze(
      AgentContext(
        places: <Place>[_place(id: 'a', latitude: 30, longitude: 31)],
        health: HealthSummary.empty,
        isSignedIn: true,
        now: DateTime.utc(2026, 2, 1),
        lastSynced: DateTime.utc(2026, 1, 1),
      ),
    );
    expect(
      insights.any((AgentInsight i) => i.kind == AgentInsightKind.staleBackup),
      isTrue,
    );
  });

  test('suggests pinning when a large list has no pins', () {
    final List<Place> places = List<Place>.generate(
      12,
      (int i) => _place(
        id: 'p$i',
        latitude: 30.0 + i,
        longitude: 31.0 + i,
      ),
    );
    final List<AgentInsight> insights = engine.analyze(
      AgentContext(places: places, health: HealthSummary.empty),
    );
    expect(
      insights.any((AgentInsight i) => i.kind == AgentInsightKind.pinFavorites),
      isTrue,
    );
  });
}
