import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/controllers/activities_controller.dart';
import 'package:smart_pet/controllers/feeding_controller.dart';
import 'package:smart_pet/controllers/health_controller.dart';
import 'package:smart_pet/controllers/pets_controller.dart';
import 'package:smart_pet/controllers/reminders_controller.dart';
import 'package:smart_pet/core/theme/app_theme.dart';
import 'package:smart_pet/models/activities_model.dart';
import 'package:smart_pet/models/auth/auth_model.dart';
import 'package:smart_pet/controllers/dashboard_controller.dart';
import 'package:smart_pet/controllers/health_booklet_controller.dart';
import 'package:smart_pet/controllers/nutrition_controller.dart';
import 'package:smart_pet/models/meal_schedule.dart';
import 'package:smart_pet/models/dashboard/dashboard_model.dart';
import 'package:smart_pet/models/dashboard/dashboard_prefs.dart';
import 'package:smart_pet/models/feeding_model.dart';
import 'package:smart_pet/models/gps/location_source.dart';
import 'package:smart_pet/models/health_model.dart';
import 'package:smart_pet/models/pet_repository.dart';
import 'package:smart_pet/models/pets_model.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminders_model.dart';
import 'package:smart_pet/models/sqlite_activity_repository.dart';
import 'package:smart_pet/models/sqlite_feeding_repository.dart';
import 'package:smart_pet/models/sqlite_health_repository.dart';
import 'package:smart_pet/models/sqlite_pet_repository.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';
import 'package:smart_pet/views/home_shell.dart';

import 'reminders/test_helpers.dart';
import 'feeding/plan_test_helpers.dart';

/// L'application complète, câblée comme dans `main.dart`, sur une base en
/// mémoire : vérifie les liens entre les cinq modules.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets('animaux → santé → rappels, puis suppression en cascade',
      (tester) async {
    tester.view.physicalSize = const Size(412, 1400) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = FakeClock(DateTime(2026, 11, 3, 14));
    final db = syncMemoryDatabase();
    addTearDown(db.close);

    final petRepo = SqlitePetRepository(db, clock: clock.call);
    final pets = PetRepositoryDirectory(petRepo);
    final petsModel = PetsModel(clock: clock.call);
    final petsCtrl = PetsController(
        model: petsModel, repository: petRepo, photos: FakePhotoStore());
    final feedingModel = FeedingModel(clock: clock.call);
    final feedingCtrl = FeedingController(
        model: feedingModel,
        repository: SqliteFeedingRepository(db, clock: clock.call),
        pets: pets);
    final activitiesModel = ActivitiesModel(clock: clock.call);
    final activitiesCtrl = ActivitiesController(
        model: activitiesModel,
        repository: SqliteActivityRepository(db, clock: clock.call),
        pets: pets);
    final remindersModel = RemindersModel(clock: clock.call);
    final remindersCtrl = RemindersController(
        model: remindersModel,
        repository: SqliteReminderRepository(db, clock: clock.call),
        notifier: FakeNotifier(),
        pets: pets,
        refreshEvery: null);
    addTearDown(remindersCtrl.dispose);
    final healthModel = HealthModel(clock: clock.call);
    final healthCtrl = HealthController(
        model: healthModel,
        repository: SqliteHealthRepository(db, clock: clock.call),
        pets: pets,
        reminders: remindersCtrl,
        onWeightMeasured: petsCtrl.updateWeight);
    petsCtrl.onPetsChanged = () async {
      await healthCtrl.load();
      await feedingCtrl.load();
      await activitiesCtrl.load();
      await remindersCtrl.load();
    };
    await petsCtrl.load();
    await petsCtrl.onPetsChanged!();
    final dashboardModel = DashboardModel(clock: clock.call);
    final nutritionModel = NutritionModel();
    final dashboardCtrl = DashboardController(
        model: dashboardModel, prefsStore: MemoryDashboardPrefsStore());

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: AuthModel()),
        Provider.value(value: dashboardCtrl),
        Provider.value(value: HealthBookletController(clock: clock.call)),
        ChangeNotifierProvider.value(value: nutritionModel),
        Provider.value(
            value: NutritionController(
                model: nutritionModel,
                scheduleStore: MemoryMealScheduleStore(),
                petList: () => feedingModel.pets)),
        ...feedingPlanProviders(feedingModel, health: false),
        ChangeNotifierProvider.value(value: dashboardModel),
        Provider<LocationSource>.value(value: FakeLocationSource()),
        Provider.value(value: petsCtrl),
        ChangeNotifierProvider.value(value: petsModel),
        Provider.value(value: healthCtrl),
        ChangeNotifierProvider.value(value: healthModel),
        Provider.value(value: feedingCtrl),
        ChangeNotifierProvider.value(value: feedingModel),
        Provider.value(value: activitiesCtrl),
        ChangeNotifierProvider.value(value: activitiesModel),
        Provider.value(value: remindersCtrl),
        ChangeNotifierProvider.value(value: remindersModel),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const HomeShell(),
      ),
    ));
    await tester.pumpAndSettle();

    // Accueil : « Mes animaux » vide → exemples.
    expect(find.text('Mes animaux'), findsOneWidget);
    await tester.tap(find.text('Voir tout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Charger des exemples'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Rex'), findsWidgets, reason: 'bulle et indice');
    // Les autres modules voient les nouveaux animaux.
    expect(feedingModel.pets.map((p) => p.name), ['Coco', 'Mia', 'Rex']);
    expect(activitiesModel.pets.firstWhere((p) => p.name == 'Rex').weightKg, 28);

    // Santé : les exemples créent des rappels et mettent à jour le poids.
    await tester.tap(find.text('Santé').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Charger des exemples').last); // Menu ouvert.
    await tester.pumpAndSettle();
    final healthReminders =
        remindersModel.all.where((r) => r.source == ReminderSource.health);
    expect(healthReminders, isNotEmpty);
    int idOf(String name) => petsModel.all.firstWhere((p) => p.name == name).id!;
    final rex = idOf('Rex'), coco = idOf('Coco');
    // Les exemples vont au chien et au chat, pas à Coco (premier par nom).
    expect(healthModel.all.where((r) => r.petId == coco), isEmpty);
    expect(petsModel.byId(rex)!.weightKg, 28.1,
        reason: 'la dernière pesée devient le poids de l\'animal');

    // Rappels : les échéances de santé apparaissent dans l'onglet.
    await tester.tap(find.text('Rappels').last);
    await tester.pumpAndSettle();
    expect(find.text('Rappels & alertes'), findsOneWidget);

    // Supprimer un animal efface ses données dans tous les modules.
    await tester.tap(find.text('Accueil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rex').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('dossier(s) de santé'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(petsModel.byId(rex), isNull);
    expect(healthModel.all.where((r) => r.petId == rex), isEmpty);
    expect(healthModel.all, isNotEmpty, reason: 'les dossiers de Mia restent');
    expect(remindersModel.all.where((r) => r.petId == rex), isEmpty);
    expect(healthModel.pets.map((p) => p.name), ['Coco', 'Mia']);
  });
}
