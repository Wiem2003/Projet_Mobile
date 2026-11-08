import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/dashboard_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/dashboard/cross_alerts.dart';
import '../../models/dashboard/dashboard_model.dart';
import '../../models/dashboard/monthly_report.dart';
import '../../models/dashboard/smart_pet_index.dart';
import '../dashboard_data.dart';
import '../formatters.dart';
import '../screens/monthly_report_screen.dart';
import '../screens/pet_cost_screen.dart';
import 'pet_photo.dart';

/// Couleur d'un indice : vert ≥ 80, orange ≥ 50, rouge sinon.
Color indexColor(IndexLevel level) => switch (level) {
      IndexLevel.good => AppColors.success,
      IndexLevel.medium => AppColors.warning,
      IndexLevel.low => AppColors.danger,
    };

/// Pastille de l'indice, posée sur la bulle d'un animal.
class IndexBadge extends StatelessWidget {
  const IndexBadge({super.key, required this.index});

  final PetIndex index;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Indice Smart Pet de ${index.pet.name} : ${index.score} / 100',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: indexColor(index.level),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: Text('${index.score}',
              style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
        ),
      );
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.icon, this.title, this.color, {this.trailing});

  final IconData icon;
  final String title;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          ?trailing,
        ],
      );
}

// ------------------------------------------------------- Rapport mensuel

/// « Votre rapport d'octobre est prêt » : à partir du 1er du mois, jusqu'à
/// ce qu'il soit ouvert.
class ReportReadyCard extends StatelessWidget {
  const ReportReadyCard({super.key});

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardModel>();
    if (!dashboard.reportReady) return const SizedBox.shrink();
    final month = MonthlyReport.previousMonth(dashboard.now);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: AppColors.primary.withValues(alpha: 0.08),
        child: ListTile(
          leading: const Icon(Icons.summarize_rounded, color: AppColors.primary),
          title: Text('Votre rapport de ${DashboardController.monthLabel(month)} est prêt',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('Dépenses, soins, activité et poids · à partager au vétérinaire'),
          trailing: IconButton(
            tooltip: 'Masquer',
            icon: const Icon(Icons.close_rounded),
            onPressed: context.read<DashboardController>().markReportSeen,
          ),
          onTap: () => MonthlyReportScreen.open(context),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Alertes

class AlertsCard extends StatelessWidget {
  const AlertsCard({super.key});

  static IconData iconOf(AlertKind k) => switch (k) {
        AlertKind.weightGain => Icons.trending_up_rounded,
        AlertKind.weightLoss => Icons.trending_down_rounded,
        AlertKind.missingMeals => Icons.no_meals_rounded,
        AlertKind.unusualSpending => Icons.payments_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final alerts = DashboardData.watch(context).alerts(context.watch<DashboardModel>());
    if (alerts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardTitle(Icons.notification_important_rounded,
                  'Alertes (${alerts.length})', AppColors.warning),
              const SizedBox(height: 6),
              for (final a in alerts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(iconOf(a.kind), size: 20, color: const Color(0xFFB45309)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.kind.label,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            Text(a.message, style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Ne plus afficher pendant 30 jours',
                        icon: const Icon(Icons.notifications_off_outlined, size: 20),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await context.read<DashboardController>().dismiss(a);
                          messenger
                            ..hideCurrentSnackBar()
                            ..showSnackBar(SnackBar(
                                content: Text('« ${a.kind.label} » masquée pendant 30 jours')));
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Indice

class SmartPetIndexCard extends StatelessWidget {
  const SmartPetIndexCard({super.key});

  @override
  Widget build(BuildContext context) {
    final indexes = DashboardData.watch(context).indexes;
    if (indexes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardTitle(Icons.health_and_safety_rounded, 'Indice Smart Pet', AppColors.primary),
              const SizedBox(height: 4),
              for (final i in indexes)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => showIndexSheet(context, i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        PetPhoto.of(i.pet, size: 38),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(i.pet.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text(
                                i.deductions.isEmpty ? i.level.label : i.deductions.first,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Text('${i.score}',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: indexColor(i.level))),
                        const Text(' /100', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Détail de l'indice : points par critère et ce qui fait baisser la note.
Future<void> showIndexSheet(BuildContext context, PetIndex index) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  PetPhoto.of(index.pet, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Indice de ${index.pet.name}',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  Text('${index.score} / 100',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: indexColor(index.level))),
                ],
              ),
              const SizedBox(height: 4),
              Text(index.summary),
              const SizedBox(height: 12),
              for (final c in index.criteria)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('${c.label} · ${c.module}',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          Text('${c.points} / ${c.max}',
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: c.points / c.max,
                          minHeight: 6,
                          color: AppColors.primary,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                        ),
                      ),
                      if (c.reason != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(c.lost > 0 ? '−${c.lost} : ${c.reason}' : c.reason!,
                              style: const TextStyle(fontSize: 12.5)),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'Soins (30) : −15 par rappel critique, −5 par rappel en retard. Activité (25) : '
                'minutes des 7 derniers jours par rapport à l\'objectif de l\'espèce. Poids (25) : '
                'stable si la variation est de moins de 5 % en 2 mois. Repas (20) : jours avec un '
                'repas saisi sur les 7 derniers.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );

// ------------------------------------------------------------------ Coûts

class PetCostCard extends StatelessWidget {
  const PetCostCard({super.key});

  @override
  Widget build(BuildContext context) {
    final costs = DashboardData.watch(context).costs;
    if (costs.pets.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle(Icons.account_balance_wallet_rounded, 'Coût par animal', AppColors.feeding,
                trailing: TextButton(
                  onPressed: () => PetCostScreen.open(context),
                  child: const Text('Détails'),
                )),
            for (final c in costs.pets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${c.pet.name} : ${Units.money(c.thisMonth)} ce mois, '
                  '${Units.money(c.perDay)} par jour',
                ),
              ),
            if (costs.comparison case final cmp?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(cmp.sentence,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.summarize_outlined, size: 18),
                label: const Text('Rapports mensuels'),
                onPressed: () => MonthlyReportScreen.open(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
