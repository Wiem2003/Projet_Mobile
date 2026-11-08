import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/controllers/reminder_form_controller.dart';
import 'package:smart_pet/controllers/reminders_controller.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminder_form_model.dart';
import 'package:smart_pet/models/reminders_model.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';

import 'test_helpers.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late SqliteReminderRepository repo;
  late RemindersController list;

  setUp(() async {
    db = memoryDatabase();
    clock = FakeClock(DateTime(2026, 10, 29, 14));
    repo = SqliteReminderRepository(db, clock: clock.call);
    list = RemindersController(
      model: RemindersModel(clock: clock.call),
      repository: repo,
      notifier: FakeNotifier(),
      pets: const DemoPetDirectory(),
      refreshEvery: null,
    );
    await list.load();
  });

  tearDown(() async {
    list.dispose();
    list.model.dispose();
    await db.close();
  });

  test('valeurs par défaut : demain 9 h, alertes J-1 + jour J', () {
    final vm = ReminderFormController(list);
    expect(vm.model.isEdit, isFalse);
    expect(vm.model.dueDate, DateTime(2026, 10, 30, 9));
    expect(vm.model.offsets, {AlertOffset.oneDay, AlertOffset.atTime});
    expect(vm.model.title, 'Vaccination');
  });

  test('le titre suit le type tant qu\'il n\'est pas personnalisé', () {
    final vm = ReminderFormController(list);
    vm.selectType(ReminderType.deworming);
    expect(vm.model.title, 'Vermifuge');
    vm.setTitle('Milbemax');
    vm.selectType(ReminderType.treatment);
    expect(vm.model.title, 'Milbemax');
  });

  test('vaccin : répétition annuelle proposée', () {
    final vm = ReminderFormController(list)
      ..selectType(ReminderType.deworming)
      ..selectType(ReminderType.vaccination);
    expect(vm.model.repeat, ReminderRepeat.yearly);
  });

  test('T02 : titre vide => enregistrement bloqué', () async {
    final vm = ReminderFormController(list)..setTitle('   ');
    expect(await vm.save(), isNull);
    expect(vm.model.error, 'Le titre est obligatoire');
    expect(await repo.getAll(), isEmpty);
    expect(ReminderFormModel.validateTitle('a' * 81), isNotNull);
  });

  test('date passée refusée', () async {
    final vm = ReminderFormController(list)
      ..setDay(DateTime(2026, 10, 29))
      ..setTime(8, 0);
    expect(await vm.save(), isNull);
    expect(vm.model.error, contains('futur'));
  });

  test('aperçu des notifications', () {
    final vm = ReminderFormController(list)
      ..setDay(DateTime(2026, 11, 3))
      ..toggleOffset(AlertOffset.tenDays, true);
    expect(vm.model.alertSchedule.map((a) => a.offset.shortLabel),
        ['J-10', 'J-1', 'Jour J']);
    expect(vm.model.pendingAlertCount, 2, reason: 'J-10 (24/10) est déjà passé');
    vm.setRepeat(ReminderRepeat.monthly);
    expect(vm.model.nextOccurrence, DateTime(2026, 12, 3, 9));
  });

  test('création puis doublon : message d\'erreur affiché', () async {
    final vm = ReminderFormController(list)..setNotes('  ');
    final saved = await vm.save();
    expect(saved, isNotNull);
    expect(saved!.notes, isNull);
    expect(list.model.upcoming, hasLength(1));

    final again = ReminderFormController(list);
    expect(await again.save(), isNull);
    expect(again.model.error, contains('identique'));
    expect(again.model.saving, isFalse);
  });

  test('modification : conserve l\'identifiant', () async {
    final created = await ReminderFormController(list).save();
    final vm = ReminderFormController(list, initial: created)
      ..setTitle('Rappel vaccin rage');
    expect(vm.model.isEdit, isTrue);
    final saved = await vm.save();
    expect(saved!.id, created!.id);
    expect(list.model.upcoming.single.title, 'Rappel vaccin rage');
  });
}
