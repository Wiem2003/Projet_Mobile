import 'feeding_record.dart';

/// Accès aux enregistrements d'alimentation et règles métier (validation).
/// Les erreurs sont des `RecordException`.
abstract interface class FeedingRepository {
  /// Du plus récent au plus ancien.
  Future<List<FeedingRecord>> getAll({int? petId});
  Future<FeedingRecord> getById(int id);
  Future<FeedingRecord> create(FeedingRecord record);

  /// Enregistre plusieurs repas en une transaction (import, démo).
  Future<int> createAll(List<FeedingRecord> records);
  Future<FeedingRecord> update(FeedingRecord record);
  Future<void> delete(int id);

  /// À appeler par le module Animaux quand un animal est supprimé.
  Future<int> deleteByPet(int petId);
}
