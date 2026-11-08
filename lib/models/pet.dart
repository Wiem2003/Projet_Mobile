import '../core/pets/pet_directory.dart';
import 'validation.dart';

/// Espèce d'un animal.
enum Species {
  dog('Chien', '🐕', 0.5, 120),
  cat('Chat', '🐈', 0.3, 15),
  bird('Oiseau', '🐦', 0.005, 15),
  rabbit('Lapin', '🐇', 0.3, 12),
  rodent('Rongeur', '🐹', 0.01, 3),
  fish('Poisson', '🐟', 0.001, 30),
  reptile('Reptile', '🦎', 0.005, 200),
  horse('Cheval', '🐴', 50, 1500),
  other('Autre', '🐾', 0.001, 1500);

  const Species(this.label, this.emoji, this.minKg, this.maxKg);

  final String label;
  final String emoji;

  /// Poids plausibles pour l'espèce (contrôle de saisie).
  final double minKg;
  final double maxKg;

  static Species parse(String? value) =>
      values.firstWhere((e) => e.name == value, orElse: () => other);

  /// Espèce d'un `PetSummary` (qui ne porte que le libellé).
  static Species? fromLabel(String? label) {
    for (final s in values) {
      if (s.label == label) return s;
    }
    return null;
  }

  /// Message si [kg] n'est pas un poids plausible pour l'espèce.
  String? weightError(double kg) => kg < minKg || kg > maxKg
      ? 'Poids peu plausible pour un ${label.toLowerCase()} '
          '(${formatDecimal(minKg, decimals: 3)} à ${formatDecimal(maxKg)} kg)'
      : null;
}

enum PetSex {
  male('Mâle', '♂'),
  female('Femelle', '♀'),
  unknown('Inconnu', '?');

  const PetSex(this.label, this.symbol);

  final String label;
  final String symbol;

  static PetSex parse(String? value) =>
      values.firstWhere((e) => e.name == value, orElse: () => unknown);
}

/// Entité Pet (Module 1), une ligne de la table SQLite `pets`.
class Pet {
  Pet({
    this.id,
    required this.name,
    required this.species,
    this.breed,
    this.sex = PetSex.unknown,
    DateTime? birthDate,
    this.weightKg,
    this.color,
    this.identification,
    this.photoPath,
    this.allergies,
    this.sterilized = false,
    this.createdAt,
    this.updatedAt,
  }) : birthDate = birthDate == null
            ? null
            : DateTime(birthDate.year, birthDate.month, birthDate.day);

  static const maxNameLength = 40;
  static const maxTextLength = 40;
  static const maxIdentificationLength = 30;
  static const maxWeightKg = 1500.0;
  static const maxAllergiesLength = 200;

  /// Clé primaire (null tant que l'animal n'est pas en base).
  final int? id;
  final String name;
  final Species species;
  final String? breed;
  final PetSex sex;

  /// Date de naissance (minuit), facultative.
  final DateTime? birthDate;

  /// Poids actuel ; mis à jour par le module Santé à chaque pesée.
  final double? weightKg;
  final String? color;

  /// Numéro de puce électronique ou de tatouage.
  final String? identification;

  /// Chemin de la photo copiée dans le stockage de l'app.
  final String? photoPath;

  /// Allergies connues (médicaments, aliments), en texte libre.
  final String? allergies;

  /// Stérilisé(e) : besoins en énergie plus faibles (ration conseillée).
  final bool sterilized;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Âge en mois révolus, `null` si la date de naissance est inconnue.
  int? ageInMonths(DateTime now) {
    final b = birthDate;
    if (b == null) return null;
    var months = (now.year - b.year) * 12 + now.month - b.month;
    if (now.day < b.day) months--;
    return months < 0 ? 0 : months;
  }

  /// « 3 ans », « 1 an et 2 mois », « 5 mois », « moins d'un mois ».
  String? ageLabel(DateTime now) {
    final m = ageInMonths(now);
    if (m == null) return null;
    if (m == 0) return 'moins d\'un mois';
    final years = m ~/ 12, months = m % 12;
    final y = years == 0 ? '' : '$years an${years > 1 ? 's' : ''}';
    final mo = months == 0 ? '' : '$months mois';
    return [y, mo].where((s) => s.isNotEmpty).join(' et ');
  }

  /// Vue partagée avec les autres modules.
  PetSummary toSummary() => PetSummary(
        id: id!,
        name: name,
        species: species.label,
        weightKg: weightKg,
        photoPath: photoPath,
        birthDate: birthDate,
        sterilized: sterilized,
      );

  /// Règles métier, partagées par le formulaire et le repository.
  /// Renvoie le message d'erreur, ou `null` si l'animal est valide.
  static String? validate(Pet p, DateTime now) {
    final name = p.name.trim();
    if (name.isEmpty) return 'Le nom est obligatoire.';
    if (name.length > maxNameLength) {
      return 'Le nom ne doit pas dépasser $maxNameLength caractères.';
    }
    for (final (label, value) in [('La race', p.breed), ('La couleur', p.color)]) {
      if ((value ?? '').trim().length > maxTextLength) {
        return '$label ne doit pas dépasser $maxTextLength caractères.';
      }
    }
    if ((p.identification ?? '').trim().length > maxIdentificationLength) {
      return 'Le numéro d\'identification est trop long.';
    }
    final b = p.birthDate;
    if (b != null && b.isAfter(now)) {
      return 'La date de naissance ne peut pas être dans le futur.';
    }
    if (b != null && b.year < 1950) return 'Date de naissance invalide.';
    final w = p.weightKg;
    if (w != null && (w <= 0 || w > maxWeightKg)) {
      return 'Le poids doit être compris entre 0 et ${maxWeightKg.round()} kg.';
    }
    if (w != null) {
      final plausible = p.species.weightError(w);
      if (plausible != null) return '$plausible.';
    }
    final nameChars = InputRules.name(name, 'Le nom', max: maxNameLength);
    if (nameChars != null) return '$nameChars.';
    for (final (label, value) in [('La race', p.breed), ('La couleur', p.color)]) {
      final e = InputRules.name(value, label, max: maxTextLength);
      if (e != null) return '$e.';
    }
    final id = InputRules.identification(p.identification);
    if (id != null) return '$id.';
    final allergies =
        InputRules.text(p.allergies, 'Les allergies', max: maxAllergiesLength);
    if (allergies != null) return '$allergies.';
    return null;
  }

  Pet copyWith({
    int? id,
    String? name,
    Species? species,
    String? Function()? breed,
    PetSex? sex,
    DateTime? Function()? birthDate,
    double? Function()? weightKg,
    String? Function()? color,
    String? Function()? identification,
    String? Function()? photoPath,
    String? Function()? allergies,
    bool? sterilized,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Pet(
      id: id ?? this.id,
      name: name ?? this.name,
      species: species ?? this.species,
      breed: breed != null ? breed() : this.breed,
      sex: sex ?? this.sex,
      birthDate: birthDate != null ? birthDate() : this.birthDate,
      weightKg: weightKg != null ? weightKg() : this.weightKg,
      color: color != null ? color() : this.color,
      identification:
          identification != null ? identification() : this.identification,
      photoPath: photoPath != null ? photoPath() : this.photoPath,
      allergies: allergies != null ? allergies() : this.allergies,
      sterilized: sterilized ?? this.sterilized,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'species': species.name,
        'breed': breed,
        'sex': sex.name,
        'birth_date': birthDate?.millisecondsSinceEpoch,
        'weight_kg': weightKg,
        'color': color,
        'identification': identification,
        'photo_path': photoPath,
        'allergies': allergies,
        'sterilized': sterilized ? 1 : 0,
        'created_at': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
        'updated_at': (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      };

  factory Pet.fromMap(Map<String, Object?> map) {
    DateTime? date(String key) {
      final v = map[key] as int?;
      return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
    }

    return Pet(
      id: map['id'] as int?,
      name: map['name'] as String,
      species: Species.parse(map['species'] as String?),
      breed: map['breed'] as String?,
      sex: PetSex.parse(map['sex'] as String?),
      birthDate: date('birth_date'),
      weightKg: (map['weight_kg'] as num?)?.toDouble(),
      color: map['color'] as String?,
      identification: map['identification'] as String?,
      photoPath: map['photo_path'] as String?,
      allergies: map['allergies'] as String?,
      sterilized: (map['sterilized'] as int? ?? 0) == 1,
      createdAt: date('created_at'),
      updatedAt: date('updated_at'),
    );
  }

  @override
  String toString() => 'Pet(#$id "$name" ${species.name})';
}
