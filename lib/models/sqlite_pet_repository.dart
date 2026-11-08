import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import 'pet.dart';
import 'pet_repository.dart';
import 'validation.dart';

/// Implémentation SQLite (table `pets`).
///
/// Avec [ownerId], seuls les animaux de ce compte sont visibles et les
/// nouveaux animaux lui appartiennent.
class SqlitePetRepository implements PetRepository {
  SqlitePetRepository(this._appDb, {DateTime Function()? clock, this.ownerId})
      : _clock = clock ?? DateTime.now;

  static const _table = 'pets';

  /// Tables des autres modules qui référencent un animal (`pet_id`).
  static const linkedTables = [
    'health_records',
    'feeding_records',
    'activities',
    'reminders',
  ];

  final AppDatabase _appDb;
  final DateTime Function() _clock;

  /// Compte connecté (`null` : tous les animaux, utilisé par les tests).
  final int? ownerId;

  /// Filtre SQL sur le propriétaire.
  String get _mine => ownerId == null ? '' : ' AND user_id = $ownerId';

  Future<Database> get _db => _appDb.database;

  @override
  Future<List<Pet>> getAll() async {
    final rows = await (await _db).query(_table,
        where: ownerId == null ? null : 'user_id = ?',
        whereArgs: ownerId == null ? null : [ownerId],
        orderBy: 'name COLLATE NOCASE, id');
    return rows.map(Pet.fromMap).toList();
  }

  @override
  Future<Pet> getById(int id) => _find(id, null);

  Future<Pet> _find(int id, DatabaseExecutor? txn) async {
    final rows =
        await (txn ?? await _db).query(_table, where: 'id = ?$_mine', whereArgs: [id]);
    if (rows.isEmpty) throw const RecordException.notFound('Animal introuvable.');
    return Pet.fromMap(rows.first);
  }

  @override
  Future<Pet> create(Pet pet) async {
    final now = _clock();
    final clean = _clean(pet).copyWith(createdAt: now, updatedAt: now);
    final db = await _db;
    await _assertUnique(db, clean);
    final id = await db.insert(_table, {
      ...clean.toMap()..remove('id'),
      'user_id': ?ownerId,
    });
    return clean.copyWith(id: id);
  }

  @override
  Future<Pet> update(Pet pet) async {
    final db = await _db;
    final current = await _find(pet.id!, db);
    final clean = _clean(pet)
        .copyWith(createdAt: current.createdAt, updatedAt: _clock());
    await _assertUnique(db, clean);
    await db.update(_table, clean.toMap(), where: 'id = ?', whereArgs: [clean.id]);
    return clean;
  }

  @override
  Future<Pet> updateWeight(int id, double weightKg) async {
    final current = await getById(id);
    return update(current.copyWith(weightKg: () => weightKg));
  }

  @override
  Future<LinkedRecords> linkedRecords(int id) async {
    final db = await _db;
    Future<int> count(String table) async => Sqflite.firstIntValue(await db
            .rawQuery('SELECT COUNT(*) FROM $table WHERE pet_id = ?', [id])) ??
        0;
    return (
      health: await count('health_records'),
      feeding: await count('feeding_records'),
      activities: await count('activities'),
      reminders: await count('reminders'),
    );
  }

  @override
  Future<void> delete(int id) async {
    await (await _db).transaction((txn) async {
      await _find(id, txn);
      for (final table in linkedTables) {
        await txn.delete(table, where: 'pet_id = ?', whereArgs: [id]);
      }
      await txn.delete(_table, where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Valide et nettoie les textes (espaces, champs vides => null).
  Pet _clean(Pet p) {
    final error = Pet.validate(p, _clock());
    if (error != null) throw RecordException(error);
    String? text(String? v) {
      final t = v?.trim();
      return t == null || t.isEmpty ? null : t;
    }

    final id = text(p.identification)?.replaceAll(' ', '').toUpperCase();
    return p.copyWith(
      name: p.name.trim(),
      breed: () => text(p.breed),
      color: () => text(p.color),
      identification: () => id,
      allergies: () => text(p.allergies),
    );
  }

  Future<void> _assertUnique(Database db, Pet p) async {
    // Un animal n'entre pas en conflit avec lui-même.
    final notSelf = p.id == null ? '' : ' AND id != ${p.id}';
    final sameName = await db.query(_table,
        where: 'LOWER(name) = LOWER(?)$notSelf$_mine', whereArgs: [p.name]);
    if (sameName.isNotEmpty) {
      throw RecordException('Un animal nommé « ${p.name} » existe déjà.');
    }
    if (p.identification != null) {
      final sameId = await db.query(_table,
          where: 'identification = ?$notSelf',
          whereArgs: [p.identification]);
      if (sameId.isNotEmpty) {
        // Le nom de l'animal d'un autre compte n'est pas révélé.
        final other = sameId.first;
        throw RecordException(ownerId == null || other['user_id'] == ownerId
            ? 'Le numéro ${p.identification} est déjà attribué à '
                '${other['name']}.'
            : 'Le numéro ${p.identification} est déjà enregistré pour un '
                'autre animal.');
      }
    }
  }
}
