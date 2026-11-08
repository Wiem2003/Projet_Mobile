import 'package:flutter/material.dart';

import '../../core/pets/pet_directory.dart';
import 'pet_avatar.dart';

/// En-tête dégradé des modules Alimentation et Activités : titre, actions,
/// sélecteur d'animal et contenu libre ([bottom]).
class ModuleHeader extends StatelessWidget {
  const ModuleHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.deepColor,
    required this.pets,
    required this.selectedPetId,
    required this.onPetSelected,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final String subtitle;
  final Color color;
  final Color deepColor;
  final List<PetSummary> pets;
  final int? selectedPetId;
  final ValueChanged<int?> onPetSelected;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [deepColor, color],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
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
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
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
                  accent: deepColor,
                  onTap: () => onPetSelected(null),
                ),
                for (final p in pets)
                  _PetChip(
                    label: p.name,
                    pet: p,
                    selected: selectedPetId == p.id,
                    accent: deepColor,
                    onTap: () => onPetSelected(p.id),
                  ),
              ],
            ),
          ),
          if (bottom != null) ...[
            const SizedBox(height: 12),
            Padding(padding: const EdgeInsets.only(right: 12), child: bottom),
          ],
        ],
      ),
    );
  }
}

class _PetChip extends StatelessWidget {
  const _PetChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.pet,
  });

  final String label;
  final bool selected;
  final Color accent;
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
                    color: selected ? accent : Colors.white,
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

/// Puces blanches sur l'en-tête (mois, période...).
class HeaderChoice<T> extends StatelessWidget {
  const HeaderChoice({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    required this.accent,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: Material(
                color: v == selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onChanged(v),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      labelOf(v),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: v == selected ? accent : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
