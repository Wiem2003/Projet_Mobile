import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/controllers/auth_controller.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/models/auth/app_user.dart';
import 'package:smart_pet/models/auth/auth_model.dart';
import 'package:smart_pet/models/auth/password_hasher.dart';
import 'package:smart_pet/models/auth/sqlite_user_repository.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/pet.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/sqlite_health_repository.dart';
import 'package:smart_pet/models/sqlite_pet_repository.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';
import 'package:smart_pet/models/validation.dart';

import '../reminders/test_helpers.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late SqliteUserRepository users;

  setUp(() {
    db = memoryDatabase();
    clock = FakeClock(DateTime(2026, 11, 5, 10));
    users = SqliteUserRepository(db,
        clock: clock.call, hasher: PasswordHasher(iterations: 1));
  });
  tearDown(() => db.close());

  Future<AppUser> signUp(String name, String email, [String pw = 'Secret123']) =>
      users.signUp(name: name, email: email, password: pw);

  Matcher fails(String message) => throwsA(
      isA<RecordException>().having((e) => e.message, 'message', contains(message)));

  group('mot de passe', () {
    test('empreinte salée, jamais le mot de passe en clair', () {
      final h = PasswordHasher(iterations: 10);
      final a = h.hash('Secret123'), b = h.hash('Secret123');
      expect(a, isNot(contains('Secret123')));
      expect(a, isNot(b), reason: 'sel différent à chaque fois');
      expect(h.verify('Secret123', a), isTrue);
      expect(h.verify('secret123', a), isFalse);
      expect(h.verify('Secret123', 'n\'importe quoi'), isFalse);
    });

    test('règles de saisie', () {
      expect(InputRules.password('court1'), contains('8 caractères'));
      expect(InputRules.password('motdepasse'), contains('un chiffre'));
      expect(InputRules.password('12345678'), contains('une lettre'));
      expect(InputRules.password('Secret123'), isNull);
      expect(InputRules.email('sofien@'), 'Adresse e-mail invalide');
      expect(InputRules.email(' sofien@gmail.com '), isNull);
    });
  });

  group('Sign up', () {
    test('le premier compte est admin, les suivants sont utilisateurs', () async {
      final first = await signUp('Sofien Zitoun', 'Sofien@Gmail.com');
      final second = await signUp('Amina', 'amina@gmail.com');
      expect((first.role, first.email, first.initials),
          (UserRole.admin, 'sofien@gmail.com', 'SZ'));
      expect(second.role, UserRole.user);
      expect(second.isAdmin, isFalse);
    });

    test('e-mail déjà utilisé (sans tenir compte de la casse), saisie invalide',
        () async {
      await signUp('Sofien', 'sofien@gmail.com');
      expect(signUp('Autre', 'SOFIEN@gmail.com'), fails('existe déjà'));
      expect(signUp('', 'a@b.tn'), fails('Le nom est obligatoire'));
      expect(signUp('Ali', 'pas-un-mail'), fails('Adresse e-mail invalide'));
      expect(signUp('Ali', 'ali@b.tn', 'abc'), fails('8 caractères'));
    });

    test('le premier compte récupère les données saisies avant les comptes',
        () async {
      final pets = SqlitePetRepository(db, clock: clock.call);
      final rex = await pets.create(Pet(name: 'Rex', species: Species.dog));
      await SqliteReminderRepository(db, clock: clock.call).create(Reminder(
          title: 'Acheter des croquettes',
          type: ReminderType.purchase,
          dueDate: DateTime(2026, 11, 8)));
      final admin = await signUp('Sofien', 'sofien@gmail.com');
      final mine = SqlitePetRepository(db, ownerId: admin.id);
      expect((await mine.getAll()).single.id, rex.id);
      expect(await SqliteReminderRepository(db, ownerId: admin.id).getAll(),
          hasLength(1));
      // Le deuxième compte part de zéro.
      final amina = await signUp('Amina', 'amina@gmail.com');
      expect(await SqlitePetRepository(db, ownerId: amina.id).getAll(), isEmpty);
    });
  });

  group('Sign in', () {
    setUp(() => signUp('Sofien', 'sofien@gmail.com'));

    test('identifiants corrects, e-mail en majuscules accepté', () async {
      clock.now = DateTime(2026, 11, 6, 8);
      final u = await users.signIn(email: ' SOFIEN@gmail.com', password: 'Secret123');
      expect(u.lastLoginAt, DateTime(2026, 11, 6, 8));
    });

    test('même message pour un e-mail inconnu et un mauvais mot de passe',
        () async {
      expect(users.signIn(email: 'sofien@gmail.com', password: 'Faux1234'),
          fails(SqliteUserRepository.badCredentials));
      expect(users.signIn(email: 'inconnu@gmail.com', password: 'Secret123'),
          fails(SqliteUserRepository.badCredentials));
      expect(users.signIn(email: '', password: ''), fails('Indiquez'));
    });

    test('blocage temporaire après 5 essais ratés', () async {
      for (var i = 0; i < 5; i++) {
        await expectLater(
            users.signIn(email: 'sofien@gmail.com', password: 'Faux1234'),
            throwsA(isA<RecordException>()));
      }
      expect(users.signIn(email: 'sofien@gmail.com', password: 'Secret123'),
          fails('Réessayez dans 5 minutes'));
      clock.now = clock.now.add(const Duration(minutes: 6));
      expect((await users.signIn(email: 'sofien@gmail.com', password: 'Secret123')).name,
          'Sofien');
    });

    test('session gardée sur le téléphone', () async {
      expect(await users.sessionUserId(), isNull);
      await users.saveSession(1);
      expect(await users.sessionUserId(), 1);
      await users.clearSession();
      expect(await users.sessionUserId(), isNull);
    });

    test('changer le nom et le mot de passe', () async {
      final u = (await users.getAll()).single.user;
      expect((await users.updateName(u.id, 'Sofien Z.')).name, 'Sofien Z.');
      expect(users.updateName(u.id, '!!!'), fails('au moins une lettre'));
      expect(users.changePassword(u.id, current: 'Faux1234', next: 'Nouveau123'),
          fails('actuel incorrect'));
      expect(users.changePassword(u.id, current: 'Secret123', next: 'Secret123'),
          fails('différent'));
      await users.changePassword(u.id, current: 'Secret123', next: 'Nouveau123');
      expect(users.signIn(email: 'sofien@gmail.com', password: 'Secret123'),
          fails(SqliteUserRepository.badCredentials));
      expect((await users.signIn(email: 'sofien@gmail.com', password: 'Nouveau123')).id,
          u.id);
    });
  });

  group('administration', () {
    late AppUser admin, amina;

    setUp(() async {
      admin = await signUp('Sofien', 'sofien@gmail.com');
      amina = await signUp('Amina', 'amina@gmail.com');
    });

    test('rôle et activation ; un compte désactivé ne se connecte plus',
        () async {
      expect((await users.setRole(amina.id, UserRole.admin, actorId: admin.id)).isAdmin,
          isTrue);
      expect((await users.setActive(amina.id, false, actorId: admin.id)).active, isFalse);
      expect(users.signIn(email: 'amina@gmail.com', password: 'Secret123'),
          fails('désactivé'));
      await users.setActive(amina.id, true, actorId: admin.id);
      expect((await users.signIn(email: 'amina@gmail.com', password: 'Secret123')).id,
          amina.id);
    });

    test('un admin ne se modifie pas lui-même ; il reste un admin actif',
        () async {
      expect(users.setRole(admin.id, UserRole.user, actorId: admin.id),
          fails('propre compte'));
      await users.setRole(amina.id, UserRole.admin, actorId: admin.id);
      // Amina retire le rôle de Sofien : possible, il reste Amina.
      await users.setRole(admin.id, UserRole.user, actorId: amina.id);
      final third = await signUp('Ali', 'ali@gmail.com');
      await users.setRole(third.id, UserRole.admin, actorId: amina.id);
      await users.setActive(third.id, false, actorId: amina.id);
      // Ali (admin désactivé) ne compte pas : Amina est le dernier admin actif.
      expect(users.setRole(amina.id, UserRole.user, actorId: third.id),
          fails('au moins un administrateur actif'));
    });

    test('supprimer un compte supprime ses animaux et toutes leurs données',
        () async {
      final pets = SqlitePetRepository(db, clock: clock.call, ownerId: amina.id);
      final mia = await pets.create(Pet(name: 'Mia', species: Species.cat));
      await pets.update(mia.copyWith(photoPath: () => '/data/pet_photos/mia.jpg'));
      await SqliteHealthRepository(db, clock: clock.call, ownerId: amina.id).create(
          HealthRecord(petId: mia.id!, type: HealthType.consultation, date: clock.now));
      await SqliteReminderRepository(db, clock: clock.call, ownerId: amina.id).create(
          Reminder(title: 'Vermifuge', type: ReminderType.deworming,
              dueDate: DateTime(2026, 12, 1)));
      final summary = (await users.getAll()).firstWhere((s) => s.user.id == amina.id);
      expect((summary.pets, summary.reminders), (1, 1));
      expect((await users.stats()).users, 2);

      final photos = await users.delete(amina.id, actorId: admin.id);
      expect(photos, ['/data/pet_photos/mia.jpg']);
      final stats = await users.stats();
      expect((stats.users, stats.pets, stats.healthRecords, stats.reminders),
          (1, 0, 0, 0));
    });

    test('AuthController : connexion, erreur affichée, reprise de session',
        () async {
      final model = AuthModel();
      final auth = AuthController(model: model, repository: users);
      await auth.restore();
      expect(model.status, AuthStatus.signedOut);
      expect(await auth.signIn(email: 'amina@gmail.com', password: 'mauvais1'), isFalse);
      expect(model.error, SqliteUserRepository.badCredentials);
      expect(await auth.signIn(email: 'amina@gmail.com', password: 'Secret123'), isTrue);
      expect((model.status, model.user!.id, model.error), (AuthStatus.signedIn, amina.id, null));

      // Relance de l'app : le compte est repris.
      final again = AuthModel();
      await AuthController(model: again, repository: users).restore();
      expect(again.user?.id, amina.id);

      // Désactivé entre-temps : il faut se reconnecter (et c'est refusé).
      await users.setActive(amina.id, false, actorId: admin.id);
      final third = AuthModel();
      await AuthController(model: third, repository: users).restore();
      expect(third.status, AuthStatus.signedOut);

      await auth.signOut();
      expect(model.user, isNull);
      expect(await users.sessionUserId(), isNull);
    });
  });
}
