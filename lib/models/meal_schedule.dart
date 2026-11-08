import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';

/// Heure d'un repas (chaque jour).
@immutable
class MealTime implements Comparable<MealTime> {
  const MealTime(this.hour, this.minute);

  final int hour;
  final int minute;

  /// « 19 h », « 7 h 30 ».
  String get label => minute == 0 ? '$hour h' : '$hour h ${minute.toString().padLeft(2, '0')}';

  String get key => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  static MealTime? parse(Object? v) {
    if (v is! String) return null;
    final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(v);
    if (m == null) return null;
    final h = int.parse(m[1]!), min = int.parse(m[2]!);
    return h < 24 && min < 60 ? MealTime(h, min) : null;
  }

  @override
  int compareTo(MealTime other) =>
      (hour * 60 + minute).compareTo(other.hour * 60 + other.minute);

  @override
  bool operator ==(Object other) =>
      other is MealTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}

/// Horaires de repas par animal (rappels quotidiens).
class MealSchedule {
  const MealSchedule([this.times = const {}]);

  /// Au plus 6 repas programmés par animal.
  static const maxPerPet = 6;

  final Map<int, List<MealTime>> times;

  List<MealTime> of(int petId) => times[petId] ?? const [];

  MealSchedule withTime(int petId, MealTime t) {
    final list = {...of(petId), t}.toList()..sort();
    return MealSchedule({...times, petId: list});
  }

  MealSchedule withoutTime(int petId, MealTime t) =>
      MealSchedule({...times, petId: [for (final x in of(petId)) if (x != t) x]});

  /// Retire les animaux supprimés.
  MealSchedule only(Set<int> petIds) =>
      MealSchedule({for (final e in times.entries) if (petIds.contains(e.key)) e.key: e.value});

  Map<String, Object> toJson() => {
        for (final e in times.entries)
          if (e.value.isNotEmpty) '${e.key}': [for (final t in e.value) t.key],
      };

  factory MealSchedule.fromJson(Object? json) {
    if (json is! Map) return const MealSchedule();
    return MealSchedule({
      for (final e in json.entries)
        if (int.tryParse('${e.key}') case final id? when e.value is List)
          id: ([for (final v in e.value as List) ?MealTime.parse(v)]..sort()),
    });
  }
}

/// Notification quotidienne « Repas de Mia, 19 h ».
typedef MealAlarm = ({int petId, String petName, MealTime time});

/// Programme les notifications des repas (indépendantes des rappels :
/// un repas non coché ne passe jamais « en retard »).
abstract interface class MealNotifier {
  Future<void> syncMeals(List<MealAlarm> alarms);
}

abstract interface class MealScheduleStore {
  Future<MealSchedule> load();
  Future<void> save(MealSchedule schedule);
}

class MemoryMealScheduleStore implements MealScheduleStore {
  MemoryMealScheduleStore([this.schedule = const MealSchedule()]);

  MealSchedule schedule;

  @override
  Future<MealSchedule> load() async => schedule;

  @override
  Future<void> save(MealSchedule s) async => schedule = s;
}

/// Table `app_settings`, une ligne JSON par compte.
class SqliteMealScheduleStore implements MealScheduleStore {
  SqliteMealScheduleStore(this._appDb, {this.ownerId});

  final AppDatabase _appDb;
  final int? ownerId;

  String get _key => ownerId == null ? 'meals' : 'meals:$ownerId';

  @override
  Future<MealSchedule> load() async {
    final rows = await (await _appDb.database)
        .query('app_settings', where: 'key = ?', whereArgs: [_key]);
    final raw = rows.firstOrNull?['value'] as String?;
    if (raw == null) return const MealSchedule();
    try {
      return MealSchedule.fromJson(jsonDecode(raw));
    } on FormatException {
      return const MealSchedule();
    }
  }

  @override
  Future<void> save(MealSchedule schedule) async {
    await (await _appDb.database).insert(
      'app_settings',
      {'key': _key, 'value': jsonEncode(schedule.toJson())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
