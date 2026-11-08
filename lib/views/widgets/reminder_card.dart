import 'package:flutter/material.dart';

import '../../core/pets/pet_directory.dart';
import '../../core/theme/app_colors.dart';
import '../../models/reminder_calculator.dart';
import '../../models/reminder.dart';
import '../../models/reminder_rules.dart';
import '../reminder_style.dart';

/// Carte d'un rappel. Glisser à droite = Fait, à gauche = Reporter
/// (ou Supprimer pour un rappel terminé).
class ReminderCard extends StatelessWidget {
  const ReminderCard({
    super.key,
    required this.reminder,
    required this.now,
    this.pet,
    this.onTap,
    this.onDone,
    this.onPostpone,
    this.onDelete,
  });

  final Reminder reminder;
  final DateTime now;
  final PetSummary? pet;
  final VoidCallback? onTap;
  final VoidCallback? onDone;
  final VoidCallback? onPostpone;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final card = _CardBody(reminder: r, now: now, pet: pet, onTap: onTap);

    return Dismissible(
      key: ValueKey('reminder-${r.id}-${r.status.name}'),
      direction: r.isDone
          ? DismissDirection.endToStart
          : DismissDirection.horizontal,
      background: const _SwipeBackground(
        color: AppColors.success,
        icon: Icons.check_rounded,
        label: 'Fait',
        alignStart: true,
      ),
      secondaryBackground: r.isDone
          ? const _SwipeBackground(
              color: AppColors.danger,
              icon: Icons.delete_outline_rounded,
              label: 'Supprimer',
              alignStart: false,
            )
          : const _SwipeBackground(
              color: AppColors.warning,
              icon: Icons.snooze_rounded,
              label: 'Reporter',
              alignStart: false,
            ),
      confirmDismiss: (direction) async {
        // La liste est rechargée par le contrôleur : on ne laisse jamais
        // Dismissible retirer la carte lui-même.
        if (direction == DismissDirection.startToEnd) {
          onDone?.call();
        } else if (r.isDone) {
          onDelete?.call();
        } else {
          onPostpone?.call();
        }
        return false;
      },
      child: card,
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody(
      {required this.reminder, required this.now, this.pet, this.onTap});

  final Reminder reminder;
  final DateTime now;
  final PetSummary? pet;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final typeColor = r.type.color;
    final urgency = urgencyColor(r, now);
    final muted = r.isDone;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: r.isOverdue(now)
              ? AppColors.danger.withValues(alpha: 0.45)
              : scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: muted ? scheme.outlineVariant : typeColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: (muted ? scheme.outline : typeColor)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          muted ? Icons.check_rounded : r.type.icon,
                          color: muted ? AppColors.success : typeColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              r.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                decoration:
                                    muted ? TextDecoration.lineThrough : null,
                                color: muted ? scheme.outline : null,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _MetaLine(reminder: r, pet: pet, now: now),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _CountdownPill(
                        label: r.isDone
                            ? 'Fait'
                            : ReminderCalculator.countdownLabel(r.dueDate, now),
                        color: urgency,
                      ),
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

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.reminder, required this.now, this.pet});

  final Reminder reminder;
  final DateTime now;
  final PetSummary? pet;

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final style = TextStyle(fontSize: 12.5, color: muted);
    final date = r.isDone && r.completedAt != null
        ? 'Fait le ${Fmt.short(r.completedAt!)}'
        : Fmt.dateTime(r.dueDate);

    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (pet != null)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.pets_rounded, size: 13, color: muted),
            const SizedBox(width: 3),
            Text(pet!.name,
                style: style.copyWith(fontWeight: FontWeight.w600)),
          ]),
        Text(date, style: style),
        if (r.repeat != ReminderRepeat.none)
          Tooltip(
            message: r.repeat.description,
            child: Icon(Icons.repeat_rounded, size: 14, color: muted),
          ),
        if (r.postponeCount > 0 && !r.isDone)
          Tooltip(
            message: 'Reporté ${r.postponeCount} fois',
            child: Icon(Icons.snooze_rounded, size: 14, color: muted),
          ),
        if (r.isAutomatic)
          Tooltip(
            message: 'Généré automatiquement : ${r.source.label}',
            child: const Icon(Icons.auto_awesome_rounded,
                size: 14, color: AppColors.reminder),
          ),
        EscalationBadge(reminder: r, now: now),
      ],
    );
  }
}

class _CountdownPill extends StatelessWidget {
  const _CountdownPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.icon,
    required this.label,
    required this.alignStart,
  });

  final Color color;
  final IconData icon;
  final String label;
  final bool alignStart;

  @override
  Widget build(BuildContext context) {
    final content = [
      Icon(icon, color: Colors.white),
      const SizedBox(width: 8),
      Text(label,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700)),
    ];
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      alignment: alignStart ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignStart ? content : content.reversed.toList(),
      ),
    );
  }
}

/// « Relance 1 », « Relance 2 » ou « Critique » pour un rappel en retard.
class EscalationBadge extends StatelessWidget {
  const EscalationBadge({super.key, required this.reminder, required this.now});

  final Reminder reminder;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final level = ReminderRules.escalation(reminder, now);
    if (level == EscalationLevel.none || level == EscalationLevel.overdue) {
      return const SizedBox.shrink();
    }
    final critical = level == EscalationLevel.critical;
    final color = critical ? AppColors.danger : AppColors.warning;
    return Tooltip(
      message: 'Urgence ${ReminderRules.urgencyScore(reminder, now)} '
          '(gravité ${ReminderRules.severity(reminder.type)} × '
          '${ReminderRules.daysLate(reminder, now)} j de retard)',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: critical ? color : color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(critical ? Icons.priority_high_rounded : Icons.campaign_rounded,
                size: 12, color: critical ? Colors.white : color),
            const SizedBox(width: 2),
            Text(level.label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: critical ? Colors.white : const Color(0xFFB45309))),
          ],
        ),
      ),
    );
  }
}
