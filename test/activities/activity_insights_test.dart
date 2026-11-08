import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_pet/controllers/activities_controller.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/core/theme/app_theme.dart';
import 'package:smart_pet/models/activities_model.dart';
import 'package:smart_pet/models/activity.dart';
import 'package:smart_pet/models/activity_guidelines.dart';
import 'package:smart_pet/models/activity_insights.dart';
import 'package:smart_pet/models/feeding_model.dart';
import 'package:smart_pet/models/feeding_record.dart';
import 'package:smart_pet/models/health_model.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/notifications/achievement_notifier.dart';
import 'package:smart_pet/models/pet.dart';
import 'package:smart_pet/models/sqlite_activity_repository.dart';
import 'package:smart_pet/views/widgets/activity_insights_section.dart';

import '../reminders/test_helpers.dart';

class FakeAchievements implements AchievementNotifier {
  final shown = <String>[];

  @override
  Future<void> showAchievement({required String title, required String body}) async =>
      shown.add(title);
}

/// Charge et récupération, durée conseillée, bilan énergétique, records.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  final now = DateTime(2026, 11, 6, 14);
  DateTime ago(int d, [int hour = 9]) => DateTime(now.year, now.month, now.day - d, hour);
  const rex = PetSummary(id: 1, name: 'Rex', species: 'Chien', weightKg: 28);
  const mia = PetSummary(id: 2, name: 'Mia', species: 'Chat', weightKg: 4.5);

  Activity act(PetSummary p, int daysAgo, int min,
          {ActivityType type = ActivityType.walk, double km = 0, double kcal = 0, int hour = 9}) =>
      Activity(petId: p.id, date: ago(daysAgo, hour), type: type, durationMin: min,
          distanceKm: km, calories: kcal);

  test('durée conseillée selon la taille ; objectif de la semaine', () {
    expect(ActivityGuidelines.dailyMinutes(Species.dog, 8), (30, 60));
    expect(ActivityGuidelines.dailyMinutes(Species.dog, 18), (60, 90));
    expect(ActivityGuidelines.dailyMinutes(Species.dog, 28), (90, 120));
    expect(ActivityGuidelines.dailyMinutes(Species.dog, null), (60, 90));
    expect(ActivityGuidelines.dailyMinutes(Species.cat, 4), (30, 60));
    expect(ActivityGuidelines.weeklyGoalMinutes(Species.dog, 28), 630);
    expect(ActivityGuidelines.weeklyGoalMinutes(Species.rabbit, 2), 120);
    expect(ActivityGuidelines.weeklyGoalMinutes(Species.bird, 0.1), isNull);
    expect(ActivityGuidelines.shortProfile(Species.dog, 28), 'grand chien');
  });

  group('charge d\'entraînement', () {
    final base = [for (var d = 7; d < 28; d++) act(rex, d, 30)]; // charge 90 par jour

    test('forte hausse et repos après 2 jours de course', () {
      final l = ActivityInsights.load(rex.id, [
        ...base,
        for (var d = 2; d < 7; d++) act(rex, d, 40),
        act(rex, 1, 45, type: ActivityType.run),
        act(rex, 0, 45, type: ActivityType.run, hour: 8),
      ], now)!;
      expect(l.level, LoadLevel.spike);
      expect(l.ratio, greaterThan(1.5));
      expect((l.runStreak, l.ranToday, l.restAdvised), (2, true, true));
      final msg = ActivityInsights.loadMessages('Rex', l);
      expect(msg.first, matches(RegExp(r'^Rex : charge en forte hausse \(\+\d+ %\), risque de blessure, '
          r'prévoyez une journée calme\.$')));
      expect(msg.last, 'Rex a couru 2 jours d\'affilée : journée de repos conseillée demain.');
    });

    test('charge stable, baisse d\'activité, historique trop court', () {
      final steady = ActivityInsights.load(rex.id, [...base, for (var d = 0; d < 7; d++) act(rex, d, 30)], now)!;
      expect(steady.level, LoadLevel.normal);
      expect(ActivityInsights.loadMessages('Rex', steady), isEmpty);
      final drop = ActivityInsights.load(rex.id, base, now)!;
      expect(ActivityInsights.loadMessages('Rex', drop).single,
          'Rex : baisse d\'activité (−100 % par rapport aux 4 dernières semaines).');
      expect(ActivityInsights.load(rex.id, [act(rex, 10, 30), act(rex, 1, 30)], now), isNull);
      expect(ActivityInsights.loadOf(act(rex, 0, 30, type: ActivityType.run)), 210);
    });
  });

  group('durée conseillée : alertes', () {
    test('chien : pas assez, puis une journée excessive', () {
      final few = [for (var d = 0; d < 7; d++) act(rex, d, 30)];
      expect(ActivityInsights.durationAlerts(rex, few, now).single,
          'Rex : 30 min par jour en moyenne cette semaine (conseillé : 90 à 120 min pour un grand chien).');
      final excess = [for (var d = 0; d < 7; d++) act(rex, d, 100), act(rex, 1, 100, hour: 17)];
      expect(ActivityInsights.durationAlerts(rex, excess, now).single,
          'Rex : 3 h 20 le 05/11, bien au-delà des 2 h conseillées (grand chien).');
    });

    test('chat : 2 jours sans séance de jeu ; animal non suivi ignoré', () {
      expect(ActivityInsights.durationAlerts(mia, [act(mia, 2, 15, type: ActivityType.play)], now).single,
          'Mia : 2 jours sans séance de jeu.');
      expect(ActivityInsights.durationAlerts(mia, [act(mia, 0, 15, type: ActivityType.play)], now), isEmpty);
      expect(ActivityInsights.durationAlerts(rex, const [], now), isEmpty);
    });
  });

  group('bilan énergétique', () {
    final meals = [
      for (var d = 0; d < 10; d++)
        FeedingRecord(petId: 1, date: ago(d), foodType: FoodType.kibble, quantityG: 450, price: 2,
            kcalPer100g: 370),
    ];
    final walks = [for (var d = 0; d < 14; d++) act(rex, d, 60, kcal: 84)];

    test('apport, dépense, poids prévu, courbe réelle qui ne confirme pas', () {
      final b = ActivityInsights.energy(
        pet: rex,
        feeding: meals,
        activities: walks,
        health: [
          HealthRecord(petId: 1, type: HealthType.consultation, date: ago(68), weightKg: 27),
          HealthRecord(petId: 1, type: HealthType.consultation, date: ago(8), weightKg: 27.5),
        ],
        now: now,
      )!;
      expect((b.intakePerDay, b.activityPerDay, b.loggedDays), (1665, 84, 10));
      expect(b.maintenancePerDay, closeTo(1022.5, 0.1));
      expect(ActivityInsights.balanceSentence('Rex', b),
          'Rex : +559 kcal par jour en moyenne (apport 1665, dépense 1106).');
      expect(ActivityInsights.projectionSentence('Rex', b),
          'À ce rythme, Rex prendrait environ 2,2 kg par mois.');
      expect(b.realKgPerMonth, closeTo(0.25, 0.01));
      expect(ActivityInsights.realSentence(b),
          'Courbe réelle (pesées du 30/08 au 29/10) : +0,3 kg par mois, elle ne confirme pas la '
          'projection : vérifiez les quantités et les calories saisies.');
    });

    test('cohérent avec les pesées ; pas assez de repas saisis', () {
      final light = [
        for (var d = 0; d < 10; d++)
          FeedingRecord(petId: 1, date: ago(d), foodType: FoodType.kibble, quantityG: 300, price: 2,
              kcalPer100g: 370),
      ];
      final b = ActivityInsights.energy(pet: rex, feeding: light, activities: walks, health: [
        HealthRecord(petId: 1, type: HealthType.consultation, date: ago(68), weightKg: 28),
        HealthRecord(petId: 1, type: HealthType.consultation, date: ago(8), weightKg: 28),
      ], now: now)!;
      expect(ActivityInsights.projectionSentence('Rex', b), 'À ce rythme, le poids de Rex resterait stable.');
      expect(b.consistent, isTrue);
      expect(ActivityInsights.energy(pet: rex, feeding: meals.take(5), activities: walks,
          health: const [], now: now), isNull);
    });
  });

  group('records', () {
    final history = [
      act(rex, 20, 50, km: 4),
      act(rex, 12, 60, km: 5, hour: 18),
      act(rex, 5, 20, km: 3, type: ActivityType.run),
      act(rex, 3, 10, km: 0.5, type: ActivityType.run), // trop court pour la vitesse
    ];

    test('plus longue, plus rapide, semaine record, bilan de l\'année', () {
      final r = ActivityInsights.records(history, petId: 1, year: 2026);
      expect(r.longest!.distanceKm, 5);
      expect(r.fastest!.distanceKm, 3, reason: '9 km/h sur 3 km');
      expect(r.bestWeek!.km, 5);
      expect(ActivityInsights.yearSentence(r), '2026 : 12,5 km, 4 activités, 2 h 20.');
    });

    test('nouveau record seulement s\'il y a une sortie à battre', () {
      final added = Activity(id: 99, petId: 1, date: ago(0), type: ActivityType.walk,
          durationMin: 70, distanceKm: 6.2);
      expect(ActivityInsights.newRecords(history, added, 'Rex'),
          ['Nouveau record pour Rex : 6,2 km !', 'Semaine record pour Rex : 6,7 km !']);
      expect(ActivityInsights.newRecords(const [], added, 'Rex'), isEmpty);
      final fast = Activity(id: 100, petId: 1, date: ago(0), type: ActivityType.run,
          durationMin: 15, distanceKm: 3);
      expect(ActivityInsights.newRecords(history, fast, 'Rex'), contains('Nouveau record de vitesse pour Rex : 12 km/h !'));
    });

    test('le Controller notifie le record à l\'enregistrement', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final model = ActivitiesModel(clock: () => now);
      final notifier = FakeAchievements();
      final ctrl = ActivitiesController(
          model: model,
          repository: SqliteActivityRepository(db, clock: () => now),
          pets: const DemoPetDirectory(),
          recordNotifier: notifier);
      await ctrl.load();
      await ctrl.save(Activity(petId: 1, date: ago(3), type: ActivityType.walk, durationMin: 50, distanceKm: 4));
      expect(notifier.shown, isEmpty, reason: 'première sortie');
      await ctrl.save(Activity(petId: 1, date: ago(1), type: ActivityType.walk, durationMin: 70, distanceKm: 6.2));
      expect(notifier.shown.first, '🏆 Nouveau record pour Rex : 6,2 km !');
      expect(model.lastRecords[1], contains('Nouveau record pour Rex : 6,2 km !'));
    });
  });

  testWidgets('section Analyse : alertes en vue « Tous », détail de Rex', (tester) async {
    tester.view.physicalSize = const Size(412, 2000) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final model = ActivitiesModel(clock: () => now)
      ..setPets([rex, mia])
      ..setActivities([
        for (var d = 7; d < 28; d++) act(rex, d, 30, km: 2),
        act(rex, 1, 45, type: ActivityType.run, km: 6),
        act(rex, 0, 45, type: ActivityType.run, km: 6, hour: 8),
      ]);
    Widget app() => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: model),
            ChangeNotifierProvider.value(value: FeedingModel(clock: () => now)),
            ChangeNotifierProvider.value(value: HealthModel(clock: () => now)),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('fr', 'FR'),
            supportedLocales: const [Locale('fr', 'FR')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const Scaffold(body: SingleChildScrollView(child: ActivityInsightsSection())),
          ),
        );
    await tester.pumpWidget(app());
    expect(find.text('Analyse'), findsOneWidget);
    expect(find.text('Rex a couru 2 jours d\'affilée : journée de repos conseillée demain.'), findsOneWidget);
    expect(find.textContaining('Bilan de l\'année 2026 :'), findsOneWidget);

    model.setPetFilter(1);
    await tester.pumpAndSettle();
    expect(find.text('Analyse de Rex'), findsOneWidget);
    expect(find.text('Charge d\'entraînement'), findsOneWidget);
    expect(find.text('90 à 120 min par jour (grand chien (plus de 25 kg))'), findsOneWidget);
    expect(find.textContaining('Saisissez les repas d\'au moins 7 jours'), findsOneWidget);
    expect(find.text('Plus longue sortie'), findsOneWidget);
    expect(find.textContaining('6 km · 0'), findsOneWidget, reason: 'deux sorties de 6 km');
  });
}
