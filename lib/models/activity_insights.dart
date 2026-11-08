import 'dart:math' as math;

import '../core/pets/pet_directory.dart';
import 'activity.dart';
import 'activity_guidelines.dart';
import 'dashboard/pet_metrics.dart';
import 'feeding_record.dart';
import 'health_record.dart';
import 'nutrition.dart';
import 'pet.dart';
import 'validation.dart';

// ---------------------------------------------------------------- Charge

enum LoadLevel { spike, normal, drop }

/// Charge d'entraînement : 7 derniers jours comparés à la moyenne des 4
/// dernières semaines (charge = minutes × intensité).
class TrainingLoad {
  const TrainingLoad({
    required this.acute,
    required this.chronicWeekly,
    required this.runStreak,
    required this.ranToday,
  });

  /// Charge des 7 derniers jours.
  final double acute;

  /// Charge moyenne par semaine sur 28 jours.
  final double chronicWeekly;

  /// Jours de course d'affilée jusqu'à aujourd'hui (ou hier).
  final int runStreak;
  final bool ranToday;

  double get ratio => chronicWeekly == 0 ? 0 : acute / chronicWeekly;

  LoadLevel get level => ratio > ActivityInsights.spikeRatio
      ? LoadLevel.spike
      : ratio < ActivityInsights.dropRatio
          ? LoadLevel.drop
          : LoadLevel.normal;

  /// Repos conseillé après 2 jours de course d'affilée.
  bool get restAdvised => runStreak >= ActivityInsights.runDaysBeforeRest;
}

// ----------------------------------------------------- Bilan énergétique

/// Apport (repas) − dépense (entretien + activités) sur 14 jours, et poids
/// prévu (indicatif).
class EnergyBalance {
  const EnergyBalance({
    required this.intakePerDay,
    required this.maintenancePerDay,
    required this.activityPerDay,
    required this.loggedDays,
    this.realKgPerMonth,
    this.realFrom,
    this.realTo,
  });

  final double intakePerDay;

  /// Besoin au repos × 1,2 (vie quotidienne hors exercice).
  final double maintenancePerDay;

  /// Calories des activités enregistrées, par jour.
  final double activityPerDay;

  /// Jours avec au moins un repas saisi sur 14.
  final int loggedDays;

  /// Évolution réelle d'après les pesées (module Santé).
  final double? realKgPerMonth;
  final DateTime? realFrom;
  final DateTime? realTo;

  double get spendingPerDay => maintenancePerDay + activityPerDay;
  double get balancePerDay => intakePerDay - spendingPerDay;

  /// 7 700 kcal ≈ 1 kg.
  double get kgPerMonth => balancePerDay * 30 / ActivityInsights.kcalPerKg;

  /// La courbe réelle va dans le même sens (écart de moins de 0,5 kg par
  /// mois). `null` sans pesées.
  bool? get consistent {
    final real = realKgPerMonth;
    if (real == null) return null;
    return (kgPerMonth - real).abs() <= ActivityInsights.toleranceKgPerMonth;
  }
}

// ---------------------------------------------------------------- Records

/// Records d'un animal (ou de tous) et total de l'année.
class ActivityRecords {
  const ActivityRecords({
    this.longest,
    this.fastest,
    this.bestWeek,
    required this.year,
    required this.yearKm,
    required this.yearCount,
    required this.yearMinutes,
  });

  /// Plus longue sortie (distance).
  final Activity? longest;

  /// Sortie la plus rapide (au moins 1 km).
  final Activity? fastest;

  /// Semaine record (lundi → dimanche).
  final ({DateTime start, double km})? bestWeek;

  final int year;
  final double yearKm;
  final int yearCount;
  final int yearMinutes;
}

/// Analyse des activités. Fonctions pures, `now` toujours injecté.
abstract final class ActivityInsights {
  static const spikeRatio = 1.5;
  static const dropRatio = 0.6;
  static const runDaysBeforeRest = 2;

  /// Historique minimal pour comparer aux 4 dernières semaines.
  static const minHistoryDays = 21;

  static const kcalPerKg = 7700.0;
  static const toleranceKgPerMonth = 0.5;
  static const balanceDays = 14;
  static const minLoggedDays = 7;

  /// Une journée au-delà de 1,5 × le maximum conseillé est un excès.
  static const excessFactor = 1.5;

  /// Sortie retenue pour le record de vitesse : au moins 1 km.
  static const minKmForSpeed = 1.0;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static Iterable<Activity> _of(int petId, Iterable<Activity> all) =>
      all.where((a) => a.petId == petId);

  /// Charge d'une activité : minutes × intensité (promenade 3, course 7,
  /// natation 5, jeu 4,5).
  static double loadOf(Activity a) => a.durationMin * a.type.met;

  /// `null` avec moins de 3 semaines d'historique.
  static TrainingLoad? load(int petId, Iterable<Activity> all, DateTime now) {
    final mine = _of(petId, all).where((a) => !a.date.isAfter(now)).toList();
    if (mine.isEmpty) return null;
    final today = _day(now);
    final first = mine.map((a) => a.date).reduce((a, b) => a.isBefore(b) ? a : b);
    if (today.difference(_day(first)).inDays < minHistoryDays) return null;
    final week = today.subtract(const Duration(days: 6));
    final month = today.subtract(const Duration(days: 27));
    double sum(DateTime from) =>
        mine.where((a) => !a.date.isBefore(from)).fold(0.0, (s, a) => s + loadOf(a));
    final runDays = {
      for (final a in mine)
        if (a.type == ActivityType.run) _day(a.date),
    };
    final ranToday = runDays.contains(today);
    var streak = 0;
    var d = ranToday ? today : today.subtract(const Duration(days: 1));
    while (runDays.contains(d)) {
      streak++;
      d = d.subtract(const Duration(days: 1));
    }
    return TrainingLoad(acute: sum(week), chronicWeekly: sum(month) / 4, runStreak: streak,
        ranToday: ranToday);
  }

  /// Messages de charge pour un animal (forte hausse, baisse, repos).
  static List<String> loadMessages(String name, TrainingLoad l) {
    final pct = PetMetrics.percent(l.ratio - 1);
    return [
      if (l.level == LoadLevel.spike)
        '$name : charge en forte hausse ($pct), risque de blessure, prévoyez une journée calme.',
      if (l.level == LoadLevel.drop)
        '$name : baisse d\'activité ($pct par rapport aux 4 dernières semaines).',
      if (l.restAdvised)
        '$name a couru ${l.runStreak} jours d\'affilée : journée de repos conseillée '
            '${l.ranToday ? 'demain' : 'aujourd\'hui'}.',
    ];
  }

  // -------------------------------------------------------- Durée conseillée

  /// « 25 min », « 3 h 10 ».
  static String minutes(num m) {
    final v = m.round();
    if (v < 60) return '$v min';
    final h = v ~/ 60, r = v % 60;
    return r == 0 ? '$h h' : '$h h ${r.toString().padLeft(2, '0')}';
  }

  /// Minutes moyennes par jour sur les 7 derniers jours.
  static double dailyAverage(int petId, Iterable<Activity> all, DateTime now) {
    final from = _day(now).subtract(const Duration(days: 6));
    return _of(petId, all)
            .where((a) => !a.date.isBefore(from) && !a.date.isAfter(now))
            .fold(0, (s, a) => s + a.durationMin) /
        7;
  }

  /// Alertes « pas assez » ou « trop » d'activité, pour un animal dont les
  /// activités sont suivies (au moins une enregistrée).
  static List<String> durationAlerts(PetSummary pet, Iterable<Activity> all, DateTime now) {
    final species = Species.fromLabel(pet.species);
    if (species == null) return const [];
    final range = ActivityGuidelines.dailyMinutes(species, pet.weightKg);
    final profile = ActivityGuidelines.shortProfile(species, pet.weightKg);
    final mine = _of(pet.id, all).where((a) => !a.date.isAfter(now)).toList();
    if (range == null || mine.isEmpty) return const [];
    final today = _day(now);
    final alerts = <String>[];

    if (species == Species.cat) {
      final last = mine.map((a) => _day(a.date)).reduce((a, b) => a.isAfter(b) ? a : b);
      final gap = today.difference(last).inDays;
      if (gap >= 2) alerts.add('${pet.name} : $gap jours sans séance de jeu.');
    } else {
      final avg = dailyAverage(pet.id, all, now);
      if (avg < range.$1) {
        alerts.add('${pet.name} : ${minutes(avg)} par jour en moyenne cette semaine '
            '(conseillé : ${range.$1} à ${range.$2} min pour un $profile).');
      }
    }
    // Excès : une journée bien au-delà du maximum conseillé.
    final byDay = <DateTime, int>{};
    for (final a in mine) {
      if (a.date.isBefore(today.subtract(const Duration(days: 6)))) continue;
      byDay[_day(a.date)] = (byDay[_day(a.date)] ?? 0) + a.durationMin;
    }
    final worst = byDay.entries.fold<MapEntry<DateTime, int>?>(
        null, (m, e) => m == null || e.value > m.value ? e : m);
    if (worst != null && worst.value > range.$2 * excessFactor) {
      alerts.add('${pet.name} : ${minutes(worst.value)} le ${PetMetrics.dayMonth(worst.key)}, '
          'bien au-delà des ${minutes(range.$2)} conseillées ($profile).');
    }
    return alerts;
  }

  // ------------------------------------------------------- Bilan énergétique

  /// `null` sans poids ou avec moins de 7 jours de repas saisis sur 14.
  static EnergyBalance? energy({
    required PetSummary pet,
    required Iterable<FeedingRecord> feeding,
    required Iterable<Activity> activities,
    required Iterable<HealthRecord> health,
    required DateTime now,
  }) {
    final kg = pet.weightKg;
    if (kg == null || kg <= 0) return null;
    final today = _day(now);
    final from = today.subtract(const Duration(days: balanceDays - 1));
    final meals = [
      for (final f in feeding)
        if (f.petId == pet.id && !f.date.isBefore(from) && !f.date.isAfter(today)) f,
    ];
    final days = {for (final f in meals) _day(f.date)}.length;
    if (days < minLoggedDays) return null;
    final burned = _of(pet.id, activities)
        .where((a) => !a.date.isBefore(from) && !a.date.isAfter(now))
        .fold(0.0, (s, a) => s + a.calories);
    final change = PetMetrics.weightChange(pet.id, health, now);
    double? real;
    if (change != null) {
      final span = change.to.date.difference(change.from.date).inDays;
      if (span > 0) real = change.deltaKg / span * 30;
    }
    return EnergyBalance(
      intakePerDay: meals.fold(0.0, (s, f) => s + Nutrition.kcalOf(f)) / days,
      maintenancePerDay: Nutrition.restingKcal(kg) * 1.2,
      activityPerDay: burned / balanceDays,
      loggedDays: days,
      realKgPerMonth: real,
      realFrom: change?.from.date,
      realTo: change?.to.date,
    );
  }

  static String _signedKcal(double v) {
    final r = v.round();
    return r > 0 ? '+$r' : (r < 0 ? '−${-r}' : '0');
  }

  /// « Rex : +220 kcal par jour en moyenne (apport 1 650, dépense 1 430). »
  static String balanceSentence(String name, EnergyBalance b) =>
      '$name : ${_signedKcal(b.balancePerDay)} kcal par jour en moyenne '
      '(apport ${b.intakePerDay.round()}, dépense ${b.spendingPerDay.round()}).';

  /// « À ce rythme, Rex prendrait environ 0,9 kg par mois. »
  static String projectionSentence(String name, EnergyBalance b) {
    final kg = b.kgPerMonth;
    if (kg.abs() < 0.1) return 'À ce rythme, le poids de $name resterait stable.';
    return 'À ce rythme, $name ${kg > 0 ? 'prendrait' : 'perdrait'} environ '
        '${formatDecimal(kg.abs(), decimals: 1)} kg par mois.';
  }

  /// Comparaison avec la courbe de poids réelle.
  static String? realSentence(EnergyBalance b) {
    final real = b.realKgPerMonth;
    if (real == null) return null;
    final trend = real.abs() < 0.1
        ? 'stable'
        : '${real > 0 ? '+' : '−'}${formatDecimal(real.abs(), decimals: 1)} kg par mois';
    final period = 'pesées du ${PetMetrics.dayMonth(b.realFrom!)} au ${PetMetrics.dayMonth(b.realTo!)}';
    return b.consistent!
        ? 'Courbe réelle ($period) : $trend, cohérente avec la projection.'
        : 'Courbe réelle ($period) : $trend, elle ne confirme pas la projection : '
            'vérifiez les quantités et les calories saisies.';
  }

  // ---------------------------------------------------------------- Records

  static DateTime weekStart(DateTime d) => _day(d).subtract(Duration(days: d.weekday - 1));

  /// Records de [petId] (tous les animaux si `null`) et total de [year].
  static ActivityRecords records(Iterable<Activity> all, {int? petId, required int year}) {
    final mine = petId == null ? all.toList() : _of(petId, all).toList();
    Activity? longest, fastest;
    final weeks = <DateTime, double>{};
    var yearKm = 0.0, yearCount = 0, yearMin = 0;
    for (final a in mine) {
      if (a.distanceKm > 0 && (longest == null || a.distanceKm > longest.distanceKm)) longest = a;
      final speed = a.speedKmh;
      if (speed != null &&
          a.distanceKm >= minKmForSpeed &&
          (fastest == null || speed > fastest.speedKmh!)) {
        fastest = a;
      }
      weeks[weekStart(a.date)] = (weeks[weekStart(a.date)] ?? 0) + a.distanceKm;
      if (a.date.year == year) {
        yearKm += a.distanceKm;
        yearCount++;
        yearMin += a.durationMin;
      }
    }
    final best = weeks.entries.where((e) => e.value > 0).fold<MapEntry<DateTime, double>?>(
        null, (m, e) => m == null || e.value > m.value ? e : m);
    return ActivityRecords(
      longest: longest,
      fastest: fastest,
      bestWeek: best == null ? null : (start: best.key, km: best.value),
      year: year,
      yearKm: yearKm,
      yearCount: yearCount,
      yearMinutes: yearMin,
    );
  }

  static String km(double v) => '${formatDecimal(v, decimals: 1)} km';

  /// Records battus par [added] (il faut une sortie précédente à battre).
  static List<String> newRecords(Iterable<Activity> before, Activity added, String name) {
    final previous = _of(added.petId, before).where((a) => a.id != added.id).toList();
    if (previous.isEmpty) return const [];
    final old = records(previous, year: added.date.year);
    final now = records([...previous, added], year: added.date.year);
    final out = <String>[];
    if (old.longest != null && identical(now.longest, added)) {
      out.add('Nouveau record pour $name : ${km(added.distanceKm)} !');
    }
    if (old.fastest != null && identical(now.fastest, added)) {
      out.add('Nouveau record de vitesse pour $name : '
          '${formatDecimal(added.speedKmh!, decimals: 1)} km/h !');
    }
    final ob = old.bestWeek, nb = now.bestWeek;
    if (ob != null && nb != null && nb.km > ob.km && nb.start == weekStart(added.date)) {
      out.add('Semaine record pour $name : ${km(nb.km)} !');
    }
    return out;
  }

  /// « 2026 : 412 km, 186 activités. »
  static String yearSentence(ActivityRecords r) =>
      '${r.year} : ${km(r.yearKm)}, ${r.yearCount} activité${r.yearCount > 1 ? 's' : ''}, '
      '${minutes(r.yearMinutes)}.';

  static double clampRatio(double v) => math.max(0, math.min(v, 3));
}
