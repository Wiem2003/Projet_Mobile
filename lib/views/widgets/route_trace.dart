import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/gps/geo_point.dart';

/// Tracé d'un trajet GPS, dessiné sans fond de carte (fonctionne hors
/// ligne). Départ en vert, position finale dans la couleur du module.
class RouteTrace extends StatelessWidget {
  const RouteTrace({
    super.key,
    required this.points,
    this.color = AppColors.activity,
    this.height = 220,
    this.emptyText = 'En attente du signal GPS…',
  });

  final List<GeoPoint> points;
  final Color color;
  final double height;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      clipBehavior: Clip.antiAlias,
      child: points.length < 2
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.satellite_alt_rounded,
                      color: color.withValues(alpha: 0.6), size: 36),
                  const SizedBox(height: 8),
                  Text(emptyText,
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            )
          : Semantics(
              label: 'Tracé du trajet (${points.length} points GPS)',
              child: CustomPaint(
                size: Size.infinite,
                painter: _RoutePainter(
                  points: points,
                  color: color,
                  grid: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({required this.points, required this.color, required this.grid})
      : count = points.length;

  /// La liste peut grandir pendant le suivi : on compare le nombre de points.
  final List<GeoPoint> points;
  final int count;
  final Color color;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Projection équirectangulaire : suffisante à l'échelle d'une promenade.
    var minLat = points.first.lat, maxLat = minLat;
    var minLng = points.first.lng, maxLng = minLng;
    for (final p in points) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    final k = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    final spanX = math.max((maxLng - minLng) * k, 1e-6);
    final spanY = math.max(maxLat - minLat, 1e-6);
    const pad = 24.0;
    final scale = math.min(
        (size.width - 2 * pad) / spanX, (size.height - 2 * pad) / spanY);
    final dx = (size.width - spanX * scale) / 2;
    final dy = (size.height - spanY * scale) / 2;
    Offset project(GeoPoint p) => Offset(
          dx + (p.lng - minLng) * k * scale,
          size.height - (dy + (p.lat - minLat) * scale),
        );

    final path = Path()..moveTo(project(points.first).dx, project(points.first).dy);
    for (final p in points.skip(1)) {
      final o = project(p);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    void dot(Offset o, Color c) {
      canvas.drawCircle(o, 9, Paint()..color = Colors.white);
      canvas.drawCircle(o, 6, Paint()..color = c);
    }

    dot(project(points.first), AppColors.success);
    dot(project(points.last), color);
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.count != count ||
      !identical(old.points, points) ||
      old.color != color ||
      old.grid != grid;
}
