import 'package:flutter/foundation.dart';

import 'pet.dart';

/// Model du module Animaux : liste des animaux et recherche.
///
/// Observé par les Views ; modifié uniquement par le `PetsController`.
class PetsModel extends ChangeNotifier {
  PetsModel({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  bool _loading = true;
  String? _error;
  List<Pet> _pets = const [];
  String _query = '';

  DateTime get now => _clock();
  bool get loading => _loading;
  String? get error => _error;
  bool get isEmpty => _pets.isEmpty;

  /// Tous les animaux, triés par nom.
  List<Pet> get all => _pets;
  String get query => _query;

  Pet? byId(int? id) {
    for (final p in _pets) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Animaux correspondant à la recherche (nom, race, espèce, couleur, puce).
  List<Pet> get visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _pets;
    return _pets
        .where((p) => [
              p.name,
              p.breed,
              p.species.label,
              p.color,
              p.identification,
            ].any((v) => v != null && v.toLowerCase().contains(q)))
        .toList();
  }

  /// Nombre d'animaux par espèce (sous-titre de l'écran).
  Map<Species, int> get countBySpecies => {
        for (final s in Species.values)
          if (_pets.any((p) => p.species == s))
            s: _pets.where((p) => p.species == s).length,
      };

  // ------------------------------------------------- Mises à jour (Controller)

  void setPets(List<Pet> pets) {
    _pets = pets;
    _loading = false;
    _error = null;
    notifyListeners();
  }

  void setError(String message) {
    _error = message;
    _loading = false;
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }
}
