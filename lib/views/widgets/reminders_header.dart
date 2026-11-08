import 'package:flutter/material.dart';

import '../../core/pets/pet_directory.dart';
import '../../core/theme/app_colors.dart';
import '../../models/reminder_calculator.dart';
import 'pet_avatar.dart';

/// En-tête dégradé : titre, sélecteur d'animal et indicateurs clés.
class RemindersHeader extends StatelessWidget {
  const RemindersHeader({
    super.key,
    required this.stats,
    required this.pets,
    required this.selectedPetId,
    required this.onPetSelected,
    required this.onOverdueTap,
    required this.actions,
  });

  final ReminderStats stats;
  final List<PetSummary> pets;
  final int? selectedPetId;
  final ValueChanged<int?> onPetSelected;
  final VoidCallback onOverdueTap;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 8, 8, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.reminderDeep, AppColors.reminder, Color(0xFF9333EA)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rappels & alertes',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
              IconTheme(
                data: const IconThemeData(color: Colors.white),
                child: Row(mainAxisSize: MainAxisSize.min, children: actions),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                _PetChip(
                  label: 'Tous',
                  selected: selectedPetId == null,
                  onTap: () => onPetSelected(null),
                ),
                for (final p in pets)
                  _PetChip(
                    label: p.name,
                    pet: p,
                    selected: selectedPetId == p.id,
                    onTap: () => onPetSelected(p.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                _StatTile(
                  value: stats.overdue,
                  label: 'En retard',
                  icon: Icons.warning_amber_rounded,
                  highlight: stats.overdue > 0,
                  onTap: onOverdueTap,
                ),
                const SizedBox(width: 10),
                _StatTile(
                  value: stats.today,
                  label: 'Aujourd\'hui',
                  icon: Icons.today_rounded,
                ),
                const SizedBox(width: 10),
                _StatTile(
                  value: stats.next7Days,
                  label: '7 jours',
                  icon: Icons.date_range_rounded,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle() {
    if (stats.upcoming == 0 && stats.overdue == 0) {
      return 'Aucune échéance à venir 🎉';
    }
    final parts = <String>[
      '${stats.upcoming} à venir',
      if (stats.doneThisMonth > 0) '${stats.doneThisMonth} faits ce mois',
    ];
    return parts.join(' · ');
  }
}

class _PetChip extends StatelessWidget {
  const _PetChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.pet,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final PetSummary? pet;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.14),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(pet == null ? 14 : 5, 5, 14, 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pet != null) ...[
                  PetAvatar(pet: pet!, size: 24),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.reminderDeep : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
    this.highlight = false,
    this.onTap,
  });

  final int value;
  final String label;
  final IconData icon;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: highlight
            ? const Color(0xFFFFE4E6)
            : Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon,
                    size: 20,
                    color: highlight ? AppColors.danger : Colors.white),
                const SizedBox(height: 8),
                Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: highlight ? AppColors.danger : Colors.white,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: highlight
                        ? AppColors.danger
                        : Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
