import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'controllers/auth_controller.dart';
import 'controllers/user_session.dart';
import 'core/database/app_database.dart';
import 'models/assistant/gemini_client.dart';
import 'models/auth/auth_model.dart';
import 'models/auth/reset_mailer.dart';
import 'models/auth/sqlite_user_repository.dart';
import 'models/gps/location_source.dart';
import 'models/notifications/local_notification_service.dart';
import 'models/pet_photo_store.dart';

/// Clé et modèle Gemini, lus à la compilation depuis `env.json` (fichier
/// local ignoré par Git) : `flutter run --dart-define-from-file=env.json`.
/// Sans clé, l'assistant fonctionne hors ligne.
const _geminiKey = String.fromEnvironment('GEMINI_API_KEY');
const _geminiModel = String.fromEnvironment('GEMINI_MODEL');

/// Mot de passe oublié : le code est envoyé par Gmail depuis
/// [_resetSender], avec un mot de passe d'application Google lu dans
/// `env.json` (`GMAIL_APP_PASSWORD`). Sans lui, en debug, le code est
/// affiché à l'écran.
const _resetSender = String.fromEnvironment('RESET_MAIL_SENDER',
    defaultValue: 'souhirzitoun2003@gmail.com');
const _gmailAppPassword = String.fromEnvironment('GMAIL_APP_PASSWORD');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  Intl.defaultLocale = 'fr_FR';

  // Base SQLite locale partagée par tous les modules et par les comptes.
  final database = AppDatabase();
  final notifications = LocalNotificationService();
  await notifications.init();
  final photos = DevicePetPhotoStore();
  // Photos de profil des comptes, dans un dossier séparé.
  final userPhotos = DevicePetPhotoStore(folder: DevicePetPhotoStore.userFolder);

  // Comptes : Sign up / Sign in, rôles admin et user.
  final users = SqliteUserRepository(database);
  final authModel = AuthModel();
  final authController = AuthController(
    model: authModel,
    repository: users,
    photos: userPhotos,
    mailer: GmailResetMailer(sender: _resetSender, appPassword: _gmailAppPassword),
  );

  final LlmClient? gemini = _geminiKey.isEmpty
      ? null
      : GeminiClient(key: _geminiKey, models: GeminiClient.modelsFrom(_geminiModel));

  // Notification touchée pour ouvrir l'app : traitée une seule fois, après
  // la connexion.
  var launch = notifications.launchEvent;

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: database),
        Provider<LlmClient?>.value(value: gemini),
        Provider<LocationSource>.value(value: const GeolocatorLocationSource()),
        Provider.value(value: authController),
        ChangeNotifierProvider.value(value: authModel),
      ],
      // MVC : à chaque connexion, la session crée les Controllers et Models
      // des cinq modules, limités aux données du compte connecté.
      child: SmartPetApp(
        sessionFactory: (user) => UserSession(
          user: user,
          database: database,
          users: users,
          notifier: notifications,
          mealNotifier: notifications,
          achievementNotifier: notifications,
          notificationEvents: notifications.events,
          photos: photos,
          userPhotos: userPhotos,
          llm: gemini,
        ),
        onSessionStarted: (session) async {
          final event = launch;
          launch = null;
          if (event != null) {
            await session.remindersController.handleNotificationEvent(event);
          }
        },
      ),
    ),
  );

  // Reprend le compte resté connecté.
  await authController.restore();
}
