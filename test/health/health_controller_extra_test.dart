import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/controllers/health_controller.dart';
import 'package:smart_pet/controllers/health_form_controller.dart';
import 'package:smart_pet/controllers/reminders_controller.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/core/pets/pet_directory.dart';
import 'package:smart_pet/models/health_model.dart';
import 'package:smart_pet/models/health_record.dart';
import 'package:smart_pet/models/health_repository.dart';
import 'package:smart_pet/models/health_stats.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminders_model.dart';
import 'package:smart_pet/models/sqlite_health_repository.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';
import 'package:smart_pet/models/validation.dart';

import '../reminders/test_helpers.dart';

/// Base inaccessible : toute lecture échoue.
class _BrokenHealthRepository implements HealthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(Exception('base inaccessible'));
}

/// Enregistrement refusé par la base (ex. contrainte).
class _RejectingHealthRepository implements HealthRepository {
  @override
  Future<List<HealthRecord>> getAll({int? petId}) async => const [];

  @override
  Future<HealthRecord> create(HealthRecord record) async =>
      throw const RecordException('Refusé par la base.');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  final clock = FakeClock(DateTime(2026, 11, 4, 14));

  group('HealthController', () {
    late AppDatabase db;
    late HealthController health;
    late RemindersController reminders;
    late List<(int, double)> weighings;

    setUp(() async {
      db = memoryDatabase();
      reminders = RemindersController(
        model: RemindersModel(clock: clock.call),
        repository: SqliteReminderRepository(db, clock: clock.call),
        notifier: FakeNotifier(),
        pets: const DemoPetDirectory(),
        refreshEvery: null,
      );
      await reminders.load();
      weighings = [];
      health = HealthController(
        model: HealthModel(clock: clock.call),
        repository: SqliteHealthRepository(db, clock: clock.call),
        pets: const DemoPetDirectory(),
        reminders: reminders,
        onWeightMeasured: (pet, kg) async => weighings.add((pet, kg)),
      );
      await health.load();
    });
    tearDown(() async {
      reminders.dispose();
      await db.close();
    });

    test('filtres transmis au Model', () {
      health
        ..setPetFilter(miaId)
        ..setTypeFilter(HealthType.analysis)
        ..setPeriod(HealthPeriod.all);
      expect((health.model.petFilter, health.model.typeFilter, health.model.period),
          (miaId, HealthType.analysis, HealthPeriod.all));
    });

    test('dossier déplacé vers un autre animal : rappel et poids suivent',
        () async {
      await health.save(HealthRecord(
          petId: rexId, type: HealthType.consultation, date: DateTime(2026, 9, 1), weightKg: 27.5));
      final moved = await health.save(HealthRecord(
          petId: rexId,
          type: HealthType.vaccination,
          date: DateTime(2026, 11, 1),
          weightKg: 28,
          nextDue: DateTime(2027, 11, 1)));
      expect(reminders.model.all.single.petId, rexId);

      weighings.clear();
      await health.save(moved.copyWith(petId: miaId, weightKg: () => 4.6));
      final r = reminders.model.all.single;
      expect((r.petId, r.sourceId, r.type), (miaId, moved.id, ReminderType.vaccination));
      // Mia prend la nouvelle pesée, Rex retrouve sa pesée précédente.
      expect(weighings, [(miaId, 4.6), (rexId, 27.5)]);
    });

    test('changer le type : l\'échéance passe au nouveau type', () async {
      final r = await health.save(HealthRecord(
          petId: rexId,
          type: HealthType.vaccination,
          date: DateTime(2026, 11, 1),
          nextDue: DateTime(2027, 5, 1)));
      await health.save(r.copyWith(type: HealthType.dental));
      expect(reminders.model.all.single.type, ReminderType.checkup);
    });

    test('sans module Rappels branché : enregistrement normal', () async {
      final alone = HealthController(
        model: HealthModel(clock: clock.call),
        repository: SqliteHealthRepository(db, clock: clock.call),
        pets: const DemoPetDirectory(),
      );
      await alone.load();
      final saved = await alone.save(HealthRecord(
          petId: rexId, type: HealthType.vaccination, date: DateTime(2026, 11, 1),
          nextDue: DateTime(2027, 11, 1)));
      expect(alone.model.byId(saved.id), isNotNull);
      await alone.delete(saved);
      expect(alone.model.isEmpty, isTrue);
    });
  });

  test('base inaccessible : message d\'erreur dans le Model', () async {
    final model = HealthModel(clock: clock.call);
    await HealthController(
            model: model,
            repository: _BrokenHealthRepository(),
            pets: const DemoPetDirectory())
        .load();
    expect(model.loading, isFalse);
    expect(model.error, contains('base inaccessible'));
  });

  test('formulaire : erreur de la base affichée, champs texte', () async {
    final health = HealthController(
        model: HealthModel(clock: clock.call),
        repository: _RejectingHealthRepository(),
        pets: const DemoPetDirectory());
    await health.load();
    final form = HealthFormController(health)
      ..setPet(miaId)
      ..setDay(DateTime(2026, 10, 30, 18))
      ..setDescription('Contrôle annuel')
      ..setNextDue(DateTime(2027, 10, 30, 7));
    expect((form.model.petId, form.model.day, form.model.nextDue),
        (miaId, DateTime(2026, 10, 30), DateTime(2027, 10, 30)));
    expect(form.model.buildRecord().description, 'Contrôle annuel');
    expect(await form.save(), isNull);
    expect(form.model.error, 'Refusé par la base.');
    expect(form.model.saving, isFalse);
    form.dispose();
  });
}
