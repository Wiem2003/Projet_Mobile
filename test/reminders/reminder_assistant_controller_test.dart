import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/controllers/reminder_assistant_controller.dart';
import 'package:smart_pet/controllers/reminders_controller.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/models/assistant/chat_message.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminders_model.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';

import 'test_helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late AppDatabase db;
  late FakeClock clock;
  late SqliteReminderRepository repo;
  late RemindersController list;
  late ReminderAssistantController bot;

  setUp(() async {
    db = memoryDatabase();
    clock = FakeClock(DateTime(2026, 10, 29, 14)); // jeudi
    repo = SqliteReminderRepository(db, clock: clock.call);
    list = RemindersController(
      model: RemindersModel(clock: clock.call),
      repository: repo,
      notifier: FakeNotifier(),
      pets: const DemoPetDirectory(),
      refreshEvery: null,
    );
    await list.load();
    bot = ReminderAssistantController(list, replyDelay: Duration.zero);
  });

  tearDown(() async {
    bot.dispose();
    list.dispose();
    list.model.dispose();
    await db.close();
  });

  Future<Reminder> seed(String title, DateTime due,
      {int? petId = rexId,
      ReminderType type = ReminderType.deworming,
      ReminderRepeat repeat = ReminderRepeat.none}) async {
    final r = await repo.create(Reminder(
        petId: petId, title: title, type: type, dueDate: due, repeat: repeat));
    await list.load();
    return r;
  }

  /// Envoie un message et renvoie la réponse de l'assistant.
  Future<ChatMessage> say(String text) async {
    await bot.send(text);
    final last = bot.model.messages.last;
    expect(last.fromUser, isFalse);
    return last;
  }

  test('message d\'accueil avec suggestions', () {
    expect(bot.model.messages.single.text, contains('assistant Rappels'));
    expect(bot.model.suggestions, contains('Aide'));
    expect(bot.model.typing, isFalse);
  });

  test('créer : confirmation, enregistrement SQLite, puis annuler', () async {
    final ask = await say('Rappelle-moi le vermifuge de Rex demain à 8h');
    expect(ask.text, contains('Je crée ce rappel ?'));
    expect(ask.suggestions, ['Oui', 'Non']);
    expect(await repo.getAll(), isEmpty, reason: 'rien avant confirmation');

    final done = await say('Oui');
    expect(done.text, contains('C\'est noté'));
    final saved = (await repo.getAll()).single;
    expect(saved.title, 'Vermifuge');
    expect(saved.petId, rexId);
    expect(saved.dueDate, DateTime(2026, 10, 30, 8));
    expect(list.model.upcoming.single.id, saved.id, reason: 'écran Rappels à jour');

    expect((await say('annuler')).text, contains('annulé'));
    expect(await repo.getAll(), isEmpty);
    expect((await say('annuler')).text, contains('rien à annuler'));
  });

  test('créer sans date : l\'assistant demande « pour quand »', () async {
    final ask = await say('Rappelle-moi d\'acheter des croquettes');
    expect(ask.text, contains('Pour quand'));
    expect((await say('samedi')).text, contains('Je crée ce rappel ?'));
    await say('oui');
    final saved = (await repo.getAll()).single;
    expect(saved.title, 'Acheter des croquettes');
    expect(saved.type, ReminderType.purchase);
    expect(saved.dueDate, DateTime(2026, 10, 31, 9));
  });

  test('vaccin : répétition annuelle par défaut', () async {
    await say('Programme un vaccin pour Mia le 15/11');
    await say('oui');
    expect((await repo.getAll()).single.repeat, ReminderRepeat.yearly);
  });

  test('refus, date passée et doublon', () async {
    await say('Rappelle-moi le vermifuge demain à 8h');
    expect((await say('non')).text, contains('j\'annule'));
    expect(await repo.getAll(), isEmpty);

    final past = await say('Rappelle-moi le vermifuge aujourd\'hui à 8h');
    expect(past.text, contains('déjà passée'));
    expect(past.isError, isTrue);

    await seed('Vermifuge', DateTime(2026, 10, 30, 8), petId: null);
    await say('Rappelle-moi le vermifuge demain à 8h');
    final dup = await say('oui');
    expect(dup.isError, isTrue);
    expect(dup.text, contains('identique'));
    expect(await repo.getAll(), hasLength(1));
  });

  test('une nouvelle question remplace la question en attente', () async {
    await seed('Antipuces', DateTime(2026, 10, 27, 19),
        petId: miaId, type: ReminderType.treatment);
    await say('Rappelle-moi d\'acheter des croquettes');
    final reply = await say('Qu\'est-ce qui est en retard ?');
    expect(reply.text, contains('1 rappel en retard'));
    expect(reply.reminders.single.title, 'Antipuces');
  });

  group('consulter', () {
    setUp(() async {
      await seed('Vermifuge', DateTime(2026, 10, 30, 8));
      await seed('Antipuces', DateTime(2026, 10, 27, 19),
          petId: miaId, type: ReminderType.treatment);
      await seed('Rappel vaccin CHPPi', DateTime(2026, 11, 8, 9),
          type: ReminderType.vaccination);
      await seed('Détartrage', DateTime(2026, 10, 29, 23),
          type: ReminderType.other);
    });

    test('demain, aujourd\'hui, semaine, retard', () async {
      final tomorrow = await say('Qu\'est-ce qui est prévu demain ?');
      expect(tomorrow.text, startsWith('Demain : 1 rappel'));
      expect(tomorrow.reminders.single.title, 'Vermifuge');

      final today = await say('Quoi de prévu aujourd\'hui ?');
      expect(today.reminders.single.title, 'Détartrage');

      final week = await say('Quoi de prévu cette semaine ?');
      expect(week.reminders.map((r) => r.title), ['Détartrage', 'Vermifuge']);

      expect((await say('Quoi en retard pour Rex ?')).text,
          contains('Rien en retard pour Rex'));
    });

    test('prochain vaccin et bilan', () async {
      final next = await say('Prochain vaccin de Rex ?');
      expect(next.text, contains('Rappel vaccin CHPPi'));
      expect(next.text, contains('dans 10 jours'));

      final summary = await say('Fais le point');
      expect(summary.text, contains('1 rappel en retard'));
      expect(summary.text, contains('1 aujourd\'hui'));
      expect(summary.suggestions, contains('Qu\'est-ce qui est en retard ?'));
    });

    test('incompris : propose des exemples', () async {
      final r = await say('Il fait beau');
      expect(r.text, contains('pas bien compris'));
      expect(r.suggestions, isNotEmpty);
    });
  });

  test('terminer : choix entre plusieurs rappels, répétition, annuler',
      () async {
    final rex = await seed('Vermifuge', DateTime(2026, 10, 30, 8),
        repeat: ReminderRepeat.monthly);
    await seed('Vermifuge', DateTime(2026, 11, 3, 8), petId: miaId);

    final ask = await say('J\'ai donné le vermifuge');
    expect(ask.text, contains('Lequel'));
    expect(ask.suggestions.first, startsWith('1. Vermifuge · Rex'));

    final done = await say(ask.suggestions.first);
    expect(done.text, contains('marqué comme fait'));
    expect(done.text, contains('Prochain rappel'), reason: 'mensuel');
    expect((await repo.getById(rex.id!)).isDone, isTrue);

    await say('annuler');
    expect((await repo.getById(rex.id!)).isDone, isFalse);
    expect(await repo.getAll(), hasLength(2), reason: 'occurrence retirée');
  });

  test('terminer directement quand un seul rappel correspond', () async {
    final r = await seed('Vermifuge', DateTime(2026, 10, 30, 8));
    await seed('Vermifuge', DateTime(2026, 11, 3, 8), petId: miaId);
    await say('J\'ai donné le vermifuge à Rex');
    expect((await repo.getById(r.id!)).isDone, isTrue);
  });

  test('« Lequel ? » : une réponse incomprise repose la question', () async {
    await seed('Vermifuge', DateTime(2026, 10, 30, 8));
    final mia = await seed('Vermifuge', DateTime(2026, 11, 3, 8), petId: miaId);
    await say('Supprime le vermifuge');

    final again = await say('oui');
    expect(again.text, contains('pas compris votre réponse'));
    expect(again.reminders, hasLength(2), reason: 'les choix sont remontrés');

    final confirm = await say('le 2');
    expect(confirm.text, contains('Supprimer définitivement'));
    expect((await say('oui')).text, contains('supprimé'));
    expect((await repo.getAll()).map((r) => r.id), isNot(contains(mia.id)));
  });

  test('questions des autres modules : orientées vers le bon onglet', () async {
    expect((await say('Combien j\'ai dépensé chez le véto ?')).text,
        contains('onglet Santé'));
    expect((await say('Quel est le poids de Rex ?')).text,
        contains('courbe d\'évolution du poids'));
    expect((await say('Quelle distance a fait Rex ?')).text,
        contains('onglet Activité'));
  });

  test('T07 : reporter à une date, d\'une durée, ou après question', () async {
    final a = await seed('Antipuces', DateTime(2026, 10, 27, 19),
        petId: miaId, type: ReminderType.treatment);
    final v = await seed('Vermifuge', DateTime(2026, 10, 30, 8));

    final r1 = await say('Reporte l\'antipuces à lundi');
    expect(r1.text, contains('reporté'));
    final moved = await repo.getById(a.id!);
    expect(moved.dueDate, DateTime(2026, 11, 2, 19), reason: 'heure gardée');
    expect(moved.status, ReminderStatus.postponed);

    await say('Décale le vermifuge de 3 jours');
    expect((await repo.getById(v.id!)).dueDate, DateTime(2026, 11, 2, 8));

    expect((await say('Reporte le vermifuge')).text, contains('À quand'));
    await say('Dans une semaine');
    expect((await repo.getById(v.id!)).dueDate, DateTime(2026, 11, 5, 8));
  });

  test('supprimer avec confirmation', () async {
    final r = await seed('Contrôle médical', DateTime(2026, 11, 20, 9),
        type: ReminderType.checkup);
    final ask = await say('Supprime le contrôle');
    expect(ask.text, contains('Supprimer définitivement'));
    await say('Non');
    expect(await repo.getAll(), hasLength(1));

    await say('Supprime le contrôle');
    await say('Oui, supprimer');
    expect(await repo.getAll(), isEmpty);
    expect(list.model.byId(r.id), isNull);
  });

  test('rappel introuvable', () async {
    await seed('Vermifuge', DateTime(2026, 10, 30, 8));
    final r = await say('J\'ai donné le shampoing');
    expect(r.text, contains('aucun rappel en cours correspondant'));
  });

  test('nouvelle conversation', () async {
    await say('Bonjour');
    expect(bot.model.messages, hasLength(3));
    bot.reset();
    expect(bot.model.messages, hasLength(1));
  });
}
