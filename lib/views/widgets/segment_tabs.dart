import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/reminders_model.dart';

/// Onglets « À venir / En retard / Terminés » avec compteurs.
class SegmentTabs extends StatelessWidget {
  const SegmentTabs({
    super.key,
    required this.current,
    required this.counts,
    required this.onChanged,
  });

  final ReminderTab current;
  final Map<ReminderTab, int> counts;
  final ValueChanged<ReminderTab> onChanged;

  static const _labels = {
    ReminderTab.upcoming: 'À venir',
    ReminderTab.overdue: 'En retard',
    ReminderTab.done: 'Terminés',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final tab in ReminderTab.values)
            Expanded(
              child: _Segment(
                label: _labels[tab]!,
                count: counts[tab] ?? 0,
                selected: tab == current,
                danger: tab == ReminderTab.overdue && (counts[tab] ?? 0) > 0,
                onTap: () => onChanged(tab),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.count,
    required this.selected,
    required this.danger,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badgeColor = danger ? AppColors.danger : AppColors.reminder;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).cardTheme.color : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: selected || danger ? 1 : 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: selected || danger ? Colors.white : badgeColor,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
