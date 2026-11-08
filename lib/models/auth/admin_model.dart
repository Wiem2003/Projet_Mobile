import 'package:flutter/foundation.dart';

import 'app_user.dart';

/// Filtre de la liste des comptes.
enum UserFilter {
  all('Tous'),
  admins('Admins'),
  users('Utilisateurs'),
  disabled('Désactivés');

  const UserFilter(this.label);

  final String label;

  bool matches(AppUser u) => switch (this) {
        all => true,
        admins => u.isAdmin,
        users => !u.isAdmin,
        disabled => !u.active,
      };
}

/// État de l'écran Administration (réservé au rôle admin).
class AdminModel extends ChangeNotifier {
  List<UserSummary> _users = const [];
  AdminStats _stats = const AdminStats();
  UserFilter _filter = UserFilter.all;
  String _query = '';
  bool _loading = true;
  String? _error;

  List<UserSummary> get all => _users;
  AdminStats get stats => _stats;
  UserFilter get filter => _filter;
  String get query => _query;
  bool get loading => _loading;
  String? get error => _error;

  /// Comptes affichés : filtre + recherche (nom ou e-mail).
  List<UserSummary> get visible {
    final q = _query.trim().toLowerCase();
    return [
      for (final s in _users)
        if (_filter.matches(s.user) &&
            (q.isEmpty ||
                s.user.name.toLowerCase().contains(q) ||
                s.user.email.contains(q)))
          s,
    ];
  }

  void setData(List<UserSummary> users, AdminStats stats) {
    _users = List.unmodifiable(users);
    _stats = stats;
    _loading = false;
    _error = null;
    notifyListeners();
  }

  void setError(String message) {
    _error = message;
    _loading = false;
    notifyListeners();
  }

  void setFilter(UserFilter f) {
    _filter = f;
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }
}
