import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pet/core/database/app_database.dart';
import 'package:smart_pet/models/reminder.dart';
import 'package:smart_pet/models/reminder_exception.dart';
import 'package:smart_pet/models/reminder_repository.dart';
import 'package:smart_pet/models/sqlite_reminder_repository.dart';

import 'test_helpers.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late SqliteReminderRepository repo;

  setUp(() {
    db = memoryDatabase();
    clock = FakeClock(DateTime(2026, 10, 29, 14));
    repo = SqliteReminderRepository(db, clock: clock.call);
  });

  tearDown(() => db.close());

  Reminder draft({
    String title = 'Vermifuge',
    DateTime? due,
    int? petId = rexId,
    ReminderRepeat repeat = ReminderRepeat.none,
    String? notes,
  }) =>
      Reminder(
        petId: petId,
        title: title,
        type: ReminderType.deworming,
        dueDate: due ?? DateTime(2026, 10, 30, 8),
        repeat: repeat,
        notes: notes,
        alertOffsets: const [AlertOffset.tenDays, AlertOffset.atTime],
      );

  Matcher throwsReminder(bool Function(ReminderException e) test) =>
      throwsA(isA<ReminderException>().having(test, 'kind', isTrue));

  group('CRUD', () {
    test('création puis relecture identique', () async {
      final saved =
          await repo.create(draft(title: '  Vermifuge ', notes: '   '));
      expect(saved.id, isNotNull);
      final read = await repo.getById(saved.id!);
      expect(read.title, 'Vermifuge');
      expect(read.notes, isNull);
      expect(read.dueDate, DateTime(2026, 10, 30, 8));
      expect(read.alertOffsets, [AlertOffset.atTime, AlertOffset.tenDays]);
      expect(read.status, ReminderStatus.upcoming);
      expect(read.source, ReminderSource.manual);
      expect(read.createdAt, clock.now);
    });

    test('T02 : titre obligatoire', () async {
      await expectLater(repo.create(draft(title: '  ')),
          throwsA(isA<ReminderException>().having(
              (e) => e.message, 'message', 'Le titre est obligatoire.')));
      expect(await repo.getAll(), isEmpty);
    });

    test('doublon refusé (casse ignorée) ; autre animal accepté', () async {
      await repo.create(draft());
      await expectLater(
          repo.create(draft(title: 'VERMIFUGE')), throwsReminder((e) => e.isConflict));
      await repo.create(draft(petId: miaId));
      expect(await repo.getAll(), hasLength(2));
    });

    test('liste triée par date et filtrée par animal', () async {
      await repo.create(draft(title: 'B', due: DateTime(2026, 11, 5)));
      await repo.create(draft(title: 'A'));
      await repo.create(draft(title: 'C', petId: miaId));
      expect((await repo.getAll()).map((r) => r.title), ['A', 'C', 'B']);
      expect((await repo.getAll(petId: rexId)).map((r) => r.title), ['A', 'B']);
    });

    test('modifier la date d\'un rappel reporté le remet « à venir »',
        () async {
      final r = await repo.create(draft());
      final postponed = await repo.postpone(r.id!, DateTime(2026, 11, 2, 8));
      final saved = await repo
          .update(postponed.copyWith(dueDate: DateTime(2026, 11, 10, 8)));
      expect(saved.status, ReminderStatus.upcoming);
    });

    test('suppression puis introuvable', () async {
      final r = await repo.create(draft());
      await repo.delete(r.id!);
      await expectLater(repo.getById(r.id!), throwsReminder((e) => e.isNotFound));
    });
  });

  group('T07 — reporter', () {
    test('date, statut et compteur mis à jour', () async {
      final r = await repo.create(draft());
      final saved = await repo.postpone(r.id!, DateTime(2026, 11, 2, 8));
      expect(saved.dueDate, DateTime(2026, 11, 2, 8));
      expect(saved.status, ReminderStatus.postponed);
      expect(saved.postponeCount, 1);
      expect((await repo.getById(r.id!)).dueDate, DateTime(2026, 11, 2, 8));
    });

    test('date passée refusée', () async {
      final r = await repo.create(draft());
      await expectLater(repo.postpone(r.id!, DateTime(2026, 10, 1)),
          throwsA(isA<ReminderException>()));
    });
  });

  group('marquer fait', () {
    test('rappel simple', () async {
      final r = await repo.create(draft());
      final result = await repo.markDone(r.id!);
      expect(result.done.isDone, isTrue);
      expect(result.done.completedAt, clock.now);
      expect(result.next, isNull);
    });

    test('mensuel : occurrence suivante au dernier jour du mois', () async {
      final r = await repo.create(
          draft(due: DateTime(2026, 10, 31, 8), repeat: ReminderRepeat.monthly));
      final result = await repo.markDone(r.id!);
      expect(result.next!.dueDate, DateTime(2026, 11, 30, 8));
      expect(result.next!.status, ReminderStatus.upcoming);
      expect(await repo.getAll(), hasLength(2));
    });

    test('annuel très en retard : saute les occurrences passées', () async {
      final r = await repo.create(
          draft(due: DateTime(2024, 3, 1, 8), repeat: ReminderRepeat.yearly));
      final result = await repo.markDone(r.id!);
      expect(result.next!.dueDate, DateTime(2027, 3, 1, 8));
    });

    test('annuler : rappel rouvert et occurrence suivante supprimée',
        () async {
      final r = await repo.create(draft(repeat: ReminderRepeat.weekly));
      final result = await repo.markDone(r.id!);
      final reopened = await repo.reopen(r.id!, removeNextId: result.next!.id);
      expect(reopened.status, ReminderStatus.upcoming);
      expect(reopened.completedAt, isNull);
      expect(await repo.getAll(), hasLength(1));
    });
  });

  group('T04 — synchronisation depuis le module Santé', () {
    Future<(SyncOutcome, Reminder?)> sync(DateTime? due) => repo.syncFromSource(
          source: ReminderSource.health,
          sourceId: 42,
          petId: rexId,
          type: ReminderType.vaccination,
          title: 'Rappel vaccin rage',
          dueDate: due,
        );

    test('deux synchronisations identiques = un seul rappel', () async {
      final (first, created) = await sync(DateTime(2026, 11, 15, 9));
      final (second, _) = await sync(DateTime(2026, 11, 15, 9));
      expect(first, SyncOutcome.created);
      expect(second, SyncOutcome.unchanged);
      expect(created!.alertOffsets, contains(AlertOffset.tenDays));
      expect(await repo.getAll(), hasLength(1));
    });

    test('échéance modifiée : même rappel mis à jour', () async {
      final (_, created) = await sync(DateTime(2026, 11, 15, 9));
      final (outcome, updated) = await sync(DateTime(2026, 12, 1, 9));
      expect(outcome, SyncOutcome.updated);
      expect(updated!.id, created!.id);
      expect(await repo.getAll(), hasLength(1));
    });

    test('échéance retirée : rappel supprimé', () async {
      await sync(DateTime(2026, 11, 15, 9));
      expect((await sync(null)).$1, SyncOutcome.removed);
      expect(await repo.getAll(), isEmpty);
    });

    test('échéance déjà faite : pas recréée', () async {
      final (_, created) = await sync(DateTime(2026, 11, 15, 9));
      await repo.markDone(created!.id!);
      expect((await sync(DateTime(2026, 11, 15, 9))).$1, SyncOutcome.unchanged);
      expect(await repo.getAll(), hasLength(1));
    });

    test('l\'index unique bloque un doublon inséré directement', () async {
      await sync(DateTime(2026, 11, 15, 9));
      final database = await db.database;
      await expectLater(
        database.insert('reminders', Reminder(
          title: 'x',
          type: ReminderType.vaccination,
          dueDate: DateTime(2026, 11, 15, 9),
          source: ReminderSource.health,
          sourceId: 42,
        ).toMap()),
        throwsA(anything),
      );
    });
  });

  test('suppressions groupées par source et par animal', () async {
    await repo.create(draft());
    await repo.create(draft(petId: miaId));
    await repo.syncFromSource(
        source: ReminderSource.health,
        sourceId: 42,
        petId: miaId,
        dueDate: DateTime(2026, 11, 15));

    expect(await repo.deleteBySource(ReminderSource.health, 42), hasLength(1));
    expect(await repo.deleteByPet(rexId), hasLength(1));
    expect(await repo.getAll(), hasLength(1));
  });
}
