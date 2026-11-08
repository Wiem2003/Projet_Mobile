import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/models/assistant/assistant_parser.dart';
import 'package:smart_pet/models/reminder.dart';

import 'test_helpers.dart';

void main() {
  // Jeudi 29 octobre 2026, 14 h.
  final now = DateTime(2026, 10, 29, 14);
  late AssistantParser parser;

  setUp(() async {
    parser = AssistantParser(
        now: now, pets: await const DemoPetDirectory().getPets());
  });

  T parse<T extends AssistantCommand>(String text) {
    final c = parser.parse(text);
    expect(c, isA<T>(), reason: text);
    return c as T;
  }

  DateTime? when(String text) => parser.parseWhen(text)?.resolve();

  group('normalisation', () {
    test('sans accents, même longueur', () {
      const s = 'Rappelle-moi l’Échéance à 9h';
      expect(normalizeFr(s), "rappelle-moi l'echeance a 9h");
      expect(normalizeFr(s).length, s.length);
    });
  });

  group('dates', () {
    test('mots-clés et jours de la semaine', () {
      expect(when('demain'), DateTime(2026, 10, 30, 9));
      expect(when('après-demain à 18h30'), DateTime(2026, 10, 31, 18, 30));
      expect(when('ce soir'), DateTime(2026, 10, 29, 19));
      expect(when('vendredi'), DateTime(2026, 10, 30, 9));
      expect(when('jeudi'), DateTime(2026, 11, 5, 9), reason: 'pas aujourd\'hui');
      expect(when('lundi prochain à 7h du soir'), DateTime(2026, 11, 2, 19));
    });

    test('relatives', () {
      expect(when('dans 3 jours'), DateTime(2026, 11, 1, 9));
      expect(when('dans une semaine'), DateTime(2026, 11, 5, 9));
      expect(when('dans 1 mois'), DateTime(2026, 11, 29, 9));
      expect(when('dans 2 heures'), DateTime(2026, 10, 29, 16));
    });

    test('explicites', () {
      expect(when('le 20/11 à 10h30'), DateTime(2026, 11, 20, 10, 30));
      expect(when('le 3/10'), DateTime(2027, 10, 3, 9), reason: 'passée');
      expect(when('le 1er décembre'), DateTime(2026, 12, 1, 9));
      expect(when('15 janvier 2027 à midi'), DateTime(2027, 1, 15, 12));
      expect(when('le 31/02'), isNull);
    });

    test('heure seule : aujourd\'hui ou demain', () {
      expect(when('à 18h'), DateTime(2026, 10, 29, 18));
      expect(when('à 8h'), DateTime(2026, 10, 30, 8));
    });

    test('aucune date', () => expect(when('le vermifuge'), isNull));
  });

  group('consulter', () {
    test('jour, retard, prochain, semaine', () {
      final d = parse<ListCommand>('Qu\'est-ce qui est prévu demain ?');
      expect((d.scope, d.day), (ListScope.day, DateTime(2026, 10, 30)));

      final o = parse<ListCommand>('Quoi en retard pour Mia ?');
      expect((o.scope, o.petId), (ListScope.overdue, miaId));

      final n = parse<ListCommand>('Prochain vaccin de Rex ?');
      expect((n.scope, n.petId, n.type),
          (ListScope.next, rexId, ReminderType.vaccination));

      expect(parse<ListCommand>('Quoi de prévu cette semaine ?').scope,
          ListScope.week);
      expect(parse<ListCommand>('Mes rappels').scope, ListScope.upcoming);
      expect(parse<ListCommand>('Historique').scope, ListScope.done);
      expect(parse<ListCommand>('Combien de rappels en retard ?').scope,
          ListScope.overdue);
      expect(parse<ListCommand>('les rappels de mon chien').petId, rexId);
    });

    test('bilan, aide, politesse, annuler, inconnu', () {
      parse<SummaryCommand>('Fais le point');
      parse<HelpCommand>('Aide');
      parse<HelpCommand>('Qu\'est-ce que tu sais faire ?');
      parse<GreetingCommand>('Bonjour !');
      parse<ThanksCommand>('Merci beaucoup');
      parse<UndoCommand>('Annuler');
      parse<UnknownCommand>('Il fait beau');
    });
  });

  group('créer', () {
    test('titre, animal, type, date', () {
      final c = parse<CreateCommand>(
          'Rappelle-moi le vermifuge de Rex vendredi à 8h');
      expect(c.title, 'Vermifuge');
      expect(c.type, ReminderType.deworming);
      expect(c.petId, rexId);
      expect(c.when!.resolve(), DateTime(2026, 10, 30, 8));
    });

    test('le titre garde les mots utiles et les accents', () {
      final c = parse<CreateCommand>(
          'Rappelle-moi d\'acheter des croquettes samedi');
      expect(c.title, 'Acheter des croquettes');
      expect(c.type, ReminderType.purchase);
      expect(c.petId, isNull);
      expect(c.when!.resolve(), DateTime(2026, 10, 31, 9));

      final v = parse<CreateCommand>(
          'Crée un rappel : visite chez le toiletteur dans 3 jours à 7h du soir');
      expect(v.title, 'Visite chez le toiletteur');
      expect(v.type, ReminderType.other);
      expect(v.when!.resolve(), DateTime(2026, 11, 1, 19));
    });

    test('répétition et date numérique', () {
      final c = parse<CreateCommand>(
          'Programme un vaccin pour Mia le 15/11 à 10h30 chaque année');
      expect(c.title, 'Vaccin');
      expect(c.petId, miaId);
      expect(c.repeat, ReminderRepeat.yearly);
      expect(c.when!.resolve(), DateTime(2026, 11, 15, 10, 30));
    });

    test('dans 2 heures', () {
      final c = parse<CreateCommand>(
          'Rappelle-moi dans 2 heures de donner la pipette à Mia');
      expect(c.title, 'Donner la pipette');
      expect(c.type, ReminderType.treatment);
      expect(c.when!.resolve(), DateTime(2026, 10, 29, 16));
    });

    test('fautes de frappe et forme courte « rappel … date »', () {
      final typo =
          parse<CreateCommand>('rapelle moi le vermifuge de rex vendredi');
      expect((typo.title, typo.petId), ('Vermifuge', rexId));
      parse<CreateCommand>('Rappel moi de peser Mia demain');

      final terse = parse<CreateCommand>('rappel vaccin rex 15/12 10h');
      expect((terse.title, terse.petId), ('Vaccin', rexId));
      expect(terse.when!.resolve(), DateTime(2026, 12, 15, 10));
      // Sans date, ou sous forme de question : c'est une recherche.
      parse<ListCommand>('rappel vaccin');
      parse<ListCommand>('rappel de Mia demain ?');
    });

    test('sans date : à demander', () {
      final c = parse<CreateCommand>('Ajoute un rendez-vous véto');
      expect(c.title, 'Rendez-vous véto');
      expect(c.type, ReminderType.vetAppointment);
      expect(c.when, isNull);
    });
  });

  group('agir sur un rappel', () {
    test('terminer', () {
      final c = parse<DoneCommand>('J\'ai donné le vermifuge à Rex');
      expect(c.query.words, ['vermifuge']);
      expect(c.query.petId, rexId);
      expect(c.query.type, ReminderType.deworming);
      expect(parse<DoneCommand>('C\'est fait').query.isEmpty, isTrue);
      parse<DoneCommand>('Le vaccin de Mia est fait');
    });

    test('reporter à une date ou d\'une durée', () {
      final a = parse<PostponeCommand>('Reporte l\'antipuces à lundi');
      expect(a.query.words, ['antipuces']);
      expect(a.when!.day, DateTime(2026, 11, 2));
      expect(a.when!.hasTime, isFalse);

      final b = parse<PostponeCommand>('Décale le rendez-vous de 3 jours');
      expect(b.delta, const Duration(days: 3));
      expect(b.query.type, ReminderType.vetAppointment);

      expect(parse<PostponeCommand>('Reporte le vermifuge').when, isNull);
    });

    test('supprimer', () {
      final c = parse<DeleteCommand>('Supprime le contrôle de Rex');
      expect(c.query.type, ReminderType.checkup);
      expect(c.query.petId, rexId);
      parse<DeleteCommand>('Annule le rendez-vous');
    });

    test('oui / non', () {
      expect(AssistantParser.isYes('Oui, supprimer'), isTrue);
      expect(AssistantParser.isYes('ok'), isTrue);
      expect(AssistantParser.isYes('Supprime le vaccin'), isFalse);
      expect(AssistantParser.isNo('Non merci'), isTrue);
      expect(AssistantParser.isNo('annuler'), isTrue);
    });
  });

  test('questions des autres modules : orientées, pas mal comprises', () {
    OtherTopic topic(String text) => parse<OutOfScopeCommand>(text).topic;
    expect(topic('Combien j\'ai dépensé chez le véto ?'),
        OtherTopic.healthSpending);
    expect(topic('Combien coûtent les croquettes ce mois-ci ?'),
        OtherTopic.foodSpending);
    expect(topic('Quel est le poids de Rex ?'), OtherTopic.weight);
    expect(topic('Quel âge a Mia ?'), OtherTopic.petInfo);
    expect(topic('Combien de croquettes a mangé Mia ?'), OtherTopic.food);
    expect(topic('Quelle distance Rex a marché cette semaine ?'),
        OtherTopic.activity);
    // Les questions sur les rappels restent des questions sur les rappels.
    expect(parse<ListCommand>('Combien de rappels en retard ?').scope,
        ListScope.overdue);
    parse<CreateCommand>('Rappelle-moi de peser Rex samedi');
  });

  test('recherche d\'un rappel par titre, type et animal', () {
    final reminders = [
      Reminder(id: 1, petId: rexId, title: 'Vermifuge',
          type: ReminderType.deworming, dueDate: DateTime(2026, 10, 30, 8)),
      Reminder(id: 2, petId: miaId, title: 'Vermifuge',
          type: ReminderType.deworming, dueDate: DateTime(2026, 11, 3, 8)),
      Reminder(id: 3, petId: miaId, title: 'Antipuces',
          type: ReminderType.treatment, dueDate: DateTime(2026, 10, 27, 19)),
    ];
    List<int?> ids(String text) =>
        parser.parseQuery(text).match(reminders, now).map((r) => r.id).toList();

    expect(ids('le vermifuge'), [1, 2]);
    expect(ids('le vermifuge de Mia'), [2]);
    expect(ids('pipette antipuces'), [3]);
    expect(ids('rien à voir'), isEmpty);
    // Sans critère : rappels en retard ou du jour.
    expect(const ReminderQuery().match(reminders, now).map((r) => r.id), [3]);
  });
}
