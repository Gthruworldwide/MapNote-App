import 'package:flutter/foundation.dart';

import '../data/local/settings_repository.dart';
import '../data/models/agent_insight.dart';
import '../data/models/place.dart';
import 'app_health_logger.dart';
import 'gemini_client.dart';
import 'local_insight_engine.dart';
import 'location_parser.dart';

/// Orchestrates the recommendation agent.
///
/// * The **local** [LocalInsightEngine] always runs — instant, offline, private.
/// * The optional **cloud** [GeminiClient] augments it with LLM suggestions when
///   an API key is configured and the user has left cloud AI enabled. The cloud
///   model may call the on-device tools in [tools] to ground its suggestions in
///   real sync state or to validate a pasted link.
///
/// Only anonymous aggregate metrics are sent to the cloud (see [_metrics]).
/// Tool results (sync timestamps, parsed coordinates) leave the device **only**
/// when a function is actually invoked — which itself only happens while cloud
/// AI is enabled.
class AgentService {
  AgentService({
    required this.logger,
    required this.settings,
    this.engine = const LocalInsightEngine(),
    GeminiClient? cloudClient,
  }) : _cloud = cloudClient ?? GeminiClient();

  final AppHealthLogger logger;
  final SettingsRepository settings;
  final LocalInsightEngine engine;
  final GeminiClient _cloud;

  static const LocationParser _parser = LocationParser();

  /// Whether the cloud path can currently run.
  bool get isCloudAvailable => settings.isCloudAiEnabled && _cloud.isConfigured;

  /// On-device tools the cloud model may call. Execution happens locally; only
  /// the (small, non-identifying) result map is sent back to the model.
  List<AgentTool> get tools => <AgentTool>[
        AgentTool(
          name: 'checkSyncStatus',
          description:
              'Checks current Google Drive sync state and last sync timestamp',
          parameters: const <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
          },
          execute: _checkSyncStatus,
        ),
        AgentTool(
          name: 'parseLocationLink',
          description:
              'Parses pasted map URL or text to validate lat/long extraction',
          parameters: const <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'inputUrl': <String, Object?>{
                'type': 'string',
                'description': 'The text or link to parse',
              },
            },
            'required': <String>['inputUrl'],
          },
          execute: _parseLocationLink,
        ),
      ];

  /// Grounds the model in the real Drive backup state stored on this device.
  Future<Map<String, Object?>> _checkSyncStatus(
    Map<String, Object?> args,
  ) async {
    final HealthSummary health = logger.summary();
    final DateTime? lastSynced = settings.lastSynced?.toUtc();
    return <String, Object?>{
      'lastSyncedIso': lastSynced?.toIso8601String(),
      'syncSucceeded': health.syncSucceeded,
      'syncFailed': health.syncFailed,
      'syncSkipped': health.syncSkipped,
    };
  }

  /// Validates a map URL or raw text and, when it parses, returns its
  /// coordinates. Short links are resolved over the network; any failure is
  /// reported without throwing.
  Future<Map<String, Object?>> _parseLocationLink(
    Map<String, Object?> args,
  ) async {
    final String input = args['inputUrl']?.toString().trim() ?? '';
    if (input.isEmpty) {
      return <String, Object?>{'success': false, 'reason': 'empty_input'};
    }
    ParsedLocation? parsed = _parser.parse(input);
    if (parsed == null && _parser.looksLikeShortMapLink(input)) {
      parsed = await _parser.resolveShortLink(input);
    }
    if (parsed == null) {
      return <String, Object?>{'success': false, 'reason': 'no_location_found'};
    }
    return <String, Object?>{
      'success': true,
      'latitude': parsed.latitude,
      'longitude': parsed.longitude,
      if (parsed.name != null && parsed.name!.isNotEmpty) 'name': parsed.name,
    };
  }

  /// Rule-based insights. Always available, never throws.
  List<AgentInsight> localInsights(AgentContext context) =>
      engine.analyze(context);

  /// LLM insights in the user's language. Best-effort: any failure is logged
  /// and returns an empty list so the local insights still stand.
  Future<List<AgentInsight>> cloudInsights(
    AgentContext context, {
    required String languageCode,
    required String languageName,
  }) async {
    if (!settings.isCloudAiEnabled) {
      logger.log(
        HealthEventType.agentSkipped,
        data: const <String, Object?>{'reason': 'disabled'},
      );
      return const <AgentInsight>[];
    }
    if (!_cloud.isConfigured) {
      logger.log(
        HealthEventType.agentSkipped,
        data: const <String, Object?>{'reason': 'not_configured'},
      );
      return const <AgentInsight>[];
    }

    final List<AgentInsight> local = engine.analyze(context);
    try {
      final List<AgentInsight> insights = await _cloud.fetchInsights(
        metrics: _metrics(context, local, languageCode),
        languageName: languageName,
        tools: tools,
      );
      logger.log(
        HealthEventType.agentRun,
        message: 'cloud',
        data: <String, Object?>{'count': insights.length},
      );
      return insights;
    } on AgentException catch (error) {
      if (kDebugMode) debugPrint('MapNote agent cloud failure: $error');
      logger.log(HealthEventType.agentFailure, message: error.message);
      return const <AgentInsight>[];
    } catch (error) {
      if (kDebugMode) debugPrint('MapNote agent cloud failure: $error');
      logger.log(HealthEventType.agentFailure, message: error.toString());
      return const <AgentInsight>[];
    }
  }

  /// Anonymous aggregate metrics — deliberately excludes names, notes, ids and
  /// coordinates so nothing personally identifying ever leaves the device.
  Map<String, Object?> _metrics(
    AgentContext context,
    List<AgentInsight> local,
    String languageCode,
  ) {
    final List<Place> places = context.places;
    final int missingNotes = places
        .where((Place place) => place.notes.trim().isEmpty)
        .length;

    int nearbyClusters = 0;
    int nearbyPlaces = 0;
    for (final AgentInsight insight in local) {
      if (insight.kind == AgentInsightKind.nearbyDuplicates) {
        nearbyClusters = (insight.params['clusters'] as int?) ?? 0;
        nearbyPlaces = (insight.params['count'] as int?) ?? 0;
      }
    }

    final DateTime? lastSynced = context.lastSynced?.toUtc();
    final int? lastBackupDaysAgo = lastSynced == null
        ? null
        : ((context.now ?? DateTime.now()).toUtc().difference(lastSynced).inDays);

    return <String, Object?>{
      'language': languageCode,
      'savedPlaces': places.length,
      'pinnedPlaces': places.where((Place p) => p.isPinned).length,
      'hiddenPlaces': places.where((Place p) => p.isHidden).length,
      'lockedPlaces': places.where((Place p) => p.isLocked).length,
      'placesWithoutNotes': missingNotes,
      'nearbyClusters': nearbyClusters,
      'nearbyPlaces': nearbyPlaces,
      'signedIn': context.isSignedIn,
      'lastBackupDaysAgo': lastBackupDaysAgo,
      'recentSyncFailures': context.health.syncFailed,
      'recentSyncSuccesses': context.health.syncSucceeded,
      'recentSyncSkipped': context.health.syncSkipped,
      'parseFailures': context.health.parseFailures,
      'shortLinkFailures': context.health.shortLinkFailures,
      'appLaunches': context.health.appLaunches,
    };
  }
}
