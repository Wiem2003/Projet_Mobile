import 'health_record.dart';

/// Période des calculs du module Santé.
enum HealthPeriod {
  quarter('3 mois', 3),
  year('12 mois', 12),
  all('Tout', null);

  const HealthPeriod(this.label, this.months);

  final String label;
  final int? months;

  /// Début de la période (minuit), `null` pour « Tout ».
  DateTime? startFrom(DateTime now) =>
      months == null ? null : DateTime(now.year, now.month - months!, now.day);

  bool contains(DateTime date, DateTime now) {
    final start = startFrom(now);
    return start == null || !date.isBefore(start);
  }
}

/// Une pesée (graphique « Évolution du poids »).
class WeightPoint {
  const WeightPoint(this.date, this.kg);

  final DateTime date;
  final double kg;
}

/// Calculs automatiques du module Santé sur la période choisie.
class HealthStats {
  const HealthStats({
    required this.period,
    required this.recordCount,
    required this.consultations,
    required this.spending,
    required this.spendingByType,
    required this.weights,
  });

  final HealthPeriod period;
  final int recordCount;

  /// Nombre de consultations (type Consultation).
  final int consultations;

  /// Dépenses médicales : somme des coûts.
  final double spending;
  final Map<HealthType, double> spendingByType;

  /// Pesées de la période, de la plus ancienne à la plus récente. Vide si
  /// plusieurs animaux sont mélangés (le poids n'a de sens que par animal).
  final List<WeightPoint> weights;

  /// Poids moyen des pesées de la période.
  double? get averageWeight => weights.isEmpty
      ? null
      : weights.fold(0.0, (s, w) => s + w.kg) / weights.length;

  double? get lastWeight => weights.isEmpty ? null : weights.last.kg;

  /// Évolution du poids : dernière pesée − première pesée (kg).
  double? get weightChangeKg =>
      weights.length < 2 ? null : weights.last.kg - weights.first.kg;

  /// Même évolution, relative (0.05 = +5 %).
  double? get weightChangeRatio {
    final change = weightChangeKg;
    return change == null ? null : change / weights.first.kg;
  }

  factory HealthStats.compute(
    Iterable<HealthRecord> records, {
    required DateTime now,
    HealthPeriod period = HealthPeriod.year,
    bool singlePet = true,
  }) {
    final inPeriod = records.where((r) => period.contains(r.date, now)).toList();
    final byType = <HealthType, double>{};
    for (final r in inPeriod) {
      if (r.cost > 0) byType[r.type] = (byType[r.type] ?? 0) + r.cost;
    }
    final weights = !singlePet
        ? <WeightPoint>[]
        : ([
            for (final r in inPeriod)
              if (r.weightKg != null) WeightPoint(r.date, r.weightKg!),
          ]..sort((a, b) => a.date.compareTo(b.date)));

    return HealthStats(
      period: period,
      recordCount: inPeriod.length,
      consultations:
          inPeriod.where((r) => r.type == HealthType.consultation).length,
      spending: inPeriod.fold(0.0, (s, r) => s + r.cost),
      spendingByType: byType,
      weights: weights,
    );
  }
}
