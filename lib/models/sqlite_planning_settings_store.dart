import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import 'reminder_planning.dart';

/// Réglages de planification enregistrés dans la table `app_settings`
/// (une ligne JSON par compte).
class SqlitePlanningSettingsStore implements PlanningSettingsStore {
  SqlitePlanningSettingsStore(this._appDb, {this.ownerId});

  final AppDatabase _appDb;

  /// Compte connecté (`null` : réglage commun, utilisé par les tests).
  final int? ownerId;

  String get _key => ownerId == null ? 'planning' : 'planning:$ownerId';

  @override
  Future<PlanningSettings> load() async {
    final rows = await (await _appDb.database)
        .query('app_settings', where: 'key = ?', whereArgs: [_key]);
    final raw = rows.firstOrNull?['value'] as String?;
    if (raw == null) return const PlanningSettings();
    try {
      return PlanningSettings.fromJson(jsonDecode(raw));
    } on FormatException {
      return const PlanningSettings();
    }
  }

  @override
  Future<void> save(PlanningSettings settings) async {
    await (await _appDb.database).insert(
      'app_settings',
      {'key': _key, 'value': jsonEncode(settings.toJson())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
