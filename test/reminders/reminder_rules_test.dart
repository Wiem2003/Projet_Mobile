import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminder_exception.dart';
import 'package:smart_pet/models/reminder_rules.dart';
import 'package:smart_pet/models/reminders_model.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';

import 'test_helpers.dart';

/// Priorité et escalade : score d'urgence, relances J+1 / J+3, critique,
/// limites de report.
void main() {
  final now = DateTime(2026, 11, 5, 14);

  Reminder r(ReminderType type, DateTime due, {int postponed = 0, int? id}) =>
      Reminder(
          id: id,
          title: type.defaultTitle,
          type: type,
          dueDate: due,
          postponeCount: postponed);

  DateTime daysAgo(int d, [int hour = 9]) =>
      DateTime(now.year, now.month, now.day - d, hour);

  group('score d\'urgence', () {
    test('gravité × jours de retard ; au moins 1 jour une fois dépassé', () {
      expect(ReminderRules.severity(ReminderType.vaccination), 5);
      expect(ReminderRules.severity(ReminderType.purchase), 1);
      expect(ReminderRules.urgencyScore(r(ReminderType.vaccination, daysAgo(3)), now), 15);
      expect(ReminderRules.urgencyScore(r(ReminderType.purchase, daysAgo(10)), now), 10);
      expect(ReminderRules.urgencyScore(r(ReminderType.vaccination, daysAgo(0)), now), 5,
          reason: 'échu ce matin');
      expect(ReminderRules.urgencyScore(
          r(ReminderType.vaccination, now.add(const Duration(days: 1))), now), 0);
      final done = r(ReminderType.vaccination, daysAgo(5))
          .copyWith(status: ReminderStatus.done);
      expect(ReminderRules.urgencyScore(done, now), 0);
    });

    test('la liste « En retard » est triée par urgence', () {
      final model = RemindersModel(clock: () => now)
        ..setReminders([
          r(ReminderType.purchase, daysAgo(10), id: 1), // 10
          r(ReminderType.vaccination, daysAgo(3), id: 2), // 15
          r(ReminderType.deworming, daysAgo(1), id: 3), // 3
          r(ReminderType.checkup, daysAgo(5), id: 4), // 15, plus ancien
        ]);
      expect(model.overdue.map((x) => x.id), [4, 2, 1, 3]);
      expect(model.criticalCount, 2, reason: 'plus de 3 jours : 10 j et 5 j');
    });
  });

  group('escalade', () {
    test('niveaux selon les jours de retard', () {
      EscalationLevel level(int days) =>
          ReminderRules.escalation(r(ReminderType.vaccination, daysAgo(days)), now);
      expect(level(0), EscalationLevel.overdue);
      expect(level(1), EscalationLevel.firstReminder);
      expect(level(2), EscalationLevel.firstReminder);
      expect(level(3), EscalationLevel.secondReminder);
      expect(level(4), EscalationLevel.critical);
      expect(ReminderRules.escalation(
          r(ReminderType.vaccination, now.add(const Duration(hours: 2))), now),
          EscalationLevel.none);
    });

    test('relances programmées à J+1 et J+3, à l\'heure de l\'échéance', () {
      final due = r(ReminderType.deworming, DateTime(2026, 11, 10, 9));
      expect(ReminderRules.relances(due).map((x) => (x.level, x.at, x.slot)), [
        (EscalationLevel.firstReminder, DateTime(2026, 11, 11, 9), 14),
        (EscalationLevel.secondReminder, DateTime(2026, 11, 13, 9), 15),
      ]);
      expect(ReminderRules.pendingRelances(due, DateTime(2026, 11, 12)).single.slot, 15);
      expect(ReminderRules.relances(due.copyWith(status: ReminderStatus.done)), isEmpty);
    });
  });

  group('limites de report', () {
    test('vaccin : 3 reports, 30 jours maximum chacun', () {
      final v = r(ReminderType.vaccination, DateTime(2026, 11, 10, 9));
      expect(ReminderRules.remainingPostpones(v), 3);
      expect(ReminderRules.latestPostponeDate(v, now), DateTime(2026, 12, 10, 9));
      expect(ReminderRules.postponeError(v, DateTime(2026, 12, 10, 9), now), isNull);
      expect(ReminderRules.postponeError(v, DateTime(2026, 12, 11, 9), now),
          'Un report ne peut pas dépasser 30 jours pour ce vaccin '
          '(au plus tard le 10/12/2026).');
      final thrice = r(ReminderType.vaccination, DateTime(2026, 11, 10, 9), postponed: 3);
      expect(ReminderRules.needsAppointment(thrice), isTrue);
      expect(ReminderRules.postponeError(thrice, DateTime(2026, 11, 11), now),
          contains('déjà été reporté 3 fois'));
    });

    test('échéance passée : les 30 jours partent d\'aujourd\'hui', () {
      final late = r(ReminderType.vaccination, daysAgo(10, 9));
      // 9 h est déjà passé aujourd'hui (14 h) : base = maintenant.
      expect(ReminderRules.latestPostponeDate(late, now), DateTime(2026, 12, 5, 14));
    });

    test('traitement : 2 reports de 7 jours ; achats sans limite', () {
      final t = r(ReminderType.treatment, DateTime(2026, 11, 10, 9));
      expect(ReminderRules.postponeError(t, DateTime(2026, 11, 18, 9), now),
          contains('7 jours'));
      final p = r(ReminderType.purchase, DateTime(2026, 11, 10, 9), postponed: 20);
      expect(ReminderRules.remainingPostpones(p), isNull);
      expect(ReminderRules.postponeError(p, DateTime(2027, 6, 1), now), isNull);
    });

    test('rendez-vous proposé : même animal, demain 10 h, titre limité', () {
      final v = Reminder(
          petId: 2,
          title: 'x' * 80,
          type: ReminderType.vaccination,
          dueDate: daysAgo(4),
          postponeCount: 3);
      final rdv = ReminderRules.appointmentFor(v, now);
      expect((rdv.petId, rdv.type, rdv.dueDate),
          (2, ReminderType.vetAppointment, DateTime(2026, 11, 6, 10)));
      expect(rdv.title.length, 80);
      expect(rdv.notes, contains('reporté 3 fois'));
    });
  });

  group('repository : la règle est appliquée à l\'enregistrement', () {
    late AppDatabase db;
    late SqliteReminderRepository repo;
    setUp(() {
      db = memoryDatabase();
      repo = SqliteReminderRepository(db, clock: () => now);
    });
    tearDown(() => db.close());

    test('4e report d\'un vaccin refusé, report trop long refusé', () async {
      var v = await repo.create(Reminder(
          title: 'Rage', type: ReminderType.vaccination, dueDate: DateTime(2026, 11, 10, 9)));
      await expectLater(
          repo.postpone(v.id!, DateTime(2026, 12, 20, 9)),
          throwsA(isA<ReminderException>()
              .having((e) => e.isPostponeLimit, 'limite', isTrue)));
      for (var i = 1; i <= 3; i++) {
        v = await repo.postpone(v.id!, v.dueDate.add(const Duration(days: 2)));
        expect(v.postponeCount, i);
      }
      await expectLater(
          repo.postpone(v.id!, v.dueDate.add(const Duration(days: 1))),
          throwsA(isA<ReminderException>()
              .having((e) => e.message, 'message', contains('Prenez rendez-vous'))));
    });

    test('un achat peut être reporté sans limite', () async {
      var p = await repo.create(Reminder(
          title: 'Croquettes', type: ReminderType.purchase, dueDate: DateTime(2026, 11, 10, 9)));
      for (var i = 0; i < 5; i++) {
        p = await repo.postpone(p.id!, p.dueDate.add(const Duration(days: 60)));
      }
      expect(p.postponeCount, 5);
    });
  });
}
