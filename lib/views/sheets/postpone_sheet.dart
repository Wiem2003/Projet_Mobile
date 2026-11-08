import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/reminder_calculator.dart';
import '../../models/reminder.dart';
import '../../models/reminder_rules.dart';
import '../reminder_style.dart';

/// Choix de la nouvelle date d'un rappel reporté.
Future<DateTime?> showPostponeSheet(
  BuildContext context,
  Reminder reminder, {
  required DateTime now,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PostponeSheet(reminder: reminder, now: now),
  );
}

class _PostponeSheet extends StatelessWidget {
  const _PostponeSheet({required this.reminder, required this.now});

  final Reminder reminder;
  final DateTime now;

  static const _options = [
    (Duration(days: 1), 'Demain', Icons.wb_sunny_outlined),
    (Duration(days: 3), 'Dans 3 jours', Icons.looks_3_outlined),
    (Duration(days: 7), 'Dans 1 semaine', Icons.date_range_outlined),
    (Duration(days: 30), 'Dans 1 mois', Icons.calendar_month_outlined),
  ];

  /// Date la plus lointaine autorisée (soins médicaux), sinon `null`.
  DateTime? get _latest => ReminderRules.latestPostponeDate(reminder, now);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final policy = ReminderRules.postponePolicy(reminder.type);
    final latest = _latest;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Reporter le rappel',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '« ${reminder.title} » — prévu ${Fmt.dateTime(reminder.dueDate)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (policy.isLimited) ...[
              const SizedBox(height: 12),
              _LimitInfo(reminder: reminder, policy: policy),
            ],
            const SizedBox(height: 16),
            for (final (delta, label, icon) in _options)
              Builder(
                builder: (context) {
                  final date = ReminderCalculator.postponeBy(
                    reminder.dueDate,
                    now,
                    delta,
                  );
                  return _OptionTile(
                    icon: icon,
                    label: label,
                    date: date,
                    allowed: latest == null || !date.isAfter(latest),
                  );
                },
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_calendar_outlined),
              label: const Text('Choisir une date et une heure'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => _pickCustom(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustom(BuildContext context) async {
    final base = ReminderCalculator.postponeBy(
      reminder.dueDate,
      now,
      const Duration(days: 1),
    );
    final latest = _latest;
    final last = latest ?? DateTime(now.year + 5);
    final date = await showDatePicker(
      context: context,
      initialDate: base.isAfter(last) ? last : base,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: last,
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(reminder.dueDate),
    );
    if (time == null || !context.mounted) return;
    final chosen = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    // Dernier jour autorisé : l'heure ne peut pas dépasser la limite.
    Navigator.pop(
      context,
      latest != null && chosen.isAfter(latest) ? latest : chosen,
    );
  }
}

/// Reports déjà faits et limites du type de soin.
class _LimitInfo extends StatelessWidget {
  const _LimitInfo({required this.reminder, required this.policy});

  final Reminder reminder;
  final PostponePolicy policy;

  @override
  Widget build(BuildContext context) {
    final left = ReminderRules.remainingPostpones(reminder);
    final parts = [
      if (policy.maxCount != null)
        'Report ${reminder.postponeCount + 1} sur ${policy.maxCount} autorisés'
            '${left == 1 ? ' (dernier report possible)' : ''}',
      if (policy.maxDays != null) '${policy.maxDays} jours maximum par report',
    ];
    final last = left == 1;
    final color = last ? AppColors.warning : AppColors.reminder;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            last ? Icons.warning_amber_rounded : Icons.rule_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.date,
    this.allowed = true,
  });

  final IconData icon;
  final String label;
  final DateTime date;

  /// Au-delà de la durée maximale de report : affiché mais désactivé.
  final bool allowed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: allowed ? 1 : 0.45,
        child: Material(
          color: AppColors.reminder.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: allowed ? () => Navigator.pop(context, date) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, color: AppColors.reminder),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          allowed
                              ? Fmt.dateTime(date)
                              : 'Au-delà de la limite de report',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
