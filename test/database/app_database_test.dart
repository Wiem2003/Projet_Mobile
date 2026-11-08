import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/models/activity.dart';
import 'package:smart_pet/models/feeding_record.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/sqlite_activity_repository.dart';
import 'package:smart_pet/models/sqlite_feeding_repository.dart';
import 'package:smart_pet/models/sqlite_health_repository.dart';
import 'package:smart_pet/models/sqlite_pet_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('migration v1 → v3 : nouvelles tables, rappels conservés, '
      'animaux de démo recréés pour les données existantes', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('smart_pet_');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'v1.db');

    // Base installée avec la version 1 : un rappel pour Rex (id 1).
    final v1 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => db.execute(
              'CREATE TABLE reminders (id INTEGER PRIMARY KEY, pet_id INTEGER, '
              'title TEXT, source TEXT, source_id INTEGER, due_date INTEGER)'),
        ));
    await v1.insert('reminders', {'pet_id': 1, 'title': 'Vermifuge'});
    await v1.close();

    final db = AppDatabase(factory: databaseFactoryFfi, path: path);
    addTearDown(db.close);
    final raw = await db.database;
    expect(await raw.getVersion(), AppDatabase.version);
    expect((await raw.query('reminders')).single['title'], 'Vermifuge');
    // v4 : comptes, et propriétaire des animaux et des rappels.
    expect(await raw.query('users'), isEmpty);
    Future<List<String>> columns(String table) async =>
        [for (final c in await raw.rawQuery('PRAGMA table_info($table)')) c['name'] as String];
    expect(await columns('pets'), contains('user_id'));
    expect(await columns('reminders'), contains('user_id'));

    // Rex a des données : il est recréé ; Mia n'en a pas.
    final pets = await SqlitePetRepository(db).getAll();
    expect(pets.map((x) => (x.id, x.name)), [(1, 'Rex')]);

    final now = DateTime.now();
    await SqliteFeedingRepository(db).create(FeedingRecord(
        petId: 1, date: now, foodType: FoodType.kibble, quantityG: 300, price: 3));
    await SqliteActivityRepository(db).create(Activity(
        petId: 1,
        date: now.subtract(const Duration(hours: 1)),
        type: ActivityType.walk,
        durationMin: 30));
    await SqliteHealthRepository(db).create(
        HealthRecord(petId: 1, type: HealthType.consultation, date: now));
    for (final table in ['feeding_records', 'activities', 'health_records']) {
      expect(await raw.query(table), hasLength(1), reason: table);
    }
  });

  test('nouvelle installation : aucun animal fictif', () async {
    sqfliteFfiInit();
    final db = AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    addTearDown(db.close);
    expect(await SqlitePetRepository(db).getAll(), isEmpty);
  });
}
