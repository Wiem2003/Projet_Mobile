/// Vue minimale d'un animal, utilisée par les modules Rappels, Alimentation
/// et Activités pour afficher le nom de l'animal et filtrer par animal.
class PetSummary {
  const PetSummary({
    required this.id,
    required this.name,
    this.species,
    this.weightKg,
    this.photoPath,
    this.birthDate,
    this.sterilized = false,
  });

  /// Id de l'animal dans la table `pets`.
  final int id;
  final String name;
  final String? species;

  /// Poids actuel, utilisé par le module Activités pour estimer les calories.
  final double? weightKg;

  /// Photo enregistrée sur le téléphone (Module 1), affichée dans l'avatar.
  final String? photoPath;

  /// Stérilisé(e) : utilisé pour la ration conseillée (module Alimentation).
  final bool sterilized;

  /// Date de naissance : les soins, repas et activités ne peuvent pas la
  /// précéder.
  final DateTime? birthDate;

  String get initial => name.isEmpty ? '?' : name[0].toUpperCase();
}

/// Point de contact avec le Module 1 (Pet).
///
/// Les autres modules ne dépendent pas directement de l'entité Pet : ils
/// lisent les animaux via cette interface. Dans l'app, l'implémentation lit
/// la table `pets` (`PetRepositoryDirectory`) ; [DemoPetDirectory] sert aux
/// tests.
abstract interface class PetDirectory {
  Future<List<PetSummary>> getPets();
}

class DemoPetDirectory implements PetDirectory {
  const DemoPetDirectory();

  static const pets = [
    PetSummary(id: 1, name: 'Rex', species: 'Chien', weightKg: 28),
    PetSummary(id: 2, name: 'Mia', species: 'Chat', weightKg: 4.5),
  ];

  @override
  Future<List<PetSummary>> getPets() async => pets;
}

extension DemoPetPair on List<PetSummary> {
  /// Animaux utilisés par les données d'exemple : un chien puis un chat de
  /// préférence (les vaccins, croquettes et promenades de démonstration
  /// sont pensés pour eux). La liste ne doit pas être vide.
  (PetSummary dog, PetSummary cat) get demoPair {
    final dog = firstWhere((p) => p.species == 'Chien', orElse: () => first);
    final others = where((p) => p.id != dog.id);
    final cat = others.firstWhere((p) => p.species == 'Chat',
        orElse: () => others.firstOrNull ?? dog);
    return (dog, cat);
  }
}
