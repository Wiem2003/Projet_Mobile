/// Type de nourriture d'un [FeedingRecord].
enum FoodType {
  kibble('Croquettes', 370),
  wet('Pâtée', 90),
  treats('Friandises', 350),
  homemade('Fait maison', 150),
  other('Autre', 200);

  const FoodType(this.label, this.typicalKcalPer100g);

  final String label;

  /// Calories typiques (kcal pour 100 g), utilisées quand l'emballage n'a
  /// pas été saisi.
  final double typicalKcalPer100g;

  static FoodType parse(String? value) =>
      values.firstWhere((e) => e.name == value, orElse: () => other);
}

/// Entité FeedingRecord (Module 3), une ligne de la table SQLite
/// `feeding_records` : ce qu'un animal a mangé un jour donné.
class FeedingRecord {
  FeedingRecord({
    this.id,
    required this.petId,
    required DateTime date,
    required this.foodType,
    required this.quantityG,
    required this.price,
    this.meals = 1,
    this.brand,
    this.kcalPer100g,
    this.createdAt,
    this.updatedAt,
  }) : date = DateTime(date.year, date.month, date.day);

  static const maxQuantityG = 20000.0;
  static const maxPrice = 10000.0;
  static const maxMeals = 10;
  static const maxBrandLength = 60;

  /// Aucun aliment ne dépasse 900 kcal pour 100 g (graisse pure).
  static const maxKcalPer100g = 900.0;

  /// Clé primaire (null tant que l'enregistrement n'est pas en base).
  final int? id;

  /// Animal concerné (table `pets`).
  final int petId;

  /// Jour du repas (à minuit).
  final DateTime date;
  final FoodType foodType;

  /// Quantité donnée, en grammes.
  final double quantityG;

  /// Prix de cette quantité.
  final double price;

  /// Nombre de repas dans la journée.
  final int meals;
  final String? brand;

  /// Calories de l'aliment (kcal pour 100 g), lues sur l'emballage.
  final double? kcalPer100g;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Règles métier, partagées par le formulaire et le repository.
  /// Renvoie le message d'erreur, ou `null` si l'enregistrement est valide.
  static String? validate(FeedingRecord r, DateTime now) {
    if (r.quantityG <= 0) return 'La quantité doit être supérieure à 0.';
    if (r.quantityG > maxQuantityG) {
      return 'Quantité trop élevée (20 kg maximum par jour).';
    }
    if (r.price < 0) return 'Le prix ne peut pas être négatif.';
    if (r.price > maxPrice) return 'Prix trop élevé.';
    if (r.meals < 1 || r.meals > maxMeals) {
      return 'Le nombre de repas doit être compris entre 1 et $maxMeals.';
    }
    final kcal = r.kcalPer100g;
    if (kcal != null && (kcal <= 0 || kcal > maxKcalPer100g)) {
      return 'Les calories doivent être comprises entre 1 et 900 kcal pour 100 g.';
    }
    if ((r.brand ?? '').trim().length > maxBrandLength) {
      return 'La marque ne doit pas dépasser $maxBrandLength caractères.';
    }
    if (r.date.isAfter(DateTime(now.year, now.month, now.day))) {
      return 'La date ne peut pas être dans le futur.';
    }
    return null;
  }

  FeedingRecord copyWith({
    int? id,
    int? petId,
    DateTime? date,
    FoodType? foodType,
    double? quantityG,
    double? price,
    int? meals,
    String? Function()? brand,
    double? Function()? kcalPer100g,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FeedingRecord(
      id: id ?? this.id,
      petId: petId ?? this.petId,
      date: date ?? this.date,
      foodType: foodType ?? this.foodType,
      quantityG: quantityG ?? this.quantityG,
      price: price ?? this.price,
      meals: meals ?? this.meals,
      brand: brand != null ? brand() : this.brand,
      kcalPer100g: kcalPer100g != null ? kcalPer100g() : this.kcalPer100g,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'pet_id': petId,
        'date': date.millisecondsSinceEpoch,
        'food_type': foodType.name,
        'quantity_g': quantityG,
        'price': price,
        'meals': meals,
        'brand': brand,
        'kcal_per_100g': kcalPer100g,
        'created_at': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
        'updated_at': (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      };

  factory FeedingRecord.fromMap(Map<String, Object?> map) {
    DateTime? date(String key) {
      final v = map[key] as int?;
      return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
    }

    return FeedingRecord(
      id: map['id'] as int?,
      petId: map['pet_id'] as int,
      date: date('date')!,
      foodType: FoodType.parse(map['food_type'] as String?),
      quantityG: (map['quantity_g'] as num).toDouble(),
      price: (map['price'] as num?)?.toDouble() ?? 0,
      meals: (map['meals'] as int?) ?? 1,
      brand: map['brand'] as String?,
      kcalPer100g: (map['kcal_per_100g'] as num?)?.toDouble(),
      createdAt: date('created_at'),
      updatedAt: date('updated_at'),
    );
  }

  @override
  String toString() =>
      'FeedingRecord(#$id pet $petId $date ${foodType.name} ${quantityG}g $price)';
}
