import 'package:geolocator/geolocator.dart';

import 'geo_point.dart';

/// Mesure reçue du GPS.
class LocationFix {
  const LocationFix(this.point, {this.accuracyM = 0});

  final GeoPoint point;

  /// Précision annoncée par le téléphone, en mètres.
  final double accuracyM;
}

enum LocationIssue { serviceDisabled, denied, deniedForever }

class LocationException implements Exception {
  const LocationException(this.issue);

  final LocationIssue issue;

  String get message => switch (issue) {
        LocationIssue.serviceDisabled =>
          'La localisation est désactivée sur le téléphone.',
        LocationIssue.denied =>
          'L\'accès à la position est nécessaire pour enregistrer le trajet.',
        LocationIssue.deniedForever =>
          'L\'accès à la position a été refusé. Autorisez-le dans les réglages.',
      };

  @override
  String toString() => message;
}

/// Accès au GPS du téléphone. Remplacé par une source simulée dans les tests.
abstract interface class LocationSource {
  /// Vérifie que le GPS est actif et demande l'autorisation.
  /// Lève une [LocationException] sinon.
  Future<void> ensureReady();

  /// Positions successives pendant la promenade.
  Stream<LocationFix> watch();

  /// Ouvre les réglages adaptés au problème rencontré.
  Future<void> openSettings(LocationIssue issue);
}

/// Implémentation avec le paquet geolocator (Android / iOS).
class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  @override
  Future<void> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(LocationIssue.serviceDisabled);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.denied:
        throw const LocationException(LocationIssue.denied);
      case LocationPermission.deniedForever:
        throw const LocationException(LocationIssue.deniedForever);
      default:
        return;
    }
  }

  @override
  Stream<LocationFix> watch() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5,
        ),
      ).map((p) => LocationFix(
            GeoPoint(p.latitude, p.longitude, p.timestamp),
            accuracyM: p.accuracy,
          ));

  @override
  Future<void> openSettings(LocationIssue issue) =>
      issue == LocationIssue.serviceDisabled
          ? Geolocator.openLocationSettings()
          : Geolocator.openAppSettings();
}
