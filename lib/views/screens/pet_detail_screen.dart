import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/health_model.dart';
import '../../models/health_stats.dart';
import '../../models/pet.dart';
import '../../models/pets_model.dart';
import '../health_style.dart';
import '../pet_actions.dart';
import '../widgets/line_chart_card.dart';
import '../widgets/pet_photo.dart';
import '../widgets/vaccination_card.dart';

/// « Consulter » : fiche complète d'un animal et résumé de sa santé.
class PetDetailScreen extends StatelessWidget {
  const PetDetailScreen({super.key, required this.petId});

  final int petId;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<PetsModel>();
    final pet = model.byId(petId);
    if (pet == null) {
      // Supprimé entre-temps.
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Animal introuvable.')));
    }
    final now = model.now;
    final health = context.watch<HealthModel>();
    final records = health.all.where((r) => r.petId == petId).toList();
    final stats =
        HealthStats.compute(records, now: now, period: HealthPeriod.all);
    final today = DateTime(now.year, now.month, now.day);
    final next = records
        .where((r) => r.nextDue != null && !r.nextDue!.isBefore(today))
        .toList()
      ..sort((a, b) => a.nextDue!.compareTo(b.nextDue!));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(pet.name),
        actions: [
          IconButton(
            tooltip: 'Modifier',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => PetActions.openForm(context, pet: pet),
          ),
          IconButton(
            tooltip: 'Supprimer',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              final navigator = Navigator.of(context);
              if (await PetActions.delete(context, pet)) navigator.pop();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(child: PetPhoto.of(pet, size: 140)),
          const SizedBox(height: 12),
          Text(pet.name,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          Text(
            [
              '${pet.species.emoji} ${pet.species.label}',
              ?pet.breed,
              if (pet.sex != PetSex.unknown) '${pet.sex.symbol} ${pet.sex.label}',
            ].join(' · '),
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                _Info(Icons.cake_outlined, 'Naissance',
                    pet.birthDate == null
                        ? 'Non renseignée'
                        : '${Fmt.long(pet.birthDate!)} (${pet.ageLabel(now)})'),
                _Info(Icons.monitor_weight_outlined, 'Poids',
                    pet.weightKg == null ? 'Non renseigné' : Units.kg(pet.weightKg!)),
                _Info(Icons.palette_outlined, 'Couleur', pet.color ?? 'Non renseignée'),
                _Info(Icons.qr_code_2_rounded, 'Identification',
                    pet.identification ?? 'Non renseignée'),
                _Info(Icons.health_and_safety_outlined, 'Stérilisé(e)',
                    pet.sterilized ? 'Oui' : 'Non'),
                _Info(Icons.warning_amber_rounded, 'Allergies',
                    pet.allergies ?? 'Aucune allergie connue'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Santé',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                _Info(Icons.folder_shared_outlined, 'Dossiers de santé',
                    '${stats.recordCount} · ${stats.consultations} consultation(s)'),
                _Info(Icons.payments_outlined, 'Dépenses médicales',
                    Units.money(stats.spending)),
                _Info(
                  Icons.event_available_rounded,
                  'Prochaine échéance',
                  next.isEmpty
                      ? 'Aucune'
                      : '${next.first.type.label} — ${Fmt.long(next.first.nextDue!)}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          VaccinationCard(pet: pet, records: records),
          if (stats.weights.length >= 2) ...[
            const SizedBox(height: 12),
            LineChartCard(
              title: 'Évolution du poids (kg)',
              subtitle: '${stats.weights.length} pesées',
              color: AppColors.health,
              valueLabel: (v) => Units.number(v),
              points: [
                for (final w in stats.weights)
                  LinePoint(Fmt.monthShort(w.date), w.kg),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.pet),
      title: Text(label,
          style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
      subtitle: Text(value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
    );
  }
}
