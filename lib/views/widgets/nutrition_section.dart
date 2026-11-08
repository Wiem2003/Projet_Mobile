import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/feeding_plan_controller.dart';
import '../../controllers/nutrition_controller.dart';
import '../../core/pets/pet_directory.dart';
import '../../core/theme/app_colors.dart';
import '../../models/activities_model.dart';
import '../../models/activity.dart';
import '../../models/feeding_insights.dart';
import '../../models/feeding_model.dart';
import '../../models/feeding_record.dart';
import '../../models/health_model.dart';
import '../../models/health_record.dart';
import '../../models/meal_schedule.dart';
import '../../models/nutrition.dart';
import '../../models/pet.dart';
import '../health_actions.dart';
import 'feeding_plan_cards.dart';

/// Section « Nutrition » de l'écran Alimentation : alertes (friandises,
/// baisse d'appétit) et, pour l'animal choisi, ration conseillée et
/// horaires des repas.
class NutritionSection extends StatelessWidget {
  const NutritionSection({super.key});

  static const _color = AppColors.feeding;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<FeedingModel>();
    final activities = context.watch<ActivitiesModel>().all;
    final schedule = context.watch<NutritionModel>().schedule;
    final diets = context.watch<FeedingPlanModel>().plan.diets;
    final health = context.watch<HealthModel>().all;
    final now = model.now;
    final selected = model.petOf(model.petFilter);
    final pets = selected == null ? model.pets : [selected];
    DietProgress? progressOf(PetSummary p) => switch (diets[p.id]) {
          final plan? => FeedingInsights.diet(plan, Species.fromLabel(p.species), health),
          null => null,
        };
    final dietSpecies = selected != null &&
        const [Species.dog, Species.cat].contains(Species.fromLabel(selected.species));

    final alerts = <Widget>[
      for (final p in pets) ..._alerts(context, p, model.all, now),
      // Perte trop rapide : signalée aussi quand tous les animaux sont affichés.
      if (selected == null)
        for (final p in pets)
          if (progressOf(p) case final d?)
            if (FeedingInsights.dietWarning(p.name, d) case final w?)
              _Alert(icon: Icons.monitor_weight_outlined, text: w),
    ];
    if (selected == null && alerts.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.monitor_heart_outlined, color: _color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(selected == null ? 'Nutrition' : 'Nutrition de ${selected.name}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ],
            ),
            if (selected != null) ...[
              const SizedBox(height: 8),
              _Ration(
                  pet: selected,
                  feeding: model.all,
                  activities: activities,
                  now: now,
                  targetKg: diets[selected.id]?.targetKg),
            ],
            ...alerts,
            if (selected != null && dietSpecies) ...[
              const Divider(height: 20),
              DietPanel(pet: selected, progress: progressOf(selected)),
            ],
            if (selected != null) ...[
              const Divider(height: 20),
              _MealTimes(pet: selected, times: schedule.of(selected.id)),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Choisissez un animal pour voir sa ration et ses horaires.',
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
          ],
        ),
      ),
    );
  }

  static List<Widget> _alerts(
      BuildContext context, PetSummary p, List<FeedingRecord> feeding, DateTime now) {
    final treats = Nutrition.treats(p.id, feeding, now);
    final appetite = Nutrition.appetite(p.id, feeding, now);
    return [
      if (treats != null && treats.tooMuch)
        _Alert(
          icon: Icons.cookie_outlined,
          text: '${p.name} : ${Nutrition.percent(treats.share)} de ses calories en friandises '
              'cette semaine (${Nutrition.percent(Nutrition.maxTreatsShare)} maximum).',
        ),
      if (appetite != null)
        _Alert(
          icon: Icons.trending_down_rounded,
          text: Nutrition.appetiteSentence(p.name, appetite),
          action: TextButton.icon(
            icon: const Icon(Icons.medical_services_outlined, size: 18),
            label: const Text('Créer un dossier Santé'),
            onPressed: () => HealthActions.openForm(
              context,
              preset: HealthRecord(
                petId: p.id,
                type: HealthType.consultation,
                date: now,
                description: 'Baisse d\'appétit : ${(-appetite.change * 100).round()} % de moins '
                    'en une semaine (${appetite.recentPerDay.round()} g par jour au lieu de '
                    '${appetite.previousPerDay.round()} g).',
              ),
            ),
          ),
        ),
    ];
  }
}

class _Ration extends StatelessWidget {
  const _Ration(
      {required this.pet,
      required this.feeding,
      required this.activities,
      required this.now,
      this.targetKg});

  final PetSummary pet;
  final List<FeedingRecord> feeding;
  final List<Activity> activities;
  final DateTime now;

  /// Poids cible du programme de perte de poids en cours.
  final double? targetKg;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final advice = Nutrition.ration(
        pet: pet, feeding: feeding, activities: activities, now: now, targetKg: targetKg);
    if (advice == null) {
      return Text(
        pet.weightKg == null
            ? 'Renseignez le poids de ${pet.name} pour calculer sa ration.'
            : 'Pas de ration de référence pour cette espèce.',
        style: TextStyle(color: muted),
      );
    }
    final gap = advice.gap;
    final over = gap != null && gap.abs() > 0.15;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(Nutrition.rationSentence(pet.name, advice),
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: over ? const Color(0xFFB45309) : null)),
        const SizedBox(height: 4),
        Text(
          'Besoin : ${Nutrition.kcal(advice.dailyKcal)} par jour '
          '(${advice.restingKcal.round()} kcal au repos × ${Nutrition.decimal(advice.factor)}, '
          '${advice.factorLabel}) · ${advice.foodType.label.toLowerCase()} à '
          '${advice.kcalPer100g.round()} kcal / 100 g'
          '${advice.kcalEstimated ? ' (valeur typique)' : ''}',
          style: TextStyle(fontSize: 12.5, color: muted),
        ),
        if (advice.actualKcalPerDay != null)
          Text('Apport réel : ${Nutrition.kcal(advice.actualKcalPerDay!)} par jour, friandises comprises',
              style: TextStyle(fontSize: 12.5, color: muted)),
        Text('Indicatif, à confirmer avec le vétérinaire.',
            style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: muted)),
      ],
    );
  }
}

class _Alert extends StatelessWidget {
  const _Alert({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: const Color(0xFFB45309)),
                const SizedBox(width: 8),
                Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
              ],
            ),
            if (action != null) Align(alignment: Alignment.centerRight, child: action),
            if (action == null) const SizedBox(height: 4),
          ],
        ),
      );
}

class _MealTimes extends StatelessWidget {
  const _MealTimes({required this.pet, required this.times});

  final PetSummary pet;
  final List<MealTime> times;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<NutritionController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Horaires des repas', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final t in times)
              InputChip(
                avatar: const Icon(Icons.notifications_active_outlined, size: 18),
                label: Text(t.label),
                deleteButtonTooltipMessage: 'Retirer ${t.label}',
                onDeleted: () => controller.removeTime(pet.id, t),
              ),
            if (times.length < MealSchedule.maxPerPet)
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ajouter un horaire'),
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    helpText: 'Heure du repas de ${pet.name}',
                    initialTime: const TimeOfDay(hour: 19, minute: 0),
                  );
                  if (picked == null) return;
                  await controller.addTime(pet.id, MealTime(picked.hour, picked.minute));
                },
              ),
          ],
        ),
        if (times.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Notification chaque jour : « Repas de ${pet.name}, ${times.first.label} ».',
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
      ],
    );
  }
}
