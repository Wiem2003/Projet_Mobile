import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/controllers/auth_controller.dart';
import 'package:smart_pet/models/auth/auth_model.dart';
import 'package:smart_pet/models/auth/captcha.dart';
import 'package:smart_pet/models/auth/password_hasher.dart';
import 'package:smart_pet/models/auth/sqlite_user_repository.dart';
import 'package:smart_pet/views/screens/auth_screens.dart';

import '../reminders/test_helpers.dart';

/// Inscription sur un petit écran (360 dp) : le choix du rôle tient.
void main() {
  testWidgets('choix du rôle et captcha sans débordement à 360 dp', (tester) async {
    tester.view.physicalSize = const Size(360, 1400) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = syncMemoryDatabase();
    addTearDown(db.close);
    final model = AuthModel();
    final auth = AuthController(
        model: model, repository: SqliteUserRepository(db, hasher: PasswordHasher(iterations: 1)));
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider.value(value: auth),
        ChangeNotifierProvider.value(value: model),
        Provider.value(value: CaptchaGenerator.fixed(testCaptcha)),
      ],
      child: const MaterialApp(home: SignUpScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Administrateur'));
    await tester.pumpAndSettle();
    // Captcha ouvert (case, image, champ), puis vérifié.
    await tester.tap(find.text('Je ne suis pas un robot'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('captcha-image')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await solveCaptcha(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Utilisateur'), findsOneWidget);
  });
}
