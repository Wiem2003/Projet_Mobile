import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/reminders_model.dart';
import '../../models/reminder_calculator.dart';
import '../reminder_style.dart';
import '../sheets/reminder_detail_sheet.dart';

/// Carte « Prochains rappels » destinée au Dashboard.
///
/// ```dart
/// UpcomingRemindersCard(onSeeAll: () => goToTab(4))
/// ```
class UpcomingRemindersCard extends StatelessWidget {
  const UpcomingRemindersCard({super.key, this.limit = 4, this.onSeeAll});

  final int limit;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<RemindersModel>();
    final now = model.now;
    final items = [...model.overdue, ...model.upcoming].take(limit).toList();
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.reminder, width: 1.4),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_rounded,
                    color: AppColors.reminder, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Prochains rappels',
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.reminder,
                          fontWeight: FontWeight.w800)),
                ),
                if (onSeeAll != null)
                  TextButton(onPressed: onSeeAll, child: const Text('Tout voir')),
              ],
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Aucun rappel à venir',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              )
            else
              for (final r in items)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => showReminderDetailSheet(context, r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                              color: r.type.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                  text: r.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              if (model.petOf(r) case final pet?)
                                TextSpan(
                                    text: ' · ${pet.name}',
                                    style: TextStyle(
                                        color: theme
                                            .colorScheme.onSurfaceVariant)),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            ReminderCalculator.countdownLabel(r.dueDate, now),
                            style: TextStyle(
                              color: urgencyColor(r, now),
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
