import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/controllers/health_booklet_controller.dart';
import 'package:smart_pet/models/assistant/gemini_client.dart';
import 'package:smart_pet/models/health_ai_summary.dart';
import 'package:smart_pet/models/health_booklet_pdf.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/pet.dart';
import 'package:smart_pet/models/vaccination_booklet.dart';
import 'package:smart_pet/views/health_booklet_actions.dart';

import '../dashboard/dashboard_test.dart' show FakeSharer;

/// Gemini simulé : renvoie [reply] ou lève [failure].
class FakeSummaryLlm implements LlmClient {
  FakeSummaryLlm(this.reply);

  String reply;
  LlmException? failure;
  String? system;
  List<Map<String, Object?>>? contents;
  List<Map<String, Object?>>? tools;

  @override
  Future<LlmTurn> generate({
    required String system,
    required List<Map<String, Object?>> contents,
    required List<Map<String, Object?>> tools,
  }) async {
    this.system = system;
    this.contents = contents;
    this.tools = tools;
    if (failure != null) throw failure!;
    return LlmTurn(content: const {}, text: reply, calls: const []);
  }
}

const _reply = '''```json
{"synthese": "Rex est un chien de 28 kg globalement suivi. Son vaccin contre la rage a expiré.",
 "points_attention": ["Rage expirée depuis le 1er octobre 2026 🐶", "Allergie à l'amoxicilline"],
 "conseils": ["Prendre rendez-vous pour le rappel → rapidement"],
 "questions_veterinaire": ["Faut-il refaire une primo-vaccination ?"]}
```''';

/// Carnet de santé PDF avec synthèse Gemini.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('fr_FR'));

  final now = DateTime(2026, 11, 8, 10);
  final rex = Pet(id: 1, name: 'Rex', species: Species.dog, weightKg: 28, breed: 'Berger',
      identification: '250269812345678', allergies: 'Amoxicilline');
  final health = [
    HealthRecord(petId: 1, type: HealthType.vaccination, date: DateTime(2025, 10, 1),
        medication: 'Rage', vet: 'Dr Ben Ali', cost: 60),
    HealthRecord(petId: 1, type: HealthType.consultation, date: DateTime(2026, 10, 20),
        description: 'Otite', weightKg: 28.1),
    HealthRecord(petId: 2, type: HealthType.consultation, date: DateTime(2026, 10, 20),
        description: 'Autre animal'),
  ];

  group('réponse de Gemini', () {
    test('JSON entouré de ```json, emojis et flèches retirés', () {
      final s = HealthAiSummary.parse(_reply);
      expect(s.overview, startsWith('Rex est un chien de 28 kg'));
      expect(s.attention, ['Rage expirée depuis le 1er octobre 2026', "Allergie à l'amoxicilline"]);
      expect(s.advice, ['Prendre rendez-vous pour le rappel -> rapidement']);
      expect(s.vetQuestions, hasLength(1));
    });

    test('listes limitées à 5, textes trop longs coupés, réponse illisible refusée', () {
      final s = HealthAiSummary.parse(jsonEncode({
        'synthese': 'x' * 2000,
        'points_attention': [for (var i = 0; i < 8; i++) 'point $i', 42, ''],
        'conseils': 'pas une liste',
      }));
      expect(s.overview.length, HealthAiSummary.maxOverview);
      expect(s.overview, endsWith('…'));
      expect(s.attention, ['point 0', 'point 1', 'point 2', 'point 3', 'point 4']);
      expect(s.advice, isEmpty);
      expect(() => HealthAiSummary.parse('Désolé, je ne peux pas.'), throwsFormatException);
      expect(() => HealthAiSummary.parse('{"conseils": []}'), throwsFormatException);
    });
  });

  test('données envoyées : santé de l\'animal seulement, sans numéro de puce', () {
    final data = HealthSummaryWriter.payload(
        pet: rex, booklet: VaccinationBooklet.compute(rex, health, now), health: health, now: now);
    final text = jsonEncode(data);
    expect(text, isNot(contains('250269812345678')));
    expect(text, isNot(contains('Autre animal')));
    expect((data['animal'] as Map)['allergies'], 'Amoxicilline');
    expect((data['dossiers'] as List), hasLength(2));
    expect((data['dossiers'] as List).first, containsPair('description', 'Otite'));
    expect(text, contains('"statut":"Expiré"'));
  });

  test('controller : synthèse ajoutée au PDF, sinon carnet simple et raison', () async {
    final llm = FakeSummaryLlm(_reply);
    final sharer = FakeSharer();
    final controller = HealthBookletController(reportSharer: sharer, clock: () => now, llm: llm);
    expect(controller.aiAvailable, isTrue);

    final withAi = await controller.shareBooklet(rex, health, withAi: true);
    expect(withAi.withAi, isTrue);
    expect(llm.tools, isEmpty);
    expect(llm.system, contains('Ne pose pas de diagnostic'));
    expect(sharer.fileName, 'carnet_sante_rex.pdf');
    final plain = await HealthBookletPdf.build(
        pet: rex, booklet: VaccinationBooklet.compute(rex, health, now), health: health, now: now);
    expect(withAi.bytes.length, greaterThan(plain.length), reason: 'section de synthèse en plus');

    llm.failure = const LlmException(LlmFailure.offline);
    final fallback = await controller.shareBooklet(rex, health, withAi: true);
    expect((fallback.withAi, fallback.aiError), (false, 'Pas de connexion Internet.'));
    expect(String.fromCharCodes(sharer.bytes!.take(4)), '%PDF', reason: 'carnet partagé quand même');

    llm
      ..failure = null
      ..reply = 'Voici la synthèse : tout va bien.';
    expect((await controller.prepareBooklet(rex, health, withAi: true)).aiError,
        'La réponse de Gemini est illisible.');
    expect(HealthBookletController(clock: () => now).aiAvailable, isFalse);
  });

  test('client Gemini : pas de liste d\'outils vide dans la requête', () async {
    late Map body;
    final client = GeminiClient(
      key: 'k',
      models: const ['m'],
      httpClient: MockClient((req) async {
        body = jsonDecode(req.body) as Map;
        return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'role': 'model',
                    'parts': [
                      {'text': '{"synthese": "ok"}'},
                    ],
                  },
                },
              ],
            }),
            200);
      }),
    );
    final summary = await HealthSummaryWriter(client)
        .write(pet: rex, booklet: VaccinationBooklet.compute(rex, health, now), health: health, now: now);
    expect(summary.overview, 'ok');
    expect(body.containsKey('tools'), isFalse);
  });

  testWidgets('écran : choix « Avec synthèse Gemini », puis repli si Gemini échoue',
      (tester) async {
    final llm = FakeSummaryLlm(_reply);
    final sharer = FakeSharer();
    await tester.pumpWidget(Provider.value(
      value: HealthBookletController(reportSharer: sharer, clock: () => now, llm: llm),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => HealthBookletActions.share(context, rex, health),
              child: const Text('Partager'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Partager'));
    await tester.pumpAndSettle();
    expect(find.text('Carnet de santé de Rex'), findsOneWidget);
    expect(find.textContaining('sont envoyées à Google'), findsOneWidget);
    await tester.tap(find.text('Avec synthèse Gemini'));
    await tester.pumpAndSettle();
    expect(sharer.fileName, 'carnet_sante_rex.pdf');
    expect(find.textContaining('indisponible'), findsNothing);

    llm.failure = const LlmException(LlmFailure.unavailable);
    sharer.bytes = null;
    await tester.tap(find.text('Partager'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avec synthèse Gemini'));
    await tester.pumpAndSettle();
    expect(find.text('Synthèse Gemini indisponible (Gemini est momentanément surchargé.) : '
        'carnet partagé sans elle.'), findsOneWidget);
    expect(sharer.bytes, isNotNull);
  });
}
