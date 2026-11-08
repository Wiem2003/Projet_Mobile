import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/controllers/reminders_controller.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/core/theme/app_theme.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminders_model.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';
import 'package:smart_pet/views/screens/reminder_compliance_screen.dart';
import 'package:smart_pet/views/screens/reminders_screen.dart';
import 'package:smart_pet/views/widgets/reminder_card.dart';
import 'package:smart_pet/views/widgets/segment_tabs.dart';

import 'test_helpers.dart';

/// Écrans : tri par urgence, relances, limite de reports, observance.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  Future<RemindersModel> pump(WidgetTester tester, Widget home,
      {bool overdue = true}) async {
    tester.view.physicalSize = const Size(412, 1100) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = FakeClock(DateTime(2026, 11, 5, 14));
    final db = syncMemoryDatabase();
    addTearDown(db.close);
    final repo = SqliteReminderRepository(db, clock: clock.call);
    final model = RemindersModel(clock: clock.call);
    final ctrl = RemindersController(
      model: model,
      repository: repo,
      notifier: FakeNotifier(),
      pets: const DemoPetDirectory(),
      refreshEvery: null,
    );
    addTearDown(ctrl.dispose);
    if (overdue) {
      for (final r in [
        Reminder(petId: rexId, title: 'Vaccin rage', type: ReminderType.vaccination,
            dueDate: DateTime(2026, 10, 30, 9), postponeCount: 3),
        Reminder(title: 'Croquettes', type: ReminderType.purchase,
            dueDate: DateTime(2026, 11, 4, 18)),
        Reminder(petId: miaId, title: 'Antipuces', type: ReminderType.treatment,
            dueDate: DateTime(2026, 11, 3, 19)),
      ]) {
        await repo.create(r);
      }
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
    return model;
  }

  final overdueTab = find.descendant(
      of: find.byType(SegmentTabs), matching: find.text('En retard'));

  List<String> cardTitles(WidgetTester tester) => [
        for (final c in tester.widgetList<ReminderCard>(find.byType(ReminderCard)))
          c.reminder.title,
      ];

  testWidgets('en retard : tri par urgence, relance et critique', (tester) async {
    await pump(tester, const RemindersScreen());
    await tester.tap(overdueTab);
    await tester.pumpAndSettle();
    // Vaccin 5 × 6 j = 30 ; antipuces 4 × 2 j = 8 ; croquettes 1 × 1 j = 1.
    expect(cardTitles(tester), ['Vaccin rage', 'Antipuces', 'Croquettes']);
    expect(find.text('Critique'), findsOneWidget);
    expect(find.text('Relance 1'), findsNWidgets(2));
    expect(find.textContaining('1 critique (plus de 3 jours de retard)'), findsOneWidget);
  });

  testWidgets('limite de reports atteinte : rendez-vous proposé', (tester) async {
    final model = await pump(tester, const RemindersScreen());
    await tester.tap(overdueTab);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vaccin rage'));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3 utilisés · 30 j maximum par report'), findsOneWidget);
    expect(find.textContaining('Critique · score 30'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Reporter'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Reporter'));
    await tester.pumpAndSettle();
    expect(find.text('Report impossible'), findsOneWidget);
    expect(find.textContaining('déjà été reporté 3 fois'), findsOneWidget);
    await tester.tap(find.text('Prendre rendez-vous'));
    await tester.pumpAndSettle();
    // Formulaire pré-rempli : nouveau rappel (pas une modification).
    expect(find.text('Rendez-vous vétérinaire : Vaccin rage'), findsOneWidget);
    expect(model.all.where((r) => r.type == ReminderType.vetAppointment), isEmpty);
  });

  testWidgets('feuille de report : reports restants, durée maximale', (tester) async {
    await pump(tester, const RemindersScreen());
    await tester.tap(overdueTab);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Antipuces'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Reporter'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Reporter'));
    await tester.pumpAndSettle();
    expect(find.text('Report 1 sur 2 autorisés · 7 jours maximum par report'),
        findsOneWidget);
    // « Dans 1 mois » dépasse 7 jours : désactivé.
    expect(find.text('Au-delà de la limite de report'), findsOneWidget);
    await tester.tap(find.text('Dans 1 semaine'));
    await tester.pumpAndSettle();
    expect(find.textContaining('encore 1 report possible'), findsOneWidget);
  });

  testWidgets('observance : historique d\'exemple, taux et séries', (tester) async {
    await pump(tester, const ReminderComplianceScreen(), overdue: false);
    expect(find.text('Aucune échéance passée'), findsOneWidget);
    await tester.tap(find.text('Charger un historique d\'exemple'));
    await tester.pumpAndSettle();
    // 16 soins à temps sur 21.
    expect(find.text('76 %'), findsOneWidget);
    expect(find.text('16 à temps · 5 en retard · 0 oublié'), findsOneWidget);
    expect(find.text('8 vermifuges d\'affilée faits à l\'heure'), findsOneWidget);
    // Filtre sur Mia : 7 soins dont 2 en retard.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Mia'));
    await tester.pumpAndSettle();
    expect(find.text('5 à temps · 2 en retard · 0 oublié'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Tous'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Le plus souvent en retard'), 300);
    expect(find.text('Le plus souvent en retard'), findsOneWidget);
  });
}
