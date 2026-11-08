import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/reminder.dart';
import '../reminder_style.dart';

class TypeFilterBar extends StatelessWidget {
  const TypeFilterBar({super.key, required this.selected, required this.onChanged});

  final ReminderType? selected;
  final ValueChanged<ReminderType?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _chip(context, null, 'Tous', Icons.apps_rounded, AppColors.reminder),
          for (final t in ReminderType.values)
            _chip(context, t, t.label, t.icon, t.color),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, ReminderType? type, String label,
      IconData icon, Color color) {
    final isSelected = selected == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        showCheckmark: false,
        avatar: Icon(icon, size: 18, color: isSelected ? Colors.white : color),
        label: Text(label),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: isSelected ? Colors.white : null,
        ),
        selectedColor: color,
        side: BorderSide(
          color: isSelected
              ? color
              : Theme.of(context).colorScheme.outlineVariant,
        ),
        onSelected: (_) => onChanged(isSelected ? null : type),
      ),
    );
  }
}
