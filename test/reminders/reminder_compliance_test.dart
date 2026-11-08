import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/controllers/reminders_controller.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminder_compliance.dart';
import 'package:smart_pet/models/reminders_model.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';

import 'test_helpers.dart';

/// Statistiques d'observance : soins faits à temps, séries, retard moyen.
void main() {
  final now = DateTime(2026, 11, 5, 14);

  Reminder done(ReminderType type, DateTime due, DateTime completed,
          {int? pet = rexId, int postponed = 0}) =>
      Reminder(
        petId: pet,
        title: type.defaultTitle,
        type: type,
        dueDate: due,
        status: ReminderStatus.done,
        completedAt: completed,
        postponeCount: postponed,
      );

  test('résultat d\'une échéance : à temps, en retard, oubliée ou pas encore',
      () {
    final due = DateTime(2026, 11, 1, 9);
    ComplianceOutcome? of(Reminder r) => ComplianceReport.outcomeOf(r, now);
    expect(of(done(ReminderType.deworming, due, DateTime(2026, 11, 1, 20))),
        ComplianceOutcome.onTime, reason: 'le jour même, plus tard');
    expect(of(done(ReminderType.deworming, due, DateTime(2026, 10, 30))),
        ComplianceOutcome.onTime, reason: 'en avance');
    expect(of(done(ReminderType.deworming, due, DateTime(2026, 11, 3, 8))),
        ComplianceOutcome.late);
    expect(ComplianceReport.delayDays(
        done(ReminderType.deworming, due, DateTime(2026, 11, 3, 8)), now), 2);
    final pending = Reminder(title: 'x', type: ReminderType.deworming, dueDate: due);
    expect(of(pending), ComplianceOutcome.missed);
    expect(ComplianceReport.delayDays(pending, now), 4);
    expect(of(pending.copyWith(dueDate: DateTime(2026, 11, 5, 9))), isNull,
        reason: 'échu ce matin : encore faisable à temps');
    expect(of(pending.copyWith(dueDate: DateTime(2026, 11, 20))), isNull);
  });

  test('taux, retard moyen, par animal, par type, par mois, séries', () {
    final report = ComplianceReport.compute([
      // Rex : 3 vermifuges à temps d'affilée (le plus ancien était en retard).
      done(ReminderType.deworming, DateTime(2026, 7, 10), DateTime(2026, 7, 14)),
      done(ReminderType.deworming, DateTime(2026, 8, 10), DateTime(2026, 8, 10)),
      done(ReminderType.deworming, DateTime(2026, 9, 10), DateTime(2026, 9, 9)),
      done(ReminderType.deworming, DateTime(2026, 10, 10), DateTime(2026, 10, 10)),
      // Mia : vaccin fait avec 10 jours de retard, après un report.
      done(ReminderType.vaccination, DateTime(2026, 10, 1), DateTime(2026, 10, 11),
          pet: miaId, postponed: 1),
      // Achat oublié depuis 5 jours.
      Reminder(title: 'Croquettes', type: ReminderType.purchase,
          dueDate: DateTime(2026, 10, 31, 18)),
      // À venir : ignoré.
      Reminder(title: 'Contrôle', type: ReminderType.checkup,
          dueDate: DateTime(2026, 12, 1)),
    ], now);

    final o = report.overall;
    expect((o.onTime, o.late, o.missed, o.postponed), (3, 2, 1, 1));
    expect(o.rate, 0.5);
    expect(o.averageDelayDays, (4 + 10 + 5) / 6);
    expect(report.byPet[rexId]!.rate, 0.75);
    expect(report.byPet[miaId]!.rate, 0);
    expect(report.byPet[null]!.missed, 1, reason: 'rappel général');
    expect(report.byType[ReminderType.vaccination]!.averageDelayDays, 10);
    expect(report.byType.containsKey(ReminderType.checkup), isFalse);
    expect(report.mostForgotten, ReminderType.vaccination);

    expect(report.byMonth.map((m) => m.$1.month), [6, 7, 8, 9, 10, 11]);
    expect(report.byMonth[1].$2.late, 1, reason: 'juillet');
    expect(report.byMonth[4].$2.evaluated, 3, reason: 'octobre');

    final streak = report.streaks.single;
    expect((streak.petId, streak.type, streak.count),
        (rexId, ReminderType.deworming, 3));
  });

  test('aucune échéance passée : statistiques vides', () {
    final report = ComplianceReport.compute(const [], now);
    expect(report.overall.isEmpty, isTrue);
    expect(report.overall.rate, isNull);
    expect(report.streaks, isEmpty);
    expect(report.mostForgotten, isNull);
  });

  test('historique d\'exemple : 8 vermifuges d\'affilée pour Rex', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final model = RemindersModel(clock: () => now);
    final ctrl = RemindersController(
      model: model,
      repository: SqliteReminderRepository(db, clock: () => now),
      notifier: FakeNotifier(),
      pets: const DemoPetDirectory(),
      refreshEvery: null,
    );
    addTearDown(ctrl.dispose);
    await ctrl.load();

    expect(await ctrl.seedHistory(), 21);
    expect(await ctrl.seedHistory(), 0, reason: 'déjà chargé');
    expect(model.done, hasLength(21));
    expect(model.overdue, isEmpty, reason: 'tout l\'historique est fait');

    final report = model.compliance;
    final o = report.overall;
    expect((o.onTime, o.late, o.missed, o.postponed), (16, 5, 0, 2));
    expect(o.totalDelayDays, 3 + 5 + 12 + 2 + 2);
    final streak = report.streaks.first;
    expect((streak.petId, streak.type, streak.count),
        (rexId, ReminderType.deworming, 8));
    expect(report.mostForgotten, ReminderType.vaccination);

    // Filtre sur Mia : seulement ses soins.
    ctrl.setPetFilter(miaId);
    expect(model.compliance.overall.evaluated, 7);
  });
}
