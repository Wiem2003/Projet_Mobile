import '../models/pet.dart';
import '../models/pet_photo_store.dart';
import '../models/pet_repository.dart';
import '../models/pets_model.dart';
import '../models/validation.dart';

/// Controller du module Animaux.
///
/// Reçoit les actions de la View (recherche, ajout, modification,
/// suppression), applique les règles via le repository SQLite puis met à
/// jour le [PetsModel]. Après chaque changement, [onPetsChanged] prévient
/// les autres modules (Santé, Repas, Activités, Rappels) pour qu'ils
/// relisent la liste des animaux.
class PetsController {
  PetsController({
    required this.model,
    required PetRepository repository,
    required this.photos,
    this.onPetsChanged,
  }) : _repo = repository;

  final PetsModel model;
  final PetRepository _repo;
  final PetPhotoStore photos;

  /// Branché dans `main.dart` : recharge les autres modules.
  Future<void> Function()? onPetsChanged;

  void setQuery(String q) => model.setQuery(q);

  Future<void> load() async {
    try {
      model.setPets(await _repo.getAll());
    } on Exception catch (e) {
      model.setError('Impossible de charger les animaux : $e');
    }
  }

  Future<T> _mutate<T>(Future<T> Function() action) async {
    final result = await action();
    await load();
    await onPetsChanged?.call();
    return result;
  }

  Future<Pet> save(Pet p) =>
      _mutate(() => p.id == null ? _repo.create(p) : _repo.update(p));

  /// Données des autres modules supprimées avec l'animal.
  Future<LinkedRecords> linkedRecords(Pet p) => _repo.linkedRecords(p.id!);

  /// Supprime l'animal, ses données dans tous les modules et sa photo.
  Future<void> delete(Pet p) async {
    await _mutate(() => _repo.delete(p.id!));
    if (p.photoPath != null) await photos.delete(p.photoPath!);
  }

  /// Nouvelle pesée enregistrée par le module Santé.
  Future<void> updateWeight(int petId, double weightKg) async {
    final current = model.byId(petId);
    if (current == null || current.weightKg == weightKg) return;
    await _mutate(() => _repo.updateWeight(petId, weightKg));
  }

  // ------------------------------------------------------------------ Démo

  /// Animaux d'exemple. Ceux qui existent déjà (même nom) sont ignorés.
  Future<int> seedDemo() async {
    final t = model.now;
    DateTime ago(int years, int months) =>
        DateTime(t.year - years, t.month - months, 12);
    final drafts = [
      Pet(
        name: 'Rex',
        species: Species.dog,
        breed: 'Berger allemand',
        sex: PetSex.male,
        birthDate: ago(3, 2),
        weightKg: 28,
        color: 'Noir et feu',
        identification: '250269812345678',
      ),
      Pet(
        name: 'Mia',
        species: Species.cat,
        breed: 'Européen',
        sex: PetSex.female,
        birthDate: ago(2, 5),
        weightKg: 4.5,
        color: 'Tigrée',
        identification: '250269887654321',
      ),
      Pet(
        name: 'Coco',
        species: Species.bird,
        breed: 'Perruche ondulée',
        sex: PetSex.unknown,
        birthDate: ago(0, 9),
        weightKg: 0.04,
        color: 'Vert et jaune',
      ),
    ];
    var count = 0;
    for (final d in drafts) {
      try {
        await _repo.create(d);
        count++;
      } on RecordException {
        // Déjà présent.
      }
    }
    await load();
    if (count > 0) await onPetsChanged?.call();
    return count;
  }
}
