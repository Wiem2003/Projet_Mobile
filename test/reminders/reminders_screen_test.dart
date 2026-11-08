import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/core/theme/app_theme.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminders_model.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';
import 'package:smart_pet/controllers/reminders_controller.dart';
import 'package:smart_pet/views/screens/reminders_screen.dart';
import 'package:smart_pet/views/widgets/reminder_card.dart';

import 'test_helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  Finder inCard(String text) => find.descendant(
      of: find.byType(ReminderCard), matching: find.text(text));

  Future<RemindersModel> pump(WidgetTester tester,
      {Size size = const Size(412, 915), bool demo = false}) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = FakeClock(DateTime(2026, 10, 29, 14));
    final db = memoryDatabase();
    final repo = SqliteReminderRepository(db, clock: clock.call);
    final model = RemindersModel(clock: clock.call);
    final ctrl = RemindersController(
      model: model,
      repository: repo,
      notifier: FakeNotifier(),
      pets: const DemoPetDirectory(),
      refreshEvery: null,
    );
    // Accès SQLite réels : hors de l'horloge simulée du test.
    await tester.runAsync(() async {
      await repo.create(Reminder(
          petId: rexId,
          title: 'Vermifuge',
          type: ReminderType.deworming,
          dueDate: DateTime(2026, 10, 30, 8)));
      await repo.create(Reminder(
          petId: miaId,
          title: 'Antipuces',
          type: ReminderType.treatment,
          dueDate: DateTime(2026, 10, 27, 19)));
      await ctrl.load();
      if (demo) await ctrl.seedDemo();
    });

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider.value(value: ctrl),
        ChangeNotifierProvider.value(value: model),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const RemindersScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    addTearDown(() => tester.runAsync(db.close));
    addTearDown(ctrl.dispose);
    return model;
  }

  testWidgets('affiche les indicateurs et les rappels à venir', (tester) async {
    await pump(tester);
    expect(find.text('Rappels & alertes'), findsOneWidget);
    expect(inCard('Vermifuge'), findsOneWidget);
    expect(inCard('Demain'), findsOneWidget);
    // Le rappel en retard n'est pas dans l'onglet « À venir ».
    expect(inCard('Antipuces'), findsNothing);
  });

  testWidgets('onglet En retard', (tester) async {
    await pump(tester);
    await tester.tap(find.text('En retard').last);
    await tester.pumpAndSettle();
    expect(inCard('Antipuces'), findsOneWidget);
    expect(find.text('Retard 2 j'), findsOneWidget);
  });

  testWidgets('filtre par animal', (tester) async {
    final model = await pump(tester);
    await tester.tap(find.text('Mia'));
    await tester.pumpAndSettle();
    expect(model.petFilter, miaId);
    expect(inCard('Vermifuge'), findsNothing);
  });

  testWidgets('le formulaire bloque un titre vide (T02)', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Nouveau rappel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.tap(find.text('Créer le rappel'));
    await tester.pumpAndSettle();
    expect(find.text('Le titre est obligatoire'), findsOneWidget);
  });

  testWidgets('aucun débordement sur un petit écran (360 dp)', (tester) async {
    final model = await pump(tester, size: const Size(360, 740), demo: true);
    expect(model.countFor(ReminderTab.upcoming), greaterThan(4));

    // Fiche détail + feuille de report.
    await tester.scrollUntilVisible(inCard('Vermifuge'), 200,
        scrollable: find
            .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(inCard('Vermifuge'));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Reporter'), 150,
        scrollable: find
            .descendant(
                of: find.byType(DraggableScrollableSheet),
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('Reporter'));
    await tester.pumpAndSettle();
    expect(find.text('Reporter le rappel'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Formulaire complet, défilé jusqu'en bas.
    await tester.tap(find.text('Nouveau rappel'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('Notifications prévues'), findsOneWidget);
  });

  testWidgets('assistant : suggestion, message libre et cartes', (tester) async {
    await pump(tester, size: const Size(360, 740));
    await tester.tap(find.byTooltip('Assistant'));
    await tester.pumpAndSettle();
    expect(find.text('Assistant Rappels'), findsOneWidget);

    await tester.tap(find.text("Quoi de prévu aujourd'hui ?"));
    await tester.pumpAndSettle();
    expect(find.text("Aujourd'hui : rien de prévu ✨"), findsOneWidget);

    await tester.enterText(
        find.byType(TextField), "Qu'est-ce qui est en retard ?");
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 rappel en retard'), findsOneWidget);
    expect(find.text('Antipuces'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Quoi de prévu demain ?');
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pumpAndSettle();
    expect(find.text('Demain : 1 rappel.'), findsOneWidget);
    expect(find.text('Vermifuge'), findsOneWidget);

    // La carte ouvre la fiche détail du rappel.
    await tester.tap(find.text('Vermifuge'));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
  });
}
