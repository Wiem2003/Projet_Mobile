import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';

/// Préférences du tableau de bord d'un compte : alertes masquées et
/// dernier rapport mensuel consulté.
class DashboardPrefs {
  const DashboardPrefs({this.dismissedUntil = const {}, this.lastReportSeen});

  /// Identifiant d'alerte → date jusqu'à laquelle elle est masquée.
  final Map<String, DateTime> dismissedUntil;

  /// Mois du dernier rapport ouvert (« 2026-10 »).
  final String? lastReportSeen;

  static String monthKey(DateTime month) =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';

  DashboardPrefs copyWith({Map<String, DateTime>? dismissedUntil, String? lastReportSeen}) =>
      DashboardPrefs(
        dismissedUntil: dismissedUntil ?? this.dismissedUntil,
        lastReportSeen: lastReportSeen ?? this.lastReportSeen,
      );

  /// Retire les masquages expirés.
  DashboardPrefs cleaned(DateTime now) => copyWith(dismissedUntil: {
        for (final e in dismissedUntil.entries)
          if (e.value.isAfter(now)) e.key: e.value,
      });

  Map<String, Object?> toJson() => {
        'dismissed': {
          for (final e in dismissedUntil.entries) e.key: e.value.millisecondsSinceEpoch,
        },
        'last_report': lastReportSeen,
      };

  factory DashboardPrefs.fromJson(Object? json) {
    if (json is! Map) return const DashboardPrefs();
    final raw = json['dismissed'];
    return DashboardPrefs(
      dismissedUntil: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.key is String && e.value is int)
              e.key as String: DateTime.fromMillisecondsSinceEpoch(e.value as int),
      },
      lastReportSeen: json['last_report'] as String?,
    );
  }
}

abstract interface class DashboardPrefsStore {
  Future<DashboardPrefs> load();
  Future<void> save(DashboardPrefs prefs);
}

class MemoryDashboardPrefsStore implements DashboardPrefsStore {
  MemoryDashboardPrefsStore([this.prefs = const DashboardPrefs()]);

  DashboardPrefs prefs;

  @override
  Future<DashboardPrefs> load() async => prefs;

  @override
  Future<void> save(DashboardPrefs p) async => prefs = p;
}

/// Table `app_settings`, une ligne JSON par compte.
class SqliteDashboardPrefsStore implements DashboardPrefsStore {
  SqliteDashboardPrefsStore(this._appDb, {this.ownerId});

  final AppDatabase _appDb;
  final int? ownerId;

  String get _key => ownerId == null ? 'dashboard' : 'dashboard:$ownerId';

  @override
  Future<DashboardPrefs> load() async {
    final rows = await (await _appDb.database)
        .query('app_settings', where: 'key = ?', whereArgs: [_key]);
    final raw = rows.firstOrNull?['value'] as String?;
    if (raw == null) return const DashboardPrefs();
    try {
      return DashboardPrefs.fromJson(jsonDecode(raw));
    } on FormatException {
      return const DashboardPrefs();
    }
  }

  @override
  Future<void> save(DashboardPrefs prefs) async {
    await (await _appDb.database).insert(
      'app_settings',
      {'key': _key, 'value': jsonEncode(prefs.toJson())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
