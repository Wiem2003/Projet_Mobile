import '../activity.dart';
import '../feeding_record.dart';
import '../health_record.dart';
import '../pet.dart';
import '../reminder.dart';
import '../reminder_compliance.dart';
import '../validation.dart';
import 'pet_metrics.dart';

/// Résumé du mois pour un animal.
class PetMonthSummary {
  const PetMonthSummary({
    required this.pet,
    required this.cares,
    required this.feedingCost,
    required this.feedingGrams,
    required this.activities,
    required this.minutes,
    required this.km,
    required this.kcal,
    required this.weightStart,
    required this.weightEnd,
    required this.onTime,
    required this.late,
    required this.missed,
  });

  final Pet pet;

  /// Soins de santé du mois (consultations, vaccins...).
  final List<HealthRecord> cares;
  final double feedingCost;
  final double feedingGrams;
  final int activities;
  final int minutes;
  final double km;
  final double kcal;

  /// Poids au début du mois (dernière pesée avant, ou première du mois)
  /// et à la fin (dernière pesée du mois). `null` sans pesée.
  final double? weightStart;
  final double? weightEnd;

  /// Rappels dont l'échéance tombait dans le mois.
  final int onTime;
  final int late;
  final int missed;

  double get healthCost => cares.fold(0, (s, h) => s + h.cost);
  double get total => healthCost + feedingCost;
  double? get weightDelta =>
      weightStart == null || weightEnd == null ? null : weightEnd! - weightStart!;
}

/// Rapport du mois écoulé, à partager avec le vétérinaire.
class MonthlyReport {
  const MonthlyReport({required this.month, required this.pets, required this.generalReminders});

  final DateTime month;
  final List<PetMonthSummary> pets;

  /// Rappels sans animal (achats...) : faits à temps, en retard, non faits.
  final ({int onTime, int late, int missed}) generalReminders;

  double get healthCost => pets.fold(0, (s, p) => s + p.healthCost);
  double get feedingCost => pets.fold(0, (s, p) => s + p.feedingCost);
  double get total => healthCost + feedingCost;
  int get minutes => pets.fold(0, (s, p) => s + p.minutes);
  double get km => pets.fold(0, (s, p) => s + p.km);
  bool get isEmpty =>
      total == 0 && minutes == 0 && pets.every((p) => p.onTime + p.late + p.missed == 0);

  /// Mois écoulé (rapport disponible à partir du 1er du mois suivant).
  static DateTime previousMonth(DateTime now) => PetMetrics.addMonths(PetMetrics.monthOf(now), -1);

  static String _kg(double v) => '${formatDecimal(v)} kg';

  String get title => 'Rapport Smart Pet - ${PetMetrics.monthLabel(month)}';

  factory MonthlyReport.compute({
    required DateTime month,
    required List<Pet> pets,
    required Iterable<HealthRecord> health,
    required Iterable<FeedingRecord> feeding,
    required Iterable<Activity> activities,
    required Iterable<Reminder> reminders,
    required DateTime now,
  }) {
    bool inMonth(DateTime d) => PetMetrics.inMonth(d, month);
    final end = PetMetrics.addMonths(month, 1);
    // Résultat des échéances jugé à la fin du mois (ou maintenant si le mois
    // est en cours).
    final judgedAt = now.isBefore(end) ? now : end.subtract(const Duration(minutes: 1));

    ({int onTime, int late, int missed}) outcomes(int? petId) {
      var onTime = 0, late = 0, missed = 0;
      for (final r in reminders) {
        if (r.petId != petId || !inMonth(r.dueDate)) continue;
        switch (ComplianceReport.outcomeOf(r, judgedAt)) {
          case ComplianceOutcome.onTime:
            onTime++;
          case ComplianceOutcome.late:
            late++;
          case ComplianceOutcome.missed:
            missed++;
          case null:
            break;
        }
      }
      return (onTime: onTime, late: late, missed: missed);
    }

    final summaries = <PetMonthSummary>[];
    for (final p in pets) {
      final id = p.id!;
      final weighings = PetMetrics.weighings(id, health);
      final during = [for (final w in weighings) if (inMonth(w.date)) w];
      final before = [for (final w in weighings) if (w.date.isBefore(month)) w];
      final acts = [for (final a in activities) if (a.petId == id && inMonth(a.date)) a];
      final o = outcomes(id);
      summaries.add(PetMonthSummary(
        pet: p,
        cares: [for (final h in health) if (h.petId == id && inMonth(h.date)) h]
          ..sort((a, b) => a.date.compareTo(b.date)),
        feedingCost: PetMetrics.feedingCost(feeding, inMonth, petId: id),
        feedingGrams: PetMetrics.feedingGrams(feeding, id, inMonth),
        activities: acts.length,
        minutes: acts.fold(0, (s, a) => s + a.durationMin),
        km: acts.fold(0.0, (s, a) => s + a.distanceKm),
        kcal: acts.fold(0.0, (s, a) => s + a.calories),
        weightStart: (before.isNotEmpty ? before.last : during.firstOrNull)?.weightKg,
        weightEnd: during.lastOrNull?.weightKg,
        onTime: o.onTime,
        late: o.late,
        missed: o.missed,
      ));
    }
    return MonthlyReport(month: month, pets: summaries, generalReminders: outcomes(null));
  }

  /// Version texte (partage par message ou e-mail).
  String toText() {
    final b = StringBuffer()
      ..writeln(title)
      ..writeln()
      ..writeln('DÉPENSES')
      ..writeln('- Santé : ${PetMetrics.money(healthCost)}')
      ..writeln('- Alimentation : ${PetMetrics.money(feedingCost)}')
      ..writeln('- Total : ${PetMetrics.money(total)}');
    for (final p in pets) {
      b
        ..writeln()
        ..writeln('${p.pet.name.toUpperCase()} (${p.pet.species.label})')
        ..writeln('Dépenses : ${PetMetrics.money(p.total)} '
            '(santé ${PetMetrics.money(p.healthCost)}, alimentation ${PetMetrics.money(p.feedingCost)})');
      if (p.cares.isEmpty) {
        b.writeln('Soins : aucun');
      } else {
        b.writeln('Soins :');
        for (final c in p.cares) {
          b.writeln('- ${PetMetrics.dayMonth(c.date)} ${c.type.label}'
              '${c.medication == null ? '' : ' (${c.medication})'}'
              '${c.vet == null ? '' : ', ${c.vet}'} : ${PetMetrics.money(c.cost)}');
        }
      }
      b.writeln('Rappels : ${p.onTime} fait(s) à temps, ${p.late} fait(s) en retard, '
          '${p.missed} non fait(s)');
      b.writeln('Activité : ${p.activities} séance(s), ${p.minutes} min, '
          '${formatDecimal(p.km, decimals: 1)} km, ${p.kcal.round()} kcal');
      final delta = p.weightDelta;
      b.writeln(p.weightEnd == null
          ? 'Poids : aucune pesée ce mois-ci'
          : 'Poids : ${_kg(p.weightEnd!)}'
              '${delta == null || delta == 0 ? '' : ' (${delta > 0 ? '+' : '-'}${_kg(delta.abs())} sur le mois)'}');
    }
    final g = generalReminders;
    if (g.onTime + g.late + g.missed > 0) {
      b
        ..writeln()
        ..writeln('Rappels généraux : ${g.onTime} fait(s) à temps, ${g.late} en retard, '
            '${g.missed} non fait(s)');
    }
    return b.toString().trimRight();
  }
}
