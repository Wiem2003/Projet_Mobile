import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/models/activity.dart';
import 'package:smart_pet/models/feeding_record.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/pet.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/sqlite_activity_repository.dart';
import 'package:smart_pet/models/sqlite_feeding_repository.dart';
import 'package:smart_pet/models/sqlite_health_repository.dart';
import 'package:smart_pet/models/sqlite_pet_repository.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';
import 'package:smart_pet/models/validation.dart';

import '../reminders/test_helpers.dart';

void main() {
  late AppDatabase db;
  late SqlitePetRepository repo;
  final clock = FakeClock(DateTime(2026, 11, 3, 14));

  setUp(() {
    db = memoryDatabase();
    repo = SqlitePetRepository(db, clock: clock.call);
  });
  tearDown(() => db.close());

  Pet pet(String name, {String? id, Species species = Species.dog}) =>
      Pet(name: name, species: species, identification: id);

  test('create : textes nettoyés, numéro normalisé, tri par nom', () async {
    final rex = await repo.create(Pet(
      name: '  Rex ',
      species: Species.dog,
      breed: ' Berger allemand ',
      sex: PetSex.male,
      birthDate: DateTime(2023, 9, 12, 18),
      weightKg: 28,
      color: '   ',
      identification: '250 2698 1234 5678',
      photoPath: '/data/pet_photos/rex.jpg',
    ));
    expect(rex.name, 'Rex');
    expect(rex.breed, 'Berger allemand');
    expect(rex.color, isNull);
    expect(rex.identification, '250269812345678');
    expect(rex.birthDate, DateTime(2023, 9, 12));

    final read = await repo.getById(rex.id!);
    expect((read.sex, read.weightKg, read.photoPath),
        (PetSex.male, 28, '/data/pet_photos/rex.jpg'));

    await repo.create(pet('mia', species: Species.cat));
    await repo.create(pet('Coco', species: Species.bird));
    expect((await repo.getAll()).map((p) => p.name), ['Coco', 'mia', 'Rex']);
  });

  test('règles métier : nom, date de naissance, poids', () async {
    Future<void> rejects(Pet p, String message) => expectLater(
        repo.create(p),
        throwsA(isA<RecordException>()
            .having((e) => e.message, 'message', contains(message))));

    await rejects(pet('   '), 'obligatoire');
    await rejects(pet('x' * 41), '40 caractères');
    await rejects(Pet(name: 'A', species: Species.cat, birthDate: DateTime(2026, 11, 4)),
        'futur');
    await rejects(Pet(name: 'A', species: Species.cat, weightKg: 0), 'poids');
    await rejects(Pet(name: 'A', species: Species.cat, breed: 'x' * 41), 'La race');
    expect(await repo.getAll(), isEmpty);
  });

  test('unicité du nom et du numéro d\'identification', () async {
    final rex = await repo.create(pet('Rex', id: '250269812345678'));
    await expectLater(repo.create(pet('rex')),
        throwsA(isA<RecordException>().having(
            (e) => e.message, 'message', 'Un animal nommé « rex » existe déjà.')));
    await expectLater(
        repo.create(pet('Mia', id: '250 269 812 345 678')),
        throwsA(isA<RecordException>()
            .having((e) => e.message, 'message', contains('déjà attribué à Rex'))));
    // Modifier l'animal lui-même n'est pas un doublon.
    final updated = await repo.update(rex.copyWith(weightKg: () => 29));
    expect(updated.weightKg, 29);
    expect((await repo.updateWeight(rex.id!, 30)).weightKg, 30);
  });

  test('suppression : toutes les données de l\'animal, dans tous les modules',
      () async {
    final rex = await repo.create(pet('Rex'));
    final mia = await repo.create(pet('Mia', species: Species.cat));
    final day = DateTime(2026, 11, 2);
    for (final id in [rex.id!, mia.id!]) {
      await SqliteHealthRepository(db, clock: clock.call).create(
          HealthRecord(petId: id, type: HealthType.consultation, date: day));
      await SqliteFeedingRepository(db, clock: clock.call).create(FeedingRecord(
          petId: id, date: day, foodType: FoodType.kibble, quantityG: 100, price: 1));
      await SqliteActivityRepository(db, clock: clock.call).create(Activity(
          petId: id, date: day, type: ActivityType.walk, durationMin: 30));
      await SqliteReminderRepository(db, clock: clock.call).create(Reminder(
          petId: id,
          title: 'Vermifuge',
          type: ReminderType.deworming,
          dueDate: DateTime(2026, 11, 10)));
    }

    expect(await repo.linkedRecords(rex.id!),
        (health: 1, feeding: 1, activities: 1, reminders: 1));
    await repo.delete(rex.id!);
    expect(await repo.linkedRecords(rex.id!),
        (health: 0, feeding: 0, activities: 0, reminders: 0));
    expect(await repo.linkedRecords(mia.id!),
        (health: 1, feeding: 1, activities: 1, reminders: 1));
    expect((await repo.getAll()).single.name, 'Mia');
    await expectLater(repo.delete(rex.id!), throwsA(isA<RecordException>()));
  });

  test('âge calculé', () {
    final now = DateTime(2026, 11, 3);
    Pet born(DateTime d) => Pet(name: 'A', species: Species.dog, birthDate: d);
    expect(born(DateTime(2023, 9, 12)).ageLabel(now), '3 ans et 1 mois');
    expect(born(DateTime(2025, 11, 3)).ageLabel(now), '1 an');
    expect(born(DateTime(2026, 6, 10)).ageLabel(now), '4 mois');
    expect(born(DateTime(2026, 10, 20)).ageLabel(now), 'moins d\'un mois');
    expect(Pet(name: 'A', species: Species.dog).ageLabel(now), isNull);
  });
}
