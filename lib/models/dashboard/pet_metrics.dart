import '../activity.dart';
import '../feeding_record.dart';
import '../health_record.dart';
import '../validation.dart';

/// Évolution du poids d'un animal entre deux pesées.
class WeightChange {
  const WeightChange({required this.from, required this.to});

  final HealthRecord from;
  final HealthRecord to;

  double get fromKg => from.weightKg!;
  double get toKg => to.weightKg!;
  double get deltaKg => toKg - fromKg;

  /// Variation relative (0,05 = +5 %).
  double get ratio => fromKg == 0 ? 0 : deltaKg / fromKg;
}

/// Calculs communs du tableau de bord (indice, alertes, coûts, rapport).
/// Fonctions pures, `now` toujours injecté.
abstract final class PetMetrics {
  static const day = Duration(days: 1);

  static DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime monthOf(DateTime d) => DateTime(d.year, d.month);
  static DateTime addMonths(DateTime month, int n) => DateTime(month.year, month.month + n);
  static int daysInMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

  static bool inMonth(DateTime d, DateTime month) =>
      d.year == month.year && d.month == month.month;

  /// [from] inclus, [to] exclu.
  static bool inRange(DateTime d, DateTime from, DateTime to) =>
      !d.isBefore(from) && d.isBefore(to);

  /// Pesées d'un animal (dossiers de santé avec un poids), de la plus
  /// ancienne à la plus récente.
  static List<HealthRecord> weighings(int petId, Iterable<HealthRecord> health) =>
      [for (final h in health) if (h.petId == petId && h.weightKg != null) h]
        ..sort((a, b) => a.date.compareTo(b.date));

  /// Évolution sur environ [days] jours : dernière pesée de la période
  /// comparée à la dernière pesée faite avant le début de la période (ou,
  /// à défaut, à la première de la période). `null` sans deux pesées.
  static WeightChange? weightChange(int petId, Iterable<HealthRecord> health, DateTime now,
      {int days = 60}) {
    final all = weighings(petId, health);
    final start = dayOf(now).subtract(Duration(days: days));
    final recent = [for (final w in all) if (!w.date.isBefore(start)) w];
    if (recent.isEmpty) return null;
    final before = [for (final w in all) if (w.date.isBefore(start)) w];
    final from = before.isNotEmpty ? before.last : recent.first;
    if (identical(from, recent.last)) return null;
    return WeightChange(from: from, to: recent.last);
  }

  /// Dépenses de santé d'un animal (ou de tous si [petId] est null).
  static double healthCost(Iterable<HealthRecord> health, bool Function(DateTime) when,
          {int? petId}) =>
      health
          .where((h) => (petId == null || h.petId == petId) && when(h.date))
          .fold(0.0, (s, h) => s + h.cost);

  static double feedingCost(Iterable<FeedingRecord> feeding, bool Function(DateTime) when,
          {int? petId}) =>
      feeding
          .where((f) => (petId == null || f.petId == petId) && when(f.date))
          .fold(0.0, (s, f) => s + f.price);

  static double feedingGrams(Iterable<FeedingRecord> feeding, int petId,
          bool Function(DateTime) when) =>
      feeding
          .where((f) => f.petId == petId && when(f.date))
          .fold(0.0, (s, f) => s + f.quantityG);

  static int activityMinutes(Iterable<Activity> activities, int petId,
          bool Function(DateTime) when) =>
      activities
          .where((a) => a.petId == petId && when(a.date))
          .fold(0, (s, a) => s + a.durationMin);

  /// « 60 DT », « 12,5 DT ».
  static String money(double v) => '${formatDecimal(v)} DT';

  /// « +5 % », « −12 % ».
  static String percent(double ratio) {
    final p = (ratio * 100).round();
    return p >= 0 ? '+$p %' : '−${-p} %';
  }

  static const monthNames = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];

  /// « octobre 2026 ».
  static String monthLabel(DateTime month) => '${monthNames[month.month - 1]} ${month.year}';

  /// « 03/10 ».
  static String dayMonth(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}
