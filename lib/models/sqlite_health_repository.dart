import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import 'health_record.dart';
import 'health_repository.dart';
import 'validation.dart';

/// Implémentation SQLite (table `health_records`).
class SqliteHealthRepository implements HealthRepository {
  SqliteHealthRepository(this._appDb, {DateTime Function()? clock, this.ownerId})
      : _clock = clock ?? DateTime.now;

  static const _table = 'health_records';

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
  Future<List<HealthRecord>> getAll({int? petId}) async {
    final rows = await (await _db).query(
      _table,
      where: '${petId == null ? '1 = 1' : 'pet_id = ?'}$_mine',
      whereArgs: petId == null ? null : [petId],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(HealthRecord.fromMap).toList();
  }

  @override
  Future<HealthRecord> getById(int id) async {
    final rows =
        await (await _db).query(_table, where: 'id = ?$_mine', whereArgs: [id]);
    if (rows.isEmpty) {
      throw const RecordException.notFound('Dossier de santé introuvable.');
    }
    return HealthRecord.fromMap(rows.first);
  }

  @override
  Future<HealthRecord> create(HealthRecord record) async {
    final now = _clock();
    final clean = _clean(record).copyWith(createdAt: now, updatedAt: now);
    final id = await (await _db).insert(_table, clean.toMap()..remove('id'));
    return clean.copyWith(id: id);
  }

  @override
  Future<HealthRecord> update(HealthRecord record) async {
    final current = await getById(record.id!);
    final clean = _clean(record)
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
      throw const RecordException.notFound('Dossier de santé introuvable.');
    }
  }

  HealthRecord _clean(HealthRecord r) {
    final error = HealthRecord.validate(r, _clock());
    if (error != null) throw RecordException(error);
    String? text(String? v) {
      final t = v?.trim();
      return t == null || t.isEmpty ? null : t;
    }

    return r.copyWith(
      vet: () => text(r.vet),
      description: () => text(r.description),
      medication: () => text(r.medication),
    );
  }
}
