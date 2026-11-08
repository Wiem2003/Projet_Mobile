import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/controllers/health_controller.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/core/theme/app_theme.dart';
import 'package:smart_pet/models/health_model.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/sqlite_health_repository.dart';
import 'package:smart_pet/views/formatters.dart';
import 'package:smart_pet/views/screens/health_screen.dart';

import '../reminders/test_helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  Future<HealthModel> pump(WidgetTester tester,
      {bool demo = true, Size size = const Size(412, 1600)}) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = FakeClock(DateTime(2026, 11, 3, 14));
    final db = syncMemoryDatabase();
    addTearDown(db.close);
    final model = HealthModel(clock: clock.call);
    final ctrl = HealthController(
        model: model,
        repository: SqliteHealthRepository(db, clock: clock.call),
        pets: const DemoPetDirectory());
    await ctrl.load();
    if (demo) await ctrl.seedDemo();

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
        home: const HealthScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    return model;
  }

  testWidgets('indicateurs, courbe de poids d\'un animal, échéances',
      (tester) async {
    final model = await pump(tester);
    expect(find.text('Santé'), findsOneWidget);
    expect(find.text('Consultations'), findsOneWidget);
    expect(find.text('Dépenses médicales'), findsOneWidget);
    expect(find.text(Units.money(model.stats.spending)), findsOneWidget);
    expect(find.text('choisissez un animal'), findsNWidgets(2));
    expect(find.text('Prochaines échéances'), findsOneWidget);

    await tester.tap(find.text('Rex').first);
    await tester.pumpAndSettle();
    expect(find.text('Évolution du poids de Rex (kg)'), findsOneWidget);
    expect(find.text('Rex · 5 pesée(s)'), findsOneWidget);
    expect(find.text('+1,6 kg'), findsOneWidget, reason: '26,5 → 28,1');
    expect(find.text(Units.kg(model.stats.averageWeight!)), findsOneWidget);
  });

  testWidgets('ajouter un dossier avec échéance', (tester) async {
    final model = await pump(tester, demo: false);
    expect(find.text('Aucun soin sur la période'), findsOneWidget);
    await tester.tap(find.text('Ajouter un dossier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vaccination'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom du vaccin (obligatoire)'),
        'Rage');
    await tester.enterText(find.widgetWithText(TextFormField, '0'), '60');
    await tester.tap(find.text('Dans 1 an'));
    await tester.pumpAndSettle();
    expect(find.text('Rappel créé automatiquement'), findsOneWidget);
    expect(find.text('Mer. 3 nov. à 9 h'), findsOneWidget);

    await tester.tap(find.text('Ajouter le dossier'));
    await tester.pumpAndSettle();
    final r = model.all.single;
    expect((r.type, r.medication, r.cost, r.nextDue),
        (HealthType.vaccination, 'Rage', 60, DateTime(2027, 11, 3)));
    expect(find.text('Vaccination · Rage'), findsOneWidget);
    expect(find.text('Prochaine échéance : Mer. 3 nov.'), findsOneWidget);
  });

  testWidgets('filtre par type, modifier, supprimer', (tester) async {
    final model = await pump(tester);
    final total = model.all.length;
    final chip = find.widgetWithText(ChoiceChip, 'Détartrage');
    // Liste horizontale des types : défilement jusqu'à « Détartrage ».
    for (var i = 0; i < 6 && chip.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(-150, 0));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.byType(HealthRecordCard), findsOneWidget);

    await tester.tap(find.byType(HealthRecordCard));
    await tester.pumpAndSettle();
    expect(find.text('Modifier le dossier'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer ce dossier ?'), findsOneWidget);
    expect(find.textContaining('ainsi que le rappel de son échéance'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(model.all, hasLength(total - 1));
    expect(find.text('Aucun soin sur la période'), findsOneWidget);
  });

  testWidgets('aucun débordement sur un petit écran (360 dp)', (tester) async {
    await pump(tester, size: const Size(360, 740));
    await tester.tap(find.text('Mia').first);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un dossier'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -2500));
    await tester.pumpAndSettle();
    expect(find.text('PROCHAINE ÉCHÉANCE'), findsOneWidget);
  });
}
