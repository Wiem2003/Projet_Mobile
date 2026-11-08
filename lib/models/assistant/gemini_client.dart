import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Appel d'outil demandé par le modèle (function calling).
class LlmCall {
  const LlmCall({required this.name, required this.args, this.id});

  final String name;
  final Map<String, Object?> args;

  /// Identifiant à renvoyer avec le résultat.
  final String? id;
}

/// Réponse du modèle : texte et/ou appels d'outils. [content] est le
/// contenu brut, à remettre tel quel dans l'historique (il contient les
/// « thought signatures » exigées par Gemini).
class LlmTurn {
  const LlmTurn({required this.content, required this.text, required this.calls});

  final Map<String, Object?> content;
  final String text;
  final List<LlmCall> calls;
}

enum LlmFailure { notConfigured, offline, unavailable, invalidKey, refused }

class LlmException implements Exception {
  const LlmException(this.failure, [this.detail]);

  final LlmFailure failure;
  final String? detail;

  String get message => switch (failure) {
        LlmFailure.notConfigured => 'Aucune clé Gemini configurée.',
        LlmFailure.offline => 'Pas de connexion Internet.',
        LlmFailure.unavailable => 'Gemini est momentanément surchargé.',
        LlmFailure.invalidKey => 'La clé Gemini est refusée (invalide ou révoquée).',
        LlmFailure.refused => 'Gemini a refusé la requête.',
      };

  @override
  String toString() => detail == null ? message : '$message ($detail)';
}

/// Modèle de langage avec appels d'outils. Remplacé par un faux dans les
/// tests.
abstract interface class LlmClient {
  Future<LlmTurn> generate({
    required String system,
    required List<Map<String, Object?>> contents,
    required List<Map<String, Object?>> tools,
  });
}

/// Client REST de l'API Gemini (generativelanguage.googleapis.com).
///
/// La clé est envoyée dans l'en-tête `x-goog-api-key` (jamais dans l'URL).
/// Si un modèle est surchargé (503/429) ou retiré (404), le suivant de
/// [models] est essayé.
class GeminiClient implements LlmClient {
  GeminiClient({
    required String key,
    List<String> models = defaultModels,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  })  : _apiKey = key,
        models = List.unmodifiable(models),
        _http = httpClient ?? http.Client();

  /// Du plus capable au plus léger.
  static const defaultModels = [
    'gemini-3.5-flash',
    'gemini-flash-latest',
    'gemini-flash-lite-latest',
  ];

  static const _base = 'https://generativelanguage.googleapis.com/v1beta/models';

  final String _apiKey;
  final List<String> models;
  final http.Client _http;
  final Duration timeout;

  /// Modèle de la dernière réponse réussie.
  String? lastModel;

  /// [preferred] en premier, puis les modèles par défaut, sans doublon.
  static List<String> modelsFrom(String preferred) =>
      {if (preferred.isNotEmpty) preferred, ...defaultModels}.toList();

  @override
  Future<LlmTurn> generate({
    required String system,
    required List<Map<String, Object?>> contents,
    required List<Map<String, Object?>> tools,
  }) async {
    if (_apiKey.isEmpty) throw const LlmException(LlmFailure.notConfigured);
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
      'contents': contents,
      // Sans outil (ex. synthèse du carnet de santé) : pas de liste vide,
      // refusée par l'API.
      if (tools.isNotEmpty)
        'tools': [
          {'functionDeclarations': tools},
        ],
      'generationConfig': {'temperature': 0.3},
    });

    LlmException? last;
    for (final model in models) {
      final http.Response res;
      try {
        res = await _http
            .post(
              Uri.parse('$_base/$model:generateContent'),
              headers: {
                'Content-Type': 'application/json',
                'x-goog-api-key': _apiKey,
              },
              body: body,
            )
            .timeout(timeout);
      } on SocketException {
        throw const LlmException(LlmFailure.offline);
      } on http.ClientException {
        throw const LlmException(LlmFailure.offline);
      } on TimeoutException {
        last = const LlmException(LlmFailure.unavailable, 'délai dépassé');
        continue;
      }
      switch (res.statusCode) {
        case 200:
          lastModel = model;
          return _parse(res.body);
        case 401 || 403:
          throw LlmException(LlmFailure.invalidKey, _errorOf(res.body));
        case 400:
          // Clé mal formée, ou requête refusée.
          final detail = _errorOf(res.body);
          throw LlmException(
              detail.contains('API key') ? LlmFailure.invalidKey : LlmFailure.refused,
              detail);
        default: // 404 (modèle retiré), 429, 5xx : modèle suivant.
          last = LlmException(LlmFailure.unavailable,
              '$model : ${res.statusCode} ${_errorOf(res.body)}');
      }
    }
    throw last ?? const LlmException(LlmFailure.unavailable);
  }

  static String _errorOf(String body) {
    try {
      final error = (jsonDecode(body) as Map)['error'] as Map?;
      return (error?['message'] as String?) ?? '';
    } on FormatException {
      return '';
    }
  }

  static LlmTurn _parse(String body) {
    final json = jsonDecode(body) as Map<String, Object?>;
    final candidates = (json['candidates'] as List?) ?? const [];
    final content = candidates.isEmpty
        ? null
        : (candidates.first as Map)['content'] as Map<String, Object?>?;
    if (content == null) {
      // Réponse bloquée par les filtres de sécurité.
      const text = 'Je ne peux pas répondre à cette demande.';
      return const LlmTurn(
        content: {
          'role': 'model',
          'parts': [
            {'text': text},
          ],
        },
        text: text,
        calls: [],
      );
    }
    final parts = (content['parts'] as List?) ?? const [];
    final text = StringBuffer();
    final calls = <LlmCall>[];
    for (final part in parts.cast<Map>()) {
      if (part['thought'] == true) continue; // Réflexion interne.
      if (part['text'] is String) text.write(part['text']);
      final call = part['functionCall'] as Map?;
      if (call != null) {
        calls.add(LlmCall(
          name: call['name'] as String,
          args: Map<String, Object?>.from((call['args'] as Map?) ?? const {}),
          id: call['id'] as String?,
        ));
      }
    }
    return LlmTurn(
      content: {...content, 'role': 'model'},
      text: text.toString().trim(),
      calls: calls,
    );
  }
}
