import '../activity.dart';
import '../activity_guidelines.dart';
import '../feeding_record.dart';
import '../health_record.dart';
import '../pet.dart';
import '../reminder.dart';
import '../reminder_rules.dart';
import 'pet_metrics.dart';

/// Un critère de l'indice : points obtenus sur [max], et la raison des
/// points perdus.
class IndexCriterion {
  const IndexCriterion({
    required this.label,
    required this.module,
    required this.max,
    required this.points,
    this.reason,
  });

  final String label;

  /// Module d'où viennent les données.
  final String module;
  final int max;
  final int points;
  final String? reason;

  int get lost => max - points;
}

enum IndexLevel {
  good('Très bien'),
  medium('À surveiller'),
  low('À améliorer');

  const IndexLevel(this.label);

  final String label;
}

/// Indice Smart Pet d'un animal (0 à 100).
class PetIndex {
  const PetIndex({required this.pet, required this.criteria});

  final Pet pet;
  final List<IndexCriterion> criteria;

  int get score => criteria.fold(0, (s, c) => s + c.points);

  IndexLevel get level => score >= SmartPetIndex.goodFrom
      ? IndexLevel.good
      : score >= SmartPetIndex.mediumFrom
          ? IndexLevel.medium
          : IndexLevel.low;

  /// Ce qui fait baisser la note, du plus pénalisant au moins pénalisant :
  /// « −25 : 2 rappels critiques ».
  List<String> get deductions => [
        for (final c in [...criteria]..sort((a, b) => b.lost.compareTo(a.lost)))
          if (c.lost > 0 && c.reason != null) '−${c.lost} : ${c.reason}',
      ];

  /// « Mia : 64 (−25 : 2 rappels critiques, −11 : peu d'activité) ».
  String get summary => deductions.isEmpty
      ? '${pet.name} : $score'
      : '${pet.name} : $score (${deductions.join(', ')})';
}

/// Calcul de l'indice : soins (30), activité (25), poids (25), repas (20).
abstract final class SmartPetIndex {
  static const careMax = 30;
  static const activityMax = 25;
  static const weightMax = 25;
  static const mealsMax = 20;

  static const goodFrom = 80;
  static const mediumFrom = 50;

  /// Points perdus par rappel critique (plus de 3 jours de retard) ou
  /// simplement en retard.
  static const criticalPenalty = 15;
  static const overduePenalty = 5;

  /// Poids stable : variation de moins de 5 % sur 2 mois.
  static const stableRatio = 0.05;
  static const watchRatio = 0.10;

  /// Objectif d'activité par semaine (minutes), selon l'espèce et la
  /// taille. Les autres espèces ne sont pas concernées : points complets.
  static int? weeklyGoalMinutes(Species s, double? kg) =>
      ActivityGuidelines.weeklyGoalMinutes(s, kg);

  static String _plural(int n, String word) => '$n $word${n > 1 ? 's' : ''}';

  static PetIndex compute(
    Pet pet, {
    required Iterable<Reminder> reminders,
    required Iterable<Activity> activities,
    required Iterable<HealthRecord> health,
    required Iterable<FeedingRecord> feeding,
    required DateTime now,
  }) {
    final id = pet.id!;
    return PetIndex(pet: pet, criteria: [
      _care(id, reminders, now),
      _activity(pet, activities, now),
      _weight(id, health, now),
      _meals(id, feeding, now),
    ]);
  }

  static IndexCriterion _care(int petId, Iterable<Reminder> reminders, DateTime now) {
    var critical = 0, overdue = 0;
    for (final r in reminders) {
      if (r.petId != petId || !r.isOverdue(now)) continue;
      ReminderRules.isCritical(r, now) ? critical++ : overdue++;
    }
    final lost = critical * criticalPenalty + overdue * overduePenalty;
    final points = (careMax - lost).clamp(0, careMax);
    final reasons = [
      if (critical > 0) critical == 1 ? '1 rappel critique' : '$critical rappels critiques',
      if (overdue > 0) '${_plural(overdue, 'rappel')} en retard',
    ];
    return IndexCriterion(
      label: 'Soins à jour',
      module: 'Rappels',
      max: careMax,
      points: points,
      reason: reasons.isEmpty ? null : reasons.join(' et '),
    );
  }

  static IndexCriterion _activity(Pet pet, Iterable<Activity> activities, DateTime now) {
    final goal = weeklyGoalMinutes(pet.species, pet.weightKg);
    if (goal == null) {
      return const IndexCriterion(
          label: 'Activité de la semaine', module: 'Activités', max: activityMax,
          points: activityMax, reason: 'pas d\'objectif pour cette espèce');
    }
    final from = PetMetrics.dayOf(now).subtract(const Duration(days: 6));
    final minutes = PetMetrics.activityMinutes(
        activities, pet.id!, (d) => !d.isBefore(from) && !d.isAfter(now));
    final ratio = minutes >= goal ? 1.0 : minutes / goal;
    final points = (activityMax * ratio).round();
    return IndexCriterion(
      label: 'Activité de la semaine',
      module: 'Activités',
      max: activityMax,
      points: points,
      reason: points < activityMax ? 'peu d\'activité ($minutes / $goal min)' : null,
    );
  }

  static IndexCriterion _weight(int petId, Iterable<HealthRecord> health, DateTime now) {
    final all = PetMetrics.weighings(petId, health);
    final from = PetMetrics.dayOf(now).subtract(const Duration(days: 60));
    final hasRecent = all.any((w) => !w.date.isBefore(from));
    if (!hasRecent) {
      return const IndexCriterion(
          label: 'Poids stable', module: 'Santé', max: weightMax, points: 15,
          reason: 'aucune pesée depuis 2 mois');
    }
    final change = PetMetrics.weightChange(petId, health, now);
    if (change == null) {
      return const IndexCriterion(
          label: 'Poids stable', module: 'Santé', max: weightMax, points: 20,
          reason: 'une seule pesée : évolution inconnue');
    }
    final variation = change.ratio.abs();
    final points = variation < stableRatio
        ? weightMax
        : variation < watchRatio
            ? 12
            : 0;
    return IndexCriterion(
      label: 'Poids stable',
      module: 'Santé',
      max: weightMax,
      points: points,
      reason: points < weightMax ? 'poids ${PetMetrics.percent(change.ratio)} en 2 mois' : null,
    );
  }

  static IndexCriterion _meals(int petId, Iterable<FeedingRecord> feeding, DateTime now) {
    final today = PetMetrics.dayOf(now);
    final from = today.subtract(const Duration(days: 6));
    final days = {
      for (final f in feeding)
        if (f.petId == petId && !f.date.isBefore(from) && !f.date.isAfter(today))
          PetMetrics.dayOf(f.date),
    }.length;
    final points = (mealsMax * days / 7).round();
    return IndexCriterion(
      label: 'Repas saisis',
      module: 'Alimentation',
      max: mealsMax,
      points: points,
      reason: days < 7 ? 'repas saisis $days jour${days > 1 ? 's' : ''} sur 7' : null,
    );
  }
}
