import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../data/models/agent_insight.dart';
import 'key_rotation_service.dart';

/// Raised when a cloud recommendation request fails.
class AgentException implements Exception {
  const AgentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A function the cloud model may call to ground its suggestions in real app
/// state.
///
/// [parameters] is a JSON-Schema object describing the arguments (the Google
/// Gemini `functionDeclarations` format). [execute] runs locally on the device
/// — the model never executes anything itself.
class AgentTool {
  const AgentTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
  });

  final String name;
  final String description;
  final Map<String, Object?> parameters;

  /// Runs the tool on-device. The returned map is sent back to the model as the
  /// `functionResponse`; keep it minimal and non-sensitive.
  final Future<Map<String, Object?>> Function(Map<String, Object?> args) execute;

  Map<String, Object?> toDeclaration() => <String, Object?>{
        'name': name,
        'description': description,
        'parameters': parameters,
      };
}

/// Thin client for Google's Gemini `generateContent` REST API.
///
/// This is intentionally optional: when no API key is configured it reports
/// [isConfigured] = false and the app stays fully offline-first. Only anonymous
/// aggregate [metrics] are ever sent — never place names, notes or coordinates.
///
/// The key pool comes from `--dart-define=GEMINI_API_KEY` (comma separated) and
/// is rotated by a [KeyRotationService]: a rejected or over-quota key is put on
/// cooldown and the request is retried with the next healthy key, so key
/// exhaustion never takes the cloud features offline.
///
/// When [fetchInsights] is given [tools], the request declares them as Gemini
/// functions. If the model answers with a `functionCall`, the tool is executed
/// locally and the conversation continues with a `functionResponse` (up to
/// [AppConfig.agentToolRounds] rounds) before the final text is parsed.
class GeminiClient {
  GeminiClient({
    http.Client? client,
    String? apiKey,
    KeyRotationService? keyRotation,
    String? model,
    Duration? timeout,
  }) : _client = client ?? http.Client(),
       _rotation =
           keyRotation ??
           KeyRotationService(
             keys: apiKey != null
                 ? AppConfig.parseGeminiApiKeys(apiKey)
                 : AppConfig.geminiApiKeys,
           ),
       _model = (model ?? AppConfig.geminiModel).trim(),
       _timeout = timeout ?? AppConfig.agentRequestTimeout;

  final http.Client _client;
  final KeyRotationService _rotation;
  final String _model;
  final Duration _timeout;

  bool get isConfigured => _rotation.hasKeys;

  /// Asks Gemini for up to [AppConfig.maxAgentInsights] localized suggestions.
  ///
  /// [languageName] is the human-readable language for the response (e.g.
  /// "English" or "Arabic") so insights arrive already localized.
  Future<List<AgentInsight>> fetchInsights({
    required Map<String, Object?> metrics,
    required String languageName,
    List<AgentTool>? tools,
  }) async {
    if (!isConfigured) return const <AgentInsight>[];

    final Map<String, Object?> body = _buildBody(metrics, languageName, tools);
    for (int round = 0; round < AppConfig.agentToolRounds; round++) {
      final http.Response response = await _postRotating(body);
      if (response.statusCode != 200) {
        throw AgentException(
          'Cloud suggestions failed (HTTP ${response.statusCode})',
        );
      }

      final Map<String, Object?> decoded = _decode(response.body);
      final List<Map<String, Object?>> calls = _functionCalls(decoded);
      if (calls.isEmpty) {
        return _parse(decoded);
      }

      // The model asked for real data: run the tools on-device, then continue
      // the conversation with the results.
      final List<Map<String, Object?>> results = await _runTools(calls, tools);
      final List<Object?> contents = List<Object?>.from(
        body['contents'] as List<Object?>,
      );
      contents.add(<String, Object?>{
        'role': 'model',
        'parts': <Object?>[
          for (final Map<String, Object?> call in calls)
            <String, Object?>{'functionCall': call},
        ],
      });
      contents.add(<String, Object?>{
        'role': 'user',
        'parts': <Object?>[
          for (final Map<String, Object?> result in results)
            <String, Object?>{'functionResponse': result},
        ],
      });
      body['contents'] = contents;
    }
    throw const AgentException('Cloud suggestions exceeded the tool round limit');
  }

  Map<String, Object?> _buildBody(
    Map<String, Object?> metrics,
    String languageName,
    List<AgentTool>? tools,
  ) {
    final Map<String, Object?> body = <String, Object?>{
      'systemInstruction': <String, Object?>{
        'parts': <Object?>[
          <String, Object?>{
            'text':
                'You are the in-app assistant of "MapNote", an offline-first '
                'location saving app. You receive anonymous aggregate metrics '
                'about the user\'s local data and app health. Respond ONLY with '
                'a JSON array (no markdown, no prose) of at most '
                '${AppConfig.maxAgentInsights} objects. Each object must have '
                'exactly these string keys: "title" (max 6 words), "body" '
                '(max 20 words), and "severity" (one of "info", "suggestion", '
                '"warning"). Give concrete, friendly, non-repetitive tips about '
                'organizing locations, sync/network reliability, or app speed. '
                'Never invent data or mention that you are an AI. If you need '
                'current sync state or a pasted link parsed, call the provided '
                'functions instead of guessing.',
          },
        ],
      },
      'contents': <Object?>[
        <String, Object?>{
          'role': 'user',
          'parts': <Object?>[
            <String, Object?>{
              'text':
                  'Language for the response: $languageName.\n'
                  'Anonymous metrics JSON:\n${jsonEncode(metrics)}',
            },
          ],
        },
      ],
      'generationConfig': <String, Object?>{
        'temperature': 0.4,
        'maxOutputTokens': 512,
        'responseMimeType': 'application/json',
      },
    };

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = <Object?>[
        <String, Object?>{
          'functionDeclarations': <Object?>[
            for (final AgentTool tool in tools) tool.toDeclaration(),
          ],
        },
      ];
    }
    return body;
  }

  /// POSTs [body], rotating to the next configured key when the current one is
  /// rejected (invalid / revoked / over quota). Returns the last response so the
  /// caller keeps its existing status handling.
  ///
  /// A key failure never throws here: the loop simply exhausts the pool, and the
  /// final non-200 response is surfaced exactly as before.
  Future<http.Response> _postRotating(Map<String, Object?> body) async {
    http.Response? response;
    final int attempts = _rotation.length == 0 ? 1 : _rotation.length;
    String? key = _rotation.currentKey;
    for (int attempt = 0; attempt < attempts && key != null; attempt++) {
      response = await _post(body, key);
      if (response.statusCode == 200 ||
          !KeyRotationService.looksLikeKeyError(
            response.statusCode,
            response.body,
          )) {
        _rotation.markSuccess(key);
        return response;
      }
      _rotation.markFailure(key, statusCode: response.statusCode);
      key = _rotation.currentKey;
    }
    if (response == null) {
      throw const AgentException('Cloud suggestions unavailable');
    }
    return response;
  }

  /// POSTs [body] to the model with [apiKey]. Deliberately opaque on failure: a
  /// raw transport error can embed the request URI and headers, so it is never
  /// surfaced.
  Future<http.Response> _post(
    Map<String, Object?> body,
    String apiKey,
  ) async {
    final Uri uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$_model:generateContent',
    );
    try {
      return await _client
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              // The key travels in a header, never the URL, so it can't leak
              // through request URIs embedded in error messages or logs.
              'x-goog-api-key': apiKey,
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const AgentException('Cloud suggestions timed out');
    } catch (_) {
      throw const AgentException('Cloud suggestions unavailable');
    }
  }

  Map<String, Object?> _decode(String rawBody) {
    final Object? decoded;
    try {
      decoded = jsonDecode(rawBody);
    } catch (_) {
      throw const AgentException('Cloud suggestions returned invalid JSON');
    }
    if (decoded is! Map) {
      throw const AgentException('Cloud suggestions returned an unexpected body');
    }
    return Map<String, Object?>.from(decoded);
  }

  /// The `parts` of the first candidate, as mutable maps.
  List<Map<String, Object?>> _candidateParts(Map<String, Object?> decoded) {
    final Object? candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const AgentException('Cloud suggestions returned no candidates');
    }
    final Object? candidate = candidates.first;
    if (candidate is! Map) return const <Map<String, Object?>>[];
    final Object? content = candidate['content'];
    if (content is! Map) return const <Map<String, Object?>>[];
    final Object? parts = content['parts'];
    if (parts is! List) return const <Map<String, Object?>>[];
    return <Map<String, Object?>>[
      for (final Object? part in parts)
        if (part is Map) Map<String, Object?>.from(part),
    ];
  }

  /// The `functionCall` parts of the first candidate (if the model asked to run
  /// a tool instead of answering directly).
  List<Map<String, Object?>> _functionCalls(Map<String, Object?> decoded) {
    final List<Map<String, Object?>> calls = <Map<String, Object?>>[];
    for (final Map<String, Object?> part in _candidateParts(decoded)) {
      final Object? call = part['functionCall'];
      if (call is Map) calls.add(Map<String, Object?>.from(call));
    }
    return calls;
  }

  /// Executes every requested tool locally and builds `functionResponse` maps.
  Future<List<Map<String, Object?>>> _runTools(
    List<Map<String, Object?>> calls,
    List<AgentTool>? tools,
  ) async {
    final Map<String, AgentTool> byName = <String, AgentTool>{
      for (final AgentTool tool in tools ?? const <AgentTool>[])
        tool.name: tool,
    };
    final List<Map<String, Object?>> results = <Map<String, Object?>>[];
    for (final Map<String, Object?> call in calls) {
      final String name = call['name']?.toString() ?? '';
      final Object? args = call['args'];
      final Map<String, Object?> argMap = args is Map
          ? Map<String, Object?>.from(args)
          : const <String, Object?>{};
      final AgentTool? tool = byName[name];

      if (tool == null) {
        results.add(<String, Object?>{
          'name': name,
          'response': <String, Object?>{
            'result': <String, Object?>{'error': 'unknown_tool'},
          },
        });
        continue;
      }

      try {
        final Map<String, Object?> result = await tool.execute(argMap);
        results.add(<String, Object?>{
          'name': name,
          'response': <String, Object?>{'result': result},
        });
      } catch (error) {
        // Give the model a terse, non-sensitive failure marker; log details
        // locally so a weird input can still be debugged.
        if (kDebugMode) {
          debugPrint('MapNote agent tool "$name" failed: $error');
        }
        results.add(<String, Object?>{
          'name': name,
          'response': <String, Object?>{
            'result': <String, Object?>{'error': 'tool_failed'},
          },
        });
      }
    }
    return results;
  }

  List<AgentInsight> _parse(Map<String, Object?> decoded) {
    final String? text = _extractText(_candidateParts(decoded));
    if (text == null || text.trim().isEmpty) {
      return const <AgentInsight>[];
    }

    final Object? parsed = jsonDecode(_stripCodeFences(text));
    if (parsed is! List) {
      throw const AgentException('Cloud suggestions were not a JSON array');
    }

    final List<AgentInsight> insights = <AgentInsight>[];
    for (final Object? item in parsed) {
      if (item is! Map) continue;
      final String title = _clean(item['title']);
      final String body = _clean(item['body']);
      if (title.isEmpty || body.isEmpty) continue;
      insights.add(
        AgentInsight(
          id: 'llm-${title.hashCode}',
          kind: AgentInsightKind.custom,
          severity: _severity(item['severity']),
          customTitle: title,
          customBody: body,
        ),
      );
      if (insights.length >= AppConfig.maxAgentInsights) break;
    }
    return insights;
  }

  String? _extractText(List<Map<String, Object?>> parts) {
    final StringBuffer buffer = StringBuffer();
    for (final Map<String, Object?> part in parts) {
      if (part['text'] != null) buffer.write(part['text']);
    }
    return buffer.toString();
  }

  static String _stripCodeFences(String value) {
    String text = value.trim();
    if (text.startsWith('```')) {
      final int firstNewline = text.indexOf('\n');
      if (firstNewline != -1) text = text.substring(firstNewline + 1);
      if (text.endsWith('```')) {
        text = text.substring(0, text.length - 3);
      }
    }
    return text.trim();
  }

  static AgentInsightSeverity _severity(Object? raw) {
    return switch (raw?.toString().toLowerCase()) {
      'warning' => AgentInsightSeverity.warning,
      'info' => AgentInsightSeverity.info,
      _ => AgentInsightSeverity.suggestion,
    };
  }

  static String _clean(Object? raw) {
    if (raw == null) return '';
    final String text = raw.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 200 ? text.substring(0, 200) : text;
  }

  /// Releases the underlying HTTP client.
  void close() => _client.close();
}