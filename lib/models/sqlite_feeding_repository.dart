import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import 'feeding_record.dart';
import 'feeding_repository.dart';
import 'validation.dart';

/// Implémentation SQLite (table `feeding_records`).
class SqliteFeedingRepository implements FeedingRepository {
  SqliteFeedingRepository(this._appDb, {DateTime Function()? clock, this.ownerId})
      : _clock = clock ?? DateTime.now;

  static const _table = 'feeding_records';

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
  Future<List<FeedingRecord>> getAll({int? petId}) async {
    final rows = await (await _db).query(
      _table,
      where: '${petId == null ? '1 = 1' : 'pet_id = ?'}$_mine',
      whereArgs: petId == null ? null : [petId],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(FeedingRecord.fromMap).toList();
  }

  @override
  Future<FeedingRecord> getById(int id) async {
    final rows =
        await (await _db).query(_table, where: 'id = ?$_mine', whereArgs: [id]);
    if (rows.isEmpty) throw const RecordException.notFound('Repas introuvable.');
    return FeedingRecord.fromMap(rows.first);
  }

  @override
  Future<FeedingRecord> create(FeedingRecord record) async {
    final now = _clock();
    final clean = _validate(record).copyWith(createdAt: now, updatedAt: now);
    final id = await (await _db).insert(_table, clean.toMap()..remove('id'));
    return clean.copyWith(id: id);
  }

  @override
  Future<int> createAll(List<FeedingRecord> records) async {
    final now = _clock();
    final rows = [
      for (final r in records)
        (_validate(r).copyWith(createdAt: now, updatedAt: now).toMap()
          ..remove('id')),
    ];
    await (await _db).transaction((txn) async {
      final batch = txn.batch();
      for (final row in rows) {
        batch.insert(_table, row);
      }
      await batch.commit(noResult: true);
    });
    return rows.length;
  }

  @override
  Future<FeedingRecord> update(FeedingRecord record) async {
    final current = await getById(record.id!);
    final clean = _validate(record)
        .copyWith(createdAt: current.createdAt, updatedAt: _clock());
    await (await _db)
        .update(_table, clean.toMap(), where: 'id = ?', whereArgs: [clean.id]);
    return clean;
  }

  @override
  Future<void> delete(int id) async {
    final count =
        await (await _db).delete(_table, where: 'id = ?$_mine', whereArgs: [id]);
    if (count == 0) throw const RecordException.notFound('Repas introuvable.');
  }

  @override
  Future<int> deleteByPet(int petId) =>
      _db.then((db) => db.delete(_table, where: 'pet_id = ?', whereArgs: [petId]));

  FeedingRecord _validate(FeedingRecord r) {
    final error = FeedingRecord.validate(r, _clock());
    if (error != null) throw RecordException(error);
    final brand = r.brand?.trim();
    return r.copyWith(brand: () => brand == null || brand.isEmpty ? null : brand);
  }
}
