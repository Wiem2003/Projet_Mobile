import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/controllers/health_controller.dart';
import 'package:smart_pet/controllers/health_form_controller.dart';
import 'package:smart_pet/controllers/reminders_controller.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/models/health_model.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminders_model.dart';
import 'package:smart_pet/models/sqlite_health_repository.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';

import '../reminders/test_helpers.dart';

void main() {
  late AppDatabase db;
  late HealthModel model;
  late HealthController health;
  late RemindersModel remindersModel;
  late RemindersController reminders;
  late List<(int, double)> weighings;
  final clock = FakeClock(DateTime(2026, 11, 3, 14));

  setUp(() async {
    db = memoryDatabase();
    remindersModel = RemindersModel(clock: clock.call);
    reminders = RemindersController(
      model: remindersModel,
      repository: SqliteReminderRepository(db, clock: clock.call),
      notifier: FakeNotifier(),
      pets: const DemoPetDirectory(),
      refreshEvery: null,
    );
    weighings = [];
    model = HealthModel(clock: clock.call);
    health = HealthController(
      model: model,
      repository: SqliteHealthRepository(db, clock: clock.call),
      pets: const DemoPetDirectory(),
      reminders: reminders,
      onWeightMeasured: (pet, kg) async => weighings.add((pet, kg)),
    );
    await reminders.load();
    await health.load();
  });
  tearDown(() async {
    reminders.dispose();
    remindersModel.dispose();
    model.dispose();
    await db.close();
  });

  List<Reminder> healthReminders() => remindersModel.all
      .where((r) => r.source == ReminderSource.health)
      .toList();

  test('prochaine échéance => rappel automatique, pesée => poids de l\'animal',
      () async {
    final vaccine = await health.save(HealthRecord(
      petId: rexId,
      type: HealthType.vaccination,
      date: DateTime(2026, 11, 2),
      medication: 'CHPPi',
      cost: 60,
      weightKg: 28.4,
      nextDue: DateTime(2027, 11, 2),
    ));
    final r = healthReminders().single;
    expect(r.sourceId, vaccine.id);
    expect(r.petId, rexId);
    expect(r.type, ReminderType.vaccination);
    expect(r.title, 'Vaccination : CHPPi');
    expect(r.dueDate, DateTime(2027, 11, 2, 9));
    expect(weighings, [(rexId, 28.4)]);

    // Échéance modifiée puis retirée.
    await health.save(vaccine.copyWith(nextDue: () => DateTime(2027, 10, 1)));
    expect(healthReminders().single.dueDate, DateTime(2027, 10, 1, 9));
    await health.save(vaccine.copyWith(nextDue: () => null));
    expect(healthReminders(), isEmpty);
  });

  test('un vaccin refait remplace le rappel du précédent', () async {
    final old = await health.save(HealthRecord(
        petId: rexId,
        type: HealthType.vaccination,
        date: DateTime(2025, 11, 1),
        nextDue: DateTime(2026, 11, 1))); // En retard.
    expect(healthReminders().single.sourceId, old.id);

    final renewed = await health.save(HealthRecord(
        petId: rexId,
        type: HealthType.vaccination,
        date: DateTime(2026, 11, 2),
        nextDue: DateTime(2027, 11, 2)));
    expect(healthReminders().map((r) => r.sourceId), [renewed.id]);

    // Un autre type ou un autre animal garde son propre rappel.
    await health.save(HealthRecord(
        petId: miaId,
        type: HealthType.vaccination,
        date: DateTime(2026, 10, 1),
        nextDue: DateTime(2027, 10, 1)));
    await health.save(HealthRecord(
        petId: rexId,
        type: HealthType.treatment,
        date: DateTime(2026, 10, 1),
        nextDue: DateTime(2026, 12, 1)));
    expect(healthReminders(), hasLength(3));

    // Supprimer le plus récent redonne l'échéance au précédent.
    await health.delete(renewed);
    expect(healthReminders().map((r) => r.sourceId), contains(old.id));
    expect(healthReminders(), hasLength(3));
  });

  test('suppression : rappel retiré, poids repris de la pesée précédente',
      () async {
    await health.save(HealthRecord(
        petId: rexId,
        type: HealthType.consultation,
        date: DateTime(2026, 9, 1),
        weightKg: 27.5));
    final last = await health.save(HealthRecord(
        petId: rexId,
        type: HealthType.analysis,
        date: DateTime(2026, 11, 1),
        weightKg: 28.2,
        nextDue: DateTime(2027, 5, 1)));
    expect(weighings.last, (rexId, 28.2));
    expect(healthReminders(), hasLength(1));

    await health.delete(last);
    expect(healthReminders(), isEmpty);
    expect(weighings.last, (rexId, 27.5));
  });

  test('formulaire : validation et échéances proposées', () async {
    final form = HealthFormController(health)
      ..setType(HealthType.vaccination)
      ..setDay(DateTime(2026, 10, 15));
    expect(form.model.petId, rexId);
    expect(form.model.quickNextDue.map((q) => q.$2),
        [DateTime(2026, 11, 15), DateTime(2027, 10, 15), DateTime(2029, 10, 15)]);

    form.setNextDue(DateTime(2026, 10, 1));
    expect(await form.save(), isNull);
    expect(form.model.error, contains('postérieure'));

    form
      ..setNextDue(form.model.quickNextDue.last.$2)
      ..setWeight('abc');
    expect(await form.save(), isNull);
    expect(form.model.error, 'Poids invalide');

    form
      ..setWeight('28,5')
      ..setCost('')
      ..setVet('  Dr Ben Salah ')
      ..setMedication('Rage');
    final saved = await form.save();
    expect((saved!.cost, saved.weightKg, saved.vet), (0, 28.5, 'Dr Ben Salah'));
    expect(healthReminders().single.title, 'Vaccination : Rage');
    form.dispose();
  });

  test('exemples : 9 dossiers, 6 échéances dans les rappels, sans doublon',
      () async {
    expect(await health.seedDemo(), 9);
    expect(healthReminders(), hasLength(6));
    expect(weighings, containsAll([(rexId, 28.1), (miaId, 4.5)]));
    expect(await health.seedDemo(), 0);
    expect(healthReminders(), hasLength(6));

    model.setPetFilter(rexId);
    expect(model.stats.consultations, 2);
    expect(model.stats.weights, hasLength(5));
  });
}
