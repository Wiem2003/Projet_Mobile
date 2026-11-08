import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smart_pet/controllers/assistant_tools.dart';
import 'package:smart_pet/controllers/gemini_assistant_controller.dart';
import 'package:smart_pet/controllers/reminder_assistant_controller.dart';
import 'package:smart_pet/controllers/reminders_controller.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/models/activities_model.dart';
import 'package:smart_pet/models/assistant/gemini_client.dart';
import 'package:smart_pet/models/feeding_model.dart';
import 'package:smart_pet/models/health_model.dart';
import 'package:smart_pet/models/pets_model.dart';
import 'package:smart_pet/models/reminders_model.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';

import '../reminders/test_helpers.dart';
import 'gemini_assistant_controller_test.dart' show FakeLlm, call, say;

/// Comportement de l'assistant Gemini dans les cas limites : modèle qui
/// boucle, conversation longue, lenteur, erreurs du client HTTP.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late AppDatabase db;
  late RemindersController reminders;
  late FakeLlm llm;
  final clock = FakeClock(DateTime(2026, 11, 4, 14));

  setUp(() async {
    db = memoryDatabase();
    reminders = RemindersController(
      model: RemindersModel(clock: clock.call),
      repository: SqliteReminderRepository(db, clock: clock.call),
      notifier: FakeNotifier(),
      pets: const DemoPetDirectory(),
      refreshEvery: null,
    );
    await reminders.load();
    llm = FakeLlm();
  });
  tearDown(() async {
    reminders.dispose();
    await db.close();
  });

  GeminiAssistantController bot({Duration budget = const Duration(seconds: 45)}) =>
      GeminiAssistantController(
        llm: llm,
        answerBudget: budget,
        offline: ReminderAssistantController(reminders, replyDelay: Duration.zero),
        tools: AssistantTools(
          reminders: reminders,
          pets: PetsModel(clock: clock.call)..setPets(const []),
          health: HealthModel(clock: clock.call),
          feeding: FeedingModel(clock: clock.call),
          activities: ActivitiesModel(clock: clock.call),
        ),
      );

  test('modèle qui appelle des outils sans fin : arrêt après 6 tours', () async {
    final b = bot();
    for (var i = 0; i < 10; i++) {
      llm.script.add(() => call('get_pets', {}));
    }
    await b.send('Boucle');
    expect(b.model.messages.last.text, contains('pas réussi à terminer'));
    expect(llm.requests, hasLength(6));
    b.dispose();
  });

  test('réponse vide : message par défaut', () async {
    final b = bot();
    llm.script.add(() => say(''));
    await b.send('?');
    expect(b.model.messages.last.text, contains('pas de réponse'));
    b.dispose();
  });

  test('conversation longue : historique limité, commence par une question',
      () async {
    final b = bot();
    for (var i = 0; i < 30; i++) {
      llm.script
        ..add(() => call('get_pets', {}))
        ..add(() => say('Réponse $i'));
      await b.send('Question $i');
    }
    final last = llm.requests.last;
    // 40 après la réponse précédente, + question, appel d'outil et résultat.
    expect(last.length, lessThanOrEqualTo(GeminiAssistantController.maxHistory + 3));
    final first = last.first;
    expect(first['role'], 'user');
    expect(((first['parts'] as List).first as Map).containsKey('text'), isTrue,
        reason: 'jamais un résultat d\'outil isolé en tête');
    expect(b.model.messages.last.text, 'Réponse 29');
    b.dispose();
  });

  test('budget de temps dépassé : l\'assistant hors ligne répond', () async {
    final b = bot(budget: Duration.zero);
    llm.script
      ..add(() => call('get_pets', {}))
      ..add(() => say('jamais affiché'));
    await b.send('Qu\'est-ce qui est en retard ?');
    expect(b.model.messages.last.text, startsWith('📴 Gemini est momentanément surchargé.'));
    expect(b.modeLabel, contains('hors ligne'));
    b.dispose();
  });

  group('GeminiClient', () {
    const contents = [
      {
        'role': 'user',
        'parts': [
          {'text': 'x'},
        ],
      },
    ];

    test('délai dépassé sur tous les modèles : indisponible', () async {
      final client = GeminiClient(
        key: 'k',
        models: const ['a', 'b'],
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
          client.generate(system: '', contents: contents, tools: const []),
          throwsA(isA<LlmException>()
              .having((e) => e.failure, 'failure', LlmFailure.unavailable)
              .having((e) => e.detail, 'detail', 'délai dépassé')));
    });

    test('corps d\'erreur illisible : erreur quand même signalée', () async {
      final client = GeminiClient(
          key: 'k',
          models: const ['a'],
          httpClient: MockClient((_) async => http.Response('<html>', 400)));
      await expectLater(
          client.generate(system: '', contents: contents, tools: const []),
          throwsA(isA<LlmException>()
              .having((e) => e.failure, 'failure', LlmFailure.refused)));
    });

    test('messages d\'erreur en français', () {
      for (final f in LlmFailure.values) {
        expect(LlmException(f).message, isNotEmpty);
      }
      expect(const LlmException(LlmFailure.offline).toString(),
          'Pas de connexion Internet.');
      expect(const LlmException(LlmFailure.unavailable, 'a : 503').toString(),
          'Gemini est momentanément surchargé. (a : 503)');
    });
  });
}
