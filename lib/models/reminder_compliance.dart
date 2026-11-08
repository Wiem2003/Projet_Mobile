import 'reminder.dart';
import 'reminder_calculator.dart';

/// Résultat d'une échéance passée.
enum ComplianceOutcome {
  /// Fait le jour prévu ou avant.
  onTime,

  /// Fait, mais après le jour prévu.
  late,

  /// Pas fait, et le jour prévu est passé.
  missed,
}

/// Chiffres d'observance d'un ensemble d'échéances.
class ComplianceStats {
  const ComplianceStats({
    this.onTime = 0,
    this.late = 0,
    this.missed = 0,
    this.totalDelayDays = 0,
    this.postponed = 0,
  });

  final int onTime;
  final int late;
  final int missed;

  /// Somme des jours de retard (0 pour un soin fait à temps).
  final int totalDelayDays;

  /// Échéances évaluées qui avaient été reportées au moins une fois.
  final int postponed;

  /// Échéances passées prises en compte.
  int get evaluated => onTime + late + missed;
  bool get isEmpty => evaluated == 0;

  /// Part des soins faits à temps (0 à 1), `null` sans échéance passée.
  double? get rate => isEmpty ? null : onTime / evaluated;

  /// Retard moyen en jours (soins faits à temps comptés 0).
  double? get averageDelayDays => isEmpty ? null : totalDelayDays / evaluated;

  ComplianceStats _add(ComplianceOutcome o, int delay, bool wasPostponed) =>
      ComplianceStats(
        onTime: onTime + (o == ComplianceOutcome.onTime ? 1 : 0),
        late: late + (o == ComplianceOutcome.late ? 1 : 0),
        missed: missed + (o == ComplianceOutcome.missed ? 1 : 0),
        totalDelayDays: totalDelayDays + delay,
        postponed: postponed + (wasPostponed ? 1 : 0),
      );
}

/// Série en cours : soins d'un même type, pour un même animal, faits à
/// temps d'affilée (du plus récent en remontant).
class ComplianceStreak {
  const ComplianceStreak({required this.petId, required this.type, required this.count});

  final int? petId;
  final ReminderType type;
  final int count;
}

/// Statistiques d'observance du module Rappels : taux de soins faits à
/// temps par animal, par type et par mois, séries en cours, retard moyen.
///
/// Seules les échéances passées comptent. Un rappel reporté est jugé sur
/// sa nouvelle date ; le nombre d'échéances reportées est donné à part.
class ComplianceReport {
  const ComplianceReport({
    required this.overall,
    required this.byPet,
    required this.byType,
    required this.byMonth,
    required this.streaks,
  });

  /// Nombre de mois du graphique (mois en cours compris).
  static const months = 6;

  /// Une série compte à partir de 2 soins d'affilée.
  static const minStreak = 2;

  final ComplianceStats overall;

  /// Clé `null` : rappels généraux (sans animal).
  final Map<int?, ComplianceStats> byPet;
  final Map<ReminderType, ComplianceStats> byType;

  /// Du plus ancien au mois en cours (mois de l'échéance).
  final List<(DateTime month, ComplianceStats stats)> byMonth;

  /// De la plus longue à la plus courte.
  final List<ComplianceStreak> streaks;

  /// Type le plus souvent en retard (retard moyen le plus élevé).
  ReminderType? get mostForgotten {
    ReminderType? worst;
    var max = 0.0;
    byType.forEach((type, s) {
      final avg = s.averageDelayDays ?? 0;
      if (avg > max) {
        max = avg;
        worst = type;
      }
    });
    return worst;
  }

  /// Résultat d'une échéance, `null` si elle n'est pas encore passée.
  static ComplianceOutcome? outcomeOf(Reminder r, DateTime now) {
    if (r.isDone) {
      final done = r.completedAt ?? r.updatedAt ?? r.dueDate;
      return ReminderCalculator.daysUntil(r.dueDate, done) >= 0
          ? ComplianceOutcome.onTime
          : ComplianceOutcome.late;
    }
    // Le jour même, le soin peut encore être fait à temps.
    return ReminderCalculator.daysUntil(r.dueDate, now) < 0
        ? ComplianceOutcome.missed
        : null;
  }

  /// Jours de retard d'une échéance passée (0 si faite à temps).
  static int delayDays(Reminder r, DateTime now) {
    final end = r.isDone ? (r.completedAt ?? r.updatedAt ?? r.dueDate) : now;
    final days = -ReminderCalculator.daysUntil(r.dueDate, end);
    return days < 0 ? 0 : days;
  }

  factory ComplianceReport.compute(Iterable<Reminder> reminders, DateTime now) {
    var overall = const ComplianceStats();
    final byPet = <int?, ComplianceStats>{};
    final byType = <ReminderType, ComplianceStats>{};
    final firstMonth = DateTime(now.year, now.month - (months - 1));
    final monthly = [
      for (var i = 0; i < months; i++) DateTime(firstMonth.year, firstMonth.month + i),
    ];
    final byMonth = {for (final m in monthly) m: const ComplianceStats()};
    // Échéances évaluées par (animal, type), pour les séries.
    final series = <(int?, ReminderType), List<(DateTime, ComplianceOutcome)>>{};

    for (final r in reminders) {
      final outcome = outcomeOf(r, now);
      if (outcome == null) continue;
      final delay = delayDays(r, now);
      final postponed = r.postponeCount > 0;
      overall = overall._add(outcome, delay, postponed);
      byPet[r.petId] =
          (byPet[r.petId] ?? const ComplianceStats())._add(outcome, delay, postponed);
      byType[r.type] =
          (byType[r.type] ?? const ComplianceStats())._add(outcome, delay, postponed);
      final month = DateTime(r.dueDate.year, r.dueDate.month);
      final m = byMonth[month];
      if (m != null) byMonth[month] = m._add(outcome, delay, postponed);
      series.putIfAbsent((r.petId, r.type), () => []).add((r.dueDate, outcome));
    }

    final streaks = <ComplianceStreak>[];
    series.forEach((key, list) {
      list.sort((a, b) => b.$1.compareTo(a.$1));
      var count = 0;
      for (final (_, o) in list) {
        if (o != ComplianceOutcome.onTime) break;
        count++;
      }
      if (count >= minStreak) {
        streaks.add(ComplianceStreak(petId: key.$1, type: key.$2, count: count));
      }
    });
    streaks.sort((a, b) => b.count.compareTo(a.count));

    return ComplianceReport(
      overall: overall,
      byPet: byPet,
      byType: byType,
      byMonth: [for (final m in monthly) (m, byMonth[m]!)],
      streaks: streaks,
    );
  }
}
