import 'activity.dart';

/// Accès aux activités et règles métier (validation, calcul des calories).
/// Les erreurs sont des `RecordException`.
abstract interface class ActivityRepository {
  /// De la plus récente à la plus ancienne.
  Future<List<Activity>> getAll({int? petId});
  Future<Activity> getById(int id);

  /// Calcule les calories puis enregistre.
  Future<Activity> create(Activity activity);
  Future<Activity> update(Activity activity);
  Future<void> delete(int id);

  /// À appeler par le module Animaux quand un animal est supprimé.
  Future<int> deleteByPet(int petId);
}
