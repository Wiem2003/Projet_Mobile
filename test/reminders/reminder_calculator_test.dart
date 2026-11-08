import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/models/reminder_calculator.dart';
import 'package:smart_pet/models/reminder.dart';

void main() {
  final now = DateTime(2026, 10, 29, 14, 0);

  Reminder r(DateTime due,
          {ReminderStatus status = ReminderStatus.upcoming,
          List<AlertOffset>? alerts}) =>
      Reminder(
        title: 'Test',
        type: ReminderType.vaccination,
        dueDate: due,
        status: status,
        alertOffsets: alerts,
      );

  group('daysUntil / jours restants', () {
    test('compte en jours calendaires, pas en tranches de 24 h', () {
      expect(ReminderCalculator.daysUntil(DateTime(2026, 10, 30, 8), now), 1);
      expect(ReminderCalculator.daysUntil(DateTime(2026, 10, 29, 23), now), 0);
      expect(ReminderCalculator.daysUntil(DateTime(2026, 11, 8, 9), now), 10);
      expect(ReminderCalculator.daysUntil(DateTime(2026, 10, 27), now), -2);
    });

    test('traverse le changement d\'heure sans erreur', () {
      expect(
          ReminderCalculator.daysUntil(
              DateTime(2026, 3, 30), DateTime(2026, 3, 28, 23)),
          2);
    });
  });

  group('countdownLabel', () {
    test('libellés', () {
      expect(ReminderCalculator.countdownLabel(DateTime(2026, 10, 29, 18), now),
          'Aujourd\'hui');
      expect(ReminderCalculator.countdownLabel(DateTime(2026, 10, 29, 9), now),
          'Échu');
      expect(ReminderCalculator.countdownLabel(DateTime(2026, 10, 30), now),
          'Demain');
      expect(ReminderCalculator.countdownLabel(DateTime(2026, 11, 8), now),
          'Dans 10 j');
      expect(ReminderCalculator.countdownLabel(DateTime(2026, 10, 26), now),
          'Retard 3 j');
      expect(ReminderCalculator.countdownLabel(DateTime(2027, 3, 1), now),
          'Dans 4 mois');
    });
  });

  group('bucketOf', () {
    test('classe les rappels par période', () {
      expect(ReminderCalculator.bucketOf(r(DateTime(2026, 10, 28)), now),
          ReminderBucket.overdue);
      expect(ReminderCalculator.bucketOf(r(DateTime(2026, 10, 29, 20)), now),
          ReminderBucket.today);
      expect(ReminderCalculator.bucketOf(r(DateTime(2026, 10, 30)), now),
          ReminderBucket.tomorrow);
      expect(ReminderCalculator.bucketOf(r(DateTime(2026, 11, 4)), now),
          ReminderBucket.thisWeek);
      expect(ReminderCalculator.bucketOf(r(DateTime(2026, 11, 20)), now),
          ReminderBucket.thisMonth);
      expect(ReminderCalculator.bucketOf(r(DateTime(2027, 1, 1)), now),
          ReminderBucket.later);
      expect(
          ReminderCalculator.bucketOf(
              r(DateTime(2026, 10, 1), status: ReminderStatus.done), now),
          ReminderBucket.done);
    });
  });

  group('nextOccurrence / répétition', () {
    test('mensuelle : ramène au dernier jour du mois', () {
      expect(
          ReminderCalculator.nextOccurrence(
              DateTime(2026, 1, 31, 9), ReminderRepeat.monthly),
          DateTime(2026, 2, 28, 9));
      expect(
          ReminderCalculator.nextOccurrence(
              DateTime(2026, 12, 15, 9), ReminderRepeat.monthly),
          DateTime(2027, 1, 15, 9));
    });

    test('annuelle : 29 février -> 28 février', () {
      expect(
          ReminderCalculator.nextOccurrence(
              DateTime(2028, 2, 29, 10), ReminderRepeat.yearly),
          DateTime(2029, 2, 28, 10));
    });

    test('hebdomadaire et aucune', () {
      expect(
          ReminderCalculator.nextOccurrence(
              DateTime(2026, 10, 29, 8), ReminderRepeat.weekly),
          DateTime(2026, 11, 5, 8));
      expect(
          ReminderCalculator.nextOccurrence(
              DateTime(2026, 10, 29), ReminderRepeat.none),
          isNull);
    });

    test('rattrape un rappel très en retard', () {
      expect(
          ReminderCalculator.nextOccurrenceAfter(
              DateTime(2026, 7, 10, 9), ReminderRepeat.monthly, now),
          DateTime(2026, 11, 10, 9));
    });
  });

  group('alertes', () {
    test('J-10, J-1 et jour J, triées ; seules les futures sont gardées', () {
      final reminder = r(DateTime(2026, 11, 3, 9), alerts: const [
        AlertOffset.atTime,
        AlertOffset.tenDays,
        AlertOffset.oneDay,
      ]);
      final all = ReminderCalculator.alertSchedule(reminder);
      expect(all.map((a) => a.at), [
        DateTime(2026, 10, 24, 9),
        DateTime(2026, 11, 2, 9),
        DateTime(2026, 11, 3, 9),
      ]);
      final pending = ReminderCalculator.pendingAlerts(reminder, now);
      expect(pending.map((a) => a.offset),
          [AlertOffset.oneDay, AlertOffset.atTime]);
    });

    test('aucune alerte pour un rappel fait', () {
      expect(
          ReminderCalculator.pendingAlerts(
              r(DateTime(2026, 12, 1), status: ReminderStatus.done), now),
          isEmpty);
    });
  });

  group('report', () {
    test('échéance future : on décale depuis l\'échéance', () {
      expect(
          ReminderCalculator.postponeBy(DateTime(2026, 11, 2, 9), now,
              const Duration(days: 3)),
          DateTime(2026, 11, 5, 9));
    });

    test('échéance passée : on repart d\'aujourd\'hui en gardant l\'heure', () {
      expect(
          ReminderCalculator.postponeBy(DateTime(2026, 10, 20, 18), now,
              const Duration(days: 1)),
          DateTime(2026, 10, 30, 18));
    });
  });

  test('ReminderStats', () {
    final stats = ReminderStats.compute([
      r(DateTime(2026, 10, 27)), // retard
      r(DateTime(2026, 10, 29, 20)), // aujourd'hui
      r(DateTime(2026, 11, 2)), // 7 jours
      r(DateTime(2026, 12, 25)), // plus tard
      Reminder(
          title: 'x',
          type: ReminderType.other,
          dueDate: DateTime(2026, 10, 5),
          status: ReminderStatus.done,
          completedAt: DateTime(2026, 10, 5)),
    ], now);
    expect(stats.overdue, 1);
    expect(stats.today, 1);
    expect(stats.next7Days, 2);
    expect(stats.upcoming, 3);
    expect(stats.doneThisMonth, 1);
  });
}
