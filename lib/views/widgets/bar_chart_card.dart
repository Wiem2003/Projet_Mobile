import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Une barre du graphique.
class BarDatum {
  const BarDatum(this.label, this.value, {this.highlight = false});

  final String label;
  final double value;

  /// Période en cours, affichée en couleur pleine.
  final bool highlight;
}

/// Graphique en barres simple (évolution par semaine ou par mois), sans
/// dépendance externe.
class BarChartCard extends StatelessWidget {
  const BarChartCard({
    super.key,
    required this.title,
    required this.bars,
    required this.color,
    required this.valueLabel,
    this.subtitle,
    this.height = 150,
  });

  final String title;
  final String? subtitle;
  final List<BarDatum> bars;
  final Color color;
  final String Function(double value) valueLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = bars.fold(0.0, (m, b) => math.max(m, b.value));
    const labelSpace = 22.0;
    final barMax = height - labelSpace;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                ),
                if (subtitle != null)
                  Text(subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 14),
            Semantics(
              label: '$title : ${bars.map((b) => '${b.label} ${valueLabel(b.value)}').join(', ')}',
              child: ExcludeSemantics(
                child: SizedBox(
                  height: height,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final b in bars)
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  valueLabel(b.value),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: b.highlight
                                        ? color
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeOutCubic,
                                height: max == 0
                                    ? 0
                                    : math.max(b.value > 0 ? 3 : 0,
                                        b.value / max * (barMax - 4)),
                                margin: const EdgeInsets.symmetric(horizontal: 6),
                                decoration: BoxDecoration(
                                  color: b.highlight
                                      ? color
                                      : color.withValues(alpha: 0.4),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(6)),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final b in bars)
                  Expanded(
                    child: Text(
                      b.label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            b.highlight ? FontWeight.w800 : FontWeight.w500,
                        color: b.highlight
                            ? color
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
