import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/controllers/reminders_controller.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/models/notifications/reminder_notifier.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminder_exception.dart';
import 'package:smart_pet/models/reminder_repository.dart';
import 'package:smart_pet/models/reminders_model.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';

import 'test_helpers.dart';

/// Repository dont chaque appel échoue (ex. base inaccessible).
class _BrokenRepository implements ReminderRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(Exception('base inaccessible'));
}

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late SqliteReminderRepository repo;
  late FakeNotifier notifier;
  late RemindersModel model;
  late RemindersController controller;

  RemindersController build(
          RemindersModel model, ReminderRepository repository) =>
      RemindersController(
        model: model,
        repository: repository,
        notifier: notifier,
        pets: const DemoPetDirectory(),
        refreshEvery: null,
      );

  setUp(() {
    db = memoryDatabase();
    clock = FakeClock(DateTime(2026, 10, 29, 14));
    repo = SqliteReminderRepository(db, clock: clock.call);
    notifier = FakeNotifier();
    model = RemindersModel(clock: clock.call);
    controller = build(model, repo);
  });

  tearDown(() async {
    controller.dispose();
    model.dispose();
    await db.close();
  });

  Future<Reminder> seed(String title, DateTime due,
          {int? petId = rexId,
          ReminderType type = ReminderType.deworming,
          ReminderRepeat repeat = ReminderRepeat.none}) =>
      repo.create(Reminder(
          petId: petId, title: title, type: type, dueDate: due, repeat: repeat));

  test('load : répartit les rappels et synchronise les notifications',
      () async {
    await seed('Vermifuge', DateTime(2026, 10, 30, 8));
    await seed('Antipuces', DateTime(2026, 10, 27, 19), petId: miaId);
    await seed('Contrôle', DateTime(2026, 11, 20, 9));

    await controller.load();

    expect(model.loading, isFalse);
    expect(model.upcoming.map((r) => r.title), ['Vermifuge', 'Contrôle']);
    expect(model.overdue.map((r) => r.title), ['Antipuces']);
    expect(model.upcomingSections.map((s) => s.$1.label),
        ['Demain', 'Ce mois-ci']);
    expect(model.stats.overdue, 1);
    expect(notifier.lastSync, hasLength(3));
    expect(notifier.lastPetNames[rexId], 'Rex');
  });

  test('erreur de chargement : message affichable', () async {
    final brokenModel = RemindersModel(clock: clock.call);
    final broken = build(brokenModel, _BrokenRepository());
    await broken.load();
    expect(brokenModel.loading, isFalse);
    expect(brokenModel.error, contains('base inaccessible'));
    broken.dispose();
    brokenModel.dispose();
  });

  test('filtres : animal, type, jour et recherche', () async {
    await seed('Vermifuge', DateTime(2026, 10, 30, 8));
    await seed('Vaccin', DateTime(2026, 11, 3, 9),
        petId: miaId, type: ReminderType.vaccination);
    await controller.load();

    controller.setPetFilter(miaId);
    expect(model.upcoming.map((r) => r.title), ['Vaccin']);
    controller.setPetFilter(null);

    controller.setTypeFilter(ReminderType.deworming);
    expect(model.upcoming.map((r) => r.title), ['Vermifuge']);
    controller.clearFilters();

    controller.setDayFilter(DateTime(2026, 11, 3));
    expect(model.upcoming.map((r) => r.title), ['Vaccin']);
    expect(model.typesOnDay(DateTime(2026, 10, 30)), [ReminderType.deworming]);
    controller.clearFilters();

    controller.setQuery('mia'); // recherche aussi sur le nom de l'animal
    expect(model.upcoming.map((r) => r.title), ['Vaccin']);
  });

  test('marquer fait (répété) puis annuler', () async {
    final r = await seed('Vermifuge', DateTime(2026, 10, 30, 8),
        repeat: ReminderRepeat.monthly);
    await controller.load();

    final result = await controller.markDone(r);
    expect(result.next!.dueDate, DateTime(2026, 11, 30, 8));
    expect(model.done.map((e) => e.id), [r.id]);
    expect(model.upcoming.map((e) => e.id), [result.next!.id]);

    await controller.undoDone(result);
    expect(model.done, isEmpty);
    expect(model.upcoming.map((e) => e.id), [r.id]);
  });

  test('T07 : reporter met à jour la liste et les notifications', () async {
    final r = await seed('Vermifuge', DateTime(2026, 10, 30, 8));
    await controller.load();
    final before = notifier.syncCount;

    await controller.postpone(r, DateTime(2026, 11, 2, 8));

    expect(model.upcoming.single.dueDate, DateTime(2026, 11, 2, 8));
    expect(model.upcoming.single.status, ReminderStatus.postponed);
    expect(notifier.syncCount, before + 1);
    expect(notifier.lastSync.single.dueDate, DateTime(2026, 11, 2, 8));
  });

  test('les erreurs d\'action remontent à la View', () async {
    final r = await seed('Vermifuge', DateTime(2026, 10, 30, 8));
    await controller.load();
    await expectLater(controller.postpone(r, DateTime(2026, 10, 1)),
        throwsA(isA<ReminderException>()));
  });

  test('notification « Fait » : marque fait et émet une intention', () async {
    final r = await seed('Vermifuge', DateTime(2026, 10, 30, 8));
    await controller.load();
    await controller.handleNotificationEvent(
        ReminderNotificationEvent(r.id!, NotificationAction.done));
    expect(model.done.single.id, r.id);
    expect(controller.intent.value?.action, NotificationAction.done);
  });

  test('démo : exemples chargés une seule fois', () async {
    await controller.load();
    expect(await controller.seedDemo(), 6);
    expect(await controller.seedDemo(), 0);
  });
}
