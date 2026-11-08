import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/pets/pet_directory.dart';
import '../../core/theme/app_colors.dart';
import '../../models/activities_model.dart';
import '../../models/activity.dart';
import '../../models/activity_guidelines.dart';
import '../../models/activity_insights.dart';
import '../../models/dashboard/pet_metrics.dart';
import '../../models/feeding_model.dart';
import '../../models/health_model.dart';
import '../../models/pet.dart';
import '../../models/validation.dart';

/// Section « Analyse » de l'écran Activités : alertes (charge, repos,
/// durée) et, pour l'animal choisi, charge d'entraînement, durée
/// conseillée, bilan énergétique et records.
class ActivityInsightsSection extends StatelessWidget {
  const ActivityInsightsSection({super.key});

  static const _color = AppColors.activity;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<ActivitiesModel>();
    final now = model.now;
    final all = model.all;
    final selected = model.petOf(model.petFilter);
    final pets = selected == null ? model.pets : [selected];

    final alerts = [
      for (final p in pets) ...[
        if (ActivityInsights.load(p.id, all, now) case final l?)
          ...ActivityInsights.loadMessages(p.name, l),
        ...ActivityInsights.durationAlerts(p, all, now),
      ],
    ];
    final year = ActivityInsights.records(all, petId: selected?.id, year: now.year);
    if (selected == null && alerts.isEmpty && year.yearCount == 0) {
      return const SizedBox.shrink();
    }
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights_rounded, color: _color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(selected == null ? 'Analyse' : 'Analyse de ${selected.name}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ],
            ),
            for (final r in model.lastRecords[selected?.id] ?? const <String>[])
              _Line(icon: Icons.emoji_events_rounded, color: AppColors.warning, text: r, bold: true),
            for (final a in alerts) _Alert(a),
            if (selected != null) ...[
              _LoadCard(pet: selected, all: all, now: now),
              _DurationAdvice(pet: selected, all: all, now: now),
              _Energy(pet: selected, all: all, now: now),
              _Records(records: year, name: selected.name),
            ] else ...[
              if (year.yearCount > 0)
                _Line(icon: Icons.calendar_month_rounded, color: _color,
                    text: 'Bilan de l\'année ${ActivityInsights.yearSentence(year)}'),
              Text('Choisissez un animal pour voir sa charge, son bilan énergétique et ses records.',
                  style: TextStyle(fontSize: 12, color: muted)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.color, required this.text, this.bold = false});

  final IconData icon;
  final Color color;
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : null)),
            ),
          ],
        ),
      );
}

class _Alert extends StatelessWidget {
  const _Alert(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 20, color: Color(0xFFB45309)),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}

class _LoadCard extends StatelessWidget {
  const _LoadCard({required this.pet, required this.all, required this.now});

  final PetSummary pet;
  final List<Activity> all;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final l = ActivityInsights.load(pet.id, all, now);
    if (l == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Title('Charge d\'entraînement'),
          Text('Il faut 3 semaines d\'activités pour comparer aux 4 dernières semaines.',
              style: TextStyle(fontSize: 12.5, color: muted)),
        ],
      );
    }
    final color = switch (l.level) {
      LoadLevel.spike => AppColors.danger,
      LoadLevel.drop => AppColors.warning,
      LoadLevel.normal => AppColors.success,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Title('Charge d\'entraînement'),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ActivityInsights.clampRatio(l.ratio) / 3,
                  minHeight: 8,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('× ${formatDecimal(l.ratio, decimals: 2)}',
                style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '7 derniers jours : ${l.acute.round()} points · moyenne des 4 semaines : '
          '${l.chronicWeekly.round()} (zone normale de × 0,6 à × 1,5)',
          style: TextStyle(fontSize: 12.5, color: muted),
        ),
      ],
    );
  }
}

class _DurationAdvice extends StatelessWidget {
  const _DurationAdvice({required this.pet, required this.all, required this.now});

  final PetSummary pet;
  final List<Activity> all;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final species = Species.fromLabel(pet.species);
    final range = species == null ? null : ActivityGuidelines.dailyMinutes(species, pet.weightKg);
    if (range == null) return const SizedBox.shrink();
    final avg = ActivityInsights.dailyAverage(pet.id, all, now);
    final profile = ActivityGuidelines.profile(species!, pet.weightKg);
    final ratio = avg / range.$1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Title('Durée conseillée'),
        Text(species == Species.cat
            ? '2 séances de jeu de 15 min par jour (chat)'
            : '${range.$1} à ${range.$2} min par jour ($profile)'),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio.clamp(0, 1).toDouble(),
            minHeight: 8,
            color: ratio >= 1 ? AppColors.success : AppColors.activity,
            backgroundColor: AppColors.activity.withValues(alpha: 0.12),
          ),
        ),
        Text('Cette semaine : ${ActivityInsights.minutes(avg)} par jour en moyenne',
            style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _Energy extends StatelessWidget {
  const _Energy({required this.pet, required this.all, required this.now});

  final PetSummary pet;
  final List<Activity> all;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final b = ActivityInsights.energy(
      pet: pet,
      feeding: context.watch<FeedingModel>().all,
      activities: all,
      health: context.watch<HealthModel>().all,
      now: now,
    );
    if (b == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Title('Bilan énergétique'),
          Text(
            pet.weightKg == null
                ? 'Renseignez le poids de ${pet.name} pour calculer son bilan.'
                : 'Saisissez les repas d\'au moins ${ActivityInsights.minLoggedDays} jours sur '
                    '${ActivityInsights.balanceDays} pour calculer le bilan.',
            style: TextStyle(fontSize: 12.5, color: muted),
          ),
        ],
      );
    }
    final real = ActivityInsights.realSentence(b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Title('Bilan énergétique (14 jours)'),
        Text(ActivityInsights.balanceSentence(pet.name, b),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(ActivityInsights.projectionSentence(pet.name, b)),
        Text(
          'Dépense = besoin au repos × 1,2 (${b.maintenancePerDay.round()} kcal) + activités '
          '(${b.activityPerDay.round()} kcal par jour) · repas saisis ${b.loggedDays} jours sur 14',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        if (real != null)
          Text(real,
              style: TextStyle(
                  fontSize: 12.5,
                  color: b.consistent! ? AppColors.success : const Color(0xFFB45309))),
        Text('Indicatif, à confirmer avec le vétérinaire.',
            style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: muted)),
      ],
    );
  }
}

class _Records extends StatelessWidget {
  const _Records({required this.records, required this.name});

  final ActivityRecords records;
  final String name;

  @override
  Widget build(BuildContext context) {
    final r = records;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final rows = [
      if (r.longest case final a?)
        ('Plus longue sortie', '${ActivityInsights.km(a.distanceKm)} · ${PetMetrics.dayMonth(a.date)}'),
      if (r.fastest case final a?)
        ('Plus rapide', '${formatDecimal(a.speedKmh!, decimals: 1)} km/h · ${PetMetrics.dayMonth(a.date)}'),
      if (r.bestWeek case final w?)
        ('Semaine record', '${ActivityInsights.km(w.km)} · semaine du ${PetMetrics.dayMonth(w.start)}'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Title('Records'),
        if (rows.isEmpty)
          Text('Pas encore de sortie avec une distance.', style: TextStyle(fontSize: 12.5, color: muted))
        else
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events_outlined, size: 16, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
                  Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        const SizedBox(height: 4),
        Text('Bilan de l\'année ${ActivityInsights.yearSentence(r)}',
            style: TextStyle(fontSize: 12.5, color: muted)),
      ],
    );
  }
}
