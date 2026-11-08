import 'package:flutter/foundation.dart';

import '../models/feeding_form_model.dart';
import '../models/feeding_record.dart';
import '../models/validation.dart';
import 'feeding_controller.dart';

/// Controller du formulaire de repas : traite la saisie et enregistre via le
/// [FeedingController].
class FeedingFormController {
  FeedingFormController(this._feeding, {FeedingRecord? initial})
      : model = FeedingFormModel(
          clock: () => _feeding.model.now,
          pets: _feeding.model.pets,
          initial: initial,
          defaultPetId: _feeding.model.petFilter,
        );

  final FeedingController _feeding;
  final FeedingFormModel model;

  void _update(VoidCallback change) {
    change();
    model
      ..error = null
      ..changed();
  }

  void setPet(int id) => _update(() => model.petId = id);

  void setDay(DateTime d) =>
      _update(() => model.day = DateTime(d.year, d.month, d.day));

  void setFoodType(FoodType t) => _update(() => model.foodType = t);

  void setMeals(int n) => _update(
      () => model.meals = n.clamp(1, FeedingRecord.maxMeals).toInt());

  /// Les champs numériques reconstruisent l'aperçu du prix au kilo.
  void setQuantity(String value) => _update(() => model.quantity = value);

  void setPrice(String value) => _update(() => model.price = value);

  void setBrand(String value) => model.brand = value;

  /// Reconstruit l'aperçu des calories.
  void setKcal(String value) => _update(() => model.kcal = value);

  /// Dernier repas de l'animal choisi, proposé à l'ajout.
  FeedingRecord? get lastRecord =>
      model.isEdit ? null : _feeding.model.lastFor(model.petId);

  /// Recopie le type, la quantité, le prix, les repas et la marque du
  /// dernier repas de l'animal.
  void copyLast() {
    final last = lastRecord;
    if (last == null) return;
    _update(() => model
      ..foodType = last.foodType
      ..quantity = formatDecimal(last.quantityG)
      ..price = formatDecimal(last.price)
      ..meals = last.meals
      ..brand = last.brand ?? ''
      ..kcal = last.kcalPer100g == null ? '' : formatDecimal(last.kcalPer100g!, decimals: 0));
  }

  /// Enregistre en base. Renvoie le repas enregistré, ou `null` si la
  /// validation l'a refusé (`model.error` est alors renseigné).
  Future<FeedingRecord?> save() async {
    model.error = model.validate();
    if (model.error != null) {
      model.changed();
      return null;
    }
    model
      ..saving = true
      ..changed();
    try {
      return await _feeding.save(model.buildRecord());
    } on RecordException catch (e) {
      model.error = e.message;
      return null;
    } finally {
      model
        ..saving = false
        ..changed();
    }
  }

  void dispose() => model.dispose();
}
