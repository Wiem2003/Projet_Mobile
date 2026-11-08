import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/models/activity.dart';
import 'package:smart_pet/models/feeding_record.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/pet.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminder_exception.dart';
import 'package:smart_pet/models/reminder_repository.dart';
import 'package:smart_pet/models/sqlite_activity_repository.dart';
import 'package:smart_pet/models/sqlite_feeding_repository.dart';
import 'package:smart_pet/models/sqlite_health_repository.dart';
import 'package:smart_pet/models/sqlite_pet_repository.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';
import 'package:smart_pet/models/validation.dart';

import '../reminders/test_helpers.dart';

/// Chaque compte ne voit que ses animaux et leurs données.
void main() {
  late AppDatabase db;
  final now = DateTime(2026, 11, 5, 10);
  DateTime clock() => now;

  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  SqlitePetRepository pets(int owner) =>
      SqlitePetRepository(db, clock: clock, ownerId: owner);

  test('animaux : liste, nom unique par compte, numéro unique partout',
      () async {
    final rexA = await pets(1).create(
        Pet(name: 'Rex', species: Species.dog, identification: '250269812345678'));
    // Un autre compte peut aussi avoir un « Rex »...
    await pets(2).create(Pet(name: 'Rex', species: Species.dog));
    expect(pets(1).create(Pet(name: 'rex', species: Species.dog)),
        throwsA(isA<RecordException>()));
    // ... mais pas la même puce, et le nom de l'animal de l'autre compte
    // n'est pas révélé.
    await expectLater(
        pets(2).create(Pet(
            name: 'Max', species: Species.dog, identification: '250269812345678')),
        throwsA(isA<RecordException>().having((e) => e.message, 'message',
            'Le numéro 250269812345678 est déjà enregistré pour un autre animal.')));

    expect((await pets(1).getAll()).map((p) => p.id), [rexA.id]);
    expect(await pets(2).getAll(), hasLength(1));
    expect(pets(2).getById(rexA.id!), throwsA(isA<RecordException>()));
    expect(pets(2).delete(rexA.id!), throwsA(isA<RecordException>()));
  });

  test('santé, repas, activités : seulement ceux de mes animaux', () async {
    final rex = await pets(1).create(Pet(name: 'Rex', species: Species.dog));
    final mia = await pets(2).create(Pet(name: 'Mia', species: Species.cat));
    final day = DateTime(2026, 11, 4);

    for (final owner in [1, 2]) {
      final pet = owner == 1 ? rex.id! : mia.id!;
      await SqliteHealthRepository(db, clock: clock, ownerId: owner).create(
          HealthRecord(petId: pet, type: HealthType.consultation, date: day));
      await SqliteFeedingRepository(db, clock: clock, ownerId: owner).create(
          FeedingRecord(
              petId: pet, date: day, foodType: FoodType.kibble, quantityG: 100, price: 1));
      await SqliteActivityRepository(db, clock: clock, ownerId: owner).create(
          Activity(petId: pet, date: day, type: ActivityType.walk, durationMin: 20));
    }

    final health = SqliteHealthRepository(db, clock: clock, ownerId: 1);
    final mine = await health.getAll();
    expect(mine.map((r) => r.petId), [rex.id]);
    expect((await SqliteFeedingRepository(db, ownerId: 1).getAll()).single.petId, rex.id);
    expect((await SqliteActivityRepository(db, ownerId: 2).getAll()).single.petId, mia.id);

    // Le dossier de Mia est invisible pour le compte 1.
    final miaRecord = (await SqliteHealthRepository(db, ownerId: 2).getAll()).single;
    expect(health.getById(miaRecord.id!), throwsA(isA<RecordException>()));
    expect(health.delete(miaRecord.id!), throwsA(isA<RecordException>()));
  });

  test('rappels : liste, doublons et synchronisation par compte', () async {
    SqliteReminderRepository repo(int owner) =>
        SqliteReminderRepository(db, clock: clock, ownerId: owner);
    final r = Reminder(
        title: 'Vermifuge', type: ReminderType.deworming, dueDate: DateTime(2026, 12, 1));
    final a = await repo(1).create(r);
    // Le même rappel dans un autre compte n'est pas un doublon.
    await repo(2).create(r);
    expect(repo(1).create(r), throwsA(isA<ReminderException>()));
    expect(await repo(1).getAll(), hasLength(1));
    expect(repo(2).markDone(a.id!), throwsA(isA<ReminderException>()));

    // Même source (ex. dossier de démo) dans deux comptes : deux rappels.
    for (final owner in [1, 2]) {
      final (outcome, _) = await repo(owner).syncFromSource(
          source: ReminderSource.health,
          sourceId: -42,
          dueDate: DateTime(2027, 1, 10, 9),
          type: ReminderType.vaccination);
      expect(outcome, SyncOutcome.created);
    }
    expect(await repo(2).deleteBySource(ReminderSource.health, -42), hasLength(1));
    expect((await repo(1).getAll()).where((x) => x.sourceId == -42), hasLength(1));
  });
}
