import 'reminder.dart';

/// Regroupement chronologique utilisé par la liste des rappels.
enum ReminderBucket {
  overdue('En retard'),
  today('Aujourd\'hui'),
  tomorrow('Demain'),
  thisWeek('Cette semaine'),
  thisMonth('Ce mois-ci'),
  later('Plus tard'),
  done('Terminés');

  const ReminderBucket(this.label);

  final String label;
}

/// Calculs du module Rappels. Fonctions pures, `now` toujours injecté
/// pour rester testable.
abstract final class ReminderCalculator {
  /// Nombre de jours calendaires entre aujourd'hui et l'échéance
  /// (0 = aujourd'hui, 1 = demain, -2 = il y a deux jours).
  static int daysUntil(DateTime due, DateTime now) {
    final a = DateTime.utc(now.year, now.month, now.day);
    final b = DateTime.utc(due.year, due.month, due.day);
    return b.difference(a).inDays;
  }

  /// Libellé court du compte à rebours : « Demain », « Dans 10 j », « Retard 2 j ».
  static String countdownLabel(DateTime due, DateTime now) {
    final days = daysUntil(due, now);
    if (days == 0) return due.isBefore(now) ? 'Échu' : 'Aujourd\'hui';
    if (days == 1) return 'Demain';
    if (days == -1) return 'Hier';
    if (days < 0) return 'Retard ${-days} j';
    if (days < 60) return 'Dans $days j';
    final months = (days / 30).round();
    return 'Dans $months mois';
  }

  /// Phrase complète utilisée dans les notifications et le détail.
  static String relativeSentence(DateTime due, DateTime now) {
    final days = daysUntil(due, now);
    if (days == 0) return 'aujourd\'hui';
    if (days == 1) return 'demain';
    if (days == -1) return 'hier';
    if (days < 0) return 'en retard de ${-days} jours';
    return 'dans $days jours';
  }

  static ReminderBucket bucketOf(Reminder r, DateTime now) {
    if (r.isDone) return ReminderBucket.done;
    if (r.isOverdue(now)) return ReminderBucket.overdue;
    final days = daysUntil(r.dueDate, now);
    if (days == 0) return ReminderBucket.today;
    if (days == 1) return ReminderBucket.tomorrow;
    if (days <= 7) return ReminderBucket.thisWeek;
    if (days <= 31) return ReminderBucket.thisMonth;
    return ReminderBucket.later;
  }

  /// Prochaine occurrence d'un rappel répété. Le jour est ramené au dernier
  /// jour du mois si nécessaire (31/01 -> 28/02, 29/02 -> 28/02).
  static DateTime? nextOccurrence(DateTime due, ReminderRepeat repeat) {
    switch (repeat) {
      case ReminderRepeat.none:
        return null;
      case ReminderRepeat.weekly:
        return DateTime(
            due.year, due.month, due.day + 7, due.hour, due.minute);
      case ReminderRepeat.monthly:
        return _addMonths(due, 1);
      case ReminderRepeat.yearly:
        return _addMonths(due, 12);
      case ReminderRepeat.seasonal:
        return nextSeasonal(due);
    }
  }

  /// Saison des parasites : de mars à octobre (inclus).
  static const seasonStartMonth = 3;
  static const seasonEndMonth = 10;

  static bool inParasiteSeason(DateTime d) =>
      d.month >= seasonStartMonth && d.month <= seasonEndMonth;

  /// Prochaine date d'un traitement saisonnier : un mois plus tard en
  /// saison, trois mois plus tard hors saison, sans dépasser le début de la
  /// saison suivante (même jour du mois de mars).
  static DateTime nextSeasonal(DateTime due) {
    if (inParasiteSeason(due)) return _addMonths(due, 1);
    final next = _addMonths(due, 3);
    final seasonYear = due.month > seasonEndMonth ? due.year + 1 : due.year;
    // Mars a 31 jours : le même jour du mois existe toujours.
    final seasonStart =
        DateTime(seasonYear, seasonStartMonth, due.day, due.hour, due.minute);
    return next.isAfter(seasonStart) ? seasonStart : next;
  }

  /// Première occurrence strictement après [now] (rattrape les retards).
  static DateTime? nextOccurrenceAfter(
      DateTime due, ReminderRepeat repeat, DateTime now) {
    var next = nextOccurrence(due, repeat);
    while (next != null && !next.isAfter(now)) {
      next = nextOccurrence(next, repeat);
    }
    return next;
  }

  static DateTime _addMonths(DateTime d, int months) {
    final monthIndex = d.month - 1 + months;
    final year = d.year + monthIndex ~/ 12;
    final month = monthIndex % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = d.day > lastDay ? lastDay : d.day;
    return DateTime(year, month, day, d.hour, d.minute);
  }

  /// Dates de notification : échéance moins chaque délai d'alerte.
  static List<({AlertOffset offset, DateTime at})> alertSchedule(
      Reminder r) {
    final list = [
      for (final o in r.alertOffsets) (offset: o, at: r.dueDate.subtract(o.duration)),
    ]..sort((a, b) => a.at.compareTo(b.at));
    return list;
  }

  /// Notifications encore à venir (celles déjà passées sont ignorées).
  static List<({AlertOffset offset, DateTime at})> pendingAlerts(
      Reminder r, DateTime now) {
    if (r.isDone) return const [];
    return alertSchedule(r).where((a) => a.at.isAfter(now)).toList();
  }

  /// Base de report : on repart de l'échéance si elle est future, sinon de
  /// maintenant, en conservant l'heure prévue.
  static DateTime postponeBase(DateTime due, DateTime now) {
    if (due.isAfter(now)) return due;
    final candidate = DateTime(now.year, now.month, now.day, due.hour, due.minute);
    return candidate.isAfter(now) ? candidate : now;
  }

  static DateTime postponeBy(DateTime due, DateTime now, Duration delta) {
    final base = postponeBase(due, now);
    return DateTime(base.year, base.month, base.day + delta.inDays,
        base.hour, base.minute);
  }
}

/// Indicateurs agrégés (en-tête du module et Dashboard).
class ReminderStats {
  const ReminderStats({
    required this.overdue,
    required this.today,
    required this.next7Days,
    required this.upcoming,
    required this.doneThisMonth,
  });

  factory ReminderStats.compute(Iterable<Reminder> reminders, DateTime now) {
    var overdue = 0, today = 0, next7 = 0, upcoming = 0, doneMonth = 0;
    for (final r in reminders) {
      if (r.isDone) {
        final c = r.completedAt;
        if (c != null && c.year == now.year && c.month == now.month) {
          doneMonth++;
        }
        continue;
      }
      if (r.isOverdue(now)) {
        overdue++;
        continue;
      }
      upcoming++;
      final days = ReminderCalculator.daysUntil(r.dueDate, now);
      if (days == 0) today++;
      if (days <= 7) next7++;
    }
    return ReminderStats(
      overdue: overdue,
      today: today,
      next7Days: next7,
      upcoming: upcoming,
      doneThisMonth: doneMonth,
    );
  }

  final int overdue;
  final int today;
  final int next7Days;
  final int upcoming;
  final int doneThisMonth;
}
