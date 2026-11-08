import 'package:flutter/foundation.dart';

import 'app_user.dart';

enum AuthStatus {
  /// Au lancement, pendant la lecture de la session enregistrée.
  unknown,
  signedOut,
  signedIn,
}

/// État de la connexion, observé par la View (écrans Sign in / Sign up,
/// porte d'entrée de l'app, profil).
class AuthModel extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unknown;
  AppUser? _user;
  bool _busy = false;
  String? _error;

  AuthStatus get status => _status;

  /// Compte connecté (`null` si déconnecté).
  AppUser? get user => _user;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get busy => _busy;

  /// Dernière erreur à afficher (identifiants incorrects, e-mail pris...).
  String? get error => _error;

  void setBusy(bool v) {
    _busy = v;
    if (v) _error = null;
    notifyListeners();
  }

  void signedIn(AppUser user) {
    _user = user;
    _status = AuthStatus.signedIn;
    _busy = false;
    _error = null;
    notifyListeners();
  }

  void signedOut() {
    _user = null;
    _status = AuthStatus.signedOut;
    _busy = false;
    notifyListeners();
  }

  void setError(String message) {
    _error = message;
    _busy = false;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
