import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/dashboard_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/dashboard/dashboard_model.dart';
import '../../models/dashboard/monthly_report.dart';
import '../../models/dashboard/pet_metrics.dart';
import '../../models/validation.dart';
import '../dashboard_data.dart';
import '../formatters.dart';
import '../widgets/pet_photo.dart';

/// Rapport mensuel : dépenses par module, soins, rappels, activité et
/// poids de chaque animal, à partager en texte ou en PDF.
class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const MonthlyReportScreen()));

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final dashboard = context.read<DashboardModel>();
    _month = MonthlyReport.previousMonth(dashboard.now);
    // Ouvrir le rapport du mois écoulé le marque comme vu (après la
    // première image : pas de notification pendant la construction).
    if (dashboard.reportReady) {
      final controller = context.read<DashboardController>();
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.markReportSeen());
    }
  }

  Future<void> _share(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Partage impossible : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = DashboardData.watch(context);
    final sharing = context.watch<DashboardModel>().sharing;
    final controller = context.read<DashboardController>();
    final report = data.report(_month);
    final current = PetMetrics.monthOf(data.now);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapport mensuel'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Mois précédent',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => setState(() => _month = PetMetrics.addMonths(_month, -1)),
              ),
              Expanded(
                child: Text(
                  PetMetrics.monthLabel(_month),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Mois suivant',
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: _month.isBefore(current)
                    ? () => setState(() => _month = PetMetrics.addMonths(_month, 1))
                    : null,
              ),
            ],
          ),
          if (_month == current)
            const Text('Mois en cours : rapport provisoire.',
                textAlign: TextAlign.center, style: TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Dépenses', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  _row('Santé', Units.money(report.healthCost)),
                  _row('Alimentation', Units.money(report.feedingCost)),
                  const Divider(),
                  _row('Total', Units.money(report.total), bold: true),
                  const SizedBox(height: 6),
                  Text('Activité : ${Units.minutes(report.minutes)} · ${Units.km(report.km)}',
                      style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
          if (report.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aucune donnée pour ce mois.', textAlign: TextAlign.center),
            ),
          for (final p in report.pets) _PetSection(summary: p),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Partager en texte'),
                  onPressed: sharing ? null : () => _share(() => controller.shareText(report)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  icon: sharing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('Partager en PDF'),
                  onPressed: sharing ? null : () => _share(() => controller.sharePdf(report)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('À envoyer au vétérinaire par e-mail, WhatsApp...',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  static Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ],
        ),
      );
}

class _PetSection extends StatelessWidget {
  const _PetSection({required this.summary});

  final PetMonthSummary summary;

  @override
  Widget build(BuildContext context) {
    final p = summary;
    final delta = p.weightDelta;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PetPhoto.of(p.pet, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(p.pet.name,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                Text(Units.money(p.total), style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Santé ${Units.money(p.healthCost)} · alimentation ${Units.money(p.feedingCost)}'
                ' (${Units.grams(p.feedingGrams)})'),
            Text('Rappels : ${p.onTime} à temps · ${p.late} en retard · ${p.missed} non fait(s)'),
            Text('Activité : ${p.activities} séance(s) · ${Units.minutes(p.minutes)} · '
                '${Units.km(p.km)} · ${Units.kcal(p.kcal)}'),
            Text(p.weightEnd == null
                ? 'Poids : aucune pesée ce mois-ci'
                : 'Poids : ${Units.kg(p.weightEnd!)}'
                    '${delta == null || delta == 0 ? '' : ' (${delta > 0 ? '+' : '−'}${formatDecimal(delta.abs())} kg)'}'),
            if (p.cares.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text('Soins', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final c in p.cares)
                Text('• ${PetMetrics.dayMonth(c.date)} ${c.type.label}'
                    '${c.medication == null ? '' : ' (${c.medication})'} · ${Units.money(c.cost)}',
                    style: const TextStyle(fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}
