import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/controllers/reminders_controller.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminder_budget.dart';
import 'package:smart_pet/models/reminder_calculator.dart';
import 'package:smart_pet/models/reminder_planning.dart';
import 'package:smart_pet/models/reminders_model.dart';
import 'package:smart_pet/models/sqlite_planning_settings_store.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';

import 'test_helpers.dart';

/// Planification de la semaine, saisonnalité et budget prévisionnel.
void main() {
  final now = DateTime(2026, 11, 5, 14);
  const vaccinVermifuge = IntervalRule(ReminderType.vaccination, ReminderType.deworming, 7);

  var nextId = 100;
  Reminder r(ReminderType type, DateTime due,
          {int? pet = rexId, String? title, ReminderRepeat repeat = ReminderRepeat.none}) =>
      Reminder(
        id: nextId++,
        petId: pet,
        title: title ?? type.defaultTitle,
        type: type,
        dueDate: due,
        repeat: repeat,
      );

  group('délai minimal entre deux soins', () {
    IntervalConflict? check(DateTime date, List<Reminder> others,
            {int? pet = rexId, List<IntervalRule> rules = const [vaccinVermifuge]}) =>
        ReminderPlanner.intervalConflict(
            petId: pet, type: ReminderType.deworming, date: date, others: others, rules: rules);

    final vaccin = r(ReminderType.vaccination, DateTime(2026, 11, 10, 9), title: 'Vaccin rage');

    test('trop proche : avertissement avec la première date possible', () {
      final c = check(DateTime(2026, 11, 12, 18), [vaccin])!;
      expect((c.other.title, c.rule.days), ('Vaccin rage', 7));
      expect(c.earliest, DateTime(2026, 11, 17, 18), reason: 'même heure');
      // Avant le vaccin, dans le délai : aussi trop proche.
      expect(check(DateTime(2026, 11, 5, 9), [vaccin])!.earliest, DateTime(2026, 11, 17, 9));
      expect(check(DateTime(2026, 11, 17, 9), [vaccin]), isNull, reason: '7 jours pile');
      expect(check(DateTime(2026, 11, 2, 9), [vaccin]), isNull, reason: '8 jours avant');
    });

    test('autre animal, rappel général ou aucune règle : pas de contrôle', () {
      expect(check(DateTime(2026, 11, 11), [vaccin], pet: miaId), isNull);
      expect(check(DateTime(2026, 11, 11), [vaccin], pet: null), isNull);
      expect(check(DateTime(2026, 11, 11), [vaccin], rules: const []), isNull);
    });

    test('un soin fait compte à la date où il a été fait', () {
      final done = vaccin.copyWith(
          status: ReminderStatus.done, completedAt: () => DateTime(2026, 11, 3, 10));
      expect(check(DateTime(2026, 11, 6, 9), [done])!.earliest, DateTime(2026, 11, 10, 9));
    });

    test('plusieurs règles : la première date les respecte toutes', () {
      final traitement = r(ReminderType.treatment, DateTime(2026, 11, 19, 9));
      final c = check(DateTime(2026, 11, 12, 9), [vaccin, traitement], rules: const [
        vaccinVermifuge,
        IntervalRule(ReminderType.deworming, ReminderType.treatment, 5),
      ])!;
      // 17/11 est à 2 jours du traitement : on passe au 24/11.
      expect(c.earliest, DateTime(2026, 11, 24, 9));
    });
  });

  group('journées surchargées', () {
    final day = DateTime(2026, 11, 10);
    DateTime at(int hour, [DateTime? d]) => DateTime((d ?? day).year, (d ?? day).month, (d ?? day).day, hour);

    List<Reminder> busyDay() => [
          r(ReminderType.vaccination, at(9)),
          r(ReminderType.checkup, at(10), pet: miaId),
          r(ReminderType.purchase, at(18), pet: null, title: 'Croquettes'),
          r(ReminderType.other, at(19), title: 'Toilettage'),
          r(ReminderType.treatment, at(20), pet: miaId),
        ];

    test('plus de 3 rappels : les moins graves vont au jour libre le plus proche', () {
      final all = busyDay();
      final days = ReminderPlanner.overloadedDays(all, now);
      expect(days.single.$1, day);
      expect(days.single.$2, hasLength(5));

      final moves = ReminderPlanner.lighten(all, now, const []);
      expect(moves.map((m) => (m.reminder.title, m.to)), [
        ('Croquettes', DateTime(2026, 11, 11, 18)),
        ('Toilettage', DateTime(2026, 11, 11, 19)),
      ]);
      expect(moves.first.reason, 'Journée chargée (5 rappels)');
    });

    test('jour suivant plein : on essaie la veille', () {
      final next = DateTime(2026, 11, 11);
      final all = [
        ...busyDay(),
        for (var h = 8; h < 11; h++) r(ReminderType.vaccination, at(h, next), pet: miaId),
      ];
      final moves = ReminderPlanner.lighten(all, now, const []);
      expect(moves.map((m) => m.to.day), [9, 9]);
    });

    test('que des soins graves : rien n\'est déplacé ; passé ignoré', () {
      final all = [for (var h = 8; h < 13; h++) r(ReminderType.vaccination, at(h))];
      expect(ReminderPlanner.overloadedDays(all, now), hasLength(1));
      expect(ReminderPlanner.lighten(all, now, const []), isEmpty);
      final past = [for (var h = 8; h < 13; h++) r(ReminderType.purchase, at(h, DateTime(2026, 11, 1)))];
      expect(ReminderPlanner.overloadedDays(past, now), isEmpty);
    });
  });

  group('saisonnalité', () {
    DateTime next(int month, [int day = 15, int year = 2026]) =>
        ReminderCalculator.nextOccurrence(DateTime(year, month, day, 19), ReminderRepeat.seasonal)!;

    test('mensuel de mars à octobre, tous les 3 mois sinon', () {
      expect(next(4), DateTime(2026, 5, 15, 19));
      expect(next(10), DateTime(2026, 11, 15, 19), reason: 'octobre : encore la saison');
      expect(next(11), DateTime(2027, 2, 15, 19), reason: 'hors saison : +3 mois');
      expect(next(2, 15, 2027), DateTime(2027, 3, 15, 19),
          reason: 'ne dépasse pas le début de la saison');
      expect(next(1, 20, 2027), DateTime(2027, 3, 20, 19));
      expect(next(10, 31), DateTime(2026, 11, 30, 19), reason: 'fin de mois');
    });

    test('marquer fait crée l\'occurrence suivante selon la saison', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = SqliteReminderRepository(db, clock: () => now);
      final antipuces = await repo.create(Reminder(
          petId: miaId,
          title: 'Antipuces',
          type: ReminderType.treatment,
          dueDate: DateTime(2026, 11, 5, 19),
          repeat: ReminderRepeat.seasonal));
      final result = await repo.markDone(antipuces.id!);
      expect(result.next!.dueDate, DateTime(2027, 2, 5, 19));
    });
  });

  group('budget prévisionnel', () {
    HealthRecord care(int id, int pet, HealthType type, DateTime date, double cost) =>
        HealthRecord(id: id, petId: pet, type: type, date: date, cost: cost);

    final records = [
      care(1, rexId, HealthType.vaccination, DateTime(2025, 12, 3), 60),
      care(2, miaId, HealthType.vaccination, DateTime(2026, 6, 1), 55),
      care(3, miaId, HealthType.dental, DateTime(2025, 12, 10), 85),
      care(4, rexId, HealthType.other, DateTime(2026, 9, 1), 20),
    ];

    test('coût : dossier source, sinon dernier soin du même type (même animal d\'abord)', () {
      final vaccinRex = r(ReminderType.vaccination, DateTime(2026, 12, 3));
      expect(ReminderBudget.estimate(vaccinRex, records)!.amount, 60);
      expect(ReminderBudget.estimate(vaccinRex, records)!.basis,
          'd\'après le soin du 03/12/2025');
      final vaccinCoco = r(ReminderType.vaccination, DateTime(2026, 12, 3), pet: 3);
      expect(ReminderBudget.estimate(vaccinCoco, records)!.amount, 55, reason: 'le plus récent');
      final fromHealth = Reminder(
          petId: miaId, title: 'Détartrage', type: ReminderType.checkup,
          dueDate: DateTime(2026, 12, 10), source: ReminderSource.health, sourceId: 3);
      expect(ReminderBudget.estimate(fromHealth, records)!.amount, 85);
      expect(ReminderBudget.estimate(r(ReminderType.purchase, DateTime(2026, 12, 1)), records),
          isNull);
    });

    test('prévision sur 3 mois, répétitions comprises, puis dépassement', () {
      final reminders = [
        r(ReminderType.vaccination, DateTime(2026, 12, 3, 9), title: 'Vaccin'),
        r(ReminderType.checkup, DateTime(2026, 12, 10, 10), pet: miaId, title: 'Détartrage'),
        r(ReminderType.purchase, DateTime(2026, 12, 12, 18), pet: null, title: 'Croquettes'),
        r(ReminderType.other, DateTime(2026, 11, 20, 9), title: 'Toilettage',
            repeat: ReminderRepeat.monthly),
        // En retard depuis octobre : compté en novembre.
        r(ReminderType.other, DateTime(2026, 10, 28, 9), title: 'Brosse'),
      ];
      final months = ReminderBudget.forecast(reminders, records, now, budget: 100);
      expect(months.map((m) => m.month.month), [11, 12, 1]);
      expect(months[0].total, 40, reason: 'toilettage + brosse');
      final dec = months[1];
      expect(dec.total, 60 + 85 + 20);
      expect(dec.unknown, 1, reason: 'croquettes : coût inconnu');
      expect(dec.lines.firstWhere((l) => l.reminder.title == 'Toilettage').projected, isTrue);
      expect((dec.overBudget, dec.excess), (true, 65));
      expect(months[2].total, 20);

      // Seuls les soins non urgents et enregistrés sont décalés.
      final moves = ReminderBudget.shiftProposal(dec, now);
      expect(moves.map((m) => (m.reminder.title, m.to)),
          [('Détartrage', DateTime(2027, 1, 10, 10))]);
      expect(ReminderBudget.shiftProposal(months[0], now), isEmpty);
    });
  });

  group('réglages et Controller', () {
    test('JSON : aller-retour, valeurs invalides ignorées', () {
      final s = const PlanningSettings(monthlyBudget: 150)
          .withInterval(const IntervalRule(ReminderType.deworming, ReminderType.vaccination, 10));
      expect(s.intervals, [const IntervalRule(ReminderType.deworming, ReminderType.vaccination, 10)],
          reason: 'remplace la règle des mêmes types');
      final back = PlanningSettings.fromJson(s.toJson());
      expect(back.intervals, s.intervals);
      expect(back.monthlyBudget, 150);
      final bad = PlanningSettings.fromJson({
        'intervals': [
          {'a': 'vaccination', 'b': 'deworming', 'days': 500},
        ],
        'monthly_budget': -3,
      });
      expect(bad.intervals, isEmpty);
      expect(bad.monthlyBudget, isNull);
    });

    test('réglages par compte en base ; déplacer ne compte pas comme report',
        () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final store1 = SqlitePlanningSettingsStore(db, ownerId: 1);
      await store1.save(const PlanningSettings(monthlyBudget: 120));
      expect((await store1.load()).monthlyBudget, 120);
      expect((await SqlitePlanningSettingsStore(db, ownerId: 2).load()).monthlyBudget, isNull);

      final repo = SqliteReminderRepository(db, clock: () => now);
      final model = RemindersModel(clock: () => now);
      final ctrl = RemindersController(
        model: model,
        repository: repo,
        notifier: FakeNotifier(),
        pets: const DemoPetDirectory(),
        refreshEvery: null,
        planning: store1,
        healthRecords: () async => [
          HealthRecord(id: 1, petId: miaId, type: HealthType.dental,
              date: DateTime(2025, 12, 10), cost: 85),
        ],
      );
      addTearDown(ctrl.dispose);
      final detartrage = await repo.create(Reminder(
          petId: miaId, title: 'Détartrage', type: ReminderType.checkup,
          dueDate: DateTime(2026, 11, 20, 10)));
      await ctrl.load();
      expect(model.planning.monthlyBudget, 120);
      expect(model.forecasts.first.total, 85);
      expect(model.overBudgetMonth, isNull);

      await ctrl.savePlanning(model.planning.copyWith(monthlyBudget: () => 50));
      expect((await store1.load()).monthlyBudget, 50);
      final month = model.overBudgetMonth!;
      final moves = ReminderBudget.shiftProposal(month, now);
      expect(await ctrl.applyMoves(moves), 1);
      final moved = model.byId(detartrage.id)!;
      expect((moved.dueDate, moved.postponeCount), (DateTime(2026, 12, 20, 10), 0));
      expect(model.overBudgetMonth?.month, DateTime(2026, 12),
          reason: 'décembre dépasse maintenant à son tour');
    });
  });
}
