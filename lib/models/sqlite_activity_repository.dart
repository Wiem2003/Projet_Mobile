import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import 'activity.dart';
import 'activity_repository.dart';
import 'activity_stats.dart';
import 'validation.dart';

/// Implémentation SQLite (table `activities`).
class SqliteActivityRepository implements ActivityRepository {
  SqliteActivityRepository(this._appDb, {DateTime Function()? clock, this.ownerId})
      : _clock = clock ?? DateTime.now;

  static const _table = 'activities';

  final AppDatabase _appDb;
  final DateTime Function() _clock;

  /// Compte connecté : seuls les enregistrements de ses animaux sont
  /// visibles (`null` : tous, utilisé par les tests).
  final int? ownerId;

  String get _mine => ownerId == null
      ? ''
      : ' AND pet_id IN (SELECT id FROM pets WHERE user_id = $ownerId)';

  Future<Database> get _db => _appDb.database;

  @override
  Future<List<Activity>> getAll({int? petId}) async {
    final rows = await (await _db).query(
      _table,
      where: '${petId == null ? '1 = 1' : 'pet_id = ?'}$_mine',
      whereArgs: petId == null ? null : [petId],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(Activity.fromMap).toList();
  }

  @override
  Future<Activity> getById(int id) async {
    final rows =
        await (await _db).query(_table, where: 'id = ?$_mine', whereArgs: [id]);
    if (rows.isEmpty) {
      throw const RecordException.notFound('Activité introuvable.');
    }
    return Activity.fromMap(rows.first);
  }

  @override
  Future<Activity> create(Activity activity) async {
    final now = _clock();
    final clean = _prepare(activity).copyWith(createdAt: now, updatedAt: now);
    final id = await (await _db).insert(_table, clean.toMap()..remove('id'));
    return clean.copyWith(id: id);
  }

  @override
  Future<Activity> update(Activity activity) async {
    final current = await getById(activity.id!);
    final clean = _prepare(activity)
        .copyWith(createdAt: current.createdAt, updatedAt: _clock());
    await (await _db)
        .update(_table, clean.toMap(), where: 'id = ?', whereArgs: [clean.id]);
    return clean;
  }

  @override
  Future<void> delete(int id) async {
    final count =
        await (await _db).delete(_table, where: 'id = ?$_mine', whereArgs: [id]);
    if (count == 0) {
      throw const RecordException.notFound('Activité introuvable.');
    }
  }

  @override
  Future<int> deleteByPet(int petId) =>
      _db.then((db) => db.delete(_table, where: 'pet_id = ?', whereArgs: [petId]));

  /// Valide, nettoie et calcule les calories.
  Activity _prepare(Activity a) {
    final error = Activity.validate(a, _clock());
    if (error != null) throw RecordException(error);
    final description = a.description?.trim();
    return a.copyWith(
      distanceKm: a.type.usesDistance ? a.distanceKm : 0,
      calories: estimateCalories(a.type, a.weightKg, a.durationMin),
      description: () =>
          description == null || description.isEmpty ? null : description,
    );
  }
}
