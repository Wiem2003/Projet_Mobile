import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/controllers/feeding_controller.dart';
import 'package:smart_pet/controllers/nutrition_controller.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/core/theme/app_theme.dart';
import 'package:smart_pet/models/activities_model.dart';
import 'package:smart_pet/models/activity.dart';
import 'package:smart_pet/models/feeding_form_model.dart';
import 'package:smart_pet/models/feeding_model.dart';
import 'package:smart_pet/models/feeding_record.dart';
import 'package:smart_pet/models/health_form_model.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/meal_schedule.dart';
import 'package:smart_pet/models/nutrition.dart';
import 'package:smart_pet/models/pet.dart';
import 'package:smart_pet/models/sqlite_feeding_repository.dart';
import 'package:smart_pet/views/screens/feeding_screen.dart';

import '../reminders/test_helpers.dart';
import 'plan_test_helpers.dart';

/// Repas programmés reçus au lieu de notifications.
class FakeMealNotifier implements MealNotifier {
  List<MealAlarm> alarms = const [];

  @override
  Future<void> syncMeals(List<MealAlarm> a) async => alarms = a;
}

class _Pets implements PetDirectory {
  const _Pets(this.pets);

  final List<PetSummary> pets;

  @override
  Future<List<PetSummary>> getPets() async => pets;
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  final now = DateTime(2026, 11, 6, 14);
  DateTime ago(int days) => DateTime(now.year, now.month, now.day - days, 8);
  final rex = PetSummary(id: 1, name: 'Rex', species: 'Chien', weightKg: 28,
      birthDate: DateTime(2023, 9, 12));
  final mia = PetSummary(id: 2, name: 'Mia', species: 'Chat', weightKg: 3,
      birthDate: DateTime(2026, 7, 1));

  FeedingRecord meal(PetSummary p, int daysAgo, double g,
          {FoodType type = FoodType.kibble, double? kcal}) =>
      FeedingRecord(petId: p.id, date: ago(daysAgo), foodType: type, quantityG: g, price: 1,
          kcalPer100g: kcal);

  group('ration conseillée', () {
    test('besoin au repos et facteur selon la situation', () {
      expect(Nutrition.restingKcal(28), closeTo(852.05, 0.01));
      double? f(Species s, int age, {bool st = false, bool active = false}) =>
          Nutrition.factor(s, ageMonths: age, sterilized: st, active: active)?.$1;
      expect(f(Species.dog, 36), 1.6);
      expect(f(Species.dog, 36, st: true), 1.4);
      expect(f(Species.dog, 2), 3.0);
      expect(f(Species.dog, 8), 2.0);
      expect(f(Species.cat, 36), 1.2);
      expect(f(Species.cat, 36, st: true), 1.0);
      expect(f(Species.dog, 36, active: true), closeTo(1.8, 1e-9));
      expect(Nutrition.factor(Species.dog, ageMonths: 36, sterilized: false, active: true)!.$2,
          'chien adulte, actif cette semaine');
      expect(f(Species.bird, 12), isNull);
    });

    test('« Rex mange 454 g par jour, la ration conseillée est de 359 g (+27 %) »', () {
      final feeding = [for (var d = 0; d < 10; d++) meal(rex, d, 454, kcal: 380)];
      final a = Nutrition.ration(pet: rex, feeding: feeding, activities: const [], now: now)!;
      expect(a.dailyKcal, closeTo(1363.3, 0.1));
      expect(a.recommendedGrams, closeTo(358.8, 0.5));
      expect(a.kcalEstimated, isFalse);
      expect(Nutrition.rationSentence('Rex', a),
          'Rex mange 454 g par jour, la ration conseillée est de 359 g (+27 %).');
      expect(Nutrition.kcal(a.dailyKcal), '1 363 kcal');
    });

    test('calories typiques si non saisies ; activité ; sans poids', () {
      final a = Nutrition.ration(
        pet: rex,
        feeding: [meal(rex, 1, 300)],
        activities: [Activity(petId: 1, date: ago(2), type: ActivityType.walk, durationMin: 640)],
        now: now,
      )!;
      expect((a.kcalPer100g, a.kcalEstimated), (370, true));
      expect(a.factor, closeTo(1.8, 1e-9), reason: "objectif d'activité atteint");
      expect(Nutrition.ration(
              pet: const PetSummary(id: 9, name: 'X', species: 'Chien'),
              feeding: const [], activities: const [], now: now),
          isNull);
    });
  });

  test('friandises : plus de 10 % des calories de la semaine', () {
    final feeding = [
      for (var d = 0; d < 7; d++) ...[
        meal(mia, d, 85, type: FoodType.wet),
        meal(mia, d, 10, type: FoodType.treats),
      ],
    ];
    final t = Nutrition.treats(mia.id, feeding, now)!;
    expect(Nutrition.percent(t.share), '31 %');
    expect(t.tooMuch, isTrue);
    expect(Nutrition.treats(mia.id, [meal(mia, 0, 85, type: FoodType.wet)], now)!.tooMuch, isFalse);
    expect(Nutrition.treats(rex.id, feeding, now), isNull);
    expect(Nutrition.kcalOf(meal(mia, 0, 100, type: FoodType.treats)), 350);
  });

  test('baisse d\'appétit : 7 derniers jours par rapport aux 30 précédents', () {
    final before = [for (var d = 8; d < 18; d++) meal(mia, d, 100, type: FoodType.wet)];
    final drop = Nutrition.appetite(mia.id, [
      ...before,
      for (var d = 0; d < 5; d++) meal(mia, d, 65, type: FoodType.wet),
    ], now)!;
    expect(drop.change, closeTo(-0.35, 1e-9));
    expect(Nutrition.appetiteSentence('Mia', drop),
        'Mia mange 35 % de moins depuis une semaine (65 g par jour au lieu de 100 g) : '
        'surveillez son état ou consultez.');
    // Deux jours saisis seulement cette semaine : pas d'alerte (oubli possible).
    expect(Nutrition.appetite(mia.id, [...before, meal(mia, 0, 10), meal(mia, 1, 10)], now), isNull);
    expect(Nutrition.appetite(mia.id, [...before, for (var d = 0; d < 5; d++) meal(mia, d, 90)], now),
        isNull, reason: '−10 %');
  });

  test('nombre de repas selon l\'âge, avertissement du formulaire', () {
    expect(Nutrition.meals(Species.cat, 4)!.range, '3 à 4 repas');
    expect(Nutrition.meals(Species.cat, 30)!.range, '2 repas');
    expect(Nutrition.meals(Species.dog, 100)!.stage, 'senior, en plus petits repas');
    expect(Nutrition.meals(Species.rabbit, 30), isNull);
    expect(Nutrition.mealsWarning(mia, 2, now),
        'Conseil pour Mia (chaton de 4 mois) : 3 à 4 repas par jour.');
    expect(Nutrition.mealsWarning(mia, 3, now), isNull);
    final form = FeedingFormModel(clock: () => now, pets: [mia], defaultPetId: 2)..meals = 1;
    expect(form.mealsWarning, contains('3 à 4 repas'));
    form
      ..quantity = '100'
      ..price = '1'
      ..kcal = '1000';
    expect(form.validate(), 'Entre 1 et 900 kcal pour 100 g');
    form.kcal = '';
    expect(form.mealKcal, 370, reason: 'valeur typique des croquettes');
  });

  test('dossier Santé pré-rempli après une baisse d\'appétit', () {
    final form = HealthFormModel(
      clock: () => now,
      pets: [mia],
      preset: HealthRecord(petId: 2, type: HealthType.consultation, date: now,
          description: 'Baisse d\'appétit'),
    );
    expect((form.isEdit, form.petId, form.description), (false, 2, 'Baisse d\'appétit'));
  });

  group('horaires des repas', () {
    test('liste triée sans doublon, JSON, animaux supprimés retirés', () {
      final s = const MealSchedule()
          .withTime(2, const MealTime(19, 0))
          .withTime(2, const MealTime(7, 30))
          .withTime(2, const MealTime(19, 0));
      expect(s.of(2).map((t) => t.label), ['7 h 30', '19 h']);
      expect(MealSchedule.fromJson(s.toJson()).of(2), s.of(2));
      expect(s.only({1}).of(2), isEmpty);
      expect(MealTime.parse('25:00'), isNull);
    });

    test('base par compte ; notifications quotidiennes ; déconnexion', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final store = SqliteMealScheduleStore(db, ownerId: 1);
      final notifier = FakeMealNotifier();
      final ctrl = NutritionController(
          model: NutritionModel(), scheduleStore: store, petList: () => [rex, mia],
          mealNotifier: notifier);
      await ctrl.load();
      await ctrl.addTime(2, const MealTime(19, 0));
      await ctrl.addTime(1, const MealTime(8, 0));
      expect(notifier.alarms.map((a) => (a.petName, a.time.label)), [('Mia', '19 h'), ('Rex', '8 h')]);
      expect((await store.load()).of(2), [const MealTime(19, 0)]);
      expect((await SqliteMealScheduleStore(db, ownerId: 2).load()).times, isEmpty);
      await ctrl.removeTime(2, const MealTime(19, 0));
      expect(notifier.alarms.single.petName, 'Rex');
      await ctrl.close();
      expect(notifier.alarms, isEmpty);
    });
  });

  testWidgets('écran Alimentation : nutrition de Mia, alerte, horaire ajouté', (tester) async {
    tester.view.physicalSize = const Size(412, 2000) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = FakeClock(now);
    final db = syncMemoryDatabase();
    addTearDown(db.close);
    final repo = SqliteFeedingRepository(db, clock: clock.call);
    // Mia : appétit en baisse et beaucoup de friandises.
    await repo.createAll([
      for (var d = 8; d < 18; d++) meal(mia, d, 100, type: FoodType.wet, kcal: 90),
      for (var d = 0; d < 5; d++) ...[
        meal(mia, d, 50, type: FoodType.wet, kcal: 90),
        meal(mia, d, 15, type: FoodType.treats),
      ],
    ]);
    final model = FeedingModel(clock: clock.call);
    final ctrl = FeedingController(model: model, repository: repo, pets: _Pets([rex, mia]));
    await ctrl.load();
    final nutrition = NutritionModel();
    final notifier = FakeMealNotifier();
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider.value(value: ctrl),
        ChangeNotifierProvider.value(value: model),
        ChangeNotifierProvider.value(value: ActivitiesModel(clock: clock.call)),
        ChangeNotifierProvider.value(value: nutrition),
        Provider.value(
            value: NutritionController(
                model: nutrition, scheduleStore: MemoryMealScheduleStore(),
                petList: () => model.pets, mealNotifier: notifier)),
        ...feedingPlanProviders(model),
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
    // Vue « Tous » : seulement les alertes.
    expect(find.text('Nutrition'), findsOneWidget);
    // Friandises : 52,5 kcal sur 97,5 par jour.
    expect(find.textContaining('Mia : 54 % de ses calories en friandises'), findsOneWidget);
    expect(find.textContaining('Mia mange 35 % de moins'), findsOneWidget);
    expect(find.text('Créer un dossier Santé'), findsOneWidget);

    await tester.tap(find.text('Mia').first);
    await tester.pumpAndSettle();
    expect(find.text('Nutrition de Mia'), findsOneWidget);
    expect(find.textContaining('Ration conseillée').evaluate().isNotEmpty ||
        find.textContaining('la ration conseillée est de').evaluate().isNotEmpty, isTrue);
    expect(find.textContaining('chaton'), findsOneWidget);

    await tester.tap(find.text('Ajouter un horaire'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('19 h'), findsOneWidget);
    expect(notifier.alarms.single.petName, 'Mia');
    await tester.tap(find.byTooltip('Retirer 19 h'));
    await tester.pumpAndSettle();
    expect(notifier.alarms, isEmpty);
  });
}
