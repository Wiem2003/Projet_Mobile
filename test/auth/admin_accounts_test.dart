import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/app.dart';
import 'package:smart_pet/controllers/admin_controller.dart';
import 'package:smart_pet/controllers/auth_controller.dart';
import 'package:smart_pet/controllers/user_session.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/models/auth/admin_model.dart';
import 'package:smart_pet/models/auth/app_user.dart';
import 'package:smart_pet/models/auth/auth_model.dart';
import 'package:smart_pet/models/auth/captcha.dart';
import 'package:smart_pet/models/auth/password_hasher.dart';
import 'package:smart_pet/models/auth/sqlite_user_repository.dart';
import 'package:smart_pet/models/gps/location_source.dart';
import 'package:smart_pet/models/validation.dart';

import '../reminders/test_helpers.dart';

/// L'administrateur crée, modifie et supprime des comptes ; photos de profil.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('repository', () {
    late AppDatabase db;
    late SqliteUserRepository users;
    late AppUser admin, amina;

    setUp(() async {
      db = memoryDatabase();
      users = SqliteUserRepository(db, hasher: PasswordHasher(iterations: 1));
      admin = await users.signUp(name: 'Sofien', email: 'sofien@gmail.com', password: 'Secret123',
          photoPath: '/data/user_photos/sofien.jpg');
      amina = await users.signUp(name: 'Amina', email: 'amina@gmail.com', password: 'Secret123');
    });
    tearDown(() => db.close());

    Matcher fails(String m) =>
        throwsA(isA<RecordException>().having((e) => e.message, 'message', contains(m)));

    test('photo à l\'inscription et changement de photo', () async {
      expect(admin.photoPath, '/data/user_photos/sofien.jpg');
      expect((await users.updatePhoto(amina.id, '/data/user_photos/a.jpg')).photoPath,
          '/data/user_photos/a.jpg');
      expect((await users.updatePhoto(amina.id, null)).photoPath, isNull);
    });

    test('l\'admin crée un compte admin avec photo ; contrôles', () async {
      final ali = await users.createAccount(
          name: 'Ali', email: 'ALI@gmail.com', password: 'Secret123', role: UserRole.admin,
          photoPath: '/data/user_photos/ali.jpg', actorId: admin.id);
      expect((ali.email, ali.role, ali.photoPath), ('ali@gmail.com', UserRole.admin, '/data/user_photos/ali.jpg'));
      expect((await users.signIn(email: 'ali@gmail.com', password: 'Secret123')).id, ali.id);
      expect(users.createAccount(name: 'X', email: 'amina@gmail.com', password: 'Secret123',
          role: UserRole.user, actorId: admin.id), fails('existe déjà'));
      expect(users.createAccount(name: 'X', email: 'x@gmail.com', password: 'court',
          role: UserRole.user, actorId: admin.id), fails('8 caractères'));
      expect(users.createAccount(name: 'X', email: 'x@gmail.com', password: 'Secret123',
          role: UserRole.user, actorId: amina.id), fails('réservée aux administrateurs'));
    });

    test('l\'admin modifie un compte : nom, e-mail, rôle, statut, photo, mot de passe', () async {
      final saved = await users.updateAccount(amina.id,
          name: 'Amina B.', email: 'amina.b@gmail.com', role: UserRole.admin, active: true,
          photoPath: '/data/user_photos/amina.jpg', newPassword: 'Nouveau123', actorId: admin.id);
      expect((saved.name, saved.email, saved.role, saved.photoPath),
          ('Amina B.', 'amina.b@gmail.com', UserRole.admin, '/data/user_photos/amina.jpg'));
      expect((await users.signIn(email: 'amina.b@gmail.com', password: 'Nouveau123')).id, amina.id);

      // Mot de passe vide : inchangé.
      await users.updateAccount(amina.id, name: 'Amina B.', email: 'amina.b@gmail.com',
          role: UserRole.user, active: false, newPassword: '', actorId: admin.id);
      expect(users.signIn(email: 'amina.b@gmail.com', password: 'Nouveau123'), fails('désactivé'));

      expect(users.updateAccount(amina.id, name: 'A', email: 'sofien@gmail.com', role: UserRole.user,
          active: true, actorId: admin.id), fails('existe déjà'));
      expect(users.updateAccount(admin.id, name: 'S', email: 'sofien@gmail.com', role: UserRole.user,
          active: true, actorId: admin.id), fails('propre compte'));
    });

    test('suppression : la photo de profil est rendue pour être effacée', () async {
      await users.updatePhoto(amina.id, '/data/user_photos/amina.jpg');
      expect(await users.delete(amina.id, actorId: admin.id), ['/data/user_photos/amina.jpg']);
    });

    test('Controllers : ancienne photo effacée quand elle est remplacée', () async {
      final photos = FakePhotoStore();
      final auth = AuthController(model: AuthModel()..signedIn(admin), repository: users, photos: photos);
      final path = await auth.pickPhoto(camera: false);
      expect(await auth.setPhoto(path), isNull);
      expect(auth.model.user!.photoPath, path);
      expect(photos.deleted, ['/data/user_photos/sofien.jpg']);

      final admins = AdminController(model: AdminModel(), repository: users, adminId: admin.id,
          photos: FakePhotoStore(), userPhotos: photos);
      await users.updatePhoto(amina.id, '/data/user_photos/old.jpg');
      final current = await users.getById(amina.id);
      await admins.update(current, name: 'Amina', email: 'amina@gmail.com', role: UserRole.user,
          active: true, photoPath: '/data/user_photos/new.jpg');
      expect(photos.deleted, contains('/data/user_photos/old.jpg'));
    });
  });

  testWidgets('écran : photo à l\'inscription, l\'admin crée puis modifie un compte',
      (tester) async {
    tester.view.physicalSize = const Size(412, 1200) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = FakeClock(DateTime(2026, 11, 7, 10));
    final db = syncMemoryDatabase();
    addTearDown(db.close);
    final users = SqliteUserRepository(db, clock: clock.call, hasher: PasswordHasher(iterations: 1));
    final photos = FakePhotoStore();
    final authModel = AuthModel();
    final auth = AuthController(model: authModel, repository: users, photos: photos);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<LocationSource>.value(value: FakeLocationSource()),
        Provider.value(value: CaptchaGenerator.fixed(testCaptcha)),
        Provider.value(value: auth),
        ChangeNotifierProvider.value(value: authModel),
      ],
      child: SmartPetApp(
        sessionFactory: (user) => UserSession(
          user: user, database: db, users: users, notifier: FakeNotifier(),
          photos: FakePhotoStore(), userPhotos: photos, clock: clock.call, refreshEvery: null),
      ),
    ));
    await auth.restore();
    await tester.pumpAndSettle();

    // Inscription avec une photo de la galerie.
    await tester.tap(find.text('Créer un compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galerie'));
    await tester.pumpAndSettle();
    expect(find.text('Retirer'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Nom'), 'Souhir Z');
    await tester.enterText(find.widgetWithText(TextFormField, 'E-mail'), 'souhir@gmail.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Mot de passe'), 'Secret123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirmer le mot de passe'), 'Secret123');
    expect(find.text('Utilisateur'), findsOneWidget, reason: 'choix du rôle');
    await tester.tap(find.text('Administrateur'));
    await tester.pumpAndSettle();
    await solveCaptcha(tester);
    await tester.ensureVisible(find.text('Créer mon compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer mon compte'));
    await tester.pumpAndSettle();
    expect(authModel.user!.photoPath, '/data/pet_photos/photo_1.jpg');
    expect(authModel.user!.role, UserRole.admin);
    expect(photos.deleted, isEmpty, reason: 'photo gardée après l\'inscription');

    // Administration → Ajouter un compte (admin).
    await tester.tap(find.text('Administration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un compte'));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau compte'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Nom'), 'Ali Ben');
    await tester.enterText(find.widgetWithText(TextFormField, 'E-mail'), 'ali@gmail.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Mot de passe'), 'Secret123');
    await tester.tap(find.text('Administrateur').last);
    await tester.tap(find.text('Créer le compte'));
    await tester.pumpAndSettle();
    expect(find.text('Compte administrateur « Ali Ben » créé'), findsOneWidget);
    expect(find.text('ali@gmail.com'), findsOneWidget);

    // Modifier le compte d'Ali : nom et e-mail.
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier le compte'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Ali Ben'), 'Ali B.');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Compte de Ali B. modifié'), findsOneWidget);
    expect(find.text('Ali B.'), findsOneWidget);
    expect(find.textContaining('0 animal ·'), findsNWidgets(2), reason: 'singulier, pour les deux comptes');
  });
}
