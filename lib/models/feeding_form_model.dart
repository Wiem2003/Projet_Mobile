import 'package:flutter/foundation.dart';

import '../core/pets/pet_directory.dart';
import 'feeding_record.dart';
import 'nutrition.dart';
import 'validation.dart';

/// Model du formulaire « Ajouter / Modifier un repas ».
///
/// Les champs numériques sont gardés tels que saisis (texte) et convertis à
/// la validation. Observé par le formulaire ; modifié uniquement par le
/// `FeedingFormController`.
class FeedingFormModel extends ChangeNotifier {
  FeedingFormModel({
    required this.clock,
    required this.pets,
    this.initial,
    int? defaultPetId,
  }) {
    final r = initial;
    final n = clock();
    petId = r?.petId ?? defaultPetId ?? pets.firstOrNull?.id;
    day = r?.date ?? DateTime(n.year, n.month, n.day);
    foodType = r?.foodType ?? FoodType.kibble;
    quantity = r == null ? '' : formatDecimal(r.quantityG);
    price = r == null ? '' : formatDecimal(r.price);
    meals = r?.meals ?? 2;
    brand = r?.brand ?? '';
    kcal = r?.kcalPer100g == null ? '' : formatDecimal(r!.kcalPer100g!, decimals: 0);
  }

  final DateTime Function() clock;
  final List<PetSummary> pets;

  /// Repas modifié (null pour un ajout).
  final FeedingRecord? initial;

  late int? petId;
  late DateTime day;
  late FoodType foodType;
  late String quantity;
  late String price;
  late int meals;
  late String brand;

  /// Calories de l'emballage (kcal pour 100 g), facultatif.
  late String kcal;
  bool saving = false;
  String? error;

  /// Signale aux Views que le formulaire a changé.
  void changed() => notifyListeners();

  bool get isEdit => initial != null;
  DateTime get now => clock();

  double? get quantityValue => parseDecimal(quantity);
  double? get priceValue => parseDecimal(price);

  /// Aperçu : prix au kilo de la saisie.
  double? get pricePerKg {
    final q = quantityValue, p = priceValue;
    return q == null || p == null || q <= 0 ? null : p / q * 1000;
  }

  // ------------------------------------------------------------- Validation

  static String? validateQuantity(String? value) {
    final q = parseDecimal(value ?? '');
    if (q == null) return 'Indiquez la quantité en grammes';
    if (q <= 0) return 'La quantité doit être supérieure à 0';
    if (q > FeedingRecord.maxQuantityG) return '20 000 g maximum';
    return null;
  }

  static String? validatePrice(String? value) {
    final p = parseDecimal(value ?? '');
    if (p == null) return 'Indiquez le prix (0 si gratuit)';
    if (p < 0) return 'Le prix ne peut pas être négatif';
    if (p > FeedingRecord.maxPrice) return 'Prix trop élevé (10 000 DT maximum)';
    return null;
  }

  static String? validateBrand(String? value) =>
      InputRules.text(value, 'La marque', max: FeedingRecord.maxBrandLength);

  static String? validateKcal(String? value) {
    if ((value ?? '').trim().isEmpty) return null;
    final k = parseDecimal(value!);
    if (k == null || k <= 0 || k > FeedingRecord.maxKcalPer100g) {
      return 'Entre 1 et 900 kcal pour 100 g';
    }
    return null;
  }

  double? get kcalValue => parseDecimal(kcal);

  /// Calories de la saisie (emballage, sinon valeur typique du type).
  double? get mealKcal {
    final q = quantityValue;
    if (q == null || q <= 0) return null;
    return q * (kcalValue ?? foodType.typicalKcalPer100g) / 100;
  }

  /// Avertissement si le nombre de repas s'écarte du conseil selon l'âge
  /// (le repas peut quand même être enregistré).
  String? get mealsWarning => Nutrition.mealsWarning(pet, meals, now);

  PetSummary? get pet {
    for (final p in pets) {
      if (p.id == petId) return p;
    }
    return null;
  }

  /// Ration journalière plausible : au plus 30 % du poids de l'animal
  /// (50 g minimum, pour les petits animaux).
  double? get maxDailyQuantityG {
    final w = pet?.weightKg;
    if (w == null) return null;
    final limit = w * 1000 * 0.3;
    return limit < 50 ? 50 : limit;
  }

  /// Quantité valide et plausible pour l'animal choisi.
  String? quantityError(String? value) {
    final base = validateQuantity(value);
    if (base != null) return base;
    final limit = maxDailyQuantityG;
    if (limit != null && parseDecimal(value!)! > limit) {
      return 'Quantité peu plausible pour ${pet!.name} : '
          '${formatDecimal(limit, decimals: 0)} g maximum par jour';
    }
    return null;
  }

  /// Le repas ne peut pas précéder la naissance de l'animal.
  String? get dateError {
    final p = pet;
    return p == null ? null : InputRules.notBeforeBirth(day, p.birthDate, p.name);
  }

  /// Renvoie le premier message d'erreur, ou `null` si tout est valide.
  String? validate() {
    if (petId == null) return 'Choisissez un animal.';
    return quantityError(quantity) ??
        validatePrice(price) ??
        validateBrand(brand) ??
        validateKcal(kcal) ??
        dateError ??
        FeedingRecord.validate(buildRecord(), now);
  }

  FeedingRecord buildRecord() => FeedingRecord(
        id: initial?.id,
        petId: petId ?? 0,
        date: day,
        foodType: foodType,
        quantityG: quantityValue ?? 0,
        price: priceValue ?? 0,
        meals: meals,
        brand: brand.trim().isEmpty ? null : brand.trim(),
        kcalPer100g: kcalValue,
        createdAt: initial?.createdAt,
      );
}
