import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/controllers/reminders_controller.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/core/theme/app_theme.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminder_planning.dart';
import 'package:smart_pet/models/reminders_model.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';
import 'package:smart_pet/views/reminder_actions.dart';
import 'package:smart_pet/views/screens/reminder_planning_screen.dart';
import 'package:smart_pet/views/screens/reminders_screen.dart';

import 'test_helpers.dart';

/// Écrans : journées chargées, budget, délais minimaux, avertissement du
/// formulaire.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  final day = DateTime(2026, 11, 10);
  DateTime at(int hour) => DateTime(day.year, day.month, day.day, hour);

  /// Journée du 10 novembre surchargée (5 rappels) et un détartrage en
  /// décembre ; le dernier détartrage de Mia a coûté 85 DT.
  final busyDay = [
    Reminder(petId: rexId, title: 'Vaccin rage', type: ReminderType.vaccination, dueDate: at(9)),
    Reminder(petId: miaId, title: 'Détartrage', type: ReminderType.checkup, dueDate: at(10)),
    Reminder(title: 'Croquettes', type: ReminderType.purchase, dueDate: at(18)),
    Reminder(petId: rexId, title: 'Toilettage', type: ReminderType.other, dueDate: at(19)),
    Reminder(petId: miaId, title: 'Antipuces', type: ReminderType.treatment, dueDate: at(20)),
  ];

  Future<(RemindersModel, MemoryPlanningSettingsStore)> pump(
      WidgetTester tester, Widget home, List<Reminder> reminders) async {
    tester.view.physicalSize = const Size(412, 1600) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = FakeClock(DateTime(2026, 11, 5, 14));
    final db = syncMemoryDatabase();
    addTearDown(db.close);
    final repo = SqliteReminderRepository(db, clock: clock.call);
    final model = RemindersModel(clock: clock.call);
    final store = MemoryPlanningSettingsStore();
    final ctrl = RemindersController(
      model: model,
      repository: repo,
      notifier: FakeNotifier(),
      pets: const DemoPetDirectory(),
      refreshEvery: null,
      planning: store,
      healthRecords: () async => [
        HealthRecord(id: 1, petId: miaId, type: HealthType.dental,
            date: DateTime(2025, 12, 10), cost: 85),
      ],
    );
    addTearDown(ctrl.dispose);
    for (final r in reminders) {
      await repo.create(r);
    }
    await ctrl.load();
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
        home: home,
      ),
    ));
    await tester.pumpAndSettle();
    return (model, store);
  }

  testWidgets('journée chargée : les rappels peu graves sont déplacés',
      (tester) async {
    final (model, _) = await pump(tester, const ReminderPlanningScreen(), busyDay);
    expect(find.textContaining('— 5 rappels'), findsOneWidget);
    expect(find.text('Croquettes · Rex'), findsNothing, reason: 'rappel général');
    expect(find.text('Croquettes'), findsWidgets);
    await tester.tap(find.text('Déplacer (2)'));
    await tester.pumpAndSettle();
    expect(find.text('2 rappels déplacé(s)'), findsOneWidget);
    expect(find.text('Aucune journée de plus de 3 rappels.'), findsOneWidget);
    final moved = model.all.firstWhere((r) => r.title == 'Croquettes');
    expect(moved.dueDate, DateTime(2026, 11, 11, 18));
  });

  testWidgets('budget : plafond, dépassement, décalage au mois suivant',
      (tester) async {
    final (model, store) = await pump(tester, const ReminderPlanningScreen(), busyDay);
    expect(find.text('Prévu en novembre 2026'), findsOneWidget);
    expect(find.text('85,00 DT'), findsWidgets);
    expect(find.text('coût inconnu'), findsWidgets);

    await tester.tap(find.text('Fixer un budget'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '50');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(store.settings.monthlyBudget, 50);
    expect(find.textContaining('Budget dépassé de 35,00 DT'), findsOneWidget);

    await tester.tap(find.text('Décaler (1)'));
    await tester.pumpAndSettle();
    expect(find.text('1 rappel décalé(s) au mois suivant'), findsOneWidget);
    expect(model.all.firstWhere((r) => r.title == 'Détartrage').dueDate,
        DateTime(2026, 12, 10, 10));
  });

  testWidgets('délais minimaux : modifier la règle par défaut', (tester) async {
    final (_, store) = await pump(tester, const ReminderPlanningScreen(), const []);
    await tester.scrollUntilVisible(find.text('Vaccin ↔ Vermifuge'), 300);
    expect(find.text('7 jours minimum, même animal'), findsOneWidget);
    await tester.tap(find.text('Vaccin ↔ Vermifuge'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '7'), '10');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(store.settings.intervals.single.days, 10);
    expect(find.text('10 jours minimum, même animal'), findsOneWidget);

    await tester.tap(find.byTooltip('Supprimer le délai'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun délai minimal'), findsOneWidget);
  });

  testWidgets('formulaire : vermifuge trop proche du vaccin, date corrigée',
      (tester) async {
    final (model, _) = await pump(tester, const RemindersScreen(), [busyDay.first]);
    final context = tester.element(find.byType(RemindersScreen));
    ReminderActions.openForm(context,
        preset: Reminder(petId: rexId, title: 'Vermifuge',
            type: ReminderType.deworming, dueDate: DateTime(2026, 11, 12, 9)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Moins de 7 jours avec « Vaccin rage »'), findsOneWidget);
    expect(find.textContaining('Première date possible : Mar. 17 nov.'), findsOneWidget);
    await tester.tap(find.text('Utiliser cette date'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Première date possible'), findsNothing);
    await tester.tap(find.text('Créer le rappel'));
    await tester.pumpAndSettle();
    expect(model.all.firstWhere((r) => r.title == 'Vermifuge').dueDate,
        DateTime(2026, 11, 17, 9));
  });

  testWidgets('bandeau « À venir » : journée chargée → planification', (tester) async {
    await pump(tester, const RemindersScreen(), busyDay);
    expect(find.textContaining('Journée chargée le'), findsOneWidget);
    await tester.tap(find.textContaining('Journée chargée le'));
    await tester.pumpAndSettle();
    expect(find.text('Planification & budget'), findsOneWidget);
  });
}
