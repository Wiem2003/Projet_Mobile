import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/controllers/dashboard_controller.dart';
import 'package:smart_pet/models/activity.dart';
import 'package:smart_pet/models/dashboard/cross_alerts.dart';
import 'package:smart_pet/models/dashboard/dashboard_model.dart';
import 'package:smart_pet/models/dashboard/dashboard_prefs.dart';
import 'package:smart_pet/models/dashboard/monthly_report.dart';
import 'package:smart_pet/models/dashboard/pet_costs.dart';
import 'package:smart_pet/models/dashboard/report_pdf.dart';
import 'package:smart_pet/models/dashboard/report_sharer.dart';
import 'package:smart_pet/models/dashboard/smart_pet_index.dart';
import 'package:smart_pet/models/feeding_record.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/pet.dart';
import 'package:smart_pet/models/reminder.dart';

import '../reminders/test_helpers.dart';

/// Partage simulé : garde ce qui aurait été envoyé.
class FakeSharer implements ReportSharer {
  String? subject, text, fileName;
  Uint8List? bytes;

  @override
  Future<void> shareText({required String subject, required String text}) async {
    this.subject = subject;
    this.text = text;
  }

  @override
  Future<void> sharePdf(
      {required String fileName, required String subject, required Uint8List bytes}) async {
    this.fileName = fileName;
    this.subject = subject;
    this.bytes = bytes;
  }
}

void main() {
  // Accès aux assets (police Roboto du PDF).
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 6, 14);
  final rex = Pet(id: 1, name: 'Rex', species: Species.dog, weightKg: 28);
  final mia = Pet(id: 2, name: 'Mia', species: Species.cat, weightKg: 4.5);
  final coco = Pet(id: 3, name: 'Coco', species: Species.bird);

  DateTime ago(int days, [int hour = 9]) => DateTime(now.year, now.month, now.day - days, hour);
  FeedingRecord meal(Pet p, DateTime d, {double g = 300, double price = 2}) =>
      FeedingRecord(petId: p.id!, date: d, foodType: FoodType.kibble, quantityG: g, price: price);
  Activity walk(Pet p, DateTime d, int min) =>
      Activity(petId: p.id!, date: d, type: ActivityType.walk, durationMin: min, distanceKm: 1);
  HealthRecord care(Pet p, DateTime d, {double? kg, double cost = 0, HealthType type = HealthType.consultation, String? med}) =>
      HealthRecord(petId: p.id!, type: type, date: d, weightKg: kg, cost: cost, medication: med);

  group('Indice Smart Pet', () {
    PetIndex index(Pet p, {List<Reminder> reminders = const [], List<Activity> activities = const [],
            List<HealthRecord> health = const [], List<FeedingRecord> feeding = const []}) =>
        SmartPetIndex.compute(p,
            reminders: reminders, activities: activities, health: health, feeding: feeding, now: now);

    test('chaque critère et ce qui fait baisser la note', () {
      final i = index(
        rex,
        reminders: [
          Reminder(petId: 1, title: 'Vaccin', type: ReminderType.vaccination, dueDate: ago(6)),
          Reminder(petId: 1, title: 'Achat', type: ReminderType.purchase, dueDate: ago(1)),
          Reminder(petId: 2, title: 'Autre animal', type: ReminderType.vaccination, dueDate: ago(9)),
        ],
        activities: [walk(rex, ago(1), 100), walk(rex, ago(3), 50), walk(rex, ago(9), 500)],
        health: [care(rex, ago(78), kg: 26), care(rex, ago(7), kg: 28)],
        feeding: [for (final d in [0, 1, 2, 4, 5]) meal(rex, ago(d)), meal(rex, ago(10))],
      );
      expect([for (final c in i.criteria) c.points], [10, 6, 12, 14], reason: 'grand chien : 630 min par semaine');
      expect(i.score, 42);
      expect(i.level, IndexLevel.low);
      expect(i.criteria[0].reason, '1 rappel critique et 1 rappel en retard');
      expect(i.criteria[1].reason, 'peu d\'activité (150 / 630 min)');
      expect(i.criteria[2].reason, 'poids +8 % en 2 mois');
      expect(i.deductions.first, '−20 : 1 rappel critique et 1 rappel en retard');
      expect(i.summary, startsWith('Rex : 42 (−20 : '));
    });

    test('tout va bien : 100 ; pas d\'objectif d\'activité pour un oiseau', () {
      final i = index(
        rex,
        activities: [walk(rex, ago(1), 640)],
        health: [care(rex, ago(70), kg: 28), care(rex, ago(5), kg: 28.5)],
        feeding: [for (var d = 0; d < 7; d++) meal(rex, ago(d))],
      );
      expect((i.score, i.level), (100, IndexLevel.good));
      expect(i.deductions, isEmpty);
      final bird = index(coco);
      expect(bird.criteria[1].points, 25);
      expect(bird.criteria[2].reason, 'aucune pesée depuis 2 mois');
      expect(index(mia, health: [care(mia, ago(10), kg: 4.5)]).criteria[2].points, 20,
          reason: 'une seule pesée');
    });
  });

  group('alertes croisées', () {
    List<CrossAlert> alerts({
      List<HealthRecord> health = const [],
      List<FeedingRecord> feeding = const [],
      List<Activity> activities = const [],
      Map<String, DateTime> dismissed = const {},
    }) =>
        CrossAlerts.compute(
            pets: [rex, mia], health: health, feeding: feeding, activities: activities,
            now: now, dismissedUntil: dismissed);

    test('mange plus et bouge moins : risque de prise de poids', () {
      final a = alerts(
        feeding: [
          for (var d = 31; d < 41; d++) meal(rex, ago(d), g: 300),
          for (var d = 0; d < 10; d++) meal(rex, ago(d), g: 400),
        ],
        activities: [walk(rex, ago(40), 600), walk(rex, ago(5), 300)],
      );
      expect(a.single.kind, AlertKind.weightGain);
      expect(a.single.message,
          'Rex mange plus (+33 %) et bouge moins (−50 %) sur 30 jours : risque de prise de poids.');
    });

    test('perte de poids et repas oubliés', () {
      final a = alerts(
        health: [care(mia, ago(78), kg: 5), care(mia, ago(7), kg: 4.5)],
        feeding: [meal(mia, ago(4)), meal(rex, ago(0))],
      );
      expect(a.map((x) => x.kind), [AlertKind.weightLoss, AlertKind.missingMeals]);
      expect(a.first.message, startsWith('Mia a perdu du poids (−10 % en 2 mois'));
      expect(a.last.message, 'Pensez à saisir les repas de Mia : aucun repas depuis 4 jours.');
    });

    test('dépense inhabituelle avec sa cause ; masquage de 30 jours', () {
      final health = [care(rex, ago(2), cost: 60, type: HealthType.vaccination)];
      final feeding = [
        for (final m in [8, 9, 10]) meal(rex, DateTime(2026, m, 15), price: 100),
        meal(rex, ago(0), price: 120),
      ];
      final a = alerts(health: health, feeding: feeding);
      final spending = a.singleWhere((x) => x.kind == AlertKind.unusualSpending);
      expect(spending.id, 'spending:2026-11');
      expect(spending.message,
          'Dépenses de novembre : 180 DT, +80 % par rapport à la moyenne des 3 mois '
          'précédents (100 DT), dont vaccination de Rex 60 DT.');
      expect(
          alerts(health: health, feeding: feeding, dismissed: {spending.id: now.add(const Duration(days: 1))})
              .where((x) => x.kind == AlertKind.unusualSpending),
          isEmpty);
      expect(
          alerts(health: health, feeding: feeding, dismissed: {spending.id: ago(1)})
              .where((x) => x.kind == AlertKind.unusualSpending),
          hasLength(1),
          reason: 'masquage expiré');
    });
  });

  test('coût de revient : mois, par jour, projection, comparaison', () {
    final report = CostReport.compute(
      pets: [rex, mia],
      health: [care(rex, ago(3), cost: 60, type: HealthType.vaccination)],
      feeding: [
        meal(rex, ago(1), price: 30),
        for (final m in [8, 9, 10]) ...[
          meal(rex, DateTime(2026, m, 10), price: 100),
          meal(mia, DateTime(2026, m, 10), price: 40),
        ],
      ],
      reminders: [
        Reminder(petId: 1, title: 'Rappel vaccin', type: ReminderType.vaccination,
            dueDate: DateTime(2027, 5, 3, 9)),
      ],
      now: now,
    );
    final r = report.pets.first;
    expect((r.pet.name, r.thisMonth, r.perDay), ('Rex', 90, 15));
    expect((r.monthlyAverage, r.plannedCare, r.annualProjection), (100, 60, 1260));
    expect(report.comparison!.sentence,
        'Rex coûte 2,5 fois plus que Mia, surtout en alimentation (3 derniers mois).');
  });

  group('rapport mensuel', () {
    final octobre = DateTime(2026, 10);
    MonthlyReport build() => MonthlyReport.compute(
          month: octobre,
          pets: [rex],
          health: [
            care(rex, DateTime(2026, 9, 20), kg: 27.5),
            care(rex, DateTime(2026, 10, 15), kg: 28, cost: 45, med: 'Otomax'),
          ],
          feeding: [meal(rex, DateTime(2026, 10, 2), price: 30), meal(rex, DateTime(2026, 11, 2), price: 99)],
          activities: [walk(rex, DateTime(2026, 10, 3, 8), 30), walk(rex, DateTime(2026, 10, 9, 8), 45)],
          reminders: [
            Reminder(petId: 1, title: 'A', type: ReminderType.deworming, dueDate: DateTime(2026, 10, 10, 9),
                status: ReminderStatus.done, completedAt: DateTime(2026, 10, 10, 10)),
            Reminder(petId: 1, title: 'B', type: ReminderType.deworming, dueDate: DateTime(2026, 10, 20, 9),
                status: ReminderStatus.done, completedAt: DateTime(2026, 10, 22, 10)),
            Reminder(petId: 1, title: 'C', type: ReminderType.checkup, dueDate: DateTime(2026, 10, 25, 9)),
            Reminder(title: 'Croquettes', type: ReminderType.purchase, dueDate: DateTime(2026, 10, 5, 18),
                status: ReminderStatus.done, completedAt: DateTime(2026, 10, 5, 19)),
          ],
          now: now,
        );

    test('dépenses, soins, rappels, activité, poids', () {
      final r = build();
      expect(MonthlyReport.previousMonth(now), octobre);
      expect((r.healthCost, r.feedingCost, r.total), (45, 30, 75));
      final p = r.pets.single;
      expect((p.onTime, p.late, p.missed), (1, 1, 1));
      expect((p.activities, p.minutes, p.km), (2, 75, 2));
      expect((p.weightStart, p.weightEnd, p.weightDelta), (27.5, 28, 0.5));
      expect(r.generalReminders.onTime, 1);
      final text = r.toText();
      expect(text, startsWith('Rapport Smart Pet - octobre 2026'));
      expect(text, contains('- 15/10 Consultation (Otomax) : 45 DT'));
      expect(text, contains('Rappels : 1 fait(s) à temps, 1 fait(s) en retard, 1 non fait(s)'));
      expect(text, contains('Poids : 28 kg (+0,5 kg sur le mois)'));
    });

    test('PDF généré', () async {
      final bytes = await ReportPdf.build(build());
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(String.fromCharCodes(bytes), contains('Roboto'),
          reason: 'police intégrée pour les accents');
    });
  });

  group('préférences et Controller', () {
    test('JSON, nettoyage des masquages expirés, base par compte', () async {
      final prefs = DashboardPrefs(
          dismissedUntil: {'a': now.add(const Duration(days: 2)), 'b': ago(1)}, lastReportSeen: '2026-10');
      final back = DashboardPrefs.fromJson(prefs.toJson());
      expect(back.lastReportSeen, '2026-10');
      expect(back.cleaned(now).dismissedUntil.keys, ['a']);

      final db = memoryDatabase();
      addTearDown(db.close);
      await SqliteDashboardPrefsStore(db, ownerId: 1).save(prefs);
      expect((await SqliteDashboardPrefsStore(db, ownerId: 1).load()).lastReportSeen, '2026-10');
      expect((await SqliteDashboardPrefsStore(db, ownerId: 2).load()).lastReportSeen, isNull);
    });

    test('masquer une alerte, rapport vu, partage texte et PDF', () async {
      final store = MemoryDashboardPrefsStore();
      final sharer = FakeSharer();
      final model = DashboardModel(clock: () => now);
      final ctrl = DashboardController(model: model, prefsStore: store, reportSharer: sharer);
      await ctrl.load();
      expect(model.reportReady, isTrue);
      await ctrl.markReportSeen();
      expect(model.reportReady, isFalse);
      expect(store.prefs.lastReportSeen, '2026-10');

      const alert = CrossAlert(id: 'meals:2', kind: AlertKind.missingMeals, message: 'x');
      await ctrl.dismiss(alert);
      expect(store.prefs.dismissedUntil['meals:2'], now.add(const Duration(days: 30)));
      expect(model.visible([alert]), isEmpty);

      final report = MonthlyReport.compute(
          month: DateTime(2026, 10), pets: [rex], health: const [], feeding: const [],
          activities: const [], reminders: const [], now: now);
      await ctrl.shareText(report);
      expect((sharer.subject, sharer.text!.split('\n').first),
          ('Rapport Smart Pet - octobre 2026', 'Rapport Smart Pet - octobre 2026'));
      await ctrl.sharePdf(report);
      expect(sharer.fileName, 'smart_pet_2026_10.pdf');
      expect(String.fromCharCodes(sharer.bytes!.take(4)), '%PDF');
      expect(model.sharing, isFalse);
    });
  });
}
