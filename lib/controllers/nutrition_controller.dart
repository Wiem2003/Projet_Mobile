import 'package:flutter/foundation.dart';

import '../core/pets/pet_directory.dart';
import '../models/meal_schedule.dart';

/// État des horaires de repas, observé par l'écran Alimentation.
class NutritionModel extends ChangeNotifier {
  MealSchedule _schedule = const MealSchedule();

  MealSchedule get schedule => _schedule;

  void setSchedule(MealSchedule s) {
    _schedule = s;
    notifyListeners();
  }
}

/// Controller des horaires de repas : ajout, suppression et notifications
/// quotidiennes « Repas de Mia, 19 h ».
class NutritionController {
  NutritionController({
    required this.model,
    required MealScheduleStore scheduleStore,
    required List<PetSummary> Function() petList,
    MealNotifier? mealNotifier,
  })  : _store = scheduleStore,
        _pets = petList,
        _notifier = mealNotifier;

  final NutritionModel model;
  final MealScheduleStore _store;
  final List<PetSummary> Function() _pets;
  final MealNotifier? _notifier;

  /// Relit les horaires (animaux supprimés retirés) et reprogramme les
  /// notifications.
  Future<void> load() async {
    final ids = {for (final p in _pets()) p.id};
    model.setSchedule((await _store.load()).only(ids));
    await _sync();
  }

  Future<void> addTime(int petId, MealTime t) async {
    if (model.schedule.of(petId).length >= MealSchedule.maxPerPet) return;
    await _save(model.schedule.withTime(petId, t));
  }

  Future<void> removeTime(int petId, MealTime t) => _save(model.schedule.withoutTime(petId, t));

  Future<void> _save(MealSchedule s) async {
    model.setSchedule(s);
    await _store.save(s);
    await _sync();
  }

  Future<void> _sync() async {
    final names = {for (final p in _pets()) p.id: p.name};
    await _notifier?.syncMeals([
      for (final e in model.schedule.times.entries)
        if (names[e.key] case final name?)
          for (final t in e.value) (petId: e.key, petName: name, time: t),
    ]);
  }

  /// Déconnexion : les repas du compte ne sont plus notifiés.
  Future<void> close() async => _notifier?.syncMeals(const []);
}
