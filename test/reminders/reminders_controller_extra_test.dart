import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/controllers/reminders_controller.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/models/notifications/reminder_notifier.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminder_repository.dart';
import 'package:smart_pet/models/reminders_model.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';

import 'test_helpers.dart';

/// Tests unitaires du RemindersController : notifications, échéances des
/// autres modules, démonstration.
void main() {
  late AppDatabase db;
  late SqliteReminderRepository repo;
  late RemindersModel model;
  late RemindersController controller;
  late FakeNotifier notifier;
  late StreamController<ReminderNotificationEvent> events;
  final clock = FakeClock(DateTime(2026, 11, 4, 14));

  setUp(() async {
    db = memoryDatabase();
    repo = SqliteReminderRepository(db, clock: clock.call);
    model = RemindersModel(clock: clock.call);
    notifier = FakeNotifier();
    events = StreamController<ReminderNotificationEvent>();
    controller = RemindersController(
      model: model,
      repository: repo,
      notifier: notifier,
      pets: const DemoPetDirectory(),
      notificationEvents: events.stream,
      refreshEvery: null,
    );
    await controller.load();
  });
  tearDown(() async {
    controller.dispose();
    await events.close();
    model.dispose();
    await db.close();
  });

  Future<Reminder> add(String title, DateTime due) async {
    final r = await controller.save(Reminder(
        petId: rexId, title: title, type: ReminderType.deworming, dueDate: due));
    return r;
  }

  test('notification « Fait » : marque fait et ouvre le rappel', () async {
    final r = await add('Vermifuge', DateTime(2026, 11, 5, 8));
    await controller.handleNotificationEvent(
        ReminderNotificationEvent(r.id!, NotificationAction.done));
    expect(model.byId(r.id)!.isDone, isTrue);
    expect(controller.intent.value!.action, NotificationAction.done);
    expect(notifier.lastSync.where((x) => x.id == r.id).single.isDone, isTrue,
        reason: 'notifications reprogrammées');
  });

  test('notification reçue par le flux d\'événements : ouverture', () async {
    final r = await add('Antipuces', DateTime(2026, 11, 6, 19));
    events.add(ReminderNotificationEvent(r.id!, NotificationAction.postpone));
    await pumpEventQueue();
    expect(controller.intent.value!.reminder.id, r.id);
    expect(controller.intent.value!.action, NotificationAction.postpone);
    expect(model.byId(r.id)!.isDone, isFalse);
  });

  test('notification d\'un rappel supprimé entre-temps : ignorée', () async {
    final r = await add('Vermifuge', DateTime(2026, 11, 5, 8));
    await controller.delete(r);
    await controller.handleNotificationEvent(
        ReminderNotificationEvent(r.id!, NotificationAction.open));
    expect(controller.intent.value, isNull);
  });

  test('autorisation et notification de test transmises au notifier', () async {
    expect(await controller.requestNotificationPermission(), isTrue);
    await controller.sendTestNotification();
    expect((notifier.permissionRequests, notifier.testsShown), (1, 1));
  });

  test('échéance d\'un autre module : création, mise à jour, suppression',
      () async {
    Future<SyncOutcome> sync(DateTime? due) => controller.syncDeadline(
          source: ReminderSource.health,
          sourceId: 10,
          dueDate: due,
          petId: rexId,
          type: ReminderType.vaccination,
          title: 'Rappel vaccin',
        );
    expect(await sync(DateTime(2027, 1, 10, 9)), SyncOutcome.created);
    expect(await sync(DateTime(2027, 1, 10, 9)), SyncOutcome.unchanged);
    expect(await sync(DateTime(2027, 2, 1, 9)), SyncOutcome.updated);
    expect(model.all.single.dueDate, DateTime(2027, 2, 1, 9));
    expect(model.all.single.isAutomatic, isTrue);
    expect(await sync(null), SyncOutcome.removed);
    expect(model.all, isEmpty);

    await sync(DateTime(2027, 3, 1, 9));
    await controller.removeDeadlines(ReminderSource.health, 10);
    expect(model.all, isEmpty);
  });

  test('démonstration Santé : une seule échéance, jamais de doublon', () async {
    expect(await controller.simulateHealthDeadline(DateTime(2026, 12, 1, 9)),
        SyncOutcome.created);
    expect(await controller.simulateHealthDeadline(DateTime(2026, 12, 8, 9)),
        SyncOutcome.updated);
    final demo = model.all.where(
        (r) => r.sourceId == RemindersController.demoHealthRecordId);
    expect(demo.single.dueDate, DateTime(2026, 12, 8, 9));
    expect(RemindersController.demoHealthRecordId, isNegative,
        reason: 'ne peut pas être l\'id d\'un vrai dossier');
  });

  test('actualisation périodique : le Model recalcule « en retard »', () async {
    final m = RemindersModel(clock: clock.call);
    final ticking = RemindersController(
      model: m,
      repository: repo,
      notifier: notifier,
      pets: const DemoPetDirectory(),
      refreshEvery: const Duration(milliseconds: 10),
    );
    var refreshed = 0;
    m.addListener(() => refreshed++);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(refreshed, 0, reason: 'aucun rappel : rien à redessiner');

    m.setReminders([
      Reminder(id: 1, title: 'X', type: ReminderType.other, dueDate: DateTime(2026, 11, 5)),
    ]);
    refreshed = 0;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(refreshed, greaterThan(1));
    ticking.dispose();
    final after = refreshed;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(refreshed, after, reason: 'minuterie arrêtée par dispose()');
    m.dispose();
  });
}
