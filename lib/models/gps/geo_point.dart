import 'dart:convert';
import 'dart:math' as math;

/// Position GPS d'un trajet.
class GeoPoint {
  const GeoPoint(this.lat, this.lng, [this.at]);

  final double lat;
  final double lng;

  /// Heure de la mesure.
  final DateTime? at;

  @override
  String toString() => 'GeoPoint($lat, $lng)';
}

/// Calculs géographiques et stockage des trajets (colonne `route`).
abstract final class Geo {
  static const earthRadiusKm = 6371.0;

  /// Distance à vol d'oiseau entre deux points (formule de haversine).
  static double distanceKm(GeoPoint a, GeoPoint b) {
    double rad(double deg) => deg * math.pi / 180;
    final dLat = rad(b.lat - a.lat);
    final dLng = rad(b.lng - a.lng);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(a.lat)) *
            math.cos(rad(b.lat)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadiusKm * math.asin(math.min(1, math.sqrt(h)));
  }

  /// Longueur d'un trajet.
  static double pathKm(List<GeoPoint> points) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += distanceKm(points[i - 1], points[i]);
    }
    return total;
  }

  /// JSON compact : `[[lat, lng, ms], ...]`.
  static String? encode(List<GeoPoint> points) {
    if (points.isEmpty) return null;
    double round(double v) => (v * 1e6).round() / 1e6;
    return jsonEncode([
      for (final p in points)
        [round(p.lat), round(p.lng), if (p.at != null) p.at!.millisecondsSinceEpoch],
    ]);
  }

  static List<GeoPoint> decode(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      return [
        for (final p in jsonDecode(json) as List)
          GeoPoint(
            (p[0] as num).toDouble(),
            (p[1] as num).toDouble(),
            p.length > 2
                ? DateTime.fromMillisecondsSinceEpoch((p[2] as num).toInt())
                : null,
          ),
      ];
    } on FormatException {
      return const [];
    }
  }
}
