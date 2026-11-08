import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../core/database/app_database.dart';
import '../models/assistant/gemini_client.dart';
import '../models/activities_model.dart';
import '../models/auth/admin_model.dart';
import '../models/auth/app_user.dart';
import '../models/auth/user_repository.dart';
import '../models/dashboard/dashboard_model.dart';
import '../models/dashboard/dashboard_prefs.dart';
import '../models/dashboard/report_sharer.dart';
import '../models/feeding_model.dart';
import '../models/feeding_plan.dart';
import '../models/meal_schedule.dart';
import '../models/notifications/achievement_notifier.dart';
import '../models/health_model.dart';
import '../models/notifications/reminder_notifier.dart';
import '../models/pet_photo_store.dart';
import '../models/pet_repository.dart';
import '../models/pets_model.dart';
import '../models/reminder_repository.dart';
import '../models/reminders_model.dart';
import '../models/sqlite_activity_repository.dart';
import '../models/sqlite_feeding_repository.dart';
import '../models/sqlite_health_repository.dart';
import '../models/sqlite_pet_repository.dart';
import '../models/sqlite_planning_settings_store.dart';
import '../models/sqlite_reminder_repository.dart';
import 'activities_controller.dart';
import 'admin_controller.dart';
import 'dashboard_controller.dart';
import 'health_booklet_controller.dart';
import 'nutrition_controller.dart';
import 'feeding_controller.dart';
import 'feeding_plan_controller.dart';
import 'health_controller.dart';
import 'pets_controller.dart';
import 'reminders_controller.dart';

/// Les cinq modules d'un compte connecté.
///
/// Créée à la connexion et fermée à la déconnexion : chaque utilisateur ne
/// voit que ses animaux et leurs données (repositories filtrés par
/// `ownerId`). Un administrateur a en plus l'écran Administration.
class UserSession {
  UserSession({
    required this.user,
    required AppDatabase database,
    required UserRepository users,
    required ReminderNotifier notifier,
    MealNotifier? mealNotifier,
    AchievementNotifier? achievementNotifier,
    required PetPhotoStore photos,
    PetPhotoStore? userPhotos,
    Stream<ReminderNotificationEvent>? notificationEvents,
    DateTime Function()? clock,
    Duration? refreshEvery = const Duration(minutes: 1),
    ReportSharer reportSharer = const SystemReportSharer(),
    LlmClient? llm,
  }) : _notifier = notifier {
    final owner = user.id;
    // Module 1 : Animaux. Les autres modules lisent les animaux via
    // PetDirectory.
    final petRepository = SqlitePetRepository(database, clock: clock, ownerId: owner);
    final pets = PetRepositoryDirectory(petRepository);
    petsModel = PetsModel(clock: clock);
    petsController = PetsController(
        model: petsModel, repository: petRepository, photos: photos);

    // Module 3 : Alimentation.
    feedingModel = FeedingModel(clock: clock);
    feedingController = FeedingController(
      model: feedingModel,
      repository: SqliteFeedingRepository(database, clock: clock, ownerId: owner),
      pets: pets,
    );

    // Module 4 : Activités.
    activitiesModel = ActivitiesModel(clock: clock);
    activitiesController = ActivitiesController(
      model: activitiesModel,
      repository: SqliteActivityRepository(database, clock: clock, ownerId: owner),
      pets: pets,
      recordNotifier: achievementNotifier,
    );

    final healthRepository =
        SqliteHealthRepository(database, clock: clock, ownerId: owner);

    // Module 5 : Rappels. Le budget lit les coûts des dossiers de santé.
    reminderRepository =
        SqliteReminderRepository(database, clock: clock, ownerId: owner);
    remindersModel = RemindersModel(clock: clock);
    remindersController = RemindersController(
      model: remindersModel,
      repository: reminderRepository,
      notifier: notifier,
      pets: pets,
      notificationEvents: notificationEvents,
      refreshEvery: refreshEvery,
      planning: SqlitePlanningSettingsStore(database, ownerId: owner),
      healthRecords: healthRepository.getAll,
    );

    // Module 2 : Santé. Les prochaines échéances deviennent des rappels et
    // la dernière pesée devient le poids de l'animal.
    healthModel = HealthModel(clock: clock);
    healthController = HealthController(
      model: healthModel,
      repository: healthRepository,
      pets: pets,
      reminders: remindersController,
      onWeightMeasured: petsController.updateWeight,
    );

    // Un animal ajouté, modifié ou supprimé : les autres modules relisent.
    petsController.onPetsChanged = () async {
      await Future.wait([
        healthController.load(),
        feedingController.load(),
        activitiesController.load(),
      ]);
      await remindersController.load();
      await nutritionController.load();
      await feedingPlanController.load();
    };

    // Tableau de bord : indice, alertes croisées, coûts, rapport mensuel.
    dashboardModel = DashboardModel(clock: clock);
    dashboardController = DashboardController(
      model: dashboardModel,
      prefsStore: SqliteDashboardPrefsStore(database, ownerId: owner),
      reportSharer: reportSharer,
    );
    healthBookletController =
        HealthBookletController(reportSharer: reportSharer, clock: clock, llm: llm);

    // Horaires des repas (notifications quotidiennes).
    nutritionModel = NutritionModel();
    nutritionController = NutritionController(
      model: nutritionModel,
      scheduleStore: SqliteMealScheduleStore(database, ownerId: owner),
      petList: () => feedingModel.pets,
      mealNotifier: mealNotifier,
    );

    // Sacs (stock, rappel « Racheter »), perte de poids et budget.
    feedingPlanModel = FeedingPlanModel();
    feedingPlanController = FeedingPlanController(
      model: feedingPlanModel,
      planStore: SqliteFeedingPlanStore(database, ownerId: owner),
      petList: () => feedingModel.pets,
      feedingRecords: () => feedingModel.all,
      reminders: remindersController,
      clock: clock,
    );
    feedingController.onRecordsChanged = feedingPlanController.syncRestock;

    // Administration : rôle admin uniquement.
    if (user.isAdmin) {
      adminModel = AdminModel();
      adminController = AdminController(
          model: adminModel!,
          repository: users,
          adminId: owner,
          photos: photos,
          userPhotos: userPhotos);
    }
  }

  final AppUser user;
  final ReminderNotifier _notifier;

  late final PetsModel petsModel;
  late final PetsController petsController;
  late final HealthModel healthModel;
  late final HealthController healthController;
  late final FeedingModel feedingModel;
  late final FeedingController feedingController;
  late final ActivitiesModel activitiesModel;
  late final ActivitiesController activitiesController;
  late final ReminderRepository reminderRepository;
  late final RemindersModel remindersModel;
  late final RemindersController remindersController;
  late final DashboardModel dashboardModel;
  late final DashboardController dashboardController;
  late final HealthBookletController healthBookletController;
  late final NutritionModel nutritionModel;
  late final NutritionController nutritionController;
  late final FeedingPlanModel feedingPlanModel;
  late final FeedingPlanController feedingPlanController;
  AdminModel? adminModel;
  AdminController? adminController;

  /// Models et Controllers fournis aux écrans (Provider).
  List<SingleChildWidget> get providers => [
        Provider.value(value: petsController),
        ChangeNotifierProvider.value(value: petsModel),
        Provider.value(value: healthController),
        ChangeNotifierProvider.value(value: healthModel),
        Provider.value(value: feedingController),
        ChangeNotifierProvider.value(value: feedingModel),
        Provider.value(value: activitiesController),
        ChangeNotifierProvider.value(value: activitiesModel),
        Provider<ReminderRepository>.value(value: reminderRepository),
        Provider.value(value: remindersController),
        ChangeNotifierProvider.value(value: remindersModel),
        Provider.value(value: dashboardController),
        Provider.value(value: healthBookletController),
        Provider.value(value: nutritionController),
        ChangeNotifierProvider.value(value: nutritionModel),
        Provider.value(value: feedingPlanController),
        ChangeNotifierProvider.value(value: feedingPlanModel),
        ChangeNotifierProvider.value(value: dashboardModel),
        if (adminController != null) ...[
          Provider.value(value: adminController!),
          ChangeNotifierProvider.value(value: adminModel!),
        ],
      ];

  /// Charge les données du compte puis programme ses notifications.
  Future<void> load({ReminderNotificationEvent? launch}) async {
    await petsController.load();
    await Future.wait([
      healthController.load(),
      feedingController.load(),
      activitiesController.load(),
    ]);
    await remindersController.load();
    await dashboardController.load();
    await nutritionController.load();
    await feedingPlanController.load();
    if (launch != null) await remindersController.handleNotificationEvent(launch);
  }

  /// Déconnexion : les notifications du compte sont annulées (le prochain
  /// utilisateur du téléphone ne les reçoit pas).
  Future<void> close() async {
    await nutritionController.close();
    remindersController.dispose();
    await _notifier.syncAll(const []);
  }

  /// Libère les Models, une fois les écrans du compte retirés.
  void dispose() {
    for (final m in [
      petsModel,
      healthModel,
      feedingModel,
      activitiesModel,
      remindersModel,
      dashboardModel,
      nutritionModel,
      feedingPlanModel,
      ?adminModel,
    ]) {
      m.dispose();
    }
  }
}
