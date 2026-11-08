import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/controllers/auth_controller.dart';
import 'package:smart_pet/models/auth/auth_model.dart';
import 'package:smart_pet/models/auth/captcha.dart';
import 'package:smart_pet/models/auth/password_hasher.dart';
import 'package:smart_pet/models/auth/sqlite_user_repository.dart';
import 'package:smart_pet/views/screens/auth_screens.dart';
import 'package:smart_pet/views/widgets/captcha_box.dart';

import '../reminders/test_helpers.dart';

/// Captcha « Je ne suis pas un robot » de la connexion et de l'inscription.
void main() {
  group('règles', () {
    test('code de 5 caractères sans caractères ambigus', () {
      final g = CaptchaGenerator(math.Random(42));
      final codes = [for (var i = 0; i < 200; i++) g.next().code];
      for (final c in codes) {
        expect(c.length, 5);
        expect(c, isNot(matches(RegExp('[01OIL]'))));
      }
      expect(codes.toSet().length, greaterThan(190), reason: 'codes variés');
    });

    test('saisie : casse et espaces ignorés', () {
      const c = CaptchaChallenge('AB3CD', 1);
      expect(c.accepts('ab3cd'), isTrue);
      expect(c.accepts(' AB 3CD '), isTrue);
      expect(c.accepts('AB3CE'), isFalse);
    });

    test('case, erreurs, nouveau code après 3 erreurs, usage unique', () {
      final s = CaptchaState(CaptchaGenerator.fixed('AB3CD'));
      expect(s.submit('AB3CD'), contains('Cochez'));
      s
        ..check()
        ..showChallenge();
      final first = s.challenge.seed;
      expect(s.submit(''), 'Recopiez le code affiché.');
      expect(s.submit('XXXXX'), contains('2 essais'));
      expect(s.submit('XXXXX'), contains('1 essai '));
      expect(s.submit('XXXXX'), 'Code incorrect. Un nouveau code a été affiché.');
      expect(s.challenge.seed, isNot(first));
      expect(s.submit('ab3cd'), isNull);
      expect(s.verified, isTrue);
      s.reset();
      expect((s.step, s.verified), (CaptchaStep.unchecked, false));
    });
  });

  testWidgets('connexion : bloquée sans captcha, puis captcha à refaire après un échec',
      (tester) async {
    tester.view.physicalSize = const Size(412, 1200) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = syncMemoryDatabase();
    addTearDown(db.close);
    final users = SqliteUserRepository(db, hasher: PasswordHasher(iterations: 1));
    await users.signUp(name: 'Sofien', email: 'sofien@gmail.com', password: 'Secret123');
    final model = AuthModel();
    final auth = AuthController(model: model, repository: users);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider.value(value: auth),
        ChangeNotifierProvider.value(value: model),
        Provider.value(value: CaptchaGenerator.fixed(testCaptcha)),
      ],
      child: const MaterialApp(home: SignInScreen()),
    ));

    await tester.enterText(find.widgetWithText(TextFormField, 'E-mail'), 'sofien@gmail.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Mot de passe'), 'Mauvais99');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    expect(find.text('Cochez « Je ne suis pas un robot ».'), findsOneWidget);
    expect(model.user, isNull);

    // Case cochée : courte vérification puis code à recopier.
    await tester.tap(find.text('Je ne suis pas un robot'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(CaptchaBoxState.checkingDelay);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('captcha-image')), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Recopiez le code'), 'ZZZZZ');
    await tester.pumpAndSettle();
    expect(find.textContaining('Code incorrect'), findsOneWidget);
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    expect(model.user, isNull, reason: 'code faux : pas de tentative');

    // Bon code, mauvais mot de passe : refusé, le captcha est à refaire.
    await tester.enterText(find.widgetWithText(TextField, 'Recopiez le code'), 'ab3cd');
    await tester.pumpAndSettle();
    expect(find.text('Vérifié : vous n\'êtes pas un robot'), findsOneWidget);
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    expect(find.text(SqliteUserRepository.badCredentials), findsOneWidget);
    expect(find.text('Je ne suis pas un robot'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Mot de passe'), 'Secret123');
    await solveCaptcha(tester);
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    expect(model.user?.email, 'sofien@gmail.com');
  });
}
