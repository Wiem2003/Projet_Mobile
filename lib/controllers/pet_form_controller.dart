import 'package:flutter/foundation.dart';

import '../models/pet.dart';
import '../models/pet_form_model.dart';
import '../models/validation.dart';
import 'pets_controller.dart';

/// Controller du formulaire d'animal : saisie, photo (appareil / galerie)
/// et enregistrement via le [PetsController]. Les photos prises puis
/// abandonnées sont supprimées du téléphone.
class PetFormController {
  PetFormController(this._pets, {Pet? initial})
      : model = PetFormModel(clock: () => _pets.model.now, initial: initial);

  final PetsController _pets;
  final PetFormModel model;

  /// Photos prises pendant la saisie.
  final _picked = <String>[];
  bool _saved = false;

  void _update(VoidCallback change) {
    change();
    model
      ..error = null
      ..changed();
  }

  /// Champs texte : pas de reconstruction à chaque frappe.
  void setName(String v) => model.name = v;
  void setBreed(String v) => model.breed = v;
  void setColor(String v) => model.color = v;
  void setIdentification(String v) => model.identification = v;
  void setAllergies(String v) => model.allergies = v;
  void setWeight(String v) => model.weight = v;

  void setSpecies(Species s) => _update(() => model.species = s);
  void setSex(PetSex s) => _update(() => model.sex = s);
  void setSterilized(bool v) => _update(() => model.sterilized = v);
  void setBirthDate(DateTime? d) => _update(() => model.birthDate = d);

  Future<void> pickPhoto({required bool camera}) async {
    _update(() => model.pickingPhoto = true);
    try {
      final path = await _pets.photos.pick(camera: camera);
      if (path != null) {
        _picked.add(path);
        model.photoPath = path;
      }
    } on Exception {
      model.error = camera
          ? 'Impossible d\'ouvrir l\'appareil photo.'
          : 'Impossible d\'ouvrir la galerie.';
    } finally {
      model
        ..pickingPhoto = false
        ..changed();
    }
  }

  void removePhoto() => _update(() => model.photoPath = null);

  /// Enregistre en base. Renvoie l'animal enregistré, ou `null` si la
  /// validation l'a refusé (`model.error` est alors renseigné).
  Future<Pet?> save() async {
    model.error = model.validate();
    if (model.error != null) {
      model.changed();
      return null;
    }
    model
      ..saving = true
      ..changed();
    try {
      final saved = await _pets.save(model.buildPet());
      _saved = true;
      // Photos remplacées ou abandonnées.
      final old = model.initial?.photoPath;
      for (final path in {..._picked, ?old}) {
        if (path != saved.photoPath) await _pets.photos.delete(path);
      }
      return saved;
    } on RecordException catch (e) {
      model.error = e.message;
      return null;
    } finally {
      model
        ..saving = false
        ..changed();
    }
  }

  void dispose() {
    if (!_saved) {
      for (final path in _picked) {
        _pets.photos.delete(path);
      }
    }
    model.dispose();
  }
}
