import 'activity.dart';

/// Calories estimées : MET du type × poids (kg) × durée (h).
double estimateCalories(ActivityType type, double? weightKg, int durationMin) =>
    weightKg == null || weightKg <= 0 || durationMin <= 0
        ? 0
        : type.met * weightKg * durationMin / 60;

/// Période choisie pour le nombre d'activités et la durée moyenne.
enum ActivityPeriod {
  week('7 jours', 7),
  month('30 jours', 30),
  quarter('3 mois', 90),
  all('Tout', null);

  const ActivityPeriod(this.label, this.days);

  final String label;
  final int? days;

  /// Début de la période (minuit), `null` pour « Tout ».
  DateTime? startFrom(DateTime now) =>
      days == null ? null : DateTime(now.year, now.month, now.day - days! + 1);

  bool contains(DateTime date, DateTime now) {
    final start = startFrom(now);
    return start == null || !date.isBefore(start);
  }
}

/// Totaux d'une semaine glissante (7 jours).
class WeekAmount {
  const WeekAmount({
    required this.start,
    required this.distanceKm,
    required this.minutes,
    required this.count,
  });

  /// Premier jour de la semaine (minuit).
  final DateTime start;
  final double distanceKm;
  final int minutes;
  final int count;
}

/// Calculs automatiques du module Activités.
///
/// Les semaines sont glissantes : la semaine actuelle couvre les 7 derniers
/// jours (aujourd'hui compris), la précédente les 7 jours d'avant.
class ActivityStats {
  const ActivityStats({
    required this.period,
    required this.count,
    required this.totalMinutes,
    required this.totalDistanceKm,
    required this.totalCalories,
    required this.weeks,
  });

  final ActivityPeriod period;

  /// Nombre d'activités sur la période choisie.
  final int count;
  final int totalMinutes;
  final double totalDistanceKm;
  final double totalCalories;

  /// Semaines glissantes, de la plus ancienne à la semaine actuelle.
  final List<WeekAmount> weeks;

  /// Durée moyenne : durée totale / nombre d'activités.
  double get averageDurationMin => count == 0 ? 0 : totalMinutes / count;

  WeekAmount get thisWeek => weeks.last;
  WeekAmount? get lastWeek => weeks.length < 2 ? null : weeks[weeks.length - 2];

  /// Distance hebdomadaire : somme des distances sur 7 jours.
  double get weeklyDistanceKm => thisWeek.distanceKm;

  /// Évolution de la distance (0.2 = +20 %), `null` sans base de comparaison.
  double? get distanceChange =>
      _change(thisWeek.distanceKm, lastWeek?.distanceKm ?? 0);

  /// Évolution du temps d'activité, semaine actuelle / semaine précédente.
  double? get minutesChange =>
      _change(thisWeek.minutes.toDouble(), (lastWeek?.minutes ?? 0).toDouble());

  static double? _change(double current, double previous) =>
      previous == 0 ? null : (current - previous) / previous;

  factory ActivityStats.compute(
    Iterable<Activity> activities, {
    required DateTime now,
    ActivityPeriod period = ActivityPeriod.month,
    int weekCount = 6,
  }) {
    var count = 0, minutes = 0;
    var distance = 0.0, calories = 0.0;
    for (final a in activities) {
      if (!period.contains(a.date, now)) continue;
      count++;
      minutes += a.durationMin;
      distance += a.distanceKm;
      calories += a.calories;
    }

    final today = DateTime(now.year, now.month, now.day);
    final weeks = [
      for (var i = weekCount - 1; i >= 0; i--)
        () {
          final start = DateTime(today.year, today.month, today.day - 7 * i - 6);
          final end = DateTime(start.year, start.month, start.day + 7);
          final inWeek = activities
              .where((a) => !a.date.isBefore(start) && a.date.isBefore(end));
          return WeekAmount(
            start: start,
            distanceKm: inWeek.fold(0.0, (s, a) => s + a.distanceKm),
            minutes: inWeek.fold(0, (s, a) => s + a.durationMin),
            count: inWeek.length,
          );
        }(),
    ];

    return ActivityStats(
      period: period,
      count: count,
      totalMinutes: minutes,
      totalDistanceKm: distance,
      totalCalories: calories,
      weeks: weeks,
    );
  }
}
