import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/controllers/user_session.dart';
import 'package:smart_pet/core/theme/app_theme.dart';
import 'package:smart_pet/models/auth/auth_model.dart';
import 'package:smart_pet/models/auth/password_hasher.dart';
import 'package:smart_pet/models/auth/sqlite_user_repository.dart';
import 'package:smart_pet/models/feeding_record.dart';
import 'package:smart_pet/models/gps/location_source.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/pet.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/sqlite_feeding_repository.dart';
import 'package:smart_pet/models/sqlite_health_repository.dart';
import 'package:smart_pet/models/sqlite_pet_repository.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';
import 'package:smart_pet/views/home_shell.dart';

import '../reminders/test_helpers.dart';
import 'dashboard_test.dart' show FakeSharer;

/// Accueil : indice, alertes, coûts, rapport mensuel et partage.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  Future<FakeSharer> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 2600) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = FakeClock(DateTime(2026, 11, 6, 14));
    final now = clock.now;
    final db = syncMemoryDatabase();
    addTearDown(db.close);
    final users = SqliteUserRepository(db, clock: clock.call, hasher: PasswordHasher(iterations: 1));
    final user = await users.signUp(name: 'Souhir Z', email: 'souhir@gmail.com', password: 'Secret123');

    // Données du compte : Rex (vaccin en retard), Mia (repas oubliés).
    final pets = SqlitePetRepository(db, clock: clock.call, ownerId: user.id);
    final rex = await pets.create(Pet(name: 'Rex', species: Species.dog, weightKg: 28));
    final mia = await pets.create(Pet(name: 'Mia', species: Species.cat, weightKg: 4.5));
    await SqliteReminderRepository(db, clock: clock.call, ownerId: user.id).create(Reminder(
        petId: rex.id, title: 'Vaccin rage', type: ReminderType.vaccination,
        dueDate: DateTime(2026, 10, 29, 9)));
    final feeding = SqliteFeedingRepository(db, clock: clock.call, ownerId: user.id);
    await feeding.create(FeedingRecord(
        petId: mia.id!, date: now.subtract(const Duration(days: 4)),
        foodType: FoodType.wet, quantityG: 85, price: 1.8));
    await feeding.create(FeedingRecord(
        petId: rex.id!, date: now, foodType: FoodType.kibble, quantityG: 350, price: 2.6));
    await SqliteHealthRepository(db, clock: clock.call, ownerId: user.id).create(HealthRecord(
        petId: rex.id!, type: HealthType.consultation, date: DateTime(2026, 10, 15),
        cost: 45, weightKg: 28, medication: 'Otomax'));

    final sharer = FakeSharer();
    final session = UserSession(
      user: user,
      database: db,
      users: users,
      notifier: FakeNotifier(),
      photos: FakePhotoStore(),
      clock: clock.call,
      refreshEvery: null,
      reportSharer: sharer,
    );
    addTearDown(session.close);
    await session.load();
    final auth = AuthModel()..signedIn(user);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        Provider<LocationSource>.value(value: FakeLocationSource()),
        ...session.providers,
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
    return sharer;
  }

  testWidgets('accueil : indice, alerte masquée 30 jours, coûts', (tester) async {
    await pump(tester);
    expect(find.text('Bonjour Souhir ! Voici le résumé de vos animaux'), findsOneWidget);
    expect(find.text('Administration'), findsOneWidget, reason: 'premier compte');
    expect(find.text('Indice Smart Pet'), findsOneWidget);
    expect(find.byTooltip(RegExp(r'^Indice Smart Pet de Rex : \d+ / 100$')), findsOneWidget);

    // Alerte « repas non saisis » pour Mia, puis masquée.
    expect(find.text('Pensez à saisir les repas de Mia : aucun repas depuis 4 jours.'),
        findsOneWidget);
    await tester.tap(find.byTooltip('Ne plus afficher pendant 30 jours'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pensez à saisir'), findsNothing);
    expect(find.text('« Repas non saisis » masquée pendant 30 jours'), findsOneWidget);

    // Détail de l'indice de Rex : le vaccin en retard est critique.
    await tester.tap(find.descendant(
        of: find.ancestor(of: find.text('Indice Smart Pet'), matching: find.byType(Card)),
        matching: find.text('Rex')));
    await tester.pumpAndSettle();
    expect(find.text('Indice de Rex'), findsOneWidget);
    expect(find.text('−15 : 1 rappel critique'), findsOneWidget);
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();

    expect(find.text('Coût par animal'), findsOneWidget);
    expect(find.text('Rex : 2,60 DT ce mois, 0,43 DT par jour'), findsOneWidget);
    await tester.tap(find.text('Détails'));
    await tester.pumpAndSettle();
    expect(find.text('Moyenne des 3 derniers mois : 15,00 DT / mois'), findsOneWidget);
  });

  testWidgets('rapport du mois écoulé : prêt, consulté, partagé en texte et PDF',
      (tester) async {
    final sharer = await pump(tester);
    expect(find.text('Votre rapport de octobre 2026 est prêt'), findsOneWidget);
    await tester.tap(find.text('Votre rapport de octobre 2026 est prêt'));
    await tester.pumpAndSettle();
    expect(find.text('octobre 2026'), findsOneWidget);
    expect(find.textContaining('15/10 Consultation (Otomax)'), findsOneWidget);

    await tester.tap(find.text('Partager en texte'));
    await tester.pumpAndSettle();
    expect(sharer.text, contains('- Santé : 45 DT'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Partager en PDF'));
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pumpAndSettle();
    expect(sharer.fileName, 'smart_pet_2026_10.pdf');

    // Mois précédent : vide ; mois suivant (en cours) : provisoire.
    await tester.tap(find.byTooltip('Mois précédent'));
    await tester.pumpAndSettle();
    expect(find.text('Aucune donnée pour ce mois.'), findsOneWidget);
    await tester.tap(find.byTooltip('Mois suivant'));
    await tester.tap(find.byTooltip('Mois suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Mois en cours : rapport provisoire.'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('est prêt'), findsNothing, reason: 'rapport consulté');
  });
}
