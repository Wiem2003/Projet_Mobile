import '../activity.dart';
import '../feeding_record.dart';
import '../health_record.dart';
import '../pet.dart';
import 'pet_metrics.dart';

enum AlertKind {
  weightGain('Risque de prise de poids'),
  weightLoss('Perte de poids'),
  missingMeals('Repas non saisis'),
  unusualSpending('Dépense inhabituelle');

  const AlertKind(this.label);

  final String label;
}

/// Alerte qui croise plusieurs modules.
class CrossAlert {
  const CrossAlert({required this.id, required this.kind, required this.message, this.petId});

  /// Identifiant stable, pour « Ne plus afficher pendant 30 jours ».
  final String id;
  final AlertKind kind;
  final String message;
  final int? petId;
}

/// Règles d'alerte du tableau de bord. Fonctions pures.
abstract final class CrossAlerts {
  /// Repas +20 % et activité −30 % sur 30 jours.
  static const mealsIncrease = 0.20;
  static const activityDecrease = 0.30;

  /// Perte de poids de 8 % ou plus en 2 mois.
  static const weightLoss = 0.08;

  /// Aucun repas saisi depuis 3 jours.
  static const mealGapDays = 3;

  /// Dépenses du mois supérieures de 50 % à la moyenne des 3 mois précédents.
  static const spendingIncrease = 0.50;

  /// Une alerte masquée l'est pendant 30 jours.
  static const snooze = Duration(days: 30);

  static List<CrossAlert> compute({
    required List<Pet> pets,
    required Iterable<HealthRecord> health,
    required Iterable<FeedingRecord> feeding,
    required Iterable<Activity> activities,
    required DateTime now,
    Map<String, DateTime> dismissedUntil = const {},
  }) {
    final alerts = <CrossAlert>[
      for (final p in pets) ...[
        ?_weightGain(p, feeding, activities, now),
        ?_weightLoss(p, health, now),
        ?_missingMeals(p, feeding, now),
      ],
      ?_spending(pets, health, feeding, now),
    ];
    return [
      for (final a in alerts)
        if (!(dismissedUntil[a.id]?.isAfter(now) ?? false)) a,
    ];
  }

  static CrossAlert? _weightGain(
      Pet p, Iterable<FeedingRecord> feeding, Iterable<Activity> activities, DateTime now) {
    final id = p.id!;
    final last = now.subtract(const Duration(days: 30));
    final prev = now.subtract(const Duration(days: 60));
    bool recent(DateTime d) => d.isAfter(last) && !d.isAfter(now);
    bool before(DateTime d) => d.isAfter(prev) && !d.isAfter(last);
    final foodNow = PetMetrics.feedingGrams(feeding, id, recent);
    final foodBefore = PetMetrics.feedingGrams(feeding, id, before);
    final moveNow = PetMetrics.activityMinutes(activities, id, recent);
    final moveBefore = PetMetrics.activityMinutes(activities, id, before);
    if (foodBefore <= 0 || moveBefore <= 0) return null;
    final eatsMore = foodNow >= foodBefore * (1 + mealsIncrease);
    final movesLess = moveNow <= moveBefore * (1 - activityDecrease);
    if (!eatsMore || !movesLess) return null;
    return CrossAlert(
      id: 'weight_gain:$id',
      kind: AlertKind.weightGain,
      petId: id,
      message: '${p.name} mange plus (${PetMetrics.percent(foodNow / foodBefore - 1)}) et '
          'bouge moins (${PetMetrics.percent(moveNow / moveBefore - 1)}) sur 30 jours : '
          'risque de prise de poids.',
    );
  }

  static CrossAlert? _weightLoss(Pet p, Iterable<HealthRecord> health, DateTime now) {
    final change = PetMetrics.weightChange(p.id!, health, now);
    if (change == null || change.ratio > -weightLoss) return null;
    return CrossAlert(
      id: 'weight_loss:${p.id}',
      kind: AlertKind.weightLoss,
      petId: p.id,
      message: '${p.name} a perdu du poids (${PetMetrics.percent(change.ratio)} en 2 mois, '
          '${PetMetrics.dayMonth(change.from.date)} → ${PetMetrics.dayMonth(change.to.date)}) : '
          'une consultation est conseillée.',
    );
  }

  /// Seulement pour un animal dont les repas sont suivis (au moins un repas
  /// saisi).
  static CrossAlert? _missingMeals(Pet p, Iterable<FeedingRecord> feeding, DateTime now) {
    DateTime? latest;
    for (final f in feeding) {
      if (f.petId == p.id && (latest == null || f.date.isAfter(latest))) latest = f.date;
    }
    if (latest == null) return null;
    final gap = PetMetrics.dayOf(now).difference(PetMetrics.dayOf(latest)).inDays;
    if (gap < mealGapDays) return null;
    return CrossAlert(
      id: 'meals:${p.id}',
      kind: AlertKind.missingMeals,
      petId: p.id,
      message: 'Pensez à saisir les repas de ${p.name} : aucun repas depuis $gap jours.',
    );
  }

  static CrossAlert? _spending(List<Pet> pets, Iterable<HealthRecord> health,
      Iterable<FeedingRecord> feeding, DateTime now) {
    if (pets.isEmpty) return null;
    final month = PetMetrics.monthOf(now);
    double total(DateTime m) =>
        PetMetrics.healthCost(health, (d) => PetMetrics.inMonth(d, m)) +
        PetMetrics.feedingCost(feeding, (d) => PetMetrics.inMonth(d, m));
    final current = total(month);
    final average =
        [for (var i = 1; i <= 3; i++) total(PetMetrics.addMonths(month, -i))].fold(0.0, (a, b) => a + b) / 3;
    if (average <= 0 || current <= average * (1 + spendingIncrease)) return null;

    String petName(int id) => pets.where((p) => p.id == id).firstOrNull?.name ?? 'un animal';
    // Cause : le soin le plus cher du mois, sinon l'alimentation la plus chère.
    HealthRecord? care;
    for (final h in health) {
      if (PetMetrics.inMonth(h.date, month) && h.cost > 0 && (care == null || h.cost > care.cost)) {
        care = h;
      }
    }
    String cause;
    if (care != null) {
      cause = '${care.type.label.toLowerCase()} de ${petName(care.petId)} ${PetMetrics.money(care.cost)}';
    } else {
      var best = 0.0;
      var bestPet = pets.first.id!;
      for (final p in pets) {
        final v = PetMetrics.feedingCost(feeding, (d) => PetMetrics.inMonth(d, month), petId: p.id);
        if (v > best) {
          best = v;
          bestPet = p.id!;
        }
      }
      cause = 'alimentation de ${petName(bestPet)} ${PetMetrics.money(best)}';
    }
    return CrossAlert(
      id: 'spending:${month.year}-${month.month}',
      kind: AlertKind.unusualSpending,
      message: 'Dépenses de ${PetMetrics.monthNames[month.month - 1]} : '
          '${PetMetrics.money(current)}, ${PetMetrics.percent(current / average - 1)} par rapport '
          'à la moyenne des 3 mois précédents (${PetMetrics.money(average)}), dont $cause.',
    );
  }
}
