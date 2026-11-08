import 'package:flutter/foundation.dart';

import '../core/pets/pet_directory.dart';
import 'activity.dart';
import 'activity_stats.dart';
import 'pet.dart';
import 'gps/walk_session_model.dart';
import 'validation.dart';

/// Model du formulaire « Nouvelle activité / Modifier ».
///
/// Peut être prérempli par une promenade GPS ([walk]). Les champs numériques
/// sont gardés tels que saisis (texte) et convertis à la validation.
/// Observé par le formulaire ; modifié uniquement par
/// l'`ActivityFormController`.
class ActivityFormModel extends ChangeNotifier {
  ActivityFormModel({
    required this.clock,
    required this.pets,
    this.initial,
    this.walk,
    int? defaultPetId,
  }) {
    final a = initial;
    final start = a?.date ?? walk?.start ?? clock();
    type = a?.type ?? ActivityType.walk;
    petId = a?.petId ?? defaultPetId ?? pets.firstOrNull?.id;
    day = DateTime(start.year, start.month, start.day);
    hour = start.hour;
    minute = start.minute;
    duration = a != null
        ? '${a.durationMin}'
        : walk != null
            ? '${walk!.durationMin}'
            : '';
    final km = a?.distanceKm ?? walk?.distanceKm ?? 0;
    distance = km > 0 ? formatDecimal(km) : '';
    weightTouched = a?.weightKg != null;
    weight = a?.weightKg != null ? formatDecimal(a!.weightKg!) : petWeightText;
    description = a?.description ?? '';
    route = a?.route ?? walk?.route ?? const [];
  }

  final DateTime Function() clock;
  final List<PetSummary> pets;

  /// Activité modifiée (null pour un ajout).
  final Activity? initial;

  /// Promenade GPS à enregistrer.
  final WalkResult? walk;

  late ActivityType type;
  late int? petId;
  late DateTime day;
  late int hour;
  late int minute;
  late String duration;
  late String distance;
  late String weight;

  /// Vrai dès que l'utilisateur a saisi un poids lui-même.
  late bool weightTouched;
  late String description;
  late List<GeoPoint> route;
  bool saving = false;
  String? error;

  /// Signale aux Views que le formulaire a changé.
  void changed() => notifyListeners();

  bool get isEdit => initial != null;
  bool get fromGps => route.length > 1;
  DateTime get now => clock();
  DateTime get date => DateTime(day.year, day.month, day.day, hour, minute);

  PetSummary? get pet {
    for (final p in pets) {
      if (p.id == petId) return p;
    }
    return null;
  }

  /// Poids connu de l'animal choisi, au format du champ.
  String get petWeightText {
    final w = pet?.weightKg;
    return w == null ? '' : formatDecimal(w);
  }

  int? get durationValue => int.tryParse(duration.trim());
  double get distanceValue => parseDecimal(distance) ?? 0;
  double? get weightValue => parseDecimal(weight);

  /// Aperçu des calories, recalculé à chaque saisie.
  double get estimatedCalories =>
      estimateCalories(type, weightValue, durationValue ?? 0);

  // ------------------------------------------------------------- Validation

  static String? validateDuration(String? value) {
    final d = int.tryParse((value ?? '').trim());
    if (d == null) return 'Indiquez la durée en minutes';
    if (d < 1) return 'Au moins 1 minute';
    if (d > Activity.maxDurationMin) return '24 h maximum';
    return null;
  }

  static String? validateDistance(String? value) {
    if ((value ?? '').trim().isEmpty) return null; // Facultative.
    final d = parseDecimal(value!);
    if (d == null || d < 0) return 'Distance invalide';
    if (d > Activity.maxDistanceKm) return '200 km maximum';
    return null;
  }

  static String? validateWeight(String? value) {
    final w = parseDecimal(value ?? '');
    if (w == null) return 'Indiquez le poids pour estimer les calories';
    if (w <= 0 || w > Activity.maxWeightKg) return 'Poids invalide';
    return null;
  }

  static String? validateDescription(String? value) => InputRules.text(
      value, 'La description', max: Activity.maxDescriptionLength);

  /// Vitesse maximale plausible par type (km/h).
  static const maxSpeedKmh = {
    ActivityType.walk: 12.0,
    ActivityType.run: 70.0,
    ActivityType.swim: 10.0,
  };

  /// Poids valide et plausible pour l'espèce de l'animal choisi.
  String? weightError(String? value) {
    final base = validateWeight(value);
    if (base != null) return base;
    return Species.fromLabel(pet?.species)?.weightError(parseDecimal(value!)!);
  }

  /// Distance et durée cohérentes (une promenade à 40 km/h est une erreur
  /// de saisie). Le GPS filtre déjà les mesures aberrantes.
  String? get speedError {
    final max = maxSpeedKmh[type];
    final minutes = durationValue;
    if (max == null || fromGps || minutes == null || minutes < 1) return null;
    final speed = distanceValue / (minutes / 60);
    if (speed <= max) return null;
    return 'Vitesse peu plausible pour : ${type.label.toLowerCase()} '
        '(${formatDecimal(speed, decimals: 1)} km/h) : vérifiez la durée ou '
        'la distance';
  }

  /// Date et heure : ni dans le futur, ni avant la naissance de l'animal.
  String? get dateError {
    if (date.isAfter(now.add(const Duration(minutes: 1)))) {
      return 'L\'activité ne peut pas être dans le futur';
    }
    final p = pet;
    return p == null ? null : InputRules.notBeforeBirth(date, p.birthDate, p.name);
  }

  /// Renvoie le premier message d'erreur, ou `null` si tout est valide.
  String? validate() {
    if (petId == null) return 'Choisissez un animal.';
    return validateDuration(duration) ??
        (type.usesDistance ? validateDistance(distance) : null) ??
        weightError(weight) ??
        (type.usesDistance ? speedError : null) ??
        validateDescription(description) ??
        dateError ??
        Activity.validate(buildActivity(), now);
  }

  Activity buildActivity() => Activity(
        id: initial?.id,
        petId: petId ?? 0,
        date: date,
        type: type,
        durationMin: durationValue ?? 0,
        distanceKm: type.usesDistance ? distanceValue : 0,
        calories: estimatedCalories,
        weightKg: weightValue,
        description: description.trim().isEmpty ? null : description.trim(),
        route: route,
        createdAt: initial?.createdAt,
      );
}
