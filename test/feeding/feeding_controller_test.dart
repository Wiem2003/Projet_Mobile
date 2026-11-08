import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/controllers/feeding_controller.dart';
import 'package:smart_pet/controllers/feeding_form_controller.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/models/feeding_model.dart';
import 'package:smart_pet/models/feeding_record.dart';
import 'package:smart_pet/models/sqlite_feeding_repository.dart';

import '../reminders/test_helpers.dart';

void main() {
  late AppDatabase db;
  late SqliteFeedingRepository repo;
  late FeedingModel model;
  late FeedingController controller;
  final clock = FakeClock(DateTime(2026, 11, 3, 14));

  setUp(() async {
    db = memoryDatabase();
    repo = SqliteFeedingRepository(db, clock: clock.call);
    model = FeedingModel(clock: clock.call);
    controller = FeedingController(
        model: model, repository: repo, pets: const DemoPetDirectory());
    await controller.load();
  });
  tearDown(() async {
    model.dispose();
    await db.close();
  });

  test('chargement, filtres par animal et par mois', () async {
    expect(model.loading, isFalse);
    expect(model.pets, hasLength(2));
    final nov = await repo.create(FeedingRecord(
        petId: rexId,
        date: DateTime(2026, 11, 2),
        foodType: FoodType.kibble,
        quantityG: 350,
        price: 2.6));
    await repo.create(FeedingRecord(
        petId: miaId,
        date: DateTime(2026, 10, 10),
        foodType: FoodType.wet,
        quantityG: 85,
        price: 1.8));
    await controller.load();

    expect(model.month, DateTime(2026, 11));
    expect(model.history.single.id, nov.id);
    expect(model.stats.spending, 2.6);

    controller.previousMonth();
    expect(model.month, DateTime(2026, 10));
    expect(model.history.single.petId, miaId);

    controller.setPetFilter(rexId);
    expect(model.history, isEmpty);
    expect(model.stats.recordCount, 0);

    // Impossible d'aller au-delà du mois en cours.
    controller
      ..nextMonth()
      ..nextMonth();
    expect(model.month, DateTime(2026, 11));
    expect(model.isCurrentMonth, isTrue);
  });

  test('formulaire : validation, ajout, reprise du dernier repas, modification',
      () async {
    final form = FeedingFormController(controller);
    expect(form.model.petId, rexId);
    expect(form.model.day, DateTime(2026, 11, 3));
    expect(form.lastRecord, isNull);

    expect(await form.save(), isNull);
    expect(form.model.error, 'Indiquez la quantité en grammes');

    form
      ..setQuantity('350')
      ..setPrice('2,6')
      ..setBrand('Royal Canin')
      ..setMeals(3);
    expect(form.model.error, isNull);
    expect(form.model.pricePerKg, closeTo(7.43, 0.01));
    final saved = await form.save();
    expect((saved!.price, saved.meals, saved.brand), (2.6, 3, 'Royal Canin'));
    expect(model.all.single.id, saved.id);
    form.dispose();

    final next = FeedingFormController(controller);
    expect(next.lastRecord?.id, saved.id);
    next.copyLast();
    expect(next.model.quantity, '350');
    expect(next.model.price, '2,6');
    expect(next.model.brand, 'Royal Canin');
    expect(next.model.meals, 3);
    next.setPet(miaId);
    expect(next.lastRecord, isNull, reason: 'Mia n\'a encore rien mangé');
    next.dispose();

    final edit = FeedingFormController(controller, initial: saved);
    expect(edit.model.isEdit, isTrue);
    expect(edit.lastRecord, isNull);
    expect(edit.model.quantity, '350');
    edit.setQuantity('400');
    final updated = await edit.save();
    expect(updated!.quantityG, 400);
    expect(model.all.single.quantityG, 400);
    edit.dispose();
  });

  test('formulaire : date future et nombre de repas bornés', () async {
    final form = FeedingFormController(controller)
      ..setQuantity('100')
      ..setPrice('1')
      ..setMeals(99)
      ..setDay(DateTime(2026, 11, 5));
    expect(form.model.meals, FeedingRecord.maxMeals);
    expect(await form.save(), isNull);
    expect(form.model.error, contains('futur'));
    expect(model.all, isEmpty);
    form.dispose();
  });

  test('exemples : 6 mois de dépenses, sans doublon', () async {
    final count = await controller.seedDemo();
    expect(count, 396);
    expect(model.stats.spendingByMonth.where((m) => m.value > 0), hasLength(6));
    expect(model.stats.spendingChange, isNotNull);
    expect(await controller.seedDemo(), 0);
  });
}
