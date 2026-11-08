import '../core/pets/pet_directory.dart';
import 'pet.dart';

/// Données des autres modules rattachées à un animal (avant suppression).
typedef LinkedRecords = ({
  int health,
  int feeding,
  int activities,
  int reminders,
});

/// Accès aux animaux et règles métier (validation, unicité du nom et du
/// numéro d'identification). Les erreurs sont des `RecordException`.
abstract interface class PetRepository {
  /// Triés par nom.
  Future<List<Pet>> getAll();
  Future<Pet> getById(int id);
  Future<Pet> create(Pet pet);
  Future<Pet> update(Pet pet);

  /// Nouveau poids mesuré (module Santé).
  Future<Pet> updateWeight(int id, double weightKg);

  Future<LinkedRecords> linkedRecords(int id);

  /// Supprime l'animal et toutes ses données (santé, repas, activités,
  /// rappels) en une transaction.
  Future<void> delete(int id);
}

/// Les autres modules lisent les animaux à travers [PetDirectory].
class PetRepositoryDirectory implements PetDirectory {
  const PetRepositoryDirectory(this._repo);

  final PetRepository _repo;

  @override
  Future<List<PetSummary>> getPets() async =>
      [for (final p in await _repo.getAll()) p.toSummary()];
}
