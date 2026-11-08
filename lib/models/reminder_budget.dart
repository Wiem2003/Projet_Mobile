import 'health_record.dart';
import 'reminder.dart';
import 'reminder_calculator.dart';
import 'reminder_planning.dart';
import 'reminder_rules.dart';

/// Coût estimé d'un rappel à venir.
class CostEstimate {
  const CostEstimate(this.amount, this.basis);

  /// Montant en DT.
  final double amount;

  /// Origine : « d'après le soin du 03/10/2026 ».
  final String basis;
}

/// Un soin prévu dans le mois : le rappel lui-même ou l'une de ses
/// répétitions à venir.
class BudgetLine {
  const BudgetLine({required this.reminder, required this.date, this.estimate});

  final Reminder reminder;
  final DateTime date;
  final CostEstimate? estimate;

  /// Répétition future (pas encore enregistrée en base).
  bool get projected => date != reminder.dueDate;
  double get amount => estimate?.amount ?? 0;
}

/// Prévision d'un mois.
class MonthForecast {
  const MonthForecast({required this.month, required this.lines, this.budget});

  /// Premier jour du mois.
  final DateTime month;
  final List<BudgetLine> lines;

  /// Plafond mensuel (`null` = aucun).
  final double? budget;

  double get total => lines.fold(0, (s, l) => s + l.amount);
  List<BudgetLine> get estimated => [for (final l in lines) if (l.estimate != null) l];

  /// Soins prévus dont le coût n'est pas connu (aucun soin passé du même type).
  int get unknown => lines.length - estimated.length;
  bool get overBudget => budget != null && total > budget!;
  double get excess => budget == null ? 0 : (total - budget!).clamp(0, double.infinity);
}

/// Budget prévisionnel des soins (Rappels + Santé). Fonctions pures.
abstract final class ReminderBudget {
  /// Mois affichés, mois en cours compris.
  static const months = 3;

  /// Soins qu'on ne décale pas pour une raison de budget.
  static bool isUrgent(ReminderType t) => switch (t) {
        ReminderType.vaccination ||
        ReminderType.treatment ||
        ReminderType.vetAppointment ||
        ReminderType.deworming =>
          true,
        ReminderType.checkup || ReminderType.purchase || ReminderType.other => false,
      };

  static String _date(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  /// Coût d'un rappel : celui du dossier de santé qui l'a créé, sinon celui
  /// du dernier soin du même type (même animal en priorité).
  static CostEstimate? estimate(Reminder r, List<HealthRecord> records) {
    if (r.source == ReminderSource.health && r.sourceId != null) {
      for (final h in records) {
        if (h.id == r.sourceId && h.cost > 0) {
          return CostEstimate(h.cost, 'd\'après le soin du ${_date(h.date)}');
        }
      }
    }
    HealthRecord? best;
    for (final h in records) {
      if (h.type.reminderType != r.type || h.cost <= 0) continue;
      final samePet = h.petId == r.petId;
      final bestSamePet = best != null && best.petId == r.petId;
      if (best == null ||
          (samePet && !bestSamePet) ||
          (samePet == bestSamePet && h.date.isAfter(best.date))) {
        best = h;
      }
    }
    if (best == null) return null;
    return CostEstimate(best.cost, 'd\'après le soin du ${_date(best.date)}');
  }

  /// Prévision des [months] prochains mois. Un rappel en retard compte dans
  /// le mois en cours ; les rappels répétés comptent chaque occurrence.
  static List<MonthForecast> forecast(Iterable<Reminder> reminders,
      List<HealthRecord> records, DateTime now,
      {double? budget, int months = months}) {
    final starts = [
      for (var i = 0; i <= months; i++) DateTime(now.year, now.month + i),
    ];
    final end = starts.last;
    final byMonth = {for (final m in starts.take(months)) m: <BudgetLine>[]};

    for (final r in reminders) {
      if (r.isDone) continue;
      final cost = estimate(r, records);
      DateTime? d = r.dueDate;
      while (d != null && d.isBefore(end)) {
        final month = d.isBefore(starts.first) ? starts.first : DateTime(d.year, d.month);
        byMonth[month]?.add(BudgetLine(reminder: r, date: d, estimate: cost));
        d = ReminderCalculator.nextOccurrence(d, r.repeat);
      }
    }
    return [
      for (final m in starts.take(months))
        MonthForecast(
          month: m,
          lines: byMonth[m]!..sort((a, b) => a.date.compareTo(b.date)),
          budget: budget,
        ),
    ];
  }

  /// Budget dépassé : décale au mois suivant les soins non urgents (les
  /// moins graves et les plus chers d'abord) jusqu'à repasser sous le
  /// plafond. Les répétitions futures ne sont pas déplacées.
  static List<ReminderMove> shiftProposal(MonthForecast f, DateTime now) {
    if (!f.overBudget) return const [];
    final candidates = [
      for (final l in f.estimated)
        if (!l.projected && !isUrgent(l.reminder.type)) l,
    ]..sort((a, b) {
        final s = ReminderRules.severity(a.reminder.type)
            .compareTo(ReminderRules.severity(b.reminder.type));
        return s != 0 ? s : b.amount.compareTo(a.amount);
      });
    var total = f.total;
    final moves = <ReminderMove>[];
    for (final l in candidates) {
      if (total <= f.budget!) break;
      final base = l.date.isAfter(now) ? l.date : now;
      final to = ReminderCalculator.nextOccurrence(
          DateTime(base.year, base.month, base.day, l.date.hour, l.date.minute),
          ReminderRepeat.monthly)!;
      moves.add(ReminderMove(
        reminder: l.reminder,
        to: to,
        reason: 'Budget dépassé (${l.amount.toStringAsFixed(0)} DT)',
      ));
      total -= l.amount;
    }
    return moves;
  }
}
