import '../feeding_record.dart';
import '../health_record.dart';
import '../pet.dart';
import '../reminder.dart';
import '../reminder_budget.dart';
import 'pet_metrics.dart';

/// Coût de revient d'un animal (santé + alimentation).
class PetCost {
  const PetCost({
    required this.pet,
    required this.healthThisMonth,
    required this.feedingThisMonth,
    required this.daysElapsed,
    required this.healthLast3,
    required this.feedingLast3,
    required this.plannedCare,
  });

  final Pet pet;
  final double healthThisMonth;
  final double feedingThisMonth;

  /// Jours écoulés dans le mois en cours (aujourd'hui compris).
  final int daysElapsed;

  /// Totaux des 3 mois complets précédents.
  final double healthLast3;
  final double feedingLast3;

  /// Soins déjà prévus sur les 12 prochains mois (rappels, coût estimé).
  final double plannedCare;

  double get thisMonth => healthThisMonth + feedingThisMonth;
  double get perDay => daysElapsed == 0 ? 0 : thisMonth / daysElapsed;
  double get last3 => healthLast3 + feedingLast3;
  double get monthlyAverage => last3 / 3;

  /// Projection sur 12 mois : alimentation (moyenne des 3 derniers mois
  /// × 12) + soins déjà prévus.
  double get annualProjection => feedingLast3 / 3 * 12 + plannedCare;
}

/// « Rex coûte 2,4 fois plus que Mia, surtout en alimentation ».
class CostComparison {
  const CostComparison({required this.costly, required this.cheap, required this.mainCategory});

  final PetCost costly;
  final PetCost cheap;

  /// « alimentation » ou « santé » : là où l'écart est le plus grand.
  final String mainCategory;

  double get ratio => costly.last3 / cheap.last3;

  String get sentence {
    final r = ratio.toStringAsFixed(1).replaceAll('.', ',');
    return '${costly.pet.name} coûte $r fois plus que ${cheap.pet.name}, '
        'surtout en $mainCategory (3 derniers mois).';
  }
}

class CostReport {
  const CostReport({required this.pets, this.comparison});

  /// Du plus cher au moins cher ce mois-ci.
  final List<PetCost> pets;
  final CostComparison? comparison;

  /// Écart minimal pour comparer deux animaux.
  static const minRatio = 1.2;

  double get totalThisMonth => pets.fold(0, (s, p) => s + p.thisMonth);
  double get totalProjection => pets.fold(0, (s, p) => s + p.annualProjection);

  factory CostReport.compute({
    required List<Pet> pets,
    required List<HealthRecord> health,
    required Iterable<FeedingRecord> feeding,
    required Iterable<Reminder> reminders,
    required DateTime now,
  }) {
    final month = PetMetrics.monthOf(now);
    final threeAgo = PetMetrics.addMonths(month, -3);
    bool thisMonth(DateTime d) => PetMetrics.inMonth(d, month);
    bool last3(DateTime d) => PetMetrics.inRange(d, threeAgo, month);
    final planned = <int?, double>{};
    for (final f in ReminderBudget.forecast(reminders, health, now, months: 12)) {
      for (final l in f.estimated) {
        planned[l.reminder.petId] = (planned[l.reminder.petId] ?? 0) + l.amount;
      }
    }

    final costs = [
      for (final p in pets)
        PetCost(
          pet: p,
          healthThisMonth: PetMetrics.healthCost(health, thisMonth, petId: p.id),
          feedingThisMonth: PetMetrics.feedingCost(feeding, thisMonth, petId: p.id),
          daysElapsed: now.day,
          healthLast3: PetMetrics.healthCost(health, last3, petId: p.id),
          feedingLast3: PetMetrics.feedingCost(feeding, last3, petId: p.id),
          plannedCare: planned[p.id] ?? 0,
        ),
    ]..sort((a, b) => b.thisMonth.compareTo(a.thisMonth));

    final ranked = [for (final c in costs) if (c.last3 > 0) c]
      ..sort((a, b) => b.last3.compareTo(a.last3));
    CostComparison? comparison;
    if (ranked.length >= 2) {
      final costly = ranked.first, cheap = ranked.last;
      if (costly.last3 >= cheap.last3 * minRatio) {
        final feedGap = costly.feedingLast3 - cheap.feedingLast3;
        final careGap = costly.healthLast3 - cheap.healthLast3;
        comparison = CostComparison(
          costly: costly,
          cheap: cheap,
          mainCategory: feedGap >= careGap ? 'alimentation' : 'santé',
        );
      }
    }
    return CostReport(pets: costs, comparison: comparison);
  }
}
