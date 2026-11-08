import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../validation.dart';
import 'app_user.dart';
import 'password_hasher.dart';
import 'user_repository.dart';

/// Implémentation SQLite (tables `users` et `app_settings`).
class SqliteUserRepository implements UserRepository {
  SqliteUserRepository(this._appDb,
      {DateTime Function()? clock, PasswordHasher? hasher, Random? random})
      : _clock = clock ?? DateTime.now,
        _hasher = hasher ?? PasswordHasher(),
        _random = random ?? Random.secure();

  static const _table = 'users';
  static const _sessionKey = 'session_user_id';

  /// Essais de mot de passe avant un blocage temporaire.
  static const maxFailures = 5;
  static const lockDuration = Duration(minutes: 5);

  /// Mot de passe oublié : code à 6 chiffres, 15 minutes, 5 essais.
  static const resetCodeLength = 6;
  static const resetValidity = Duration(minutes: 15);
  static const maxResetAttempts = 5;
  static const resetInvalid = 'Code incorrect ou expiré. Demandez un nouveau code.';

  final AppDatabase _appDb;
  final DateTime Function() _clock;
  final PasswordHasher _hasher;
  final Random _random;

  /// Échecs de connexion par e-mail (protection contre les essais en série).
  final _failures = <String, ({int count, DateTime last})>{};

  Future<Database> get _db => _appDb.database;

  static const badCredentials = 'E-mail ou mot de passe incorrect.';
  static const disabledMessage =
      'Ce compte a été désactivé par un administrateur.';

  String _normalize(String email) => email.trim().toLowerCase();

  // ------------------------------------------------------- Sign up / Sign in

  @override
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
    String? photoPath,
    UserRole role = UserRole.user,
  }) async {
    _checkAccount(name, email, password);
    final mail = _normalize(email);
    final hash = _hasher.hash(password);
    final now = _clock().millisecondsSinceEpoch;
    final db = await _db;
    final id = await db.transaction((txn) async {
      final existing = await txn
          .query(_table, columns: ['id'], where: 'email = ?', whereArgs: [mail]);
      if (existing.isNotEmpty) {
        throw const RecordException(
            'Un compte existe déjà avec cette adresse e-mail.');
      }
      final first = (await _count(txn, 'SELECT COUNT(*) FROM users')) == 0;
      final id = await txn.insert(_table, {
        'name': name.trim(),
        'email': mail,
        'password_hash': hash,
        'photo_path': photoPath,
        // Le premier compte administre toujours l'application ; les
        // suivants prennent le rôle choisi à l'inscription.
        'role': first ? UserRole.admin.name : role.name,
        'active': 1,
        'last_login_at': now,
        'created_at': now,
        'updated_at': now,
      });
      if (first) {
        // Données saisies avant l'ajout des comptes : au premier compte.
        await txn.rawUpdate('UPDATE pets SET user_id = ? WHERE user_id IS NULL', [id]);
        await txn.rawUpdate(
            'UPDATE reminders SET user_id = ? WHERE user_id IS NULL', [id]);
      }
      return id;
    });
    return getById(id);
  }

  @override
  Future<AppUser> signIn(
      {required String email, required String password}) async {
    final mail = _normalize(email);
    if (mail.isEmpty || password.isEmpty) {
      throw const RecordException(
          'Indiquez votre e-mail et votre mot de passe.');
    }
    final now = _clock();
    final failed = _failures[mail];
    if (failed != null && failed.count >= maxFailures) {
      final unlock = failed.last.add(lockDuration);
      if (now.isBefore(unlock)) {
        final minutes = (unlock.difference(now).inSeconds / 60).ceil();
        throw RecordException('Trop d\'essais. Réessayez dans $minutes '
            'minute${minutes > 1 ? 's' : ''}.');
      }
      _failures.remove(mail);
    }
    final db = await _db;
    final rows = await db.query(_table, where: 'email = ?', whereArgs: [mail]);
    final row = rows.firstOrNull;
    // Même message si l'e-mail est inconnu : on ne révèle pas les comptes.
    if (row == null || !_hasher.verify(password, row['password_hash'] as String)) {
      final previous = _failures[mail];
      _failures[mail] = (count: (previous?.count ?? 0) + 1, last: now);
      throw const RecordException(badCredentials);
    }
    _failures.remove(mail);
    if (row['active'] != 1) throw const RecordException(disabledMessage);
    await db.update(_table, {'last_login_at': now.millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [row['id']]);
    return getById(row['id'] as int);
  }

  // ------------------------------------------------- Mot de passe oublié

  /// Demande en cours, dans `app_settings` (elle survit si Android ferme
  /// l'app pendant la lecture de l'e-mail). Seule l'empreinte du code est
  /// enregistrée.
  static String _resetKey(int userId) => 'password_reset:$userId';

  Future<Map<String, Object?>?> _resetOf(int userId) async {
    final rows = await (await _db)
        .query('app_settings', where: 'key = ?', whereArgs: [_resetKey(userId)]);
    final raw = rows.firstOrNull?['value'] as String?;
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, Object?>();
    } on FormatException {
      return null;
    }
  }

  Future<void> _saveReset(int userId, Map<String, Object?> value) async =>
      (await _db).insert('app_settings', {'key': _resetKey(userId), 'value': jsonEncode(value)},
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> _clearReset(int userId) async => (await _db)
      .delete('app_settings', where: 'key = ?', whereArgs: [_resetKey(userId)]);

  Future<Map<String, Object?>?> _activeRow(String email) async {
    final rows = await (await _db)
        .query(_table, where: 'email = ? AND active = 1', whereArgs: [_normalize(email)]);
    return rows.firstOrNull;
  }

  @override
  Future<PasswordResetRequest?> requestPasswordReset(String email) async {
    final row = await _activeRow(email);
    if (row == null) return null;
    final id = row['id'] as int;
    final code = List.generate(resetCodeLength, (_) => _random.nextInt(10)).join();
    final now = _clock();
    final expires = now.add(resetValidity);
    await _saveReset(id, {
      'hash': _hasher.hash(code),
      'expires': expires.millisecondsSinceEpoch,
      'attempts': 0,
    });
    return PasswordResetRequest(user: AppUser.fromMap(row), code: code, expiresAt: expires);
  }

  @override
  Future<AppUser> resetPassword(
      {required String email, required String code, required String newPassword}) async {
    final row = await _activeRow(email);
    final id = row?['id'] as int?;
    final request = id == null ? null : await _resetOf(id);
    if (id == null || request == null) throw const RecordException(resetInvalid);

    final now = _clock();
    if (now.millisecondsSinceEpoch > (request['expires'] as int)) {
      await _clearReset(id);
      throw const RecordException('Ce code a expiré. Demandez un nouveau code.');
    }
    final typed = code.replaceAll(RegExp(r'\s'), '');
    if (!_hasher.verify(typed, request['hash'] as String)) {
      final attempts = (request['attempts'] as int) + 1;
      if (attempts >= maxResetAttempts) {
        await _clearReset(id);
        throw const RecordException("Trop d'essais : demandez un nouveau code.");
      }
      await _saveReset(id, {...request, 'attempts': attempts});
      final left = maxResetAttempts - attempts;
      throw RecordException('Code incorrect ($left essai${left > 1 ? 's' : ''} restant${left > 1 ? 's' : ''}).');
    }
    final error = InputRules.password(newPassword);
    if (error != null) throw RecordException('$error.');

    await (await _db).update(
        _table, {'password_hash': _hasher.hash(newPassword), 'updated_at': now.millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
    await _clearReset(id);
    _failures.remove(_normalize(email));
    return getById(id);
  }

  @override
  Future<int?> sessionUserId() async {
    final rows = await (await _db).query('app_settings',
        where: 'key = ?', whereArgs: [_sessionKey]);
    return int.tryParse(rows.firstOrNull?['value'] as String? ?? '');
  }

  @override
  Future<void> saveSession(int userId) async {
    await (await _db).insert(
        'app_settings', {'key': _sessionKey, 'value': '$userId'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> clearSession() async {
    await (await _db)
        .delete('app_settings', where: 'key = ?', whereArgs: [_sessionKey]);
  }

  // ------------------------------------------------------------------ Profil

  @override
  Future<AppUser> getById(int id) async {
    final rows =
        await (await _db).query(_table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw const RecordException.notFound('Compte introuvable.');
    return AppUser.fromMap(rows.first);
  }

  @override
  Future<AppUser> updateName(int id, String name) async {
    final error = InputRules.name(name, 'Le nom',
        required: true, max: AppUser.maxNameLength);
    if (error != null) throw RecordException('$error.');
    await getById(id);
    await (await _db).update(_table,
        {'name': name.trim(), 'updated_at': _clock().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
    return getById(id);
  }

  @override
  Future<void> changePassword(int id,
      {required String current, required String next}) async {
    final db = await _db;
    final rows = await db.query(_table,
        columns: ['password_hash'], where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw const RecordException.notFound('Compte introuvable.');
    if (!_hasher.verify(current, rows.first['password_hash'] as String)) {
      throw const RecordException('Mot de passe actuel incorrect.');
    }
    final error = InputRules.password(next);
    if (error != null) throw RecordException('$error.');
    if (current == next) {
      throw const RecordException(
          'Le nouveau mot de passe doit être différent de l\'ancien.');
    }
    await db.update(
        _table,
        {
          'password_hash': _hasher.hash(next),
          'updated_at': _clock().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  @override
  Future<AppUser> updatePhoto(int id, String? photoPath) async {
    await getById(id);
    await _set(id, {'photo_path': photoPath});
    return getById(id);
  }

  // -------------------------------------------------------- Administration

  /// Nom, e-mail et mot de passe (si [password] n'est pas null).
  static void _checkAccount(String name, String email, String? password) {
    final error = InputRules.name(name, 'Le nom', required: true, max: AppUser.maxNameLength) ??
        InputRules.email(email) ??
        (password == null ? null : InputRules.password(password));
    if (error != null) throw RecordException('$error.');
  }

  Future<void> _assertEmailFree(DatabaseExecutor db, String mail, {int? selfId}) async {
    final rows = await db.query(_table,
        columns: ['id'],
        where: 'email = ?${selfId == null ? '' : ' AND id != $selfId'}',
        whereArgs: [mail]);
    if (rows.isNotEmpty) {
      throw const RecordException('Un compte existe déjà avec cette adresse e-mail.');
    }
  }

  Future<void> _assertAdmin(int actorId) async {
    final actor = await getById(actorId);
    if (!actor.isAdmin || !actor.active) {
      throw const RecordException('Action réservée aux administrateurs.');
    }
  }

  @override
  Future<AppUser> createAccount({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String? photoPath,
    required int actorId,
  }) async {
    await _assertAdmin(actorId);
    _checkAccount(name, email, password);
    final mail = _normalize(email);
    final db = await _db;
    await _assertEmailFree(db, mail);
    final now = _clock().millisecondsSinceEpoch;
    final id = await db.insert(_table, {
      'name': name.trim(),
      'email': mail,
      'password_hash': _hasher.hash(password),
      'photo_path': photoPath,
      'role': role.name,
      'active': 1,
      'created_at': now,
      'updated_at': now,
    });
    return getById(id);
  }

  @override
  Future<AppUser> updateAccount(
    int id, {
    required String name,
    required String email,
    required UserRole role,
    required bool active,
    String? photoPath,
    String? newPassword,
    required int actorId,
  }) async {
    await _assertAdmin(actorId);
    final target = await _target(id, actorId);
    final password = (newPassword ?? '').isEmpty ? null : newPassword;
    _checkAccount(name, email, password);
    if (role != UserRole.admin || !active) await _assertNotLastAdmin(target);
    final mail = _normalize(email);
    final db = await _db;
    await _assertEmailFree(db, mail, selfId: id);
    await _set(id, {
      'name': name.trim(),
      'email': mail,
      'role': role.name,
      'active': active ? 1 : 0,
      'photo_path': photoPath,
      'password_hash': ?password == null ? null : _hasher.hash(password),
    });
    return getById(id);
  }

  @override
  Future<List<UserSummary>> getAll() async {
    final rows = await (await _db).rawQuery('''
      SELECT u.*,
        (SELECT COUNT(*) FROM pets p WHERE p.user_id = u.id) AS pet_count,
        (SELECT COUNT(*) FROM reminders r WHERE r.user_id = u.id) AS reminder_count
      FROM users u
      ORDER BY u.created_at DESC, u.id DESC
    ''');
    return [
      for (final r in rows)
        UserSummary(
          user: AppUser.fromMap(r),
          pets: r['pet_count'] as int,
          reminders: r['reminder_count'] as int,
        ),
    ];
  }

  @override
  Future<AdminStats> stats() async {
    final db = await _db;
    Future<int> n(String sql) => _count(db, sql);
    return AdminStats(
      users: await n('SELECT COUNT(*) FROM users'),
      admins: await n("SELECT COUNT(*) FROM users WHERE role = 'admin'"),
      disabled: await n('SELECT COUNT(*) FROM users WHERE active = 0'),
      pets: await n('SELECT COUNT(*) FROM pets'),
      healthRecords: await n('SELECT COUNT(*) FROM health_records'),
      feedingRecords: await n('SELECT COUNT(*) FROM feeding_records'),
      activities: await n('SELECT COUNT(*) FROM activities'),
      reminders: await n('SELECT COUNT(*) FROM reminders'),
    );
  }

  @override
  Future<AppUser> setRole(int id, UserRole role, {required int actorId}) async {
    final target = await _target(id, actorId);
    if (target.role == role) return target;
    if (role != UserRole.admin) await _assertNotLastAdmin(target);
    await _set(id, {'role': role.name});
    return getById(id);
  }

  @override
  Future<AppUser> setActive(int id, bool active, {required int actorId}) async {
    final target = await _target(id, actorId);
    if (target.active == active) return target;
    if (!active) await _assertNotLastAdmin(target);
    await _set(id, {'active': active ? 1 : 0});
    return getById(id);
  }

  @override
  Future<List<String>> delete(int id, {required int actorId}) async {
    final target = await _target(id, actorId);
    await _assertNotLastAdmin(target);
    final db = await _db;
    return db.transaction((txn) async {
      final pets = await txn.query('pets',
          columns: ['id', 'photo_path'], where: 'user_id = ?', whereArgs: [id]);
      const petTables = ['health_records', 'feeding_records', 'activities', 'reminders'];
      for (final table in petTables) {
        await txn.rawDelete(
            'DELETE FROM $table WHERE pet_id IN (SELECT id FROM pets WHERE user_id = ?)',
            [id]);
      }
      await txn.delete('reminders', where: 'user_id = ?', whereArgs: [id]);
      await txn.delete('pets', where: 'user_id = ?', whereArgs: [id]);
      await txn.delete(_table, where: 'id = ?', whereArgs: [id]);
      return [
        for (final p in pets)
          if (p['photo_path'] case final String path) path,
        ?target.photoPath,
      ];
    });
  }

  // ---------------------------------------------------------------- Interne

  Future<AppUser> _target(int id, int actorId) async {
    if (id == actorId) {
      throw const RecordException(
          'Vous ne pouvez pas modifier votre propre compte depuis '
          'l\'administration.');
    }
    return getById(id);
  }

  /// Il reste toujours au moins un administrateur actif.
  Future<void> _assertNotLastAdmin(AppUser target) async {
    if (!target.isAdmin || !target.active) return;
    final admins = await _count(await _db,
        "SELECT COUNT(*) FROM users WHERE role = 'admin' AND active = 1");
    if (admins <= 1) {
      throw const RecordException(
          'Il doit rester au moins un administrateur actif.');
    }
  }

  Future<void> _set(int id, Map<String, Object?> values) async {
    await (await _db).update(
        _table, {...values, 'updated_at': _clock().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> _count(DatabaseExecutor db, String sql) async =>
      Sqflite.firstIntValue(await db.rawQuery(sql)) ?? 0;
}
