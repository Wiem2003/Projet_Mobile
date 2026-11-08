import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/controllers/feeding_controller.dart';
import 'package:smart_pet/controllers/nutrition_controller.dart';
import 'package:smart_pet/models/activities_model.dart';
import 'package:smart_pet/models/meal_schedule.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/core/theme/app_theme.dart';
import 'package:smart_pet/models/feeding_model.dart';
import 'package:smart_pet/models/feeding_record.dart';
import 'package:smart_pet/models/sqlite_feeding_repository.dart';
import 'package:smart_pet/views/screens/feeding_screen.dart';

import '../reminders/test_helpers.dart';
import 'plan_test_helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  Future<FeedingModel> pump(WidgetTester tester,
      {bool withRecords = true, Size size = const Size(412, 2000)}) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = FakeClock(DateTime(2026, 11, 3, 14));
    final db = syncMemoryDatabase();
    addTearDown(db.close);
    final repo = SqliteFeedingRepository(db, clock: clock.call);
    final model = FeedingModel(clock: clock.call);
    final ctrl = FeedingController(
        model: model, repository: repo, pets: const DemoPetDirectory());
    if (withRecords) {
      await repo.create(FeedingRecord(
          petId: rexId,
          date: DateTime(2026, 11, 2),
          foodType: FoodType.kibble,
          quantityG: 350,
          price: 2.6,
          meals: 2,
          brand: 'Royal Canin'));
      await repo.create(FeedingRecord(
          petId: miaId,
          date: DateTime(2026, 10, 10),
          foodType: FoodType.wet,
          quantityG: 85,
          price: 1.8,
          brand: 'Felix'));
    }
    await ctrl.load();
    final nutritionModel = NutritionModel();

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider.value(value: ctrl),
        ChangeNotifierProvider.value(value: model),
        ChangeNotifierProvider.value(value: ActivitiesModel(clock: clock.call)),
        ChangeNotifierProvider.value(value: nutritionModel),
        Provider.value(
            value: NutritionController(
                model: nutritionModel,
                scheduleStore: MemoryMealScheduleStore(),
                petList: () => model.pets)),
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
    return model;
  }

  testWidgets('indicateurs, graphique et historique du mois', (tester) async {
    await pump(tester);
    expect(find.text('Alimentation'), findsOneWidget);
    expect(find.text('Novembre 2026'), findsOneWidget);
    expect(find.text('Quantité consommée'), findsOneWidget);
    expect(find.text('350 g'), findsOneWidget);
    expect(find.text('117 g / j'), findsOneWidget, reason: '350 g sur 3 jours');
    expect(find.text('Dépenses mensuelles (DT)'), findsOneWidget);
    expect(find.text('Croquettes · Royal Canin'), findsOneWidget);
    expect(find.text('Pâtée · Felix'), findsNothing);

    await tester.tap(find.byTooltip('Mois précédent'));
    await tester.pumpAndSettle();
    expect(find.text('Octobre 2026'), findsOneWidget);
    expect(find.text('Pâtée · Felix'), findsOneWidget);
    // Novembre commencé : comparé aux mêmes jours d'octobre (le repas du
    // 10 octobre n'en fait pas partie), pas au mois complet.
    await tester.tap(find.byTooltip('Mois suivant'));
    await tester.pumpAndSettle();
    expect(find.text('+44 %'), findsNothing);
    expect(find.textContaining('pas de dépense du 1er au'), findsOneWidget);
  });

  testWidgets('filtre par animal', (tester) async {
    final model = await pump(tester);
    await tester.tap(find.text('Mia'));
    await tester.pumpAndSettle();
    expect(model.petFilter, miaId);
    expect(find.text('Aucun repas ce mois-ci'), findsOneWidget);
    expect(find.text('Charger des exemples'), findsNothing);
  });

  testWidgets('ajouter un repas : validation puis enregistrement',
      (tester) async {
    final model = await pump(tester, size: const Size(412, 2400));
    await tester.tap(find.text('Ajouter un repas'));
    await tester.pumpAndSettle();
    expect(find.text('Reprendre le dernier repas'), findsOneWidget);

    await tester.tap(find.text('Ajouter le repas'));
    await tester.pumpAndSettle();
    expect(find.text('Indiquez la quantité en grammes'), findsOneWidget);
    expect(find.text('Indiquez le prix (0 si gratuit)'), findsOneWidget);

    await tester.tap(find.text('Pâtée'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Ex. 350'), '200');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Prix de cette quantité'), '1,5');
    await tester.pumpAndSettle();
    expect(find.text('7,50 DT / kg'), findsOneWidget);

    await tester.tap(find.text('Ajouter le repas'));
    await tester.pumpAndSettle();
    expect(find.text('Repas ajouté — 200 g, 1,50 DT'), findsOneWidget);
    expect(model.all, hasLength(3));
    expect(find.text('Pâtée'), findsOneWidget);
  });

  testWidgets('reprendre le dernier repas puis modifier et supprimer',
      (tester) async {
    final model = await pump(tester, size: const Size(412, 2400));
    await tester.tap(find.text('Ajouter un repas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reprendre'));
    await tester.pumpAndSettle();
    expect(find.text('2,6'), findsOneWidget);
    expect(find.text('Royal Canin'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Modifier via le tap sur la carte.
    await tester.tap(find.text('Croquettes · Royal Canin'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier le repas'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '350'), '400');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(model.byId(model.all.first.id)!.quantityG, 400);

    // Supprimer via le menu.
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer ce repas ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(model.all, hasLength(1));
    expect(find.text('Repas supprimé'), findsOneWidget);
  });

  testWidgets('écran vide : charger les exemples', (tester) async {
    final model = await pump(tester, withRecords: false);
    expect(find.text('Aucun repas ce mois-ci'), findsOneWidget);
    await tester.tap(find.text('Charger des exemples'));
    await tester.pumpAndSettle();
    expect(model.all, hasLength(396));
    expect(find.text('396 repas d\'exemple ajoutés'), findsOneWidget);
    expect(find.text('Aucun repas ce mois-ci'), findsNothing);
  });

  testWidgets('aucun débordement sur un petit écran (360 dp)', (tester) async {
    final model = await pump(tester, size: const Size(360, 740));
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Charger des exemples'));
    await tester.pumpAndSettle();
    expect(model.history.length, greaterThan(3));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3500));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ajouter un repas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reprendre'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('Prix au kilo (calculé)'), findsOneWidget);
  });

  testWidgets('contrôles de saisie : lettres bloquées, erreur pendant la saisie',
      (tester) async {
    await pump(tester, size: const Size(412, 2400));
    await tester.tap(find.text('Ajouter un repas'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Mia'));
    await tester.pumpAndSettle();

    final quantity = find.widgetWithText(TextFormField, 'Ex. 350');
    await tester.enterText(quantity, 'abc');
    await tester.pumpAndSettle();
    expect(find.text('abc'), findsNothing, reason: 'lettres refusées à la frappe');

    // Mia pèse 4,5 kg : 5 kg de nourriture par jour est une erreur de saisie.
    await tester.enterText(quantity, '5000');
    await tester.pumpAndSettle();
    expect(find.text('Quantité peu plausible pour Mia : 1350 g maximum par jour'),
        findsOneWidget, reason: 'affichée sans appuyer sur Enregistrer');
    await tester.enterText(quantity, '120');
    await tester.pumpAndSettle();
    expect(find.textContaining('peu plausible'), findsNothing);
  });
}
