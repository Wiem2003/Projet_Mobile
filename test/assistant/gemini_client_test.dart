import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_pet/models/assistant/gemini_client.dart';

void main() {
  const tools = [
    {'name': 'get_pets', 'description': 'x'},
  ];
  final contents = [
    {
      'role': 'user',
      'parts': [
        {'text': 'Bonjour'},
      ],
    },
  ];

  http.Response ok(List<Map<String, Object?>> parts) => http.Response(
      jsonEncode({
        'candidates': [
          {
            'content': {'role': 'model', 'parts': parts},
          },
        ],
      }),
      200);

  test('requête : clé dans l\'en-tête, outils et consignes envoyés', () async {
    late http.Request sent;
    final client = GeminiClient(
      key: 'secret',
      models: const ['m1'],
      httpClient: MockClient((req) async {
        sent = req;
        return ok([
          {'text': 'réflexion', 'thought': true},
          {'text': 'Bonjour !'},
          {
            'functionCall': {
              'name': 'get_pets',
              'args': {'x': 1},
              'id': 'call_1',
            },
            'thoughtSignature': 'sig',
          },
        ]);
      }),
    );
    final turn = await client.generate(system: 'Consigne', contents: contents, tools: tools);

    expect(sent.url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/m1:generateContent');
    expect(sent.url.toString(), isNot(contains('secret')));
    expect(sent.headers['x-goog-api-key'], 'secret');
    final body = jsonDecode(sent.body) as Map;
    expect(body['systemInstruction']['parts'][0]['text'], 'Consigne');
    expect(body['tools'][0]['functionDeclarations'][0]['name'], 'get_pets');

    expect(turn.text, 'Bonjour !', reason: 'réflexion interne ignorée');
    expect(turn.calls.single.name, 'get_pets');
    expect(turn.calls.single.id, 'call_1');
    expect(turn.calls.single.args, {'x': 1});
    // Contenu brut conservé (signature à renvoyer).
    expect((turn.content['parts'] as List).last['thoughtSignature'], 'sig');
    expect(client.lastModel, 'm1');
  });

  test('modèle surchargé ou retiré : le suivant est essayé', () async {
    final tried = <String>[];
    final client = GeminiClient(
      key: 'k',
      models: const ['a', 'b', 'c'],
      httpClient: MockClient((req) async {
        final model = req.url.pathSegments.last.split(':').first;
        tried.add(model);
        return switch (model) {
          'a' => http.Response('{"error":{"message":"high demand"}}', 503),
          'b' => http.Response('{"error":{"message":"gone"}}', 404),
          _ => ok([
              {'text': 'OK'},
            ]),
        };
      }),
    );
    final turn = await client.generate(system: '', contents: contents, tools: tools);
    expect(tried, ['a', 'b', 'c']);
    expect(turn.text, 'OK');
    expect(client.lastModel, 'c');
  });

  test('erreurs : clé refusée, tous surchargés, hors ligne, sans clé', () async {
    GeminiClient with_(http.Response Function() res) => GeminiClient(
        key: 'k', models: const ['a', 'b'], httpClient: MockClient((_) async => res()));
    Future<LlmFailure> failure(GeminiClient c) async {
      try {
        await c.generate(system: '', contents: contents, tools: tools);
      } on LlmException catch (e) {
        return e.failure;
      }
      fail('exception attendue');
    }

    expect(await failure(with_(() => http.Response('{}', 403))), LlmFailure.invalidKey);
    expect(
        await failure(with_(() => http.Response(
            '{"error":{"message":"API key not valid"}}', 400))),
        LlmFailure.invalidKey);
    expect(await failure(with_(() => http.Response('{}', 503))), LlmFailure.unavailable);
    expect(
        await failure(GeminiClient(
            key: 'k',
            httpClient: MockClient((_) async => throw http.ClientException('réseau')))),
        LlmFailure.offline);
    expect(await failure(GeminiClient(key: '')), LlmFailure.notConfigured);
  });

  test('réponse bloquée : message de refus', () async {
    final client = GeminiClient(
        key: 'k',
        models: const ['a'],
        httpClient: MockClient((_) async => http.Response('{"candidates":[]}', 200)));
    final turn = await client.generate(system: '', contents: contents, tools: tools);
    expect(turn.text, contains('ne peux pas répondre'));
    expect(turn.calls, isEmpty);
  });

  test('modèle préféré puis modèles par défaut, sans doublon', () {
    expect(GeminiClient.modelsFrom('gemini-x').first, 'gemini-x');
    expect(GeminiClient.modelsFrom(GeminiClient.defaultModels.first),
        GeminiClient.defaultModels);
    expect(GeminiClient.modelsFrom(''), GeminiClient.defaultModels);
  });
}
