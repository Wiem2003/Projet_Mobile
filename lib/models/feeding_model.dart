import 'package:flutter/foundation.dart';

import '../core/pets/pet_directory.dart';
import 'feeding_record.dart';
import 'feeding_stats.dart';

/// Model du module Alimentation : repas chargés depuis SQLite, filtres
/// (animal, mois) et calculs automatiques.
///
/// Observé par les Views ; modifié uniquement par le `FeedingController`.
class FeedingModel extends ChangeNotifier {
  FeedingModel({DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    final n = now;
    _month = DateTime(n.year, n.month);
  }

  final DateTime Function() _clock;

  bool _loading = true;
  String? _error;
  List<FeedingRecord> _records = const [];
  List<PetSummary> _pets = const [];
  int? _petFilter;
  late DateTime _month;

  DateTime get now => _clock();
  bool get loading => _loading;
  String? get error => _error;
  bool get isEmpty => _records.isEmpty;

  /// Tous les repas, du plus récent au plus ancien.
  List<FeedingRecord> get all => _records;
  List<PetSummary> get pets => _pets;
  int? get petFilter => _petFilter;

  /// Mois affiché (premier jour du mois).
  DateTime get month => _month;

  bool get isCurrentMonth {
    final n = now;
    return _month.year == n.year && _month.month == n.month;
  }

  PetSummary? petOf(int? id) {
    for (final p in _pets) {
      if (p.id == id) return p;
    }
    return null;
  }

  FeedingRecord? byId(int? id) {
    for (final r in _records) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Dernier repas saisi pour un animal (bouton « Reprendre le dernier »).
  FeedingRecord? lastFor(int? petId) {
    for (final r in _records) {
      if (r.petId == petId) return r;
    }
    return null;
  }

  List<FeedingRecord> get _forPet => _petFilter == null
      ? _records
      : _records.where((r) => r.petId == _petFilter).toList();

  /// Historique du mois affiché.
  List<FeedingRecord> get history => _forPet
      .where((r) => r.date.year == _month.year && r.date.month == _month.month)
      .toList();

  FeedingStats get stats =>
      FeedingStats.compute(_forPet, month: _month, now: now);

  // ------------------------------------------------- Mises à jour (Controller)

  void setRecords(List<FeedingRecord> records) {
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

  void setMonth(DateTime month) {
    _month = DateTime(month.year, month.month);
    notifyListeners();
  }
}
