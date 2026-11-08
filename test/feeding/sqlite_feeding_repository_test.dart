import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/models/feeding_record.dart';
import 'package:smart_pet/models/sqlite_feeding_repository.dart';
import 'package:smart_pet/models/validation.dart';

import '../reminders/test_helpers.dart';

void main() {
  late AppDatabase db;
  late SqliteFeedingRepository repo;
  final clock = FakeClock(DateTime(2026, 11, 3, 14));

  setUp(() {
    db = memoryDatabase();
    repo = SqliteFeedingRepository(db, clock: clock.call);
  });
  tearDown(() => db.close());

  FeedingRecord draft({
    int petId = rexId,
    DateTime? date,
    FoodType type = FoodType.kibble,
    double quantityG = 350,
    double price = 2.6,
    int meals = 2,
    String? brand,
  }) =>
      FeedingRecord(
        petId: petId,
        date: date ?? DateTime(2026, 11, 2),
        foodType: type,
        quantityG: quantityG,
        price: price,
        meals: meals,
        brand: brand,
      );

  test('create : date à minuit, marque nettoyée, horodatage', () async {
    final r = await repo.create(
        draft(date: DateTime(2026, 11, 2, 19, 30), brand: '  Royal Canin '));
    expect(r.id, isNotNull);
    expect(r.date, DateTime(2026, 11, 2));
    expect(r.brand, 'Royal Canin');
    expect(r.createdAt, clock.now);

    final read = await repo.getById(r.id!);
    expect(read.quantityG, 350);
    expect(read.price, 2.6);
    expect(read.meals, 2);
    expect(read.foodType, FoodType.kibble);

    expect((await repo.create(draft(brand: '   '))).brand, isNull);
  });

  test('règles métier : quantité, prix, repas, marque, date', () async {
    Future<void> rejects(FeedingRecord r, String message) => expectLater(
        repo.create(r),
        throwsA(isA<RecordException>()
            .having((e) => e.message, 'message', contains(message))));

    await rejects(draft(quantityG: 0), 'quantité');
    await rejects(draft(quantityG: 25000), 'Quantité trop élevée');
    await rejects(draft(price: -1), 'négatif');
    await rejects(draft(meals: 0), 'repas');
    await rejects(draft(brand: 'x' * 61), 'marque');
    await rejects(draft(date: DateTime(2026, 11, 4)), 'futur');
    // Aujourd'hui est accepté.
    await repo.create(draft(date: DateTime(2026, 11, 3, 23)));
    expect(await repo.getAll(), hasLength(1));
  });

  test('historique trié, filtre par animal, modification', () async {
    final old = await repo.create(draft(date: DateTime(2026, 10, 1)));
    final mia = await repo.create(
        draft(petId: miaId, type: FoodType.wet, quantityG: 85, price: 1.8));
    final recent = await repo.create(draft(date: DateTime(2026, 11, 3)));

    expect((await repo.getAll()).map((r) => r.id), [recent.id, mia.id, old.id]);
    expect((await repo.getAll(petId: miaId)).single.id, mia.id);

    clock.now = DateTime(2026, 11, 3, 15);
    final updated =
        await repo.update(old.copyWith(quantityG: 400, brand: () => 'Purina'));
    expect(updated.createdAt, DateTime(2026, 11, 3, 14));
    expect(updated.updatedAt, DateTime(2026, 11, 3, 15));
    final read = await repo.getById(old.id!);
    expect((read.quantityG, read.brand), (400, 'Purina'));

    await expectLater(repo.update(old.copyWith(id: 999)),
        throwsA(isA<RecordException>()));
    await expectLater(
        repo.update(old.copyWith(quantityG: -5)), throwsA(isA<RecordException>()));
  });

  test('suppression, import groupé, suppression par animal', () async {
    final r = await repo.create(draft());
    await repo.delete(r.id!);
    await expectLater(repo.delete(r.id!), throwsA(isA<RecordException>()));

    final count = await repo.createAll([
      for (var d = 1; d <= 3; d++) draft(date: DateTime(2026, 11, d)),
      draft(petId: miaId),
    ]);
    expect(count, 4);
    expect(await repo.deleteByPet(rexId), 3);
    expect((await repo.getAll()).single.petId, miaId);

    // Une ligne invalide annule tout l'import.
    await expectLater(repo.createAll([draft(), draft(quantityG: 0)]),
        throwsA(isA<RecordException>()));
    expect(await repo.getAll(), hasLength(1));
  });
}
