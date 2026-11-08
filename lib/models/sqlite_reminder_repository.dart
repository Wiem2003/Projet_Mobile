import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import 'reminder.dart';
import 'reminder_calculator.dart';
import 'reminder_exception.dart';
import 'reminder_repository.dart';
import 'reminder_rules.dart';

/// Implémentation SQLite (table `reminders`) avec les règles métier.
class SqliteReminderRepository implements ReminderRepository {
  SqliteReminderRepository(this._appDb, {DateTime Function()? clock, this.ownerId})
      : _clock = clock ?? DateTime.now;

  static const _table = 'reminders';
  static const maxTitleLength = 80;

  final AppDatabase _appDb;
  final DateTime Function() _clock;

  /// Compte connecté : seuls ses rappels sont visibles et les nouveaux lui
  /// appartiennent (`null` : tous, utilisé par les tests).
  final int? ownerId;

  String get _mine => ownerId == null ? '' : ' AND user_id = $ownerId';

  Future<Database> get _db => _appDb.database;

  // ---------------------------------------------------------------- Lecture

  @override
  Future<List<Reminder>> getAll({int? petId}) async {
    final rows = await (await _db).query(
      _table,
      where: '${petId == null ? '1 = 1' : 'pet_id = ?'}$_mine',
      whereArgs: petId == null ? null : [petId],
      orderBy: 'due_date ASC',
    );
    return rows.map(Reminder.fromMap).toList();
  }

  @override
  Future<Reminder> getById(int id) => _find(id, null);

  Future<Reminder> _find(int id, DatabaseExecutor? txn) async {
    final rows =
        await (txn ?? await _db).query(_table, where: 'id = ?$_mine', whereArgs: [id]);
    if (rows.isEmpty) throw const ReminderException.notFound();
    return Reminder.fromMap(rows.first);
  }

  // ------------------------------------------------------------------- CRUD

  @override
  Future<Reminder> create(Reminder reminder) async {
    final now = _clock();
    final clean = _validate(reminder).copyWith(
      status: ReminderStatus.upcoming,
      source: ReminderSource.manual,
      sourceId: () => null,
      createdAt: now,
      updatedAt: now,
    );
    final db = await _db;
    await _assertNotDuplicate(db, clean);
    return _insert(db, clean);
  }

  @override
  Future<Reminder> update(Reminder reminder) async {
    final db = await _db;
    final current = await _find(reminder.id!, db);
    var clean = _validate(reminder).copyWith(updatedAt: _clock());
    // Nouvelle date sur un rappel non terminé : il redevient « à venir ».
    if (clean.dueDate != current.dueDate && !current.isDone) {
      clean = clean.copyWith(status: ReminderStatus.upcoming);
    }
    await _assertNotDuplicate(db, clean);
    await _guardUnique(() => db.update(_table, clean.toMap(),
        where: 'id = ?', whereArgs: [clean.id]));
    return clean;
  }

  @override
  Future<void> delete(int id) async {
    final count =
        await (await _db).delete(_table, where: 'id = ?$_mine', whereArgs: [id]);
    if (count == 0) throw const ReminderException.notFound();
  }

  // ----------------------------------------------------- Actions utilisateur

  @override
  Future<CompletionResult> markDone(int id) async {
    final now = _clock();
    return (await _db).transaction((txn) async {
      final current = await _find(id, txn);
      if (current.isDone) return CompletionResult(done: current);

      final done = current.copyWith(
        status: ReminderStatus.done,
        completedAt: () => now,
        updatedAt: now,
      );
      await txn.update(_table, done.toMap(), where: 'id = ?', whereArgs: [id]);

      Reminder? next;
      final nextDate = ReminderCalculator.nextOccurrenceAfter(
          current.dueDate, current.repeat, now);
      if (nextDate != null) {
        final draft = Reminder(
          petId: current.petId,
          title: current.title,
          type: current.type,
          dueDate: nextDate,
          alertOffsets: current.alertOffsets,
          repeat: current.repeat,
          notes: current.notes,
          source: current.source,
          sourceId: current.sourceId,
          createdAt: now,
          updatedAt: now,
        );
        final exists = current.sourceId != null
            ? await _existsForSource(
                txn, current.source, current.sourceId!, nextDate)
            : await _existsSimilar(txn, draft);
        if (!exists) next = await _insert(txn, draft);
      }
      return CompletionResult(done: done, next: next);
    });
  }

  @override
  Future<Reminder> reopen(int id, {int? removeNextId}) async {
    return (await _db).transaction((txn) async {
      final current = await _find(id, txn);
      final reopened = current.copyWith(
        status: current.postponeCount > 0
            ? ReminderStatus.postponed
            : ReminderStatus.upcoming,
        completedAt: () => null,
        updatedAt: _clock(),
      );
      await txn.update(_table, reopened.toMap(),
          where: 'id = ?', whereArgs: [id]);
      if (removeNextId != null) {
        // Supprime l'occurrence créée par markDone si elle n'a pas été traitée.
        await txn.delete(_table,
            where: 'id = ? AND title = ? AND status != ?$_mine',
            whereArgs: [removeNextId, current.title, ReminderStatus.done.name]);
      }
      return reopened;
    });
  }

  @override
  Future<Reminder> postpone(int id, DateTime dueDate) async {
    if (!dueDate.isAfter(_clock())) {
      throw const ReminderException(
          'La nouvelle date doit être dans le futur.');
    }
    final db = await _db;
    final current = await _find(id, db);
    if (current.isDone) {
      throw const ReminderException(
          'Un rappel terminé ne peut pas être reporté.');
    }
    // Soins médicaux : nombre et durée des reports limités.
    final limit = ReminderRules.postponeError(current, dueDate, _clock());
    if (limit != null) {
      throw ReminderException(limit, ReminderErrorKind.postponeLimit);
    }
    final saved = current.copyWith(
      dueDate: dueDate,
      status: ReminderStatus.postponed,
      postponeCount: current.postponeCount + 1,
      updatedAt: _clock(),
    );
    await _guardUnique(() =>
        db.update(_table, saved.toMap(), where: 'id = ?', whereArgs: [id]));
    return saved;
  }

  // ------------------------------------------------- Intégration des modules

  @override
  Future<(SyncOutcome, Reminder?)> syncFromSource({
    required ReminderSource source,
    required int sourceId,
    required DateTime? dueDate,
    int? petId,
    ReminderType type = ReminderType.other,
    String? title,
    List<AlertOffset> alertOffsets = const [
      AlertOffset.tenDays,
      AlertOffset.oneDay,
      AlertOffset.atTime,
    ],
    ReminderRepeat repeat = ReminderRepeat.none,
  }) async {
    if (source == ReminderSource.manual) {
      throw const ReminderException(
          'La synchronisation concerne les sources santé ou alimentation.');
    }
    final now = _clock();
    return (await _db).transaction((txn) async {
      final rows = await txn.query(
        _table,
        where: 'source = ? AND source_id = ? AND status != ?$_mine',
        whereArgs: [source.name, sourceId, ReminderStatus.done.name],
        orderBy: 'due_date ASC',
        limit: 1,
      );
      final existing = rows.isEmpty ? null : Reminder.fromMap(rows.first);

      if (dueDate == null) {
        if (existing == null) return (SyncOutcome.unchanged, null);
        await txn.delete(_table, where: 'id = ?', whereArgs: [existing.id]);
        return (SyncOutcome.removed, null);
      }

      final wantedTitle = (title ?? type.defaultTitle).trim();
      if (existing != null) {
        if (existing.dueDate == dueDate &&
            existing.title == wantedTitle &&
            existing.type == type &&
            existing.petId == petId) {
          return (SyncOutcome.unchanged, existing);
        }
        final saved = existing.copyWith(
          dueDate: dueDate,
          title: wantedTitle,
          type: type,
          petId: () => petId,
          status: ReminderStatus.upcoming,
          updatedAt: now,
        );
        await txn.update(_table, saved.toMap(),
            where: 'id = ?', whereArgs: [saved.id]);
        return (SyncOutcome.updated, saved);
      }

      // Échéance déjà traitée (rappel « fait » à cette même date).
      if (await _existsForSource(txn, source, sourceId, dueDate)) {
        return (SyncOutcome.unchanged, null);
      }

      final created = await _insert(
        txn,
        Reminder(
          petId: petId,
          title: wantedTitle,
          type: type,
          dueDate: dueDate,
          alertOffsets: alertOffsets,
          repeat: repeat,
          source: source,
          sourceId: sourceId,
          createdAt: now,
          updatedAt: now,
        ),
      );
      return (SyncOutcome.created, created);
    });
  }

  @override
  Future<List<int>> deleteBySource(ReminderSource source, int sourceId) =>
      _deleteWhere('source = ? AND source_id = ?', [source.name, sourceId]);

  @override
  Future<List<int>> deleteByPet(int petId) =>
      _deleteWhere('pet_id = ?', [petId]);

  // ---------------------------------------------------------------- Interne

  Reminder _validate(Reminder r) {
    final title = r.title.trim();
    if (title.isEmpty) {
      throw const ReminderException('Le titre est obligatoire.');
    }
    if (title.length > maxTitleLength) {
      throw const ReminderException(
          'Le titre ne doit pas dépasser $maxTitleLength caractères.');
    }
    final notes = r.notes?.trim();
    return r.copyWith(
      title: title,
      notes: () => (notes == null || notes.isEmpty) ? null : notes,
    );
  }

  /// Refuse un rappel non terminé identique (même animal, type, date et
  /// titre sans tenir compte de la casse).
  Future<void> _assertNotDuplicate(DatabaseExecutor db, Reminder r) async {
    if (await _existsSimilar(db, r)) throw const ReminderException.conflict();
  }

  Future<bool> _existsSimilar(DatabaseExecutor db, Reminder r) async {
    final rows = await db.query(
      _table,
      columns: ['id'],
      where: '${r.petId == null ? 'pet_id IS NULL' : 'pet_id = ?'} '
          'AND type = ? AND due_date = ? AND lower(title) = lower(?) '
          'AND status != ?${r.id != null ? ' AND id != ?' : ''}$_mine',
      whereArgs: [
        ?r.petId,
        r.type.name,
        r.dueDate.millisecondsSinceEpoch,
        r.title.trim(),
        ReminderStatus.done.name,
        ?r.id,
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> _existsForSource(DatabaseExecutor db, ReminderSource source,
      int sourceId, DateTime dueDate) async {
    final rows = await db.query(
      _table,
      columns: ['id'],
      where: 'source = ? AND source_id = ? AND due_date = ?$_mine',
      whereArgs: [source.name, sourceId, dueDate.millisecondsSinceEpoch],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<Reminder> _insert(DatabaseExecutor db, Reminder r) async {
    final id = await _guardUnique(() => db.insert(_table, {
          ...r.toMap()..remove('id'),
          'user_id': ?ownerId,
        }));
    return r.copyWith(id: id);
  }

  /// Convertit la violation de l'index unique en erreur métier.
  Future<T> _guardUnique<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw const ReminderException.conflict(
            'Un rappel existe déjà pour cette source et cette date.');
      }
      rethrow;
    }
  }

  Future<List<int>> _deleteWhere(String condition, List<Object?> args) async {
    final where = '$condition$_mine';
    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.query(_table,
          columns: ['id'], where: where, whereArgs: args);
      await txn.delete(_table, where: where, whereArgs: args);
      return [for (final r in rows) r['id'] as int];
    });
  }
}
