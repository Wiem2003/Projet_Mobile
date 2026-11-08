import 'health_record.dart';

/// Accès aux dossiers de santé et règles métier (validation).
/// Les erreurs sont des `RecordException`.
abstract interface class HealthRepository {
  /// Du plus récent au plus ancien.
  Future<List<HealthRecord>> getAll({int? petId});
  Future<HealthRecord> getById(int id);
  Future<HealthRecord> create(HealthRecord record);
  Future<HealthRecord> update(HealthRecord record);
  Future<void> delete(int id);
}
