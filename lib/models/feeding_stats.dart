import 'feeding_record.dart';

/// Montant d'un mois (graphique d'évolution).
class MonthAmount {
  const MonthAmount(this.month, this.value);

  /// Premier jour du mois.
  final DateTime month;
  final double value;
}

/// Calculs automatiques du module Alimentation pour un mois donné.
class FeedingStats {
  const FeedingStats({
    required this.month,
    required this.recordCount,
    required this.meals,
    required this.quantityG,
    required this.spending,
    required this.days,
    required this.spendingChange,
    required this.previousSamePeriod,
    this.comparedDays,
    required this.spendingByMonth,
    required this.quantityByType,
  });

  /// Premier jour du mois analysé.
  final DateTime month;
  final int recordCount;
  final int meals;

  /// Quantité consommée sur le mois (g).
  final double quantityG;

  /// Dépense alimentaire du mois.
  final double spending;

  /// Jours pris en compte pour les moyennes : jours écoulés pour le mois en
  /// cours, tous les jours du mois pour un mois passé.
  final int days;

  /// Évolution des dépenses par rapport au mois précédent (0.12 = +12 %),
  /// `null` si le mois précédent n'a aucune dépense sur la même période.
  /// Pour le mois en cours, la comparaison porte sur le même nombre de
  /// jours (du 1er au jour d'aujourd'hui) : un mois commencé n'est pas
  /// comparé à un mois complet.
  final double? spendingChange;

  /// Dépense du mois précédent sur la période comparée.
  final double previousSamePeriod;

  /// Jours comparés (du 1er au N du mois précédent), `null` si les deux
  /// mois sont comparés en entier.
  final int? comparedDays;

  /// Dépenses des derniers mois, du plus ancien au mois analysé.
  final List<MonthAmount> spendingByMonth;
  final Map<FoodType, double> quantityByType;

  /// Moyenne quotidienne consommée (g/jour).
  double get dailyAverageG => days == 0 ? 0 : quantityG / days;

  /// Dépense moyenne par jour.
  double get dailyAverageSpending => days == 0 ? 0 : spending / days;

  double get previousSpending => spendingByMonth.length < 2
      ? 0
      : spendingByMonth[spendingByMonth.length - 2].value;

  static bool _inMonth(DateTime d, DateTime month) =>
      d.year == month.year && d.month == month.month;

  factory FeedingStats.compute(
    Iterable<FeedingRecord> records, {
    required DateTime month,
    required DateTime now,
    int months = 6,
  }) {
    final m = DateTime(month.year, month.month);
    final inMonth = records.where((r) => _inMonth(r.date, m)).toList();

    var quantity = 0.0, spending = 0.0, meals = 0;
    final byType = <FoodType, double>{};
    for (final r in inMonth) {
      quantity += r.quantityG;
      spending += r.price;
      meals += r.meals;
      byType[r.foodType] = (byType[r.foodType] ?? 0) + r.quantityG;
    }

    final current = DateTime(now.year, now.month);
    final days = m.isAfter(current)
        ? 0
        : m == current
            ? now.day
            : DateTime(m.year, m.month + 1, 0).day;

    final byMonth = [
      for (var i = months - 1; i >= 0; i--)
        () {
          final mm = DateTime(m.year, m.month - i);
          return MonthAmount(
            mm,
            records
                .where((r) => _inMonth(r.date, mm))
                .fold(0.0, (sum, r) => sum + r.price),
          );
        }(),
    ];
    // Mois en cours : même nombre de jours au mois précédent.
    final prevMonth = DateTime(m.year, m.month - 1);
    final prevLength = DateTime(prevMonth.year, prevMonth.month + 1, 0).day;
    final compared = m == current && now.day < prevLength ? now.day : null;
    final previous = records
        .where((r) => _inMonth(r.date, prevMonth) && (compared == null || r.date.day <= compared))
        .fold(0.0, (sum, r) => sum + r.price);

    return FeedingStats(
      month: m,
      recordCount: inMonth.length,
      meals: meals,
      quantityG: quantity,
      spending: spending,
      days: days,
      spendingChange: previous == 0 ? null : (spending - previous) / previous,
      previousSamePeriod: previous,
      comparedDays: compared,
      spendingByMonth: byMonth,
      quantityByType: byType,
    );
  }
}
