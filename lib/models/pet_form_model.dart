import 'package:flutter/foundation.dart';

import 'pet.dart';
import 'validation.dart';

/// Model du formulaire « Ajouter / Modifier un animal ».
///
/// Observé par le formulaire ; modifié uniquement par le
/// `PetFormController`.
class PetFormModel extends ChangeNotifier {
  PetFormModel({required this.clock, this.initial}) {
    final p = initial;
    name = p?.name ?? '';
    species = p?.species ?? Species.dog;
    breed = p?.breed ?? '';
    sex = p?.sex ?? PetSex.unknown;
    sterilized = p?.sterilized ?? false;
    birthDate = p?.birthDate;
    weight = p?.weightKg == null ? '' : formatDecimal(p!.weightKg!);
    color = p?.color ?? '';
    identification = p?.identification ?? '';
    allergies = p?.allergies ?? '';
    photoPath = p?.photoPath;
  }

  final DateTime Function() clock;

  /// Animal modifié (null pour un ajout).
  final Pet? initial;

  late String name;
  late Species species;
  late String breed;
  late PetSex sex;
  late bool sterilized;
  late DateTime? birthDate;
  late String weight;
  late String color;
  late String identification;
  late String allergies;
  late String? photoPath;
  bool saving = false;
  bool pickingPhoto = false;
  String? error;

  /// Signale aux Views que le formulaire a changé.
  void changed() => notifyListeners();

  bool get isEdit => initial != null;
  DateTime get now => clock();
  double? get weightValue => parseDecimal(weight);

  /// Aperçu de l'âge calculé.
  String? get ageLabel => Pet(name: '', species: species, birthDate: birthDate)
      .ageLabel(now);

  // ------------------------------------------------- Contrôles de saisie

  static String? validateName(String? value) =>
      InputRules.name(value, 'Le nom', required: true, max: Pet.maxNameLength);

  static String? validateBreed(String? value) =>
      InputRules.name(value, 'La race', max: Pet.maxTextLength);

  static String? validateColor(String? value) =>
      InputRules.name(value, 'La couleur', max: Pet.maxTextLength);

  static String? validateIdentification(String? value) =>
      InputRules.identification(value);

  static String? validateAllergies(String? value) =>
      InputRules.text(value, 'Les allergies', max: Pet.maxAllergiesLength);

  /// Poids facultatif, plausible pour l'espèce choisie.
  String? weightError(String? value) {
    if ((value ?? '').trim().isEmpty) return null;
    final w = parseDecimal(value!);
    if (w == null || w <= 0 || w > Pet.maxWeightKg) return 'Poids invalide';
    return species.weightError(w);
  }

  /// Date de naissance : ni dans le futur, ni avant 1950.
  String? get birthDateError {
    final b = birthDate;
    if (b == null) return null;
    if (b.isAfter(now)) return 'La date de naissance ne peut pas être dans le futur';
    if (b.year < 1950) return 'Date de naissance invalide';
    return null;
  }

  String? validate() =>
      validateName(name) ??
      validateBreed(breed) ??
      validateColor(color) ??
      validateIdentification(identification) ??
      validateAllergies(allergies) ??
      weightError(weight) ??
      birthDateError ??
      Pet.validate(buildPet(), now);

  Pet buildPet() => Pet(
        id: initial?.id,
        name: name.trim(),
        species: species,
        breed: breed,
        sex: sex,
        sterilized: sterilized,
        birthDate: birthDate,
        weightKg: weightValue,
        color: color,
        identification: identification,
        photoPath: photoPath,
        allergies: allergies,
        createdAt: initial?.createdAt,
      );
}
