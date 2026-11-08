import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/reminder_calculator.dart';
import '../../models/reminder.dart';
import '../reminder_style.dart';

/// Calendrier horizontal des 21 prochains jours, avec une pastille par
/// échéance (couleur du type). Toucher un jour filtre la liste.
class DayStrip extends StatelessWidget {
  const DayStrip({
    super.key,
    required this.today,
    required this.selected,
    required this.typesOnDay,
    required this.onSelected,
    this.days = 21,
  });

  final DateTime today;
  final DateTime? selected;
  final List<ReminderType> Function(DateTime day) typesOnDay;
  final ValueChanged<DateTime?> onSelected;
  final int days;

  @override
  Widget build(BuildContext context) {
    final start = DateTime(today.year, today.month, today.day);
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: days,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final day = DateTime(start.year, start.month, start.day + i);
          final isSelected = selected != null &&
              ReminderCalculator.daysUntil(day, selected!) == 0;
          return _DayCell(
            day: day,
            isToday: i == 0,
            selected: isSelected,
            types: typesOnDay(day),
            onTap: () => onSelected(isSelected ? null : day),
          );
        },
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.selected,
    required this.types,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool selected;
  final List<ReminderType> types;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? Colors.white : scheme.onSurface;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 54,
      decoration: BoxDecoration(
        color: selected ? AppColors.reminder : Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isToday && !selected
              ? AppColors.reminder
              : scheme.outlineVariant.withValues(alpha: 0.6),
          width: isToday && !selected ? 1.6 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppColors.reminder.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isToday ? 'Auj.' : Fmt.weekday(day),
              style: TextStyle(
                fontSize: 11.5,
                color: selected
                    ? Colors.white.withValues(alpha: 0.85)
                    : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final t in types.take(3))
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : t.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
