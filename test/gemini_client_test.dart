import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:routenote/src/data/models/agent_insight.dart';
import 'package:routenote/src/services/gemini_client.dart';

http.Response _responseWith(List<Map<String, String>> suggestions) {
  final String inner = jsonEncode(suggestions);
  final Map<String, Object?> body = <String, Object?>{
    'candidates': <Object?>[
      <String, Object?>{
        'content': <String, Object?>{
          'parts': <Object?>[
            <String, Object?>{'text': inner},
          ],
        },
      },
    ],
  };
  return http.Response(jsonEncode(body), 200);
}

void main() {
  test('parses localized suggestions from a Gemini response', () async {
    final GeminiClient client = GeminiClient(
      apiKey: 'test-key',
      client: MockClient(
        (http.Request request) async => _responseWith(<Map<String, String>>[
          <String, String>{
            'title': 'Group nearby places',
            'body': 'Two saved places overlap.',
            'severity': 'suggestion',
          },
          <String, String>{
            'title': 'Back up now',
            'body': 'Your last backup is old.',
            'severity': 'warning',
          },
        ]),
      ),
    );

    expect(client.isConfigured, isTrue);
    final List<AgentInsight> insights = await client.fetchInsights(
      metrics: const <String, Object?>{'savedPlaces': 3},
      languageName: 'English',
    );

    expect(insights, hasLength(2));
    expect(insights.first.kind, AgentInsightKind.custom);
    expect(insights.first.customTitle, 'Group nearby places');
    expect(insights.first.customBody, 'Two saved places overlap.');
    expect(insights[1].severity, AgentInsightSeverity.warning);
  });

  test('sends the API key in a header, never in the URL', () async {
    late http.Request captured;
    final GeminiClient client = GeminiClient(
      apiKey: 'secret-key',
      client: MockClient((http.Request request) async {
        captured = request;
        return _responseWith(const <Map<String, String>>[]);
      }),
    );

    await client.fetchInsights(
      metrics: const <String, Object?>{},
      languageName: 'English',
    );

    expect(captured.headers['x-goog-api-key'], 'secret-key');
    expect(captured.url.query.contains('secret-key'), isFalse);
    expect(captured.url.queryParameters.containsKey('key'), isFalse);
  });

  test('never surfaces the raw transport error (which could embed the URL)',
      () async {
    final GeminiClient client = GeminiClient(
      apiKey: 'secret-key',
      client: MockClient((http.Request request) async {
        throw http.ClientException(
          'failed to connect to ${request.url}',
          request.url,
        );
      }),
    );

    await expectLater(
      () => client.fetchInsights(
        metrics: const <String, Object?>{},
        languageName: 'English',
      ),
      throwsA(
        isA<AgentException>().having(
          (AgentException e) => e.message,
          'message',
          isNot(contains('secret-key')),
        ),
      ),
    );
  });

  test('executes tool calls on-device and continues the conversation', () async {
    int requests = 0;
    bool executed = false;
    final GeminiClient client = GeminiClient(
      apiKey: 'test-key',
      client: MockClient((http.Request request) async {
        requests++;
        final Map<String, dynamic> body =
            jsonDecode(request.body) as Map<String, dynamic>;
        if (requests == 1) {
          // Tools are declared up front.
          final List<dynamic> tools = body['tools'] as List<dynamic>;
          final List<dynamic> declarations =
              tools.first['functionDeclarations'] as List<dynamic>;
          expect(
            declarations.map((dynamic d) => d['name']),
            containsAll(<String>['checkSyncStatus', 'parseLocationLink']),
          );
          return http.Response(
            jsonEncode(<String, Object?>{
              'candidates': <Object?>[
                <String, Object?>{
                  'content': <String, Object?>{
                    'parts': <Object?>[
                      <String, Object?>{
                        'functionCall': <String, Object?>{
                          'name': 'checkSyncStatus',
                          'args': <String, Object?>{},
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }
        // Second round: the functionResponse for checkSyncStatus was appended.
        final List<dynamic> contents = body['contents'] as List<dynamic>;
        final Map<String, dynamic> modelTurn =
            contents[1] as Map<String, dynamic>;
        expect(modelTurn['role'], 'model');
        final Map<String, dynamic> responseTurn =
            contents[2] as Map<String, dynamic>;
        expect(responseTurn['role'], 'user');
        final List<dynamic> parts =
            responseTurn['parts'] as List<dynamic>;
        final Map<String, dynamic> responsePart =
            parts.first as Map<String, dynamic>;
        final Map<String, dynamic> functionResponse =
            responsePart['functionResponse'] as Map<String, dynamic>;
        expect(functionResponse['name'], 'checkSyncStatus');
        expect(
          (functionResponse['response'] as Map<dynamic, dynamic>)['result'],
          <String, Object?>{'ok': true},
        );
        return _responseWith(<Map<String, String>>[
          <String, String>{
            'title': 'Grounded',
            'body': 'Sync looks healthy.',
            'severity': 'info',
          },
        ]);
      }),
    );

    final List<AgentInsight> insights = await client.fetchInsights(
      metrics: const <String, Object?>{},
      languageName: 'English',
      tools: <AgentTool>[
        AgentTool(
          name: 'checkSyncStatus',
          description: 'Check sync state',
          parameters: const <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
          },
          execute: (Map<String, Object?> args) async {
            executed = true;
            return <String, Object?>{'ok': true};
          },
        ),
        AgentTool(
          name: 'parseLocationLink',
          description: 'Parse a link',
          parameters: const <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'inputUrl': <String, Object?>{'type': 'string'},
            },
            'required': <String>['inputUrl'],
          },
          execute: (Map<String, Object?> args) async =>
              <String, Object?>{'success': false},
        ),
      ],
    );

    expect(requests, 2);
    expect(executed, isTrue);
    expect(insights, hasLength(1));
    expect(insights.single.customTitle, 'Grounded');
  });

  test('reports an unknown tool instead of failing the request', () async {
    int requests = 0;
    final GeminiClient client = GeminiClient(
      apiKey: 'test-key',
      client: MockClient((http.Request request) async {
        requests++;
        if (requests > 1) return _responseWith(const <Map<String, String>>[]);
        return http.Response(
          jsonEncode(<String, Object?>{
            'candidates': <Object?>[
              <String, Object?>{
                'content': <String, Object?>{
                  'parts': <Object?>[
                    <String, Object?>{
                      'functionCall': <String, Object?>{
                        'name': 'totallyUnknown',
                        'args': <String, Object?>{},
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    final List<AgentInsight> insights = await client.fetchInsights(
      metrics: const <String, Object?>{},
      languageName: 'English',
      tools: <AgentTool>[
        AgentTool(
          name: 'checkSyncStatus',
          description: 'Check sync state',
          parameters: const <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
          },
          execute: (Map<String, Object?> args) async =>
              <String, Object?>{'ok': true},
        ),
      ],
    );

    // The loop still terminates: the model is told the tool is missing and the
    // next round's text answer is parsed normally.
    expect(requests, 2);
    expect(insights, isEmpty);
  });

  test('does not declare tools when none are provided', () async {
    Map<String, dynamic>? captured;
    final GeminiClient client = GeminiClient(
      apiKey: 'test-key',
      client: MockClient((http.Request request) async {
        captured = jsonDecode(request.body) as Map<String, dynamic>;
        return _responseWith(const <Map<String, String>>[]);
      }),
    );

    await client.fetchInsights(
      metrics: const <String, Object?>{},
      languageName: 'English',
    );

    expect(captured, isNotNull);
    expect(captured!.containsKey('tools'), isFalse);
  });

  test('strips markdown code fences from the response', () async {
    final GeminiClient client = GeminiClient(
      apiKey: 'test-key',
      client: MockClient(
        (http.Request request) async => http.Response(
          jsonEncode(<String, Object?>{
            'candidates': <Object?>[
              <String, Object?>{
                'content': <String, Object?>{
                  'parts': <Object?>[
                    <String, Object?>{
                      'text':
                          '```json\n'
                          '[{"title":"T","body":"B","severity":"info"}]\n'
                          '```',
                    },
                  ],
                },
              },
            ],
          }),
          200,
        ),
      ),
    );

    final List<AgentInsight> insights = await client.fetchInsights(
      metrics: const <String, Object?>{},
      languageName: 'English',
    );
    expect(insights, hasLength(1));
    expect(insights.single.severity, AgentInsightSeverity.info);
  });

  test('returns an empty list when no key is configured', () async {
    final GeminiClient client = GeminiClient(
      apiKey: '',
      client: MockClient(
        (http.Request request) async => http.Response('{}', 200),
      ),
    );
    expect(client.isConfigured, isFalse);
    expect(
      await client.fetchInsights(
        metrics: const <String, Object?>{},
        languageName: 'English',
      ),
      isEmpty,
    );
  });

  test('throws AgentException on an HTTP failure', () async {
    final GeminiClient client = GeminiClient(
      apiKey: 'test-key',
      client: MockClient(
        (http.Request request) async => http.Response('nope', 500),
      ),
    );
    expect(
      () => client.fetchInsights(
        metrics: const <String, Object?>{},
        languageName: 'English',
      ),
      throwsA(isA<AgentException>()),
    );
  });

  group('key rotation', () {
    test('retries with the fallback key when the primary is over quota',
        () async {
      final List<String> usedKeys = <String>[];
      final GeminiClient client = GeminiClient(
        apiKey: 'primary,fallback',
        client: MockClient((http.Request request) async {
          final String key = request.headers['x-goog-api-key']!;
          usedKeys.add(key);
          if (key == 'primary') return http.Response('quota', 429);
          return _responseWith(<Map<String, String>>[
            <String, String>{
              'title': 'Recovered',
              'body': 'The fallback key answered.',
              'severity': 'info',
            },
          ]);
        }),
      );

      final List<AgentInsight> insights = await client.fetchInsights(
        metrics: const <String, Object?>{},
        languageName: 'English',
      );

      expect(usedKeys, <String>['primary', 'fallback']);
      expect(insights.single.customTitle, 'Recovered');
    });

    test('keeps using the healthy key on the next request', () async {
      final List<String> usedKeys = <String>[];
      final GeminiClient client = GeminiClient(
        apiKey: 'primary,fallback',
        client: MockClient((http.Request request) async {
          final String key = request.headers['x-goog-api-key']!;
          usedKeys.add(key);
          if (key == 'primary') return http.Response('quota', 429);
          return _responseWith(const <Map<String, String>>[]);
        }),
      );

      await client.fetchInsights(
        metrics: const <String, Object?>{},
        languageName: 'English',
      );
      await client.fetchInsights(
        metrics: const <String, Object?>{},
        languageName: 'English',
      );

      // primary, fallback (rotated), then fallback again — no second probe of
      // the key that is cooling down.
      expect(usedKeys, <String>['primary', 'fallback', 'fallback']);
    });

    test('rotates on an API_KEY_INVALID 400 response', () async {
      final List<String> usedKeys = <String>[];
      final GeminiClient client = GeminiClient(
        apiKey: 'primary,fallback',
        client: MockClient((http.Request request) async {
          final String key = request.headers['x-goog-api-key']!;
          usedKeys.add(key);
          if (key == 'primary') {
            return http.Response('{"error":{"status":"INVALID_ARGUMENT",'
                '"details":[{"reason":"API_KEY_INVALID"}]}}', 400);
          }
          return _responseWith(const <Map<String, String>>[]);
        }),
      );

      await client.fetchInsights(
        metrics: const <String, Object?>{},
        languageName: 'English',
      );

      expect(usedKeys, <String>['primary', 'fallback']);
    });

    test('surfaces the failure once every key has been rejected', () async {
      int requests = 0;
      final GeminiClient client = GeminiClient(
        apiKey: 'primary,fallback',
        client: MockClient((http.Request request) async {
          requests++;
          return http.Response('quota', 429);
        }),
      );

      await expectLater(
        () => client.fetchInsights(
          metrics: const <String, Object?>{},
          languageName: 'English',
        ),
        throwsA(isA<AgentException>()),
      );
      // One attempt per configured key on the first round, then it gives up.
      expect(requests, 2);
    });

    test('does not rotate on a transient server error', () async {
      final List<String> usedKeys = <String>[];
      final GeminiClient client = GeminiClient(
        apiKey: 'primary,fallback',
        client: MockClient((http.Request request) async {
          usedKeys.add(request.headers['x-goog-api-key']!);
          return http.Response('boom', 503);
        }),
      );

      await expectLater(
        () => client.fetchInsights(
          metrics: const <String, Object?>{},
          languageName: 'English',
        ),
        throwsA(isA<AgentException>()),
      );
      expect(usedKeys, <String>['primary']);
    });
  });
}
