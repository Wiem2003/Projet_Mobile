import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/dashboard/pet_costs.dart';
import '../dashboard_data.dart';
import '../formatters.dart';
import '../widgets/pet_photo.dart';

/// Coût de revient par animal : mois en cours, coût par jour, moyenne des
/// 3 derniers mois, projection sur 12 mois et comparaison.
class PetCostScreen extends StatelessWidget {
  const PetCostScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const PetCostScreen()));

  @override
  Widget build(BuildContext context) {
    final costs = DashboardData.watch(context).costs;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coût par animal'),
        backgroundColor: AppColors.feeding,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            color: AppColors.feeding.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ce mois : ${Units.money(costs.totalThisMonth)}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  Text('Projection sur 12 mois : ${Units.money(costs.totalProjection)}'),
                  if (costs.comparison case final cmp?)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(cmp.sentence, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          ),
          for (final c in costs.pets) _PetCostCard(cost: c),
          const SizedBox(height: 8),
          Text(
            'Coût = santé (dossiers de santé) + alimentation (repas). La projection sur 12 mois '
            'ajoute l\'alimentation (moyenne des 3 derniers mois complets × 12) et les soins déjà '
            'prévus dans les rappels, au coût du dernier soin du même type.',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
    );
  }
}

class _PetCostCard extends StatelessWidget {
  const _PetCostCard({required this.cost});

  final PetCost cost;

  @override
  Widget build(BuildContext context) {
    final c = cost;
    final share = c.thisMonth == 0 ? 0.0 : c.feedingThisMonth / c.thisMonth;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PetPhoto.of(c.pet, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(c.pet.name,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(Units.money(c.thisMonth),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('${Units.money(c.perDay)} / jour', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Part de l'alimentation (vert) et de la santé (rouge).
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 8,
                color: AppColors.feeding,
                backgroundColor:
                    c.thisMonth == 0 ? Colors.grey.withValues(alpha: 0.2) : AppColors.health,
              ),
            ),
            const SizedBox(height: 6),
            Text('Alimentation ${Units.money(c.feedingThisMonth)} · santé '
                '${Units.money(c.healthThisMonth)}'),
            Text('Moyenne des 3 derniers mois : ${Units.money(c.monthlyAverage)} / mois'),
            Text('Projection sur 12 mois : ${Units.money(c.annualProjection)}'
                '${c.plannedCare > 0 ? ' (dont ${Units.money(c.plannedCare)} de soins prévus)' : ''}'),
          ],
        ),
      ),
    );
  }
}
