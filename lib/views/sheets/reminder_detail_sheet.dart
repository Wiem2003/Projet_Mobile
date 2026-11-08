import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/reminders_model.dart';
import '../../models/reminder_rules.dart';
import '../../models/reminder_calculator.dart';
import '../../models/reminder.dart';
import '../reminder_actions.dart';
import '../reminder_style.dart';
import '../widgets/pet_avatar.dart';

Future<void> showReminderDetailSheet(BuildContext context, Reminder r) {
  final model = context.read<RemindersModel>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider.value(
      value: model,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (context, scroll) =>
            _DetailContent(reminderId: r.id!, fallback: r, scroll: scroll),
      ),
    ),
  );
}

class _DetailContent extends StatelessWidget {
  const _DetailContent({
    required this.reminderId,
    required this.fallback,
    required this.scroll,
  });

  final int reminderId;
  final Reminder fallback;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<RemindersModel>();
    // Version à jour après une action (report, modification...).
    final r = model.byId(reminderId) ?? fallback;
    final now = model.now;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pet = model.petOf(r);
    final color = r.type.color;
    final urgency = urgencyColor(r, now);
    final alerts = ReminderCalculator.alertSchedule(r);

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(r.type.icon, color: color, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.type.label.toUpperCase(),
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(r.title,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        // Compte à rebours mis en avant.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              urgency.withValues(alpha: 0.16),
              urgency.withValues(alpha: 0.04),
            ]),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(
                r.isDone
                    ? Icons.check_circle_rounded
                    : r.isOverdue(now)
                        ? Icons.warning_amber_rounded
                        : Icons.hourglass_bottom_rounded,
                color: urgency,
                size: 32,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.isDone
                          ? 'Terminé le ${Fmt.medium(r.completedAt ?? r.dueDate)}'
                          : _headline(r, now),
                      style: TextStyle(
                          color: urgency,
                          fontWeight: FontWeight.w800,
                          fontSize: 17),
                    ),
                    Text('${Fmt.long(r.dueDate)} à ${Fmt.time(r.dueDate)}',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _InfoRow(
          icon: Icons.pets_rounded,
          label: 'Animal',
          child: pet == null
              ? const Text('Tous les animaux')
              : Row(children: [
                  PetAvatar(pet: pet, size: 22),
                  const SizedBox(width: 8),
                  Text(pet.name),
                ]),
        ),
        _InfoRow(
          icon: r.repeat.icon,
          label: 'Répétition',
          child: Text(r.repeat.description),
        ),
        _InfoRow(
          icon: Icons.flag_outlined,
          label: 'Statut',
          child: Text(r.isOverdue(now)
              ? 'En retard'
              : r.postponeCount > 0 && !r.isDone
                  ? '${r.status.label} (${r.postponeCount}×)'
                  : r.status.label),
        ),
        if (r.isOverdue(now))
          _InfoRow(
            icon: Icons.priority_high_rounded,
            label: 'Urgence',
            child: Text(
              '${ReminderRules.escalation(r, now).label} · score '
              '${ReminderRules.urgencyScore(r, now)} (gravité '
              '${ReminderRules.severity(r.type)} × '
              '${ReminderRules.daysLate(r, now)} j de retard)',
            ),
          ),
        if (!r.isDone && ReminderRules.postponePolicy(r.type).isLimited)
          _InfoRow(
            icon: Icons.snooze_rounded,
            label: 'Reports',
            child: Text([
              if (ReminderRules.postponePolicy(r.type).maxCount case final max?)
                '${r.postponeCount} / $max utilisés',
              if (ReminderRules.postponePolicy(r.type).maxDays case final days?)
                '$days j maximum par report',
            ].join(' · ')),
          ),
        _InfoRow(
          icon: r.isAutomatic ? Icons.auto_awesome_rounded : Icons.edit_note,
          label: 'Origine',
          child: Text(r.isAutomatic
              ? '${r.source.label} #${r.sourceId}'
              : r.source.label),
        ),
        if (r.notes != null)
          _InfoRow(
            icon: Icons.notes_rounded,
            label: 'Notes',
            child: Text(r.notes!),
          ),
        const SizedBox(height: 12),
        Text('Notifications',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (alerts.isEmpty)
          Text('Aucune notification pour ce rappel.',
              style: TextStyle(color: scheme.onSurfaceVariant))
        else
          for (final (i, a) in alerts.indexed)
            _TimelineTile(
              label: a.offset.label,
              date: a.at,
              passed: !a.at.isAfter(now) || r.isDone,
              isLast: i == alerts.length - 1,
            ),
        const SizedBox(height: 20),
        if (!r.isDone) ...[
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Fait'),
                  onPressed: () async {
                    Navigator.pop(context);
                    await ReminderActions.markDone(context, r);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50)),
                  icon: const Icon(Icons.snooze_rounded),
                  label: const Text('Reporter'),
                  onPressed: () => ReminderActions.postpone(context, r),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ] else ...[
          FilledButton.tonalIcon(
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.undo_rounded),
            label: const Text('Rouvrir le rappel'),
            onPressed: () => ReminderActions.reopen(context, r),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Modifier'),
                onPressed: () => ReminderActions.openForm(context, reminder: r),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Supprimer'),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  if (await ReminderActions.delete(context, r)) nav.pop();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _headline(Reminder r, DateTime now) {
    final s = ReminderCalculator.relativeSentence(r.dueDate, now);
    return s[0].toUpperCase() + s.substring(1);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.child});

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: Text(label,
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontWeight: FontWeight.w600),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.label,
    required this.date,
    required this.passed,
    required this.isLast,
  });

  final String label;
  final DateTime date;
  final bool passed;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = passed ? scheme.outline : AppColors.reminder;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Icon(
                  passed
                      ? Icons.check_circle_outline_rounded
                      : Icons.notifications_active_rounded,
                  size: 18,
                  color: color,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: scheme.outlineVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: passed ? scheme.outline : null,
                          decoration:
                              passed ? TextDecoration.lineThrough : null,
                        )),
                  ),
                  Text(Fmt.dateTime(date),
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
