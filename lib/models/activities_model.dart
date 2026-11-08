import 'package:flutter/foundation.dart';

import '../core/pets/pet_directory.dart';
import 'activity.dart';
import 'activity_stats.dart';

/// Model du module Activités : activités chargées depuis SQLite, filtres
/// (animal, type, période) et calculs automatiques.
///
/// Observé par les Views ; modifié uniquement par l'`ActivitiesController`.
class ActivitiesModel extends ChangeNotifier {
  ActivitiesModel({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  bool _loading = true;
  String? _error;
  List<Activity> _activities = const [];
  List<PetSummary> _pets = const [];
  int? _petFilter;
  ActivityType? _typeFilter;
  ActivityPeriod _period = ActivityPeriod.month;

  DateTime get now => _clock();
  bool get loading => _loading;
  String? get error => _error;
  bool get isEmpty => _activities.isEmpty;

  /// Toutes les activités, de la plus récente à la plus ancienne.
  List<Activity> get all => _activities;

  /// Records battus par la dernière activité enregistrée (par animal).
  Map<int, List<String>> get lastRecords => _lastRecords;
  Map<int, List<String>> _lastRecords = const {};

  void setLastRecords(int petId, List<String> records) {
    _lastRecords = {..._lastRecords, petId: records};
    notifyListeners();
  }
  List<PetSummary> get pets => _pets;
  int? get petFilter => _petFilter;
  ActivityType? get typeFilter => _typeFilter;
  ActivityPeriod get period => _period;

  PetSummary? petOf(int? id) {
    for (final p in _pets) {
      if (p.id == id) return p;
    }
    return null;
  }

  Activity? byId(int? id) {
    for (final a in _activities) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Activités de l'animal et du type choisis (toutes périodes).
  List<Activity> get _filtered => _activities
      .where((a) =>
          (_petFilter == null || a.petId == _petFilter) &&
          (_typeFilter == null || a.type == _typeFilter))
      .toList();

  /// Historique de la période choisie.
  List<Activity> get visible {
    final n = now;
    return _filtered.where((a) => _period.contains(a.date, n)).toList();
  }

  ActivityStats get stats =>
      ActivityStats.compute(_filtered, now: now, period: _period);

  // ------------------------------------------------- Mises à jour (Controller)

  void setActivities(List<Activity> activities) {
    _activities = [...activities]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : (b.id ?? 0).compareTo(a.id ?? 0);
      });
    _loading = false;
    _error = null;
    notifyListeners();
  }

  void setPets(List<PetSummary> pets) {
    _pets = pets;
    notifyListeners();
  }

  void setError(String message) {
    _error = message;
    _loading = false;
    notifyListeners();
  }

  void setPetFilter(int? petId) {
    _petFilter = petId;
    notifyListeners();
  }

  void setTypeFilter(ActivityType? type) {
    _typeFilter = type;
    notifyListeners();
  }

  void setPeriod(ActivityPeriod period) {
    _period = period;
    notifyListeners();
  }
}
