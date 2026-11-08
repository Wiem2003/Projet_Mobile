import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/reminders_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/reminder.dart';
import '../../models/reminder_compliance.dart';
import '../../models/reminders_model.dart';
import '../reminder_style.dart';
import '../widgets/bar_chart_card.dart';
import '../widgets/empty_state.dart';

/// Statistiques d'observance : part des soins faits à temps par animal,
/// par type et par mois, séries en cours et retard moyen.
class ReminderComplianceScreen extends StatelessWidget {
  const ReminderComplianceScreen({super.key});

  static const _color = AppColors.reminder;

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const ReminderComplianceScreen()));

  /// « vermifuges », « vaccins »... pour les séries.
  static String plural(ReminderType t) => switch (t) {
        ReminderType.vaccination => 'vaccins',
        ReminderType.deworming => 'vermifuges',
        ReminderType.vetAppointment => 'rendez-vous',
        ReminderType.treatment => 'traitements',
        ReminderType.checkup => 'contrôles',
        ReminderType.purchase => 'achats',
        ReminderType.other => 'rappels',
      };

  static String percent(double? rate) =>
      rate == null ? '—' : '${(rate * 100).round()} %';

  static String days(double? v) {
    if (v == null) return '—';
    final s = v.toStringAsFixed(1).replaceAll('.', ',');
    return '${s.endsWith(',0') ? s.substring(0, s.length - 2) : s} j';
  }

  /// Vert au-dessus de 80 %, orange au-dessus de 50 %, rouge en dessous.
  static Color rateColor(double? rate) => rate == null
      ? Colors.grey
      : rate >= 0.8
          ? AppColors.success
          : rate >= 0.5
              ? AppColors.warning
              : AppColors.danger;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<RemindersModel>();
    final controller = context.read<RemindersController>();
    final report = model.compliance;
    String petName(int? id) {
      if (id == null) return 'Rappels généraux';
      for (final p in model.pets) {
        if (p.id == id) return p.name;
      }
      return 'Animal #$id';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Observance'),
        backgroundColor: _color,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (model.pets.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Tous'),
                  selected: model.petFilter == null,
                  onSelected: (_) => controller.setPetFilter(null),
                ),
                for (final p in model.pets)
                  ChoiceChip(
                    label: Text(p.name),
                    selected: model.petFilter == p.id,
                    onSelected: (_) => controller.setPetFilter(p.id),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          if (report.overall.isEmpty)
            EmptyState(
              icon: Icons.insights_rounded,
              color: _color,
              title: 'Aucune échéance passée',
              message: 'Les statistiques apparaissent quand des soins arrivent à '
                  'échéance : faits à temps, en retard ou oubliés.',
              action: OutlinedButton.icon(
                icon: const Icon(Icons.history_rounded),
                label: const Text('Charger un historique d\'exemple'),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final n = await controller.seedHistory();
                  messenger.showSnackBar(SnackBar(
                      content: Text(n == 0
                          ? 'L\'historique est déjà chargé'
                          : '$n soins passés ajoutés')));
                },
              ),
            )
          else ...[
            _OverallCard(stats: report.overall),
            if (report.streaks.isNotEmpty) ...[
              const _Title('Séries en cours'),
              for (final s in report.streaks.take(4))
                Card(
                  child: ListTile(
                    leading: const Text('🔥', style: TextStyle(fontSize: 24)),
                    title: Text(
                      '${s.count} ${plural(s.type)} d\'affilée faits à l\'heure',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(petName(s.petId)),
                  ),
                ),
            ],
            const _Title('Par mois'),
            BarChartCard(
              title: 'Soins faits à temps',
              subtitle: '${ComplianceReport.months} derniers mois',
              color: _color,
              valueLabel: (v) => '${v.round()} %',
              bars: [
                for (final (i, (month, stats)) in report.byMonth.indexed)
                  BarDatum(
                    Fmt.monthShort(month),
                    (stats.rate ?? 0) * 100,
                    highlight: i == report.byMonth.length - 1,
                  ),
              ],
            ),
            const _Title('Par animal'),
            Card(
              child: Column(
                children: [
                  for (final MapEntry(key: pet, value: stats)
                      in report.byPet.entries)
                    _RateRow(
                      leading: const Icon(Icons.pets_rounded),
                      label: petName(pet),
                      stats: stats,
                    ),
                ],
              ),
            ),
            const _Title('Par type de soin'),
            Card(
              child: Column(
                children: [
                  for (final type in ReminderType.values)
                    if (report.byType[type] case final stats?)
                      _RateRow(
                        leading: Icon(type.icon, color: type.color),
                        label: type.label,
                        stats: stats,
                        showDelay: true,
                        flag: type == report.mostForgotten
                            ? 'Le plus souvent en retard'
                            : null,
                      ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Un soin est « à temps » s\'il est fait le jour prévu ou avant. '
              'Un rappel reporté est jugé sur sa nouvelle date. Le retard moyen '
              'compte 0 jour pour un soin fait à temps.',
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
      );
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.stats});

  final ComplianceStats stats;

  @override
  Widget build(BuildContext context) {
    final rate = stats.rate;
    final color = ReminderComplianceScreen.rateColor(rate);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              height: 92,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: rate ?? 0,
                    strokeWidth: 9,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15),
                  ),
                  Center(
                    child: Text(ReminderComplianceScreen.percent(rate),
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800, color: color)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('des soins faits à temps',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('${stats.onTime} à temps · ${stats.late} en retard · '
                      '${stats.missed} oublié${stats.missed > 1 ? 's' : ''}'),
                  Text('Retard moyen : '
                      '${ReminderComplianceScreen.days(stats.averageDelayDays)}'),
                  if (stats.postponed > 0)
                    Text('${stats.postponed} échéance(s) reportée(s)',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RateRow extends StatelessWidget {
  const _RateRow({
    required this.leading,
    required this.label,
    required this.stats,
    this.showDelay = false,
    this.flag,
  });

  final Widget leading;
  final String label;
  final ComplianceStats stats;
  final bool showDelay;
  final String? flag;

  @override
  Widget build(BuildContext context) {
    final rate = stats.rate;
    final color = ReminderComplianceScreen.rateColor(rate);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: rate ?? 0,
                    minHeight: 6,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    '${stats.onTime}/${stats.evaluated} à temps',
                    if (showDelay)
                      'retard moyen ${ReminderComplianceScreen.days(stats.averageDelayDays)}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12),
                ),
                if (flag != null)
                  Text(flag!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(ReminderComplianceScreen.percent(rate),
              style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}
