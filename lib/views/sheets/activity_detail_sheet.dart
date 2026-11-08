import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/activities_model.dart';
import '../../models/activity.dart';
import '../activity_actions.dart';
import '../activity_style.dart';
import '../widgets/pet_avatar.dart';
import '../widgets/route_trace.dart';

Future<void> showActivityDetailSheet(BuildContext context, Activity activity) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ActivityDetail(activity: activity, parent: context),
  );
}

class _ActivityDetail extends StatelessWidget {
  const _ActivityDetail({required this.activity, required this.parent});

  final Activity activity;

  /// Contexte de l'écran : les actions survivent à la fermeture de la feuille.
  final BuildContext parent;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final pet = context.read<ActivitiesModel>().petOf(a.petId);
    final theme = Theme.of(context);
    final speed = a.speedKmh;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: a.hasRoute ? 0.85 : 0.6,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: a.type.color.withValues(alpha: 0.12),
                child: Icon(a.type.icon, color: a.type.color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.type.label,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Text(Fmt.dateTime(a.date),
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (pet != null)
                Chip(
                  avatar: PetAvatar(pet: pet, size: 22),
                  label: Text(pet.name),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (a.hasRoute) ...[
            RouteTrace(points: a.route, color: a.type.color, height: 240),
            const SizedBox(height: 6),
            Text('Trajet enregistré au GPS · ${a.route.length} points',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 14),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Metric(Icons.timer_outlined, 'Durée', Units.minutes(a.durationMin)),
              if (a.type.usesDistance)
                _Metric(Icons.straighten_rounded, 'Distance', Units.km(a.distanceKm)),
              if (speed != null)
                _Metric(Icons.speed_rounded, 'Vitesse moy.', Units.speed(speed)),
              _Metric(Icons.local_fire_department_rounded, 'Calories',
                  Units.kcal(a.calories)),
            ],
          ),
          if (a.weightKg != null) ...[
            const SizedBox(height: 10),
            Text(
              'Calories estimées : MET ${a.type.met} × ${Units.kg(a.weightKg!)} '
              '× ${Units.minutes(a.durationMin)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (a.description != null) ...[
            const SizedBox(height: 18),
            Text('Description',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(a.description!),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger),
                  onPressed: () async {
                    Navigator.pop(context);
                    await ActivityActions.delete(parent, a);
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Supprimer'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.activity),
                  onPressed: () {
                    Navigator.pop(context);
                    ActivityActions.openForm(parent, activity: a);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifier'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.activity),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                Text(value,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
