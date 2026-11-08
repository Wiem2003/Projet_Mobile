import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/health_booklet_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/health_record.dart';
import '../../models/pet.dart';
import '../../models/vaccination_booklet.dart';
import '../formatters.dart';
import '../health_booklet_actions.dart';

Color vaccineStatusColor(VaccineStatus? s) => switch (s) {
      VaccineStatus.upToDate => AppColors.success,
      VaccineStatus.expiringSoon => AppColors.warning,
      VaccineStatus.expired => AppColors.danger,
      null => Colors.grey,
    };

/// Statut d'un vaccin ou du carnet.
class VaccineChip extends StatelessWidget {
  const VaccineChip({super.key, required this.label, required this.status});

  final String label;
  final VaccineStatus? status;

  @override
  Widget build(BuildContext context) {
    final color = vaccineStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: status == VaccineStatus.expiringSoon ? const Color(0xFFB45309) : color,
              fontSize: 12,
              fontWeight: FontWeight.w800)),
    );
  }
}

/// Carnet de vaccination d'un animal (fiche détail) : statut de chaque
/// vaccin, vérification avant un voyage, carnet de santé en PDF.
class VaccinationCard extends StatefulWidget {
  const VaccinationCard({super.key, required this.pet, required this.records});

  final Pet pet;
  final List<HealthRecord> records;

  @override
  State<VaccinationCard> createState() => _VaccinationCardState();
}

class _VaccinationCardState extends State<VaccinationCard> {
  bool _sharing = false;

  HealthBookletController get _controller => context.read<HealthBookletController>();

  Future<void> _checkTravel() async {
    final now = _controller.now;
    final today = DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      helpText: 'Date du départ',
      initialDate: today.add(const Duration(days: 7)),
      firstDate: today,
      lastDate: DateTime(today.year + 3),
    );
    if (date == null || !mounted) return;
    final check = _controller.checkTravel(widget.pet, widget.records, date);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(check.ok ? Icons.flight_takeoff_rounded : Icons.block_rounded,
            color: check.ok ? AppColors.success : AppColors.danger),
        title: Text(check.ok ? 'Voyage possible' : 'Voyage impossible'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(check.message),
            if (check.warnings.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('À vérifier :', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final w in check.warnings) Text('• $w'),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        ],
      ),
    );
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      await HealthBookletActions.share(context, widget.pet, widget.records);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booklet = _controller.booklet(widget.pet, widget.records);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Statut sous le titre : lisible même sur un petit écran.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.vaccines_rounded, color: AppColors.health),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Carnet de vaccination',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 4),
                      VaccineChip(label: booklet.summary, status: booklet.worst),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (booklet.isEmpty)
              Text('Ajoutez une vaccination dans le module Santé (ex. « CHPPi + rage »).',
                  style: TextStyle(color: muted))
            else
              for (final e in booklet.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              'Injection ${Fmt.short(e.injectedOn)} · valable jusqu\'au '
                              '${Fmt.medium(e.expiresOn)}',
                              style: TextStyle(fontSize: 12.5, color: muted),
                            ),
                          ],
                        ),
                      ),
                      VaccineChip(
                        label: switch (e.status) {
                          VaccineStatus.expiringSoon => 'J-${e.daysLeft}',
                          _ => e.status.label,
                        },
                        status: e.status,
                      ),
                    ],
                  ),
                ),
            if (booklet.missingCore.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    'Conseillés, jamais enregistrés : '
                    '${booklet.missingCore.map((v) => v.label).join(', ')}',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.flight_takeoff_rounded, size: 18),
                  label: const Text('Vérifier un voyage'),
                  onPressed: _checkTravel,
                ),
                TextButton.icon(
                  icon: _sharing
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: Text(_controller.aiAvailable
                      ? 'Carnet de santé PDF (Gemini)'
                      : 'Carnet de santé PDF'),
                  onPressed: _sharing ? null : _share,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
