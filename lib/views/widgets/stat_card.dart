import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../formatters.dart';

/// Indicateur calculé (quantité, dépense, distance...).
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.caption,
    this.trend,
    this.upIsGood = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? caption;

  /// Variation relative affichée en badge (0.12 = +12 %).
  final double? trend;

  /// Une hausse est-elle une bonne nouvelle (activité) ou non (dépenses) ?
  /// `null` : ni l'un ni l'autre (poids), badge neutre.
  final bool? upIsGood;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const Spacer(),
                if (trend != null) TrendBadge(ratio: trend!, upIsGood: upIsGood),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            if (caption != null)
              Text(
                caption!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

/// Badge « ▲ +12 % » coloré selon que la hausse est souhaitable ou non.
class TrendBadge extends StatelessWidget {
  const TrendBadge({super.key, required this.ratio, this.upIsGood = true});

  final double ratio;

  /// `null` : badge neutre.
  final bool? upIsGood;

  @override
  Widget build(BuildContext context) {
    final flat = ratio.abs() < 0.005;
    final color = flat
        ? Theme.of(context).colorScheme.outline
        : upIsGood == null
            ? AppColors.primary
            : (ratio > 0) == upIsGood
            ? AppColors.success
            : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            flat
                ? Icons.trending_flat_rounded
                : ratio > 0
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            Units.percent(ratio),
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

/// Grille de 2 colonnes, cartes de même hauteur par ligne.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: 10),
                Expanded(
                  child: i + 1 < children.length
                      ? children[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
