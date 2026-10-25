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

  group('measured motion', () {
    /// A context whose only content is [motion]: one pinned place with notes
    /// raises no other rule, so whatever comes out is the motion insight.
    AgentContext contextWith(MotionSnapshot motion) => AgentContext(
          places: <Place>[
            _place(id: 'a', latitude: 30, longitude: 31, pinned: true),
          ],
          health: HealthSummary.empty,
          motion: motion,
        );

    test('a day with over a kilometre of motion is summarised', () {
      final List<AgentInsight> insights = engine.analyze(
        contextWith(
          const MotionSnapshot(
            walkingKm: 1.2,
            runningKm: 3.5,
            vehicleKm: 18,
            steps: 6200,
          ),
        ),
      );

      expect(insights, hasLength(1));
      final AgentInsight insight = insights.single;
      expect(insight.kind, AgentInsightKind.motionSummary);
      expect(insight.id, 'motion-summary');
      expect(insight.action, AgentInsightAction.none);
      // The params are the numbers the tracker persisted — nothing derived,
      // nothing rounded, and no coordinate or place name among them.
      expect(insight.params['walkingKm'], 1.2);
      expect(insight.params['runningKm'], 3.5);
      expect(insight.params['vehicleKm'], 18.0);
      expect(insight.params['steps'], 6200);
      expect(insight.params.keys, hasLength(4));
    });

    test('exactly the threshold is enough to qualify', () {
      final List<AgentInsight> insights = engine.analyze(
        contextWith(const MotionSnapshot(walkingKm: 1)),
      );

      expect(insights.single.kind, AgentInsightKind.motionSummary);
    });

    test('a few hundred metres of motion stays quiet', () {
      // A walk to the shop is not news: below `motionSummaryMinKm` the card
      // must not appear at all.
      final List<AgentInsight> insights = engine.analyze(
        contextWith(const MotionSnapshot(walkingKm: 0.9, steps: 1200)),
      );

      expect(insights, isEmpty);
    });

    test('the categories add up: walking and running alone can qualify', () {
      final List<AgentInsight> insights = engine.analyze(
        contextWith(
          const MotionSnapshot(walkingKm: 0.4, runningKm: 0.7, steps: 1400),
        ),
      );

      expect(insights.single.kind, AgentInsightKind.motionSummary);
      expect(insights.single.params['vehicleKm'], 0.0);
    });

    test('the default snapshot is empty and changes nothing', () {
      // Every caller that predates motion tracking gets `MotionSnapshot.none`,
      // so its insights must match what it produced before the feature.
      final List<Place> places = <Place>[
        _place(id: 'a', latitude: 30, longitude: 31, notes: ''),
      ];
      final List<AgentInsight> implicit = engine.analyze(
        AgentContext(places: places, health: HealthSummary.empty),
      );
      final List<AgentInsight> explicit = engine.analyze(
        AgentContext(
          places: places,
          health: HealthSummary.empty,
          motion: MotionSnapshot.none,
        ),
      );

      expect(MotionSnapshot.none.isEmpty, isTrue);
      expect(MotionSnapshot.none.totalKm, 0);
      expect(
        implicit.any(
          (AgentInsight i) => i.kind == AgentInsightKind.motionSummary,
        ),
        isFalse,
      );
      expect(
        implicit.map((AgentInsight i) => i.kind).toList(),
        explicit.map((AgentInsight i) => i.kind).toList(),
      );
    });

    test('the snapshot compares by value', () {
      const MotionSnapshot a =
          MotionSnapshot(walkingKm: 0.4, runningKm: 0.7, steps: 1400);
      const MotionSnapshot b =
          MotionSnapshot(walkingKm: 0.4, runningKm: 0.7, steps: 1400);
      const MotionSnapshot c =
          MotionSnapshot(walkingKm: 0.4, runningKm: 0.7, steps: 1401);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.totalKm, closeTo(1.1, 1e-9));
      expect(a.toString(), contains('1400 steps'));
    });
  });
}
