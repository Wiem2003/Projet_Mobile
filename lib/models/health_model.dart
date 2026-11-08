import 'package:flutter/foundation.dart';

import '../core/pets/pet_directory.dart';
import 'health_record.dart';
import 'health_stats.dart';

/// Model du module Santé : dossiers chargés depuis SQLite, filtres (animal,
/// type, période) et calculs automatiques.
///
/// Observé par les Views ; modifié uniquement par le `HealthController`.
class HealthModel extends ChangeNotifier {
  HealthModel({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  bool _loading = true;
  String? _error;
  List<HealthRecord> _records = const [];
  List<PetSummary> _pets = const [];
  int? _petFilter;
  HealthType? _typeFilter;
  HealthPeriod _period = HealthPeriod.year;

  DateTime get now => _clock();
  bool get loading => _loading;
  String? get error => _error;
  bool get isEmpty => _records.isEmpty;

  /// Tous les dossiers, du plus récent au plus ancien.
  List<HealthRecord> get all => _records;
  List<PetSummary> get pets => _pets;
  int? get petFilter => _petFilter;
  HealthType? get typeFilter => _typeFilter;
  HealthPeriod get period => _period;

  PetSummary? petOf(int? id) {
    for (final p in _pets) {
      if (p.id == id) return p;
    }
    return null;
  }

  HealthRecord? byId(int? id) {
    for (final r in _records) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Animal dont on suit le poids : celui du filtre, ou le seul animal.
  int? get weightPetId =>
      _petFilter ?? (_pets.length == 1 ? _pets.first.id : null);

  List<HealthRecord> _matching({bool withType = true}) => _records
      .where((r) =>
          (_petFilter == null || r.petId == _petFilter) &&
          (!withType || _typeFilter == null || r.type == _typeFilter))
      .toList();

  /// Historique de la période choisie.
  List<HealthRecord> get history {
    final n = now;
    return _matching().where((r) => _period.contains(r.date, n)).toList();
  }

  /// Calculs de la période. Le poids suit toutes les pesées de l'animal,
  /// quel que soit le filtre de type.
  HealthStats get stats {
    final base = HealthStats.compute(_matching(),
        now: now, period: _period, singlePet: false);
    final pet = weightPetId;
    if (pet == null) return base;
    final weighings = HealthStats.compute(_records.where((r) => r.petId == pet),
        now: now, period: _period);
    return HealthStats(
      period: base.period,
      recordCount: base.recordCount,
      consultations: base.consultations,
      spending: base.spending,
      spendingByType: base.spendingByType,
      weights: weighings.weights,
    );
  }

  /// Prochaines échéances (aujourd'hui et après), la plus proche d'abord.
  List<HealthRecord> get upcoming {
    final n = now;
    final today = DateTime(n.year, n.month, n.day);
    return _matching(withType: false)
        .where((r) => r.nextDue != null && !r.nextDue!.isBefore(today))
        .toList()
      ..sort((a, b) => a.nextDue!.compareTo(b.nextDue!));
  }

  /// Dernière pesée d'un animal (pour mettre à jour sa fiche).
  HealthRecord? lastWeighing(int petId) {
    for (final r in _records) {
      if (r.petId == petId && r.weightKg != null) return r;
    }
    return null;
  }

  // ------------------------------------------------- Mises à jour (Controller)

  void setRecords(List<HealthRecord> records) {
    _records = [...records]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : (b.id ?? 0).compareTo(a.id ?? 0);
      });
    _loading = false;
    _error = null;
    notifyListeners();
  }

  void setPets(List<PetSummary> pets) {
    _pets = pets;
    if (_petFilter != null && !pets.any((p) => p.id == _petFilter)) {
      _petFilter = null;
    }
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

  void setTypeFilter(HealthType? type) {
    _typeFilter = type;
    notifyListeners();
  }

  void setPeriod(HealthPeriod period) {
    _period = period;
    notifyListeners();
  }
}
