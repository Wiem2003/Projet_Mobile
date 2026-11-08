import 'package:flutter/foundation.dart';

import '../core/pets/pet_directory.dart';
import 'health_record.dart';
import 'pet.dart';
import 'validation.dart';

/// Model du formulaire « Ajouter / Modifier un dossier de santé ».
///
/// Observé par le formulaire ; modifié uniquement par le
/// `HealthFormController`.
class HealthFormModel extends ChangeNotifier {
  HealthFormModel({
    required this.clock,
    required this.pets,
    this.initial,
    HealthRecord? preset,
    int? defaultPetId,
  }) {
    // [preset] pré-remplit un nouveau dossier ; [initial] est modifié.
    final r = initial ?? preset;
    final n = clock();
    type = r?.type ?? HealthType.consultation;
    petId = r?.petId ?? defaultPetId ?? pets.firstOrNull?.id;
    day = r?.date ?? DateTime(n.year, n.month, n.day);
    vet = r?.vet ?? '';
    description = r?.description ?? '';
    weight = r?.weightKg == null ? '' : formatDecimal(r!.weightKg!);
    medication = r?.medication ?? '';
    cost = r == null ? '' : formatDecimal(r.cost);
    nextDue = r?.nextDue;
  }

  final DateTime Function() clock;
  final List<PetSummary> pets;

  /// Dossier modifié (null pour un ajout).
  final HealthRecord? initial;

  late HealthType type;
  late int? petId;
  late DateTime day;
  late String vet;
  late String description;
  late String weight;
  late String medication;
  late String cost;
  late DateTime? nextDue;
  bool saving = false;
  String? error;

  /// Signale aux Views que le formulaire a changé.
  void changed() => notifyListeners();

  bool get isEdit => initial != null;
  DateTime get now => clock();
  double? get weightValue => parseDecimal(weight);

  /// Échéances proposées selon le type de soin.
  List<(String, DateTime)> get quickNextDue {
    DateTime after({int months = 0, int years = 0}) =>
        DateTime(day.year + years, day.month + months, day.day);
    return switch (type) {
      HealthType.vaccination => [
          ('Dans 1 mois', after(months: 1)),
          ('Dans 1 an', after(years: 1)),
          // Certains vaccins contre la rage sont valables 3 ans.
          ('Dans 3 ans', after(years: 3)),
        ],
      HealthType.treatment => [
          ('Dans 1 mois', after(months: 1)),
          ('Dans 3 mois', after(months: 3)),
        ],
      HealthType.dental => [('Dans 1 an', after(years: 1))],
      _ => [
          ('Dans 1 mois', after(months: 1)),
          ('Dans 6 mois', after(months: 6)),
        ],
    };
  }

  static String? validateCost(String? value) {
    if ((value ?? '').trim().isEmpty) return null; // 0 par défaut.
    final c = parseDecimal(value!);
    if (c == null || c < 0) return 'Coût invalide';
    if (c > HealthRecord.maxCost) return 'Coût trop élevé (100 000 DT maximum)';
    return null;
  }

  static String? validateVet(String? value) => InputRules.text(
      value, 'Le nom du vétérinaire', max: HealthRecord.maxVetLength);

  static String? validateDescription(String? value) => InputRules.text(
      value, 'La description', max: HealthRecord.maxDescriptionLength);

  PetSummary? get pet {
    for (final p in pets) {
      if (p.id == petId) return p;
    }
    return null;
  }

  /// Un vaccin ou un traitement doit être nommé.
  String? medicationError(String? value) {
    final required = type == HealthType.vaccination || type == HealthType.treatment;
    final v = (value ?? '').trim();
    if (required && v.isEmpty) {
      return type == HealthType.vaccination
          ? 'Indiquez le nom du vaccin'
          : 'Indiquez le médicament';
    }
    return InputRules.text(v, 'Le médicament', max: HealthRecord.maxMedicationLength);
  }

  /// Poids facultatif, plausible pour l'espèce de l'animal choisi.
  String? weightError(String? value) {
    final base = validateWeight(value);
    if (base != null || (value ?? '').trim().isEmpty) return base;
    return Species.fromLabel(pet?.species)?.weightError(parseDecimal(value!)!);
  }

  /// Le soin ne peut pas précéder la naissance de l'animal.
  String? get dateError {
    final p = pet;
    return p == null ? null : InputRules.notBeforeBirth(day, p.birthDate, p.name);
  }

  /// Échéance après le soin, et au plus dans 10 ans.
  String? get nextDueError {
    final n = nextDue;
    if (n == null) return null;
    if (!n.isAfter(day)) {
      return 'La prochaine échéance doit être postérieure à la date du soin';
    }
    if (n.isAfter(DateTime(day.year + 10, day.month, day.day))) {
      return 'Échéance trop lointaine (10 ans maximum)';
    }
    return null;
  }

  static String? validateWeight(String? value) {
    if ((value ?? '').trim().isEmpty) return null; // Facultatif.
    final w = parseDecimal(value!);
    if (w == null || w <= 0 || w > HealthRecord.maxWeightKg) {
      return 'Poids invalide';
    }
    return null;
  }

  /// Renvoie le premier message d'erreur, ou `null` si tout est valide.
  String? validate() {
    if (petId == null) return 'Choisissez un animal.';
    return weightError(weight) ??
        validateCost(cost) ??
        HealthRecord.validate(buildRecord(), now) ??
        nextDueError ??
        medicationError(medication) ??
        validateVet(vet) ??
        validateDescription(description) ??
        dateError;
  }

  HealthRecord buildRecord() => HealthRecord(
        id: initial?.id,
        petId: petId ?? 0,
        type: type,
        date: day,
        vet: vet,
        description: description,
        weightKg: weightValue,
        medication: medication,
        cost: parseDecimal(cost) ?? 0,
        nextDue: nextDue,
        createdAt: initial?.createdAt,
      );
}
