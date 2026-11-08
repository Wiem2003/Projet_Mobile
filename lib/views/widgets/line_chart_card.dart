import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Un point de la courbe.
class LinePoint {
  const LinePoint(this.label, this.value);

  final String label;
  final double value;
}

/// Courbe simple (évolution du poids), sans dépendance externe.
class LineChartCard extends StatelessWidget {
  const LineChartCard({
    super.key,
    required this.title,
    required this.points,
    required this.color,
    required this.valueLabel,
    this.subtitle,
    this.height = 150,
  });

  final String title;
  final String? subtitle;
  final List<LinePoint> points;
  final Color color;
  final String Function(double value) valueLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Au plus 6 étiquettes sous l'axe pour rester lisible.
    final step = math.max(1, (points.length / 6).ceil());
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
              label: '$title : ${points.map((p) => '${p.label} ${valueLabel(p.value)}').join(', ')}',
              child: SizedBox(
                height: height,
                width: double.infinity,
                child: CustomPaint(
                  painter: _LinePainter(
                    points: points,
                    color: color,
                    grid: theme.colorScheme.outlineVariant,
                    textColor: theme.colorScheme.onSurfaceVariant,
                    valueLabel: valueLabel,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final (i, p) in points.indexed)
                  Expanded(
                    child: Text(
                      i % step == 0 || i == points.length - 1 ? p.label : '',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                          fontSize: 10.5,
                          color: theme.colorScheme.onSurfaceVariant),
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

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.points,
    required this.color,
    required this.grid,
    required this.textColor,
    required this.valueLabel,
  });

  final List<LinePoint> points;
  final Color color;
  final Color grid;
  final Color textColor;
  final String Function(double) valueLabel;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    var lo = points.map((p) => p.value).reduce(math.min);
    var hi = points.map((p) => p.value).reduce(math.max);
    final margin = math.max((hi - lo) * 0.15, hi.abs() * 0.02 + 0.01);
    lo -= margin;
    hi += margin;
    const top = 18.0, bottom = 6.0;
    final h = size.height - top - bottom;
    final slot = size.width / points.length;
    Offset at(int i) => Offset(
        slot * (i + 0.5), top + h * (1 - (points[i].value - lo) / (hi - lo)));

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var k = 0; k <= 2; k++) {
      final y = top + h * k / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final area = Path.from(line)
      ..lineTo(at(points.length - 1).dx, size.height)
      ..lineTo(at(0).dx, size.height)
      ..close();
    canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size));
    canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);

    for (var i = 0; i < points.length; i++) {
      final o = at(i);
      canvas.drawCircle(o, 5, Paint()..color = Colors.white);
      canvas.drawCircle(o, 3.5, Paint()..color = color);
      // Valeur au-dessus des points extrêmes et du dernier.
      if (i == 0 || i == points.length - 1 ||
          points[i].value == points.map((p) => p.value).reduce(math.max)) {
        final tp = TextPainter(
          text: TextSpan(
              text: valueLabel(points[i].value),
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: i == points.length - 1 ? color : textColor)),
          textDirection: TextDirection.ltr,
        )..layout();
        final x = (o.dx - tp.width / 2).clamp(0.0, size.width - tp.width);
        tp.paint(canvas, Offset(x, o.dy - tp.height - 6));
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.points != points || old.color != color || old.grid != grid;
}
