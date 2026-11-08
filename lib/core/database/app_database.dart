import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Base SQLite locale partagée par tous les modules (fichier `smart_pet.db`).
///
/// Chaque module ajoute ses tables dans [_onCreate] et, pour une base déjà
/// installée, une migration dans [_onUpgrade] en incrémentant [version].
class AppDatabase {
  /// [factory] et [path] servent aux tests (base en mémoire via sqflite_ffi).
  AppDatabase({DatabaseFactory? factory, this.path})
      : _factory = factory ?? databaseFactory;

  static const String fileName = 'smart_pet.db';

  /// 1 : rappels — 2 : alimentation et activités — 3 : animaux et santé —
  /// 4 : comptes utilisateurs (chaque animal et rappel appartient à un compte) —
  /// 5 : allergies des animaux (carnet de santé) — 6 : animal stérilisé et
  /// calories des repas (ration conseillée) — 7 : photo de profil des comptes.
  static const int version = 7;

  final DatabaseFactory _factory;
  final String? path;
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = path ?? p.join(await _factory.getDatabasesPath(), fileName);
    _db = await _factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    // --- Module 1 : Animaux -------------------------------------------------
    _createPets(batch);
    // --- Module 2 : Santé ---------------------------------------------------
    _createHealthRecords(batch);
    // --- Module 3 : Alimentation --------------------------------------------
    _createFeedingRecords(batch);
    // --- Module 4 : Activités -----------------------------------------------
    _createActivities(batch);
    // --- Module 5 : Rappels -------------------------------------------------
    _createReminders(batch);
    // --- Comptes utilisateurs -----------------------------------------------
    _createUsers(batch);
    await batch.commit(noResult: true);
  }

  static Future<void> _onUpgrade(Database db, int from, int to) async {
    final batch = db.batch();
    if (from < 2) {
      _createFeedingRecords(batch);
      _createActivities(batch);
    }
    if (from < 3) {
      _createPets(batch);
      _createHealthRecords(batch);
    }
    if (from < 4) {
      // `_createPets` crée déjà la colonne pour une base antérieure à la v3.
      if (from >= 3) batch.execute('ALTER TABLE pets ADD COLUMN user_id INTEGER');
      batch.execute('ALTER TABLE reminders ADD COLUMN user_id INTEGER');
      batch.execute('DROP INDEX IF EXISTS idx_reminders_source_due');
      _createReminderSourceIndex(batch);
      _createUsers(batch);
    }
    // `_createPets` crée déjà la colonne pour une base antérieure à la v3.
    if (from < 5 && from >= 3) {
      batch.execute('ALTER TABLE pets ADD COLUMN allergies TEXT');
    }
    // `_createUsers` crée déjà la colonne pour une base antérieure à la v4.
    if (from < 7 && from >= 4) {
      batch.execute('ALTER TABLE users ADD COLUMN photo_path TEXT');
    }
    if (from < 6) {
      // Tables déjà créées par les étapes précédentes : colonne incluse.
      if (from >= 3) {
        batch.execute('ALTER TABLE pets ADD COLUMN sterilized INTEGER NOT NULL DEFAULT 0');
      }
      if (from >= 2) {
        batch.execute('ALTER TABLE feeding_records ADD COLUMN kcal_per_100g REAL');
      }
    }
    await batch.commit(noResult: true);
    if (from < 3) await _adoptDemoPets(db);
  }

  /// Avant la version 3, les animaux étaient fictifs (Rex = 1, Mia = 2) :
  /// on les crée pour que les données déjà saisies restent rattachées.
  static Future<void> _adoptDemoPets(Database db) async {
    final used = await db.rawQuery('''
      SELECT pet_id FROM reminders WHERE pet_id IS NOT NULL
      UNION SELECT pet_id FROM feeding_records
      UNION SELECT pet_id FROM activities
    ''');
    final ids = {for (final r in used) r['pet_id'] as int};
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final (id, name, species, weight) in [
      (1, 'Rex', 'dog', 28.0),
      (2, 'Mia', 'cat', 4.5),
    ]) {
      if (!ids.contains(id)) continue;
      await db.insert('pets', {
        'id': id,
        'name': name,
        'species': species,
        'weight_kg': weight,
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  static void _createPets(Batch batch) {
    batch.execute('''
      CREATE TABLE pets (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id        INTEGER,
        name           TEXT    NOT NULL,
        species        TEXT    NOT NULL,
        breed          TEXT,
        sex            TEXT    NOT NULL DEFAULT 'unknown',
        birth_date     INTEGER,
        weight_kg      REAL,
        color          TEXT,
        identification TEXT,
        photo_path     TEXT,
        allergies      TEXT,
        sterilized     INTEGER NOT NULL DEFAULT 0,
        created_at     INTEGER NOT NULL,
        updated_at     INTEGER NOT NULL
      )
    ''');
    // Un numéro d'identification (puce, tatouage) ne peut appartenir qu'à un animal.
    batch.execute('''
      CREATE UNIQUE INDEX idx_pets_identification
      ON pets(identification) WHERE identification IS NOT NULL
    ''');
  }

  static void _createHealthRecords(Batch batch) {
    batch.execute('''
      CREATE TABLE health_records (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        pet_id      INTEGER NOT NULL,
        type        TEXT    NOT NULL,
        date        INTEGER NOT NULL,
        vet         TEXT,
        description TEXT,
        weight_kg   REAL,
        medication  TEXT,
        cost        REAL    NOT NULL DEFAULT 0,
        next_due    INTEGER,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL
      )
    ''');
    batch.execute(
        'CREATE INDEX idx_health_pet_date ON health_records(pet_id, date)');
  }

  static void _createFeedingRecords(Batch batch) {
    batch.execute('''
      CREATE TABLE feeding_records (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        pet_id      INTEGER NOT NULL,
        date        INTEGER NOT NULL,
        food_type   TEXT    NOT NULL,
        quantity_g  REAL    NOT NULL,
        price       REAL    NOT NULL DEFAULT 0,
        meals       INTEGER NOT NULL DEFAULT 1,
        brand       TEXT,
        kcal_per_100g REAL,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL
      )
    ''');
    batch.execute(
        'CREATE INDEX idx_feeding_pet_date ON feeding_records(pet_id, date)');
  }

  static void _createActivities(Batch batch) {
    batch.execute('''
      CREATE TABLE activities (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        pet_id       INTEGER NOT NULL,
        date         INTEGER NOT NULL,
        type         TEXT    NOT NULL,
        duration_min INTEGER NOT NULL,
        distance_km  REAL    NOT NULL DEFAULT 0,
        calories     REAL    NOT NULL DEFAULT 0,
        weight_kg    REAL,
        description  TEXT,
        route        TEXT,
        created_at   INTEGER NOT NULL,
        updated_at   INTEGER NOT NULL
      )
    ''');
    batch.execute(
        'CREATE INDEX idx_activities_pet_date ON activities(pet_id, date)');
  }

  static void _createReminders(Batch batch) {
    batch.execute('''
      CREATE TABLE reminders (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id        INTEGER,
        pet_id         INTEGER,
        title          TEXT    NOT NULL,
        type           TEXT    NOT NULL,
        due_date       INTEGER NOT NULL,
        alert_offsets  TEXT    NOT NULL DEFAULT '',
        repeat         TEXT    NOT NULL DEFAULT 'none',
        status         TEXT    NOT NULL DEFAULT 'upcoming',
        notes          TEXT,
        source         TEXT    NOT NULL DEFAULT 'manual',
        source_id      INTEGER,
        postpone_count INTEGER NOT NULL DEFAULT 0,
        completed_at   INTEGER,
        created_at     INTEGER NOT NULL,
        updated_at     INTEGER NOT NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_reminders_pet ON reminders(pet_id, due_date)');
    _createReminderSourceIndex(batch);
  }

  /// Anti-doublon : une seule échéance par compte, source et date.
  static void _createReminderSourceIndex(Batch batch) {
    batch.execute('''
      CREATE UNIQUE INDEX idx_reminders_source_due
      ON reminders(COALESCE(user_id, 0), source, source_id, due_date)
      WHERE source_id IS NOT NULL
    ''');
  }

  /// Comptes (sign up / sign in) et session ouverte sur le téléphone.
  /// Les animaux (`pets.user_id`) et les rappels (`reminders.user_id`)
  /// appartiennent à un compte ; santé, repas et activités suivent l'animal.
  static void _createUsers(Batch batch) {
    batch.execute('''
      CREATE TABLE users (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        name          TEXT    NOT NULL,
        email         TEXT    NOT NULL UNIQUE COLLATE NOCASE,
        password_hash TEXT    NOT NULL,
        photo_path    TEXT,
        role          TEXT    NOT NULL DEFAULT 'user',
        active        INTEGER NOT NULL DEFAULT 1,
        last_login_at INTEGER,
        created_at    INTEGER NOT NULL,
        updated_at    INTEGER NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE app_settings (
        key   TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    batch.execute('CREATE INDEX idx_pets_user ON pets(user_id)');
    batch.execute('CREATE INDEX idx_reminders_user ON reminders(user_id, due_date)');
  }
}
