import 'gps/geo_point.dart';

export 'gps/geo_point.dart';

/// Type d'activité physique.
enum ActivityType {
  walk('Promenade', 3.0, usesDistance: true),
  run('Course', 7.0, usesDistance: true),
  play('Jeu', 4.5),
  swim('Natation', 5.0, usesDistance: true),
  other('Autre', 3.5);

  const ActivityType(this.label, this.met, {this.usesDistance = false});

  final String label;

  /// Intensité (MET) utilisée pour estimer les calories.
  final double met;

  /// La distance a un sens pour ce type (masquée pour le jeu).
  final bool usesDistance;

  static ActivityType parse(String? value) =>
      values.firstWhere((e) => e.name == value, orElse: () => other);
}

/// Entité Activity (Module 4), une ligne de la table SQLite `activities`.
class Activity {
  Activity({
    this.id,
    required this.petId,
    required this.date,
    required this.type,
    required this.durationMin,
    this.distanceKm = 0,
    this.calories = 0,
    this.weightKg,
    this.description,
    List<GeoPoint>? route,
    this.createdAt,
    this.updatedAt,
  }) : route = List.unmodifiable(route ?? const <GeoPoint>[]);

  static const maxDurationMin = 24 * 60;
  static const maxDistanceKm = 200.0;
  static const maxWeightKg = 1500.0;
  static const maxDescriptionLength = 500;

  /// Clé primaire (null tant que l'activité n'est pas en base).
  final int? id;

  /// Animal concerné (table `pets`).
  final int petId;

  /// Date et heure de début.
  final DateTime date;
  final ActivityType type;

  /// Durée en minutes.
  final int durationMin;

  /// Distance en kilomètres (0 si non mesurée).
  final double distanceKm;

  /// Calories estimées, calculées à l'enregistrement.
  final double calories;

  /// Poids de l'animal utilisé pour le calcul des calories.
  final double? weightKg;
  final String? description;

  /// Trajet enregistré par le GPS (vide pour une saisie manuelle).
  final List<GeoPoint> route;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasRoute => route.length > 1;

  /// Vitesse moyenne (km/h), si la distance est connue.
  double? get speedKmh =>
      distanceKm > 0 && durationMin > 0 ? distanceKm / (durationMin / 60) : null;

  /// Règles métier, partagées par le formulaire et le repository.
  /// Renvoie le message d'erreur, ou `null` si l'activité est valide.
  static String? validate(Activity a, DateTime now) {
    if (a.durationMin < 1) return 'La durée doit être d\'au moins 1 minute.';
    if (a.durationMin > maxDurationMin) {
      return 'La durée ne peut pas dépasser 24 heures.';
    }
    if (a.distanceKm < 0) return 'La distance ne peut pas être négative.';
    if (a.distanceKm > maxDistanceKm) {
      return 'Distance trop élevée (${maxDistanceKm.round()} km maximum).';
    }
    final w = a.weightKg;
    if (w != null && (w <= 0 || w > maxWeightKg)) {
      return 'Le poids doit être compris entre 0 et ${maxWeightKg.round()} kg.';
    }
    if ((a.description ?? '').length > maxDescriptionLength) {
      return 'La description ne doit pas dépasser $maxDescriptionLength caractères.';
    }
    if (a.date.isAfter(now.add(const Duration(minutes: 1)))) {
      return 'La date ne peut pas être dans le futur.';
    }
    return null;
  }

  Activity copyWith({
    int? id,
    int? petId,
    DateTime? date,
    ActivityType? type,
    int? durationMin,
    double? distanceKm,
    double? calories,
    double? Function()? weightKg,
    String? Function()? description,
    List<GeoPoint>? route,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Activity(
      id: id ?? this.id,
      petId: petId ?? this.petId,
      date: date ?? this.date,
      type: type ?? this.type,
      durationMin: durationMin ?? this.durationMin,
      distanceKm: distanceKm ?? this.distanceKm,
      calories: calories ?? this.calories,
      weightKg: weightKg != null ? weightKg() : this.weightKg,
      description: description != null ? description() : this.description,
      route: route ?? this.route,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'pet_id': petId,
        'date': date.millisecondsSinceEpoch,
        'type': type.name,
        'duration_min': durationMin,
        'distance_km': distanceKm,
        'calories': calories,
        'weight_kg': weightKg,
        'description': description,
        'route': Geo.encode(route),
        'created_at': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
        'updated_at': (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      };

  factory Activity.fromMap(Map<String, Object?> map) {
    DateTime? date(String key) {
      final v = map[key] as int?;
      return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
    }

    return Activity(
      id: map['id'] as int?,
      petId: map['pet_id'] as int,
      date: date('date')!,
      type: ActivityType.parse(map['type'] as String?),
      durationMin: map['duration_min'] as int,
      distanceKm: (map['distance_km'] as num?)?.toDouble() ?? 0,
      calories: (map['calories'] as num?)?.toDouble() ?? 0,
      weightKg: (map['weight_kg'] as num?)?.toDouble(),
      description: map['description'] as String?,
      route: Geo.decode(map['route'] as String?),
      createdAt: date('created_at'),
      updatedAt: date('updated_at'),
    );
  }

  @override
  String toString() =>
      'Activity(#$id pet $petId ${type.name} $date ${durationMin}min ${distanceKm}km)';
}
