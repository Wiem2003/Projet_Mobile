import 'package:flutter/foundation.dart';

import '../models/activity.dart';
import '../models/activity_form_model.dart';
import '../models/gps/walk_session_model.dart';
import '../models/validation.dart';
import 'activities_controller.dart';

/// Controller du formulaire d'activité : traite la saisie, garde le poids
/// aligné sur l'animal choisi et enregistre via l'[ActivitiesController].
class ActivityFormController {
  ActivityFormController(this._activities, {Activity? initial, WalkResult? walk})
      : model = ActivityFormModel(
          clock: () => _activities.model.now,
          pets: _activities.model.pets,
          initial: initial,
          walk: walk,
          defaultPetId: _activities.model.petFilter,
        );

  final ActivitiesController _activities;
  final ActivityFormModel model;

  void _update(VoidCallback change) {
    change();
    model
      ..error = null
      ..changed();
  }

  void setType(ActivityType t) => _update(() => model.type = t);

  /// Le poids suit l'animal tant que l'utilisateur ne l'a pas saisi.
  void setPet(int id) => _update(() {
        model.petId = id;
        if (!model.weightTouched) model.weight = model.petWeightText;
      });

  void setDay(DateTime d) =>
      _update(() => model.day = DateTime(d.year, d.month, d.day));

  void setTime(int hour, int minute) => _update(() => model
    ..hour = hour
    ..minute = minute);

  /// Les champs numériques reconstruisent l'aperçu des calories.
  void setDuration(String value) => _update(() => model.duration = value);

  void setDistance(String value) => _update(() => model.distance = value);

  void setWeight(String value) => _update(() => model
    ..weight = value
    ..weightTouched = true);

  void setDescription(String value) => model.description = value;

  /// Enregistre en base. Renvoie l'activité enregistrée, ou `null` si la
  /// validation l'a refusée (`model.error` est alors renseigné).
  Future<Activity?> save() async {
    model.error = model.validate();
    if (model.error != null) {
      model.changed();
      return null;
    }
    model
      ..saving = true
      ..changed();
    try {
      return await _activities.save(model.buildActivity());
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
