import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smart_pet/controllers/activities_controller.dart';
import 'package:smart_pet/controllers/assistant_tools.dart';
import 'package:smart_pet/controllers/feeding_controller.dart';
import 'package:smart_pet/controllers/gemini_assistant_controller.dart';
import 'package:smart_pet/controllers/health_controller.dart';
import 'package:smart_pet/controllers/pets_controller.dart';
import 'package:smart_pet/controllers/reminder_assistant_controller.dart';
import 'package:smart_pet/controllers/reminders_controller.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/models/activities_model.dart';
import 'package:smart_pet/models/assistant/gemini_client.dart';
import 'package:smart_pet/models/feeding_model.dart';
import 'package:smart_pet/models/health_model.dart';
import 'package:smart_pet/models/pet_repository.dart';
import 'package:smart_pet/models/pets_model.dart';
import 'package:smart_pet/models/reminders_model.dart';
import 'package:smart_pet/models/sqlite_activity_repository.dart';
import 'package:smart_pet/models/sqlite_feeding_repository.dart';
import 'package:smart_pet/models/sqlite_health_repository.dart';
import 'package:smart_pet/models/sqlite_pet_repository.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';

import '../reminders/test_helpers.dart';

/// Gemini simulé : renvoie les réponses prévues et garde les requêtes.
class FakeLlm implements LlmClient {
  final script = <LlmTurn Function()>[];
  final requests = <List<Map<String, Object?>>>[];
  LlmException? failure;

  @override
  Future<LlmTurn> generate({
    required String system,
    required List<Map<String, Object?>> contents,
    required List<Map<String, Object?>> tools,
  }) async {
    if (failure != null) throw failure!;
    requests.add([...contents]);
    return script.removeAt(0)();
  }
}

LlmTurn say(String text) => LlmTurn(
      content: {
        'role': 'model',
        'parts': [
          {'text': text},
        ],
      },
      text: text,
      calls: const [],
    );

LlmTurn call(String name, Map<String, Object?> args) => LlmTurn(
      content: {
        'role': 'model',
        'parts': [
          {
            'functionCall': {'name': name, 'args': args, 'id': 'id_$name'},
            'thoughtSignature': 'sig',
          },
        ],
      },
      text: '',
      calls: [LlmCall(name: name, args: args, id: 'id_$name')],
    );

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late AppDatabase db;
  late RemindersController reminders;
  late AssistantTools tools;
  late FakeLlm llm;
  late GeminiAssistantController bot;
  final clock = FakeClock(DateTime(2026, 11, 4, 14)); // mercredi

  setUp(() async {
    db = memoryDatabase();
    final petRepo = SqlitePetRepository(db, clock: clock.call);
    final directory = PetRepositoryDirectory(petRepo);
    final petsModel = PetsModel(clock: clock.call);
    await PetsController(
            model: petsModel, repository: petRepo, photos: FakePhotoStore())
        .seedDemo();
    reminders = RemindersController(
      model: RemindersModel(clock: clock.call),
      repository: SqliteReminderRepository(db, clock: clock.call),
      notifier: FakeNotifier(),
      pets: directory,
      refreshEvery: null,
    );
    await reminders.load();
    final health = HealthController(
        model: HealthModel(clock: clock.call),
        repository: SqliteHealthRepository(db, clock: clock.call),
        pets: directory,
        reminders: reminders);
    await health.load();
    await health.seedDemo();
    final feeding = FeedingController(
        model: FeedingModel(clock: clock.call),
        repository: SqliteFeedingRepository(db, clock: clock.call),
        pets: directory);
    await feeding.load();
    await feeding.seedDemo();
    final activities = ActivitiesController(
        model: ActivitiesModel(clock: clock.call),
        repository: SqliteActivityRepository(db, clock: clock.call),
        pets: directory);
    await activities.load();
    await activities.seedDemo();

    tools = AssistantTools(
      reminders: reminders,
      pets: petsModel,
      health: health.model,
      feeding: feeding.model,
      activities: activities.model,
    );
    llm = FakeLlm();
    bot = GeminiAssistantController(
      llm: llm,
      tools: tools,
      offline: ReminderAssistantController(reminders, replyDelay: Duration.zero),
    );
  });
  tearDown(() async {
    bot.dispose();
    reminders.dispose();
    await db.close();
  });

  String lastText() => bot.model.messages.last.text;

  test('créer un rappel via un outil, réponse et carte', () async {
    llm.script
      ..add(() => call('create_reminder', {
            'title': 'Vermifuge',
            'type': 'deworming',
            'date_time': '2026-11-07T09:00',
            'pet_name': 'rex',
          }))
      ..add(() => say('C\'est noté : **Vermifuge** pour Rex samedi à 9h.'));
    await bot.send('Rappelle-moi le vermifuge de Rex samedi');

    final created = reminders.model.all.where((r) => r.title == 'Vermifuge');
    expect(created.single.dueDate, DateTime(2026, 11, 7, 9));
    expect(lastText(), 'C\'est noté : Vermifuge pour Rex samedi à 9h.',
        reason: 'Markdown retiré');
    expect(bot.model.messages.last.reminders.single.title, 'Vermifuge');

    // Le résultat de l'outil est renvoyé avec l'id de l'appel.
    final second = llm.requests[1];
    expect(second.first['parts'], [
      {'text': 'Rappelle-moi le vermifuge de Rex samedi'},
    ]);
    expect((second[1]['parts'] as List).first['thoughtSignature'], 'sig');
    final response = (second.last['parts'] as List).first['functionResponse'] as Map;
    expect(response['id'], 'id_create_reminder');
    expect((response['response'] as Map)['created']['pet'], 'Rex');
  });

  test('erreurs métier et animal inconnu renvoyés au modèle', () async {
    final unknown = await tools.run('get_health_summary', {'pet_name': 'Médor'});
    expect(unknown.response['error'], contains('Animal inconnu'));
    expect(unknown.response['error'], contains('Rex'));
    final empty = await tools.run('create_reminder',
        {'title': '', 'type': 'other', 'date_time': '2026-11-10T09:00'});
    expect(empty.response['error'], isNotNull, reason: 'T02 : titre requis');
    final badDate = await tools.run('create_reminder',
        {'title': 'X', 'type': 'other', 'date_time': 'samedi'});
    expect(badDate.response['error'], contains('date_time invalide'));
  });

  test('lectures : santé, repas, activités, animaux', () async {
    final health =
        (await tools.run('get_health_summary', {'pet_name': 'Rex'})).response;
    expect(health['consultations'], 2);
    expect(health['medical_spending_dt'], 370);
    expect(health['weight_change_kg'], closeTo(1.6, 1e-9));
    expect((health['upcoming_deadlines'] as List), isNotEmpty);

    final feeding = (await tools.run('get_feeding_summary', {})).response;
    expect(feeding['month'], '2026-11');
    expect(feeding['spending_dt'], greaterThan(0));

    final act = (await tools.run(
            'get_activity_summary', {'pet_name': 'Rex', 'period': '7_days'}))
        .response;
    expect(act['weekly_distance_km_last_7_days'], greaterThan(0));

    final pets = (await tools.run('get_pets', {})).response['pets'] as List;
    expect(pets.map((p) => p['name']), ['Coco', 'Mia', 'Rex']);
    expect(pets.last['age'], isNotNull);

    final overdue = await tools.run('get_reminders', {'scope': 'upcoming'});
    expect(overdue.response['count'], greaterThan(0));
    expect(overdue.cards, isNotEmpty);
  });

  test('suppression : seulement après un « oui » de l\'utilisateur', () async {
    final target = reminders.model.all.first;
    final id = target.id;

    // Le modèle essaie de supprimer directement : refusé par l'app.
    llm.script
      ..add(() => call('delete_reminder', {'reminder_id': id, 'confirmed': true}))
      ..add(() => say('Voulez-vous vraiment supprimer ce rappel ?'));
    await bot.send('Supprime ce rappel');
    expect(reminders.model.byId(id), isNotNull);
    expect(bot.model.messages.last.suggestions, ['Oui, supprimer', 'Non']);

    // L'utilisateur confirme : suppression effectuée.
    llm.script
      ..add(() => call('delete_reminder', {'reminder_id': id, 'confirmed': true}))
      ..add(() => say('Rappel supprimé.'));
    await bot.send('Oui, supprimer');
    expect(reminders.model.byId(id), isNull);
    expect(lastText(), 'Rappel supprimé.');
  });

  test('Gemini indisponible : réponse hors ligne, historique intact', () async {
    llm.failure = const LlmException(LlmFailure.offline);
    await bot.send('Qu\'est-ce qui est en retard ?');
    expect(lastText(), startsWith('📴 Pas de connexion Internet.'));
    expect(lastText(), contains('mode hors ligne'));
    expect(bot.modeLabel, contains('hors ligne'));

    llm
      ..failure = null
      ..script.add(() => say('Rien en retard.'));
    await bot.send('Et maintenant ?');
    expect(lastText(), 'Rien en retard.');
    expect(bot.modeLabel, startsWith('Gemini'));
    expect(llm.requests.single, hasLength(1),
        reason: 'la question échouée n\'est pas restée dans l\'historique');
  });

  test('nouvelle conversation : historique effacé', () async {
    llm.script.add(() => say('Bonjour !'));
    await bot.send('Bonjour');
    bot.reset();
    expect(bot.model.messages.single.text, contains('propulsé par Gemini'));
    llm.script.add(() => say('Re-bonjour'));
    await bot.send('Salut');
    expect(llm.requests.last, hasLength(1));
  });
}
