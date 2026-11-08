import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/app.dart';
import 'package:smart_pet/controllers/auth_controller.dart';
import 'package:smart_pet/controllers/user_session.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/models/auth/auth_model.dart';
import 'package:smart_pet/models/auth/captcha.dart';
import 'package:smart_pet/models/auth/password_hasher.dart';
import 'package:smart_pet/models/auth/sqlite_user_repository.dart';
import 'package:smart_pet/models/gps/location_source.dart';
import 'package:smart_pet/models/pet.dart';
import 'package:smart_pet/models/sqlite_pet_repository.dart';

import '../reminders/test_helpers.dart';

/// Parcours complet : Sign up, accueil, compte, Sign out, Sign in,
/// administration.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  Future<({SqliteUserRepository users, FakeNotifier notifier, AppDatabase db})> pump(
      WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 1000) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = FakeClock(DateTime(2026, 11, 5, 10));
    final db = syncMemoryDatabase();
    addTearDown(db.close);
    final users = SqliteUserRepository(db,
        clock: clock.call, hasher: PasswordHasher(iterations: 1));
    final notifier = FakeNotifier();
    final authModel = AuthModel();
    final auth = AuthController(model: authModel, repository: users);

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<LocationSource>.value(value: FakeLocationSource()),
        Provider.value(value: CaptchaGenerator.fixed(testCaptcha)),
        Provider.value(value: auth),
        ChangeNotifierProvider.value(value: authModel),
      ],
      child: SmartPetApp(
        sessionFactory: (user) => UserSession(
          user: user,
          database: db,
          users: users,
          notifier: notifier,
          photos: FakePhotoStore(),
          clock: clock.call,
          refreshEvery: null,
        ),
      ),
    ));
    await auth.restore();
    await tester.pumpAndSettle();
    return (users: users, notifier: notifier, db: db);
  }

  Future<void> fill(WidgetTester tester, String label, String text) =>
      tester.enterText(find.widgetWithText(TextFormField, label), text);

  Future<void> signUp(WidgetTester tester, String name, String email) async {
    await tester.tap(find.text('Créer un compte'));
    await tester.pumpAndSettle();
    await fill(tester, 'Nom', name);
    await fill(tester, 'E-mail', email);
    await fill(tester, 'Mot de passe', 'Secret123');
    await fill(tester, 'Confirmer le mot de passe', 'Secret123');
    await solveCaptcha(tester);
    await tester.ensureVisible(find.text('Créer mon compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer mon compte'));
    await tester.pumpAndSettle();
  }

  Future<void> signOut(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Mon compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Se déconnecter'));
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester, String email, String password) async {
    await fill(tester, 'E-mail', email);
    await fill(tester, 'Mot de passe', password);
    await solveCaptcha(tester);
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
  }

  testWidgets('sign up : contrôles de saisie puis premier compte admin',
      (tester) async {
    await pump(tester);
    expect(find.text('Connexion'), findsOneWidget);

    await tester.tap(find.text('Créer un compte'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Créer mon compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer mon compte'));
    await tester.pumpAndSettle();
    expect(find.text('Le nom est obligatoire'), findsOneWidget);
    expect(find.text("L'adresse e-mail est obligatoire"), findsOneWidget);
    await fill(tester, 'Mot de passe', 'abc');
    await fill(tester, 'Confirmer le mot de passe', 'abd');
    await tester.pumpAndSettle();
    expect(find.text('Au moins 8 caractères'), findsOneWidget);
    expect(find.text('Les mots de passe ne correspondent pas'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await signUp(tester, 'Sofien Zitoun', 'sofien@gmail.com');
    expect(find.text('Bonjour Sofien ! Voici le résumé de vos animaux'), findsOneWidget);
    expect(find.text('Administration'), findsOneWidget, reason: 'premier compte = admin');

    await tester.tap(find.byTooltip('Mon compte'));
    await tester.pumpAndSettle();
    expect(find.text('sofien@gmail.com'), findsOneWidget);
    expect(find.text('Administrateur'), findsOneWidget);
  });

  testWidgets('chaque compte a ses animaux ; un utilisateur n\'a pas '
      'l\'administration', (tester) async {
    final (:users, :notifier, :db) = await pump(tester);
    await signUp(tester, 'Sofien', 'sofien@gmail.com');
    final sofien = (await users.getAll()).single.user;
    await SqlitePetRepository(db, ownerId: sofien.id)
        .create(Pet(name: 'Rex', species: Species.dog));
    await signOut(tester);
    expect(find.text('Connexion'), findsOneWidget);
    expect(notifier.lastSync, isEmpty, reason: 'notifications du compte annulées');

    await signUp(tester, 'Amina', 'amina@gmail.com');
    expect(find.text('Bonjour Amina ! Voici le résumé de vos animaux'), findsOneWidget);
    expect(find.text('Administration'), findsNothing);
    expect(find.text('Rex'), findsNothing, reason: 'animal de Sofien');
    await tester.tap(find.byTooltip('Mon compte'));
    await tester.pumpAndSettle();
    expect(find.text('Utilisateur'), findsOneWidget);
  });

  testWidgets('sign in : erreur affichée, puis administration des comptes',
      (tester) async {
    final (:users, notifier: _, db: _) = await pump(tester);
    await users.signUp(name: 'Sofien', email: 'sofien@gmail.com', password: 'Secret123');
    await users.signUp(name: 'Amina', email: 'amina@gmail.com', password: 'Secret123');

    await signIn(tester, 'sofien@gmail.com', 'Mauvais99');
    expect(find.text(SqliteUserRepository.badCredentials), findsOneWidget);
    await signIn(tester, 'sofien@gmail.com', 'Secret123');
    expect(find.text('Bonjour Sofien ! Voici le résumé de vos animaux'), findsOneWidget);

    await tester.tap(find.text('Administration'));
    await tester.pumpAndSettle();
    expect(find.text('Sofien (vous)'), findsOneWidget);
    expect(find.text('amina@gmail.com'), findsOneWidget);
    expect(find.byTooltip('Actions'), findsOneWidget, reason: 'pas sur son propre compte');

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nommer administrateur'));
    await tester.pumpAndSettle();
    expect(find.text('Amina est maintenant administrateur'), findsOneWidget);
    expect(find.text('Administrateur'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Désactiver'));
    await tester.pumpAndSettle();
    expect(find.text('Désactivé'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Désactivés'));
    await tester.pumpAndSettle();
    expect(find.text('Sofien (vous)'), findsNothing);

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer le compte de Amina ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Compte de Amina supprimé'), findsOneWidget);
    expect((await users.getAll()).map((s) => s.user.name), ['Sofien']);
  });
}
