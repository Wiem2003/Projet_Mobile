import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/controllers/feeding_controller.dart';
import 'package:smart_pet/controllers/feeding_plan_controller.dart';
import 'package:smart_pet/controllers/nutrition_controller.dart';
import 'package:smart_pet/controllers/reminders_controller.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/core/theme/app_theme.dart';
import 'package:smart_pet/models/activities_model.dart';
import 'package:smart_pet/models/feeding_insights.dart';
import 'package:smart_pet/models/feeding_model.dart';
import 'package:smart_pet/models/feeding_plan.dart';
import 'package:smart_pet/models/feeding_record.dart';
import 'package:smart_pet/models/health_model.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/meal_schedule.dart';
import 'package:smart_pet/models/nutrition.dart';
import 'package:smart_pet/models/pet.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminders_model.dart';
import 'package:smart_pet/models/sqlite_feeding_repository.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';
import 'package:smart_pet/models/validation.dart';
import 'package:smart_pet/views/screens/feeding_screen.dart';

import '../reminders/test_helpers.dart';

/// Stock des sacs, programme de perte de poids, budget alimentaire.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  // Dimanche 8 novembre 2026, 10 h.
  final now = DateTime(2026, 11, 8, 10);
  const rex = PetSummary(id: rexId, name: 'Rex', species: 'Chien', weightKg: 28, sterilized: true);
  const mia = PetSummary(id: miaId, name: 'Mia', species: 'Chat', weightKg: 6);

  FeedingRecord meal(int pet, int day, double g,
          {FoodType type = FoodType.kibble, String? brand, double price = 1}) =>
      FeedingRecord(
          petId: pet, date: DateTime(2026, 11, day), foodType: type, quantityG: g,
          price: price, brand: brand);

  group('stock', () {
    final bag = FoodBag(
        id: 1, petIds: [rexId, miaId], foodType: FoodType.kibble, weightG: 3000, price: 40,
        openedOn: DateTime(2026, 11, 3), brand: 'Royal Canin');

    test('reste, consommation additionnée et date du rappel', () {
      final s = FeedingInsights.stock(bag, [
        meal(rexId, 2, 300), // avant l'ouverture
        for (var d = 3; d <= 8; d++) ...[meal(rexId, d, 300), meal(miaId, d, 60)],
        meal(rexId, 8, 50, type: FoodType.treats), // autre aliment
        meal(miaId, 7, 40, brand: 'Purina'), // autre marque
      ], now);
      expect(s.consumedG, 6 * 360);
      expect(s.remainingG, 840);
      expect(s.dailyG, 360, reason: 'Rex + Mia, par jour saisi');
      expect(s.daysLeft, closeTo(2.33, 0.01));
      expect(s.emptyOn, DateTime(2026, 11, 10));
      expect(s.restockOn, DateTime(2026, 11, 8), reason: '3 jours avant, pas avant aujourd\'hui');
      expect(s.low, isTrue);
      expect(FeedingInsights.stockSentence(s, ['Rex', 'Mia']),
          'Sac de Rex et Mia vide dans environ 2 jours.');
    });

    test('sac vide, consommation inconnue, validation', () {
      final empty = FeedingInsights.stock(bag, [meal(rexId, 4, 3200)], now);
      expect((empty.empty, empty.daysLeft, empty.emptyOn), (true, 0, DateTime(2026, 11, 8)));
      expect(FeedingInsights.stockSentence(empty, ['Rex']), 'Sac de Rex vide : pensez à en racheter.');
      final unknown = FeedingInsights.stock(bag, const [], now);
      expect((unknown.dailyG, unknown.emptyOn, unknown.low), (null, null, false));

      String? v(FoodBag b) => FoodBag.validate(b, now);
      expect(v(bag), isNull);
      expect(v(bag.withPets([])), 'Choisissez au moins un animal.');
      expect(v(FoodBag(id: 2, petIds: [1], foodType: FoodType.kibble, weightG: 60000, price: 0,
          openedOn: now)), contains('50 kg'));
      expect(v(FoodBag(id: 2, petIds: [1], foodType: FoodType.kibble, weightG: 1000, price: 0,
          openedOn: DateTime(2026, 11, 9))), contains('futur'));
    });
  });

  group('perte de poids', () {
    final plan = DietPlan(petId: rexId, startKg: 28, targetKg: 25, startDate: DateTime(2026, 9, 1));

    test('durée, date d\'arrivée et courbe prévue', () {
      expect(plan.weeks, 12, reason: '28 → 25 kg à 1 % par semaine');
      expect(plan.arrival, DateTime(2026, 11, 24));
      expect(plan.plannedKgAt(DateTime(2026, 9, 8)), closeTo(27.72, 0.001));
      expect(plan.plannedKgAt(DateTime(2027, 6, 1)), 25, reason: 'jamais sous l\'objectif');
      expect(DietPlan.validate(plan), isNull);
      expect(DietPlan.validate(DietPlan(petId: 1, startKg: 28, targetKg: 29, startDate: now)),
          contains('inférieur'));
      expect(DietPlan.validate(DietPlan(petId: 1, startKg: 28, targetKg: 15, startDate: now)),
          contains('40 %'));
      expect(DietPlan.validate(DietPlan(petId: 1, startKg: 28, targetKg: 25, startDate: now,
          weeklyRate: 0.03)), contains('1 et 2 %'));
    });

    HealthRecord weigh(int pet, DateTime d, double kg) =>
        HealthRecord(petId: pet, type: HealthType.consultation, date: d, weightKg: kg);

    test('suivi : pesées, rythme mesuré et position sur la courbe', () {
      final p = FeedingInsights.diet(plan, Species.dog, [
        weigh(rexId, DateTime(2026, 8, 20), 28.4), // avant le programme
        weigh(rexId, DateTime(2026, 9, 15), 27.5),
        weigh(rexId, DateTime(2026, 10, 1), 27.1),
        weigh(miaId, DateTime(2026, 10, 1), 6),
      ]);
      expect(p.weights.map((w) => w.kg), [28, 27.5, 27.1]);
      expect(p.weeklyLoss, closeTo(0.4 / 27.5 / (16 / 7), 1e-9));
      expect(p.tooFast, isFalse);
      expect(p.pace, DietPace.behind, reason: 'prévu ≈ 26,4 kg au 1er octobre');
      expect(p.progress, closeTo(0.3, 0.001));
      expect(FeedingInsights.dietWarning('Rex', p), isNull);

      final reached = FeedingInsights.diet(plan, Species.dog, [weigh(rexId, DateTime(2026, 11, 20), 24.9)]);
      expect(reached.pace, DietPace.reached);
    });

    test('chat : perte de plus de 2 % par semaine = alerte lipidose', () {
      final cat = DietPlan(petId: miaId, startKg: 6, targetKg: 5, startDate: DateTime(2026, 10, 1));
      final p = FeedingInsights.diet(cat, Species.cat, [weigh(miaId, DateTime(2026, 10, 15), 5.6)]);
      expect(p.weeklyLoss, closeTo(0.4 / 6 / 2, 1e-9), reason: '3,3 % par semaine');
      expect(p.tooFast, isTrue);
      expect(FeedingInsights.dietWarning('Mia', p), allOf(contains('Mia perd 3,3 %'), contains('lipidose')));
    });

    test('ration calculée sur le poids cible', () {
      final normal = Nutrition.ration(pet: rex, feeding: const [], activities: const [], now: now)!;
      final diet =
          Nutrition.ration(pet: rex, feeding: const [], activities: const [], now: now, targetKg: 25)!;
      expect(diet.restingKcal, closeTo(Nutrition.restingKcal(25), 1e-9));
      expect(diet.dailyKcal, lessThan(normal.dailyKcal));
      expect(diet.factorLabel, contains('poids cible de 25 kg'));
    });
  });

  group('budget', () {
    test('projection de fin de mois et plafond', () {
      final b = FeedingInsights.budget(spent: 5, month: DateTime(2026, 11), now: now, cap: 15);
      expect(b.projected, closeTo(18.75, 1e-9), reason: '5 DT ÷ 8 jours × 30 jours');
      expect((b.exceeded, b.willExceed), (false, true));
      expect(FeedingInsights.budget(spent: 20, month: DateTime(2026, 11), now: now, cap: 15).exceeded,
          isTrue);
      expect(FeedingInsights.projection(12, DateTime(2026, 10), now), 12, reason: 'mois terminé');
    });

    test('plafonds par animal et pour tous ; animaux supprimés retirés', () {
      final plan = FeedingPlan(
        budget: const FoodBudget().withCap(null, 60).withCap(rexId, 40).withCap(miaId, 20),
        bags: [
          FoodBag(id: 1, petIds: [rexId, miaId], foodType: FoodType.kibble, weightG: 1000,
              price: 0, openedOn: now),
          FoodBag(id: 2, petIds: [miaId], foodType: FoodType.wet, weightG: 1000, price: 0,
              openedOn: now),
        ],
        diets: {miaId: DietPlan(petId: miaId, startKg: 6, targetKg: 5, startDate: now)},
      );
      expect((plan.budget.capFor(null), plan.budget.capFor(rexId)), (60, 40));
      final json = FeedingPlan.fromJson(plan.toJson());
      expect(json.budget.capFor(miaId), 20);
      expect(json.bags.map((b) => b.petIds), [[rexId, miaId], [miaId]]);
      final kept = plan.only({rexId});
      expect(kept.bags.map((b) => b.petIds), [[rexId]]);
      expect(kept.diets, isEmpty);
      expect(kept.budget.capFor(miaId), isNull);
    });
  });

  test('controller : rappel « Racheter » créé, déplacé, puis supprimé', () async {
    final clock = FakeClock(now);
    final db = memoryDatabase();
    addTearDown(db.close);
    final feedingRepo = SqliteFeedingRepository(db, clock: clock.call);
    final feeding = FeedingModel(clock: clock.call);
    final feedingCtrl =
        FeedingController(model: feeding, repository: feedingRepo, pets: const DemoPetDirectory());
    final reminders = RemindersController(
      model: RemindersModel(clock: clock.call),
      repository: SqliteReminderRepository(db, clock: clock.call),
      notifier: FakeNotifier(),
      pets: const DemoPetDirectory(),
      refreshEvery: null,
    );
    addTearDown(reminders.dispose);
    final store = MemoryFeedingPlanStore();
    final plan = FeedingPlanController(
      model: FeedingPlanModel(),
      planStore: store,
      petList: () => feeding.pets,
      feedingRecords: () => feeding.all,
      reminders: reminders,
      clock: clock.call,
    );
    feedingCtrl.onRecordsChanged = plan.syncRestock;
    await feedingCtrl.load();
    await reminders.load();
    await plan.load();

    for (var d = 1; d <= 8; d++) {
      await feedingRepo.create(meal(rexId, d, 400));
    }
    await feedingCtrl.load();
    final bag = await plan.saveBag(FoodBag(
        id: 0, petIds: [rexId], foodType: FoodType.kibble, weightG: 6000, price: 45,
        openedOn: DateTime(2026, 11, 1)));
    expect(bag.id, 1);
    expect(store.plan.bags.single.weightG, 6000, reason: 'enregistré');

    Reminder? restock() => reminders.model.all
        .where((r) => r.source == ReminderSource.feeding && r.sourceId == bag.id)
        .firstOrNull;
    // 6 kg − 3,2 kg = 2,8 kg à 400 g/j : vide le 15, rappel le 12 à 9 h.
    expect(restock()!.dueDate, DateTime(2026, 11, 12, 9));
    expect(restock()!.type, ReminderType.purchase);
    expect(restock()!.title, 'Racheter : croquettes (Rex)');
    expect(restock()!.petId, rexId);

    // Un gros repas : le rappel avance.
    await feedingCtrl.save(meal(rexId, 8, 1600));
    expect(restock()!.dueDate, DateTime(2026, 11, 8, 9));

    await plan.removeBag(bag);
    expect(restock(), isNull);
    expect(store.plan.bags, isEmpty);
    expect(() => plan.saveBag(bag.withPets([])), throwsA(isA<RecordException>()));
  });

  testWidgets('écran : budget, sac ouvert et programme de perte de poids', (tester) async {
    tester.view.physicalSize = const Size(412, 2600) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = FakeClock(now);
    final db = syncMemoryDatabase();
    addTearDown(db.close);
    final repo = SqliteFeedingRepository(db, clock: clock.call);
    for (var d = 1; d <= 8; d++) {
      await repo.create(meal(rexId, d, 400, price: 2.5));
    }
    final model = FeedingModel(clock: clock.call);
    final ctrl = FeedingController(model: model, repository: repo, pets: const _Pets([rex, mia]));
    await ctrl.load();
    final nutrition = NutritionModel();
    final planModel = FeedingPlanModel();
    final planCtrl = FeedingPlanController(
        model: planModel,
        planStore: MemoryFeedingPlanStore(),
        petList: () => model.pets,
        feedingRecords: () => model.all,
        clock: clock.call);
    await planCtrl.load();
    final health = HealthModel(clock: clock.call)
      ..setRecords([
        HealthRecord(petId: rexId, type: HealthType.consultation, date: DateTime(2026, 11, 8),
            weightKg: 28),
      ]);

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider.value(value: ctrl),
        ChangeNotifierProvider.value(value: model),
        ChangeNotifierProvider.value(value: ActivitiesModel(clock: clock.call)),
        ChangeNotifierProvider.value(value: nutrition),
        Provider.value(
            value: NutritionController(
                model: nutrition, scheduleStore: MemoryMealScheduleStore(), petList: () => model.pets)),
        ChangeNotifierProvider.value(value: planModel),
        Provider.value(value: planCtrl),
        ChangeNotifierProvider.value(value: health),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const FeedingScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    // Budget : 20 DT en 8 jours → environ 75 DT en fin de mois.
    expect(find.text('Budget alimentaire'), findsOneWidget);
    expect(find.text('Vous finirez le mois à environ 75,00 DT'), findsOneWidget);
    await tester.tap(find.byTooltip('Définir un plafond'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Montant'), '50');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('20,00 DT sur 50,00 DT'), findsOneWidget);
    expect(find.textContaining('le plafond sera dépassé d\'environ 25,00 DT'), findsOneWidget);

    // Ouvrir un sac de 4 kg le 1er novembre pour Rex : il reste 800 g.
    await tester.tap(find.text('Ouvrir un sac'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Poids du sac'), '4');
    await tester.tap(find.text('Ouvert le'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Sac enregistré'), findsOneWidget);
    expect(find.textContaining('Reste 800 g sur 4 kg'), findsOneWidget);
    expect(find.text('Sac de Rex vide dans environ 2 jours.'), findsOneWidget);

    // Programme de perte de poids de Rex : 28 → 25 kg.
    await tester.tap(find.text('Rex').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Démarrer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Poids cible'), '25');
    await tester.pumpAndSettle();
    expect(find.textContaining('Environ 12 semaines'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Démarrer'));
    await tester.pumpAndSettle();
    expect(find.text('Perte de poids : 28 kg → 25 kg'), findsOneWidget);
    expect(find.textContaining('calculé sur le poids cible de 25 kg'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

class _Pets implements PetDirectory {
  const _Pets(this.pets);

  final List<PetSummary> pets;

  @override
  Future<List<PetSummary>> getPets() async => pets;
}
