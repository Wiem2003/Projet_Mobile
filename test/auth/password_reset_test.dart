import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/controllers/auth_controller.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/models/auth/app_user.dart';
import 'package:smart_pet/models/auth/auth_model.dart';
import 'package:smart_pet/models/auth/captcha.dart';
import 'package:smart_pet/models/auth/password_hasher.dart';
import 'package:smart_pet/models/auth/reset_mailer.dart';
import 'package:smart_pet/models/auth/sqlite_user_repository.dart';
import 'package:smart_pet/models/validation.dart';
import 'package:smart_pet/views/screens/auth_screens.dart';

import '../reminders/test_helpers.dart';

/// E-mails « envoyés » pendant les tests.
class FakeResetMailer implements ResetMailer {
  final sent = <({String to, String code})>[];
  String? failWith;

  @override
  bool configured = true;

  String get lastCode => sent.last.code;

  @override
  Future<void> sendResetCode(
      {required AppUser user, required String code, required DateTime expiresAt}) async {
    if (failWith != null) throw RecordException(failWith!);
    sent.add((to: user.email, code: code));
  }
}

/// Mot de passe oublié : code par e-mail, nouveau mot de passe.
void main() {
  late AppDatabase db;
  late FakeClock clock;
  late SqliteUserRepository users;
  late AppUser sofien;

  setUp(() async {
    db = memoryDatabase();
    clock = FakeClock(DateTime(2026, 11, 8, 10));
    users = SqliteUserRepository(db, clock: clock.call, hasher: PasswordHasher(iterations: 1));
    sofien = await users.signUp(name: 'Sofien', email: 'sofien@gmail.com', password: 'Secret123');
  });
  tearDown(() => db.close());

  Matcher fails(String m) =>
      throwsA(isA<RecordException>().having((e) => e.message, 'message', contains(m)));

  group('repository', () {
    test('code à 6 chiffres, mot de passe changé, code à usage unique', () async {
      final r = (await users.requestPasswordReset(' Sofien@Gmail.com '))!;
      expect(r.user.id, sofien.id);
      expect(r.code, matches(RegExp(r'^\d{6}$')));
      expect(r.expiresAt, DateTime(2026, 11, 8, 10, 15));

      await expectLater(
          users.resetPassword(email: 'sofien@gmail.com', code: r.code, newPassword: 'court'),
          fails('8 caractères'));
      final u = await users.resetPassword(
          email: 'sofien@gmail.com', code: r.code, newPassword: 'Nouveau2026');
      expect(u.id, sofien.id);
      expect((await users.signIn(email: 'sofien@gmail.com', password: 'Nouveau2026')).id, sofien.id);
      await expectLater(users.signIn(email: 'sofien@gmail.com', password: 'Secret123'),
          fails('incorrect'));
      await expectLater(
          users.resetPassword(email: 'sofien@gmail.com', code: r.code, newPassword: 'Autre2026'),
          fails('Demandez un nouveau code'));
    });

    test('compte inconnu ou désactivé : pas de code', () async {
      expect(await users.requestPasswordReset('inconnu@gmail.com'), isNull);
      final amina = await users.signUp(name: 'Amina', email: 'amina@gmail.com', password: 'Secret123');
      // Sofien est le premier compte (admin) : il désactive Amina.
      await users.setActive(amina.id, false, actorId: sofien.id);
      expect(await users.requestPasswordReset('amina@gmail.com'), isNull);
    });

    test('5 essais, expiration, nouveau code qui remplace l\'ancien', () async {
      final first = (await users.requestPasswordReset('sofien@gmail.com'))!;
      final second = (await users.requestPasswordReset('sofien@gmail.com'))!;
      final wrong = second.code == '000000' ? '111111' : '000000';
      // L'ancien code ne fonctionne plus (sauf tirage identique, 1 sur un million).
      await expectLater(
          users.resetPassword(
              email: 'sofien@gmail.com',
              code: first.code != second.code ? first.code : wrong,
              newPassword: 'Nouveau2026'),
          fails('4 essais restants'));
      for (final left in ['3 essais', '2 essais', '1 essai restant']) {
        await expectLater(
            users.resetPassword(email: 'sofien@gmail.com', code: wrong, newPassword: 'Nouveau2026'),
            fails(left));
      }
      await expectLater(
          users.resetPassword(email: 'sofien@gmail.com', code: wrong, newPassword: 'Nouveau2026'),
          fails('Trop d\'essais'));
      await expectLater(
          users.resetPassword(email: 'sofien@gmail.com', code: second.code, newPassword: 'Nouveau2026'),
          fails('Demandez un nouveau code'), reason: 'code supprimé');

      final late = (await users.requestPasswordReset('sofien@gmail.com'))!;
      clock.now = clock.now.add(const Duration(minutes: 16));
      await expectLater(
          users.resetPassword(email: 'sofien@gmail.com', code: late.code, newPassword: 'Nouveau2026'),
          fails('expiré'));
    });

    test('le blocage après 5 mots de passe faux est levé', () async {
      for (var i = 0; i < 5; i++) {
        await expectLater(users.signIn(email: 'sofien@gmail.com', password: 'Mauvais99'), fails(''));
      }
      await expectLater(
          users.signIn(email: 'sofien@gmail.com', password: 'Secret123'), fails('Trop d\'essais'));
      final r = (await users.requestPasswordReset('sofien@gmail.com'))!;
      await users.resetPassword(email: 'sofien@gmail.com', code: r.code, newPassword: 'Nouveau2026');
      expect((await users.signIn(email: 'sofien@gmail.com', password: 'Nouveau2026')).id, sofien.id);
    });
  });

  group('controller', () {
    test('envoi par e-mail, délai de 60 s entre deux codes', () async {
      final mailer = FakeResetMailer();
      final auth = AuthController(
          model: AuthModel(), repository: users, mailer: mailer, clock: clock.call,
          showCodeWithoutMailer: false);
      final r = await auth.requestPasswordReset('sofien@gmail.com');
      expect((r.ok, r.demoCode), (true, null));
      expect(mailer.sent.single.to, 'sofien@gmail.com');
      expect(mailer.lastCode, matches(RegExp(r'^\d{6}$')));

      final again = await auth.requestPasswordReset('SOFIEN@gmail.com');
      expect(again.error, 'Patientez 60 s avant de demander un nouveau code.');
      clock.now = clock.now.add(const Duration(seconds: 61));
      expect((await auth.requestPasswordReset('sofien@gmail.com')).ok, isTrue);
      expect(mailer.sent, hasLength(2));

      // Compte inconnu : même réponse, rien n'est envoyé.
      expect((await auth.requestPasswordReset('inconnu@gmail.com')).ok, isTrue);
      expect(mailer.sent, hasLength(2));

      expect(await auth.resetPassword(email: 'sofien@gmail.com', code: '12', newPassword: 'Nouveau2026'),
          contains('Code incorrect'));
      expect(await auth.resetPassword(
          email: 'sofien@gmail.com', code: mailer.lastCode, newPassword: 'Nouveau2026'), isNull);
    });

    test('erreur d\'envoi, e-mail non configuré, mode démo', () async {
      final mailer = FakeResetMailer()..failWith = 'Pas de connexion Internet';
      final auth = AuthController(
          model: AuthModel(), repository: users, mailer: mailer, clock: clock.call,
          showCodeWithoutMailer: false);
      expect((await auth.requestPasswordReset('sofien@gmail.com')).error, 'Pas de connexion Internet');
      expect(auth.resendIn('sofien@gmail.com'), Duration.zero, reason: 'on peut réessayer');

      mailer.configured = false;
      expect((await auth.requestPasswordReset('sofien@gmail.com')).error, contains('pas configuré'));

      final demo = AuthController(
          model: AuthModel(), repository: users, mailer: mailer, clock: clock.call,
          showCodeWithoutMailer: true);
      expect((await demo.requestPasswordReset('sofien@gmail.com')).demoCode, matches(RegExp(r'^\d{6}$')));
    });
  });

  test('e-mail : code, nom échappé, mot de passe d\'application', () {
    final at = DateTime(2026, 11, 8, 10, 15);
    expect(ResetEmail.text('Sofien', '482913', at, 15),
        allOf(contains('Bonjour Sofien'), contains('482913'), contains('jusqu\'à 10 h 15')));
    expect(ResetEmail.html('<b>Ali</b>', '482913', at, 15),
        allOf(contains('&lt;b&gt;Ali'), contains('482913')));
    expect(GmailResetMailer(sender: 'souhirzitoun2003@gmail.com', appPassword: '').configured, isFalse);
    expect(GmailResetMailer(sender: 'souhirzitoun2003@gmail.com', appPassword: 'abcd efgh ijkl mnop')
        .configured, isTrue);
  });

  testWidgets('écran : mot de passe oublié puis connexion avec le nouveau', (tester) async {
    tester.view.physicalSize = const Size(412, 1400) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final wdb = syncMemoryDatabase();
    addTearDown(wdb.close);
    final repo = SqliteUserRepository(wdb, clock: clock.call, hasher: PasswordHasher(iterations: 1));
    await repo.signUp(name: 'Sofien', email: 'sofien@gmail.com', password: 'Secret123');
    final mailer = FakeResetMailer();
    final model = AuthModel();
    final auth = AuthController(
        model: model, repository: repo, mailer: mailer, clock: clock.call,
        showCodeWithoutMailer: false);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider.value(value: auth),
        ChangeNotifierProvider.value(value: model),
        Provider.value(value: CaptchaGenerator.fixed(testCaptcha)),
      ],
      child: const MaterialApp(home: SignInScreen()),
    ));

    await tester.enterText(find.widgetWithText(TextFormField, 'E-mail'), 'sofien@gmail.com');
    await tester.tap(find.text('Mot de passe oublié ?'));
    await tester.pumpAndSettle();
    expect(find.text('Mot de passe oublié'), findsOneWidget);
    expect(find.text('sofien@gmail.com'), findsOneWidget, reason: 'e-mail repris');

    // Sans captcha : rien n'est envoyé.
    await tester.tap(find.text('Envoyer le code'));
    await tester.pumpAndSettle();
    expect(mailer.sent, isEmpty);
    await solveCaptcha(tester);
    await tester.tap(find.text('Envoyer le code'));
    await tester.pumpAndSettle();
    expect(mailer.sent.single.to, 'sofien@gmail.com');
    expect(find.text('Nouveau mot de passe'), findsWidgets);
    expect(find.text('Renvoyer le code (60 s)'), findsOneWidget);

    // Mauvais code, puis le bon.
    await tester.enterText(find.widgetWithText(TextFormField, 'Code reçu par e-mail'),
        mailer.lastCode == '000000' ? '111111' : '000000');
    await tester.enterText(find.widgetWithText(TextFormField, 'Nouveau mot de passe'), 'Nouveau2026');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirmer le mot de passe'), 'Nouveau2026');
    await tester.tap(find.text('Changer le mot de passe'));
    await tester.pumpAndSettle();
    expect(find.text('Code incorrect (4 essais restants).'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Code reçu par e-mail'), mailer.lastCode);
    await tester.tap(find.text('Changer le mot de passe'));
    await tester.pumpAndSettle();

    // Retour à la connexion, e-mail prérempli.
    expect(find.text('Connexion'), findsOneWidget);
    expect(find.text('Mot de passe modifié. Connectez-vous avec le nouveau.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Mot de passe'), 'Nouveau2026');
    await solveCaptcha(tester);
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    expect(model.user?.email, 'sofien@gmail.com');
  });
}
