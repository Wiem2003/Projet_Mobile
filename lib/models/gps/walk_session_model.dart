import 'package:flutter/foundation.dart';

import 'geo_point.dart';
import 'location_source.dart';

enum WalkStatus { idle, starting, tracking, paused, finished }

/// Résultat d'une promenade GPS, repris par le formulaire d'activité.
typedef WalkResult = ({
  DateTime start,
  int durationMin,
  double distanceKm,
  List<GeoPoint> route,
});

/// Model de la promenade en cours : trajet, distance et durée en direct.
///
/// Observé par l'écran GPS ; modifié uniquement par le
/// `WalkTrackingController`.
class WalkSessionModel extends ChangeNotifier {
  WalkStatus status = WalkStatus.idle;
  final List<GeoPoint> points = [];
  double distanceKm = 0;
  Duration elapsed = Duration.zero;
  DateTime? startedAt;

  /// Précision de la dernière mesure, en mètres.
  double? accuracyM;
  String? error;
  LocationIssue? issue;

  bool get isActive =>
      status == WalkStatus.tracking || status == WalkStatus.paused;

  /// Vitesse moyenne depuis le départ.
  double? get speedKmh => elapsed.inSeconds < 10 || distanceKm == 0
      ? null
      : distanceKm / (elapsed.inSeconds / 3600);

  /// Signale aux Views que la promenade a changé.
  void changed() => notifyListeners();
}
