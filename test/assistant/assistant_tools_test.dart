import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/controllers/assistant_tools.dart';
import 'package:smart_pet/controllers/reminders_controller.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/models/activities_model.dart';
import 'package:smart_pet/models/activity.dart';
import 'package:smart_pet/models/feeding_model.dart';
import 'package:smart_pet/models/feeding_record.dart';
import 'package:smart_pet/models/health_model.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/pet.dart';
import 'package:smart_pet/models/pets_model.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminders_model.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';

import '../reminders/test_helpers.dart';

/// Tests unitaires des outils de l'assistant Gemini, sans appel réseau.
void main() {
  late AppDatabase db;
  late SqliteReminderRepository repo;
  late RemindersController reminders;
  late AssistantTools tools;
  final clock = FakeClock(DateTime(2026, 11, 4, 14)); // mercredi

  setUp(() async {
    db = memoryDatabase();
    repo = SqliteReminderRepository(db, clock: clock.call);
    reminders = RemindersController(
      model: RemindersModel(clock: clock.call),
      repository: repo,
      notifier: FakeNotifier(),
      pets: const DemoPetDirectory(),
      refreshEvery: null,
    );
    Future<void> add(String title, DateTime due, {int pet = rexId,
        ReminderRepeat repeat = ReminderRepeat.none}) async =>
        repo.create(Reminder(petId: pet, title: title, type: ReminderType.other,
            dueDate: due, repeat: repeat));
    await add('En retard', DateTime(2026, 11, 2, 9));
    await add('Ce soir', DateTime(2026, 11, 4, 20), repeat: ReminderRepeat.monthly);
    await add('Samedi', DateTime(2026, 11, 7, 9), pet: miaId);
    await add('Plus tard', DateTime(2026, 12, 20, 9));
    final done = await repo.create(Reminder(
        petId: rexId, title: 'Déjà fait', type: ReminderType.other,
        dueDate: DateTime(2026, 11, 1, 9)));
    await repo.markDone(done.id!);
    await reminders.load();

    tools = AssistantTools(
      reminders: reminders,
      pets: PetsModel(clock: clock.call)
        ..setPets([
          Pet(id: rexId, name: 'Rex', species: Species.dog, weightKg: 28),
          Pet(id: miaId, name: 'Mia', species: Species.cat),
        ]),
      health: HealthModel(clock: clock.call)
        ..setRecords([
          HealthRecord(petId: rexId, type: HealthType.consultation,
              date: DateTime(2026, 10, 1), cost: 40, weightKg: 28),
        ]),
      feeding: FeedingModel(clock: clock.call)
        ..setRecords([
          FeedingRecord(petId: miaId, date: DateTime(2026, 10, 10),
              foodType: FoodType.wet, quantityG: 100, price: 2),
        ]),
      activities: ActivitiesModel(clock: clock.call)
        ..setActivities([
          Activity(petId: rexId, date: DateTime(2026, 11, 3, 8),
              type: ActivityType.walk, durationMin: 40, distanceKm: 3),
          Activity(petId: rexId, date: DateTime(2026, 9, 1),
              type: ActivityType.walk, durationMin: 60, distanceKm: 5),
        ]),
    );
  });
  tearDown(() async {
    reminders.dispose();
    await db.close();
  });

  Future<List<String>> titles(String scope, [String? pet]) async {
    final res = await tools.run('get_reminders', {'scope': scope, 'pet_name': ?pet});
    return [for (final r in res.response['reminders'] as List) r['title'] as String];
  }

  test('déclarations : un outil par nom, paramètres décrits', () {
    final names = AssistantTools.declarations.map((d) => d['name']).toList();
    expect(names.toSet(), hasLength(names.length));
    expect(names, containsAll(['get_reminders', 'create_reminder', 'delete_reminder']));
    for (final d in AssistantTools.declarations) {
      expect((d['parameters'] as Map)['type'], 'OBJECT', reason: '${d['name']}');
    }
  });

  test('get_reminders : en retard, aujourd\'hui, semaine, à venir, historique',
      () async {
    expect(await titles('overdue'), ['En retard']);
    expect(await titles('today'), ['Ce soir']);
    expect(await titles('week'), ['Ce soir', 'Samedi']);
    expect(await titles('upcoming'), ['Ce soir', 'Samedi', 'Plus tard']);
    expect(await titles('done'), ['Déjà fait']);
    expect(await titles('upcoming', 'mia'), ['Samedi'], reason: 'nom sans majuscule');
    final res = await tools.run('get_reminders', {'scope': 'overdue'});
    expect((res.response['reminders'] as List).single['status'], 'overdue');
    expect(res.cards.single.title, 'En retard');
  });

  test('mark_reminder_done : rappel répété, occurrence suivante en carte', () async {
    final id = reminders.model.all.firstWhere((r) => r.title == 'Ce soir').id;
    final res = await tools.run('mark_reminder_done', {'reminder_id': id});
    expect((res.response['done'] as Map)['status'], 'done');
    expect((res.response['next_occurrence'] as Map)['date_time'], '2026-12-04T20:00');
    expect(res.cards.single.dueDate, DateTime(2026, 12, 4, 20));
  });

  test('postpone_reminder : nouvelle date ; id inconnu ; outil inconnu', () async {
    final id = reminders.model.all.firstWhere((r) => r.title == 'Samedi').id;
    final res = await tools.run(
        'postpone_reminder', {'reminder_id': id, 'new_date_time': '2026-11-09T10:30'});
    expect((res.response['postponed'] as Map)['date_time'], '2026-11-09T10:30');
    expect(reminders.model.byId(id)!.postponeCount, 1);

    final missing = await tools.run('mark_reminder_done', {'reminder_id': 999});
    expect(missing.response['error'], 'Rappel introuvable (id 999).');
    final unknown = await tools.run('send_email', {});
    expect(unknown.response['error'], 'Outil inconnu : send_email');
  });

  test('résumés : mois choisi, poids sans animal, périodes d\'activité', () async {
    final oct = (await tools.run('get_feeding_summary', {'month': '2026-10'})).response;
    expect((oct['month'], oct['quantity_g'], oct['spending_dt']), ('2026-10', 100, 2));

    final all = (await tools.run('get_health_summary', {})).response;
    expect(all['weight_note'], isNotNull, reason: 'tous les animaux mélangés');
    expect(all['average_weight_kg'], isNull);
    final rex = (await tools.run('get_health_summary', {'pet_name': 'Rex'})).response;
    expect(rex['average_weight_kg'], 28);

    Future<Object?> count(String period) async =>
        (await tools.run('get_activity_summary', {'period': period})).response['activities'];
    expect(await count('7_days'), 1);
    expect(await count('30_days'), 1);
    expect(await count('3_months'), 2);
    expect(await count('all'), 2);
  });
}
