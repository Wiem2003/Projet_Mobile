import 'package:flutter/foundation.dart';

import '../models/health_form_model.dart';
import '../models/health_record.dart';
import '../models/validation.dart';
import 'health_controller.dart';

/// Controller du formulaire de dossier de santé : traite la saisie et
/// enregistre via le [HealthController].
class HealthFormController {
  /// [preset] : nouveau dossier pré-rempli (ex. consultation proposée après
  /// une baisse d'appétit).
  HealthFormController(this._health, {HealthRecord? initial, HealthRecord? preset})
      : model = HealthFormModel(
          clock: () => _health.model.now,
          pets: _health.model.pets,
          initial: initial,
          preset: preset,
          defaultPetId: _health.model.petFilter,
        );

  final HealthController _health;
  final HealthFormModel model;

  void _update(VoidCallback change) {
    change();
    model
      ..error = null
      ..changed();
  }

  void setType(HealthType t) => _update(() => model.type = t);
  void setPet(int id) => _update(() => model.petId = id);

  void setDay(DateTime d) =>
      _update(() => model.day = DateTime(d.year, d.month, d.day));

  void setNextDue(DateTime? d) => _update(() => model.nextDue =
      d == null ? null : DateTime(d.year, d.month, d.day));

  /// Champs texte : pas de reconstruction à chaque frappe.
  void setVet(String v) => model.vet = v;
  void setDescription(String v) => model.description = v;
  void setMedication(String v) => model.medication = v;
  void setWeight(String v) => model.weight = v;
  void setCost(String v) => model.cost = v;

  /// Enregistre en base. Renvoie le dossier enregistré, ou `null` si la
  /// validation l'a refusé (`model.error` est alors renseigné).
  Future<HealthRecord?> save() async {
    model.error = model.validate();
    if (model.error != null) {
      model.changed();
      return null;
    }
    model
      ..saving = true
      ..changed();
    try {
      return await _health.save(model.buildRecord());
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
