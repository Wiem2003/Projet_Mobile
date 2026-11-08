import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/models/feeding_model.dart';
import 'package:smart_pet/models/health_model.dart';
import 'package:smart_pet/controllers/activities_controller.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/core/theme/app_theme.dart';
import 'package:smart_pet/models/activities_model.dart';
import 'package:smart_pet/models/activity.dart';
import 'package:smart_pet/models/gps/location_source.dart';
import 'package:smart_pet/models/sqlite_activity_repository.dart';
import 'package:smart_pet/views/formatters.dart';
import 'package:smart_pet/views/screens/activities_screen.dart';

import '../reminders/test_helpers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late FakeLocationSource gps;

  Future<ActivitiesModel> pump(WidgetTester tester,
      {bool withData = true, Size size = const Size(412, 2400)}) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = FakeClock(DateTime(2026, 11, 3, 14));
    final db = syncMemoryDatabase();
    addTearDown(db.close);
    final repo = SqliteActivityRepository(db, clock: clock.call);
    final model = ActivitiesModel(clock: clock.call);
    final ctrl = ActivitiesController(
        model: model, repository: repo, pets: const DemoPetDirectory());
    gps = FakeLocationSource();
    addTearDown(gps.fixes.close);
    if (withData) {
      await repo.create(Activity(
          petId: rexId,
          date: DateTime(2026, 11, 3, 8),
          type: ActivityType.walk,
          durationMin: 40,
          distanceKm: 3,
          weightKg: 28));
      await repo.create(Activity(
          petId: miaId,
          date: DateTime(2026, 10, 30, 20),
          type: ActivityType.play,
          durationMin: 20,
          weightKg: 4.5));
      final start = DateTime(2026, 11, 2, 18);
      final route = ActivitiesController.demoRoute(start);
      await repo.create(Activity(
          petId: rexId,
          date: start,
          type: ActivityType.walk,
          durationMin: 42,
          distanceKm: double.parse(Geo.pathKm(route).toStringAsFixed(2)),
          weightKg: 28,
          route: route));
    }
    await ctrl.load();

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<LocationSource>.value(value: gps),
        Provider.value(value: ctrl),
        ChangeNotifierProvider.value(value: model),
        ChangeNotifierProvider.value(value: FeedingModel()),
        ChangeNotifierProvider.value(value: HealthModel()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const ActivitiesScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    return model;
  }

  testWidgets('indicateurs, graphique et historique', (tester) async {
    final model = await pump(tester);
    final stats = model.stats;
    expect(find.text('Activités'), findsOneWidget);
    expect(find.text('Distance hebdomadaire'), findsOneWidget);
    expect(find.text(Units.km(stats.weeklyDistanceKm)), findsOneWidget);
    expect(find.text('Nombre d\'activités'), findsOneWidget);
    expect(stats.count, 3);
    expect(find.text('Durée moyenne'), findsOneWidget);
    expect(find.text('34 min'), findsOneWidget, reason: '(40 + 20 + 42) / 3');
    expect(find.text('Distance hebdomadaire (km)'), findsOneWidget);
    expect(find.text('Cette sem.'), findsOneWidget);
    expect(find.text('GPS'), findsOneWidget);
  });

  testWidgets('période et filtre par type', (tester) async {
    final model = await pump(tester);
    final chip = find.widgetWithText(ChoiceChip, 'Jeu');
    // Liste horizontale des types : on la fait défiler jusqu'à « Jeu ».
    await tester.drag(find.byType(ListView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(model.typeFilter, ActivityType.play);
    expect(find.byType(ActivityCard), findsOneWidget);

    await tester.tap(find.text('7 jours'));
    await tester.pumpAndSettle();
    expect(model.period.days, 7);
    expect(model.stats.count, 1);
  });

  testWidgets('détail d\'une promenade GPS avec son tracé', (tester) async {
    await pump(tester);
    await tester.tap(find.text('GPS'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Trajet enregistré au GPS'), findsOneWidget);
    expect(find.text('Vitesse moy.'), findsOneWidget);
    expect(find.textContaining('MET 3.0'), findsOneWidget);
  });

  testWidgets('promenade GPS : suivi, fin, formulaire prérempli, enregistrement',
      (tester) async {
    final model = await pump(tester, size: const Size(412, 2400));
    await tester.tap(find.text('Promenade GPS'));
    await tester.pumpAndSettle();
    expect(find.text('Appuyez sur « Démarrer » pour enregistrer le trajet'),
        findsOneWidget);

    await tester.tap(find.text('Démarrer'));
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);
    final t0 = DateTime(2026, 11, 3, 14);
    for (var i = 0; i <= 10; i++) {
      gps.fixes.add(LocationFix(
          GeoPoint(36.800 + i * 0.0005, 10.18, t0.add(Duration(seconds: 30 * i))),
          accuracyM: 6));
    }
    await tester.pump();
    expect(find.text('0,6 km'), findsOneWidget);
    expect(find.textContaining('précision ±6 m'), findsOneWidget);

    await tester.tap(find.text('Terminer'));
    await tester.pumpAndSettle();
    expect(find.text('Enregistrer la promenade'), findsOneWidget);
    expect(find.text('0,56'), findsOneWidget, reason: 'distance mesurée');
    expect(find.text('Mesurée par le GPS'), findsOneWidget);

    await tester.tap(find.text('Ajouter l\'activité'));
    await tester.pumpAndSettle();
    expect(model.all.where((a) => a.hasRoute), hasLength(2));
    expect(find.text('GPS'), findsNWidgets(2));
  });

  testWidgets('GPS refusé : message et bouton réglages', (tester) async {
    await pump(tester, withData: false);
    gps.issue = LocationIssue.deniedForever;
    await tester.tap(find.text('Promenade GPS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Démarrer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Autorisez-le dans les réglages'), findsOneWidget);
    await tester.tap(find.text('Ouvrir les réglages'));
    expect(gps.settingsOpened, 1);
  });

  testWidgets('nouvelle activité manuelle et écran vide', (tester) async {
    final model =
        await pump(tester, withData: false, size: const Size(412, 1600));
    expect(find.text('Aucune activité sur la période'), findsOneWidget);
    await tester.tap(find.text('Nouvelle activité'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Course'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Ex. 45'), '30');
    await tester.pumpAndSettle();
    // Course : MET 7 × 28 kg × 0,5 h.
    expect(find.text('98 kcal'), findsOneWidget);
    await tester.tap(find.text('Ajouter l\'activité'));
    await tester.pumpAndSettle();
    expect(find.text('Course enregistrée — 98 kcal'), findsOneWidget);
    expect(model.all.single.type, ActivityType.run);
  });

  testWidgets('aucun débordement sur un petit écran (360 dp)', (tester) async {
    final model = await pump(tester, size: const Size(360, 740));
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Charger des exemples'));
    await tester.pumpAndSettle();
    expect(model.visible.length, greaterThan(10));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPS').first);
    await tester.pumpAndSettle();
    // Feuille agrandie puis défilée jusqu'en bas : les boutons sont visibles.
    for (var i = 0; i < 3; i++) {
      await tester.drag(find.text('Calories'), const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    final sheetBottom =
        tester.getBottomLeft(find.byType(DraggableScrollableSheet)).dy;
    expect(tester.getBottomLeft(find.text('Modifier')).dy,
        lessThanOrEqualTo(sheetBottom));
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -2500));
    await tester.pumpAndSettle();
    expect(find.text('Calories estimées (calcul automatique)'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Promenade GPS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Démarrer'));
    await tester.pump();
    gps.fixes.add(LocationFix(GeoPoint(36.8, 10.18, DateTime(2026, 11, 3, 14)),
        accuracyM: 12));
    await tester.pump();
    expect(find.text('Terminer'), findsOneWidget);
  });
}
