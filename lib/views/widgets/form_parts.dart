import 'package:flutter/material.dart';

/// Éléments communs des formulaires Alimentation et Activités.
class FormSectionLabel extends StatelessWidget {
  const FormSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class FormBanner extends StatelessWidget {
  const FormBanner({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class PickerTile extends StatelessWidget {
  const PickerTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    required this.color,
    this.error,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Color color;

  /// Contrôle de saisie : message affiché sous le sélecteur.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tile = _tile(context);
    if (error == null) return tile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tile,
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 0, 0),
          child: Text(error!,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).inputDecorationTheme.fillColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: error == null ? scheme.outlineVariant : scheme.error),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 11.5, color: scheme.onSurfaceVariant)),
                    Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grille de choix illustrés (type de nourriture, type d'activité).
class ChoiceGrid<T> extends StatelessWidget {
  const ChoiceGrid({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.iconOf,
    required this.colorOf,
    required this.onSelected,
    this.columns = 5,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final IconData Function(T) iconOf;
  final Color Function(T) colorOf;
  final ValueChanged<T> onSelected;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.9,
      children: [
        for (final v in values)
          Builder(builder: (context) {
            final on = v == selected;
            final color = colorOf(v);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: on
                    ? color.withValues(alpha: 0.14)
                    : Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: on ? color : scheme.outlineVariant,
                  width: on ? 1.8 : 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onSelected(v),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(iconOf(v), color: color, size: 26),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          labelOf(v),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                            color: on ? color : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

/// Puces de valeurs rapides (« 100 g », « 30 min »...).
class QuickValues extends StatelessWidget {
  const QuickValues({
    super.key,
    required this.options,
    required this.onPick,
  });

  final List<(String, String)> options;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final (label, value) in options)
            ActionChip(
              label: Text(label),
              visualDensity: VisualDensity.compact,
              onPressed: () => onPick(value),
            ),
        ],
      ),
    );
  }
}

/// Bouton d'enregistrement fixé en bas du formulaire.
class SaveBar extends StatelessWidget {
  const SaveBar({
    super.key,
    required this.color,
    required this.saving,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final Color color;
  final bool saving;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            minimumSize: const Size.fromHeight(54),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: saving ? null : onPressed,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Icon(icon),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

/// Encadré « calcul automatique » (prix au kilo, calories...).
class ComputedPanel extends StatelessWidget {
  const ComputedPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant)),
                Text(value,
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, color: color)),
                if (detail != null)
                  Text(detail!,
                      style: TextStyle(
                          fontSize: 11.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
